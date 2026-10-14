// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager, ModifyLiquidityParams, SwapParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {FixedPoint96} from "@uniswap/v4-core/src/libraries/FixedPoint96.sol";

import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {PositionInfo, PositionInfoLibrary} from "v4-periphery/src/libraries/PositionInfoLibrary.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";

import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IWETHVault {
    function deposit() external payable;
    function transfer(address to, uint256 value) external returns (bool);
}

/**
 * @title IRLMarketingVault
 * @notice Trustless Liquidity Custody & Marketing Vault for Internet Robinhood Lottery ($IRL).
 * Clearly separates:
 * 1. 90% Permanently Locked Liquidity (900,000,000 $IRL, `PERMANENT_LOCKED_SALT`):
 *    Seeded into Uniswap V4 PoolManager with NO withdrawal or decrease function anywhere in the contract.
 *    Its principal is permanently and irreversibly locked on-chain forever.
 * 2. 10% Conditionally Withdrawable Marketing Liquidity (100,000,000 $IRL, `MARKETING_VAULT_SALT`):
 *    Can ONLY be withdrawn once the pool's current tick has strictly crossed the marketing bracket
 *    (`isIrlToken0 ? currentTick >= marketingTickUpper : currentTick <= marketingTickLower`),
 *    mathematically guaranteeing 100% conversion of $IRL into WETH before withdrawal.
 */
