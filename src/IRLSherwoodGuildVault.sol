// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

interface IIRLStaking {
    function MIN_ELIGIBLE_STAKE() external view returns (uint256);
    function MAX_ELIGIBLE_STAKE() external view returns (uint256);
    function stakedBalance(address user) external view returns (uint256);
    function eligibleStake(address user) external view returns (uint256);
    function pendingYield(address user) external view returns (uint256);
    function isCooldownMet(address user) external view returns (bool);
    function isUnstakeUnlocked(address user) external view returns (bool);
    function unstakeUnlockTime(address user) external view returns (uint256);
    function stake(uint256 amount) external;
    function unstake(uint256 amount) external;
    function claimYield() external returns (uint256 amount);
}

interface IIRLHookGuild {
    function claimStakingTickets() external;
    function claimUnclaimedRewards() external;
    function unclaimedRewards(address user) external view returns (uint256);
    function lastLotteryDay() external view returns (uint256);
    function lastLotteryWeek() external view returns (uint256);
    function vrfRequestType(uint256 requestId) external view returns (uint8);
    function randomnessRouter() external view returns (address);
    function nftTicket() external view returns (address);
}

interface IIRLTicketNFTGuild {
    function totalTicketsMinted() external view returns (uint256);
    function ownerOf(uint256 tokenId) external view returns (address);
    function balanceOf(address owner) external view returns (uint256);
}

interface IOpenVRFGuildView {
    function nextRequestId() external view returns (uint256);
}

/**
 * @title IRLSherwoodGuildVault (Co-Staking & Shared Lottery Pool for Small Holders)
 * @notice Aggregates $IRL from small holders (< 1,000,000 $IRL) with ZERO minimum deposit
 *         into the official IRLStaking contract so small holders collectively:
 *         1. Unlock the [0.1%, 2.0%] (1M - 20M $IRL) 30% native ETH Real Yield stream (`accEthPerShare`).
 *         2. Claim free staking NFT Lottery Tickets directly for the Guild contract (`claimGuildStakingTickets`).
 *         3. Share all Daily & Weekly Lottery Jackpots won by Guild tickets among active Guild stakers who:
 *            - Are STILL staking in the Guild at the exact moment of the lottery draw (`stakedBalance[user] > 0`), AND
 *            - Have staked for at least 8 HOURS (`>= 8 hours`) on the day of the valid ticket for a Daily Lottery win, OR
 *            - Have staked for at least 1 DAY (`>= 24 hours`) on the week of the valid ticket for a Weekly (Sunday Mega-Jackpot) win.
 * @dev 100% Non-Custodial: The owner has zero ability to withdraw user $IRL or user ETH rewards.
 */
