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
        uint256 amountIn = 0.5 ether; // Needs to be > 0.1 to trigger NFT
        
        // On BaseTest, currency0 and currency1 are MockERC20 tokens.
        // We approve the swapRouter to spend our tokens
        // For testing, we just use the test contract itself as the swapper since it has the tokens minted
        
        // Mint tokens to this test contract for the swap
        deal(Currency.unwrap(currency0), address(this), 10 ether);
        deal(Currency.unwrap(currency1), address(this), 10 ether);
        
        // Approve Router
        // Since currency0 is a MockERC20, we can use an external call to approve
        (bool success, ) = Currency.unwrap(currency0).call(
            abi.encodeWithSignature("approve(address,uint256)", address(swapRouter), type(uint256).max)
        );
        require(success, "approve failed");

        // Perform a test swap
        BalanceDelta swapDelta = swapRouter.swapExactTokensForTokens({
            amountIn: amountIn,
            amountOutMin: 0, // Unlimited price impact for test
            zeroForOne: true, // Swapping currency0 for currency1
            poolKey: poolKey,
            hookData: abi.encode(address(this)),
            receiver: address(this),
            deadline: block.timestamp + 1
        });

        // 1. Verify swap happened
        assertEq(int256(swapDelta.amount0()), -int256(amountIn));

        // 2. Verify Volume Tracking
        uint256 hourId = block.timestamp / 1 hours;
        
        address actualTrader = address(this);
        uint256 trackedVolume = hook.userVolumePerHour(hourId, actualTrader);
        
        // Volume should be equal to amountIn (simplified in hook delta logic)
        assertEq(trackedVolume, amountIn);

        // 3. Verify Top 10 Leaderboard
        address top1 = hook.topTradersPerHour(hourId, 0);
        assertEq(top1, actualTrader); // Our trader should be #1

        // 4. Verify NFT Minting
        // Since amountIn (0.5 ether) > TICKET_VOLUME_THRESHOLD (0.1 ether)
        // Trader should have received tickets!
        uint256 ticketsEarned = hook.dailyTicketsMinted(block.timestamp / 1 days, actualTrader);
        assertEq(ticketsEarned, 5); // 0.5 ETH / 0.1 ETH = 5 tickets! (Max per day)
        
        // Verify NFT balance
        assertEq(nft.balanceOf(actualTrader), 5);
        assertEq(nft.ownerOf(1), actualTrader); // First NFT belongs to trader
    }
}
