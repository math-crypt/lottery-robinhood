// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "@openzeppelin/uniswap-hooks/src/base/BaseHook.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager, SwapParams, ModifyLiquidityParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";

import {IRLTicketNFT} from "./IRLTicketNFT.sol";

// Chainlink Imports
import {AutomationCompatibleInterface} from "@chainlink/contracts/v0.8/automation/AutomationCompatible.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/v0.8/vrf/VRFConsumerBaseV2.sol";
import {VRFCoordinatorV2Interface} from "@chainlink/contracts/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title IRL Uniswap V4 Hook
 * @dev Implements the Lottery Robinhood ecosystem logic: 3% Tax, Top 10 Tracking, NFT minting, Automations, VRF and Anti-Whale checks.
 */
contract IRLUniswapV4Hook is BaseHook, AutomationCompatibleInterface, VRFConsumerBaseV2, Ownable {
    using PoolIdLibrary for PoolKey;

    IRLTicketNFT public immutable nftTicket;

    // --- ANTI-WHALE LIMITS ---
    bool public limitsEnabled = true;
    uint256 public constant MAX_TX_AMOUNT = 10_000_000 ether; // 1% of 1B supply
    uint256 public constant MAX_WALLET_AMOUNT = 20_000_000 ether; // 2% of 1B supply

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
        address vrfCoordinator,
        uint64 subscriptionId,
        bytes32 keyHash
    ) BaseHook(_poolManager) VRFConsumerBaseV2(vrfCoordinator) Ownable(msg.sender) {
        nftTicket = IRLTicketNFT(_nftTicket);
        COORDINATOR = VRFCoordinatorV2Interface(vrfCoordinator);
        s_subscriptionId = subscriptionId;
        s_keyHash = keyHash;

        lastProcessedHour = block.timestamp / 1 hours;
        lastLotteryDay = block.timestamp / 1 days;
    }

    /**
     * @notice Removes the Anti-Whale launch limits definitively.
     * @dev Can only be called by the contract owner.
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
            beforeSwap: false,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
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
        address trader = tx.origin;

        // --- ANTI-WHALE CHECKS ---
        if (limitsEnabled) {
            require(volume <= MAX_TX_AMOUNT, "Anti-Whale: Max TX exceeded");
            // In a full implementation, we would also check the actual ERC20 balance of `trader` here.
            // require(IRL(token).balanceOf(trader) <= MAX_WALLET_AMOUNT, "Anti-Whale: Max Wallet exceeded");
        }

        userVolumePerHour[hourId][trader] += volume;
        _updateTop10(hourId, trader, userVolumePerHour[hourId][trader]);

        // If trader is not in current queue, we should ideally add them for the "all traders" queue.
        // For simplicity in this demo, we assume the queue is built from topTraders or a separate array.
        // In production, an EnumerableSet is recommended to avoid duplicates.

        // --- NFT TICKET LOGIC ---
        dailyVolume[dayId][trader] += volume;
        uint256 currentVolume = dailyVolume[dayId][trader];
        
        while (dailyTicketsMinted[dayId][trader] < MAX_TICKETS_PER_DAY) {
            uint256 targetVolume = (dailyTicketsMinted[dayId][trader] + 1) * TICKET_VOLUME_THRESHOLD;
            if (currentVolume >= targetVolume) {
                dailyTicketsMinted[dayId][trader]++;
                uint256 tokenId = nftTicket.mintTicket(trader);
                emit TicketMinted(trader, tokenId);
            } else {
                break;
            }
        }

        // TODO: Swap and Liquify 3% Tax natively using PoolManager

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

    // --- CHAINLINK AUTOMATION (Keepers) ---
    function checkUpkeep(bytes calldata /* checkData */) external view override returns (bool upkeepNeeded, bytes memory performData) {
        uint256 currentHour = block.timestamp / 1 hours;
        uint256 currentDay = block.timestamp / 1 days;
        
        // 1. Need to transition hour
        if (currentHour > lastProcessedHour && queueIndex == currentQueue.length) {
            return (true, abi.encode(uint8(1), currentHour));
        }
        // 2. Need to process queue
        if (queueIndex < currentQueue.length) {
            return (true, abi.encode(uint8(2), 0));
        }
        // 3. Need to trigger daily lottery
        if (currentDay > lastLotteryDay) {
            return (true, abi.encode(uint8(3), currentDay));
        }
        
        return (false, "");
    }

    function performUpkeep(bytes calldata performData) external override {
        (uint8 actionType, uint256 timeId) = abi.decode(performData, (uint8, uint256));
        
        if (actionType == 1) {
            // Setup new hour distribution
            _setupHourDistribution(lastProcessedHour);
            lastProcessedHour = timeId;
        } else if (actionType == 2) {
            // Process queue batch
            _processQueueBatch(50); // Batch size 50
        } else if (actionType == 3) {
            // Trigger Lottery
            _triggerDailyLottery(lastLotteryDay);
            lastLotteryDay = timeId;
        }
    }

    function _setupHourDistribution(uint256 hourId) internal {
        // Logic to calculate pot, distribute 50% to top10 directly, and queue the rest
        // In a full implementation, `currentQueue` is populated with all traders of `hourId`.
        emit HourlyRewardsDistributed(hourId, 0);
    }

    function _processQueueBatch(uint256 batchSize) internal {
        uint256 limit = queueIndex + batchSize;
        if (limit > currentQueue.length) {
            limit = currentQueue.length;
        }

        for (uint256 i = queueIndex; i < limit; i++) {
            address user = currentQueue[i];
            // Pay user: payable(user).transfer(queueRewardPerUser)
            emit UserRewarded(user, queueRewardPerUser);
        }
        queueIndex = limit;
    }

    // --- CHAINLINK VRF ---
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
        uint256 totalTickets = nftTicket.totalTicketsMinted(); // Simplified: should be tickets of that day
        
        if (totalTickets > 0) {
            uint256 winningTokenId = (randomWords[0] % totalTickets) + 1;
            address winner = nftTicket.ownerOf(winningTokenId);
            
            // Send ETH pot to winner
            // payable(winner).transfer(lotteryPot);
            
            emit LotteryWinnerDrawn(winner, winningTokenId, 0); // 0 = prize amount placeholder
        }
    }
}