contract IRLSherwoodGuildVault is ReentrancyGuard, Ownable, IERC721Receiver {
    using SafeERC20 for IERC20;

    uint256 public constant PRECISION = 1e18;
    uint256 public constant MAX_GUILD_CAPACITY = 20_000_000 ether; // Matches IRLStaking 2.0% max eligible tier
    uint256 public constant MIN_REAL_YIELD_THRESHOLD = 1_000_000 ether; // Matches IRLStaking 0.1% min eligible tier

    // Lottery Jackpot Sharing Eligibility Durations
    uint256 public constant DAILY_LOTTERY_MIN_STAKE_TIME = 8 hours; // Must stake >= 8h on the day & still stake at draw
    uint256 public constant WEEKLY_LOTTERY_MIN_STAKE_TIME = 1 days; // Must stake >= 1d (24h) on the week & still stake at draw

    IERC20 public immutable stakingToken;
    IIRLStaking public immutable mainStaking;
    address public hookContract;

    uint256 public totalGuildStaked;
    uint256 public accEthPerShare;
    uint256 public unallocatedEth;
    uint256 public totalEthHarvested;
    uint256 public totalLotteryEthWon;

    // User staking balances & Hourly Real Yield accounting
    mapping(address => uint256) public stakedBalance;
    mapping(address => uint256) public rewardDebt;
    mapping(address => uint256) public pendingEth;
    mapping(address => uint256) public pendingLotteryEth;

    // User staking duration tracking for the 8h (Daily) / 1d (Weekly) Lottery Jackpot eligibility
    mapping(address => uint256) public stakedSince;
    mapping(address => uint256) public recentTopUpAmount;
    mapping(address => uint256) public recentTopUpTimestamp;

    // Active Guild stakers set (O(1) add & swap-and-pop removal when balance reaches 0)
    address[] public guildStakers;
    mapping(address => uint256) private _stakerIndexPlusOne;

    // Guild NFT Lottery Tickets claimed for this contract
    uint256[] public guildTicketIds;
    mapping(uint256 => bool) public isGuildTicketRecorded;
    uint256 public lastKnownHookWeek;

    struct PendingLotteryJackpot {
        uint256 amount;
        uint256 drawTimestamp;
        bool isWeekly; // false = Daily Draw (>= 8h required), true = Weekly Sunday Draw (>= 1d required)
        bool settled;
    }

    PendingLotteryJackpot[] public pendingLotteryJackpots;
    uint256 public nextUnsettledJackpotIndex;

    bool private _inMainHarvest;
    bool private _inHookUnclaimedPull;

    event GuildStaked(address indexed user, uint256 amount, uint256 newTotalGuildStaked);
    event GuildUnstaked(address indexed user, uint256 amount, uint256 newTotalGuildStaked);
    event GuildYieldHarvested(uint256 amount);
    event GuildBonusEthReceived(address indexed sender, uint256 amount);
    event GuildYieldClaimed(address indexed user, uint256 totalAmount, uint256 lotteryPortion);
    event GuildTicketsClaimed(address indexed caller, uint256 totalGuildTickets, uint256 timestamp);
    event GuildLotteryJackpotRecorded(uint256 indexed jackpotIndex, uint256 amount, bool isWeekly, uint256 drawTimestamp);
    event GuildLotteryJackpotSettled(uint256 indexed jackpotIndex, uint256 amount, bool isWeekly, uint256 eligibleStakersCount, uint256 totalEligibleWeight);

    constructor(address _stakingToken, address _mainStaking, address _hookContract) Ownable(msg.sender) {
        require(_stakingToken != address(0) && _mainStaking != address(0), "Zero address");
        stakingToken = IERC20(_stakingToken);
        mainStaking = IIRLStaking(_mainStaking);
        hookContract = _hookContract;

        if (_hookContract != address(0) && _hookContract.code.length > 0) {
            try IIRLHookGuild(_hookContract).lastLotteryWeek() returns (uint256 w) {
                lastKnownHookWeek = w;
            } catch {}
        }

        // Pre-approve main IRLStaking contract for seamless pooling
        IERC20(_stakingToken).forceApprove(_mainStaking, type(uint256).max);
    }

    /**
     * @notice Receives native ETH from:
     *         1. `IRLStaking.claimYield()` (30% Hourly Real Yield stream)
     *         2. `IRLUniswapV4Hook._fulfillRandomness()` when a Guild Ticket wins the Daily or Weekly Lottery!
     *            (Kept ultra gas-light < 30,000 gas so OpenVRF's 150k callbackGasLimit never reverts).
     *         3. Direct community/treasury bonus ETH drops.
     */
    receive() external payable {
        if (_inMainHarvest || _inHookUnclaimedPull) {
            return;
        }
        if (msg.value == 0) return;

        if (msg.sender == hookContract) {
            bool isWeekly = _detectIfWeeklyDraw();
            uint256 idx = pendingLotteryJackpots.length;
            pendingLotteryJackpots.push(
                PendingLotteryJackpot({
                    amount: msg.value,
                    drawTimestamp: block.timestamp,
                    isWeekly: isWeekly,
                    settled: false
                })
            );
            totalLotteryEthWon += msg.value;
            emit GuildLotteryJackpotRecorded(idx, msg.value, isWeekly, block.timestamp);
        } else {
            _distributeEth(msg.value);
            emit GuildBonusEthReceived(msg.sender, msg.value);
        }
    }

    /**
     * @notice Explicit callable entry point to record a Guild Lottery Win (e.g. in tests or manual routing)
     *         with explicit Daily (`isWeekly = false`, >= 8h) or Weekly (`isWeekly = true`, >= 1d) rule.
     */
    function recordLotteryWin(bool isWeekly) external payable nonReentrant {
        require(msg.value > 0, "Zero prize");
        uint256 idx = pendingLotteryJackpots.length;
        pendingLotteryJackpots.push(
            PendingLotteryJackpot({
                amount: msg.value,
                drawTimestamp: block.timestamp,
                isWeekly: isWeekly,
                settled: false
            })
        );
        totalLotteryEthWon += msg.value;
        emit GuildLotteryJackpotRecorded(idx, msg.value, isWeekly, block.timestamp);
        _settlePendingLotteryJackpots();
    }

    /**
     * @notice Explicit payable entry point to inject bonus ETH yield into the Guild.
     */
    function distributeBonusYield() external payable nonReentrant {
        require(msg.value > 0, "Zero ETH");
        _settlePendingLotteryJackpots();
        _distributeEth(msg.value);
        emit GuildBonusEthReceived(msg.sender, msg.value);
    }

    /**
     * @dev Detects whether a lottery payout arriving from `hookContract` corresponds to a
     *      Daily Lottery Draw (`false` -> 8h min stake) or a Weekly Sunday Mega-Jackpot Draw (`true` -> 1d min stake).
     */
    function _detectIfWeeklyDraw() internal returns (bool isWeekly) {
        if (hookContract == address(0) || hookContract.code.length == 0) {
            return false;
        }
        // 1. Check OpenVRF most recent fulfilled request type on Hook if available
        try IIRLHookGuild(hookContract).randomnessRouter() returns (address router) {
            if (router != address(0) && router.code.length > 0) {
                try IOpenVRFGuildView(router).nextRequestId() returns (uint256 nextId) {
                    if (nextId > 1) {
                        uint8 reqType = IIRLHookGuild(hookContract).vrfRequestType(nextId - 1);
                        if (reqType == 2) {
                            try IIRLHookGuild(hookContract).lastLotteryWeek() returns (uint256 w) {
                                lastKnownHookWeek = w;
                            } catch {}
                            return true;
                        }
                        if (reqType == 1) {
                            return false;
                        }
                    }
                } catch {}
            }
        } catch {}

        // 2. Fallback: Check if Hook's lastLotteryWeek advanced since our last observation
        try IIRLHookGuild(hookContract).lastLotteryWeek() returns (uint256 currentHookWeek) {
            if (lastKnownHookWeek > 0 && currentHookWeek > lastKnownHookWeek) {
                lastKnownHookWeek = currentHookWeek;
                return true;
            }
            lastKnownHookWeek = currentHookWeek;
        } catch {}

        return false;
    }

    /**
     * @notice Computes a user's eligible $IRL stake for a Lottery Draw at `drawTimestamp`:
     *         - User MUST still be staking at `drawTimestamp` (`stakedBalance[user] > 0`).
     *         - For Daily Lottery (`isWeeklyDraw == false`): stake must have been held `>= 8 hours`.
     *         - For Weekly Lottery (`isWeeklyDraw == true`): stake must have been held `>= 1 day (24 hours)`.
     */
    function getEligibleLotteryStakeAt(
        address user,
        uint256 drawTimestamp,
        bool isWeeklyDraw
    ) public view returns (uint256) {
        uint256 totalBal = stakedBalance[user];
        if (totalBal == 0) return 0;

        uint256 minDuration = isWeeklyDraw ? WEEKLY_LOTTERY_MIN_STAKE_TIME : DAILY_LOTTERY_MIN_STAKE_TIME;
        uint256 topUp = recentTopUpAmount[user] <= totalBal ? recentTopUpAmount[user] : totalBal;
        uint256 baseStake = totalBal - topUp;

        uint256 eligible = 0;
        if (baseStake > 0 && stakedSince[user] > 0 && drawTimestamp >= stakedSince[user] + minDuration) {
            eligible += baseStake;
        }
        if (topUp > 0 && recentTopUpTimestamp[user] > 0 && drawTimestamp >= recentTopUpTimestamp[user] + minDuration) {
            eligible += topUp;
        }
        return eligible;
    }

    /**
     * @notice Returns whether `user` currently qualifies for Daily (`>= 8h`) and Weekly (`>= 1d`) Guild Lottery Jackpots.
     */
    function getUserLotteryEligibility(address user)
        external
        view
        returns (
            bool isCurrentlyStaking,
            bool eligibleForDaily8h,
            bool eligibleForWeekly1d,
            uint256 dailyEligibleWeightIrl,
            uint256 weeklyEligibleWeightIrl,
            uint256 stakedDurationSeconds
        )
    {
        isCurrentlyStaking = stakedBalance[user] > 0;
        dailyEligibleWeightIrl = getEligibleLotteryStakeAt(user, block.timestamp, false);
        weeklyEligibleWeightIrl = getEligibleLotteryStakeAt(user, block.timestamp, true);
        eligibleForDaily8h = dailyEligibleWeightIrl > 0;
        eligibleForWeekly1d = weeklyEligibleWeightIrl > 0;
        stakedDurationSeconds = (isCurrentlyStaking && stakedSince[user] > 0 && block.timestamp >= stakedSince[user])
            ? (block.timestamp - stakedSince[user])
            : 0;
    }

    /**
     * @notice Settles any pending Lottery Jackpots won by Guild tickets BEFORE any user balance
     *         can be modified by `stake()` or `unstake()`, guaranteeing that eligibility is evaluated
     *         against the exact staker balances and durations at `drawTimestamp`!
     */
    function settlePendingLotteryJackpots() external nonReentrant {
        _settlePendingLotteryJackpots();
    }

    function _settlePendingLotteryJackpots() internal {
        uint256 len = pendingLotteryJackpots.length;
        while (nextUnsettledJackpotIndex < len) {
            uint256 idx = nextUnsettledJackpotIndex;
            nextUnsettledJackpotIndex++;

            PendingLotteryJackpot storage jp = pendingLotteryJackpots[idx];
            if (jp.settled || jp.amount == 0) continue;
            jp.settled = true;

            uint256 prize = jp.amount;
            uint256 drawTs = jp.drawTimestamp;
            bool isWeekly = jp.isWeekly;

            uint256 stakerCount = guildStakers.length;
            uint256 totalEligibleWeight = 0;
            uint256 eligibleCount = 0;

            for (uint256 i = 0; i < stakerCount; i++) {
                uint256 w = getEligibleLotteryStakeAt(guildStakers[i], drawTs, isWeekly);
                if (w > 0) {
                    totalEligibleWeight += w;
                    eligibleCount++;
                }
            }

            if (totalEligibleWeight > 0) {
                uint256 distributed = 0;
                address lastWinner = address(0);
                for (uint256 i = 0; i < stakerCount; i++) {
                    address member = guildStakers[i];
                    uint256 w = getEligibleLotteryStakeAt(member, drawTs, isWeekly);
                    if (w > 0) {
                        uint256 share = (prize * w) / totalEligibleWeight;
                        if (share > 0) {
                            pendingEth[member] += share;
                            pendingLotteryEth[member] += share;
                            distributed += share;
                            lastWinner = member;
                        }
                    }
                }
                if ( prize > distributed && lastWinner != address(0)) {
                    uint256 dust = prize - distributed;
                    pendingEth[lastWinner] += dust;
                    pendingLotteryEth[lastWinner] += dust;
                }
            } else {
                // Safety fallback if no staker has reached 8h/24h yet: distribute across active Guild stakers so ETH is never stuck
                _distributeEth(prize);
            }

            emit GuildLotteryJackpotSettled(idx, prize, isWeekly, eligibleCount, totalEligibleWeight);
        }
    }

    /**
     * @notice Harvests any pending native ETH Real Yield from the main IRLStaking contract
     *         and distributes it pro-rata across all Guild stakers.
     */
    function harvestFromMainStaking() public {
        _settlePendingLotteryJackpots();
        _harvestMainStaking();
    }

    function harvestMainStakingYield() external {
        harvestFromMainStaking();
    }

    function _harvestMainStaking() internal {
        uint256 pendingInMain = mainStaking.pendingYield(address(this));
        if (pendingInMain > 0) {
            _inMainHarvest = true;
            uint256 balBefore = address(this).balance;
            try mainStaking.claimYield() returns (uint256) {
                uint256 received = address(this).balance > balBefore ? (address(this).balance - balBefore) : 0;
                _inMainHarvest = false;
                if (received > 0) {
                    _distributeEth(received);
                    emit GuildYieldHarvested(received);
                }
            } catch {
                _inMainHarvest = false;
            }
        }
    }

    function _distributeEth(uint256 amount) internal {
        if (amount == 0) return;
        totalEthHarvested += amount;
        if (totalGuildStaked > 0) {
            uint256 totalToDistribute = amount + unallocatedEth;
            unallocatedEth = 0;
            accEthPerShare += (totalToDistribute * PRECISION) / totalGuildStaked;
        } else {
            unallocatedEth += amount;
        }
    }

    function _updateUserYield(address user) internal {
        uint256 userBal = stakedBalance[user];
        if (userBal > 0) {
            uint256 accumulated = (userBal * accEthPerShare) / PRECISION;
            if (accumulated > rewardDebt[user]) {
                pendingEth[user] += (accumulated - rewardDebt[user]);
            }
        }
    }

    /**
     * @notice Returns the total claimable native ETH for a Guild member (both Hourly Real Yield
     *         and their share of any Guild Lottery Jackpots!).
     */
    function pendingYield(address user) public view returns (uint256) {
        uint256 userBal = stakedBalance[user];
        uint256 basePending = pendingEth[user];

        // Include any unsettled lottery jackpots for which this user is eligible
        uint256 len = pendingLotteryJackpots.length;
        for (uint256 idx = nextUnsettledJackpotIndex; idx < len; idx++) {
            PendingLotteryJackpot storage jp = pendingLotteryJackpots[idx];
            if (!jp.settled && jp.amount > 0) {
                uint256 userW = getEligibleLotteryStakeAt(user, jp.drawTimestamp, jp.isWeekly);
                if (userW > 0) {
                    uint256 totalW = 0;
                    for (uint256 i = 0; i < guildStakers.length; i++) {
                        totalW += getEligibleLotteryStakeAt(guildStakers[i], jp.drawTimestamp, jp.isWeekly);
                    }
                    if (totalW > 0) {
                        basePending += (jp.amount * userW) / totalW;
                    }
                }
            }
        }

        if (userBal == 0) {
            return basePending;
        }

        uint256 effectiveAcc = accEthPerShare;
        if (totalGuildStaked > 0) {
            uint256 unharvestedMain = mainStaking.pendingYield(address(this));
            uint256 totalNew = unharvestedMain + unallocatedEth;
            if (totalNew > 0) {
                effectiveAcc += (totalNew * PRECISION) / totalGuildStaked;
            }
        }

        uint256 accumulated = (userBal * effectiveAcc) / PRECISION;
        uint256 delta = accumulated > rewardDebt[user] ? (accumulated - rewardDebt[user]) : 0;
        return basePending + delta;
    }

    function pendingGuildYield(address user) external view returns (uint256) {
        return pendingYield(user);
    }

    function guildStakedBalance(address user) external view returns (uint256) {
        return stakedBalance[user];
    }

    /**
     * @notice Deposit any amount of $IRL (> 0) into the Sherwood Guild Co-Staking Pool.
     *         No 1,000,000 $IRL minimum required!
     *         Automatically claims any mature free staking lottery tickets for the Guild BEFORE staking
     *         so the Guild never misses a free ticket when `mainStaking.stake()` updates `lastStakedTimestamp`.
     */
    function stake(uint256 amount) public nonReentrant {
        require(amount > 0, "Amount must be > 0");
        require(totalGuildStaked + amount <= MAX_GUILD_CAPACITY, "Exceeds 20M Guild cap");

        // 1. Settle any pending Lottery Jackpots at their exact drawTimestamp BEFORE changing balances
        _settlePendingLotteryJackpots();

        // 2. If Guild already reached 24h maturity in mainStaking, auto-claim free Guild tickets before stake resets cooldown
        _tryAutoClaimMatureGuildTickets();

        // 3. Harvest any pending ETH from main staking before changing weights
        _harvestMainStaking();
        _updateUserYield(msg.sender);

        // 4. Pull $IRL from user and stake into main IRLStaking
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        mainStaking.stake(amount);

        // 5. Update Guild member balances and 8h/24h lottery seniority timestamps
        uint256 prevBal = stakedBalance[msg.sender];
        if (prevBal == 0) {
            stakedBalance[msg.sender] = amount;
            stakedSince[msg.sender] = block.timestamp;
            recentTopUpAmount[msg.sender] = 0;
            recentTopUpTimestamp[msg.sender] = 0;
            _addGuildStaker(msg.sender);
        } else {
            // If previous recent top-up has already matured >= 1 day (Weekly threshold), fold it into base stake
            if (
                recentTopUpAmount[msg.sender] > 0 &&
                block.timestamp >= recentTopUpTimestamp[msg.sender] + WEEKLY_LOTTERY_MIN_STAKE_TIME
            ) {
                recentTopUpAmount[msg.sender] = 0;
            }
            stakedBalance[msg.sender] = prevBal + amount;
            recentTopUpAmount[msg.sender] += amount;
            recentTopUpTimestamp[msg.sender] = block.timestamp;
        }

        totalGuildStaked += amount;

        // 6. Flush any buffered ETH if this is the first staker
        if (unallocatedEth > 0 && totalGuildStaked > 0) {
            uint256 buffered = unallocatedEth;
            unallocatedEth = 0;
            accEthPerShare += (buffered * PRECISION) / totalGuildStaked;
        }

        rewardDebt[msg.sender] = (stakedBalance[msg.sender] * accEthPerShare) / PRECISION;

        emit GuildStaked(msg.sender, amount, totalGuildStaked);
    }

    function deposit(uint256 amount) external {
        stake(amount);
    }

    /**
     * @notice Withdraw staked $IRL from the Sherwood Guild back to the user's wallet.
     *         Note: If a user unstakes before a lottery draw, they are no longer staking at the moment
     *         of the lottery draw and therefore forfeit future lottery jackpots on the withdrawn amount,
     *         while keeping 100% of their already-earned ETH yield!
     */
    function unstake(uint256 amount) public nonReentrant {
        require(amount > 0, "Amount must be > 0");
        require(stakedBalance[msg.sender] >= amount, "Insufficient Guild stake");

        // 1. Settle any pending Lottery Jackpots that happened BEFORE this unstake!
        _settlePendingLotteryJackpots();

        // 2. Harvest any pending ETH from main staking before changing weights
        _harvestMainStaking();
        _updateUserYield(msg.sender);

        // 3. Update Guild member state before external interactions (CEI)
        stakedBalance[msg.sender] -= amount;
        totalGuildStaked -= amount;

        if (stakedBalance[msg.sender] == 0) {
            stakedSince[msg.sender] = 0;
            recentTopUpAmount[msg.sender] = 0;
            recentTopUpTimestamp[msg.sender] = 0;
            _removeGuildStaker(msg.sender);
        } else if (recentTopUpAmount[msg.sender] > 0) {
            if (amount >= recentTopUpAmount[msg.sender]) {
                recentTopUpAmount[msg.sender] = 0;
                recentTopUpTimestamp[msg.sender] = 0;
            } else {
                recentTopUpAmount[msg.sender] -= amount;
            }
        }

        rewardDebt[msg.sender] = (stakedBalance[msg.sender] * accEthPerShare) / PRECISION;

        // 4. Unstake from main IRLStaking and return $IRL to user
        mainStaking.unstake(amount);
        stakingToken.safeTransfer(msg.sender, amount);

        emit GuildUnstaked(msg.sender, amount, totalGuildStaked);
    }

    function withdraw(uint256 amount) external {
        unstake(amount);
    }

    /**
     * @notice Claims accumulated native ETH (both Hourly Real Yield and shared Guild Lottery Jackpots!) for the caller.
     */
    function claimYield() public nonReentrant returns (uint256 amount) {
        _settlePendingLotteryJackpots();
        _harvestMainStaking();
        _updateUserYield(msg.sender);

        amount = pendingEth[msg.sender];
        require(amount > 0, "No Guild ETH yield to claim");

        uint256 lotteryPortion = pendingLotteryEth[msg.sender];
        pendingEth[msg.sender] = 0;
        pendingLotteryEth[msg.sender] = 0;
        rewardDebt[msg.sender] = (stakedBalance[msg.sender] * accEthPerShare) / PRECISION;

        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "ETH transfer failed");

        emit GuildYieldClaimed(msg.sender, amount, lotteryPortion);
    }

    function claimGuildYield() external returns (uint256) {
        return claimYield();
    }

    /**
     * @notice Claims free staking NFT Lottery Tickets for the Guild contract (`address(this)`) from `IRLUniswapV4Hook`.
     *         - Unlocks as soon as at least 0.1% of supply (`1,000,000 $IRL`) is deposited in the Guild.
     *         - Applies ZERO 24h unstake lock on the Guild's supply!
     */
    function claimGuildStakingTickets() public nonReentrant {
        _claimGuildTicketsInternal(true);
    }

    function claimGuildStakingTickets(bool allowInstantIfUnder24h) external nonReentrant {
        _claimGuildTicketsInternal(allowInstantIfUnder24h);
    }

    function _claimGuildTicketsInternal(bool /* allowInstantIfUnder24h */) internal {
        require(hookContract != address(0), "Hook not configured");
        require(totalGuildStaked >= MIN_REAL_YIELD_THRESHOLD, "Need >= 0.1% supply (1M IRL) in Guild to claim tickets");

        (address nftAddr, uint256 mintedBefore) = _getNftTicketState();
        IIRLHookGuild(hookContract).claimStakingTickets();
        _recordMintedTicketsRange(nftAddr, mintedBefore);

        emit GuildTicketsClaimed(msg.sender, guildTicketIds.length, block.timestamp);
    }

    function _tryAutoClaimMatureGuildTickets() internal {
        if (hookContract != address(0) && totalGuildStaked >= MIN_REAL_YIELD_THRESHOLD) {
            (address nftAddr, uint256 mintedBefore) = _getNftTicketState();
            try IIRLHookGuild(hookContract).claimStakingTickets() {
                _recordMintedTicketsRange(nftAddr, mintedBefore);
                emit GuildTicketsClaimed(msg.sender, guildTicketIds.length, block.timestamp);
            } catch {}
        }
    }

    function _getNftTicketState() internal view returns (address nftAddr, uint256 totalMinted) {
        if (hookContract != address(0) && hookContract.code.length > 0) {
            try IIRLHookGuild(hookContract).nftTicket() returns (address addr) {
                nftAddr = addr;
                if (addr != address(0) && addr.code.length > 0) {
                    try IIRLTicketNFTGuild(addr).totalTicketsMinted() returns (uint256 m) {
                        totalMinted = m;
                    } catch {}
                }
            } catch {}
        }
    }

    function _recordMintedTicketsRange(address nftAddr, uint256 mintedBefore) internal {
        if (nftAddr == address(0) || nftAddr.code.length == 0) return;
        try IIRLTicketNFTGuild(nftAddr).totalTicketsMinted() returns (uint256 mintedAfter) {
            for (uint256 tid = mintedBefore + 1; tid <= mintedAfter; tid++) {
                if (!isGuildTicketRecorded[tid]) {
                    try IIRLTicketNFTGuild(nftAddr).ownerOf(tid) returns (address holder) {
                        if (holder == address(this)) {
                            isGuildTicketRecorded[tid] = true;
                            guildTicketIds.push(tid);
                        }
                    } catch {}
                }
            }
        } catch {}
    }

    /**
     * @notice Registers a ticket ID owned by the Guild if transferred via standard ERC721 `transferFrom`.
     */
    function registerGuildTicket(uint256 tokenId) external {
        (address nftAddr, ) = _getNftTicketState();
        require(nftAddr != address(0), "NFT contract not resolved");
        require(IIRLTicketNFTGuild(nftAddr).ownerOf(tokenId) == address(this), "Not owned by Guild");
        if (!isGuildTicketRecorded[tokenId]) {
            isGuildTicketRecorded[tokenId] = true;
            guildTicketIds.push(tokenId);
        }
    }

    /**
     * @notice Pulls any unclaimed lottery rewards credited to this Guild contract inside `IRLUniswapV4Hook.unclaimedRewards`
     *         and distributes them according to the 8h (Daily) / 1d (Weekly) active-staker rules.
     */
    function claimUnclaimedFromHook(bool isWeekly) external nonReentrant {
        require(hookContract != address(0), "Hook not configured");
        uint256 unclaimed = IIRLHookGuild(hookContract).unclaimedRewards(address(this));
        require(unclaimed > 0, "No unclaimed rewards in Hook");

        _inHookUnclaimedPull = true;
        uint256 balBefore = address(this).balance;
        IIRLHookGuild(hookContract).claimUnclaimedRewards();
        uint256 received = address(this).balance > balBefore ? (address(this).balance - balBefore) : 0;
        _inHookUnclaimedPull = false;

        if (received > 0) {
            uint256 idx = pendingLotteryJackpots.length;
            pendingLotteryJackpots.push(
                PendingLotteryJackpot({
                    amount: received,
                    drawTimestamp: block.timestamp,
                    isWeekly: isWeekly,
                    settled: false
                })
            );
            totalLotteryEthWon += received;
            emit GuildLotteryJackpotRecorded(idx, received, isWeekly, block.timestamp);
            _settlePendingLotteryJackpots();
        }
    }

    /**
     * @notice Allows updating the Hook contract reference if not set at deployment.
     */
    function setHookContract(address _hook) external onlyOwner {
        require(_hook != address(0), "Zero address");
        hookContract = _hook;
    }

    function getGuildStakersCount() external view returns (uint256) {
        return guildStakers.length;
    }

    function getGuildTicketCount() external view returns (uint256) {
        return guildTicketIds.length;
    }

    function getGuildTicketIds() external view returns (uint256[] memory) {
        return guildTicketIds;
    }

    function isGuildYieldActive() external view returns (bool) {
        return totalGuildStaked >= mainStaking.MIN_ELIGIBLE_STAKE();
    }

    function guildRemainingCapacity() external view returns (uint256) {
        return totalGuildStaked >= MAX_GUILD_CAPACITY ? 0 : (MAX_GUILD_CAPACITY - totalGuildStaked);
    }

    function userShareBps(address user) external view returns (uint256) {
        if (totalGuildStaked == 0) return 0;
        return (stakedBalance[user] * 10000) / totalGuildStaked;
    }

    /**
     * @notice Returns comprehensive Guild status for DApp and Telegram Bot display.
     */
    function getGuildStats()
        external
        view
        returns (
            uint256 pooledIrl,
            uint256 eligibleWeightInMain,
            uint256 totalEthDistributed,
            uint256 unharvestedMainEth,
            bool isMainYieldUnlocked,
            uint256 irlNeededForMinTier,
            uint256 totalTicketsOwnedByGuild,
            uint256 totalLotteryWonWei,
            uint256 activeStakersCount
        )
    {
        pooledIrl = totalGuildStaked;
        eligibleWeightInMain = mainStaking.eligibleStake(address(this));
        totalEthDistributed = totalEthHarvested + totalLotteryEthWon + mainStaking.pendingYield(address(this));
        unharvestedMainEth = mainStaking.pendingYield(address(this));
        uint256 minTier = mainStaking.MIN_ELIGIBLE_STAKE();
        isMainYieldUnlocked = pooledIrl >= minTier;
        irlNeededForMinTier = pooledIrl >= minTier ? 0 : (minTier - pooledIrl);
        totalTicketsOwnedByGuild = guildTicketIds.length;
        totalLotteryWonWei = totalLotteryEthWon;
        activeStakersCount = guildStakers.length;
    }

    function _addGuildStaker(address user) internal {
        if (_stakerIndexPlusOne[user] == 0) {
            guildStakers.push(user);
            _stakerIndexPlusOne[user] = guildStakers.length;
        }
    }

    function _removeGuildStaker(address user) internal {
        uint256 idxPlusOne = _stakerIndexPlusOne[user];
        if (idxPlusOne == 0) return;
        uint256 idx = idxPlusOne - 1;
        uint256 lastIdx = guildStakers.length - 1;
        if (idx != lastIdx) {
            address lastUser = guildStakers[lastIdx];
            guildStakers[idx] = lastUser;
            _stakerIndexPlusOne[lastUser] = idx + 1;
        }
        guildStakers.pop();
        _stakerIndexPlusOne[user] = 0;
    }

    function onERC721Received(
        address,
        address,
        uint256 tokenId,
        bytes calldata
    ) external override returns (bytes4) {
        if (!isGuildTicketRecorded[tokenId]) {
            isGuildTicketRecorded[tokenId] = true;
            guildTicketIds.push(tokenId);
        }
        return IERC721Receiver.onERC721Received.selector;
    }
}
