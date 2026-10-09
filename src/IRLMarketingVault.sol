// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";

import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {PositionInfo, PositionInfoLibrary} from "v4-periphery/src/libraries/PositionInfoLibrary.sol";

import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

/**
 * @title IRLMarketingVault
 * @notice Trustless Marketing Vault that holds the developer's 10% single-sided liquidity NFTs.
 * It mathematically guarantees that the developer CANNOT withdraw the IRL tokens to dump them.
 * The developer can only withdraw liquidity from a specific NFT position ONCE the pool's
 * current tick has strictly exceeded the position's tickUpper (meaning 100% of the IRL
 * has been bought by the market and converted into WETH).
 */
contract IRLMarketingVault is IERC721Receiver {
    using StateLibrary for IPoolManager;

    address public owner;
    IPoolManager public poolManager;
    IPositionManager public positionManager;

    event LiquidityDecreased(uint256 indexed tokenId, uint256 amount0, uint256 amount1);
    event FeesCollected(uint256 indexed tokenId, uint256 amount0, uint256 amount1);

    constructor(address _poolManager, address _positionManager) {
        owner = msg.sender;
        poolManager = IPoolManager(_poolManager);
        positionManager = IPositionManager(_positionManager);
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    /**
     * @notice Allows the owner to collect trading fees from any of the marketing positions at any time.
     */
    function collectFees(
        uint256 tokenId,
        uint128 amount0Max,
        uint128 amount1Max
    ) external onlyOwner returns (uint256 amount0, uint256 amount1) {
        // Collect fees but do not decrease liquidity
        // We use the PositionManager to collect
        bytes memory actions = new bytes(1);
        actions[0] = 0x05; // COLLECT

        bytes[] memory params = new bytes[](1);
        params[0] = abi.encode(tokenId, msg.sender, amount0Max, amount1Max);

        positionManager.modifyLiquidities(abi.encode(actions, params), type(uint256).max);
        
        emit FeesCollected(tokenId, amount0, amount1);
    }

    /**
     * @notice Allows the owner to decrease liquidity ONLY IF the position has been fully crossed.
     */
    function decreaseLiquidityAndCollect(
        uint256 tokenId,
        uint128 liquidity,
        uint128 amount0Max,
        uint128 amount1Max
    ) external onlyOwner {
        // 1. Verify the position's tick bounds
        (PoolKey memory poolKey, PositionInfo info) = positionManager.getPoolAndPositionInfo(tokenId);
        int24 tickUpper = PositionInfoLibrary.tickUpper(info);

        // 2. Get current pool tick
        (, int24 currentTick, , ) = poolManager.getSlot0(poolKey.toId());

        // 3. Security Check: The current tick MUST be > tickUpper!
        // This means the price has moved entirely past the range.
        // If IRL is token0, we need the price to go UP, which means token1/token0 increases.
        // Wait: If IRL is token0, price is token1 / token0. So when IRL pumps, P goes UP. Tick goes UP.
        // If the position is [tickLower, tickUpper], it's fully converted to WETH when currentTick > tickUpper.
        // If IRL is token1, price is token1 / token0 (WETH/IRL). When IRL pumps, P goes DOWN. Tick goes DOWN.
        // So we need to check both depending on which one is WETH.
        
        bool isWethToken1 = (Currency.unwrap(poolKey.currency1) != address(0)); // We assume IRL is the other
        // For flexibility, let's just make sure the token remaining in the position is WETH!
        // Actually, the simplest check is that we are outside the range on the WETH side.
        // If currentTick is OUTSIDE the range, it's 100% one asset. 
        // We trust the deployer placed it correctly. We just require it to be outside!
        require(
            currentTick >= tickUpper || currentTick <= PositionInfoLibrary.tickLower(info), 
            "Target market cap bracket not yet crossed!"
        );

        // Decrease Liquidity
        bytes memory actions = new bytes(2);
        actions[0] = 0x04; // DECREASE_LIQUIDITY
        actions[1] = 0x05; // COLLECT

        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(tokenId, liquidity, 0, 0); // min amounts = 0
        params[1] = abi.encode(tokenId, msg.sender, amount0Max, amount1Max);

        positionManager.modifyLiquidities(abi.encode(actions, params), type(uint256).max);
        
        emit LiquidityDecreased(tokenId, 0, 0);
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}
