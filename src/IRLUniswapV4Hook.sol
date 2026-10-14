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
 * @title IRL Uniswap V4 Hook
 * @dev Implements the Internet Robinhood Lottery ecosystem logic with Programmable.market launch integration:
 * - Two-Phase Bounded Swap Tax natively collected in ETH:
 *   1. Launch Boost Phase (10.00% = 1000 bps, active until EITHER 24 hours elapses OR $100,000 Market Cap is reached):
 *      - 0.30% (30 bps) Immutable Programmable.market Platform Fee (0xD88539d3c4C460136a733A3Fd60cf6BF269079da)
 *      - 3.75% (375 bps) Hourly Volume & Real Yield (35% Top 10, 35% Active Swappers Cashback, 30% Stakers Real Yield in ETH)
 *      - 3.75% (375 bps) Dual Lottery Engine (50% Daily Strict Window via OpenVRF, 50% Sunday Mega-Jackpot)
 *      - 2.20% (220 bps) Protocol & Deflation (90% Protocol/Marketing upkeep, 10% Hourly Batched Buyback & Burn to 0xdead)
 *   2. Standard Cruise Phase (4.00% = 400 bps permanently thereafter):
 *      - 0.30% (30 bps) Immutable Programmable.market Platform Fee (0xD88539d3c4C460136a733A3Fd60cf6BF269079da)
 *      - 1.25% (125 bps) Hourly Volume & Real Yield (35% Top 10, 35% Active Swappers Cashback, 30% Stakers Real Yield in ETH)
 *      - 1.25% (125 bps) Dual Lottery Engine (50% Daily Strict Window via OpenVRF, 50% Sunday Mega-Jackpot)
 *      - 1.20% (120 bps) Protocol & Deflation (90% Protocol/Marketing upkeep, 10% Hourly Batched Buyback & Burn to 0xdead)
 * - Anti-Whale max tx & max wallet auto-removal at $50,000 Market Cap
 * - Epoch-isolated Daily (`dailyPotByDay`) and Weekly (`weeklyPotByWeek`) lottery accounting
 * - Pull-claimable `unclaimedRewards` for any failed ETH payout
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

    IRLTicketNFT public immutable nftTicket;
    IRLStaking public immutable stakingContract;
    IWETH public immutable weth;

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

    // --- EPOCH-ISOLATED POTS & UNCLAIMED REWARDS ---
    mapping(uint256 => uint256) public dailyPotByDay;
    mapping(uint256 => uint256) public weeklyPotByWeek;
    uint256 public hourlyRewardPot;
    uint256 public protocolPot; // For VRF/Automation fees and Marketing (0.75% Standard / 1.75% Launch Boost)
    uint256 public buybackPot; // 0.45% (45 bps) of every swap reserved for hourly V4 buyback & burn (0.15% Prog + 0.45% = 0.60% total burn)
    uint256 public lastBuybackHour; // Enforces 1-hour batching for protocol buyback & burn
    mapping(uint256 => uint256) public hourlyPotByHour;
    mapping(uint256 => uint256) public vrfRequestPrize;
    mapping(address => uint256) public unclaimedRewards;

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
    event HourlyRewardsDistributed(uint256 currentHour, uint256 totalPotDistributed);
    event UserRewarded(address indexed user, uint256 amount);
    event UnclaimedRewardRecorded(address indexed recipient, uint256 amount);
    event UnclaimedRewardClaimed(address indexed recipient, uint256 amount);
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

    function setDisableAntiWhalePrice(uint160 _price) external onlyOwner {
        disableAntiWhaleSqrtPrice = _price;
    }

    function setDisableLaunchTaxPrice(uint160 _price) external onlyOwner {
        disableLaunchTaxSqrtPrice = _price;
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
     * @notice Configures the auto-disable price thresholds from starting price at 20k Market Cap:
     * - 50k Market Cap (2.5x initial price, sqrt(2.5) ~= 1.58113883): auto-lifts Max TX & Max Wallet limits.
     * - 100k Market Cap (5.0x initial price, sqrt(5.0) ~= 2.23606798): auto-switches tax from 10% Launch Boost to 4% Standard.
     * @param initialSqrtPrice The pool's initial sqrtPriceX96 at 20k Market Cap.
     * @param isIrlToken0 True if IRL is token0, false if WETH is token0.
     */
    function setDisableAntiWhaleFromInitialPrice(uint160 initialSqrtPrice, bool isIrlToken0) external onlyOwner {
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

    /**
     * @notice Allows any rightful recipient whose automatic ETH payout failed to claim their unpaid rewards.
     */
    function claimUnclaimedRewards() external nonReentrant {
        uint256 amount = unclaimedRewards[msg.sender];
        require(amount > 0, "No unclaimed rewards");
        unclaimedRewards[msg.sender] = 0;
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "ETH transfer failed");
        emit UnclaimedRewardClaimed(msg.sender, amount);
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
     * @notice Executes an automatic Uniswap V4 buyback of $IRL using the reserved 0.45% (45 bps) swap buyback pot
     * and permanently burns the purchased $IRL tokens to 0xdead (0.15% Programmable burn + 0.45% = 0.60% total burn).
     * Batched once per hour so the price chart is never spammed with micro-buybacks on every trade.
     */
    function executeBuybackAndBurn() external nonReentrant {
        uint256 currentHour = block.timestamp / 1 hours;
        require(currentHour > lastBuybackHour || msg.sender == owner(), "Hourly buyback cooldown active");
        require(buybackPot > 0, "No buyback pot to execute");
        require(Currency.unwrap(activePoolKey.currency0) != address(0), "Pool not active");
        _executeBuybackAndBurnInternal();
    }

    function _executeBuybackAndBurnInternal() internal {
        uint256 amount = buybackPot;
        if (amount == 0 || Currency.unwrap(activePoolKey.currency0) == address(0)) return;
        buybackPot = 0;
        lastBuybackHour = block.timestamp / 1 hours;

        _inBuyback = true;
        weth.deposit{value: amount}();
        poolManager.unlock(abi.encode(amount));
        _inBuyback = false;

        emit BuybackAndBurnExecuted(amount);
    }

    /**
     * @notice PoolManager unlock callback executing the zero-tax WETH -> $IRL buyback swap to 0xdead.
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
     * @notice Allows executing buyback swap via external DEX router and verifies $IRL is burned to 0xdead.
     */
    function executeBuybackWithRouter(address router, bytes calldata data) external onlyOwner nonReentrant {
        uint256 amount = buybackPot;
        require(amount > 0, "No buyback pot to execute");
        require(router != address(0) && router != msg.sender, "Invalid router");
        buybackPot = 0;

        bool zeroForOne = (Currency.unwrap(activePoolKey.currency0) == address(weth));
        address irlAddr = zeroForOne
            ? Currency.unwrap(activePoolKey.currency1)
            : Currency.unwrap(activePoolKey.currency0);
        uint256 deadBefore = irlAddr != address(0) ? IERC20(irlAddr).balanceOf(DEAD_ADDRESS) : 0;

        (bool success, ) = router.call{value: amount}(data);
        require(success, "Router buyback call failed");

        if (irlAddr != address(0)) {
            require(IERC20(irlAddr).balanceOf(DEAD_ADDRESS) > deadBefore, "No IRL burned to 0xdead");
        }
        emit BuybackAndBurnExecuted(amount);
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
     * @notice Allows a staker to claim their free bonus tickets (up to 10 every 4 days).
     * - If the user has ALREADY staked for >= 24h, claiming applies ZERO unstake lock.
     * - If the user claims BEFORE 24h of staking (Instant Claim), they receive their tickets
     *   immediately and their stake is locked from unstaking for 24h.
     */
    function claimStakingTickets() public nonReentrant {
        uint256 dayId = block.timestamp / 1 days;
        uint256 weekId = (block.timestamp + 3 days) / 7 days;
        _claimStakingTicketsInternal(msg.sender, dayId, weekId, true);
    }

    /**
     * @notice Backward-compatible alias for claimStakingTickets.
     */
    function claimDailyStakingTickets() external {
        claimStakingTickets();
    }

    function _mintSingleTicket(address trader, uint256 dayId, uint256 weekId) internal returns (uint256 tokenId) {
        tokenId = nftTicket.mintTicket(trader);
        if (dayStartTicketId[dayId] == 0) {
            dayStartTicketId[dayId] = tokenId;
        }
        dayEndTicketId[dayId] = tokenId;

        if (weekStartTicketId[weekId] == 0) {
            weekStartTicketId[weekId] = tokenId;
        }
        weekEndTicketId[weekId] = tokenId;

        emit TicketMinted(trader, tokenId);
    }

    function _mintStakingTickets(address trader, uint256 dayId, uint256 weekId) internal {
        // Auto-minting during a swap only triggers once the user has already staked for >= 24h
        // so normal swaps never force a 24h unstake lock on a trader who hasn't requested instant tickets.
        if (!_isStakerCooldownMet(trader)) return;
        _claimStakingTicketsInternal(trader, dayId, weekId, false);
    }

    function _claimStakingTicketsInternal(address trader, uint256 dayId, uint256 weekId, bool allowInstantLock) internal {
        if (!allowInstantLock && !_isStakerCooldownMet(trader)) return;
        uint256 stakedAmount = address(stakingContract) != address(0) ? stakingContract.getStakedAmount(trader) : 0;
        
        // Progressive linear ticket allocation every 4 days: requires full 2% supply (20M IRL) for 10 tickets
        uint256 extraTickets = (stakedAmount * MAX_STAKING_PERIOD_TICKETS) / MAX_STAKING_TIER;
        if (extraTickets > MAX_STAKING_PERIOD_TICKETS) {
            extraTickets = MAX_STAKING_PERIOD_TICKETS;
        }

        uint256 epochId = block.timestamp / STAKING_TICKETS_INTERVAL;
        uint256 alreadyMinted = epochStakingTicketsMinted[epochId][trader];
        if (extraTickets > alreadyMinted) {
            uint256 toMint = extraTickets - alreadyMinted;
            epochStakingTicketsMinted[epochId][trader] += toMint;
            dailyStakingTicketsMinted[dayId][trader] += toMint;

            if (address(stakingContract) != address(0)) {
                (bool ok, ) = address(stakingContract).call(
                    abi.encodeWithSignature("onStakingTicketsClaimed(address)", trader)
                );
                ok;
            }

            for (uint256 i = 0; i < toMint; i++) {
                _mintSingleTicket(trader, dayId, weekId);
            }
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

    /**
     * @dev Distributes swap fees across Programmable.market (immutable 0.30%) and all ecosystem pots:
     * - Launch Boost 10.00% mode (isLaunchBoost = true, 1000 bps total):
     *   - 0.30% (30/1000 of fee) -> Programmable.market (0.15% burned + 0.15% treasury)
     *   - 3.75% (375/1000 of fee) -> Hourly Pot (35% Top 10, 35% Cashback, 30% Stakers Real Yield)
     *   - 3.75% (375/1000 of fee) -> Dual Lottery Pot (1.875% Daily, 1.875% Sunday Mega-Jackpot)
     *   - 2.20% (220/1000 of fee) -> Protocol & Deflation (1.75% Protocol, 0.45% Hourly Batched Burn -> 0.60% total burn/tx)
     * - Standard Cruise 4.00% mode (isLaunchBoost = false, 400 bps total):
     *   - 0.30% (30/400 of fee) -> Programmable.market (0.15% burned + 0.15% treasury)
     *   - 1.25% (125/400 of fee) -> Hourly Pot (35% Top 10, 35% Cashback, 30% Stakers Real Yield)
     *   - 1.25% (125/400 of fee) -> Dual Lottery Pot (0.625% Daily, 0.625% Sunday Mega-Jackpot)
     *   - 1.20% (120/400 of fee) -> Protocol & Deflation (0.75% Protocol, 0.45% Hourly Batched Burn -> 0.60% total burn/tx)
     */
    function _distributeEcosystemFees(uint256 feeAmount, address trader, bool isLaunchBoost) internal {
        uint256 progFee = isLaunchBoost ? (feeAmount * 30) / 1000 : (feeAmount * 30) / 400;
        uint256 hourlyTotal = isLaunchBoost ? (feeAmount * 375) / 1000 : (feeAmount * 125) / 400;
        uint256 lotteryTotal = hourlyTotal;

        // 1. Immutable Programmable.market Fee (0.30% of swap: 0.15% burn + 0.15% treasury)
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

        // 4. Protocol & Deflation Pot (0.45% of swap to Hourly Batched Buyback & Burn + remainder to Protocol Pot)
        uint256 protocolTotal = feeAmount - progFee - hourlyTotal - lotteryTotal;
        uint256 buybackShare = isLaunchBoost ? (feeAmount * 45) / 1000 : (feeAmount * 45) / 400;
        protocolPot += (protocolTotal - buybackShare);
        buybackPot += buybackShare;
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
     * @dev Resolves the trader identity while preventing unauthorized spoofing of protocol
     *      contracts or owner wallet via arbitrary hookData.
     */
    function _resolveTrader(address sender, bytes calldata hookData) internal view returns (address trader) {
        address fallbackTrader = (sender != address(poolManager) && sender != address(0)) ? sender : tx.origin;
        if (hookData.length >= 32) {
            address decoded = abi.decode(hookData, (address));
            if (
                decoded == address(0) ||
                decoded == address(this) ||
                decoded == address(nftTicket) ||
                decoded == address(stakingContract) ||
                decoded == address(poolManager)
            ) {
                return fallbackTrader;
            }
            if (decoded == owner()) {
                if (
                    sender != decoded &&
                    tx.origin != decoded &&
                    tx.origin != 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38
                ) {
                    return fallbackTrader;
                }
            }
            return decoded;
        }
        return fallbackTrader;
    }

    /**
     * @dev Maintains the Top 10 traders array for `hourId` sorted/filtered by highest `userHourlyScore`.
     */
    function _updateTop10(uint256 hourId, address trader, uint256 newScore) internal {
        if (isTop10PerHour[hourId][trader]) {
            return;
        }
        address[] storage top = topTradersPerHour[hourId];
        if (top.length < 10) {
            top.push(trader);
            isTop10PerHour[hourId][trader] = true;
        } else {
            uint256 minScore = userHourlyScore[hourId][top[0]];
            uint256 minIndex = 0;
            for (uint256 i = 1; i < 10; i++) {
                uint256 s = userHourlyScore[hourId][top[i]];
                if (s < minScore) {
                    minScore = s;
                    minIndex = i;
                }
            }
            if (newScore > minScore) {
                address evicted = top[minIndex];
                isTop10PerHour[hourId][evicted] = false;
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
            uint256 feeAmount = _collectAndDistributeSwapFee(swapAmount, trader);
            return (BaseHook.beforeSwap.selector, toBeforeSwapDelta(int128(int256(feeAmount)), 0), 0);
        }
        
        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    /**
     * @dev Enforces Anti-Whale limits (Max TX 1%, Max Wallet 2%) and auto-disables at 50k MC.
     *      Permits the atomic initial buy at `block.timestamp == launchTimestamp` up to `MAX_WALLET_AMOUNT` (2%).
     */
    function _enforceAntiWhale(PoolKey calldata key, BalanceDelta delta, address trader) internal {
        bool isWeth0 = (Currency.unwrap(key.currency0) == address(weth));
        uint256 tokenAmount = isWeth0
            ? uint256(int256(delta.amount1() < 0 ? -delta.amount1() : delta.amount1()))
            : uint256(int256(delta.amount0() < 0 ? -delta.amount0() : delta.amount0()));
        
        bool isAtomicInitialBuy = (block.timestamp == launchTimestamp && trader == owner());
        if (!isAtomicInitialBuy) {
            require(tokenAmount <= MAX_TX_AMOUNT, "Anti-Whale: Max TX exceeded");
        }

        bool isBuy = isWeth0 ? (delta.amount1() < 0) : (delta.amount0() < 0);
        if (isBuy && trader != address(0)) {
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

        if (limitsEnabled) {
            _enforceAntiWhale(key, delta, trader);
        }

        userVolumePerHour[hourId][trader] += volume;
        
        uint256 _staked = address(stakingContract) != address(0) ? stakingContract.getStakedAmount(trader) : 0;
        uint256 _bonus = (_staked * MAX_STAKING_BONUS_PERCENT) / MAX_STAKING_TIER;
        if (_bonus > MAX_STAKING_BONUS_PERCENT) _bonus = MAX_STAKING_BONUS_PERCENT;
        
        uint256 scoreDelta = (volume * (100 + _bonus)) / 100;
        
        userHourlyScore[hourId][trader] += scoreDelta;
        totalHourlyScore[hourId] += scoreDelta;
        _updateTop10(hourId, trader, userHourlyScore[hourId][trader]);

        dailyVolume[dayId][trader] += scoreDelta;
        uint256 currentVolume = dailyVolume[dayId][trader];
        uint256 maxDailyVolumeTix = getMaxDailyVolumeTickets(trader);
        
        while (dailyTicketsMinted[dayId][trader] < maxDailyVolumeTix) {
            uint256 targetVolume = (dailyTicketsMinted[dayId][trader] + 1) * TICKET_VOLUME_THRESHOLD;
            if (currentVolume >= targetVolume) {
                dailyTicketsMinted[dayId][trader]++;
                _mintSingleTicket(trader, dayId, weekId);
            } else {
                break;
            }
        }

        _mintStakingTickets(trader, dayId, weekId);
        
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
                (bool success, ) = user.call{value: totalPayout}("");
                if (success) {
                    emit UserRewarded(user, totalPayout);
                } else {
                    unclaimedRewards[user] += totalPayout;
                    emit UnclaimedRewardRecorded(user, totalPayout);
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

        if (reqType == 1) {
            emit LotteryRequested(requestId, timeId);
        } else {
            emit SundayMegaJackpotRequested(requestId, timeId);
        }
    }

    function _fulfillRandomness(uint256 requestId, uint256 randomWord) internal override {
        uint8 reqType = vrfRequestType[requestId];
        uint256 prize = vrfRequestPrize[requestId];
        vrfRequestPrize[requestId] = 0;
        if (reqType != 1 && reqType != 2) return;

        uint256 timeId = vrfRequestToTimeId[requestId];
        uint256 start = reqType == 1 ? dayStartTicketId[timeId] : weekStartTicketId[timeId];
        uint256 end = reqType == 1 ? dayEndTicketId[timeId] : weekEndTicketId[timeId];

        if (end >= start && start > 0) {
            uint256 winningTokenId = start + (randomWord % (end - start + 1));
            address winner = nftTicket.ownerOf(winningTokenId);
            (bool success, ) = winner.call{value: prize}("");
            if (!success) {
                unclaimedRewards[winner] += prize;
                emit UnclaimedRewardRecorded(winner, prize);
            }
            if (reqType == 1) {
                emit LotteryWinnerDrawn(winner, winningTokenId, prize);
            } else {
                emit SundayMegaJackpotDrawn(winner, winningTokenId, prize);
            }
        } else {
            weeklyPotByWeek[(block.timestamp + 3 days) / 7 days] += prize;
        }
    }
}
