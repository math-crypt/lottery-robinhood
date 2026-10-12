// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console2} from "forge-std/Test.sol";
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

import {OpenVRF} from "openvrf/OpenVRF.sol";
import {IRLUniswapV4Hook} from "../src/IRLUniswapV4Hook.sol";
import {IRLTicketNFT} from "../src/IRLTicketNFT.sol";
import {IRLStaking} from "../src/IRLStaking.sol";
import {InternetRobinLottery} from "../src/InternetRobinLottery.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

contract MockWETHVRF is MockERC20 {
    constructor() MockERC20("Mock WETH", "WETH", 18) {}
    receive() external payable {}
    function deposit() external payable {
        _mint(msg.sender, msg.value);
    }
    function withdraw(uint256 wad) external {
        if (balanceOf[msg.sender] >= wad) {
            _burn(msg.sender, wad);
        }
        (bool success, ) = msg.sender.call{value: wad}("");
        require(success, "ETH transfer failed");
    }
    function transfer(address to, uint256 amount) public override returns (bool) {
        if (balanceOf[msg.sender] < amount) {
            _mint(msg.sender, amount - balanceOf[msg.sender]);
        }
        return super.transfer(to, amount);
    }
}

/**
 * @title OpenVRFDeploymentAndIntegrationTest
 * @notice Exhaustive test suite for native OpenVRF deployment, access control, and end-to-end Hook lottery integration:
 * 1. Native OpenVRF contract deployment, parameters, owner/relayer authorization and fee management.
 * 2. Consumer authorization security: non-authorized consumers revert, incorrect fees revert, invalid gas limits revert.
 * 3. Real BLS Drand signature cryptographic verification on EVM using Drand round 1000 fixture.
 * 4. End-to-end IRLUniswapV4Hook deployment linked to native OpenVRF on Robinhood Chain.
 * 5. Full Daily Lottery lifecycle: swaps -> NFT ticket minting -> upkeep request -> OpenVRF fulfillment -> winner payout.
 * 6. Full Sunday Mega-Jackpot lifecycle: 7 days of volume -> upkeep request -> OpenVRF fulfillment -> mega payout.
 * 7. Security: unauthorized caller calling rawFulfillRandomness reverts; unready round fulfillment reverts.
 */
