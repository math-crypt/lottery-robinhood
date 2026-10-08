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

import {IRLTicketNFT} from "./IRLTicketNFT.sol";
import {IRLStaking} from "./IRLStaking.sol";

// Chainlink Imports
import {AutomationCompatibleInterface} from "@chainlink/contracts/v0.8/automation/AutomationCompatible.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/v0.8/vrf/VRFConsumerBaseV2.sol";
import {VRFCoordinatorV2Interface} from "@chainlink/contracts/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IWETH {
    function withdraw(uint wad) external;
}

/**
 * @title IRL Uniswap V4 Hook
 * @dev Implements the Lottery Robinhood ecosystem logic: 3% Tax natively collected in ETH, Top 10 Tracking, NFT minting, Automations, VRF and Anti-Whale checks.
 */
contract IRLUniswapV4Hook is BaseHook, AutomationCompatibleInterface, VRFConsumerBaseV2, Ownable, ReentrancyGuard {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    IRLTicketNFT public immutable nftTicket;
    IRLStaking public immutable stakingContract;
    IWETH public immutable weth;

    // --- ANTI-WHALE LIMITS ---
    bool public limitsEnabled = true;
    uint256 public constant MAX_TX_AMOUNT = 10_000_000 ether; // 1% of 1B supply
    uint256 public constant MAX_WALLET_AMOUNT = 20_000_000 ether; // 2% of 1B supply

    // --- POTS (Reward & Lottery) ---
    uint256 public lotteryPot;
    uint256 public hourlyRewardPot;

    // --- PENDING WINNERS ---
    mapping(address => uint256) public pendingWithdrawals;

    // --- EVENTS (For Telegram Bot indexing) ---
    event Top10Updated(address indexed user, uint256 volume, uint256 currentHour);
    event TicketMinted(address indexed user, uint256 tokenId);
    event HourlyRewardsDistributed(uint256 currentHour, uint256 totalPotDistributed);
    event UserRewarded(address indexed user, uint256 amount);
    event LotteryWinnerDrawn(address indexed winner, uint256 tokenId, uint256 prize);
    event LotteryRequested(uint256 requestId, uint256 dayId);

    // --- STATE ---
    uint256 public constant TICKET_VOLUME_THRESHOLD = 0.1 ether;
    uint256 public constant MAX_TICKETS_PER_DAY = 5;

    // Tracking
    mapping(uint256 => mapping(address => uint256)) public userVolumePerHour;
    mapping(uint256 => address[10]) public topTradersPerHour;
    
    // Daily tracking for NFT
    mapping(uint256 => mapping(address => uint256)) public dailyVolume;
    mapping(uint256 => mapping(address => uint256)) public dailyTicketsMinted;

    // Automation Queue State
    uint256 public lastProcessedHour;
    address[] public currentQueue;
    uint256 public queueIndex;
    uint256 public queueRewardPerUser;

    // VRF State
    VRFCoordinatorV2Interface COORDINATOR;
    uint64 s_subscriptionId;
    bytes32 s_keyHash;
    uint32 callbackGasLimit = 100000;
    uint16 requestConfirmations = 3;
    uint32 numWords = 1;

    mapping(uint256 => uint256) public vrfRequestToDayId;
    uint256 public lastLotteryDay;

    constructor(
        IPoolManager _poolManager, 
        address _nftTicket,
        address _stakingContract,
        address vrfCoordinator,
        uint64 subscriptionId,
        bytes32 keyHash,
        address _weth
    ) BaseHook(_poolManager) VRFConsumerBaseV2(vrfCoordinator) Ownable(msg.sender) {
        nftTicket = IRLTicketNFT(_nftTicket);
        stakingContract = IRLStaking(_stakingContract);
        COORDINATOR = VRFCoordinatorV2Interface(vrfCoordinator);
        s_subscriptionId = subscriptionId;
        s_keyHash = keyHash;
        weth = IWETH(_weth);

        lastProcessedHour = block.timestamp / 1 hours;
        lastLotteryDay = block.timestamp / 1 days;
    }

    receive() external payable {}

    function withdrawWinnings() external nonReentrant {
        uint256 amount = pendingWithdrawals[msg.sender];
        require(amount > 0, "No winnings to withdraw");
        pendingWithdrawals[msg.sender] = 0;
        
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "ETH transfer failed");
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

    function _beforeSwap(
        address,
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
            uint256 feeAmount = (swapAmount * 3) / 100;
            
            Currency feeCurrency = Currency.wrap(address(weth));
            poolManager.take(feeCurrency, address(this), feeAmount);
            
            weth.withdraw(feeAmount);
            
            uint256 split = feeAmount / 3;
            lotteryPot += split;
            hourlyRewardPot += split;
            
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

        uint256 volume = uint256(int256(delta.amount0() > 0 ? delta.amount0() : -delta.amount0()));
        
        // Tracking trader identity
        require(hookData.length >= 32, "HookData must contain user address");
        address trader = abi.decode(hookData, (address));

        // Anti-Whale
        if (limitsEnabled) {
            require(volume <= MAX_TX_AMOUNT, "Anti-Whale: Max TX exceeded");
        }

        // Leaderboard
        userVolumePerHour[hourId][trader] += volume;
        _updateTop10(hourId, trader, userVolumePerHour[hourId][trader]);

        // NFTs
        dailyVolume[dayId][trader] += volume;
        uint256 currentVolume = dailyVolume[dayId][trader];
        
        uint256 stakedAmount = address(stakingContract) != address(0) ? stakingContract.getStakedAmount(trader) : 0;
        uint256 maxTicketsForTrader = MAX_TICKETS_PER_DAY + (stakedAmount / 10_000 ether);

        while (dailyTicketsMinted[dayId][trader] < maxTicketsForTrader) {
            uint256 targetVolume = (dailyTicketsMinted[dayId][trader] + 1) * TICKET_VOLUME_THRESHOLD;
            if (currentVolume >= targetVolume) {
                dailyTicketsMinted[dayId][trader]++;
                uint256 tokenId = nftTicket.mintTicket(trader);
                emit TicketMinted(trader, tokenId);
            } else {
                break;
            }
        }
        
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
            
            // Output amount should be positive from pool's perspective if we're taking fees?
            // Actually, delta.amount0() > 0 means the pool received token0.
            // If it's unspecified output, the pool sent it to the user, so outputAmount < 0.
            uint256 absOutput = uint256(int256(outputAmount > 0 ? outputAmount : -outputAmount));
            uint256 feeAmount = (absOutput * 3) / 100;
            
            Currency feeCurrency = Currency.wrap(address(weth));
            poolManager.take(feeCurrency, address(this), feeAmount);
            
            weth.withdraw(feeAmount);
            
            uint256 split = feeAmount / 3;
            lotteryPot += split;
            hourlyRewardPot += split;
            
            return (BaseHook.afterSwap.selector, int128(int256(feeAmount)));
        }

        return (BaseHook.afterSwap.selector, 0);
    }

    function _updateTop10(uint256 hourId, address trader, uint256 newVolume) internal {
        bool inList = false;
        uint256 pos = 10;
        address[10] storage top10 = topTradersPerHour[hourId];

        for (uint256 i = 0; i < 10; i++) {
            if (top10[i] == trader) {
                inList = true;
                pos = i;
                break;
            }
        }

        if (!inList) {
            if (top10[9] == address(0) || newVolume > userVolumePerHour[hourId][top10[9]]) {
                pos = 9;
                top10[9] = trader;
            } else {
                return;
            }
        }

        while (pos > 0) {
            address prevTrader = top10[pos - 1];
            if (prevTrader == address(0) || newVolume > userVolumePerHour[hourId][prevTrader]) {
                top10[pos - 1] = trader;
                top10[pos] = prevTrader;
                pos--;
            } else {
                break;
            }
        }
        
        emit Top10Updated(trader, newVolume, hourId);
    }

    function checkUpkeep(bytes calldata) external view override returns (bool upkeepNeeded, bytes memory performData) {
        uint256 currentHour = block.timestamp / 1 hours;
        uint256 currentDay = block.timestamp / 1 days;
        
        if (currentHour > lastProcessedHour && queueIndex == currentQueue.length) {
            return (true, abi.encode(uint8(1), currentHour));
        }
        if (queueIndex < currentQueue.length) {
            return (true, abi.encode(uint8(2), 0));
        }
        if (currentDay > lastLotteryDay) {
            return (true, abi.encode(uint8(3), currentDay));
        }
        
        return (false, "");
    }

    function performUpkeep(bytes calldata performData) external override nonReentrant {
        (uint8 actionType, uint256 timeId) = abi.decode(performData, (uint8, uint256));
        
        if (actionType == 1) {
            _setupHourDistribution(lastProcessedHour);
            lastProcessedHour = timeId;
        } else if (actionType == 2) {
            _processQueueBatch(50);
        } else if (actionType == 3) {
            _triggerDailyLottery(lastLotteryDay);
            lastLotteryDay = timeId;
        }
    }

    function _setupHourDistribution(uint256 hourId) internal {
        emit HourlyRewardsDistributed(hourId, 0);
    }

    function _processQueueBatch(uint256 batchSize) internal {
        uint256 limit = queueIndex + batchSize;
        if (limit > currentQueue.length) limit = currentQueue.length;

        for (uint256 i = queueIndex; i < limit; i++) {
            address user = currentQueue[i];
            
            uint256 stakedAmount = address(stakingContract) != address(0) ? stakingContract.getStakedAmount(user) : 0;
            uint256 bonusPercentage = (stakedAmount / 10_000 ether);
            if (bonusPercentage > 50) bonusPercentage = 50;
            
            uint256 rewardAmount = queueRewardPerUser + ((queueRewardPerUser * bonusPercentage) / 100);
            
            (bool success, ) = user.call{value: rewardAmount}("");
            if (success) {
                emit UserRewarded(user, rewardAmount);
            }
        }
        queueIndex = limit;
    }

    function _triggerDailyLottery(uint256 dayId) internal {
        uint256 requestId = COORDINATOR.requestRandomWords(
            s_keyHash,
            s_subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            numWords
        );
        vrfRequestToDayId[requestId] = dayId;
        emit LotteryRequested(requestId, dayId);
    }

    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal override {
        uint256 dayId = vrfRequestToDayId[requestId];
        uint256 totalTickets = nftTicket.totalTicketsMinted(); 
        
        if (totalTickets > 0) {
            uint256 winningTokenId = (randomWords[0] % totalTickets) + 1;
            address winner = nftTicket.ownerOf(winningTokenId);
            
            uint256 prize = lotteryPot;
            lotteryPot = 0;
            
            // SECURITY FIX: Use Pull over Push to prevent reverts
            pendingWithdrawals[winner] += prize;
            
            emit LotteryWinnerDrawn(winner, winningTokenId, prize); 
        }
    }
}
