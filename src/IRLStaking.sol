// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title IRL Staking (Real Yield Sanctuary)
 * @dev Staking contract for the Internet Robin Lottery token.
 * Features:
 * - 30% of all hourly swap redistribution pots stream directly into native ETH Real Yield!
 * - Bonus daily lottery chances in the V4 Hook.
 * - Score multiplier on hourly volume reward distributions.
 * - No lock penalty, instant unstake anytime.
 */
contract IRLStaking is ReentrancyGuard {
    using SafeERC20 for IERC20;

    /**
     * @notice PROJECT INFO & SOCIALS
     * 
     *      (
     *       \
     *        )
     * ##-------->  $IRL Lottery
     *        )
     *       /
     *      (
     * 
     * We steal from the whales to give back to the community!
     * 
     * Telegram: t.me/InternetRobinhoodLottery
     * GitHub: https://github.com/math-crypt/lottery-robinhood
     * Website: https://irlprotocol.xyz
     * X (Twitter): https://x.com/IRL_Protocol
     */
    string public constant SOCIALS = "Website: https://irlprotocol.xyz | X: https://x.com/IRL_Protocol | Telegram: t.me/InternetRobinhoodLottery | GitHub: https://github.com/math-crypt/lottery-robinhood";

    uint256 public constant STAKE_COOLDOWN = 24 hours;
    uint256 public constant MIN_ELIGIBLE_STAKE = 1_000_000 ether;  // 0.1% of 1B supply minimum to qualify for 30% Real Yield
    uint256 public constant MAX_ELIGIBLE_STAKE = 20_000_000 ether; // 2.0% of 1B supply maximum cap per wallet

    IERC20 public immutable stakingToken;
    address public hookContract;
    address public sherwoodGuildVault;

    mapping(address => uint256) public stakedBalance;
    mapping(address => uint256) public eligibleStake;
    mapping(address => uint256) public lastStakedTimestamp;
    mapping(address => uint256) public unstakeUnlockTime;
    uint256 public totalStaked;
    uint256 public totalEligibleStaked;

    // Real Yield in native ETH (MasterChef/Synthetix distribution across [0.1%, 2.0%] eligible tiers)
    uint256 public accEthPerShare;
    uint256 public unallocatedYield;
    mapping(address => uint256) public rewardDebt;
    mapping(address => uint256) public pendingEth;

    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event YieldDistributed(uint256 amount);
    event YieldClaimed(address indexed user, uint256 amount);
    event HookRegistered(address indexed hook);
    event SherwoodGuildRegistered(address indexed guild);
    event InstantTicketsClaimLockApplied(address indexed user, uint256 unlockTime);

    constructor(address _stakingToken) {
        stakingToken = IERC20(_stakingToken);
    }

    /**
     * @notice One-time registration of the Uniswap V4 Hook contract.
     */
    function registerHook(address _hook) external {
        require(hookContract == address(0) && _hook != address(0), "Hook already registered");
        hookContract = _hook;
        emit HookRegistered(_hook);
    }

    /**
     * @notice Registration of the Sherwood Co-Staking Guild Vault for small holders (< 0.1% supply).
     */
    function registerSherwoodGuild(address _guild) external {
        require(
            (sherwoodGuildVault == address(0) || msg.sender == hookContract) && _guild != address(0),
            "Guild already registered"
        );
        sherwoodGuildVault = _guild;
        emit SherwoodGuildRegistered(_guild);
    }

    function _isSherwoodGuild(address user) internal view returns (bool) {
        if (user == address(0)) return false;
        if (user == sherwoodGuildVault) return true;
        if (user.code.length > 0) {
            (bool ok, bytes memory data) = user.staticcall(abi.encodeWithSignature("mainStaking()"));
            if (ok && data.length >= 32 && abi.decode(data, (address)) == address(this)) {
                return true;
            }
        }
        return false;
    }

    /**
     * @notice Called by the Uniswap V4 Hook when a staker claims their free staking tickets.
     * - For the Sherwood Co-Staking Guild pool (`_isSherwoodGuild(user)`), claiming tickets NEVER locks the pooled supply for 24h.
     * - If an individual user has ALREADY staked for >= 24h (`block.timestamp >= lastStakedTimestamp[user] + 24h`),
     *   they claim their tickets with ZERO unstake lock (remain free to unstake anytime).
     * - If an individual user claims BEFORE 24h of staking (`block.timestamp < lastStakedTimestamp[user] + 24h`),
     *   they receive their tickets immediately and their stake is locked for 24h (`unstakeUnlockTime`).
     */
    function onStakingTicketsClaimed(address user) external {
        if (hookContract == address(0)) {
            (bool ok, bytes memory data) = msg.sender.staticcall(abi.encodeWithSignature("stakingContract()"));
            require(ok && data.length >= 32 && abi.decode(data, (address)) == address(this), "Only IRL Hook");
            hookContract = msg.sender;
            emit HookRegistered(msg.sender);
        } else {
            require(msg.sender == hookContract, "Only IRL Hook");
        }

        if (_isSherwoodGuild(user)) {
            if (sherwoodGuildVault == address(0)) {
                sherwoodGuildVault = user;
                emit SherwoodGuildRegistered(user);
            }
            // Small-holder Co-Staking Guild pool never locks its supply for 24h when claiming tickets
            return;
        }

        if (block.timestamp < lastStakedTimestamp[user] + STAKE_COOLDOWN) {
            unstakeUnlockTime[user] = block.timestamp + STAKE_COOLDOWN;
            emit InstantTicketsClaimLockApplied(user, unstakeUnlockTime[user]);
        } else {
            lastStakedTimestamp[user] = block.timestamp;
        }
    }

    /**
     * @dev Computes a staker's effective yield weight bounded strictly between 0.1% (1M IRL) and 2.0% (20M IRL).
     */
    function _computeEligibleWeight(uint256 balance) internal pure returns (uint256) {
        if (balance < MIN_ELIGIBLE_STAKE) {
            return 0;
        }
        if (balance > MAX_ELIGIBLE_STAKE) {
            return MAX_ELIGIBLE_STAKE;
        }
        return balance;
    }

    /**
     * @notice Receives ETH from the Uniswap V4 Hook (30% of hourly pot) and distributes to eligible stakers (0.1% to 2.0%).
     */
    receive() external payable {
        _distributeYield(msg.value);
    }

    function distributeYield() external payable {
        _distributeYield(msg.value);
    }

    function _distributeYield(uint256 amount) internal {
        if (amount > 0) {
            if (totalEligibleStaked > 0) {
                uint256 totalToDistribute = amount + unallocatedYield;
                unallocatedYield = 0;
                accEthPerShare += (totalToDistribute * 1e18) / totalEligibleStaked;
                emit YieldDistributed(totalToDistribute);
            } else {
                // Buffer ETH if no eligible staker (>= 0.1%) is active yet so zero yield is ever orphaned
                unallocatedYield += amount;
            }
        }
    }

    /**
     * @notice Calculates pending native ETH yield for a staker based on their [0.1%, 2.0%] eligible tier weight.
     */
    function pendingYield(address user) public view returns (uint256) {
        uint256 accumulated = (eligibleStake[user] * accEthPerShare) / 1e18;
        uint256 delta = accumulated > rewardDebt[user] ? (accumulated - rewardDebt[user]) : 0;
        return pendingEth[user] + delta;
    }

    function _updateYield(address user) internal {
        if (eligibleStake[user] > 0) {
            uint256 accumulated = (eligibleStake[user] * accEthPerShare) / 1e18;
            if (accumulated > rewardDebt[user]) {
                pendingEth[user] += accumulated - rewardDebt[user];
            }
        }
    }

    /**
     * @notice Claims accumulated native ETH yield.
     */
    function claimYield() external nonReentrant returns (uint256 amount) {
        _updateYield(msg.sender);
        amount = pendingEth[msg.sender];
        require(amount > 0, "No ETH yield to claim");
        pendingEth[msg.sender] = 0;
        rewardDebt[msg.sender] = (eligibleStake[msg.sender] * accEthPerShare) / 1e18;

        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "ETH transfer failed");

        emit YieldClaimed(msg.sender, amount);
    }

    /**
     * @notice Stake tokens into the contract.
     * @param amount The amount of tokens to stake.
     */
    function stake(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be greater than 0");

        _updateYield(msg.sender);

        stakedBalance[msg.sender] += amount;
        totalStaked += amount;

        uint256 oldWeight = eligibleStake[msg.sender];
        uint256 newWeight = _computeEligibleWeight(stakedBalance[msg.sender]);
        eligibleStake[msg.sender] = newWeight;
        totalEligibleStaked = totalEligibleStaked - oldWeight + newWeight;

        lastStakedTimestamp[msg.sender] = block.timestamp;
        rewardDebt[msg.sender] = (newWeight * accEthPerShare) / 1e18;

        // If yield was buffered while totalEligibleStaked was 0, distribute it now to active eligible stakers
        if (unallocatedYield > 0 && totalEligibleStaked > 0) {
            uint256 buffered = unallocatedYield;
            unallocatedYield = 0;
            accEthPerShare += (buffered * 1e18) / totalEligibleStaked;
            emit YieldDistributed(buffered);
        }

        stakingToken.safeTransferFrom(msg.sender, address(this), amount);

        emit Staked(msg.sender, amount);
    }

    /**
     * @notice Unstake tokens from the contract.
     * Users can unstake freely at any time unless they claimed free staking tickets before completing 24h of staking.
     * @param amount The amount of tokens to unstake.
     */
    function unstake(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        require(stakedBalance[msg.sender] >= amount, "Insufficient staked balance");
        require(
            block.timestamp >= unstakeUnlockTime[msg.sender],
            "Stake cooldown active (24h)"
        );

        _updateYield(msg.sender);

        stakedBalance[msg.sender] -= amount;
        totalStaked -= amount;

        uint256 oldWeight = eligibleStake[msg.sender];
        uint256 newWeight = _computeEligibleWeight(stakedBalance[msg.sender]);
        eligibleStake[msg.sender] = newWeight;
        totalEligibleStaked = totalEligibleStaked - oldWeight + newWeight;

        rewardDebt[msg.sender] = (newWeight * accEthPerShare) / 1e18;

        stakingToken.safeTransfer(msg.sender, amount);

        emit Unstaked(msg.sender, amount);
    }

    /**
     * @notice Returns whether the user has staked for at least 24 hours (allowing zero-lock ticket claims).
     */
    function isCooldownMet(address user) external view returns (bool) {
        return stakedBalance[user] > 0 && block.timestamp >= lastStakedTimestamp[user] + STAKE_COOLDOWN;
    }

    /**
     * @notice Returns whether the user's stake is currently unlocked for withdrawal.
     */
    function isUnstakeUnlocked(address user) external view returns (bool) {
        return block.timestamp >= unstakeUnlockTime[user];
    }

    /**
     * @notice Helper to get the staked amount of a user.
     * @param user The address of the user.
     * @return The amount staked by the user.
     */
    function getStakedAmount(address user) external view returns (uint256) {
        return stakedBalance[user];
    }
}
