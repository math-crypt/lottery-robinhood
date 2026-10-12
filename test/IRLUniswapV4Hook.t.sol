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

contract MockWETH {
    mapping(address => uint256) public balanceOf;
    function deposit() external payable {
        balanceOf[msg.sender] += msg.value;
    }
    function withdraw(uint256 wad) external {
        require(balanceOf[msg.sender] >= wad, "Insufficient WETH");
        balanceOf[msg.sender] -= wad;
        (bool success, ) = msg.sender.call{value: wad}("");
        require(success, "ETH transfer failed");
    }
}

contract MockStaking {
    mapping(address => uint256) public staked;
    function setStaked(address user, uint256 amount) external {
        staked[user] = amount;
    }
    function getStakedAmount(address user) external view returns (uint256) {
        return staked[user];
    }
}

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
    MockStaking mockStaking;

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
        uint160 hookFlags = uint160(
            Hooks.BEFORE_SWAP_FLAG | 
            Hooks.AFTER_SWAP_FLAG | 
            Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG | 
            Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        );
        address flags = address(hookFlags ^ (0x4444 << 144));
        
        MockWETH mockWeth = new MockWETH();
        mockStaking = new MockStaking();
        
        bytes memory constructorArgs = abi.encode(poolManager, address(nft), address(mockStaking), address(vrfMock), subId, bytes32(0), address(mockWeth));
        deployCodeTo("IRLUniswapV4Hook.sol:IRLUniswapV4Hook", constructorArgs, flags);
        hook = IRLUniswapV4Hook(payable(flags));

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
        
        // Volume should be close to amountIn (net of pool fees/slippage)
        assertApproxEqRel(trackedVolume, amountIn, 0.01e18);

        // 3. Verify Dynamic Score Tracking
        uint256 score = hook.userHourlyScore(hourId, actualTrader);
        assertEq(score, trackedVolume); // Without staking, score equals volume

        // 4. Verify NFT Minting
        // Since trackedVolume (~0.496 ether) > TICKET_VOLUME_THRESHOLD (0.1 ether)
        // Trader should have received 4 tickets! (0.496 ETH / 0.10 ETH = 4)
        uint256 ticketsEarned = hook.dailyTicketsMinted(block.timestamp / 1 days, actualTrader);
        assertEq(ticketsEarned, 4);
        
        // Verify NFT balance
        assertEq(nft.balanceOf(actualTrader), 4);
        assertEq(nft.ownerOf(1), actualTrader); // First NFT belongs to trader
    }

    function testStakerTicketVolumeMultiplierAnd4DayEpoch() public {
        address staker = address(0x456);
        // Staker stakes full 2% tier = 20,000,000 IRL
        mockStaking.setStaked(staker, 20_000_000 ether);

        // 1. Claim staking tickets: should get 10 tickets for epoch 0
        vm.prank(staker);
        hook.claimStakingTickets();
        assertEq(nft.balanceOf(staker), 10);
        assertEq(hook.epochStakingTicketsMinted(block.timestamp / 4 days, staker), 10);

        // Calling again in same epoch should not mint additional tickets
        vm.prank(staker);
        hook.claimStakingTickets();
        assertEq(nft.balanceOf(staker), 10);

        // Advance time by 3 days: still in same 4-day epoch (day 3 / 4 = 0)
        vm.warp(block.timestamp + 3 days);
        vm.prank(staker);
        hook.claimStakingTickets();
        assertEq(nft.balanceOf(staker), 10);

        // Advance time by 1 more day: now day 4, epoch 1 (day 4 / 4 = 1)
        vm.warp(block.timestamp + 1 days);
        vm.prank(staker);
        hook.claimStakingTickets();
        assertEq(nft.balanceOf(staker), 20); // 10 from epoch 0 + 10 from epoch 1

        // 2. Test Staker Volume Multiplier for Tickets:
        // A non-staker swapping 0.075 ETH gets tracked volume ~0.0745 ETH < 0.10 ETH threshold -> 0 tickets
        // The staker (20M staked, +50% multiplier) gets boosted volume:
        // scoreDelta = 0.0745 * 150 / 100 = 0.11175 ETH >= 0.10 ETH threshold -> 1 ticket!
        deal(Currency.unwrap(currency0), staker, 10 ether);
        deal(Currency.unwrap(currency1), staker, 10 ether);

        vm.startPrank(staker);
        (bool success, ) = Currency.unwrap(currency0).call(
            abi.encodeWithSignature("approve(address,uint256)", address(swapRouter), type(uint256).max)
        );
        require(success, "approve failed");

        uint256 ticketsBeforeSwap = nft.balanceOf(staker); // 20

        swapRouter.swapExactTokensForTokens({
            amountIn: 0.075 ether,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: poolKey,
            hookData: abi.encode(staker),
            receiver: staker,
            deadline: block.timestamp + 1
        });
        vm.stopPrank();

        // Staker received 1 additional ticket from the 0.075 ETH swap thanks to +50% volume multiplier!
        uint256 ticketsAfterSwap = nft.balanceOf(staker);
        assertEq(ticketsAfterSwap - ticketsBeforeSwap, 1);
    }

    function testDailyVolumeLimitsNonStakerVsStaker() public {
        address nonStaker = address(0x789);
        address staker = address(0x999);
        mockStaking.setStaked(staker, 20_000_000 ether);

        // 1. Verify limit view functions
        assertEq(hook.getMaxDailyVolumeTickets(nonStaker), 6);
        assertEq(hook.getMaxDailyTicketsLimit(nonStaker), 6);
        assertEq(hook.getMaxWeeklyTicketsLimit(nonStaker), 42); // 6 * 7

        assertEq(hook.getMaxDailyVolumeTickets(staker), 10);
        assertEq(hook.getMaxDailyTicketsLimit(staker), 10);
        assertEq(hook.getMaxWeeklyTicketsLimit(staker), 70); // 10 * 7

        // 2. Non-staker does large swap (1.5 ETH)
        // With threshold 0.10 ETH, 1.5 ETH could produce 15 tickets if unbounded
        // But non-staker is strictly capped at 6 tickets!
        deal(Currency.unwrap(currency0), nonStaker, 10 ether);
        deal(Currency.unwrap(currency1), nonStaker, 10 ether);

        vm.startPrank(nonStaker);
        (bool ok1, ) = Currency.unwrap(currency0).call(
            abi.encodeWithSignature("approve(address,uint256)", address(swapRouter), type(uint256).max)
        );
        require(ok1, "Approve failed");
        swapRouter.swapExactTokensForTokens({
            amountIn: 1.5 ether,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: poolKey,
            hookData: abi.encode(nonStaker),
            receiver: nonStaker,
            deadline: block.timestamp + 1
        });
        vm.stopPrank();

        assertEq(hook.dailyTicketsMinted(block.timestamp / 1 days, nonStaker), 6);
        assertEq(nft.balanceOf(nonStaker), 6);

        // 3. Staker does large swap (1.5 ETH)
        // Staker is capped at 10 tickets for daily volume!
        deal(Currency.unwrap(currency0), staker, 10 ether);
        deal(Currency.unwrap(currency1), staker, 10 ether);

        vm.startPrank(staker);
        (bool ok2, ) = Currency.unwrap(currency0).call(
            abi.encodeWithSignature("approve(address,uint256)", address(swapRouter), type(uint256).max)
        );
        require(ok2, "Approve failed");
        swapRouter.swapExactTokensForTokens({
            amountIn: 1.5 ether,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: poolKey,
            hookData: abi.encode(staker),
            receiver: staker,
            deadline: block.timestamp + 1
        });
        vm.stopPrank();

        assertEq(hook.dailyTicketsMinted(block.timestamp / 1 days, staker), 10);
        // And staker can still claim their 10 free staking tickets every 4 days!
        vm.prank(staker);
        hook.claimStakingTickets();
        assertEq(nft.balanceOf(staker), 20); // 10 from volume + 10 free staking tickets!
    }
}


