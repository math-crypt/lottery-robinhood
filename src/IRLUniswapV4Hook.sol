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
    uint256 public protocolPot; // For VRF/Automation fees and Marketing

    // --- EVENTS (For Telegram Bot indexing) ---
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
    mapping(uint256 => mapping(address => uint256)) public userHourlyScore;
    mapping(uint256 => uint256) public totalHourlyScore;
    mapping(uint256 => mapping(address => uint256)) public userCashbackPerHour;
    mapping(uint256 => address[]) public allTradersPerHour;
    mapping(uint256 => mapping(address => bool)) public traderRecordedPerHour;
    
    mapping(uint256 => mapping(address => uint256)) public userCashbackPerHour;
    mapping(uint256 => address[]) public allTradersPerHour;
    mapping(uint256 => mapping(address => bool)) public traderRecordedPerHour;
    
    // Daily tracking for NFT
    mapping(uint256 => mapping(address => uint256)) public dailyVolume;
    mapping(uint256 => mapping(address => uint256)) public dailyTicketsMinted;

    // Automation Queue State
    uint256 public lastProcessedHour;
    address[] public currentQueue;
    uint256 public queueIndex;
    uint256 public currentHourTotalReward;
    uint256 public currentHourTotalScore;

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

    /**
     * @notice Allows the owner to withdraw the protocol/marketing share of the tax (1%)
     * @dev Used to fund VRF and Automation upkeep
     */
    function withdrawProtocolFees() external onlyOwner nonReentrant {
        uint256 amount = protocolPot;
        require(amount > 0, "No fees to withdraw");
        protocolPot = 0;
        
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
            
            require(hookData.length >= 32, "HookData must contain user address");
            address trader = abi.decode(hookData, (address));

            uint256 split = feeAmount / 3;
            uint256 cashback = split / 2;
            uint256 top10 = split - cashback;
            
            lotteryPot += split;
            protocolPot += split;
            hourlyRewardPot += top10;
            
            uint256 currentHour = block.timestamp / 1 hours;
            userCashbackPerHour[currentHour][trader] += cashback;
            if (!traderRecordedPerHour[currentHour][trader]) {
                traderRecordedPerHour[currentHour][trader] = true;
                allTradersPerHour[currentHour].push(trader);
            }
            
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

        // Dynamic Score Leaderboard
        userVolumePerHour[hourId][trader] += volume;
        
        uint256 _staked = address(stakingContract) != address(0) ? stakingContract.getStakedAmount(trader) : 0;
        uint256 _bonus = (_staked / 10_000 ether);
        if (_bonus > 50) _bonus = 50;
        
        uint256 scoreMultiplier = 100 + _bonus;
        uint256 scoreDelta = (volume * scoreMultiplier) / 100;
        
        userHourlyScore[hourId][trader] += scoreDelta;
        totalHourlyScore[hourId] += scoreDelta;

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
            uint256 cashback = split / 2;
            uint256 top10 = split - cashback;
            
            lotteryPot += split;
            protocolPot += split;
            hourlyRewardPot += top10;
            
            uint256 currentHour = block.timestamp / 1 hours;
            userCashbackPerHour[currentHour][trader] += cashback;
            if (!traderRecordedPerHour[currentHour][trader]) {
                traderRecordedPerHour[currentHour][trader] = true;
                allTradersPerHour[currentHour].push(trader);
            }
            
            return (BaseHook.afterSwap.selector, int128(int256(feeAmount)));
        }

        return (BaseHook.afterSwap.selector, 0);
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
        uint256 totalReward = hourlyRewardPot;
        hourlyRewardPot = 0;
        
        address[] memory traders = allTradersPerHour[hourId];
        delete currentQueue;
        
        for (uint256 i = 0; i < traders.length; i++) {
            currentQueue.push(traders[i]);
        }
        
        uint256 tScore = totalHourlyScore[hourId];
        if (tScore > 0) {
            currentHourTotalReward = totalReward;
            currentHourTotalScore = tScore;
        } else {
            currentHourTotalReward = 0;
            currentHourTotalScore = 0;
            protocolPot += totalReward;
        }
        
        queueIndex = 0;
        emit HourlyRewardsDistributed(hourId, totalReward);
    }

    function _processQueueBatch(uint256 batchSize) internal {
        uint256 limit = queueIndex + batchSize;
        if (limit > currentQueue.length) limit = currentQueue.length;

        uint256 hourId = lastProcessedHour;

        for (uint256 i = queueIndex; i < limit; i++) {
            address user = currentQueue[i];
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
            
            // Push pattern: If the winner is a smart contract that reverts, they lose the prize.
            // The ETH remains in the contract and is implicitly collected by `withdrawProtocolFees()`.
            (bool success, ) = winner.call{value: prize}("");
            if (!success) {
                // Optionally log failure, but do not revert the VRF callback.
            }
            
            emit LotteryWinnerDrawn(winner, winningTokenId, prize); 
        }
    }
}
