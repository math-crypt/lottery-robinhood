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
// Standalone OpenVRFMock to avoid bls-solidity "stack too deep" compilation errors
contract OpenVRFMock {
    uint256 public requestFee = 0;
    mapping(address => bool) public authorizedConsumers;

    uint256 public nextId = 1;

    struct Request {
        address consumer;
    }
    mapping(uint256 => Request) public requests;

    function setConsumerAuthorization(address consumer, bool authorized) external {
        authorizedConsumers[consumer] = authorized;
    }

    function requestRandomness(uint32 /*callbackGasLimit*/) external payable returns (uint256 id) {
        id = nextId++;
        requests[id] = Request({consumer: msg.sender});
    }

    function fulfillMock(uint256 id, uint256 randomWord) external {
        Request storage req = requests[id];
        (bool success, ) = req.consumer.call(
            abi.encodeWithSignature("rawFulfillRandomness(uint256,uint256)", id, randomWord)
        );
        require(success, "Mock fulfill failed");
    }
}

contract MockWETH is MockERC20 {
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

contract SimulationEcosystemTest is BaseTest {
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
    OpenVRFMock openVrfMock;
    MockWETH weth;

    uint256 tokenId;
    int24 tickLower;
    int24 tickUpper;

    address alice = address(0x111);
    address bob = address(0x222);

    uint160 constant SQRT_PRICE_IRL_TOKEN0 = 7158327914619714881093632; 
    uint160 constant SQRT_PRICE_IRL_TOKEN1 = 876895058097984813589920800000000;

    function setUp() public {
        vm.warp(1000 hours); // Start at a clean hour boundary
        deployArtifactsAndLabel();

        // 1. We wrap WETH as standard Mock ERC20 so tests work smoothly
        weth = new MockWETH();
        irl = new InternetRobinLottery(address(this), 1_000_000_000 ether);

        if (address(irl) < address(weth)) {
            currency0 = Currency.wrap(address(irl));
            currency1 = Currency.wrap(address(weth));
        } else {
            currency0 = Currency.wrap(address(weth));
            currency1 = Currency.wrap(address(irl));
        }

        // 2. Mock VRF
        openVrfMock = new OpenVRFMock();

        nft = new IRLTicketNFT(address(this));
        staking = new IRLStaking(address(irl));

        // 3. Setup Hook
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
        
        openVrfMock.setConsumerAuthorization(address(hook), true);
        
        hook.removeLimits(); // Disable AntiWhale for tests

        // 4. Setup Pool Manager
        poolKey = PoolKey(currency0, currency1, 3000, 60, IHooks(hook));
        poolId = poolKey.toId();
        
        uint160 startPrice = address(irl) < address(weth) ? SQRT_PRICE_IRL_TOKEN0 : SQRT_PRICE_IRL_TOKEN1;
        poolManager.initialize(poolKey, startPrice);

        // 5. Provide 90% Liquidity to hit 20k market cap curve
        irl.approve(address(permit2), type(uint256).max);
        irl.approve(address(swapRouter), type(uint256).max);
        weth.approve(address(permit2), type(uint256).max);
        weth.approve(address(swapRouter), type(uint256).max);
        
        permit2.approve(address(irl), address(positionManager), type(uint160).max, type(uint48).max);
        permit2.approve(address(irl), address(poolManager), type(uint160).max, type(uint48).max);
        permit2.approve(address(weth), address(positionManager), type(uint160).max, type(uint48).max);
        permit2.approve(address(weth), address(poolManager), type(uint160).max, type(uint48).max);
        weth.deposit{value: 10 ether}();

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

        (tokenId,) = positionManager.mint(
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

        // Distribute some tokens and ETH to Alice and Bob
        irl.transfer(alice, 10_000_000 ether);
        irl.transfer(bob, 10_000_000 ether);
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
    }

    function testFullSimulationWithLogs() public {
        console2.log("==============================================");
        console2.log("         STARTING FULL SIMULATION");
        console2.log("==============================================\n");
        console2.log("Setup: 90% Supply provided to V4 Pool");
        console2.log("Starting Market Cap valuation: ~20k USD\n");

        // Alice stakes 1M IRL tokens
        vm.startPrank(alice);
        irl.approve(address(staking), type(uint256).max);
        staking.stake(1_000_000 ether);
        vm.stopPrank();
        console2.log("-> Alice stakes 1,000,000 IRL");

        // Alice swaps 0.5 ETH for IRL
        vm.startPrank(alice);
        weth.deposit{value: 0.5 ether}();
        weth.approve(address(swapRouter), type(uint256).max);
        weth.approve(address(permit2), type(uint256).max);
        permit2.approve(address(weth), address(swapRouter), type(uint160).max, type(uint48).max);
        bool zeroForOneAlice = address(weth) < address(irl);
        swapRouter.swapExactTokensForTokens({
            amountIn: 0.5 ether,
            amountOutMin: 0,
            zeroForOne: zeroForOneAlice,
            poolKey: poolKey,
            hookData: abi.encode(alice),
            receiver: alice,
            deadline: type(uint256).max
        });
        vm.stopPrank();
        console2.log("-> Alice swaps 0.5 ETH to buy IRL. (Triggers Hook Tax)");

        // Bob swaps 1 ETH for IRL
        vm.startPrank(bob);
        weth.deposit{value: 1 ether}();
        weth.approve(address(swapRouter), type(uint256).max);
        weth.approve(address(permit2), type(uint256).max);
        permit2.approve(address(weth), address(swapRouter), type(uint160).max, type(uint48).max);
        bool zeroForOneBob = address(weth) < address(irl);
        swapRouter.swapExactTokensForTokens({
            amountIn: 1 ether,
            amountOutMin: 0,
            zeroForOne: zeroForOneBob,
            poolKey: poolKey,
            hookData: abi.encode(bob),
            receiver: bob,
            deadline: type(uint256).max
        });
        vm.stopPrank();
        console2.log("-> Bob swaps 1.0 ETH to buy IRL. (Triggers Hook Tax)\n");

        console2.log("--- End of the Hour Metrics ---");
        console2.log("Lottery Pot:", hook.lotteryPot());
        console2.log("Hourly Reward Pot:", hook.hourlyRewardPot());
        console2.log("Alice Tickets (NFTs):", nft.balanceOf(alice));
        console2.log("Bob Tickets (NFTs):", nft.balanceOf(bob));
        console2.log("\n");

        // Advance 1 hour
        vm.warp(1001 hours);
        
        console2.log("==============================================");
        console2.log("  EXECUTING AUTOMATION (HOURLY REWARDS)");
        console2.log("==============================================\n");
        uint256 aliceEthBefore = alice.balance;
        uint256 bobEthBefore = bob.balance;

        // Chainlink Keeper Upkeep Check
        (bool upkeepNeeded, bytes memory performData) = hook.checkUpkeep("");
        require(upkeepNeeded, "Upkeep should be needed");
        
        // Execute Hourly distribution (Setup)
        hook.performUpkeep(performData);
        
        // Execute queue batch
        (bool queueNeeded, bytes memory queueData) = hook.checkUpkeep("");
        require(queueNeeded, "Queue should be needed");
        hook.performUpkeep(queueData);
        
        console2.log("-> Hourly Rewards distributed!");
        console2.log("Alice ETH gained from Cashback & Top Rewards:", alice.balance - aliceEthBefore);
        console2.log("Bob ETH gained from Cashback & Top Rewards:", bob.balance - bobEthBefore);
        console2.log("\n");

        console2.log("==============================================");
        console2.log("      EXECUTING LOTTERY (END OF DAY)");
        console2.log("==============================================\n");
        vm.warp(1025 hours); // Next day
        
        (bool lotteryNeeded, bytes memory lotteryData) = hook.checkUpkeep("");
        require(lotteryNeeded, "Lottery upkeep should be needed");
        
        // Request VRF
        hook.performUpkeep(lotteryData);
        console2.log("-> Lottery Triggered. Chainlink VRF Request Sent.");
        
        // Fulfill OpenVRF manually
        uint256 requestId = 1; 
        uint256 randomWord = 777; // Lucky number
        
        uint256 aliceEthBeforeLottery = alice.balance;
        uint256 bobEthBeforeLottery = bob.balance;

        console2.log("Hook ETH Balance before Lottery:", address(hook).balance);

        openVrfMock.fulfillMock(requestId, randomWord);

        console2.log("-> Lottery VRF Fulfilled.");
        uint256 aliceGained = alice.balance - aliceEthBeforeLottery;
        uint256 bobGained = bob.balance - bobEthBeforeLottery;
        
        if (aliceGained > 0) {
            console2.log("*** ALICE WON THE LOTTERY! Prize:", aliceGained, "***");
        } else if (bobGained > 0) {
            console2.log("*** BOB WON THE LOTTERY! Prize:", bobGained, "***");
        } else {
            console2.log("SOMEONE ELSE WON (or fail).");
        }
        console2.log("\n==============================================");
    }

    function testMassiveSimulation() public {
        vm.warp(1002 hours);
        
        console2.log("==============================================");
        console2.log("    STARTING MASSIVE SIMULATION (300 USERS)");
        console2.log("==============================================");
        
        bool zeroForOne = address(weth) < address(irl);
        
        for (uint160 i = 1; i <= 300; i++) {
            address user = address(uint160(0x10000 + i));
            
            vm.startPrank(user);
            vm.deal(user, 1 ether);
            weth.deposit{value: 0.01 ether}();
            weth.approve(address(swapRouter), type(uint256).max);
            weth.approve(address(permit2), type(uint256).max);
            permit2.approve(address(weth), address(swapRouter), type(uint160).max, type(uint48).max);
            
            swapRouter.swapExactTokensForTokens({
                amountIn: 0.01 ether,
                amountOutMin: 0,
                zeroForOne: zeroForOne,
                poolKey: poolKey,
                hookData: abi.encode(user),
                receiver: user,
                deadline: type(uint256).max
            });
            vm.stopPrank();
        }
        
        console2.log("300 swaps completed.");
        console2.log("Hourly Reward Pot:", hook.hourlyRewardPot());
        
        vm.warp(1003 hours);
        console2.log("\nExecuting Automations for 300 USERS...");
        
        (bool upkeepNeeded, bytes memory performData) = hook.checkUpkeep("");
        require(upkeepNeeded, "Upkeep setup needed");
        hook.performUpkeep(performData);
        
        uint256 batches = 0;
        while (true) {
            (bool queueNeeded, bytes memory queueData) = hook.checkUpkeep("");
            if (!queueNeeded) break;
            
            uint256 gasBefore = gasleft();
            hook.performUpkeep(queueData);
            uint256 gasUsed = gasBefore - gasleft();
            
            if (batches == 0) {
                console2.log("Gas used for a full batch of 50 users:", gasUsed);
            }
            batches++;
        }
        
        console2.log("Completed distribution in batches:", batches);
        
        console2.log("\nStarting 500 swaps for Day 2...");
        vm.warp(1026 hours);
        
        for (uint160 i = 1; i <= 500; i++) {
            address user = address(uint160(0x20000 + i));
            
            vm.startPrank(user);
            vm.deal(user, 1 ether);
            weth.deposit{value: 0.01 ether}();
            weth.approve(address(swapRouter), type(uint256).max);
            weth.approve(address(permit2), type(uint256).max);
            permit2.approve(address(weth), address(swapRouter), type(uint160).max, type(uint48).max);
            
            swapRouter.swapExactTokensForTokens({
                amountIn: 0.01 ether,
                amountOutMin: 0,
                zeroForOne: zeroForOne,
                poolKey: poolKey,
                hookData: abi.encode(user),
                receiver: user,
                deadline: type(uint256).max
            });
            vm.stopPrank();
        }
        
        console2.log("500 swaps completed.");
        console2.log("Total minted NFTs:", nft.totalTicketsMinted());
    }

    function testProgrammableFeeRoutingAndClaiming() public {
        address programmableRecipient = 0xD88539d3c4C460136a733A3Fd60cf6BF269079da;

        // 1. Initial state: recipient is hardcoded to 0xD88539d3c4C460136a733A3Fd60cf6BF269079da, pot is 0
        assertEq(hook.programmableFeeRecipient(), programmableRecipient);
        assertEq(hook.PROGRAMMABLE_FEE_RECIPIENT(), programmableRecipient);
        assertEq(hook.PROGRAMMABLE_FEE_BPS(), 30);
        assertEq(hook.programmableFeePot(), 0);

        uint256 recipientEthBefore = programmableRecipient.balance;

        // Perform 1 ETH swap from Alice
        vm.startPrank(alice);
        weth.deposit{value: 1.0 ether}();
        weth.approve(address(swapRouter), type(uint256).max);
        weth.approve(address(permit2), type(uint256).max);
        permit2.approve(address(weth), address(swapRouter), type(uint160).max, type(uint48).max);
        bool zeroForOne = address(weth) < address(irl);

        swapRouter.swapExactTokensForTokens({
            amountIn: 1.0 ether,
            amountOutMin: 0,
            zeroForOne: zeroForOne,
            poolKey: poolKey,
            hookData: abi.encode(alice),
            receiver: alice,
            deadline: type(uint256).max
        });
        vm.stopPrank();

        // 4% total tax = 0.04 ETH. Programmable share (0.30%) = 0.003 ETH routed directly.
        assertEq(programmableRecipient.balance - recipientEthBefore, 0.003 ether);
        assertEq(hook.programmableFeePot(), 0);

        // 2. Test direct automatic routing on subsequent swaps
        vm.startPrank(bob);
        weth.deposit{value: 2.0 ether}();
        weth.approve(address(swapRouter), type(uint256).max);
        weth.approve(address(permit2), type(uint256).max);
        permit2.approve(address(weth), address(swapRouter), type(uint160).max, type(uint48).max);

        uint256 recipientEthBeforeBob = programmableRecipient.balance;
        swapRouter.swapExactTokensForTokens({
            amountIn: 2.0 ether,
            amountOutMin: 0,
            zeroForOne: zeroForOne,
            poolKey: poolKey,
            hookData: abi.encode(bob),
            receiver: bob,
            deadline: type(uint256).max
        });
        vm.stopPrank();

        // 2 ETH swap * 4% tax = 0.08 ETH. Programmable 0.30% = 0.006 ETH routed directly!
        assertEq(programmableRecipient.balance - recipientEthBeforeBob, 0.006 ether);
        assertEq(hook.programmableFeePot(), 0);
    }
}


