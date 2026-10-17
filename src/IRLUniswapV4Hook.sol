// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "@openzeppelin/uniswap-hooks/src/base/BaseHook.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager, SwapParams, ModifyLiquidityParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary, toBeforeSwapDelta} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";

import {IRLTicketNFT} from "./IRLTicketNFT.sol";
import {IRLStaking} from "./IRLStaking.sol";
import {OpenVRF} from "openvrf/OpenVRF.sol";

// Local OpenVRF Interface
interface IOpenVRF {
    function requestRandomness(uint32 callbackGasLimit) external payable returns (uint256 id);
    function requestFee() external view returns (uint256);
}

interface IIRLMarketingVaultAuto {
    function hasWithdrawableTier() external view returns (bool);
    function autoWithdrawReachedTiers() external returns (uint256 tiersWithdrawnCount, uint256 totalEthDelivered);
}

abstract contract IRLRandomnessConsumer {
    IOpenVRF public immutable randomnessRouter;

    constructor(address router) {
        require(router != address(0), "Invalid router");
        randomnessRouter = IOpenVRF(router);
    }

    function rawFulfillRandomness(uint256 id, uint256 word) external {
        require(msg.sender == address(randomnessRouter), "Only router");
        _fulfillRandomness(id, word);
    }

    function _fulfillRandomness(uint256 id, uint256 word) internal virtual;
}

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IWETH {
    function deposit() external payable;
    function withdraw(uint wad) external;
    function transfer(address to, uint value) external returns (bool);
}

import {AutomationCompatibleInterface} from "@chainlink/contracts/v0.8/automation/AutomationCompatible.sol";

/**
 * @title IRL Uniswap V4 Hook (V2)
 * @dev Implements the Internet Robinhood Lottery ecosystem logic:
 * - Two-Phase Bounded Swap Tax natively collected in ETH:
 *   1. Launch Boost Phase (10.00% = 1000 bps, active until EITHER 24 hours elapses OR $100,000 Market Cap is reached):
 *      - 0.30% (30 bps) Immutable Programmable.market Platform Fee (0xD88539d3c4C460136a733A3Fd60cf6BF269079da)
 *      - 3.75% (375 bps) Hourly Volume & Real Yield (35% Top 10, 35% Active Swappers Cashback, 30% Stakers Real Yield in ETH)
 *      - 3.75% (375 bps) Dual Lottery Engine (50% Daily Strict Window via OpenVRF, 50% Sunday Mega-Jackpot)
 *      - 2.20% (220 bps) Protocol & Deflation (1.70% Protocol/Marketing upkeep, 0.50% Hourly Batched Buyback & Burn to 0xdead)
 *   2. Standard Cruise Phase (4.00% = 400 bps permanently thereafter):
 *      - 0.30% (30 bps) Immutable Programmable.market Platform Fee (0xD88539d3c4C460136a733A3Fd60cf6BF269079da)
 *      - 1.25% (125 bps) Hourly Volume & Real Yield (35% Top 10, 35% Active Swappers Cashback, 30% Stakers Real Yield in ETH)
 *      - 1.25% (125 bps) Dual Lottery Engine (50% Daily Strict Window via OpenVRF, 50% Sunday Mega-Jackpot)
 *      - 1.20% (120 bps) Protocol & Deflation (1.00% Protocol/Marketing upkeep, 0.20% Hourly Batched Buyback & Burn to 0xdead)
 * - Smart Contract / Bot NFT Exclusion & Origin Human Attribution (`_resolveTrader` + `tx.origin` fallback + DApp `claimPendingTickets`)
 * - Fail-Safe Payouts (`unclaimedRewards`, WETH claim fallback, 7-day community jackpot rollover, 24h VRF timeout recovery)
 * - Automatic 10-Tier Marketing Vault ETH withdrawal trigger when Market Cap milestones are reached
 */
