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
     */
    string public constant SOCIALS = "Telegram: t.me/InternetRobinhoodLottery | GitHub: https://github.com/math-crypt/lottery-robinhood";

    IERC20 public immutable stakingToken;

    mapping(address => uint256) public stakedBalance;
    uint256 public totalStaked;

    // Real Yield in native ETH (MasterChef/Synthetix distribution)
    uint256 public accEthPerShare;
    mapping(address => uint256) public rewardDebt;
    mapping(address => uint256) public pendingEth;

    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event YieldDistributed(uint256 amount);
    event YieldClaimed(address indexed user, uint256 amount);

    constructor(address _stakingToken) {
        stakingToken = IERC20(_stakingToken);
    }

    /**
     * @notice Receives ETH from the Uniswap V4 Hook (30% of hourly pot) and distributes to stakers.
     */
    receive() external payable {
        _distributeYield(msg.value);
    }

    function distributeYield() external payable {
        _distributeYield(msg.value);
    }

    function _distributeYield(uint256 amount) internal {
        if (amount > 0 && totalStaked > 0) {
            accEthPerShare += (amount * 1e18) / totalStaked;
            emit YieldDistributed(amount);
        }
    }

    /**
     * @notice Calculates pending native ETH yield for a staker.
     */
    function pendingYield(address user) public view returns (uint256) {
        uint256 accumulated = (stakedBalance[user] * accEthPerShare) / 1e18;
        uint256 delta = accumulated > rewardDebt[user] ? (accumulated - rewardDebt[user]) : 0;
        return pendingEth[user] + delta;
    }

    function _updateYield(address user) internal {
        if (stakedBalance[user] > 0) {
            uint256 accumulated = (stakedBalance[user] * accEthPerShare) / 1e18;
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
        rewardDebt[msg.sender] = (stakedBalance[msg.sender] * accEthPerShare) / 1e18;

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
        rewardDebt[msg.sender] = (stakedBalance[msg.sender] * accEthPerShare) / 1e18;

        stakingToken.safeTransferFrom(msg.sender, address(this), amount);

        emit Staked(msg.sender, amount);
    }

    /**
     * @notice Unstake tokens from the contract.
     * @param amount The amount of tokens to unstake.
     */
    function unstake(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        require(stakedBalance[msg.sender] >= amount, "Insufficient staked balance");

        _updateYield(msg.sender);

        stakedBalance[msg.sender] -= amount;
        totalStaked -= amount;

        rewardDebt[msg.sender] = (stakedBalance[msg.sender] * accEthPerShare) / 1e18;

        stakingToken.safeTransfer(msg.sender, amount);

        emit Unstaked(msg.sender, amount);
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
