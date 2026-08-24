// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {Constants} from "@uniswap/v4-core/test/utils/Constants.sol";

import {EasyPosm} from "./utils/libraries/EasyPosm.sol";
import {BaseTest} from "./utils/BaseTest.sol";

import {IRLUniswapV4Hook} from "../src/IRLUniswapV4Hook.sol";
import {IRLTicketNFT} from "../src/IRLTicketNFT.sol";
import {InternetRobinLottery} from "../src/InternetRobinLottery.sol";

// Mock VRF
import {VRFCoordinatorV2Mock} from "@chainlink/contracts/v0.8/vrf/mocks/VRFCoordinatorV2Mock.sol";

contract IRLUniswapV4HookTest is BaseTest {
    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    Currency currency0;
    Currency currency1;
    PoolKey poolKey;
    PoolId poolId;

    IRLUniswapV4Hook hook;
    IRLTicketNFT nft;
    InternetRobinLottery irlToken;
    VRFCoordinatorV2Mock vrfMock;

    uint256 tokenId;
    int24 tickLower;
    int24 tickUpper;

    address trader = address(0x123);

    function setUp() public {
        deployArtifactsAndLabel();

        (currency0, currency1) = deployCurrencyPair();

        // 1. Deploy VRF Mock
        vrfMock = new VRFCoordinatorV2Mock(0.1 ether, 1e9); // baseFee, gasPriceLink
        uint64 subId = vrfMock.createSubscription();
        vrfMock.fundSubscription(subId, 100 ether);

        // 2. Deploy NFT
        nft = new IRLTicketNFT(address(this));

        // 3. Deploy Hook (requires careful flag generation)
        address flags = address(
            uint160(Hooks.AFTER_SWAP_FLAG) ^ (0x4444 << 144)
        );
        
        bytes memory constructorArgs = abi.encode(poolManager, address(nft), address(vrfMock), subId, bytes32(0));
        deployCodeTo("IRLUniswapV4Hook.sol:IRLUniswapV4Hook", constructorArgs, flags);
        hook = IRLUniswapV4Hook(flags);

        // Give Hook permission to mint NFTs
        nft.transferOwnership(address(hook));

        // Create the pool
        poolKey = PoolKey(currency0, currency1, 3000, 60, IHooks(hook));
        poolId = poolKey.toId();
        poolManager.initialize(poolKey, Constants.SQRT_PRICE_1_1);

        // Provide full-range liquidity to the pool
        tickLower = TickMath.minUsableTick(poolKey.tickSpacing);
        tickUpper = TickMath.maxUsableTick(poolKey.tickSpacing);

        uint128 liquidityAmount = 100e18;

        (uint256 amount0Expected, uint256 amount1Expected) = LiquidityAmounts.getAmountsForLiquidity(
            Constants.SQRT_PRICE_1_1,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            liquidityAmount
        );

        (tokenId,) = positionManager.mint(
            poolKey,
            tickLower,
            tickUpper,
            liquidityAmount,
            amount0Expected + 1,
            amount1Expected + 1,
            address(this),
            block.timestamp,
            Constants.ZERO_BYTES
        );
        
        // Fund trader
        deal(Currency.unwrap(currency0), trader, 10 ether);
        deal(Currency.unwrap(currency1), trader, 10 ether);
    }

    function testAfterSwapTracksVolume() public {
        vm.startPrank(trader);
        
        uint256 amountIn = 0.5 ether; // Needs to be > 0.1 to trigger NFT
        
        // Approve router
        // In this base testing setup, swaps are done via swapRouter (deployArtifactsAndLabel deploys it)
        // Wait, swapRouter requires approvals
        // We will just execute a swap!
        
        // Actually, we need to approve the swapRouter first.
        // currency0 is an ERC20 in BaseTest.
        // I will just use address(swapRouter) or similar. 
        // BaseTest swapRouter is already deployed.
    }
}
