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
    function withdraw(uint256 wad) external;
    function transfer(address to, uint256 value) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

/**
 * @title IRLMarketingVault
 * @notice Trustless Liquidity Custody & 10-Tier Auto-Withdrawing Dev/Marketing Vault for $IRL V2.
 * Clearly separates:
 * 1. 80% Permanently Locked Liquidity (800,000,000 $IRL, `PERMANENT_LOCKED_SALT`):
 *    Seeded into Uniswap V4 PoolManager with NO withdrawal or decrease function anywhere in the contract.
 *    Its principal is permanently and irreversibly locked on-chain forever.
 * 2. 20% Multi-Tier Auto-Withdrawing Dev/Marketing Liquidity (200,000,000 $IRL, `MARKETING_VAULT_SALT` base):
 *    Split into 10 distinct 2% single-sided LP tiers (`20,000,000 $IRL` per tier) at exact Market Cap milestones:
 *    - Tier 0:  $40,000 MC (2.0x initial price, +6960 ticks)
 *    - Tier 1:  $70,000 MC (3.5x initial price, +12540 ticks)
 *    - Tier 2: $100,000 MC (5.0x initial price, +16080 ticks)
 *    - Tier 3: $250,000 MC (12.5x initial price, +25260 ticks)
 *    - Tier 4: $500,000 MC (25.0x initial price, +32220 ticks)
 *    - Tier 5: $750,000 MC (37.5x initial price, +36240 ticks)
 *    - Tier 6: $1,000,000 MC (50.0x initial price, +39120 ticks)
 *    - Tier 7: $1,500,000 MC (75.0x initial price, +43200 ticks)
 *    - Tier 8: $2,000,000 MC (100.0x initial price, +46080 ticks)
 *    - Tier 9: $5,000,000 MC (250.0x initial price, +55200 ticks)
 *    Each tier can ONLY be withdrawn once the pool's current tick has strictly crossed that tier's bracket
 *    (`isIrlToken0 ? currentTick >= tierTickUpper[i] : currentTick <= tierTickLower[i]`),
 *    mathematically guaranteeing 100% conversion of $IRL into WETH/ETH before automatic withdrawal to `owner`.
 */
