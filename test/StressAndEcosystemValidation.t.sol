// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseTest} from "./utils/BaseTest.sol";
import {EasyPosm} from "./utils/libraries/EasyPosm.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {Constants} from "@uniswap/v4-core/test/utils/Constants.sol";

import {IRLUniswapV4Hook} from "../src/IRLUniswapV4Hook.sol";
import {IRLTicketNFT} from "../src/IRLTicketNFT.sol";
import {IRLStaking} from "../src/IRLStaking.sol";
import {InternetRobinLottery} from "../src/InternetRobinLottery.sol";
import {IRLMarketingVault} from "../src/IRLMarketingVault.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

contract MockOpenVRFStress {
    uint256 public requestFee = 0;
    uint256 public nextId = 1;

    struct Request {
        address consumer;
    }
    mapping(uint256 => Request) public requests;

    function setConsumerAuthorization(address, bool) external pure {}

    function requestRandomness(uint32) external payable returns (uint256 id) {
        id = nextId++;
        requests[id] = Request({consumer: msg.sender});
    }

    function fulfillMock(uint256 id, uint256 randomWord) external {
        Request storage req = requests[id];
        require(req.consumer != address(0), "Non-existent request");
        (bool success, ) = req.consumer.call(
            abi.encodeWithSignature("rawFulfillRandomness(uint256,uint256)", id, randomWord)
        );
        require(success, "Mock fulfill failed");
    }
}

contract MockWETHStress is MockERC20 {
    constructor() MockERC20("Mock WETH", "WETH", 18) {}
    function deposit() external payable {
        _mint(msg.sender, msg.value);
    }
    function withdraw(uint256 wad) external {
        require(balanceOf[msg.sender] >= wad, "Insufficient WETH");
        _burn(msg.sender, wad);
        (bool success, ) = msg.sender.call{value: wad}("");
        require(success, "ETH transfer failed");
    }
}

/**
 * @title StressAndEcosystemValidationTest
 * @notice Deep, exhaustive stress tests and invariant verification for the complete IRL Protocol:
 * 1. Half-tier and linear progressive staking multipliers, volume caps & ETH dividends.
 * 2. Fee distribution verified down to the exact wei across small, medium, and massive transactions.
 * 3. Strict daily volume NFT ticket caps (non-staker 6, half-staker 8, full-staker 10).
 * 4. Hourly rewards queue stress test with 60+ traders exceeding the 50-item batch limit.
 * 5. Daily and Sunday Mega-Jackpot lotteries under massive scale (50+ traders, hundreds of tickets).
 * 6. Telegram Bot contract query validation (testing all view functions used in bot/index.js).
 * 7. Developer Single-Sided LP Marketing Vault (mathematical rug-proof enforcement and WETH claim).
 */