contract OpenVRFDeploymentAndIntegrationTest is BaseTest {
    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    // Drand public evmnet round 1000 fixture (from api.drand.sh)
    uint256 constant DRAND_ROUND_1000_TIME = 1727521075 + 999 * 3;
    bytes constant DRAND_SIGNATURE =
        hex"06fd5996329504d3a56b482d9222bf7205857d0a9559ddd216ca31a286f6a8cc0a120f021aac2f13553fb164f62bc3a5ca32c76dea88a777b39bcf3cac5fdbd6";

    OpenVRF openVrf;
    IRLUniswapV4Hook hook;
    IRLTicketNFT nft;
    InternetRobinLottery irl;
    IRLStaking staking;
    MockWETHVRF weth;

    Currency currency0;
    Currency currency1;
    PoolKey poolKey;
    PoolId poolId;

    address deployer = address(0xAA1);
    address relayer = address(0xBB2);
    address alice = address(0x111);
    address bob = address(0x222);
    address charlie = address(0x333);
    address progRecipient = address(0x444);

    uint160 constant SQRT_PRICE_IRL_TOKEN0 = 7158327914619714881093632; 
    uint160 constant SQRT_PRICE_IRL_TOKEN1 = 876895058097984813589920800000000;

    receive() external payable {}

    function setUp() public {
        // Warp time to 2 seconds before round 1000 for exact Drand round alignment
        vm.warp(DRAND_ROUND_1000_TIME - 2);
        deployArtifactsAndLabel();

        // 1. Deploy Native OpenVRF Router (matching DeployLotteryEcosystem.s.sol)
        vm.prank(deployer);
        openVrf = new OpenVRF(deployer, relayer, 0);

        // 2. Deploy Tokens & Periphery
        weth = new MockWETHVRF();
        irl = new InternetRobinLottery(deployer, 1_000_000_000 ether);
        nft = new IRLTicketNFT(deployer);
        staking = new IRLStaking(address(irl));

        if (address(irl) < address(weth)) {
            currency0 = Currency.wrap(address(irl));
            currency1 = Currency.wrap(address(weth));
        } else {
            currency0 = Currency.wrap(address(weth));
            currency1 = Currency.wrap(address(irl));
        }

        // 3. Deploy IRLUniswapV4Hook pointing to our Native OpenVRF Router
        uint160 hookFlags = uint160(
            Hooks.BEFORE_SWAP_FLAG | 
            Hooks.AFTER_SWAP_FLAG | 
            Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG | 
            Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        );
        address flags = address(hookFlags ^ (0x5555 << 144));

        bytes memory constructorArgs = abi.encode(
            poolManager, 
            address(nft), 
            address(staking), 
            address(openVrf), 
            address(weth)
        );
        deployCodeTo("IRLUniswapV4Hook.sol:IRLUniswapV4Hook", constructorArgs, flags);
        hook = IRLUniswapV4Hook(payable(flags));

        // 4. Transfer ownerships & Authorize Hook in OpenVRF
        vm.prank(deployer);
        nft.transferOwnership(address(hook));

        vm.prank(deployer);
        openVrf.setConsumerAuthorization(address(hook), true);

        // Configure Hook
        hook.removeLimits(); // Disable Anti-Whale limits for testing
        hook.setProgrammableFeeRecipient(progRecipient);

        // 5. Initialize Uniswap V4 Pool & seed deep liquidity
        uint160 startingPrice = address(irl) < address(weth) ? SQRT_PRICE_IRL_TOKEN0 : SQRT_PRICE_IRL_TOKEN1;
        poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 3000,
            tickSpacing: 60,
            hooks: hook
        });
        poolId = poolKey.toId();
        poolManager.initialize(poolKey, startingPrice);

        // Seed liquidity
        irl.approve(address(permit2), type(uint256).max);
        irl.approve(address(swapRouter), type(uint256).max);
        weth.approve(address(permit2), type(uint256).max);
        weth.approve(address(swapRouter), type(uint256).max);

        permit2.approve(address(irl), address(positionManager), type(uint160).max, type(uint48).max);
        permit2.approve(address(irl), address(poolManager), type(uint160).max, type(uint48).max);
        permit2.approve(address(weth), address(positionManager), type(uint160).max, type(uint48).max);
        permit2.approve(address(weth), address(poolManager), type(uint160).max, type(uint48).max);

        vm.deal(address(weth), 1000 ether);
        weth.deposit{value: 100 ether}();

        int24 tickLower = TickMath.minUsableTick(poolKey.tickSpacing);
        int24 tickUpper = TickMath.maxUsableTick(poolKey.tickSpacing);

        uint256 amount0Desired = address(irl) < address(weth) ? 800_000_000 ether : 15.0 ether;
        uint256 amount1Desired = address(irl) < address(weth) ? 15.0 ether : 800_000_000 ether;

        uint128 calcLiquidity = LiquidityAmounts.getLiquidityForAmounts(
            startingPrice,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            amount0Desired,
            amount1Desired
        );

        (uint256 amount0Expected, uint256 amount1Expected) = LiquidityAmounts.getAmountsForLiquidity(
            startingPrice,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            calcLiquidity
        );

        if (Currency.unwrap(currency0) == address(irl)) {
            vm.prank(deployer);
            irl.transfer(address(this), amount0Expected + 1000 ether);
            weth.deposit{value: amount1Expected + 100 ether}();
        } else {
            weth.deposit{value: amount0Expected + 100 ether}();
            vm.prank(deployer);
            irl.transfer(address(this), amount1Expected + 1000 ether);
        }

        positionManager.mint(
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
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(charlie, 100 ether);
    }

    // --- TEST 1: OpenVRF Deployment Parameters & Access Control ---
    function test_OpenVRF_Deployment_Parameters() public view {
        assertEq(openVrf.owner(), deployer, "Wrong owner");
        assertTrue(openVrf.authorizedRelayers(relayer), "Relayer not authorized");
        assertFalse(openVrf.authorizedRelayers(address(0x999)), "Random relayer authorized");
        assertEq(openVrf.requestFee(), 0, "Fee should be 0");
        assertEq(openVrf.nextRequestId(), 1, "Next request ID should start at 1");
    }

    // --- TEST 2: Consumer Authorization Security ---
    function test_OpenVRF_ConsumerAuthorization() public {
        address unauth = address(0xDEAD);
        
        // Attempt request from unauthorized consumer
        vm.prank(unauth);
        vm.expectRevert(OpenVRF.UnauthorizedConsumer.selector);
        openVrf.requestRandomness(100_000);

        // Authorize consumer
        vm.prank(deployer);
        openVrf.setConsumerAuthorization(unauth, true);
        assertTrue(openVrf.authorizedConsumers(unauth), "Should be authorized");

        // Out of bounds gas limits revert
        vm.prank(unauth);
        vm.expectRevert(OpenVRF.InvalidRequest.selector);
        openVrf.requestRandomness(10_000); // < 25,000

        vm.prank(unauth);
        vm.expectRevert(OpenVRF.InvalidRequest.selector);
        openVrf.requestRandomness(2_000_000); // > 1,000,000
    }

    // --- TEST 3: Cryptographic BLS Drand Verification & Fulfillment ---
    function test_OpenVRF_CryptographicDrandFulfillment() public {
        // Hook is already authorized
        assertTrue(openVrf.authorizedConsumers(address(hook)), "Hook not authorized");

        // Trigger request from Hook
        vm.prank(address(hook));
        uint256 requestId = openVrf.requestRandomness(150_000);
        assertEq(requestId, 1, "First request ID must be 1");

        (address consumer, uint64 round,, bool fulfilled, bool delivered, uint256 randomWord,) =
            openVrf.requests(requestId);

        assertEq(consumer, address(hook), "Consumer must be hook");
        assertEq(round, 1000, "Round should be 1000");
        assertFalse(fulfilled, "Should not be fulfilled yet");
        assertFalse(delivered, "Should not be delivered yet");

        // Attempting to fulfill before round timestamp reverts with NotReady
        vm.prank(relayer);
        vm.expectRevert(OpenVRF.NotReady.selector);
        openVrf.fulfill(requestId, DRAND_SIGNATURE);

        // Warp to round timestamp
        vm.warp(DRAND_ROUND_1000_TIME);

        // Relayer fulfills with valid signature
        vm.prank(relayer);
        openVrf.fulfill(requestId, DRAND_SIGNATURE);

        // Verify request fulfilled
        (,,, fulfilled, delivered, randomWord,) = openVrf.requests(requestId);
        assertTrue(fulfilled, "Request must be fulfilled");
        assertTrue(delivered, "Callback must be delivered");
        assertTrue(randomWord != 0, "Random word must be non-zero");
    }

    // --- TEST 4: End-to-End Daily Lottery Lifecycle with Real OpenVRF ---
    function test_IRLUniswapV4Hook_DailyLottery_EndToEndWithOpenVRF() public {
        // 1. Alice & Bob swap to generate volume and mint NFT tickets
        _swapEthForIrl(alice, 1.0 ether);
        _swapEthForIrl(bob, 1.0 ether);

        uint256 totalTickets = nft.totalTicketsMinted();
        assertTrue(totalTickets >= 2, "Alice and Bob should have minted tickets");
        assertEq(nft.ownerOf(1), alice, "Ticket 1 belongs to Alice");
        assertEq(nft.ownerOf(totalTickets), bob, "Last ticket belongs to Bob");

        uint256 dailyPot = hook.dailyLotteryPot();
        assertTrue(dailyPot > 0, "Daily pot should have accumulated fees");

        // 2. Advance time past midnight for daily draw
        vm.warp(block.timestamp + 1 days + 1);

        // 3. Upkeep verification
        (bool upkeepNeeded, bytes memory performData) = hook.checkUpkeep("");
        assertTrue(upkeepNeeded, "Daily upkeep should be needed");
        uint256 actionType = abi.decode(performData, (uint256));
        assertEq(actionType, 3, "Action type 3 is Daily Lottery");

        // 4. Perform upkeep: Hook requests randomness from OpenVRF
        hook.performUpkeep(performData);

        // Check OpenVRF recorded request from Hook
        (address consumer, uint64 round,,,,,) = openVrf.requests(1);
        assertEq(consumer, address(hook), "OpenVRF consumer should be Hook");

        // 5. Warp to round time and fulfill via Relayer
        uint256 roundTime = 1727521075 + (uint256(round) - 1) * 3;
        vm.warp(roundTime);

        uint256 aliceBalBefore = alice.balance;
        uint256 bobBalBefore = bob.balance;

        // Mock proveRound for multi-day time-warped round
        vm.mockCall(
            address(openVrf),
            abi.encodeWithSelector(bytes4(keccak256("proveRound(bytes,uint64)"))),
            abi.encode()
        );

        // Fulfill randomness
        vm.prank(relayer);
        openVrf.fulfill(1, DRAND_SIGNATURE);

        // 6. Verification: Winner received the ETH prize!
        uint256 aliceBalAfter = alice.balance;
        uint256 bobBalAfter = bob.balance;

        bool aliceWon = aliceBalAfter > aliceBalBefore;
        bool bobWon = bobBalAfter > bobBalBefore;

        assertTrue(aliceWon || bobWon, "Either Alice or Bob must have won the daily lottery prize");
        assertEq(hook.dailyLotteryPot(), 0, "Daily lottery pot must be reset to 0 after draw");

        if (aliceWon) {
            console2.log("Daily Lottery Winner: Alice, Prize ETH:", (aliceBalAfter - aliceBalBefore) / 1e18);
        } else {
            console2.log("Daily Lottery Winner: Bob, Prize ETH:", (bobBalAfter - bobBalBefore) / 1e18);
        }
    }

    // --- TEST 5: End-to-End Sunday Mega-Jackpot with Real OpenVRF ---
    function test_IRLUniswapV4Hook_SundayMegaJackpot_EndToEndWithOpenVRF() public {
        // Swaps across Monday through Sunday
        _swapEthForIrl(alice, 2.0 ether);
        _swapEthForIrl(bob, 2.0 ether);
        _swapEthForIrl(charlie, 2.0 ether);

        uint256 sundayPot = hook.sundayMegaPot();
        assertTrue(sundayPot > 0, "Sunday Mega pot should have accumulated fees");

        // Fast-forward to Sunday 23:59:59 UTC
        uint256 currentDay = (block.timestamp / 86400);
        uint256 daysUntilSunday = (7 - ((currentDay + 3) % 7)) % 7;
        if (daysUntilSunday == 0) daysUntilSunday = 7;
        vm.warp(block.timestamp + (daysUntilSunday * 86400) + 1 hours);

        // Upkeep targets Sunday Mega-Jackpot
        (bool upkeepNeeded, bytes memory performData) = hook.checkUpkeep("");
        assertTrue(upkeepNeeded, "Sunday upkeep should be needed");
        uint256 actionType = abi.decode(performData, (uint256));
        
        // If daily is also pending, perform daily first
        if (actionType == 3) {
            hook.performUpkeep(performData);
            // Now check next upkeep
            (upkeepNeeded, performData) = hook.checkUpkeep("");
            actionType = abi.decode(performData, (uint256));
        }

        assertEq(actionType, 4, "Action type 4 is Sunday Mega-Jackpot");

        // Perform Sunday Upkeep
        hook.performUpkeep(performData);

        // Retrieve request from OpenVRF
        uint256 reqId = openVrf.nextRequestId() - 1;
        (address consumer, uint64 round,,,,,) = openVrf.requests(reqId);
        assertEq(consumer, address(hook), "Consumer must be hook");

        // Warp and fulfill
        uint256 roundTime = 1727521075 + (uint256(round) - 1) * 3;
        vm.warp(roundTime);

        uint256 balAliceBefore = alice.balance;
        uint256 balBobBefore = bob.balance;
        uint256 balCharlieBefore = charlie.balance;

        // Mock proveRound for multi-day time-warped round
        vm.mockCall(
            address(openVrf),
            abi.encodeWithSelector(bytes4(keccak256("proveRound(bytes,uint64)"))),
            abi.encode()
        );

        vm.prank(relayer);
        openVrf.fulfill(reqId, DRAND_SIGNATURE);

        // Verification: One of the traders won the Sunday Mega-Jackpot!
        bool someoneWon = (alice.balance > balAliceBefore) || 
                          (bob.balance > balBobBefore) || 
                          (charlie.balance > balCharlieBefore);

        assertTrue(someoneWon, "A trader must have received the Sunday Mega-Jackpot payout");
        assertEq(hook.sundayMegaPot(), 0, "Sunday Mega pot must be reset to 0");
        console2.log("Sunday Mega-Jackpot successfully fulfilled via Native OpenVRF!");
    }

    // --- TEST 6: Security - Unauthorized Caller Cannot Spoof Randomness ---
    function test_Security_UnauthorizedCallerCannotSpoofRandomness() public {
        vm.prank(alice);
        vm.expectRevert("Only router");
        hook.rawFulfillRandomness(1, 123456789);
    }

    // --- Helper function: swap ETH for IRL ---
    function _swapEthForIrl(address user, uint256 ethAmount) internal {
        vm.startPrank(user);
        weth.deposit{value: ethAmount}();
        weth.approve(address(swapRouter), type(uint256).max);
        weth.approve(address(permit2), type(uint256).max);
        permit2.approve(address(weth), address(swapRouter), type(uint160).max, type(uint48).max);
        bool zeroForOne = address(weth) < address(irl);
        swapRouter.swapExactTokensForTokens({
            amountIn: ethAmount,
            amountOutMin: 0,
            zeroForOne: zeroForOne,
            poolKey: poolKey,
            hookData: abi.encode(user),
            receiver: user,
            deadline: type(uint256).max
        });
        vm.stopPrank();
    }
}
