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

// Interfaces from Chainlink (Will be properly imported via remappings)
// import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/automation/AutomationCompatible.sol";
// import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";

/**
 * @title IRL Uniswap V4 Hook
 * @dev Implements the Lottery Robinhood ecosystem logic: 3% Tax, Top 10 Tracking, NFT minting.
 */
contract IRLUniswapV4Hook is BaseHook {
    using PoolIdLibrary for PoolKey;

    IRLTicketNFT public immutable nftTicket;

    // --- EVENTS (For Telegram Bot indexing) ---
    event Top10Updated(address indexed user, uint256 volume, uint256 currentHour);
    event TicketMinted(address indexed user, uint256 tokenId);
    event HourlyRewardsDistributed(uint256 currentHour, uint256 totalPotDistributed);
    event UserRewarded(address indexed user, uint256 amount);
    event LotteryWinnerDrawn(address indexed winner, uint256 tokenId, uint256 prize);

    // --- STATE ---
    // Constants
    uint256 public constant TICKET_VOLUME_THRESHOLD = 0.1 ether;
    uint256 public constant MAX_TICKETS_PER_DAY = 5;

    // Tracking
    mapping(uint256 => mapping(address => uint256)) public userVolumePerHour;
    mapping(uint256 => address[10]) public topTradersPerHour;
    
    // Daily tracking for NFT
    mapping(uint256 => mapping(address => uint256)) public dailyVolume;
    mapping(uint256 => mapping(address => uint256)) public dailyTicketsMinted;

    constructor(IPoolManager _poolManager, address _nftTicket) BaseHook(_poolManager) {
        nftTicket = IRLTicketNFT(_nftTicket);
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
            afterSwap: true, // We intercept after swap for tracking and tax extraction
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

        // Extract volume from delta (simplified)
        uint256 volume = uint256(int256(delta.amount0() > 0 ? delta.amount0() : -delta.amount0()));
        
        address trader = tx.origin; // In a real hook, we might use hookData to identify the actual swapper if interacting via a router

        // Update hourly volume
        userVolumePerHour[hourId][trader] += volume;
        
        // --- TOP 10 LOGIC ---
        _updateTop10(hourId, trader, userVolumePerHour[hourId][trader]);

        // --- NFT TICKET LOGIC ---
        dailyVolume[dayId][trader] += volume;
        if (dailyTicketsMinted[dayId][trader] < MAX_TICKETS_PER_DAY) {
            uint256 currentVolume = dailyVolume[dayId][trader];
            uint256 targetVolume = (dailyTicketsMinted[dayId][trader] + 1) * TICKET_VOLUME_THRESHOLD;
            if (currentVolume >= targetVolume) {
                dailyTicketsMinted[dayId][trader]++;
                uint256 tokenId = nftTicket.mintTicket(trader);
                emit TicketMinted(trader, tokenId);
            }
        }

        // TODO: Swap and Liquify (extract 3% tax, swap to WETH via PoolManager)

        return (BaseHook.afterSwap.selector, 0);
    }

    function _updateTop10(uint256 hourId, address trader, uint256 newVolume) internal {
        // Simple insertion sort logic for a size-10 array
        bool inList = false;
        uint256 pos = 10;
        
        address[10] storage top10 = topTradersPerHour[hourId];

        // Find if user is already in list
        for (uint256 i = 0; i < 10; i++) {
            if (top10[i] == trader) {
                inList = true;
                pos = i;
                break;
            }
        }

        // If not in list, find if they beat the 10th
        if (!inList) {
            if (top10[9] == address(0) || newVolume > userVolumePerHour[hourId][top10[9]]) {
                pos = 9;
                top10[9] = trader;
            } else {
                return; // Not in top 10
            }
        }

        // Bubble up
        while (pos > 0) {
            address prevTrader = top10[pos - 1];
            if (prevTrader == address(0) || newVolume > userVolumePerHour[hourId][prevTrader]) {
                // Swap
                top10[pos - 1] = trader;
                top10[pos] = prevTrader;
                pos--;
            } else {
                break;
            }
        }
        
        emit Top10Updated(trader, newVolume, hourId);
    }

}
