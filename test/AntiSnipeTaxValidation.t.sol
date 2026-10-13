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
import {InternetRobinLottery} from "../src/InternetRobinLottery.sol";
import {IRLStaking} from "../src/IRLStaking.sol";
import {OpenVRF} from "openvrf/OpenVRF.sol";

contract MockWETHAntiSnipe {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function deposit() external payable {
        balanceOf[msg.sender] += msg.value;
    }

    function withdraw(uint wad) external {
        require(balanceOf[msg.sender] >= wad, "Insufficient WETH");
        balanceOf[msg.sender] -= wad;
        (bool success, ) = msg.sender.call{value: wad}("");
        require(success, "ETH transfer failed");
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 val) external returns (bool) {
        require(balanceOf[msg.sender] >= val, "Insufficient WETH");
        balanceOf[msg.sender] -= val;
        balanceOf[to] += val;
        return true;
    }

    function transferFrom(address from, address to, uint256 val) external returns (bool) {
        if (from != msg.sender && allowance[from][msg.sender] != type(uint256).max) {
            require(allowance[from][msg.sender] >= val, "Insufficient allowance");
            allowance[from][msg.sender] -= val;
        }
        require(balanceOf[from] >= val, "Insufficient WETH");
        balanceOf[from] -= val;
        balanceOf[to] += val;
        return true;
    }
}

contract RejectingDevWallet {
    // Rejects incoming native ETH to test fallback buffer pot
    receive() external payable {
        revert("Rejecting dev ETH");
    }
}

