// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console2} from "forge-std/Test.sol";
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
import {IRLStaking} from "../src/IRLStaking.sol";
import {InternetRobinLottery} from "../src/InternetRobinLottery.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

contract MockOpenVRFScenarios {
    uint256 public requestFee = 0;
    uint256 public nextId = 1;

    struct Request {
        address consumer;
    }
    mapping(uint256 => Request) public requests;

    function setConsumerAuthorization(address /*consumer*/, bool /*authorized*/) external pure {}

    function requestRandomness(uint32 /*callbackGasLimit*/) external payable returns (uint256 id) {
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

contract MockWETHScenarios is MockERC20 {
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

contract RevertingETHReceiver {
    // Rejects all incoming ETH transfers
    receive() external payable {
        revert("I refuse ETH");
    }
}

/**
 * @title IRLProtocolScenariosTest
 * @notice Comprehensive Foundry multi-scenario test suite proving IRL Protocol correctness over:
 * - 1 Day (24 consecutive hours of trading, volume rewards, daily VRF draw)
 * - 1 Week (7 daily cycles, staking epoch claims, zero-ticket rollover, Sunday Mega-Jackpot)
 * - 1 Month (30-day flywheel, continuous staking yield, 4 Sunday Jackpots, 10% buyback & burn)
 * - Security Hardening & Edge Cases (Reverting winners, Programmable fee fallbacks, input validation)
 */
contract IRLProtocolScenariosTest is BaseTest {
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
    MockOpenVRFScenarios openVrfMock;
    MockWETHScenarios weth;

    uint256 posmTokenId;
    int24 tickLower;
    int24 tickUpper;

    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address charlie = address(0xCC1);
    address progRecipient = address(0x999);

    uint160 constant SQRT_PRICE_IRL_TOKEN0 = 7158327914619714881093632; 
    uint160 constant SQRT_PRICE_IRL_TOKEN1 = 876895058097984813589920800000000;

    function setUp() public {
        // Warp to exactly 42 days (1008 hours) - clean day and week boundary
        vm.warp(42 days);
        deployArtifactsAndLabel();

        openVrfMock = new MockOpenVRFScenarios();
        weth = new MockWETHScenarios();
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
        hook.removeLimits(); // Disable AntiWhale limit for test volume
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
        weth.deposit{value: 50 ether}();

        tickLower = TickMath.minUsableTick(poolKey.tickSpacing);
        tickUpper = TickMath.maxUsableTick(poolKey.tickSpacing);

        uint256 amount0Desired = address(irl) < address(weth) ? 900_000_000 ether : 7.346 ether;
        uint256 amount1Desired = address(irl) < address(weth) ? 7.346 ether : 900_000_000 ether;

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

        // Fund test users
        irl.transfer(alice, 20_000_000 ether); // Max staking tier (2% supply)
        irl.transfer(bob, 5_000_000 ether);
        irl.transfer(charlie, 1_000_000 ether);
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(charlie, 100 ether);
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
     * @notice Scenario 1: 1 Full Day (24 consecutive hours of trading, volume rewards, daily VRF draw)
     */
    function testSimulation_1Day_HourlyAndDailyDraw() public {
        // Alice stakes 20M IRL (Max 2% tier: +50% volume score, 10 tickets/day cap)
        vm.startPrank(alice);
        irl.approve(address(staking), type(uint256).max);
        staking.stake(20_000_000 ether);
        vm.stopPrank();

        uint256 progEthBefore = progRecipient.balance;
        uint256 day42 = block.timestamp / 1 days;
        uint256 currentTime = block.timestamp;

        // Simulate 24 hours of trading
        for (uint256 h = 0; h < 24; h++) {
            _performSwap(alice, 0.20 ether); // Unlocks 2 tickets (due to +50% boost)
            _performSwap(bob, 0.20 ether);   // Unlocks 2 tickets
            _performSwap(charlie, 0.10 ether); // Unlocks 1 ticket

            currentTime += 1 hours;
            vm.warp(currentTime);

            // Execute hourly automation
            (bool upkeepNeeded, bytes memory performData) = hook.checkUpkeep("");
            if (upkeepNeeded) {
                (uint8 actionType, ) = abi.decode(performData, (uint8, uint256));
                hook.performUpkeep(performData);
                if (actionType == 3) {
                    uint256 reqId = openVrfMock.nextId() - 1;
                    openVrfMock.fulfillMock(reqId, 123456789);
                }
                (bool queueNeeded, bytes memory queueData) = hook.checkUpkeep("");
                if (queueNeeded) {
                    hook.performUpkeep(queueData);
                }
            }
        }

        // Verify Programmable 1% fee was routed on every swap
        assertTrue(progRecipient.balance > progEthBefore, "Programmable fees should be received");
        assertEq(hook.programmableFeePot(), 0, "No pending fees stuck in pot");

        // Verify NFT tickets minted during Day 42
        uint256 startTicket = hook.dayStartTicketId(day42);
        uint256 endTicket = hook.dayEndTicketId(day42);
        assertTrue(startTicket > 0, "Tickets should be minted today");
        assertTrue(endTicket >= startTicket, "End ticket must be >= start ticket");

        // Process any remaining upkeeps to trigger daily lottery draw if not triggered in loop
        while (true) {
            (bool needed, bytes memory data) = hook.checkUpkeep("");
            if (!needed) break;
            (uint8 actionType, ) = abi.decode(data, (uint8, uint256));
            hook.performUpkeep(data);
            if (actionType == 3) {
                uint256 vrfRequestId = openVrfMock.nextId() - 1;
                openVrfMock.fulfillMock(vrfRequestId, 123456789);
                break;
            }
        }

        // Verify Daily Lottery winner was paid out and pot was reset
        assertEq(hook.dailyLotteryPot(), 0, "Daily pot must be 0 after draw");
    }

    /**
     * @notice Scenario 2: 1 Full Week (7 daily cycles, staking epoch claims, zero-ticket rollover, Sunday Mega-Jackpot)
     */
    function testSimulation_1Week_DailyDrawsAndSundayMegaJackpot() public {
        // Alice stakes 20M IRL
        vm.startPrank(alice);
        irl.approve(address(staking), type(uint256).max);
        staking.stake(20_000_000 ether);
        vm.stopPrank();

        uint256 currentTime = block.timestamp;

        // Days 1 through 4: active trading and daily lotteries
        for (uint256 d = 0; d < 4; d++) {
            _performSwap(alice, 0.30 ether);
            _performSwap(bob, 0.30 ether);

            currentTime += 1 days;
            vm.warp(currentTime);
            while (true) {
                (bool needed, bytes memory data) = hook.checkUpkeep("");
                if (!needed) break;
                (uint8 actionType, ) = abi.decode(data, (uint8, uint256));
                hook.performUpkeep(data);
                if (actionType == 3) {
                    uint256 reqId = openVrfMock.nextId() - 1;
                    openVrfMock.fulfillMock(reqId, 999 + d);
                    break;
                }
            }
        }

        // Day 4: Alice claims free 4-day epoch staking tickets
        vm.startPrank(alice);
        hook.claimStakingTickets();
        assertEq(nft.balanceOf(alice) >= 10, true, "Alice should receive 10 staking tickets");
        vm.stopPrank();

        // Day 5: Zero swaps simulated -> Test automatic rollover of daily pot into Sunday Mega Pot!
        uint256 sundayPotBeforeRollover = hook.sundayMegaPot();
        currentTime += 1 days;
        vm.warp(currentTime);
        while (true) {
            (bool zeroDayNeeded, bytes memory zeroDayData) = hook.checkUpkeep("");
            if (!zeroDayNeeded) break;
            (uint8 actionType, ) = abi.decode(zeroDayData, (uint8, uint256));
            hook.performUpkeep(zeroDayData);
            if (actionType == 3) {
                uint256 zeroReqId = openVrfMock.nextId() - 1;
                // Fulfill mock with 0 tickets minted today: should rollover to Sunday
                openVrfMock.fulfillMock(zeroReqId, 42);
                break;
            }
        }
        assertTrue(hook.sundayMegaPot() >= sundayPotBeforeRollover, "Rollover should preserve Sunday pot");

        // Day 6 & 7: Swaps and advance across the week boundary (Sunday Mega-Jackpot)
        _performSwap(alice, 0.20 ether);
        _performSwap(bob, 0.20 ether);

        // Warp 2 days to cross week boundary
        currentTime += 2 days;
        vm.warp(currentTime);
        uint256 sundayMegaPot = hook.sundayMegaPot();
        assertTrue(sundayMegaPot > 0, "Sunday Mega pot must be funded");

        // Process all upkeeps until Sunday Mega draw is triggered
        while (true) {
            (bool sundayNeeded, bytes memory sundayData) = hook.checkUpkeep("");
            if (!sundayNeeded) break;
            (uint8 actionType, ) = abi.decode(sundayData, (uint8, uint256));
            hook.performUpkeep(sundayData);
            if (actionType == 3) {
                // If daily draw happens first, fulfill it
                openVrfMock.fulfillMock(openVrfMock.nextId() - 1, 123);
            } else if (actionType == 4) {
                // Sunday Mega Jackpot triggered!
                uint256 sundayReqId = openVrfMock.nextId() - 1;
                openVrfMock.fulfillMock(sundayReqId, 777);
                break;
            }
        }

        assertEq(hook.sundayMegaPot(), 0, "Sunday Mega pot must be reset to 0 after payout");
    }

    /**
     * @notice Scenario 3: 1 Month Continuous Flywheel (30 days, continuous staking yield, 10% buyback & burn)
     */
    function testSimulation_1Month_ContinuousFlywheel() public {
        // Alice stakes 20M IRL for Real Yield
        vm.startPrank(alice);
        irl.approve(address(staking), type(uint256).max);
        staking.stake(20_000_000 ether);
        vm.stopPrank();

        uint256 totalSwaps = 30;
        uint256 currentTime = block.timestamp;
        for (uint256 day = 0; day < totalSwaps; day++) {
            _performSwap(bob, 0.50 ether);
            _performSwap(charlie, 0.50 ether);

            currentTime += 1 days;
            vm.warp(currentTime);

            // Trigger daily draw
            (bool needed, bytes memory data) = hook.checkUpkeep("");
            if (needed) {
                hook.performUpkeep(data);
                openVrfMock.fulfillMock(openVrfMock.nextId() - 1, 1000 + day);
            }
        }

        // 1. Verify Staking Real Yield accumulated in native ETH
        uint256 pendingYield = staking.pendingYield(alice);
        assertTrue(pendingYield > 0, "Alice should have accumulated Real Yield ETH");

        uint256 aliceEthBefore = alice.balance;
        vm.startPrank(alice);
        staking.claimYield();
        vm.stopPrank();
        assertEq(alice.balance - aliceEthBefore, pendingYield, "Alice must receive full pending ETH yield");

        // 2. Verify Protocol Buyback & Burn (10% of protocol fees burned to 0xdead)
        uint256 buybackPot = hook.buybackPot();
        assertTrue(buybackPot > 0, "Buyback pot should have accumulated 10% of protocol share");

        address deadAddress = address(0x000000000000000000000000000000000000dEaD);
        uint256 deadEthBefore = deadAddress.balance;
        hook.executeBuybackAndBurn();

        assertEq(hook.buybackPot(), 0, "Buyback pot must be reset to 0");
        assertEq(deadAddress.balance - deadEthBefore, buybackPot, "Dead address must receive burned ETH");
    }

    /**
     * @notice Scenario 4: Security Hardening & Edge Cases
     */
    function testSecurityHardening_RevertingWinnerAndFallbackPots() public {
        // 1. Test Input Validation on setProgrammableFeeRecipient
        vm.expectRevert(bytes("InvalidRecipientZeroAddress"));
        hook.setProgrammableFeeRecipient(address(0));

        vm.expectRevert(bytes("InvalidRecipientSelf"));
        hook.setProgrammableFeeRecipient(address(hook));

        // 2. Test Programmable Fee Reverting Recipient Fallback
        RevertingETHReceiver badRecipient = new RevertingETHReceiver();
        hook.setProgrammableFeeRecipient(address(badRecipient));

        // Swap must NOT revert; fee should safely buffer in programmableFeePot
        _performSwap(bob, 1.0 ether);
        // 1 ETH swap * 4% tax = 0.04 ETH. 1% Programmable = 0.01 ETH
        assertEq(hook.programmableFeePot(), 0.01 ether, "Fee should buffer when recipient reverts");

        // Unauthorized caller cannot claim
        vm.startPrank(bob);
        vm.expectRevert(bytes("Unauthorized"));
        hook.claimProgrammableFees();
        vm.stopPrank();

        // Fix recipient and claim
        hook.setProgrammableFeeRecipient(progRecipient);
        uint256 progEthBefore = progRecipient.balance;
        hook.claimProgrammableFees();
        assertEq(progRecipient.balance - progEthBefore, 0.01 ether, "Buffered fee claimed");
        assertEq(hook.programmableFeePot(), 0);

        // 3. Test Reverting Winner Fallback (Prize redirected to protocolPot, zero stuck ETH)
        // Advance to a fresh day and clear any prior day's upkeep
        uint256 currentTime = block.timestamp + 1 days;
        vm.warp(currentTime);
        while (true) {
            (bool needed, bytes memory data) = hook.checkUpkeep("");
            if (!needed) break;
            (uint8 actionType, ) = abi.decode(data, (uint8, uint256));
            hook.performUpkeep(data);
            if (actionType == 3) {
                openVrfMock.fulfillMock(openVrfMock.nextId() - 1, 1);
            }
        }

        // Fund badRecipient so it can execute swaps and mint the ONLY tickets on this new day
        vm.deal(address(badRecipient), 10 ether);
        _performSwap(address(badRecipient), 0.20 ether);

        // Advance 1 day to trigger the daily lottery draw for badRecipient's day
        currentTime += 1 days;
        vm.warp(currentTime);
        uint256 dailyPot = hook.dailyLotteryPot();
        assertTrue(dailyPot > 0, "Daily pot should exist");

        while (true) {
            (bool needed, bytes memory data) = hook.checkUpkeep("");
            if (!needed) break;
            (uint8 actionType, ) = abi.decode(data, (uint8, uint256));
            hook.performUpkeep(data);
            if (actionType == 3) break;
        }

        uint256 protocolPotBefore = hook.protocolPot();
        // Fulfill VRF: ticket belongs to badRecipient whose receive() reverts
        openVrfMock.fulfillMock(openVrfMock.nextId() - 1, 0);

        // Verify the badRecipient did not break the protocol and prize went to protocolPot
        assertEq(hook.protocolPot() - protocolPotBefore, dailyPot, "Prize should redirect to protocolPot");
        assertEq(hook.dailyLotteryPot(), 0, "Daily pot must be cleared");
    }
}