contract IRLMarketingVault is IERC721Receiver {
    using StateLibrary for IPoolManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    address public constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;
    bytes32 public constant PERMANENT_LOCKED_SALT = keccak256("IRL_PERMANENT_LOCKED_LP_90");
    bytes32 public constant MARKETING_VAULT_SALT = keccak256("IRL_MARKETING_VAULT_LP_10");

    uint256 public constant PERMANENT_LP_AMOUNT = 900_000_000 ether;
    uint256 public constant MARKETING_LP_AMOUNT = 100_000_000 ether;

    uint8 private constant ACTION_SEED_LP = 1;
    uint8 private constant ACTION_DECREASE_MARKETING_LP = 2;
    uint8 private constant ACTION_INITIAL_BUY = 3;

    address public immutable owner;
    IPoolManager public immutable poolManager;
    IPositionManager public immutable positionManager;
    address public irlToken;

    bool public liquiditySeeded;
    bool public initialBuyExecuted;
    PoolKey public seededPoolKey;

    int24 public permanentTickLower;
    int24 public permanentTickUpper;
    uint128 public permanentLiquidity;

    int24 public marketingTickLower;
    int24 public marketingTickUpper;
    uint128 public marketingLiquidity;

    event PermanentLiquidityLocked(
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        uint256 irlAmount,
        bytes32 salt
    );
    event MarketingLiquiditySeeded(
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        uint256 irlAmount,
        bytes32 salt
    );
    event InitialBuyExecuted(address indexed buyer, uint256 ethIn, uint256 irlOut);
    event LiquidityDecreased(uint256 indexed tokenId, uint256 amount0, uint256 amount1);
    event FeesCollected(uint256 indexed tokenId, uint256 amount0, uint256 amount1);

    constructor(address _poolManager, address _positionManager, address _irlToken) {
        owner = (msg.sender == 0x4e59b44847b379578588920cA78FbF26c0B4956C
            || msg.sender == 0xe21827818Fea1F14d59929CAE36a93c0B44e0aE1) && tx.origin != address(0)
            ? tx.origin
            : msg.sender;
        poolManager = IPoolManager(_poolManager);
        positionManager = IPositionManager(_positionManager);
        irlToken = _irlToken;
    }

    modifier onlyOwner() {
        require(
            msg.sender == owner ||
            (msg.sender == 0xe21827818Fea1F14d59929CAE36a93c0B44e0aE1 && tx.origin == owner),
            "Not owner"
        );
        _;
    }

    function setIrlToken(address _irlToken) external onlyOwner {
        require(irlToken == address(0), "IRL token already set");
        irlToken = _irlToken;
    }

    function _getLiquidityForAmount0(
        uint160 sqrtPriceAX96,
        uint160 sqrtPriceBX96,
        uint256 amount0
    ) internal pure returns (uint128) {
        if (sqrtPriceAX96 > sqrtPriceBX96) (sqrtPriceAX96, sqrtPriceBX96) = (sqrtPriceBX96, sqrtPriceAX96);
        uint256 intermediate = FullMath.mulDiv(sqrtPriceAX96, sqrtPriceBX96, FixedPoint96.Q96);
        return uint128(FullMath.mulDiv(amount0, intermediate, sqrtPriceBX96 - sqrtPriceAX96));
    }

    function _getLiquidityForAmount1(
        uint160 sqrtPriceAX96,
        uint160 sqrtPriceBX96,
        uint256 amount1
    ) internal pure returns (uint128) {
        if (sqrtPriceAX96 > sqrtPriceBX96) (sqrtPriceAX96, sqrtPriceBX96) = (sqrtPriceBX96, sqrtPriceAX96);
        return uint128(FullMath.mulDiv(amount1, FixedPoint96.Q96, sqrtPriceBX96 - sqrtPriceAX96));
    }

    /**
     * @notice Seeds the 90% Permanently Locked Liquidity (900M $IRL) and the 10% Conditionally
     *         Withdrawable Marketing Liquidity (100M $IRL) into the Uniswap V4 pool.
     *         Any residual rounding dust (< 0.00001 $IRL) is permanently burned to 0xdead.
     */
    function seedInitialLiquidity(PoolKey calldata poolKey) external onlyOwner {
        require(!liquiditySeeded, "Liquidity already seeded");
        require(
            IERC20(irlToken).balanceOf(address(this)) >= PERMANENT_LP_AMOUNT + MARKETING_LP_AMOUNT,
            "Insufficient IRL funding"
        );
        liquiditySeeded = true;
        seededPoolKey = poolKey;

        (uint160 sqrtPriceX96, int24 currentTick, , ) = poolManager.getSlot0(poolKey.toId());
        int24 spacing = poolKey.tickSpacing;
        bool isIrl0 = (Currency.unwrap(poolKey.currency0) == irlToken);

        int24 pLower;
        int24 pUpper;
        int24 mLower;
        int24 mUpper;
        uint128 pLiq;
        uint128 mLiq;

        if (isIrl0) {
            int24 rem = currentTick % spacing;
            int24 aligned = currentTick - rem;
            if (aligned <= currentTick) aligned += spacing;
            if (TickMath.getSqrtPriceAtTick(aligned) < sqrtPriceX96) aligned += spacing;

            pLower = aligned;
            pUpper = TickMath.maxUsableTick(spacing);
            mLower = aligned + 24000;
            mUpper = aligned + 48000;

            pLiq = _getLiquidityForAmount0(
                TickMath.getSqrtPriceAtTick(pLower),
                TickMath.getSqrtPriceAtTick(pUpper),
                PERMANENT_LP_AMOUNT - 1e12
            );
            mLiq = _getLiquidityForAmount0(
                TickMath.getSqrtPriceAtTick(mLower),
                TickMath.getSqrtPriceAtTick(mUpper),
                MARKETING_LP_AMOUNT - 1e12
            );
        } else {
            int24 rem = currentTick % spacing;
            int24 aligned = currentTick - rem;
            if (aligned > currentTick) aligned -= spacing;
            if (TickMath.getSqrtPriceAtTick(aligned) > sqrtPriceX96) aligned -= spacing;

            pLower = TickMath.minUsableTick(spacing);
            pUpper = aligned;
            mUpper = aligned - 24000;
            mLower = aligned - 48000;

            pLiq = _getLiquidityForAmount1(
                TickMath.getSqrtPriceAtTick(pLower),
                TickMath.getSqrtPriceAtTick(pUpper),
                PERMANENT_LP_AMOUNT - 1e12
            );
            mLiq = _getLiquidityForAmount1(
                TickMath.getSqrtPriceAtTick(mLower),
                TickMath.getSqrtPriceAtTick(mUpper),
                MARKETING_LP_AMOUNT - 1e12
            );
        }

        permanentTickLower = pLower;
        permanentTickUpper = pUpper;
        permanentLiquidity = pLiq;

        marketingTickLower = mLower;
        marketingTickUpper = mUpper;
        marketingLiquidity = mLiq;

        poolManager.unlock(
            abi.encode(ACTION_SEED_LP, poolKey, pLower, pUpper, pLiq, mLower, mUpper, mLiq)
        );

        uint256 dust = IERC20(irlToken).balanceOf(address(this));
        if (dust > 0) {
            IERC20(irlToken).transfer(DEAD_ADDRESS, dust);
        }

        emit PermanentLiquidityLocked(pLower, pUpper, pLiq, PERMANENT_LP_AMOUNT, PERMANENT_LOCKED_SALT);
        emit MarketingLiquiditySeeded(mLower, mUpper, mLiq, MARKETING_LP_AMOUNT, MARKETING_VAULT_SALT);
    }

    /**
     * @notice Executes the one-time atomic initial buy on the newly seeded Uniswap V4 pool
     *         and sends the purchased $IRL directly to `recipient`.
     */
    function executeInitialBuy(
        PoolKey calldata poolKey,
        address wethAddr,
        uint256 minIrlOut,
        address recipient
    ) external payable onlyOwner returns (uint256 irlBought) {
        require(liquiditySeeded, "Liquidity not seeded");
        require(!initialBuyExecuted, "Initial buy already executed");
        require(msg.value > 0, "Zero ETH sent");
        require(recipient != address(0), "Invalid recipient");
        initialBuyExecuted = true;

        IWETHVault(wethAddr).deposit{value: msg.value}();
        bytes memory res = poolManager.unlock(
            abi.encode(ACTION_INITIAL_BUY, poolKey, wethAddr, msg.value, recipient)
        );
        irlBought = abi.decode(res, (uint256));
        require(irlBought >= minIrlOut, "Insufficient initial buy output");

        emit InitialBuyExecuted(recipient, msg.value, irlBought);
    }

    /**
     * @notice Decreases the 10% Conditionally Withdrawable Marketing Liquidity (`MARKETING_VAULT_SALT`)
     *         ONLY IF the pool's current tick has completely crossed the marketing bracket (100% WETH).
     *         Note: The 90% `PERMANENT_LOCKED_SALT` position has NO decrease function and is locked forever.
     */
    function decreaseMarketingLiquidity(
        uint128 liquidityToRemove,
        address recipient
    ) external onlyOwner {
        require(liquiditySeeded, "Not seeded");
        require(liquidityToRemove > 0 && liquidityToRemove <= marketingLiquidity, "Invalid liquidity");
        require(recipient != address(0), "Invalid recipient");

        (, int24 currentTick, , ) = poolManager.getSlot0(seededPoolKey.toId());
        bool isIrl0 = (Currency.unwrap(seededPoolKey.currency0) == irlToken);
        if (isIrl0) {
            require(
                currentTick >= marketingTickUpper,
                "Market bracket not reached: IRL not yet converted to WETH (tick < tickUpper)"
            );
        } else {
            require(
                currentTick <= marketingTickLower,
                "Market bracket not reached: IRL not yet converted to WETH (tick > tickLower)"
            );
        }

        marketingLiquidity -= liquidityToRemove;
        poolManager.unlock(
            abi.encode(ACTION_DECREASE_MARKETING_LP, liquidityToRemove, recipient)
        );

        emit LiquidityDecreased(0, 0, 0);
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(poolManager), "Only PoolManager");
        uint8 action = abi.decode(data, (uint8));

        if (action == ACTION_SEED_LP) {
            (
                ,
                PoolKey memory poolKey,
                int24 pLower,
                int24 pUpper,
                uint128 pLiq,
                int24 mLower,
                int24 mUpper,
                uint128 mLiq
            ) = abi.decode(data, (uint8, PoolKey, int24, int24, uint128, int24, int24, uint128));

            (BalanceDelta d1, ) = poolManager.modifyLiquidity(
                poolKey,
                ModifyLiquidityParams({
                    tickLower: pLower,
                    tickUpper: pUpper,
                    liquidityDelta: int256(uint256(pLiq)),
                    salt: PERMANENT_LOCKED_SALT
                }),
                ""
            );

            (BalanceDelta d2, ) = poolManager.modifyLiquidity(
                poolKey,
                ModifyLiquidityParams({
                    tickLower: mLower,
                    tickUpper: mUpper,
                    liquidityDelta: int256(uint256(mLiq)),
                    salt: MARKETING_VAULT_SALT
                }),
                ""
            );

            bool isIrl0 = (Currency.unwrap(poolKey.currency0) == irlToken);
            int128 totalIrlDelta = isIrl0
                ? (d1.amount0() + d2.amount0())
                : (d1.amount1() + d2.amount1());
            uint256 irlOwed = uint256(int256(-totalIrlDelta));

            Currency irlCurr = Currency.wrap(irlToken);
            poolManager.sync(irlCurr);
            require(IERC20(irlToken).transfer(address(poolManager), irlOwed), "IRL settle failed");
            poolManager.settle();

            return "";
        } else if (action == ACTION_INITIAL_BUY) {
            (
                ,
                PoolKey memory poolKey,
                address wethAddr,
                uint256 wethAmount,
                address recipient
            ) = abi.decode(data, (uint8, PoolKey, address, uint256, address));

            bool zeroForOne = (Currency.unwrap(poolKey.currency0) == wethAddr);
            uint160 sqrtPriceLimitX96 = zeroForOne
                ? 4295128740
                : 1461446703485210103287273052203988822378723970341;

            BalanceDelta swapDelta = poolManager.swap(
                poolKey,
                SwapParams({
                    zeroForOne: zeroForOne,
                    amountSpecified: -int256(wethAmount),
                    sqrtPriceLimitX96: sqrtPriceLimitX96
                }),
                abi.encode(recipient)
            );

            Currency wethCurr = Currency.wrap(wethAddr);
            poolManager.sync(wethCurr);
            require(IWETHVault(wethAddr).transfer(address(poolManager), wethAmount), "WETH settle failed");
            poolManager.settle();

            Currency irlCurr = zeroForOne ? poolKey.currency1 : poolKey.currency0;
            int128 outDelta = zeroForOne ? swapDelta.amount1() : swapDelta.amount0();
            uint256 irlBought = uint256(int256(outDelta > 0 ? outDelta : -outDelta));
            if (irlBought > 0) {
                poolManager.take(irlCurr, recipient, irlBought);
            }

            return abi.encode(irlBought);
        } else if (action == ACTION_DECREASE_MARKETING_LP) {
            (, uint128 liquidityToRemove, address recipient) = abi.decode(
                data,
                (uint8, uint128, address)
            );

            (BalanceDelta d, ) = poolManager.modifyLiquidity(
                seededPoolKey,
                ModifyLiquidityParams({
                    tickLower: marketingTickLower,
                    tickUpper: marketingTickUpper,
                    liquidityDelta: -int256(uint256(liquidityToRemove)),
                    salt: MARKETING_VAULT_SALT
                }),
                ""
            );

            if (d.amount0() > 0) {
                poolManager.take(seededPoolKey.currency0, recipient, uint256(int256(d.amount0())));
            }
            if (d.amount1() > 0) {
                poolManager.take(seededPoolKey.currency1, recipient, uint256(int256(d.amount1())));
            }

            return "";
        }

        revert("Unknown vault action");
    }

    /**
     * @notice Allows the owner to collect trading fees from any PositionManager marketing NFT position.
     */
    function collectFees(
        uint256 tokenId,
        uint128 amount0Min,
        uint128 amount1Min
    ) external onlyOwner returns (uint256 amount0, uint256 amount1) {
        (PoolKey memory poolKey, ) = positionManager.getPoolAndPositionInfo(tokenId);

        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(tokenId, 0, amount0Min, amount1Min, "");
        params[1] = abi.encode(poolKey.currency0, poolKey.currency1, msg.sender);

        positionManager.modifyLiquidities(
            abi.encode(abi.encodePacked(uint8(Actions.DECREASE_LIQUIDITY), uint8(Actions.TAKE_PAIR)), params),
            type(uint256).max
        );
        
        emit FeesCollected(tokenId, amount0, amount1);
    }

    /**
     * @notice Allows the owner to decrease PositionManager NFT liquidity ONLY IF the position has been fully crossed.
     */
    function decreaseLiquidityAndCollect(
        uint256 tokenId,
        uint128 liquidity,
        uint128 amount0Min,
        uint128 amount1Min
    ) external onlyOwner {
        (PoolKey memory poolKey, PositionInfo info) = positionManager.getPoolAndPositionInfo(tokenId);
        int24 tickUpper = PositionInfoLibrary.tickUpper(info);
        int24 tickLower = PositionInfoLibrary.tickLower(info);

        (, int24 currentTick, , ) = poolManager.getSlot0(poolKey.toId());

        bool isIrlToken0 = (Currency.unwrap(poolKey.currency0) == irlToken);
        if (isIrlToken0) {
            require(currentTick >= tickUpper, "Market bracket not reached: IRL not yet converted to WETH (tick < tickUpper)");
        } else {
            require(currentTick <= tickLower, "Market bracket not reached: IRL not yet converted to WETH (tick > tickLower)");
        }

        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(tokenId, liquidity, amount0Min, amount1Min, "");
        params[1] = abi.encode(poolKey.currency0, poolKey.currency1, msg.sender);

        positionManager.modifyLiquidities(
            abi.encode(abi.encodePacked(uint8(Actions.DECREASE_LIQUIDITY), uint8(Actions.TAKE_PAIR)), params),
            type(uint256).max
        );
        
        emit LiquidityDecreased(tokenId, 0, 0);
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}
