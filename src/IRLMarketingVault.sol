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
    address public irlToken;

    event LiquidityDecreased(uint256 indexed tokenId, uint256 amount0, uint256 amount1);
    event FeesCollected(uint256 indexed tokenId, uint256 amount0, uint256 amount1);

    constructor(address _poolManager, address _positionManager, address _irlToken) {
        owner = msg.sender;
        poolManager = IPoolManager(_poolManager);
        positionManager = IPositionManager(_positionManager);
        irlToken = _irlToken;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    function setIrlToken(address _irlToken) external onlyOwner {
        require(irlToken == address(0), "IRL token already set");
        irlToken = _irlToken;
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
        int24 tickLower = PositionInfoLibrary.tickLower(info);

        // 2. Get current pool tick
        (, int24 currentTick, , ) = poolManager.getSlot0(poolKey.toId());

        // 3. Mathematical Rug-Proof Guarantee:
        // Position must be strictly 100% converted into WETH!
        bool isIrlToken0 = (Currency.unwrap(poolKey.currency0) == irlToken);
        if (isIrlToken0) {
            // Price = WETH / IRL. When IRL pumps, price & tick go UP.
            // When currentTick >= tickUpper, 100% of IRL has been bought by market and converted into WETH.
            require(currentTick >= tickUpper, "Market bracket not reached: IRL not yet converted to WETH (tick < tickUpper)");
        } else {
            // Price = IRL / WETH. When IRL pumps, price & tick go DOWN.
            // When currentTick <= tickLower, 100% of IRL has been bought by market and converted into WETH.
            require(currentTick <= tickLower, "Market bracket not reached: IRL not yet converted to WETH (tick > tickLower)");
        }

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