contract AntiSnipeTaxValidationTest is BaseTest {
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
    MockWETHAntiSnipe weth;
    OpenVRF openVrf;

    address deployer = address(0xAA11);
    address devWallet = address(0xDE77);
    address progRecipient = address(0xBB99);
    address whitelistedTrader = address(0xCC33);
    address sniper = address(0x5511);

    uint256 tokenId;

    function setUp() public {
        deployArtifactsAndLabel();

        vm.deal(deployer, 1000 ether);
        vm.deal(whitelistedTrader, 100 ether);
        vm.deal(sniper, 100 ether);

        vm.startPrank(deployer);

        openVrf = new OpenVRF(deployer, deployer, 0);
        weth = new MockWETHAntiSnipe();
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

        uint160 hookFlags = uint160(
            Hooks.BEFORE_SWAP_FLAG | 
            Hooks.AFTER_SWAP_FLAG | 
            Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG | 
            Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        );
        address flags = address(hookFlags ^ (0x7777 << 144));

        bytes memory constructorArgs = abi.encode(
            poolManager, 
            address(nft), 
            address(staking), 
            address(openVrf), 
            address(weth)
        );
        deployCodeTo("IRLUniswapV4Hook.sol:IRLUniswapV4Hook", constructorArgs, flags);
        hook = IRLUniswapV4Hook(payable(flags));

        nft.transferOwnership(address(hook));
        openVrf.setConsumerAuthorization(address(hook), true);

        // Configure dev wallet & programmable recipient
        hook.setDevWallet(devWallet);
        hook.setProgrammableFeeRecipient(progRecipient);

        // Configure Whitelist
        hook.setAntiSnipeWhitelist(whitelistedTrader, true);

        // Create and initialize pool
        poolKey = PoolKey(currency0, currency1, 3000, 60, IHooks(hook));
        poolId = poolKey.toId();
        poolManager.initialize(poolKey, Constants.SQRT_PRICE_1_1);

        // Provide full-range liquidity to the pool with Permit2 approvals
        irl.approve(address(permit2), type(uint256).max);
        irl.approve(address(swapRouter), type(uint256).max);
        weth.approve(address(permit2), type(uint256).max);
        weth.approve(address(swapRouter), type(uint256).max);

        permit2.approve(address(irl), address(positionManager), type(uint160).max, type(uint48).max);
        permit2.approve(address(irl), address(poolManager), type(uint160).max, type(uint48).max);
        permit2.approve(address(weth), address(positionManager), type(uint160).max, type(uint48).max);
        permit2.approve(address(weth), address(poolManager), type(uint160).max, type(uint48).max);

        weth.deposit{value: 500 ether}();

        int24 tickLower = TickMath.minUsableTick(poolKey.tickSpacing);
        int24 tickUpper = TickMath.maxUsableTick(poolKey.tickSpacing);
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
            deployer,
            block.timestamp + 1000,
            Constants.ZERO_BYTES
        );

        vm.stopPrank();

        // Setup traders with deposits and Permit2 approvals
        vm.startPrank(whitelistedTrader);
        weth.deposit{value: 10 ether}();
        weth.approve(address(permit2), type(uint256).max);
        weth.approve(address(swapRouter), type(uint256).max);
        permit2.approve(address(weth), address(swapRouter), type(uint160).max, type(uint48).max);
        vm.stopPrank();

        vm.startPrank(sniper);
        weth.deposit{value: 10 ether}();
        weth.approve(address(permit2), type(uint256).max);
        weth.approve(address(swapRouter), type(uint256).max);
        permit2.approve(address(weth), address(swapRouter), type(uint160).max, type(uint48).max);
        vm.stopPrank();
    }

    function test_AntiSnipe_WhitelistedAddress_PaysNormalTax() public {
        vm.startPrank(deployer);
        hook.launch();
        vm.stopPrank();

        uint256 devBalBefore = devWallet.balance;
        uint256 progBalBefore = progRecipient.balance;

        // Whitelisted trader swaps 1.0 WETH for IRL tokens during the first minute (at t=10s)
        vm.warp(hook.launchTimestamp() + 10);

        vm.startPrank(whitelistedTrader);
        deal(Currency.unwrap(currency0), whitelistedTrader, 10 ether);
        deal(Currency.unwrap(currency1), whitelistedTrader, 10 ether);

        bool zeroForOne = Currency.unwrap(poolKey.currency0) == address(weth);

        swapRouter.swapExactTokensForTokens({
            amountIn: 1.0 ether,
            amountOutMin: 0,
            zeroForOne: zeroForOne,
            poolKey: poolKey,
            hookData: abi.encode(whitelistedTrader),
            receiver: whitelistedTrader,
            deadline: block.timestamp + 1
        });
        vm.stopPrank();

        // 1. Dev wallet should NOT receive 90% snipe tax
        assertEq(devWallet.balance - devBalBefore, 0, "Whitelisted trader should not trigger 90% dev tax");

        // 2. Programmable.market receives standard 1% tax (0.01 WETH)
        assertEq(progRecipient.balance - progBalBefore, 0.01 ether, "Programmable receives standard 1% fee");

        // 3. Whitelisted trader receives volume & leaderboard score
        uint256 hourId = block.timestamp / 1 hours;
        assertGt(hook.userVolumePerHour(hourId, whitelistedTrader), 0, "Whitelisted trader should have volume recorded");
        assertGt(hook.userHourlyScore(hourId, whitelistedTrader), 0, "Whitelisted trader should have score recorded");
    }

    function test_AntiSnipe_NonWhitelistedSniper_Pays90PercentDevAnd1PercentProg() public {
        vm.startPrank(deployer);
        hook.launch();
        vm.stopPrank();

        uint256 devBalBefore = devWallet.balance;
        uint256 progBalBefore = progRecipient.balance;

        // Sniper swaps 1.0 WETH for IRL tokens in the first minute (at t=15s)
        vm.warp(hook.launchTimestamp() + 15);

        vm.startPrank(sniper);
        deal(Currency.unwrap(currency0), sniper, 10 ether);
        deal(Currency.unwrap(currency1), sniper, 10 ether);

        bool zeroForOne = Currency.unwrap(poolKey.currency0) == address(weth);

        swapRouter.swapExactTokensForTokens({
            amountIn: 1.0 ether,
            amountOutMin: 0,
            zeroForOne: zeroForOne,
            poolKey: poolKey,
            hookData: abi.encode(sniper),
            receiver: sniper,
            deadline: block.timestamp + 1
        });
        vm.stopPrank();

        // 1. Dev wallet receives EXACTLY 90% tax (0.90 ETH)
        uint256 devReceived = devWallet.balance - devBalBefore;
        assertEq(devReceived, 0.90 ether, "Dev wallet must receive exactly 90% of swap amount");

        // 2. Programmable.market receives EXACTLY 1% tax (0.01 ETH)
        uint256 progReceived = progRecipient.balance - progBalBefore;
        assertEq(progReceived, 0.01 ether, "Programmable.market must receive exactly 1% of swap amount");

        // 3. Sniper gets ZERO volume leaderboard score and ZERO NFT tickets
        uint256 hourId = block.timestamp / 1 hours;
        assertEq(hook.userVolumePerHour(hourId, sniper), 0, "Sniper must have 0 volume recorded");
        assertEq(hook.userHourlyScore(hourId, sniper), 0, "Sniper must have 0 score recorded");
        assertEq(nft.balanceOf(sniper), 0, "Sniper must receive 0 NFT tickets");
    }

    function test_AntiSnipe_AfterOneMinute_EveryonePaysNormalTax() public {
        vm.startPrank(deployer);
        hook.launch();
        vm.stopPrank();

        uint256 devBalBefore = devWallet.balance;
        uint256 progBalBefore = progRecipient.balance;

        // Fast-forward past the 1-minute anti-snipe window (t = launch + 65 seconds)
        vm.warp(hook.launchTimestamp() + 65);

        assertFalse(hook.isAntiSnipeActive(), "Anti-snipe window should be inactive after 1 minute");

        vm.startPrank(sniper);
        deal(Currency.unwrap(currency0), sniper, 10 ether);
        deal(Currency.unwrap(currency1), sniper, 10 ether);

        bool zeroForOne = Currency.unwrap(poolKey.currency0) == address(weth);

        swapRouter.swapExactTokensForTokens({
            amountIn: 1.0 ether,
            amountOutMin: 0,
            zeroForOne: zeroForOne,
            poolKey: poolKey,
            hookData: abi.encode(sniper),
            receiver: sniper,
            deadline: block.timestamp + 1
        });
        vm.stopPrank();

        // 1. Dev wallet does NOT receive 90% (pays standard 4% tax to ecosystem pots)
        assertEq(devWallet.balance - devBalBefore, 0, "Dev wallet must not receive 90% tax after 1 minute");

        // 2. Programmable.market still receives 1% standard fee (0.01 ETH)
        assertEq(progRecipient.balance - progBalBefore, 0.01 ether, "Programmable receives standard 1% fee");

        // 3. Trader is now treated as legitimate: gets volume and tickets
        uint256 hourId = block.timestamp / 1 hours;
        assertGt(hook.userVolumePerHour(hourId, sniper), 0, "Volume should be recorded after anti-snipe expires");
        assertGt(nft.balanceOf(sniper), 0, "NFT tickets should be minted after anti-snipe expires");
    }

    function test_AntiSnipe_RemoveLimitsDisablesAntiSnipeImmediately() public {
        vm.startPrank(deployer);
        hook.launch();
        // Owner explicitly removes limits
        hook.removeLimits();
        vm.stopPrank();

        assertFalse(hook.isAntiSnipeActive(), "Anti-snipe should be inactive when limits are removed");

        uint256 devBalBefore = devWallet.balance;

        // Sniper swaps within 10s of launch, but limits were removed
        vm.warp(hook.launchTimestamp() + 10);

        vm.startPrank(sniper);
        deal(Currency.unwrap(currency0), sniper, 10 ether);
        deal(Currency.unwrap(currency1), sniper, 10 ether);

        bool zeroForOne = Currency.unwrap(poolKey.currency0) == address(weth);

        swapRouter.swapExactTokensForTokens({
            amountIn: 1.0 ether,
            amountOutMin: 0,
            zeroForOne: zeroForOne,
            poolKey: poolKey,
            hookData: abi.encode(sniper),
            receiver: sniper,
            deadline: block.timestamp + 1
        });
        vm.stopPrank();

        assertEq(devWallet.balance - devBalBefore, 0, "No 90% tax when limits are disabled");
    }

    function test_AntiSnipe_BatchWhitelist() public {
        address[] memory addresses = new address[](3);
        addresses[0] = address(0x1111);
        addresses[1] = address(0x2222);
        addresses[2] = address(0x3333);

        vm.startPrank(deployer);
        hook.setAntiSnipeWhitelistBatch(addresses, true);
        vm.stopPrank();

        assertTrue(hook.antiSnipeWhitelist(addresses[0]));
        assertTrue(hook.antiSnipeWhitelist(addresses[1]));
        assertTrue(hook.antiSnipeWhitelist(addresses[2]));

        // Remove one address
        vm.startPrank(deployer);
        hook.setAntiSnipeWhitelist(addresses[1], false);
        vm.stopPrank();

        assertTrue(hook.antiSnipeWhitelist(addresses[0]));
        assertFalse(hook.antiSnipeWhitelist(addresses[1]));
        assertTrue(hook.antiSnipeWhitelist(addresses[2]));
    }

    function test_AntiSnipe_FallbackDevPotIfCallFails() public {
        RejectingDevWallet rejectingWallet = new RejectingDevWallet();

        vm.startPrank(deployer);
        hook.setDevWallet(address(rejectingWallet));
        hook.launch();
        vm.stopPrank();

        vm.warp(hook.launchTimestamp() + 5);

        vm.startPrank(sniper);
        deal(Currency.unwrap(currency0), sniper, 10 ether);
        deal(Currency.unwrap(currency1), sniper, 10 ether);

        bool zeroForOne = Currency.unwrap(poolKey.currency0) == address(weth);

        // Swap must NOT revert even if dev wallet call fails
        swapRouter.swapExactTokensForTokens({
            amountIn: 1.0 ether,
            amountOutMin: 0,
            zeroForOne: zeroForOne,
            poolKey: poolKey,
            hookData: abi.encode(sniper),
            receiver: sniper,
            deadline: block.timestamp + 1
        });
        vm.stopPrank();

        // 90% tax safely buffered in devSnipeTaxPot
        assertEq(hook.devSnipeTaxPot(), 0.90 ether, "Dev snipe tax must be safely stored in fallback pot");

        // Owner or new dev wallet can claim it
        address newDev = address(0x8888);
        vm.startPrank(deployer);
        hook.setDevWallet(newDev);
        hook.claimDevSnipeTax();
        vm.stopPrank();

        assertEq(newDev.balance, 0.90 ether, "New dev wallet successfully claimed accumulated snipe fees");
        assertEq(hook.devSnipeTaxPot(), 0, "Fallback pot must be reset to 0 after claim");
    }

    function test_AntiSnipe_AutoLaunchOnFirstSwap_WithoutManualCall() public {
        // Confirm launchTimestamp is uninitialized (0)
        assertEq(hook.launchTimestamp(), 0, "Launch timestamp must initially be 0");

        uint256 devBalBefore = devWallet.balance;
        uint256 progBalBefore = progRecipient.balance;

        // Sniper swaps 1.0 WETH at t = 5000 WITHOUT the deployer ever calling hook.launch()
        vm.warp(5000);

        vm.startPrank(sniper);
        deal(Currency.unwrap(currency0), sniper, 10 ether);
        deal(Currency.unwrap(currency1), sniper, 10 ether);

        bool zeroForOne = Currency.unwrap(poolKey.currency0) == address(weth);

        swapRouter.swapExactTokensForTokens({
            amountIn: 1.0 ether,
            amountOutMin: 0,
            zeroForOne: zeroForOne,
            poolKey: poolKey,
            hookData: abi.encode(sniper),
            receiver: sniper,
            deadline: block.timestamp + 1
        });
        vm.stopPrank();

        // 1. launchTimestamp was automatically initialized on the first swap
        assertEq(hook.launchTimestamp(), 5000, "launchTimestamp should auto-initialize on the first swap");

        // 2. Sniper was caught and taxed 90% dev + 1% programmable
        assertEq(devWallet.balance - devBalBefore, 0.90 ether, "Dev receives 90% automatically");
        assertEq(progRecipient.balance - progBalBefore, 0.01 ether, "Programmable receives 1% automatically");

        // 3. Sniper gets zero perks
        assertEq(nft.balanceOf(sniper), 0, "Sniper receives 0 NFT tickets");
    }

    function test_AntiWhale_AutoDisableAt50kMarketCap() public {
        // Set auto-disable price threshold from initial pool price (20k MC -> 50k MC = 2.5x increase)
        bool isIrl0 = (address(irl) < address(weth));
        vm.startPrank(deployer);
        hook.setDisableAntiWhaleFromInitialPrice(Constants.SQRT_PRICE_1_1, isIrl0);
        vm.stopPrank();

        assertTrue(hook.limitsEnabled(), "Limits must be active before reaching 50k MC");
        uint160 target50k = hook.disableAntiWhaleSqrtPrice();
        assertGt(target50k, 0, "50k MC threshold must be configured");

        // Simulate reaching 50k MC by calling setDisableAntiWhalePrice with current price
        vm.startPrank(deployer);
        hook.setDisableAntiWhalePrice(Constants.SQRT_PRICE_1_1);
        vm.stopPrank();

        // Whitelisted trader performs a swap to trigger tick update
        vm.warp(hook.launchTimestamp() + 120);
        vm.startPrank(whitelistedTrader);
        deal(Currency.unwrap(currency0), whitelistedTrader, 10 ether);
        deal(Currency.unwrap(currency1), whitelistedTrader, 10 ether);

        bool zeroForOne = Currency.unwrap(poolKey.currency0) == address(weth);
        swapRouter.swapExactTokensForTokens({
            amountIn: 0.1 ether,
            amountOutMin: 0,
            zeroForOne: zeroForOne,
            poolKey: poolKey,
            hookData: abi.encode(whitelistedTrader),
            receiver: whitelistedTrader,
            deadline: block.timestamp + 1
        });
        vm.stopPrank();

        // Limits are now automatically disabled onchain
        assertFalse(hook.limitsEnabled(), "Limits must be automatically disabled once 50k MC price is reached");
    }

    function test_AntiSnipe_SpoofedHookDataRejected() public {
        vm.startPrank(deployer);
        hook.launch();
        vm.stopPrank();

        uint256 devBalBefore = devWallet.balance;
        vm.warp(hook.launchTimestamp() + 10);

        // Sniper attempts to spoof address(hook) or deployer via hookData during the 60s Anti-Snipe window
        vm.startPrank(sniper, sniper);
        deal(Currency.unwrap(currency0), sniper, 10 ether);
        deal(Currency.unwrap(currency1), sniper, 10 ether);

        bool zeroForOne = Currency.unwrap(poolKey.currency0) == address(weth);
        swapRouter.swapExactTokensForTokens({
            amountIn: 1.0 ether,
            amountOutMin: 0,
            zeroForOne: zeroForOne,
            poolKey: poolKey,
            hookData: abi.encode(address(hook)),
            receiver: sniper,
            deadline: block.timestamp + 1
        });
        vm.stopPrank();

        // Spoofed hookData is rejected; sniper is still taxed 90% to devWallet!
        assertEq(devWallet.balance - devBalBefore, 0.90 ether, "Spoofing hook address via hookData must be rejected and taxed 90%");
    }

    function test_NFTTicket_OnChainHoldingCapEnforced() public {
        IRLTicketNFT cappedNft = new IRLTicketNFT(deployer);
        vm.startPrank(deployer);
        // Mint 42 tickets to sniper (non-staker max weekly cap = 42) and 1 ticket to whitelistedTrader
        for (uint256 i = 0; i < 42; i++) {
            cappedNft.mintTicket(sniper);
        }
        uint256 extraTicketId = cappedNft.mintTicket(whitelistedTrader);
        cappedNft.transferOwnership(address(hook));
        vm.stopPrank();

        assertEq(cappedNft.balanceOf(sniper), 42);

        // Secondary transfer of the 43rd ticket to non-staker must revert on-chain
        vm.startPrank(whitelistedTrader);
        vm.expectRevert("IRLTicketNFT: Weekly ticket holding cap exceeded");
        cappedNft.transferFrom(whitelistedTrader, sniper, extraTicketId);
        vm.stopPrank();
    }
}