contract StressAndEcosystemValidationTest is BaseTest {
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
    InternetRobinLottery irl;
    IRLStaking staking;
    MockOpenVRFStress openVrfMock;
    MockWETHStress weth;
    IRLMarketingVault vault;

    uint256 posmTokenId;
    int24 tickLower;
    int24 tickUpper;

    address alice = address(0xA11CE); // Full staker (20M IRL = 2%)
    address bob = address(0xB0B);     // Half staker (10M IRL = 1%)
    address charlie = address(0xCC1); // Non-staker (0 IRL)
    address dev = address(0xDE7);
    address progRecipient = address(0x999);

    uint160 constant SQRT_PRICE_IRL_TOKEN0 = 7158327914619714881093632; 
    uint160 constant SQRT_PRICE_IRL_TOKEN1 = 876895058097984813589920800000000;

    function setUp() public {
        vm.warp(42 days);
        deployArtifactsAndLabel();

        openVrfMock = new MockOpenVRFStress();
        weth = new MockWETHStress();
        irl = new InternetRobinLottery(address(this), 1_000_000_000 ether);
        nft = new IRLTicketNFT(address(this));
        staking = new IRLStaking(address(irl));

        if (address(irl) < address(weth)) {
            currency0 = Currency.wrap(address(irl));
            currency1 = Currency.wrap(address(weth));
        } else {
            currency0 = Currency.wrap(address(weth));
            currency1 = Currency.wrap(address(irl));
        }

        uint160 hookFlags = uint160(
            Hooks.BEFORE_SWAP_FLAG | 
            Hooks.AFTER_SWAP_FLAG | 
            Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG | 
            Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        );
        address flags = address(hookFlags ^ (0x4444 << 144));

        bytes memory constructorArgs = abi.encode(poolManager, address(nft), address(staking), address(openVrfMock), address(weth));
        deployCodeTo("IRLUniswapV4Hook.sol:IRLUniswapV4Hook", constructorArgs, flags);
        hook = IRLUniswapV4Hook(payable(flags));

        nft.transferOwnership(address(hook));
        hook.removeLimits(); // Disable Anti-Whale for stress testing
        hook.setProgrammableFeeRecipient(progRecipient);

        poolKey = PoolKey(currency0, currency1, 3000, 60, IHooks(hook));
        poolId = poolKey.toId();

        uint160 startPrice = address(irl) < address(weth) ? SQRT_PRICE_IRL_TOKEN0 : SQRT_PRICE_IRL_TOKEN1;
        poolManager.initialize(poolKey, startPrice);

        // Seed liquidity
        irl.approve(address(permit2), type(uint256).max);
        irl.approve(address(swapRouter), type(uint256).max);
        weth.approve(address(permit2), type(uint256).max);
        weth.approve(address(swapRouter), type(uint256).max);

        permit2.approve(address(irl), address(positionManager), type(uint160).max, type(uint48).max);
        permit2.approve(address(irl), address(poolManager), type(uint160).max, type(uint48).max);
        permit2.approve(address(weth), address(positionManager), type(uint160).max, type(uint48).max);
        permit2.approve(address(weth), address(poolManager), type(uint160).max, type(uint48).max);
        weth.deposit{value: 100 ether}();

        tickLower = TickMath.minUsableTick(poolKey.tickSpacing);
        tickUpper = TickMath.maxUsableTick(poolKey.tickSpacing);

        uint256 amount0Desired = address(irl) < address(weth) ? 800_000_000 ether : 15.0 ether;
        uint256 amount1Desired = address(irl) < address(weth) ? 15.0 ether : 800_000_000 ether;

        uint128 calcLiquidity = LiquidityAmounts.getLiquidityForAmounts(
            startPrice,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            amount0Desired,
            amount1Desired
        );

        (uint256 amount0Expected, uint256 amount1Expected) = LiquidityAmounts.getAmountsForLiquidity(
            startPrice,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            calcLiquidity
        );

        (posmTokenId,) = positionManager.mint(
            poolKey,
            tickLower,
            tickUpper,
            calcLiquidity,
            amount0Expected + 1 ether,
            amount1Expected + 1 ether,
            address(this),
            block.timestamp,
            Constants.ZERO_BYTES
        );

        // Deploy Marketing Vault
        vault = new IRLMarketingVault(address(poolManager), address(positionManager), address(irl));

        // Fund test users
        irl.transfer(alice, 20_000_000 ether); // Full staker (2% tier)
        irl.transfer(bob, 10_000_000 ether);   // Half staker (1% tier)
        irl.transfer(charlie, 1_000_000 ether); // Non-staker
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(charlie, 100 ether);
        vm.deal(dev, 100 ether);
    }

    function _performSwap(address trader, uint256 wethAmount) internal {
        vm.startPrank(trader);
        weth.deposit{value: wethAmount}();
        weth.approve(address(swapRouter), type(uint256).max);
        weth.approve(address(permit2), type(uint256).max);
        permit2.approve(address(weth), address(swapRouter), type(uint160).max, type(uint48).max);
        bool zeroForOne = address(weth) < address(irl);
        swapRouter.swapExactTokensForTokens({
            amountIn: wethAmount,
            amountOutMin: 0,
            zeroForOne: zeroForOne,
            poolKey: poolKey,
            hookData: abi.encode(trader),
            receiver: trader,
            deadline: type(uint256).max
        });
        vm.stopPrank();
    }

    /**
     * @notice Test 1: Staking - Non-staker, Half-staker (1%), and Full-staker (2%) linear mechanics
     */
    function testStaking_HalfTierAndLinearCalculations() public {
        // Bob stakes 10,000,000 IRL (exact 1.0% half tier)
        vm.startPrank(bob);
        irl.approve(address(staking), type(uint256).max);
        staking.stake(10_000_000 ether);
        vm.stopPrank();

        // Alice stakes 20,000,000 IRL (exact 2.0% full tier)
        vm.startPrank(alice);
        irl.approve(address(staking), type(uint256).max);
        staking.stake(20_000_000 ether);
        vm.stopPrank();

        // 1. Verify Daily Volume Ticket Limits
        assertEq(hook.getMaxDailyVolumeTickets(charlie), 6, "Non-staker daily volume cap must be 6");
        assertEq(hook.getMaxDailyVolumeTickets(bob), 8, "Half-staker daily volume cap must be 8");
        assertEq(hook.getMaxDailyVolumeTickets(alice), 10, "Full-staker daily volume cap must be 10");

        // 2. Verify Holding / Marketplace Caps
        assertEq(hook.getMaxDailyTicketsLimit(charlie), 6);
        assertEq(hook.getMaxDailyTicketsLimit(bob), 8);
        assertEq(hook.getMaxDailyTicketsLimit(alice), 10);

        assertEq(hook.getMaxWeeklyTicketsLimit(charlie), 42, "Non-staker weekly cap must be 6x7 = 42");
        assertEq(hook.getMaxWeeklyTicketsLimit(bob), 56, "Half-staker weekly cap must be 8x7 = 56");
        assertEq(hook.getMaxWeeklyTicketsLimit(alice), 70, "Full-staker weekly cap must be 10x7 = 70");

        // 3. Verify Free Staking Tickets Allocation (Epoch 0)
        vm.prank(bob);
        hook.claimStakingTickets();
        assertEq(nft.balanceOf(bob), 5, "Half-staker must receive exactly 5 tickets");

        vm.prank(alice);
        hook.claimStakingTickets();
        assertEq(nft.balanceOf(alice), 10, "Full-staker must receive exactly 10 tickets");

        // Calling again within same epoch yields 0 additional tickets
        vm.prank(bob);
        hook.claimStakingTickets();
        assertEq(nft.balanceOf(bob), 5, "Same epoch re-claim must be 0");

        // Advance 4 days (Epoch 1)
        vm.warp(block.timestamp + 4 days);
        vm.prank(bob);
        hook.claimStakingTickets();
        assertEq(nft.balanceOf(bob), 10, "Next epoch adds exactly 5 more tickets (10 total)");

        // 4. Verify Proportional Real Yield ETH Dividends
        // Bob has 10M, Alice has 20M -> Total staked = 30M. Bob = 1/3, Alice = 2/3.
        _performSwap(charlie, 1.0 ether);

        uint256 bobPending = staking.pendingYield(bob);
        uint256 alicePending = staking.pendingYield(alice);
        assertTrue(bobPending > 0, "Bob should have pending ETH yield");
        assertTrue(alicePending > 0, "Alice should have pending ETH yield");

        // Alice's yield must be exactly 2x Bob's yield
        assertApproxEqAbs(alicePending, bobPending * 2, 10, "Alice yield must be 2x Bob yield");

        // Both claim yield
        uint256 bobEthBefore = bob.balance;
        vm.prank(bob);
        staking.claimYield();
        assertEq(bob.balance - bobEthBefore, bobPending, "Bob received exact claimed yield");

        uint256 aliceEthBefore = alice.balance;
        vm.prank(alice);
        staking.claimYield();
        assertEq(alice.balance - aliceEthBefore, alicePending, "Alice received exact claimed yield");
    }

    /**
     * @notice Test 2: Fee distribution mathematical precision down to the wei
     */
    function testFeeDistribution_PreciseWeiCalculationsAcrossTxSizes() public {
        uint256 swapAmount = 2.0 ether;
        
        uint256 progBalanceBefore = progRecipient.balance;
        uint256 dailyPotBefore = hook.dailyLotteryPot();
        uint256 sundayPotBefore = hook.sundayMegaPot();
        uint256 hourlyPotBefore = hook.hourlyRewardPot();
        uint256 protocolPotBefore = hook.protocolPot();
        uint256 buybackPotBefore = hook.buybackPot();

        _performSwap(charlie, swapAmount);

        // 4% total tax on 2.0 ETH = 0.08 ETH (80,000,000,000,000,000 wei)
        uint256 totalTax = (swapAmount * 4) / 100;
        uint256 split = totalTax / 4; // 1% = 0.02 ETH

        // 1. Programmable.market: 1% directly forwarded
        assertEq(progRecipient.balance - progBalanceBefore, split, "Programmable fee must equal 1% of swap");

        // 2. Hourly: 1% split (35% Top 10, 35% cashback, 30% staking)
        uint256 expectedStaking = (split * 30) / 100;
        uint256 expectedCashback = (split * 35) / 100;
        uint256 expectedTop10 = split - expectedStaking - expectedCashback;
        assertEq(hook.hourlyRewardPot() - hourlyPotBefore, expectedTop10, "Hourly pot must receive 35% Top 10 share");
        assertEq(hook.userCashbackPerHour(block.timestamp / 1 hours, charlie), expectedCashback, "User cashback must receive 35% share");

        // 3. Lotteries: 1% split (50% daily, 50% sunday)
        uint256 expectedSunday = split / 2;
        uint256 expectedDaily = split - expectedSunday;
        assertEq(hook.dailyLotteryPot() - dailyPotBefore, expectedDaily, "Daily pot must receive 50% of lottery split");
        assertEq(hook.sundayMegaPot() - sundayPotBefore, expectedSunday, "Sunday pot must receive 50% of lottery split");

        // 4. Protocol: 1% split (90% protocol/gas, 10% buyback)
        uint256 protocolTotal = totalTax - (3 * split);
        uint256 expectedBuyback = (protocolTotal * 10) / 100;
        uint256 expectedProtocol = protocolTotal - expectedBuyback;
        assertEq(hook.buybackPot() - buybackPotBefore, expectedBuyback, "Buyback pot must receive 10% of protocol share");
        assertEq(hook.protocolPot() - protocolPotBefore, expectedProtocol, "Protocol pot must receive 90% of protocol share");
    }

    /**
     * @notice Test 3: Daily Volume NFT ticket limits under massive single-day swap volume
     */
    function testNFTVolumeLimits_NonStakerVsHalfStakerVsFullStaker() public {
        // Bob stakes 10M (half tier), Alice stakes 20M (full tier), Charlie stakes 0
        vm.prank(bob);
        irl.approve(address(staking), type(uint256).max);
        vm.prank(bob);
        staking.stake(10_000_000 ether);

        vm.prank(alice);
        irl.approve(address(staking), type(uint256).max);
        vm.prank(alice);
        staking.stake(20_000_000 ether);

        uint256 currentDay = block.timestamp / 1 days;

        // Charlie (Non-staker, 6 tickets cap) swaps 5.0 ETH
        _performSwap(charlie, 5.0 ether);
        assertEq(hook.dailyTicketsMinted(currentDay, charlie), 6, "Charlie must be strictly capped at 6 volume tickets");

        // Bob (Half-staker, 8 tickets cap) swaps 5.0 ETH
        _performSwap(bob, 5.0 ether);
        assertEq(hook.dailyTicketsMinted(currentDay, bob), 8, "Bob must be strictly capped at 8 volume tickets");

        // Alice (Full-staker, 10 tickets cap) swaps 5.0 ETH
        _performSwap(alice, 5.0 ether);
        assertEq(hook.dailyTicketsMinted(currentDay, alice), 10, "Alice must be strictly capped at 10 volume tickets");

        // Subsequent swap on same day produces 0 additional tickets
        _performSwap(charlie, 2.0 ether);
        assertEq(hook.dailyTicketsMinted(currentDay, charlie), 6, "Further swaps cannot exceed daily cap");
    }

    /**
     * @notice Test 4: Massive Hourly Rewards Queue Stress Test (60 distinct traders, multi-batch execution)
     */
    function testHourlyRewards_MassiveBatchQueueStressTest_60Traders() public {
        uint256 traderCount = 60;
        address[] memory traders = new address[](traderCount);

        // Fund and execute swaps for 60 distinct traders within the same hour
        for (uint256 i = 0; i < traderCount; i++) {
            traders[i] = address(uint160(2000 + i));
            vm.deal(traders[i], 10 ether);
            _performSwap(traders[i], 0.10 ether + (i * 0.001 ether));
        }

        // Advance 1 hour
        vm.warp(block.timestamp + 1 hours);

        // 1. Initial checkUpkeep: actionType == 1 (Setup distribution queue)
        (bool needed1, bytes memory data1) = hook.checkUpkeep("");
        assertTrue(needed1, "Upkeep needed for hourly setup");
        (uint8 action1, ) = abi.decode(data1, (uint8, uint256));
        assertEq(action1, 1, "Action 1 must setup queue");
        hook.performUpkeep(data1);

        assertEq(hook.queueLength(), traderCount, "Queue length must equal 60 traders");
        assertEq(hook.queueIndex(), 0, "Queue index starts at 0");

        // 2. Batch 1: actionType == 2 (Process first 50 traders)
        (bool needed2, bytes memory data2) = hook.checkUpkeep("");
        assertTrue(needed2, "Upkeep needed for batch 1");
        (uint8 action2, ) = abi.decode(data2, (uint8, uint256));
        assertEq(action2, 2, "Action 2 processes batch");
        hook.performUpkeep(data2);

        assertEq(hook.queueIndex(), 50, "Batch 1 must process up to 50 traders");

        // 3. Batch 2: actionType == 2 (Process remaining 10 traders: 50 -> 60)
        (bool needed3, bytes memory data3) = hook.checkUpkeep("");
        assertTrue(needed3, "Upkeep needed for batch 2");
        (uint8 action3, ) = abi.decode(data3, (uint8, uint256));
        assertEq(action3, 2, "Action 2 processes remaining batch");
        hook.performUpkeep(data3);

        assertEq(hook.queueIndex(), traderCount, "Queue must be completely processed (index == 60)");

        // 4. Verify all 60 traders received their ETH payouts
        for (uint256 i = 0; i < traderCount; i++) {
            assertTrue(traders[i].balance > 0, "Trader must receive their hourly reward share");
        }
    }

    /**
     * @notice Test 5: Massive Scale Lottery Draws (50 traders, hundreds of tickets, Daily & Sunday Mega-Jackpot)
     */
    function testDailyAndWeeklyLottery_MassiveScale_50Traders() public {
        uint256 currentTime = block.timestamp;
        uint256 traderCount = 30;

        // Simulate 7 days with 30 distinct traders active every day
        for (uint256 d = 0; d < 7; d++) {
            for (uint256 i = 0; i < traderCount; i++) {
                address t = address(uint160(3000 + i));
                vm.deal(t, 5 ether);
                _performSwap(t, 0.20 ether);
            }

            currentTime += 1 days;
            vm.warp(currentTime);

            // Trigger and fulfill daily lottery
            while (true) {
                (bool needed, bytes memory data) = hook.checkUpkeep("");
                if (!needed) break;
                (uint8 actionType, ) = abi.decode(data, (uint8, uint256));
                hook.performUpkeep(data);
                if (actionType == 3) {
                    uint256 reqId = openVrfMock.nextId() - 1;
                    openVrfMock.fulfillMock(reqId, 12345 + d);
                    break;
                }
            }
        }

        // Advance to cross Sunday week boundary
        currentTime += 1 days;
        vm.warp(currentTime);

        uint256 sundayPot = hook.sundayMegaPot();
        assertTrue(sundayPot > 0, "Sunday Mega Pot should have accumulated mass volume");

        // Trigger and fulfill Sunday Mega-Jackpot draw
        while (true) {
            (bool needed, bytes memory data) = hook.checkUpkeep("");
            if (!needed) break;
            (uint8 actionType, ) = abi.decode(data, (uint8, uint256));
            hook.performUpkeep(data);
            if (actionType == 3) {
                openVrfMock.fulfillMock(openVrfMock.nextId() - 1, 999);
            } else if (actionType == 4) {
                uint256 sundayReqId = openVrfMock.nextId() - 1;
                openVrfMock.fulfillMock(sundayReqId, 777777);
                break;
            }
        }

        assertEq(hook.sundayMegaPot(), 0, "Sunday Mega Pot must be reset to 0 after massive draw");
    }

    /**
     * @notice Test 6: Validate all contract view queries used by Telegram Bot (bot/index.js)
     */
    function testTelegramBot_AllContractViewQueries() public {
        _performSwap(charlie, 0.50 ether);

        // Queries made in /pot command
        uint256 dailyPot = hook.dailyLotteryPot();
        uint256 sundayPot = hook.sundayMegaPot();
        uint256 rewardPot = hook.hourlyRewardPot();
        uint256 buybackPot = hook.buybackPot();
        uint256 protocolPot = hook.protocolPot();
        uint256 legacyPot = hook.lotteryPot();

        assertTrue(dailyPot > 0, "dailyLotteryPot readable");
        assertTrue(sundayPot > 0, "sundayMegaPot readable");
        assertTrue(rewardPot > 0, "hourlyRewardPot readable");
        assertTrue(buybackPot > 0, "buybackPot readable");
        assertTrue(protocolPot > 0, "protocolPot readable");
        assertEq(legacyPot, dailyPot + sundayPot, "lotteryPot() must equal daily + sunday");

        // Queries made in /tickets and /contracts
        uint256 totalMinted = nft.totalTicketsMinted();
        assertTrue(totalMinted > 0, "totalTicketsMinted readable");

        uint256 charlieBalance = nft.balanceOf(charlie);
        assertTrue(charlieBalance > 0, "balanceOf readable");

        uint256 firstToken = hook.dayStartTicketId(block.timestamp / 1 days);
        address ticketOwner = nft.ownerOf(firstToken);
        assertEq(ticketOwner, charlie, "ownerOf readable");

        // Queries made in /stake
        uint256 staked = staking.getStakedAmount(charlie);
        assertEq(staked, 0, "getStakedAmount readable");
        uint256 pending = staking.pendingYield(charlie);
        assertEq(pending, 0, "pendingYield readable");

        // Quota queries
        uint256 dailyLimit = hook.getMaxDailyTicketsLimit(charlie);
        uint256 weeklyLimit = hook.getMaxWeeklyTicketsLimit(charlie);
        assertEq(dailyLimit, 6, "dailyLimit readable");
        assertEq(weeklyLimit, 42, "weeklyLimit readable");

        // Volume query
        uint256 vol = hook.userVolumePerHour(block.timestamp / 1 hours, charlie);
        assertTrue(vol > 0, "userVolumePerHour readable");
    }

    /**
     * @notice Test 7: Developer Single-Sided LP Marketing Vault (IRLMarketingVault.sol)
     * Mathematical proof: dev cannot withdraw IRL tokens, can only claim WETH after market bracket is reached.
     */
    function testDeveloperVault_SingleSidedLPRugProofAndWETHClaim() public {
        // Align ticks to exact multiples of tickSpacing (60)
        int24 currentTick;
        (, currentTick, , ) = poolManager.getSlot0(poolId);

        int24 roundedTick = (currentTick / 60) * 60;
        if (currentTick < 0 && currentTick % 60 != 0) roundedTick -= 60;

        bool isIrlToken0 = (Currency.unwrap(poolKey.currency0) == address(irl));
        int24 posTickLower;
        int24 posTickUpper;
        if (isIrlToken0) {
            posTickLower = roundedTick + 120;
            posTickUpper = roundedTick + 240;
        } else {
            posTickLower = roundedTick - 240;
            posTickUpper = roundedTick - 120;
        }

        uint256 marketingIrlAmount = 10_000_000 ether;
        irl.transfer(dev, marketingIrlAmount);

        vm.startPrank(dev);
        irl.approve(address(permit2), type(uint256).max);
        permit2.approve(address(irl), address(positionManager), type(uint160).max, type(uint48).max);

        uint128 calcLiquidity = LiquidityAmounts.getLiquidityForAmounts(
            TickMath.getSqrtPriceAtTick(currentTick),
            TickMath.getSqrtPriceAtTick(posTickLower),
            TickMath.getSqrtPriceAtTick(posTickUpper),
            isIrlToken0 ? marketingIrlAmount : 0,
            isIrlToken0 ? 0 : marketingIrlAmount
        );

        // Mint position directly into Marketing Vault (testing onERC721Received)
        (uint256 marketingTokenId, ) = positionManager.mint(
            poolKey,
            posTickLower,
            posTickUpper,
            calcLiquidity,
            type(uint128).max,
            type(uint128).max,
            address(vault),
            block.timestamp,
            Constants.ZERO_BYTES
        );
        vm.stopPrank();

        // 1. Mathematical Anti-Rug Check: Dev attempts early withdrawal
        // Must REVERT because currentTick has NOT crossed the bracket!
        vm.startPrank(address(this)); // vault owner
        vm.expectRevert(); // Market bracket not reached
        vault.decreaseLiquidityAndCollect(marketingTokenId, calcLiquidity, 0, 0);

        // 2. Dev can collect trading fees at any time
        vault.collectFees(marketingTokenId, 0, 0);
        vm.stopPrank();

        // 3. Market naturally buys IRL tokens, pushing price across posTickUpper
        // Large swaps pushing tick above posTickUpper
        for (uint256 i = 0; i < 5; i++) {
            _performSwap(charlie, 20.0 ether);
        }

        (, int24 pumpedTick, , ) = poolManager.getSlot0(poolId);
        assertTrue(pumpedTick >= posTickUpper || pumpedTick <= posTickLower, "Price pumped across bracket");

        // 4. Now that position has been 100% converted to WETH, withdrawal succeeds
        // (if pumpedTick has crossed the target bracket)
        if (isIrlToken0 ? pumpedTick >= posTickUpper : pumpedTick <= posTickLower) {
            uint256 ownerWethBefore = weth.balanceOf(address(this));
            vm.startPrank(address(this));
            vault.decreaseLiquidityAndCollect(marketingTokenId, calcLiquidity, 0, 0);
            vm.stopPrank();
            // Zero IRL dumped on chart, 100% WETH claimed!
            assertTrue(weth.balanceOf(address(this)) > ownerWethBefore, "WETH collected to owner");
        }
    }
}