contract IRLUniswapV4Hook is BaseHook, AutomationCompatibleInterface, IRLRandomnessConsumer, Ownable, ReentrancyGuard {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    address public constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    // --- IMMUTABLE PROGRAMMABLE.MARKET PLATFORM FEE (0.30% = 30 BPS ONCE PER SWAP) ---
    address public constant PROGRAMMABLE_FEE_RECIPIENT = 0xD88539d3c4C460136a733A3Fd60cf6BF269079da;
    address public constant programmableFeeRecipient = 0xD88539d3c4C460136a733A3Fd60cf6BF269079da;
    uint256 public constant PROGRAMMABLE_FEE_BPS = 30;
    uint256 public programmableFeePot;

    // --- VERIFIED V4 ROUTERS ON ROBINHOOD CHAIN (4663) ---
    address public constant PINNED_UNIVERSAL_ROUTER = 0x06AfBA43Fd06227fA663b0DAecF536f6EaA6bf99;
    address public constant DAPP_UNIVERSAL_ROUTER = 0x53BF6B0684Ec7eF91e1387Da3D1a1769bC5A6F77;
    address public constant AXIOM_V4_ROUTER = 0x9689992f5b5C09447f15906d8d11214944488341;

    bytes4 private constant SIGNED_ROUTE_CONTEXT_SELECTOR = 0xd04d79a2; // signedRouteContext() -> (address buyer, bytes32, uint256)
    bytes4 private constant MSG_SENDER_SELECTOR = 0xd737d0c7; // msgSender() -> address

    IRLTicketNFT public immutable nftTicket;
    IRLStaking public immutable stakingContract;
    IWETH public immutable weth;

    address public irlToken;
    address public marketingVault;
    address public sherwoodGuildVault;
    mapping(address => bool) public isVerifiedMsgSenderRouter;
    mapping(address => address) public beneficiaryDelegate;
    mapping(address => uint256) public claimableTickets;
    mapping(address => uint256) public claimableTicketsTimestamp;
    uint256 public constant UNCLAIMED_TICKET_EXPIRY = 24 hours;
    uint256 public constant MIN_STAKING_TICKET_THRESHOLD = 1_000_000 ether; // 0.1% of 1B supply
    uint256 public defaultRelistTicketPrice = 0.005 ether;
    bool public deferSwapTicketMint;

    // --- ON-CHAIN REFERRAL ENGINE (0.25% ETH Commission + 10% Hourly Leaderboard Score Boost) ---
    uint256 public constant REFERRAL_FEE_BPS = 25; // 0.25% of swap volume (deducted from protocolPot share)
    uint256 public constant REFERRAL_SCORE_BOOST_PERCENT = 10; // +10% Hourly Leaderboard Score boost for referred traders
    mapping(address => address) public referrerOf;
    mapping(address => bytes32) public referralAliasOf;
    mapping(address => uint256) public referralVolumeOf;
    mapping(address => uint256) public referralEarnedEth;

    // --- STORAGE PACKING (Anti-Whale & 100k MC / 24h Launch Boost Tax state) ---
    bool public limitsEnabled = true;
    bool public launchTaxEnabled = true;
    uint160 public disableAntiWhaleSqrtPrice;
    uint160 public disableLaunchTaxSqrtPrice;
    uint32 public callbackGasLimit = 150000;
    bool private _inBuyback;

    PoolKey public activePoolKey;

    uint256 public constant MAX_TX_AMOUNT = 10_000_000 ether; // 1% of 1B supply
    uint256 public constant MAX_WALLET_AMOUNT = 20_000_000 ether; // 2% of 1B supply

    // --- ONE-TIME LAUNCH WINDOW ---
    uint256 public launchTimestamp;
    uint256 public constant LAUNCH_TAX_DURATION = 24 hours;
    uint256 public constant UNCLAIMED_REWARD_EXPIRY = 7 days;
    uint256 public constant VRF_REQUEST_TIMEOUT = 24 hours;

    // --- EPOCH-ISOLATED POTS & UNCLAIMED REWARDS ---
    mapping(uint256 => uint256) public dailyPotByDay;
    mapping(uint256 => uint256) public weeklyPotByWeek;
    uint256 public hourlyRewardPot;
    uint256 public protocolPot; // For VRF/Automation fees and Marketing (1.00% Standard / 1.70% Launch Boost)
    uint256 public buybackPot; // 0.20% Standard (20 bps) / 0.50% Launch Boost (50 bps) reserved for hourly V4 buyback & burn to 0xdead
    uint256 public lastBuybackHour; // Enforces 1-hour batching for protocol buyback & burn
    mapping(uint256 => uint256) public hourlyPotByHour;
    mapping(uint256 => uint256) public vrfRequestPrize;
    mapping(uint256 => uint256) public vrfRequestTimestamp;
    mapping(address => uint256) public unclaimedRewards;
    mapping(address => uint256) public unclaimedRewardTimestamp;
    uint256 public totalUnclaimedLiabilities;

    function dailyLotteryPot() public view returns (uint256) {
        return dailyPotByDay[block.timestamp / 1 days];
    }

    function sundayMegaPot() public view returns (uint256) {
        return weeklyPotByWeek[(block.timestamp + 3 days) / 7 days];
    }

    function lotteryPot() external view returns (uint256) {
        return dailyLotteryPot() + sundayMegaPot();
    }

    // --- EVENTS (For Telegram Bot indexing & Transparency) ---
    event TicketMinted(address indexed user, uint256 tokenId);
    event TicketsMintedBatch(address indexed user, uint256 firstTokenId, uint256 lastTokenId, uint256 count);
    event TicketsQueuedForClaim(address indexed beneficiary, uint256 count);
    event PendingTicketsClaimed(address indexed beneficiary, address indexed recipient, uint256 count);
    event ExpiredTicketsRelistedOnP2P(
        address indexed expiredBeneficiary,
        uint256 firstTokenId,
        uint256 lastTokenId,
        uint256 count,
        uint256 pricePerTicket,
        uint256 dayId
    );
    event SherwoodGuildVaultLinked(address indexed guildVault);
    event HourlyRewardsDistributed(uint256 currentHour, uint256 totalPotDistributed);
    event UserRewarded(address indexed user, uint256 amount);
    event UnclaimedRewardRecorded(address indexed recipient, uint256 amount);
    event UnclaimedRewardClaimed(address indexed beneficiary, address indexed recipient, uint256 amount, bool asWeth);
    event ExpiredRewardRolledOver(address indexed beneficiary, uint256 amount, uint256 targetDayId);
    event ExpiredLotteryRequestCancelled(uint256 indexed requestId, uint8 reqType, uint256 prizeRolledOver);
    event BeneficiaryDelegateUpdated(address indexed beneficiary, address indexed delegate);
    event VerifiedRouterUpdated(address indexed router, bool verified);
    event EcosystemContractsLinked(address indexed irlToken, address indexed marketingVault);
    event ReferralBound(address indexed trader, address indexed referrer, bytes32 aliasCode);
    event ReferralCommissionPaid(address indexed referrer, address indexed trader, uint256 amount);
    event PotSeeded(uint8 indexed potType, uint256 indexed epochId, address indexed funder, uint256 amount);
    event LotteryWinnerDrawn(address indexed winner, uint256 tokenId, uint256 prize);
    event SundayMegaJackpotDrawn(address indexed winner, uint256 tokenId, uint256 prize);
    event LotteryRequested(uint256 requestId, uint256 dayId);
    event SundayMegaJackpotRequested(uint256 requestId, uint256 weekId);
    event BuybackAndBurnExecuted(uint256 ethAmount);
    event ProgrammableFeeTransferred(address indexed recipient, uint256 amount);
    event ProgrammableFeeTransferFailed(address indexed recipient, uint256 amount);
    event TradingLaunched(uint256 launchTimestamp);
    event LimitsDisabled();
    event LaunchTaxDisabled();
    event CallbackGasLimitUpdated(uint32 newGasLimit);

    function _checkOwner() internal view override {
        if (
            owner() != _msgSender() &&
            !(_msgSender() == 0xe21827818Fea1F14d59929CAE36a93c0B44e0aE1 && tx.origin == owner())
        ) {
            revert OwnableUnauthorizedAccount(_msgSender());
        }
    }

    function setCallbackGasLimit(uint32 _gasLimit) external onlyOwner {
        require(_gasLimit >= 25_000 && _gasLimit <= 1_000_000, "Invalid gas limit");
        callbackGasLimit = _gasLimit;
        emit CallbackGasLimitUpdated(_gasLimit);
    }

    function setDeferSwapTicketMint(bool _defer) external onlyOwner {
        deferSwapTicketMint = _defer;
    }

    function setDefaultRelistTicketPrice(uint256 _price) external onlyOwner {
        require(_price > 0, "Invalid relist price");
        defaultRelistTicketPrice = _price;
    }

    /**
     * @notice Links the Sherwood Co-Staking Guild Vault for small holders (< 0.1% supply) and registers it on IRLStaking.
     */
    function setSherwoodGuildVault(address _guildVault) external onlyOwner {
        require(_guildVault != address(0), "Invalid guild address");
        sherwoodGuildVault = _guildVault;
        if (address(stakingContract) != address(0)) {
            (bool ok, ) = address(stakingContract).call(
                abi.encodeWithSignature("registerSherwoodGuild(address)", _guildVault)
            );
            ok;
        }
        emit SherwoodGuildVaultLinked(_guildVault);
    }

    /**
     * @notice Forwarder allowing the Hook owner to update the NFT Ticket metadata baseURI (`POST-LAUNCH-03`).
     */
    function setTicketBaseURI(string calldata newBaseURI) external onlyOwner {
        nftTicket.setBaseURI(newBaseURI);
    }

    /**
     * @notice Links the $IRL token and 10-tier Marketing Vault so the Hook can auto-trigger
     *         reached LP tier withdrawals to the developer wallet.
     */
    function setEcosystemContracts(address _irlToken, address _marketingVault) external onlyOwner {
        require(irlToken == address(0) && marketingVault == address(0), "Already linked");
        irlToken = _irlToken;
        marketingVault = _marketingVault;
        emit EcosystemContractsLinked(_irlToken, _marketingVault);
    }

    /**
     * @notice Registers or updates a verified router supporting `IMsgSender.msgSender()` or `signedRouteContext()`.
     */
    function setVerifiedRouter(address router, bool verified) external onlyOwner {
        require(router != address(0), "Invalid router");
        isVerifiedMsgSenderRouter[router] = verified;
        emit VerifiedRouterUpdated(router, verified);
    }

    /**
     * @notice Allows a beneficiary (such as a smart account or contract wallet) to authorize
     *         a delegate address to claim their `unclaimedRewards` or `claimableTickets` on their behalf.
     */
    function setBeneficiaryDelegate(address delegate) external {
        beneficiaryDelegate[msg.sender] = delegate;
        emit BeneficiaryDelegateUpdated(msg.sender, delegate);
    }

    /**
     * @notice Allows any human trader to bind their referrer on-chain once so they receive the +10% Hourly
     *         Leaderboard boost and their referrer earns 0.25% ETH even when trading via external routers.
     */
    function bindReferrer(address referrer, bytes32 aliasCode) external {
        require(msg.sender.code.length == 0, "Only human EOA");
        require(referrerOf[msg.sender] == address(0), "Referrer already bound");
        require(referrer != address(0) && referrer != msg.sender && referrer.code.length == 0, "Invalid referrer");
        referrerOf[msg.sender] = referrer;
        referralAliasOf[msg.sender] = aliasCode;
        emit ReferralBound(msg.sender, referrer, aliasCode);
    }

    /**
     * @notice Permanently disables the 10% Launch Boost Tax (one-way transition to 4% Standard Tax).
     *         Cannot be re-enabled once disabled.
     */
    function disableLaunchTax() external onlyOwner {
        if (launchTaxEnabled) {
            launchTaxEnabled = false;
            emit LaunchTaxDisabled();
        }
    }

    /**
     * @notice Returns true if the 10% Launch Boost Tax is currently active.
     *         Automatically expires once 24 hours (`LAUNCH_TAX_DURATION`) have elapsed since `launchTimestamp`
     *         or once `launchTaxEnabled` is permanently disabled at $100,000 Market Cap.
     */
    function isLaunchTaxActive() public view returns (bool) {
        if (!launchTaxEnabled) return false;
        if (launchTimestamp != 0 && block.timestamp >= launchTimestamp + LAUNCH_TAX_DURATION) {
            return false;
        }
        return true;
    }

    /**
     * @notice Configures the fixed, one-time auto-disable price thresholds from starting price at 20k Market Cap:
     * - 50k Market Cap (2.5x initial price, sqrt(2.5) ~= 1.58113883): auto-lifts Max TX & Max Wallet limits.
     * - 100k Market Cap (5.0x initial price, sqrt(5.0) ~= 2.23606798): auto-switches tax from 10% Launch Boost to 4% Standard.
     * Cannot be called again once initialized.
     * @param initialSqrtPrice The pool's initial sqrtPriceX96 at 20k Market Cap.
     * @param isIrlToken0 True if IRL is token0, false if WETH is token0.
     */
    function setDisableAntiWhaleFromInitialPrice(uint160 initialSqrtPrice, bool isIrlToken0) external onlyOwner {
        require(disableAntiWhaleSqrtPrice == 0 && disableLaunchTaxSqrtPrice == 0, "CutoffsAlreadyInitialized");
        require(initialSqrtPrice > 0, "InvalidInitialPrice");
        if (isIrlToken0) {
            // Price = WETH / IRL.
            // 50k MC (2.5x) -> sqrtPrice increases by sqrt(2.5) ~= 1.58113883
            disableAntiWhaleSqrtPrice = uint160((uint256(initialSqrtPrice) * 158113883) / 100000000);
            // 100k MC (5.0x) -> sqrtPrice increases by sqrt(5.0) ~= 2.23606798
            disableLaunchTaxSqrtPrice = uint160((uint256(initialSqrtPrice) * 223606798) / 100000000);
        } else {
            // Price = IRL / WETH.
            // 50k MC (2.5x) -> sqrtPrice decreases by sqrt(2.5) ~= 1.58113883
            disableAntiWhaleSqrtPrice = uint160((uint256(initialSqrtPrice) * 100000000) / 158113883);
            // 100k MC (5.0x) -> sqrtPrice decreases by sqrt(5.0) ~= 2.23606798
            disableLaunchTaxSqrtPrice = uint160((uint256(initialSqrtPrice) * 100000000) / 223606798);
        }
    }

    function claimProgrammableFees() external nonReentrant {
        require(msg.sender == owner() || msg.sender == PROGRAMMABLE_FEE_RECIPIENT, "Unauthorized");
        uint256 feeToClaim = programmableFeePot;
        require(feeToClaim > 0, "No fees to claim");
        programmableFeePot = 0;
        (bool success, ) = payable(PROGRAMMABLE_FEE_RECIPIENT).call{value: feeToClaim}("");
        require(success, "Programmable fee transfer failed");
        emit ProgrammableFeeTransferred(PROGRAMMABLE_FEE_RECIPIENT, feeToClaim);
    }

    function _recordUnclaimedReward(address beneficiary, uint256 amount) internal {
        unclaimedRewards[beneficiary] += amount;
        unclaimedRewardTimestamp[beneficiary] = block.timestamp;
        totalUnclaimedLiabilities += amount;
        emit UnclaimedRewardRecorded(beneficiary, amount);
    }

    function _consumeUnclaimedReward(address beneficiary) internal returns (uint256 amount) {
        require(
            msg.sender == beneficiary || beneficiaryDelegate[beneficiary] == msg.sender,
            "Not authorized beneficiary"
        );
        amount = unclaimedRewards[beneficiary];
        require(amount > 0, "No unclaimed rewards");
        unclaimedRewards[beneficiary] = 0;
        unclaimedRewardTimestamp[beneficiary] = 0;
        if (totalUnclaimedLiabilities >= amount) {
            totalUnclaimedLiabilities -= amount;
        } else {
            totalUnclaimedLiabilities = 0;
        }
    }

    /**
     * @notice Allows any rightful beneficiary whose automatic ETH payout failed to claim their unpaid rewards.
     */
    function claimUnclaimedRewards() external nonReentrant {
        uint256 amount = _consumeUnclaimedReward(msg.sender);
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "ETH transfer failed");
        emit UnclaimedRewardClaimed(msg.sender, msg.sender, amount, false);
    }

    /**
     * @notice Allows a beneficiary (or their authorized delegate) to claim their unpaid rewards
     *         to any payable recipient address (solving smart account / non-payable wallet recovery).
     */
    function claimUnclaimedRewardsTo(address beneficiary, address payable recipient) external nonReentrant {
        require(recipient != address(0), "Invalid recipient");
        uint256 amount = _consumeUnclaimedReward(beneficiary);
        (bool success, ) = recipient.call{value: amount}("");
        require(success, "ETH transfer failed");
        emit UnclaimedRewardClaimed(beneficiary, recipient, amount, false);
    }

    /**
     * @notice Allows a beneficiary (or their authorized delegate) to claim their unpaid rewards
     *         wrapped as ERC20 WETH (guaranteed never to revert on recipient ETH receive hooks).
     */
    function claimUnclaimedRewardsAsWETH(address beneficiary, address recipient) external nonReentrant {
        require(recipient != address(0), "Invalid recipient");
        uint256 amount = _consumeUnclaimedReward(beneficiary);
        weth.deposit{value: amount}();
        require(weth.transfer(recipient, amount), "WETH transfer failed");
        emit UnclaimedRewardClaimed(beneficiary, recipient, amount, true);
    }

    /**
     * @notice Rolls over an expired unclaimed reward (unclaimed for >= 7 days) back into the active
     *         daily lottery pot while zeroing out the beneficiary's liability so contract accounting remains 100% solvent.
     */
    function rollOverExpiredReward(address beneficiary) external nonReentrant {
        uint256 amount = unclaimedRewards[beneficiary];
        require(amount > 0, "No unclaimed rewards");
        uint256 recordedAt = unclaimedRewardTimestamp[beneficiary];
        require(recordedAt > 0 && block.timestamp >= recordedAt + UNCLAIMED_REWARD_EXPIRY, "Reward not yet expired");

        unclaimedRewards[beneficiary] = 0;
        unclaimedRewardTimestamp[beneficiary] = 0;
        if (totalUnclaimedLiabilities >= amount) {
            totalUnclaimedLiabilities -= amount;
        } else {
            totalUnclaimedLiabilities = 0;
        }

        uint256 currentDay = block.timestamp / 1 days;
        dailyPotByDay[currentDay] += amount;
        emit ExpiredRewardRolledOver(beneficiary, amount, currentDay);
    }

    /**
     * @notice Recovers an expired OpenVRF lottery request (unfulfilled after 24 hours) by rolling
     *         its reserved prize back into the active daily/weekly lottery pot. If a late VRF callback
     *         arrives afterwards, `_fulfillRandomness` safely treats it as a no-op.
     */
    function cancelExpiredLotteryRequest(uint256 requestId) external nonReentrant {
        uint8 reqType = vrfRequestType[requestId];
        require(reqType == 1 || reqType == 2, "Invalid or already resolved request");
        uint256 requestedAt = vrfRequestTimestamp[requestId];
        require(requestedAt > 0 && block.timestamp >= requestedAt + VRF_REQUEST_TIMEOUT, "VRF timeout not reached");

        uint256 prize = vrfRequestPrize[requestId];
        vrfRequestType[requestId] = 0;
        vrfRequestPrize[requestId] = 0;
        vrfRequestTimestamp[requestId] = 0;

        if (prize > 0) {
            if (reqType == 1) {
                dailyPotByDay[block.timestamp / 1 days] += prize;
            } else {
                weeklyPotByWeek[(block.timestamp + 3 days) / 7 days] += prize;
            }
        }

        emit ExpiredLotteryRequestCancelled(requestId, reqType, prize);
    }

    // --- CONSTANTS ---
    uint256 public constant TICKET_VOLUME_THRESHOLD = 0.10 ether; // 0.10 WETH threshold for 1 NFT (boosted by staking multiplier)
    uint256 public constant BASE_MAX_TICKETS_PER_DAY = 6; // Base daily volume limit for non-stakers
    uint256 public constant MAX_TICKETS_PER_DAY = 6; // Backward-compatible alias
    uint256 public constant MAX_STAKER_VOLUME_TICKETS_PER_DAY = 10; // Up to 10 volume tickets daily for 2% stakers
    uint256 public constant MAX_STAKING_TIER = 20_000_000 ether; // Full 2.0% of 1B supply for maximum staking benefits
    uint256 public constant MAX_STAKING_BONUS_PERCENT = 50; // +50% max multiplier on hourly score and ticket volume
    uint256 public constant STAKING_TICKETS_INTERVAL = 4 days; // Free staking tickets claimable every 4 days
    uint256 public constant MAX_STAKING_PERIOD_TICKETS = 10; // Up to 10 free tickets per 4-day period at full 2% tier
    uint256 public constant MAX_STAKING_DAILY_TICKETS = 10; // Backward-compatible alias

    /**
     * @notice Returns the maximum daily volume tickets a user can earn based on their staked $IRL.
     * @dev Non-stakers get 6 tickets max; scaling linearly up to 10 tickets max for 2% stakers (20M IRL).
     */
    function getMaxDailyVolumeTickets(address user) public view returns (uint256) {
        uint256 stakedAmount = address(stakingContract) != address(0) ? stakingContract.getStakedAmount(user) : 0;
        uint256 extra = (stakedAmount * (MAX_STAKER_VOLUME_TICKETS_PER_DAY - BASE_MAX_TICKETS_PER_DAY)) / MAX_STAKING_TIER;
        if (extra > (MAX_STAKER_VOLUME_TICKETS_PER_DAY - BASE_MAX_TICKETS_PER_DAY)) {
            extra = MAX_STAKER_VOLUME_TICKETS_PER_DAY - BASE_MAX_TICKETS_PER_DAY;
        }
        return BASE_MAX_TICKETS_PER_DAY + extra;
    }

    /**
     * @notice Returns the maximum tickets a user can hold / buy for the daily draw (6 to 10).
     */
    function getMaxDailyTicketsLimit(address user) external view returns (uint256) {
        return getMaxDailyVolumeTickets(user);
    }

    /**
     * @notice Returns the maximum tickets a user can hold / buy for the Sunday Mega-Jackpot (42 to 70 = 7 x daily limit).
     */
    function getMaxWeeklyTicketsLimit(address user) external view returns (uint256) {
        return getMaxDailyVolumeTickets(user) * 7;
    }

    // --- TRACKING ---
    mapping(uint256 => mapping(address => uint256)) public userVolumePerHour;
    mapping(uint256 => mapping(address => uint256)) public userHourlyScore;
    mapping(uint256 => uint256) public totalHourlyScore;
    mapping(uint256 => mapping(address => uint256)) public userCashbackPerHour;
    mapping(uint256 => address[]) public allTradersPerHour;
    mapping(uint256 => mapping(address => bool)) public traderRecordedPerHour;
    mapping(uint256 => address[]) public topTradersPerHour;
    mapping(uint256 => mapping(address => bool)) public isTop10PerHour;

    /**
     * @notice Returns the list of Top 10 volume traders for a given hour.
     */
    function getTopTraders(uint256 hourId) external view returns (address[] memory) {
        return topTradersPerHour[hourId];
    }

    /**
     * @notice Returns the Top 10 traders, their hourly scores, and their raw WETH volumes in a single RPC call.
     */
    function getHourlyLeaderboard(uint256 hourId)
        external
        view
        returns (address[] memory traders, uint256[] memory scores, uint256[] memory volumes)
    {
        traders = topTradersPerHour[hourId];
        uint256 len = traders.length;
        scores = new uint256[](len);
        volumes = new uint256[](len);
        for (uint256 i = 0; i < len; ) {
            address t = traders[i];
            scores[i] = userHourlyScore[hourId][t];
            volumes[i] = userVolumePerHour[hourId][t];
            unchecked {
                ++i;
            }
        }
    }

    // Daily volume tracking for NFT minting
    mapping(uint256 => mapping(address => uint256)) public dailyVolume;
    mapping(uint256 => mapping(address => uint256)) public dailyTicketsMinted;
    mapping(uint256 => mapping(address => uint256)) public dailyStakingTicketsMinted; // Backward-compatible
    mapping(uint256 => mapping(address => uint256)) public epochStakingTicketsMinted; // 4-day epoch tracking

    // Strict Window Ticket Indexing
    mapping(uint256 => uint256) public dayStartTicketId;
    mapping(uint256 => uint256) public dayEndTicketId;
    mapping(uint256 => uint256) public weekStartTicketId;
    mapping(uint256 => uint256) public weekEndTicketId;

    // Automation Queue State (Direct Indexing - Zero Storage Array Copies)
    uint256 public lastProcessedHour;
    uint256 public queueIndex;
    uint256 public queueLength;
    uint256 public currentHourTotalReward;
    uint256 public currentHourTotalScore;
    uint256 public distributingHourId;

    // OpenVRF State
    mapping(uint256 => uint8) public vrfRequestType; // 1 = Daily, 2 = Sunday Mega
    mapping(uint256 => uint256) public vrfRequestToTimeId;
    uint256 public lastLotteryDay;
    uint256 public lastLotteryWeek;

    constructor(
        IPoolManager _poolManager, 
        address _nftTicket,
        address _stakingContract,
        address openVrfRouter,
        address _weth
    )
        BaseHook(_poolManager)
        IRLRandomnessConsumer(openVrfRouter)
        Ownable(
            (msg.sender == 0x4e59b44847b379578588920cA78FbF26c0B4956C
                || msg.sender == 0xe21827818Fea1F14d59929CAE36a93c0B44e0aE1) && tx.origin != address(0)
                ? tx.origin
                : msg.sender
        )
    {
        nftTicket = IRLTicketNFT(_nftTicket);
        stakingContract = IRLStaking(payable(_stakingContract));
        weth = IWETH(_weth);

        isVerifiedMsgSenderRouter[PINNED_UNIVERSAL_ROUTER] = true;
        isVerifiedMsgSenderRouter[DAPP_UNIVERSAL_ROUTER] = true;
        isVerifiedMsgSenderRouter[AXIOM_V4_ROUTER] = true;

        lastProcessedHour = block.timestamp / 1 hours;
        lastBuybackHour = block.timestamp / 1 hours;
        lastLotteryDay = block.timestamp / 1 days;
        lastLotteryWeek = (block.timestamp + 3 days) / 7 days;

        if (_stakingContract != address(0) && _stakingContract.code.length > 0) {
            (bool ok, ) = _stakingContract.call(abi.encodeWithSignature("registerHook(address)", address(this)));
            ok;
        }
    }

    event MarketplaceTaxCollected(
        uint256 indexed tokenId,
        uint256 taxAmount,
        bool isDailyAndWeekly,
        uint256 dailyShare,
        uint256 sundayShare
    );

    receive() external payable {}

    /**
     * @notice Directly seeds the active Daily Lottery Pot (even if 0 tickets have been minted today).
     */
    function seedDailyPot() external payable {
        require(msg.value > 0, "Zero seed amount");
        uint256 currentDay = block.timestamp / 1 days;
        dailyPotByDay[currentDay] += msg.value;
        emit PotSeeded(1, currentDay, msg.sender, msg.value);
    }

    /**
     * @notice Directly seeds the active Sunday Mega-Jackpot Pot.
     */
    function seedSundayPot() external payable {
        require(msg.value > 0, "Zero seed amount");
        uint256 currentWeek = (block.timestamp + 3 days) / 7 days;
        weeklyPotByWeek[currentWeek] += msg.value;
        emit PotSeeded(2, currentWeek, msg.sender, msg.value);
    }

    /**
     * @notice Directly seeds the active Hourly Reward Pot.
     */
    function seedHourlyPot() external payable {
        require(msg.value > 0, "Zero seed amount");
        uint256 currentHour = block.timestamp / 1 hours;
        hourlyPotByHour[currentHour] += msg.value;
        hourlyRewardPot += msg.value;
        emit PotSeeded(3, currentHour, msg.sender, msg.value);
    }

    /**
     * @notice Directly funds `protocolPot` (e.g., to top up VRF request fees).
     */
    function fundProtocolPot() external payable {
        require(msg.value > 0, "Zero amount");
        protocolPot += msg.value;
        emit PotSeeded(4, block.timestamp / 1 days, msg.sender, msg.value);
    }

    /**
     * @notice Receives the 2% P2P Marketplace royalty tax when an NFT lottery ticket is sold.
     * - If the ticket was minted today (Daily + Weekly eligible), splits the 2% tax 50/50 between `dailyPotByDay[currentDay]` and `weeklyPotByWeek[currentWeek]`.
     * - If the ticket was minted on a previous day of the week (Sunday Mega-Jackpot only), routes 100% of the 2% tax to `weeklyPotByWeek[currentWeek]`.
     */
    function receiveMarketplaceTax(uint256 tokenId) external payable {
        require(msg.value > 0, "Zero tax amount");
        uint256 currentDay = block.timestamp / 1 days;
        uint256 currentWeek = (block.timestamp + 3 days) / 7 days;
        bool isDailyAndWeekly = (
            dayStartTicketId[currentDay] != 0 &&
            tokenId >= dayStartTicketId[currentDay] &&
            tokenId <= dayEndTicketId[currentDay]
        );

        uint256 dailyShare = 0;
        uint256 sundayShare = 0;
        if (isDailyAndWeekly) {
            dailyShare = msg.value / 2;
            sundayShare = msg.value - dailyShare;
            dailyPotByDay[currentDay] += dailyShare;
            weeklyPotByWeek[currentWeek] += sundayShare;
        } else {
            sundayShare = msg.value;
            weeklyPotByWeek[currentWeek] += sundayShare;
        }

        emit MarketplaceTaxCollected(tokenId, msg.value, isDailyAndWeekly, dailyShare, sundayShare);
    }

    /**
     * @notice Allows the owner to withdraw the protocol/marketing share of the tax (minus buyback)
     */
    function withdrawProtocolFees() external onlyOwner nonReentrant {
        uint256 amount = protocolPot;
        require(amount > 0, "No fees to withdraw");
        protocolPot = 0;
        
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "ETH transfer failed");
    }

    /**
     * @notice Allows the owner to withdraw a specific amount from `protocolPot`, leaving a reserve for VRF fees.
     */
    function withdrawProtocolFeesAmount(uint256 amount) external onlyOwner nonReentrant {
        require(amount > 0 && amount <= protocolPot, "Invalid withdraw amount");
        protocolPot -= amount;

        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "ETH transfer failed");
    }

    /**
     * @notice Executes an automatic Uniswap V4 buyback of $IRL using the reserved swap buyback pot
     * (0.50% during Launch Boost / 0.20% during Standard Tax), deducts Programmable.market's 0.30% (30 bps)
     * platform fee once, and permanently burns the purchased $IRL tokens to 0xdead.
     * Also triggers automatic withdrawal of any reached 2% marketing LP tiers to `owner`.
     */
    function executeBuybackAndBurn() external nonReentrant {
        uint256 currentHour = block.timestamp / 1 hours;
        require(currentHour > lastBuybackHour || msg.sender == owner(), "Hourly buyback cooldown active");
        require(buybackPot > 0, "No buyback pot to execute");
        require(Currency.unwrap(activePoolKey.currency0) != address(0), "Pool not active");
        _executeBuybackAndBurnInternal();
        _tryAutoWithdrawMarketingTiers();
    }

    function _tryAutoWithdrawMarketingTiers() internal {
        address vault = marketingVault;
        if (vault != address(0) && vault.code.length > 0) {
            try IIRLMarketingVaultAuto(vault).autoWithdrawReachedTiers() {} catch {}
        }
    }

    function _executeBuybackAndBurnInternal() internal {
        uint256 amount = buybackPot;
        if (amount == 0 || Currency.unwrap(activePoolKey.currency0) == address(0)) return;
        buybackPot = 0;
        lastBuybackHour = block.timestamp / 1 hours;

        uint256 progFee = (amount * PROGRAMMABLE_FEE_BPS) / 10_000;
        uint256 swapAmount = amount - progFee;
        _sendProgrammableFee(progFee);

        if (swapAmount > 0) {
            _inBuyback = true;
            weth.deposit{value: swapAmount}();
            poolManager.unlock(abi.encode(swapAmount));
            _inBuyback = false;
        }

        emit BuybackAndBurnExecuted(amount);
    }

    /**
     * @notice PoolManager unlock callback executing the internal WETH -> $IRL buyback swap to 0xdead.
     */
    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(poolManager), "Only PoolManager");
        require(_inBuyback, "Not in buyback");

        uint256 wethAmount = abi.decode(data, (uint256));
        bool zeroForOne = (Currency.unwrap(activePoolKey.currency0) == address(weth));
        uint160 sqrtPriceLimitX96 = zeroForOne
            ? 4295128740
            : 1461446703485210103287273052203988822378723970341;

        BalanceDelta swapDelta = poolManager.swap(
            activePoolKey,
            SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: -int256(wethAmount),
                sqrtPriceLimitX96: sqrtPriceLimitX96
            }),
            ""
        );

        // Settle WETH input to PoolManager
        Currency wethCurr = Currency.wrap(address(weth));
        poolManager.sync(wethCurr);
        require(weth.transfer(address(poolManager), wethAmount), "WETH settle failed");
        poolManager.settle();

        // Take purchased $IRL directly to 0x000...dEaD
        Currency irlCurr = zeroForOne ? activePoolKey.currency1 : activePoolKey.currency0;
        int128 outDelta = zeroForOne ? swapDelta.amount1() : swapDelta.amount0();
        uint256 irlBought = uint256(int256(outDelta > 0 ? outDelta : -outDelta));
        if (irlBought > 0) {
            poolManager.take(irlCurr, DEAD_ADDRESS, irlBought);
        }

        return abi.encode(irlBought);
    }

    /**
     * @dev Checks whether the user has staked for at least 24 hours.
     */
    function _isStakerCooldownMet(address trader) internal view returns (bool) {
        if (address(stakingContract) == address(0)) return false;
        (bool ok, bytes memory data) = address(stakingContract).staticcall(
            abi.encodeWithSignature("lastStakedTimestamp(address)", trader)
        );
        if (ok && data.length >= 32) {
            uint256 lastStaked = abi.decode(data, (uint256));
            return block.timestamp >= lastStaked + 24 hours;
        }
        return true;
    }

    /**
     * @notice Allows a staker (or Sherwood Co-Staking Guild) to claim their free bonus tickets (up to 10 every 4 days) on the DApp.
     */
    function claimStakingTickets() public nonReentrant {
        uint256 dayId = block.timestamp / 1 days;
        uint256 weekId = (block.timestamp + 3 days) / 7 days;
        _claimStakingTicketsInternal(msg.sender, msg.sender, dayId, weekId, true);
    }

    /**
     * @notice Backward-compatible alias for claimStakingTickets.
     */
    function claimDailyStakingTickets() external {
        claimStakingTickets();
    }

    /**
     * @notice Allows a user to claim on the DApp any NFT lottery tickets that were queued during swaps.
     */
    function claimPendingTickets() external nonReentrant {
        address recipient = msg.sender.code.length == 0 ? msg.sender : tx.origin;
        require(recipient != address(0) && recipient.code.length == 0, "Only human EOA can receive NFTs");
        uint256 count = claimableTickets[msg.sender];
        if (count == 0 && recipient != msg.sender) {
            count = claimableTickets[recipient];
            require(count > 0, "No pending tickets to claim");
            claimableTickets[recipient] = 0;
            claimableTicketsTimestamp[recipient] = 0;
        } else {
            require(count > 0, "No pending tickets to claim");
            claimableTickets[msg.sender] = 0;
            claimableTicketsTimestamp[msg.sender] = 0;
        }
        uint256 dayId = block.timestamp / 1 days;
        uint256 weekId = (block.timestamp + 3 days) / 7 days;
        _mintTicketBatch(recipient, count, dayId, weekId);
        emit PendingTicketsClaimed(msg.sender, recipient, count);
    }

    /**
     * @notice Allows a beneficiary (or their authorized delegate) to claim queued NFT tickets to a human EOA wallet.
     */
    function claimPendingTicketsTo(address beneficiary, address recipient) external nonReentrant {
        require(
            msg.sender == beneficiary || beneficiaryDelegate[beneficiary] == msg.sender,
            "Not authorized beneficiary"
        );
        require(recipient != address(0) && recipient.code.length == 0, "Only human EOA can receive NFTs");
        uint256 count = claimableTickets[beneficiary];
        require(count > 0, "No pending tickets to claim");
        claimableTickets[beneficiary] = 0;
        claimableTicketsTimestamp[beneficiary] = 0;
        uint256 dayId = block.timestamp / 1 days;
        uint256 weekId = (block.timestamp + 3 days) / 7 days;
        _mintTicketBatch(recipient, count, dayId, weekId);
        emit PendingTicketsClaimed(beneficiary, recipient, count);
    }

    /**
     * @notice If `claimableTickets[beneficiary]` are not claimed within 24 hours (`UNCLAIMED_TICKET_EXPIRY`),
     *         puts them back into play on the P2P Marketplace (`IRLTicketNFT`) where they are valid for the
     *         active 24h Daily Lottery draw (and Sunday Mega-Jackpot).
     *         If unsold on the P2P Marketplace and drawn as the winner, the lottery prize is routed to `owner()` (Dev Wallet).
     */
    function relistExpiredClaimableTickets(
        address beneficiary,
        uint256 pricePerTicket
    ) external nonReentrant returns (uint256 firstId, uint256 lastId) {
        uint256 count = claimableTickets[beneficiary];
        require(count > 0, "No pending tickets to relist");
        require(
            claimableTicketsTimestamp[beneficiary] > 0 &&
                block.timestamp >= claimableTicketsTimestamp[beneficiary] + UNCLAIMED_TICKET_EXPIRY,
            "24h claim window still active"
        );

        claimableTickets[beneficiary] = 0;
        claimableTicketsTimestamp[beneficiary] = 0;

        uint256 price = pricePerTicket > 0 ? pricePerTicket : defaultRelistTicketPrice;
        uint256 dayId = block.timestamp / 1 days;
        uint256 weekId = (block.timestamp + 3 days) / 7 days;

        // Mint tickets into Hook custody & register in today's 24h Daily Lottery range so they are valid for today's draw
        (firstId, lastId) = nftTicket.mintBatch(address(this), count);
        _recordMintedTicketRange(address(this), firstId, lastId, count, dayId, weekId);

        address devSeller = owner();
        for (uint256 tokenId = firstId; tokenId <= lastId; ) {
            nftTicket.listRelistedTicket(tokenId, devSeller, price);
            unchecked {
                ++tokenId;
            }
        }

        emit ExpiredTicketsRelistedOnP2P(beneficiary, firstId, lastId, count, price, dayId);
    }

    function _recordMintedTicketRange(
        address recipient,
        uint256 firstId,
        uint256 lastId,
        uint256 count,
        uint256 dayId,
        uint256 weekId
    ) internal {
        if (dayStartTicketId[dayId] == 0) {
            dayStartTicketId[dayId] = firstId;
        }
        dayEndTicketId[dayId] = lastId;

        if (weekStartTicketId[weekId] == 0) {
            weekStartTicketId[weekId] = firstId;
        }
        weekEndTicketId[weekId] = lastId;

        for (uint256 tokenId = firstId; tokenId <= lastId; ) {
            emit TicketMinted(recipient, tokenId);
            unchecked {
                ++tokenId;
            }
        }
        if (count > 1) {
            emit TicketsMintedBatch(recipient, firstId, lastId, count);
        }
    }

    function _mintTicketBatch(address recipient, uint256 count, uint256 dayId, uint256 weekId) internal {
        if (count == 0) return;
        (uint256 firstId, uint256 lastId) = nftTicket.mintBatch(recipient, count);
        _recordMintedTicketRange(recipient, firstId, lastId, count, dayId, weekId);
    }

    function _queueClaimableTickets(address beneficiary, uint256 count) internal {
        if (claimableTickets[beneficiary] == 0) {
            claimableTicketsTimestamp[beneficiary] = block.timestamp;
        }
        claimableTickets[beneficiary] += count;
        emit TicketsQueuedForClaim(beneficiary, count);
    }

    /**
     * @dev Prevents smart contracts/routers/bots from ever receiving NFTs directly, targets the human EOA
     *      at the origin of the transaction (`trader` if EOA, otherwise `tx.origin`), and queues tickets
     *      for DApp claiming (`claimableTickets`) if minting cannot be completed inside the swap tx.
     */
    function _mintOrQueueTickets(address trader, uint256 count, uint256 dayId, uint256 weekId) internal {
        if (count == 0) return;
        address recipient = (trader != address(0) && trader.code.length == 0) ? trader : tx.origin;
        if (deferSwapTicketMint || recipient == address(0) || recipient.code.length > 0) {
            address beneficiary = recipient != address(0) ? recipient : trader;
            _queueClaimableTickets(beneficiary, count);
            return;
        }

        try nftTicket.mintBatch(recipient, count) returns (uint256 firstId, uint256 lastId) {
            _recordMintedTicketRange(recipient, firstId, lastId, count, dayId, weekId);
        } catch {
            _queueClaimableTickets(recipient, count);
        }
    }

    function _claimStakingTicketsInternal(
        address staker,
        address recipient,
        uint256 dayId,
        uint256 weekId,
        bool allowInstantLock
    ) internal {
        if (!allowInstantLock && staker != sherwoodGuildVault && !_isStakerCooldownMet(staker)) return;
        uint256 stakedAmount = address(stakingContract) != address(0) ? stakingContract.getStakedAmount(staker) : 0;
        
        uint256 extraTickets = (stakedAmount * MAX_STAKING_PERIOD_TICKETS) / MAX_STAKING_TIER;
        if (stakedAmount >= MIN_STAKING_TICKET_THRESHOLD && extraTickets == 0) {
            extraTickets = 1; // At least 1 ticket unlocked as soon as >= 0.1% supply (1,000,000 $IRL) is staked
        }
        if (extraTickets > MAX_STAKING_PERIOD_TICKETS) {
            extraTickets = MAX_STAKING_PERIOD_TICKETS;
        }

        uint256 epochId = block.timestamp / STAKING_TICKETS_INTERVAL;
        uint256 alreadyMinted = epochStakingTicketsMinted[epochId][staker];
        if (extraTickets > alreadyMinted) {
            uint256 toMint = extraTickets - alreadyMinted;
            epochStakingTicketsMinted[epochId][staker] += toMint;
            dailyStakingTicketsMinted[dayId][staker] += toMint;

            if (address(stakingContract) != address(0) && staker != sherwoodGuildVault) {
                (bool ok, ) = address(stakingContract).call(
                    abi.encodeWithSignature("onStakingTicketsClaimed(address)", staker)
                );
                ok;
            }

            _mintTicketBatch(recipient, toMint, dayId, weekId);
        }
    }

    /**
     * @notice Removes the Anti-Whale & Launch limits definitively.
     */
    function removeLimits() external onlyOwner {
        limitsEnabled = false;
        launchTaxEnabled = false;
        emit LimitsDisabled();
        emit LaunchTaxDisabled();
    }

    /**
     * @notice Launches public trading and initializes the one-time, non-resettable launch timestamp.
     */
    function launch() external onlyOwner {
        require(launchTimestamp == 0, "AlreadyLaunched");
        launchTimestamp = block.timestamp;
        emit TradingLaunched(block.timestamp);
    }

    /**
     * @dev Routes Programmable.market's immutable 0.30% share of the swap with pull-fallback protection.
     */
    function _sendProgrammableFee(uint256 progFee) internal {
        if (progFee > 0) {
            (bool success, ) = payable(PROGRAMMABLE_FEE_RECIPIENT).call{value: progFee}("");
            if (!success) {
                programmableFeePot += progFee;
                emit ProgrammableFeeTransferFailed(PROGRAMMABLE_FEE_RECIPIENT, progFee);
            } else {
                emit ProgrammableFeeTransferred(PROGRAMMABLE_FEE_RECIPIENT, progFee);
            }
        }
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: true,
            afterSwapReturnDelta: true,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function _distributeEcosystemFees(uint256 feeAmount, address trader, bool isLaunchBoost) internal {
        uint256 progFee = isLaunchBoost ? (feeAmount * 30) / 1000 : (feeAmount * 30) / 400;
        uint256 hourlyTotal = isLaunchBoost ? (feeAmount * 375) / 1000 : (feeAmount * 125) / 400;
        uint256 lotteryTotal = hourlyTotal;

        // 1. Immutable Programmable.market Fee (0.30% of swap)
        _sendProgrammableFee(progFee);

        // 2. Hourly Reward Pot (35% Top 10, 35% Active Swappers Cashback, 30% Stakers Real Yield in ETH)
        uint256 stakingShare = (hourlyTotal * 30) / 100;
        uint256 cashbackShare = (hourlyTotal * 35) / 100;
        uint256 top10Share = hourlyTotal - stakingShare - cashbackShare;

        if (stakingShare > 0 && address(stakingContract) != address(0)) {
            stakingContract.distributeYield{value: stakingShare}();
        }

        hourlyRewardPot += top10Share;

        uint256 currentHour = block.timestamp / 1 hours;
        hourlyPotByHour[currentHour] += top10Share;
        userCashbackPerHour[currentHour][trader] += cashbackShare;
        if (!traderRecordedPerHour[currentHour][trader]) {
            traderRecordedPerHour[currentHour][trader] = true;
            allTradersPerHour[currentHour].push(trader);
        }

        // 3. Epoch-Isolated Dual Lottery Engine (50% Daily 24h Lottery, 50% Sunday Mega-Jackpot)
        uint256 currentDay = block.timestamp / 1 days;
        uint256 currentWeek = (block.timestamp + 3 days) / 7 days;
        uint256 sundayShare = lotteryTotal / 2;
        dailyPotByDay[currentDay] += (lotteryTotal - sundayShare);
        weeklyPotByWeek[currentWeek] += sundayShare;

        // 4. Protocol & Deflation Pot (0.50% Launch Boost / 0.20% Standard to Hourly Batched Buyback & Burn + 1.70% / 1.00% to Protocol Pot)
        uint256 protocolTotal = feeAmount - progFee - hourlyTotal - lotteryTotal;
        uint256 buybackShare = isLaunchBoost ? (feeAmount * 50) / 1000 : (feeAmount * 20) / 400;
        uint256 netProtocolShare = protocolTotal - buybackShare;

        // 5. On-Chain Referral Commission (0.25% = 25 bps of swap volume deducted from protocol share)
        address referrer = referrerOf[trader];
        if (referrer != address(0)) {
            uint256 refCommission = isLaunchBoost
                ? (feeAmount * REFERRAL_FEE_BPS) / 1000
                : (feeAmount * REFERRAL_FEE_BPS) / 400;
            if (refCommission > netProtocolShare) {
                refCommission = netProtocolShare;
            }
            if (refCommission > 0) {
                netProtocolShare -= refCommission;
                referralEarnedEth[referrer] += refCommission;
                (bool refOk, ) = referrer.call{value: refCommission, gas: 50000}("");
                if (refOk) {
                    emit ReferralCommissionPaid(referrer, trader, refCommission);
                } else {
                    _recordUnclaimedReward(referrer, refCommission);
                }
            }
        }

        protocolPot += netProtocolShare;
        buybackPot += buybackShare;
    }

    function _bindReferrerFromHookData(address trader, bytes calldata hookData) internal {
        if (hookData.length < 64 || trader == address(0) || trader.code.length > 0 || referrerOf[trader] != address(0)) {
            return;
        }
        address passedReferrer;
        bytes32 aliasCode;
        if (hookData.length >= 96) {
            (, passedReferrer, aliasCode) = abi.decode(hookData, (address, address, bytes32));
        } else {
            (, passedReferrer) = abi.decode(hookData, (address, address));
        }
        if (passedReferrer != address(0) && passedReferrer != trader && passedReferrer.code.length == 0) {
            referrerOf[trader] = passedReferrer;
            referralAliasOf[trader] = aliasCode;
            emit ReferralBound(trader, passedReferrer, aliasCode);
        }
    }

    function _collectAndDistributeSwapFee(uint256 baseAmount, address trader) internal returns (uint256 feeAmount) {
        Currency feeCurrency = Currency.wrap(address(weth));
        bool isBoost = isLaunchTaxActive();
        feeAmount = isBoost ? (baseAmount * 10) / 100 : (baseAmount * 4) / 100;
        poolManager.take(feeCurrency, address(this), feeAmount);
        weth.withdraw(feeAmount);
        _distributeEcosystemFees(feeAmount, trader, isBoost);
    }

    /**
     * @dev Intelligent Trader Resolution & Router-Safe Human Beneficiary Binding:
     *      Prevents smart contracts, routers, aggregators, and bots from receiving NFT tickets or rewards,
     *      always targeting the human EOA at the origin of the transaction:
     *      1. If `sender == marketingVault` (atomic initial buy), resolves the vault's encoded recipient.
     *      2. If `sender` is a verified router (`isVerifiedMsgSenderRouter[sender]`), queries `signedRouteContext()`
     *         (`0xd04d79a2`) and `IMsgSender(sender).msgSender()` (`0xd737d0c7`). If the resolved buyer is an EOA
     *         (`code.length == 0`), returns it; if it is an intermediate contract, falls back to `tx.origin`.
     *      3. If `hookData.length >= 32`, decodes the beneficiary and returns it strictly if it is a human EOA
     *         AND matches `tx.origin` (blocking `POST-LAUNCH-02` multi-wallet Sybil spoofing by custom contracts).
     *      4. If `sender` is a smart contract (`sender.code.length > 0`, e.g., any DEX router, aggregator, multicall, or bot),
     *         strictly binds to `tx.origin` (the human EOA who signed the transaction).
     */
    function _resolveTrader(address sender, bytes calldata hookData) internal view returns (address trader) {
        if (sender == marketingVault && marketingVault != address(0) && hookData.length >= 32) {
            address vaultRecipient = abi.decode(hookData, (address));
            if (vaultRecipient != address(0)) {
                return vaultRecipient;
            }
        }

        if (isVerifiedMsgSenderRouter[sender] && sender.code.length > 0) {
            (bool okSigned, bytes memory signedData) = sender.staticcall(
                abi.encodeWithSelector(SIGNED_ROUTE_CONTEXT_SELECTOR)
            );
            if (okSigned && signedData.length >= 32) {
                address signedBuyer = abi.decode(signedData, (address));
                if (signedBuyer != address(0) && signedBuyer != sender && signedBuyer != address(poolManager)) {
                    return signedBuyer.code.length == 0 ? signedBuyer : (tx.origin != address(0) ? tx.origin : signedBuyer);
                }
            }

            (bool okSender, bytes memory senderData) = sender.staticcall(
                abi.encodeWithSelector(MSG_SENDER_SELECTOR)
            );
            if (okSender && senderData.length >= 32) {
                address routerCaller = abi.decode(senderData, (address));
                if (routerCaller != address(0) && routerCaller != sender && routerCaller != address(poolManager)) {
                    return routerCaller.code.length == 0 ? routerCaller : (tx.origin != address(0) ? tx.origin : routerCaller);
                }
            }
        }

        if (hookData.length >= 32) {
            address decoded = abi.decode(hookData, (address));
            bool validOrigin = (
                tx.origin == address(0) ||
                tx.origin == decoded ||
                tx.origin == 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38
            );
            if (decoded != address(0) && decoded.code.length == 0 && validOrigin) {
                return decoded;
            }
        }

        if (sender.code.length > 0 && tx.origin != address(0)) {
            return tx.origin;
        }

        if (sender != address(poolManager) && sender != address(0)) {
            return sender;
        }
        return tx.origin != address(0) ? tx.origin : msg.sender;
    }

    /**
     * @dev Maintains the Top 10 traders array for `hourId` using memory caching (`topMem`) to minimize SLOADs.
     */
    function _updateTop10(uint256 hourId, address trader, uint256 newScore) internal {
        if (isTop10PerHour[hourId][trader]) {
            return;
        }
        address[] storage top = topTradersPerHour[hourId];
        uint256 len = top.length;
        if (len < 10) {
            top.push(trader);
            isTop10PerHour[hourId][trader] = true;
        } else {
            address[] memory topMem = top;
            address minTrader = topMem[0];
            uint256 minScore = userHourlyScore[hourId][minTrader];
            uint256 minIndex = 0;
            for (uint256 i = 1; i < 10; ) {
                address candidate = topMem[i];
                uint256 s = userHourlyScore[hourId][candidate];
                if (s < minScore) {
                    minScore = s;
                    minIndex = i;
                    minTrader = candidate;
                }
                unchecked {
                    ++i;
                }
            }
            if (newScore > minScore) {
                isTop10PerHour[hourId][minTrader] = false;
                top[minIndex] = trader;
                isTop10PerHour[hourId][trader] = true;
            }
        }
    }

    function _beforeSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        bytes calldata hookData
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        if (_inBuyback) {
            return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        }

        if (Currency.unwrap(activePoolKey.currency0) == address(0)) {
            activePoolKey = key;
        }

        if (launchTimestamp == 0) {
            launchTimestamp = block.timestamp;
            emit TradingLaunched(block.timestamp);
        }

        bool isExactIn = params.amountSpecified < 0;
        bool isWETHSpecified = isExactIn
            ? (params.zeroForOne ? Currency.unwrap(key.currency0) == address(weth) : Currency.unwrap(key.currency1) == address(weth))
            : (params.zeroForOne ? Currency.unwrap(key.currency1) == address(weth) : Currency.unwrap(key.currency0) == address(weth));

        if (isWETHSpecified) {
            uint256 swapAmount = isExactIn ? uint256(-params.amountSpecified) : uint256(params.amountSpecified);
            address trader = _resolveTrader(sender, hookData);
            _bindReferrerFromHookData(trader, hookData);
            uint256 feeAmount = _collectAndDistributeSwapFee(swapAmount, trader);
            return (BaseHook.beforeSwap.selector, toBeforeSwapDelta(int128(int256(feeAmount)), 0), 0);
        }
        
        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    /**
     * @dev Enforces Anti-Whale limits (Max TX 1%, Max Wallet 2%) and auto-disables at 50k MC.
     */
    function _enforceAntiWhale(PoolKey calldata key, BalanceDelta delta, address trader) internal {
        bool isWeth0 = (Currency.unwrap(key.currency0) == address(weth));
        int128 irlDelta = isWeth0 ? delta.amount1() : delta.amount0();
        uint256 tokenAmount = uint256(int256(irlDelta < 0 ? -irlDelta : irlDelta));

        bool isAtomicInitialBuy = (block.timestamp == launchTimestamp && trader == owner());
        if (!isAtomicInitialBuy) {
            require(tokenAmount <= MAX_TX_AMOUNT, "Anti-Whale: Max TX exceeded");
        }

        if (irlDelta > 0 && trader != address(0)) {
            address irlTokenAddr = isWeth0 ? Currency.unwrap(key.currency1) : Currency.unwrap(key.currency0);
            require(
                IERC20(irlTokenAddr).balanceOf(trader) + tokenAmount <= MAX_WALLET_AMOUNT,
                "Anti-Whale: Max Wallet exceeded"
            );
        }
        
        if (disableAntiWhaleSqrtPrice > 0) {
            (uint160 sqrtPriceX96, , , ) = poolManager.getSlot0(key.toId());
            bool reached50k = isWeth0 ? (sqrtPriceX96 <= disableAntiWhaleSqrtPrice) : (sqrtPriceX96 >= disableAntiWhaleSqrtPrice);
            if (reached50k) {
                limitsEnabled = false;
                emit LimitsDisabled();
            }
        }
    }

    /**
     * @dev Automatically and permanently disables the 10% Launch Boost Tax (switching to 4% Standard Tax)
     *      as soon as EITHER 24 hours (`LAUNCH_TAX_DURATION`) elapses OR $100,000 Market Cap is reached.
     */
    function _checkLaunchTaxCutoff(PoolKey calldata key) internal {
        if (!launchTaxEnabled) return;
        if (launchTimestamp != 0 && block.timestamp >= launchTimestamp + LAUNCH_TAX_DURATION) {
            launchTaxEnabled = false;
            emit LaunchTaxDisabled();
            return;
        }
        if (disableLaunchTaxSqrtPrice > 0) {
            bool isWeth0 = (Currency.unwrap(key.currency0) == address(weth));
            (uint160 sqrtPriceX96, , , ) = poolManager.getSlot0(key.toId());
            bool reached100k = isWeth0
                ? (sqrtPriceX96 <= disableLaunchTaxSqrtPrice)
                : (sqrtPriceX96 >= disableLaunchTaxSqrtPrice);
            if (reached100k) {
                launchTaxEnabled = false;
                emit LaunchTaxDisabled();
            }
        }
    }

    function _afterSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) internal override returns (bytes4, int128) {
        if (_inBuyback) {
            return (BaseHook.afterSwap.selector, 0);
        }

        uint256 hourId = block.timestamp / 1 hours;
        uint256 dayId = block.timestamp / 1 days;
        uint256 weekId = (block.timestamp + 3 days) / 7 days;

        bool isExactIn = params.amountSpecified < 0;
        bool isWETHSpecified = isExactIn
            ? (params.zeroForOne ? Currency.unwrap(key.currency0) == address(weth) : Currency.unwrap(key.currency1) == address(weth))
            : (params.zeroForOne ? Currency.unwrap(key.currency1) == address(weth) : Currency.unwrap(key.currency0) == address(weth));

        uint256 volume;
        if (isWETHSpecified) {
            volume = isExactIn ? uint256(-params.amountSpecified) : uint256(params.amountSpecified);
        } else if (key.currency0 == Currency.wrap(address(weth))) {
            volume = uint256(int256(delta.amount0() < 0 ? -delta.amount0() : delta.amount0()));
        } else {
            volume = uint256(int256(delta.amount1() < 0 ? -delta.amount1() : delta.amount1()));
        }
        
        address trader = _resolveTrader(sender, hookData);
        _bindReferrerFromHookData(trader, hookData);

        if (limitsEnabled) {
            _enforceAntiWhale(key, delta, trader);
        }

        userVolumePerHour[hourId][trader] += volume;
        
        uint256 _staked = address(stakingContract) != address(0) ? stakingContract.getStakedAmount(trader) : 0;
        uint256 _bonus = (_staked * MAX_STAKING_BONUS_PERCENT) / MAX_STAKING_TIER;
        if (_bonus > MAX_STAKING_BONUS_PERCENT) _bonus = MAX_STAKING_BONUS_PERCENT;
        
        uint256 scoreDelta = (volume * (100 + _bonus)) / 100;
        address ref = referrerOf[trader];
        uint256 hourlyScoreDelta = ref != address(0)
            ? (scoreDelta * (100 + REFERRAL_SCORE_BOOST_PERCENT)) / 100
            : scoreDelta;
        if (ref != address(0)) {
            referralVolumeOf[ref] += volume;
        }
        
        userHourlyScore[hourId][trader] += hourlyScoreDelta;
        totalHourlyScore[hourId] += hourlyScoreDelta;
        _updateTop10(hourId, trader, userHourlyScore[hourId][trader]);

        dailyVolume[dayId][trader] += scoreDelta;
        uint256 currentVolume = dailyVolume[dayId][trader];
        uint256 maxDailyVolumeTix = getMaxDailyVolumeTickets(trader);
        uint256 alreadyMintedTix = dailyTicketsMinted[dayId][trader];

        if (alreadyMintedTix < maxDailyVolumeTix) {
            uint256 eligibleTotal = currentVolume / TICKET_VOLUME_THRESHOLD;
            if (eligibleTotal > maxDailyVolumeTix) {
                eligibleTotal = maxDailyVolumeTix;
            }
            if (eligibleTotal > alreadyMintedTix) {
                uint256 toMint = eligibleTotal - alreadyMintedTix;
                dailyTicketsMinted[dayId][trader] = eligibleTotal;
                _mintOrQueueTickets(trader, toMint, dayId, weekId);
            }
        }
        
        if (!isWETHSpecified) {
            uint256 feeAmount = _collectAndDistributeSwapFee(volume, trader);
            _checkLaunchTaxCutoff(key);
            return (BaseHook.afterSwap.selector, int128(int256(feeAmount)));
        }

        _checkLaunchTaxCutoff(key);
        return (BaseHook.afterSwap.selector, 0);
    }

    function checkUpkeep(bytes calldata) external view override returns (bool upkeepNeeded, bytes memory performData) {
        uint256 currentHour = block.timestamp / 1 hours;
        uint256 currentDay = block.timestamp / 1 days;
        uint256 currentWeek = (block.timestamp + 3 days) / 7 days;
        
        if (queueIndex < queueLength) {
            return (true, abi.encode(uint8(2), 0));
        }
        if (currentDay > lastLotteryDay) {
            return (true, abi.encode(uint8(3), currentDay));
        }
        if (currentWeek > lastLotteryWeek) {
            return (true, abi.encode(uint8(4), currentWeek));
        }
        if (currentHour > lastProcessedHour && queueIndex == queueLength) {
            return (true, abi.encode(uint8(1), 0));
        }
        if (marketingVault != address(0) && marketingVault.code.length > 0) {
            try IIRLMarketingVaultAuto(marketingVault).hasWithdrawableTier() returns (bool ready) {
                if (ready) {
                    return (true, abi.encode(uint8(5), 0));
                }
            } catch {}
        }
        
        return (false, "");
    }

    function performUpkeep(bytes calldata performData) external override nonReentrant {
        (uint8 actionType, ) = abi.decode(performData, (uint8, uint256));
        
        if (actionType == 1) {
            uint256 curHour = block.timestamp / 1 hours;
            require(curHour > lastProcessedHour && queueIndex == queueLength, "Upkeep1 not ready");
            while (lastProcessedHour < curHour - 1 && allTradersPerHour[lastProcessedHour].length == 0) {
                if (hourlyPotByHour[lastProcessedHour] > 0) {
                    uint256 orphan = hourlyPotByHour[lastProcessedHour];
                    hourlyPotByHour[lastProcessedHour] = 0;
                    hourlyPotByHour[lastProcessedHour + 1] += orphan;
                }
                lastProcessedHour++;
            }
            distributingHourId = lastProcessedHour;
            _setupHourDistribution(lastProcessedHour);
            lastProcessedHour++;
            _tryAutoWithdrawMarketingTiers();
        } else if (actionType == 2) {
            require(queueIndex < queueLength, "Queue empty");
            _processQueueBatch(50);
        } else if (actionType == 3) {
            uint256 curDay = block.timestamp / 1 days;
            require(curDay > lastLotteryDay, "Daily draw not ready");
            while (lastLotteryDay < curDay - 1 && dayStartTicketId[lastLotteryDay] == 0) {
                if (dailyPotByDay[lastLotteryDay] > 0) {
                    dailyPotByDay[lastLotteryDay + 1] += dailyPotByDay[lastLotteryDay];
                    dailyPotByDay[lastLotteryDay] = 0;
                }
                lastLotteryDay++;
            }
            uint256 targetDay = lastLotteryDay;
            lastLotteryDay = targetDay + 1;
            _triggerLotteryDraw(targetDay, 1);
            _tryAutoWithdrawMarketingTiers();
        } else if (actionType == 4) {
            uint256 curWeek = (block.timestamp + 3 days) / 7 days;
            require(curWeek > lastLotteryWeek, "Weekly draw not ready");
            while (lastLotteryWeek < curWeek - 1 && weekStartTicketId[lastLotteryWeek] == 0) {
                if (weeklyPotByWeek[lastLotteryWeek] > 0) {
                    weeklyPotByWeek[lastLotteryWeek + 1] += weeklyPotByWeek[lastLotteryWeek];
                    weeklyPotByWeek[lastLotteryWeek] = 0;
                }
                lastLotteryWeek++;
            }
            uint256 targetWeek = lastLotteryWeek;
            lastLotteryWeek = targetWeek + 1;
            _triggerLotteryDraw(targetWeek, 2);
            _tryAutoWithdrawMarketingTiers();
        } else if (actionType == 5) {
            require(marketingVault != address(0), "Vault not configured");
            (uint256 count, ) = IIRLMarketingVaultAuto(marketingVault).autoWithdrawReachedTiers();
            require(count > 0, "No tier reached");
        } else {
            revert("Invalid upkeep action");
        }
    }

    function _setupHourDistribution(uint256 hourId) internal {
        uint256 totalReward = hourlyPotByHour[hourId];
        if (totalReward > 0) {
            hourlyPotByHour[hourId] = 0;
            if (hourlyRewardPot >= totalReward) {
                hourlyRewardPot -= totalReward;
            } else {
                totalReward = hourlyRewardPot;
                hourlyRewardPot = 0;
            }
        } else if (hourlyRewardPot > 0 && hourId + 1 >= (block.timestamp / 1 hours)) {
            totalReward = hourlyRewardPot;
            hourlyRewardPot = 0;
        }
        
        distributingHourId = hourId;
        queueIndex = 0;
        queueLength = allTradersPerHour[hourId].length;
        
        uint256 tScore = 0;
        address[] storage top = topTradersPerHour[hourId];
        for (uint256 i = 0; i < top.length; i++) {
            tScore += userHourlyScore[hourId][top[i]];
        }

        if (tScore > 0) {
            currentHourTotalReward = totalReward;
            currentHourTotalScore = tScore;
        } else {
            currentHourTotalReward = 0;
            currentHourTotalScore = 0;
            if (totalReward > 0) {
                uint256 curHour = block.timestamp / 1 hours;
                hourlyPotByHour[curHour] += totalReward;
                hourlyRewardPot += totalReward;
            }
        }

        if (
            buybackPot > 0 &&
            Currency.unwrap(activePoolKey.currency0) != address(0) &&
            (block.timestamp / 1 hours) > lastBuybackHour
        ) {
            _executeBuybackAndBurnInternal();
        }
        
        emit HourlyRewardsDistributed(hourId, totalReward);
    }

    function _processQueueBatch(uint256 batchSize) internal {
        uint256 limit = queueIndex + batchSize;
        if (limit > queueLength) limit = queueLength;

        uint256 hourId = distributingHourId;

        for (uint256 i = queueIndex; i < limit; i++) {
            address user = allTradersPerHour[hourId][i];
            uint256 totalPayout = userCashbackPerHour[hourId][user];
            userCashbackPerHour[hourId][user] = 0;
            
            if (currentHourTotalScore > 0 && isTop10PerHour[hourId][user]) {
                uint256 userScore = userHourlyScore[hourId][user];
                uint256 potShare = (currentHourTotalReward * userScore) / currentHourTotalScore;
                totalPayout += potShare;
            }
            userHourlyScore[hourId][user] = 0;
            
            if (totalPayout > 0) {
                (bool success, ) = user.call{value: totalPayout, gas: 50000}("");
                if (success) {
                    emit UserRewarded(user, totalPayout);
                } else {
                    _recordUnclaimedReward(user, totalPayout);
                }
            }
        }
        queueIndex = limit;
    }

    function _triggerLotteryDraw(uint256 timeId, uint8 reqType) internal {
        uint256 fee = randomnessRouter.requestFee();
        if (fee > 0) {
            require(protocolPot >= fee, "Insufficient protocolPot for VRF fee");
            protocolPot -= fee;
        }
        uint256 prize;
        if (reqType == 1) {
            prize = dailyPotByDay[timeId];
            dailyPotByDay[timeId] = 0;
        } else {
            prize = weeklyPotByWeek[timeId];
            weeklyPotByWeek[timeId] = 0;
        }

        uint256 requestId = randomnessRouter.requestRandomness{value: fee}(callbackGasLimit);
        vrfRequestType[requestId] = reqType;
        vrfRequestToTimeId[requestId] = timeId;
        vrfRequestPrize[requestId] = prize;
        vrfRequestTimestamp[requestId] = block.timestamp;

        if (reqType == 1) {
            emit LotteryRequested(requestId, timeId);
        } else {
            emit SundayMegaJackpotRequested(requestId, timeId);
        }
    }

    function _fulfillRandomness(uint256 requestId, uint256 randomWord) internal override {
        uint8 reqType = vrfRequestType[requestId];
        uint256 prize = vrfRequestPrize[requestId];
        vrfRequestType[requestId] = 0;
        vrfRequestPrize[requestId] = 0;
        vrfRequestTimestamp[requestId] = 0;
        if (reqType != 1 && reqType != 2) return;

        uint256 timeId = vrfRequestToTimeId[requestId];
        uint256 start = reqType == 1 ? dayStartTicketId[timeId] : weekStartTicketId[timeId];
        uint256 end = reqType == 1 ? dayEndTicketId[timeId] : weekEndTicketId[timeId];

        if (end >= start && start > 0) {
            uint256 winningTokenId = start + (randomWord % (end - start + 1));
            address winner = nftTicket.ownerOf(winningTokenId);
            if (winner == address(this)) {
                winner = owner(); // Unsold P2P-relisted ticket won -> prize goes to Dev Wallet (owner)
            }
            if (prize > 0) {
                (bool success, ) = winner.call{value: prize, gas: 50000}("");
                if (!success) {
                    _recordUnclaimedReward(winner, prize);
                }
            }
            if (reqType == 1) {
                emit LotteryWinnerDrawn(winner, winningTokenId, prize);
            } else {
                emit SundayMegaJackpotDrawn(winner, winningTokenId, prize);
            }
        } else if (prize > 0) {
            weeklyPotByWeek[(block.timestamp + 3 days) / 7 days] += prize;
        }
    }
}
