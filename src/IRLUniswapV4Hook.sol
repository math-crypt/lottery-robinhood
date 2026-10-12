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

// Local OpenVRF Interface
interface IOpenVRF {
    function requestRandomness(uint32 callbackGasLimit) external payable returns (uint256 id);
    function requestFee() external view returns (uint256);
}

abstract contract IRLRandomnessConsumer {
    IOpenVRF public immutable randomnessRouter;

    constructor(address router) {
        require(router.code.length > 0, "Invalid router");
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

interface IWETH {
    function withdraw(uint wad) external;
}

import {AutomationCompatibleInterface} from "@chainlink/contracts/v0.8/automation/AutomationCompatible.sol";

/**
 * @title IRL Uniswap V4 Hook
 * @dev Implements the Internet Robinhood Lottery ecosystem logic with Programmable.market launch integration:
 * - 4% Constant Tax natively collected in ETH:
 *   - 1% Programmable.market Integration (50% Auto-Burn [0.50% of swap] + 50% Programmable Treasury [0.50% of swap])
 *   - 1% Hourly Volume & Real Yield (35% Top 10, 35% All Traders cashback, 30% Stakers Real Yield in ETH)
 *   - 1% Dual Lottery Engine (50% Daily Strict Window via OpenVRF, 50% Sunday Mega-Jackpot)
 *   - 1% Protocol & Deflation (90% Protocol/Marketing upkeep, 10% Buyback & Burn)
 * - Anti-Whale max tx & auto-removal at target price
 * - OpenVRF verifiable randomness
 * - Aggregator fallback for zero-friction routing (1inch, Paraswap, Odos)
 * - Gas-optimized direct indexing (DoS-proof queue)
 */
contract IRLUniswapV4Hook is BaseHook, AutomationCompatibleInterface, IRLRandomnessConsumer, Ownable, ReentrancyGuard {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    IRLTicketNFT public immutable nftTicket;
    IRLStaking public immutable stakingContract;
    IWETH public immutable weth;

    // --- STORAGE PACKING (1 Slot for Anti-Whale state) ---
    bool public limitsEnabled = true;
    uint160 public disableAntiWhaleSqrtPrice;
    uint32 public callbackGasLimit = 150000;

    uint256 public constant MAX_TX_AMOUNT = 10_000_000 ether; // 1% of 1B supply
    uint256 public constant MAX_WALLET_AMOUNT = 20_000_000 ether; // 2% of 1B supply

    // --- POTS ---
    uint256 public dailyLotteryPot;
    uint256 public sundayMegaPot;
    uint256 public hourlyRewardPot;
    uint256 public protocolPot; // For VRF/Automation fees and Marketing
    uint256 public buybackPot; // 10% of protocol fees reserved for buyback & burn

    // --- PROGRAMMABLE.MARKET INTEGRATION (1% OF SWAP) ---
    address public programmableFeeRecipient;
    uint256 public programmableFeePot;

    // Backward-compatibility view for total lottery pot
    function lotteryPot() external view returns (uint256) {
        return dailyLotteryPot + sundayMegaPot;
    }

    // --- EVENTS (For Telegram Bot indexing & Transparency) ---
    event TicketMinted(address indexed user, uint256 tokenId);
    event HourlyRewardsDistributed(uint256 currentHour, uint256 totalPotDistributed);
    event UserRewarded(address indexed user, uint256 amount);
    event LotteryWinnerDrawn(address indexed winner, uint256 tokenId, uint256 prize);
    event SundayMegaJackpotDrawn(address indexed winner, uint256 tokenId, uint256 prize);
    event LotteryRequested(uint256 requestId, uint256 dayId);
    event SundayMegaJackpotRequested(uint256 requestId, uint256 weekId);
    event BuybackAndBurnExecuted(uint256 ethAmount);
    event ProgrammableFeeTransferred(address indexed recipient, uint256 amount);
    event ProgrammableFeeRecipientUpdated(address indexed newRecipient);

    function setDisableAntiWhalePrice(uint160 _price) external onlyOwner {
        disableAntiWhaleSqrtPrice = _price;
    }

    function setProgrammableFeeRecipient(address _recipient) external onlyOwner {
        programmableFeeRecipient = _recipient;
        emit ProgrammableFeeRecipientUpdated(_recipient);
    }

    function claimProgrammableFees() external nonReentrant {
        uint256 feeToClaim = programmableFeePot;
        if (feeToClaim > 0 && programmableFeeRecipient != address(0)) {
            programmableFeePot = 0;
            (bool success, ) = payable(programmableFeeRecipient).call{value: feeToClaim}("");
            require(success, "Programmable fee transfer failed");
            emit ProgrammableFeeTransferred(programmableFeeRecipient, feeToClaim);
        }
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
    ) BaseHook(_poolManager) IRLRandomnessConsumer(openVrfRouter) Ownable(msg.sender) {
        nftTicket = IRLTicketNFT(_nftTicket);
        stakingContract = IRLStaking(payable(_stakingContract));
        weth = IWETH(_weth);

        lastProcessedHour = block.timestamp / 1 hours;
        lastLotteryDay = block.timestamp / 1 days;
        lastLotteryWeek = (block.timestamp + 3 days) / 7 days;
    }

    receive() external payable {}

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
     * @notice Executes buyback and burn from the reserved 10% protocol fees.
     */
    function executeBuybackAndBurn() external nonReentrant {
        uint256 amount = buybackPot;
        require(amount > 0, "No buyback pot to execute");
        buybackPot = 0;
        
        (bool success, ) = payable(address(0x000000000000000000000000000000000000dEaD)).call{value: amount}("");
        require(success, "Buyback burn failed");
        emit BuybackAndBurnExecuted(amount);
    }

    /**
     * @notice Allows executing buyback swap via external DEX router and burning tokens.
     */
    function executeBuybackWithRouter(address router, bytes calldata data) external onlyOwner nonReentrant {
        uint256 amount = buybackPot;
        require(amount > 0, "No buyback pot to execute");
        buybackPot = 0;
        
        (bool success, ) = router.call{value: amount}(data);
        require(success, "Router buyback call failed");
        emit BuybackAndBurnExecuted(amount);
    }

    /**
     * @notice Allows a user to claim their bonus tickets from staking every 4 days without needing to trade.
     */
    function claimStakingTickets() public nonReentrant {
        uint256 dayId = block.timestamp / 1 days;
        uint256 weekId = (block.timestamp + 3 days) / 7 days;
        _mintStakingTickets(msg.sender, dayId, weekId);
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

            for (uint256 i = 0; i < toMint; i++) {
                _mintSingleTicket(trader, dayId, weekId);
            }
        }
    }

    /**
     * @notice Removes the Anti-Whale launch limits definitively.
     */
    function removeLimits() external onlyOwner {
        limitsEnabled = false;
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
     * @dev Distributes the 4% swap tax across Programmable.market and all ecosystem pots:
     * - 1.0% Programmable.market Fee: Routed to Programmable (which manages 50% Auto-Burn + 50% Treasury)
     * - 1.0% Hourly Stream (35/35/30): 35% Top 10 Volume, 35% Active Swapper Cashback, 30% Stakers Real Yield in ETH
     * - 1.0% Dual Lottery Engine: 50% Daily 24h VRF Draw, 50% Sunday Mega-Jackpot
     * - 1.0% Protocol & Deflation: 90% Gas/Infra/Marketing, 10% Deflationary Buyback & Burn
     */
    function _distributeSwapFees(uint256 feeAmount, address trader) internal {
        uint256 split = feeAmount / 4; // Each 1.0% portion of the 4.0% tax
        
        // 1. Programmable.market Fee (1% of swap):
        // Forwarded directly to Programmable fee recipient (who manages their burn & treasury)
        uint256 progFee = split;
        if (programmableFeeRecipient != address(0) && progFee > 0) {
            (bool success, ) = payable(programmableFeeRecipient).call{value: progFee}("");
            if (!success) {
                programmableFeePot += progFee;
            } else {
                emit ProgrammableFeeTransferred(programmableFeeRecipient, progFee);
            }
        } else {
            programmableFeePot += progFee;
        }

        // 2. Hourly split (1% of swap):
        // 35% Top 10 hourly pot, 35% all traders of the hour, 30% Real Yield stakers
        uint256 stakingShare = (split * 30) / 100;
        uint256 cashbackShare = (split * 35) / 100;
        uint256 top10Share = split - stakingShare - cashbackShare;

        if (stakingShare > 0 && address(stakingContract) != address(0)) {
            stakingContract.distributeYield{value: stakingShare}();
        }

        hourlyRewardPot += top10Share;

        uint256 currentHour = block.timestamp / 1 hours;
        userCashbackPerHour[currentHour][trader] += cashbackShare;
        if (!traderRecordedPerHour[currentHour][trader]) {
            traderRecordedPerHour[currentHour][trader] = true;
            allTradersPerHour[currentHour].push(trader);
        }

        // 3. Lottery split (1% of swap):
        // 50% Daily Lottery (strict 24h window), 50% Sunday Mega-Jackpot (weekly window)
        uint256 sundayShare = split / 2;
        uint256 dailyShare = split - sundayShare;
        dailyLotteryPot += dailyShare;
        sundayMegaPot += sundayShare;

        // 4. Protocol split (1% of swap):
        // 90% Protocol & Marketing pot, 10% Deflationary Buyback & Burn
        uint256 protocolTotal = feeAmount - (3 * split);
        uint256 buybackShare = (protocolTotal * 10) / 100;
        protocolPot += (protocolTotal - buybackShare);
        buybackPot += buybackShare;
    }

    function _beforeSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        bytes calldata hookData
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        bool isExactIn = params.amountSpecified < 0;
        
        // Identify if WETH is the specified token
        bool isWETHSpecified = false;
        if (isExactIn) {
            isWETHSpecified = params.zeroForOne ? Currency.unwrap(key.currency0) == address(weth) : Currency.unwrap(key.currency1) == address(weth);
        } else {
            isWETHSpecified = params.zeroForOne ? Currency.unwrap(key.currency1) == address(weth) : Currency.unwrap(key.currency0) == address(weth);
        }

        if (isWETHSpecified) {
            uint256 swapAmount = params.amountSpecified < 0 ? uint256(-params.amountSpecified) : uint256(params.amountSpecified);
            uint256 feeAmount = (swapAmount * 4) / 100; // 4.0% Total Swap Tax (1.0% Programmable + 3.0% IRL Ecosystem)
            
            Currency feeCurrency = Currency.wrap(address(weth));
            poolManager.take(feeCurrency, address(this), feeAmount);
            
            weth.withdraw(feeAmount);
            
            // Trader identification with aggregator/router fallback
            address trader;
            if (hookData.length >= 32) {
                trader = abi.decode(hookData, (address));
            } else {
                trader = (sender != address(poolManager) && sender != address(0)) ? sender : tx.origin;
            }

            _distributeSwapFees(feeAmount, trader);
            
            BeforeSwapDelta returnDelta = toBeforeSwapDelta(
                int128(int256(feeAmount)), // Specified delta
                0
            );
            return (BaseHook.beforeSwap.selector, returnDelta, 0);
        }
        
        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function _afterSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) internal override returns (bytes4, int128) {
        uint256 hourId = block.timestamp / 1 hours;
        uint256 dayId = block.timestamp / 1 days;
        uint256 weekId = (block.timestamp + 3 days) / 7 days;

        uint256 volume;
        if (key.currency0 == Currency.wrap(address(weth))) {
            volume = uint256(int256(delta.amount0() < 0 ? -delta.amount0() : delta.amount0()));
        } else {
            volume = uint256(int256(delta.amount1() < 0 ? -delta.amount1() : delta.amount1()));
        }
        
        // Tracking trader identity with aggregator/router fallback
        address trader;
        if (hookData.length >= 32) {
            trader = abi.decode(hookData, (address));
        } else {
            trader = (sender != address(poolManager) && sender != address(0)) ? sender : tx.origin;
        }

        // Anti-Whale Auto-Disable with cached PoolId
        if (limitsEnabled) {
            require(volume <= MAX_TX_AMOUNT, "Anti-Whale: Max TX exceeded");
            
            if (disableAntiWhaleSqrtPrice > 0) {
                PoolId poolId = key.toId();
                (uint160 sqrtPriceX96, , , ) = poolManager.getSlot0(poolId);
                if (sqrtPriceX96 >= disableAntiWhaleSqrtPrice) {
                    limitsEnabled = false;
                }
            }
        }

        // Dynamic Score Leaderboard
        userVolumePerHour[hourId][trader] += volume;
        
        uint256 _staked = address(stakingContract) != address(0) ? stakingContract.getStakedAmount(trader) : 0;
        // Progressive multiplier from 0% to +50% requiring the full 2% supply (20M IRL)
        uint256 _bonus = (_staked * MAX_STAKING_BONUS_PERCENT) / MAX_STAKING_TIER;
        if (_bonus > MAX_STAKING_BONUS_PERCENT) _bonus = MAX_STAKING_BONUS_PERCENT;
        
        uint256 scoreMultiplier = 100 + _bonus;
        uint256 scoreDelta = (volume * scoreMultiplier) / 100;
        
        userHourlyScore[hourId][trader] += scoreDelta;
        totalHourlyScore[hourId] += scoreDelta;

        // Volume NFTs (boosted by staking multiplier, bounded by user's daily volume limit 6 to 10)
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

        // Staking NFTs Auto-Mint (Every 4-day epoch)
        _mintStakingTickets(trader, dayId, weekId);
        
        // Fee on unspecified currency
        bool isExactIn = params.amountSpecified < 0;
        bool isWETHUnspecified = false;
        if (isExactIn) {
            isWETHUnspecified = params.zeroForOne ? Currency.unwrap(key.currency1) == address(weth) : Currency.unwrap(key.currency0) == address(weth);
        } else {
            isWETHUnspecified = params.zeroForOne ? Currency.unwrap(key.currency0) == address(weth) : Currency.unwrap(key.currency1) == address(weth);
        }
                                          
        if (isWETHUnspecified) {
            bool outputIsToken0 = params.zeroForOne ? false : true;
            int256 outputAmount = outputIsToken0 ? delta.amount0() : delta.amount1();
            
            uint256 absOutput = uint256(int256(outputAmount > 0 ? outputAmount : -outputAmount));
            uint256 feeAmount = (absOutput * 3) / 100;
            
            Currency feeCurrency = Currency.wrap(address(weth));
            poolManager.take(feeCurrency, address(this), feeAmount);
            
            weth.withdraw(feeAmount);
            
            _distributeSwapFees(feeAmount, trader);
            
            return (BaseHook.afterSwap.selector, int128(int256(feeAmount)));
        }

        return (BaseHook.afterSwap.selector, 0);
    }

    function checkUpkeep(bytes calldata) external view override returns (bool upkeepNeeded, bytes memory performData) {
        uint256 currentHour = block.timestamp / 1 hours;
        uint256 currentDay = block.timestamp / 1 days;
        uint256 currentWeek = (block.timestamp + 3 days) / 7 days;
        
        if (currentHour > lastProcessedHour && queueIndex == queueLength) {
            return (true, abi.encode(uint8(1), 0));
        }
        if (queueIndex < queueLength) {
            return (true, abi.encode(uint8(2), 0));
        }
        if (currentDay > lastLotteryDay) {
            return (true, abi.encode(uint8(3), currentDay));
        }
        if (currentWeek > lastLotteryWeek) {
            return (true, abi.encode(uint8(4), currentWeek));
        }
        
        return (false, "");
    }

    function performUpkeep(bytes calldata performData) external override nonReentrant {
        (uint8 actionType, uint256 timeId) = abi.decode(performData, (uint8, uint256));
        
        if (actionType == 1) {
            distributingHourId = lastProcessedHour;
            _setupHourDistribution(lastProcessedHour);
            lastProcessedHour++;
        } else if (actionType == 2) {
            _processQueueBatch(50);
        } else if (actionType == 3) {
            _triggerDailyLottery(lastLotteryDay);
            lastLotteryDay = timeId;
        } else if (actionType == 4) {
            _triggerSundayMegaJackpot(lastLotteryWeek);
            lastLotteryWeek = timeId;
        }
    }

    function _setupHourDistribution(uint256 hourId) internal {
        uint256 totalReward = hourlyRewardPot;
        hourlyRewardPot = 0;
        
        distributingHourId = hourId;
        queueIndex = 0;
        queueLength = allTradersPerHour[hourId].length;
        
        uint256 tScore = totalHourlyScore[hourId];
        if (tScore > 0) {
            currentHourTotalReward = totalReward;
            currentHourTotalScore = tScore;
        } else {
            currentHourTotalReward = 0;
            currentHourTotalScore = 0;
            protocolPot += totalReward;
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
            
            if (currentHourTotalScore > 0) {
                uint256 userScore = userHourlyScore[hourId][user];
                uint256 potShare = (currentHourTotalReward * userScore) / currentHourTotalScore;
                totalPayout += potShare;
            }
            
            if (totalPayout > 0) {
                (bool success, ) = user.call{value: totalPayout}("");
                if (success) {
                    emit UserRewarded(user, totalPayout);
                } else {
                    protocolPot += totalPayout;
                }
            }
        }
        queueIndex = limit;
    }

    function _triggerDailyLottery(uint256 dayId) internal {
        uint256 fee = randomnessRouter.requestFee();
        uint256 requestId = randomnessRouter.requestRandomness{value: fee}(callbackGasLimit);
        
        vrfRequestType[requestId] = 1; // 1 = Daily
        vrfRequestToTimeId[requestId] = dayId;
        emit LotteryRequested(requestId, dayId);
    }

    function _triggerSundayMegaJackpot(uint256 weekId) internal {
        uint256 fee = randomnessRouter.requestFee();
        uint256 requestId = randomnessRouter.requestRandomness{value: fee}(callbackGasLimit);
        
        vrfRequestType[requestId] = 2; // 2 = Sunday Mega
        vrfRequestToTimeId[requestId] = weekId;
        emit SundayMegaJackpotRequested(requestId, weekId);
    }

    function _fulfillRandomness(uint256 requestId, uint256 randomWord) internal override {
        uint8 reqType = vrfRequestType[requestId];
        
        if (reqType == 1) {
            // Daily Lottery: strictly within the day's tickets
            uint256 dayId = vrfRequestToTimeId[requestId];
            uint256 start = dayStartTicketId[dayId];
            uint256 end = dayEndTicketId[dayId];
            
            if (end >= start && start > 0) {
                uint256 count = end - start + 1;
                uint256 winningTokenId = start + (randomWord % count);
                address winner = nftTicket.ownerOf(winningTokenId);
                
                uint256 prize = dailyLotteryPot;
                dailyLotteryPot = 0;
                
                (bool success, ) = winner.call{value: prize}("");
                if (!success) {
                    // Smart contract winner reverted: route to protocol/marketing pot
                    protocolPot += prize;
                }
                
                emit LotteryWinnerDrawn(winner, winningTokenId, prize);
            } else {
                // No tickets minted today: rollover daily pot to Sunday Mega-Jackpot
                sundayMegaPot += dailyLotteryPot;
                dailyLotteryPot = 0;
            }
        } else if (reqType == 2) {
            // Sunday Mega-Jackpot: all tickets minted from Monday through Sunday
            uint256 weekId = vrfRequestToTimeId[requestId];
            uint256 start = weekStartTicketId[weekId];
            uint256 end = weekEndTicketId[weekId];
            
            if (end >= start && start > 0) {
                uint256 count = end - start + 1;
                uint256 winningTokenId = start + (randomWord % count);
                address winner = nftTicket.ownerOf(winningTokenId);
                
                uint256 prize = sundayMegaPot;
                sundayMegaPot = 0;
                
                (bool success, ) = winner.call{value: prize}("");
                if (!success) {
                    protocolPot += prize;
                }
                
                emit SundayMegaJackpotDrawn(winner, winningTokenId, prize);
            }
        }
    }
}