contract IRLMarketingVault is IERC721Receiver {
    using StateLibrary for IPoolManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    address public constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;
    bytes32 public constant PERMANENT_LOCKED_SALT = keccak256("IRL_PERMANENT_LOCKED_LP_80");
    bytes32 public constant MARKETING_VAULT_SALT = keccak256("IRL_MARKETING_VAULT_LP_20");

    uint256 public constant PERMANENT_LP_AMOUNT = 800_000_000 ether;
    uint256 public constant MARKETING_LP_AMOUNT = 200_000_000 ether;
    uint256 public constant NUM_MARKETING_TIERS = 10;
    uint256 public constant TIER_LP_AMOUNT = 20_000_000 ether; // 2% per tier

    uint8 private constant ACTION_SEED_LP = 1;
    uint8 private constant ACTION_DECREASE_MARKETING_LP = 2;
    uint8 private constant ACTION_INITIAL_BUY = 3;
    uint8 private constant ACTION_WITHDRAW_TIER = 4;

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

    int24[10] public tierTickLower;
    int24[10] public tierTickUpper;
    uint128[10] public tierLiquidity;
    bool[10] public tierWithdrawn;

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
    event MarketingTierSeeded(
        uint256 indexed tierIndex,
        uint256 targetMarketCapUsd,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        bytes32 salt
    );
    event MarketingTierAutoWithdrawn(
        uint256 indexed tierIndex,
        uint256 targetMarketCapUsd,
        uint128 liquidityRemoved,
        uint256 ethDeliveredToOwner,
        address indexed recipient
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

    receive() external payable {}

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

    /**
     * @notice Returns the deterministic salt for each of the 10 marketing LP tiers (0..9).
     */
    function getTierSalt(uint256 tierIndex) public pure returns (bytes32) {
        require(tierIndex < NUM_MARKETING_TIERS, "Invalid tier");
        return keccak256(abi.encodePacked(MARKETING_VAULT_SALT, tierIndex));
    }

    /**
     * @notice Returns the target Market Cap in USD (relative to $20,000 initial launch MC) for tier `tierIndex`.
     */
    function getTierTargetMarketCapUsd(uint256 tierIndex) public pure returns (uint256) {
        require(tierIndex < NUM_MARKETING_TIERS, "Invalid tier");
        if (tierIndex == 0) return 40_000;
        if (tierIndex == 1) return 70_000;
        if (tierIndex == 2) return 100_000;
        if (tierIndex == 3) return 250_000;
        if (tierIndex == 4) return 500_000;
        if (tierIndex == 5) return 750_000;
        if (tierIndex == 6) return 1_000_000;
        if (tierIndex == 7) return 1_500_000;
        if (tierIndex == 8) return 2_000_000;
        return 5_000_000;
    }

    /**
     * @dev Returns the tick offset (multiple of 60) corresponding to each of the 10 Market Cap milestones:
     * 40k (2x -> 6960), 70k (3.5x -> 12540), 100k (5x -> 16080), 250k (12.5x -> 25260),
     * 500k (25x -> 32220), 750k (37.5x -> 36240), 1M (50x -> 39120), 1.5M (75x -> 43200),
     * 2M (100x -> 46080), 5M (250x -> 55200).
     */
    function _getTierTickOffset(uint256 tierIndex) internal pure returns (int24) {
        if (tierIndex == 0) return 6960;
        if (tierIndex == 1) return 12540;
        if (tierIndex == 2) return 16080;
        if (tierIndex == 3) return 25260;
        if (tierIndex == 4) return 32220;
        if (tierIndex == 5) return 36240;
        if (tierIndex == 6) return 39120;
        if (tierIndex == 7) return 43200;
        if (tierIndex == 8) return 46080;
        return 55200;
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
     * @notice Seeds the 80% Permanently Locked Liquidity (800M $IRL) and the 20% 10-Tier
     *         Auto-Withdrawing Dev/Marketing Liquidity (10 x 20M $IRL = 200M $IRL) into the Uniswap V4 pool.
     *         Any residual rounding dust is permanently burned to 0xdead.
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
        uint128 pLiq;
        uint128 totalMLiq = 0;

        if (isIrl0) {
            int24 rem = currentTick % spacing;
            int24 aligned = currentTick - rem;
            if (aligned <= currentTick) aligned += spacing;
            if (TickMath.getSqrtPriceAtTick(aligned) < sqrtPriceX96) aligned += spacing;

            pLower = aligned;
            pUpper = TickMath.maxUsableTick(spacing);

            pLiq = _getLiquidityForAmount0(
                TickMath.getSqrtPriceAtTick(pLower),
                TickMath.getSqrtPriceAtTick(pUpper),
                PERMANENT_LP_AMOUNT - 1e12
            );

            for (uint256 i = 0; i < NUM_MARKETING_TIERS; i++) {
                int24 tUpper = aligned + _getTierTickOffset(i);
                int24 tLower = tUpper - spacing;
                uint128 tLiq = _getLiquidityForAmount0(
                    TickMath.getSqrtPriceAtTick(tLower),
                    TickMath.getSqrtPriceAtTick(tUpper),
                    TIER_LP_AMOUNT - 1e11
                );
                tierTickLower[i] = tLower;
                tierTickUpper[i] = tUpper;
                tierLiquidity[i] = tLiq;
                totalMLiq += tLiq;
            }
            marketingTickLower = tierTickLower[0];
            marketingTickUpper = tierTickUpper[NUM_MARKETING_TIERS - 1];
        } else {
            int24 rem = currentTick % spacing;
            int24 aligned = currentTick - rem;
            if (aligned > currentTick) aligned -= spacing;
            if (TickMath.getSqrtPriceAtTick(aligned) > sqrtPriceX96) aligned -= spacing;

            pLower = TickMath.minUsableTick(spacing);
            pUpper = aligned;

            pLiq = _getLiquidityForAmount1(
                TickMath.getSqrtPriceAtTick(pLower),
                TickMath.getSqrtPriceAtTick(pUpper),
                PERMANENT_LP_AMOUNT - 1e12
            );

            for (uint256 i = 0; i < NUM_MARKETING_TIERS; i++) {
                int24 tLower = aligned - _getTierTickOffset(i);
                int24 tUpper = tLower + spacing;
                uint128 tLiq = _getLiquidityForAmount1(
                    TickMath.getSqrtPriceAtTick(tLower),
                    TickMath.getSqrtPriceAtTick(tUpper),
                    TIER_LP_AMOUNT - 1e11
                );
                tierTickLower[i] = tLower;
                tierTickUpper[i] = tUpper;
                tierLiquidity[i] = tLiq;
                totalMLiq += tLiq;
            }
            marketingTickLower = tierTickLower[NUM_MARKETING_TIERS - 1];
            marketingTickUpper = tierTickUpper[0];
        }

        permanentTickLower = pLower;
        permanentTickUpper = pUpper;
        permanentLiquidity = pLiq;
        marketingLiquidity = totalMLiq;

        poolManager.unlock(abi.encode(ACTION_SEED_LP, poolKey, pLower, pUpper, pLiq));

        uint256 dust = IERC20(irlToken).balanceOf(address(this));
        if (dust > 0) {
            IERC20(irlToken).transfer(DEAD_ADDRESS, dust);
        }

        emit PermanentLiquidityLocked(pLower, pUpper, pLiq, PERMANENT_LP_AMOUNT, PERMANENT_LOCKED_SALT);
        emit MarketingLiquiditySeeded(
            marketingTickLower,
            marketingTickUpper,
            totalMLiq,
            MARKETING_LP_AMOUNT,
            MARKETING_VAULT_SALT
        );
        for (uint256 i = 0; i < NUM_MARKETING_TIERS; i++) {
            emit MarketingTierSeeded(
                i,
                getTierTargetMarketCapUsd(i),
                tierTickLower[i],
                tierTickUpper[i],
                tierLiquidity[i],
                getTierSalt(i)
            );
        }
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
     * @notice Returns true if at least one of the 10 marketing LP tiers has reached its target
     *         Market Cap (100% converted to WETH) and is ready for automatic withdrawal to `owner`.
     */
    function hasWithdrawableTier() public view returns (bool) {
        if (!liquiditySeeded) return false;
        (, int24 currentTick, , ) = poolManager.getSlot0(seededPoolKey.toId());
        bool isIrl0 = (Currency.unwrap(seededPoolKey.currency0) == irlToken);
        for (uint256 i = 0; i < NUM_MARKETING_TIERS; i++) {
            if (!tierWithdrawn[i] && tierLiquidity[i] > 0) {
                bool reached = isIrl0
                    ? (currentTick >= tierTickUpper[i])
                    : (currentTick <= tierTickLower[i]);
                if (reached) return true;
            }
        }
        return false;
    }

    /**
     * @notice Automatically withdraws all reached 2% marketing LP tiers (where the pool price has crossed
     *         the tier's target Market Cap so the position is 100% WETH/ETH), unwraps the WETH into native ETH,
     *         and sends 100% of the proceeds directly to `owner` (dev wallet).
     *         Can be triggered automatically by the V4 Hook upkeep/buyback or called directly by anyone.
     * @return tiersWithdrawnCount Number of tiers withdrawn in this call.
     * @return totalEthDelivered Total WETH/ETH delivered to `owner`.
     */
    function autoWithdrawReachedTiers() public returns (uint256 tiersWithdrawnCount, uint256 totalEthDelivered) {
        if (!liquiditySeeded) return (0, 0);
        (, int24 currentTick, , ) = poolManager.getSlot0(seededPoolKey.toId());
        bool isIrl0 = (Currency.unwrap(seededPoolKey.currency0) == irlToken);

        for (uint256 i = 0; i < NUM_MARKETING_TIERS; i++) {
            if (!tierWithdrawn[i] && tierLiquidity[i] > 0) {
                bool reached = isIrl0
                    ? (currentTick >= tierTickUpper[i])
                    : (currentTick <= tierTickLower[i]);
                if (reached) {
                    uint128 liq = tierLiquidity[i];
                    tierWithdrawn[i] = true;
                    tierLiquidity[i] = 0;
                    if (marketingLiquidity >= liq) {
                        marketingLiquidity -= liq;
                    } else {
                        marketingLiquidity = 0;
                    }

                    bytes memory res = poolManager.unlock(
                        abi.encode(ACTION_WITHDRAW_TIER, i, liq, owner)
                    );
                    uint256 ethOut = abi.decode(res, (uint256));
                    tiersWithdrawnCount++;
                    totalEthDelivered += ethOut;

                    emit MarketingTierAutoWithdrawn(
                        i,
                        getTierTargetMarketCapUsd(i),
                        liq,
                        ethOut,
                        owner
                    );
                }
            }
        }
    }

    /**
     * @notice Decreases a specific tier or the first available reached tier of the 20% Marketing Liquidity
     *         ONLY IF the pool's current tick has completely crossed that tier's bracket (100% WETH).
     *         Note: The 80% `PERMANENT_LOCKED_SALT` position has NO decrease function and is locked forever.
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

        uint256 targetTier = type(uint256).max;
        for (uint256 i = 0; i < NUM_MARKETING_TIERS; i++) {
            if (!tierWithdrawn[i] && tierLiquidity[i] >= liquidityToRemove) {
                bool reached = isIrl0
                    ? (currentTick >= tierTickUpper[i])
                    : (currentTick <= tierTickLower[i]);
                if (reached) {
                    targetTier = i;
                    break;
                }
            }
        }
        require(
            targetTier != type(uint256).max,
            "Market bracket not reached: IRL not yet converted to WETH"
        );

        tierLiquidity[targetTier] -= liquidityToRemove;
        if (tierLiquidity[targetTier] == 0) {
            tierWithdrawn[targetTier] = true;
        }
        marketingLiquidity -= liquidityToRemove;

        poolManager.unlock(
            abi.encode(ACTION_DECREASE_MARKETING_LP, targetTier, liquidityToRemove, recipient)
        );

        emit LiquidityDecreased(targetTier, 0, 0);
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
                uint128 pLiq
            ) = abi.decode(data, (uint8, PoolKey, int24, int24, uint128));

            (BalanceDelta dPerm, ) = poolManager.modifyLiquidity(
                poolKey,
                ModifyLiquidityParams({
                    tickLower: pLower,
                    tickUpper: pUpper,
                    liquidityDelta: int256(uint256(pLiq)),
                    salt: PERMANENT_LOCKED_SALT
                }),
                ""
            );

            bool isIrl0 = (Currency.unwrap(poolKey.currency0) == irlToken);
            int128 totalIrlDelta = isIrl0 ? dPerm.amount0() : dPerm.amount1();

            for (uint256 i = 0; i < NUM_MARKETING_TIERS; i++) {
                (BalanceDelta dTier, ) = poolManager.modifyLiquidity(
                    poolKey,
                    ModifyLiquidityParams({
                        tickLower: tierTickLower[i],
                        tickUpper: tierTickUpper[i],
                        liquidityDelta: int256(uint256(tierLiquidity[i])),
                        salt: getTierSalt(i)
                    }),
                    ""
                );
                totalIrlDelta += isIrl0 ? dTier.amount0() : dTier.amount1();
            }

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
        } else if (action == ACTION_WITHDRAW_TIER) {
            (, uint256 tierIndex, uint128 liquidityToRemove, address recipient) = abi.decode(
                data,
                (uint8, uint256, uint128, address)
            );

            (BalanceDelta d, ) = poolManager.modifyLiquidity(
                seededPoolKey,
                ModifyLiquidityParams({
                    tickLower: tierTickLower[tierIndex],
                    tickUpper: tierTickUpper[tierIndex],
                    liquidityDelta: -int256(uint256(liquidityToRemove)),
                    salt: getTierSalt(tierIndex)
                }),
                ""
            );

            bool isIrl0 = (Currency.unwrap(seededPoolKey.currency0) == irlToken);
            Currency wethCurr = isIrl0 ? seededPoolKey.currency1 : seededPoolKey.currency0;
            Currency irlCurr = isIrl0 ? seededPoolKey.currency0 : seededPoolKey.currency1;
            int128 wethDelta = isIrl0 ? d.amount1() : d.amount0();
            int128 irlDelta = isIrl0 ? d.amount0() : d.amount1();

            // Burn any microscopic rounding dust of IRL if present
            if (irlDelta > 0) {
                poolManager.take(irlCurr, DEAD_ADDRESS, uint256(int256(irlDelta)));
            }

            uint256 wethAmount = wethDelta > 0 ? uint256(int256(wethDelta)) : 0;
            if (wethAmount > 0) {
                address wethAddr = Currency.unwrap(wethCurr);
                poolManager.take(wethCurr, address(this), wethAmount);
                try IWETHVault(wethAddr).withdraw(wethAmount) {
                    (bool ok, ) = payable(recipient).call{value: wethAmount}("");
                    if (!ok) {
                        IWETHVault(wethAddr).deposit{value: wethAmount}();
                        require(IWETHVault(wethAddr).transfer(recipient, wethAmount), "WETH fallback failed");
                    }
                } catch {
                    require(IWETHVault(wethAddr).transfer(recipient, wethAmount), "WETH transfer failed");
                }
            }

            return abi.encode(wethAmount);
        } else if (action == ACTION_DECREASE_MARKETING_LP) {
            (, uint256 tierIndex, uint128 liquidityToRemove, address recipient) = abi.decode(
                data,
                (uint8, uint256, uint128, address)
            );

            (BalanceDelta d, ) = poolManager.modifyLiquidity(
                seededPoolKey,
                ModifyLiquidityParams({
                    tickLower: tierTickLower[tierIndex],
                    tickUpper: tierTickUpper[tierIndex],
                    liquidityDelta: -int256(uint256(liquidityToRemove)),
                    salt: getTierSalt(tierIndex)
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
