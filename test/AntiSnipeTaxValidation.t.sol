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
import {IRLMarketingVault} from "../src/IRLMarketingVault.sol";
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

contract ToggleableEthRecipient {
    bool public acceptEth = false;

    function setAcceptEth(bool _accept) external {
        acceptEth = _accept;
    }

    function claimFromHook(IRLUniswapV4Hook hook) external {
        hook.claimUnclaimedRewards();
    }

    receive() external payable {
        require(acceptEth, "Temporarily rejecting ETH");
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
    IRLMarketingVault vault;
    MockWETHAntiSnipe weth;
    OpenVRF openVrf;

    address deployer = address(0xAA11);
    address progRecipient = 0xD88539d3c4C460136a733A3Fd60cf6BF269079da;
    address traderA = address(0xCC33);
    address traderB = address(0x5511);

    uint256 tokenId;

    function setUp() public {
        vm.warp(1_728_000_000);
        deployArtifactsAndLabel();

        vm.deal(deployer, 1000 ether);
        vm.deal(traderA, 100 ether);
        vm.deal(traderB, 100 ether);

        vm.startPrank(deployer);

        openVrf = new OpenVRF(deployer, deployer, 0);
        weth = new MockWETHAntiSnipe();
        irl = new InternetRobinLottery(deployer, 1_000_000_000 ether);
        nft = new IRLTicketNFT(deployer);
        staking = new IRLStaking(address(irl));
        vault = new IRLMarketingVault(address(poolManager), address(positionManager), address(irl));

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
        vm.startPrank(traderA);
        weth.deposit{value: 10 ether}();
        weth.approve(address(permit2), type(uint256).max);
        weth.approve(address(swapRouter), type(uint256).max);
        permit2.approve(address(weth), address(swapRouter), type(uint160).max, type(uint48).max);
        vm.stopPrank();

        vm.startPrank(traderB);
        weth.deposit{value: 10 ether}();
        weth.approve(address(permit2), type(uint256).max);
        weth.approve(address(swapRouter), type(uint256).max);
        permit2.approve(address(weth), address(swapRouter), type(uint160).max, type(uint48).max);
        vm.stopPrank();
    }

    function test_LaunchWindow_OneTimeNonResettable_And24HourExpiry() public {
        vm.startPrank(deployer);
        hook.launch();

        // Owner cannot restart the launch window
        vm.expectRevert("AlreadyLaunched");
        hook.launch();
        vm.stopPrank();

        assertTrue(hook.isLaunchTaxActive(), "Launch Boost Tax must be active immediately after launch");

        // Fast-forward 24 hours + 1 second without reaching 100k MC
        vm.warp(hook.launchTimestamp() + hook.LAUNCH_TAX_DURATION() + 1);
        assertFalse(hook.isLaunchTaxActive(), "Launch Boost Tax view must report false after 24 hours");

        uint256 progBefore = progRecipient.balance;
        uint256 dailyBefore = hook.dailyLotteryPot();
        uint256 protocolBefore = hook.protocolPot();
        uint256 burnBefore = hook.buybackPot();

        bool zeroForOne = Currency.unwrap(poolKey.currency0) == address(weth);
        vm.startPrank(traderA);
        deal(Currency.unwrap(currency0), traderA, 10 ether);
        deal(Currency.unwrap(currency1), traderA, 10 ether);

        swapRouter.swapExactTokensForTokens({
            amountIn: 1.0 ether,
            amountOutMin: 0,
            zeroForOne: zeroForOne,
            poolKey: poolKey,
            hookData: abi.encode(traderA),
            receiver: traderA,
            deadline: type(uint256).max
        });
        vm.stopPrank();

        // Storage flag permanently flipped to false and 4.00% Standard Tax applied:
        // - 0.30% Programmable (0.003 ETH)
        // - 1.25% Hourly (0.0125 ETH)
        // - 1.25% Lottery (0.625% Daily = 0.00625 ETH + 0.625% Weekly = 0.00625 ETH)
        // - 1.20% Protocol & Burn (1.08% Protocol = 0.0108 ETH + 0.12% Buyback = 0.0012 ETH)
        assertFalse(hook.launchTaxEnabled(), "launchTaxEnabled storage flag must permanently flip to false after 24h");
        assertEq(progRecipient.balance - progBefore, 0.003 ether, "0.30% Programmable fee after 24h");
        assertEq(hook.dailyLotteryPot() - dailyBefore, 0.00625 ether, "0.625% Daily Lottery after 24h");
        assertEq(hook.protocolPot() - protocolBefore, 0.0108 ether, "1.08% Protocol Pot after 24h");
        assertEq(hook.buybackPot() - burnBefore, 0.0012 ether, "0.12% Buyback Burn Pot after 24h");
    }

    function test_LaunchTax_10PercentUpTo100kMarketCap_Then4Percent() public {
        bool isIrl0 = (address(irl) < address(weth));
        vm.startPrank(deployer);
        hook.setDisableAntiWhaleFromInitialPrice(Constants.SQRT_PRICE_1_1, isIrl0);
        hook.launch();
        vm.stopPrank();

        assertTrue(hook.launchTaxEnabled(), "10% Launch Boost Tax must be active initially");
        assertTrue(hook.isLaunchTaxActive(), "isLaunchTaxActive must be true initially");
        assertGt(hook.disableLaunchTaxSqrtPrice(), 0, "100k MC threshold must be configured");

        vm.warp(hook.launchTimestamp() + 120);

        uint256 hourId = block.timestamp / 1 hours;
        bool zeroForOne = Currency.unwrap(poolKey.currency0) == address(weth);
        uint256 progBefore = progRecipient.balance;

        vm.startPrank(traderB);
        deal(Currency.unwrap(currency0), traderB, 20 ether);
        deal(Currency.unwrap(currency1), traderB, 20 ether);

        swapRouter.swapExactTokensForTokens({
            amountIn: 1.0 ether,
            amountOutMin: 0,
            zeroForOne: zeroForOne,
            poolKey: poolKey,
            hookData: abi.encode(traderB),
            receiver: traderB,
            deadline: type(uint256).max
        });
        vm.stopPrank();

        // Verify 10.00% Launch Boost Tax split on 1.0 WETH swap:
        // - 0.30% Programmable.market (0.003 ETH)
        // - 3.75% Hourly Pot (0.0375 ETH)
        // - 3.75% Lottery Pots (1.875% Daily = 0.01875 ETH + 1.875% Weekly = 0.01875 ETH)
        // - 2.20% Protocol & Buyback Pot (1.98% Protocol = 0.0198 ETH + 0.22% Buyback Burn = 0.0022 ETH)
        assertEq(progRecipient.balance - progBefore, 0.003 ether, "0.30% Programmable during Launch Boost");
        assertEq(
            hook.hourlyPotByHour(hourId) + hook.userCashbackPerHour(hourId, traderB) + address(staking).balance,
            0.0375 ether,
            "3.75% Hourly Pot during Launch Boost"
        );
        assertEq(hook.dailyLotteryPot(), 0.01875 ether, "1.875% Daily Lottery during Launch Boost");
        assertEq(hook.sundayMegaPot(), 0.01875 ether, "1.875% Sunday Lottery during Launch Boost");
        assertEq(hook.protocolPot(), 0.0198 ether, "1.98% Protocol Pot during Launch Boost");
        assertEq(hook.buybackPot(), 0.0022 ether, "0.22% Buyback Burn Pot during Launch Boost");

        // Simulate reaching 100k Market Cap cutoff
        (uint160 currentSqrtPrice,,,) = poolManager.getSlot0(poolId);
        vm.startPrank(deployer);
        hook.setDisableLaunchTaxPrice(currentSqrtPrice);
        vm.stopPrank();

        // Execute a small swap that crosses/triggers the 100k MC cutoff
        vm.startPrank(traderA);
        deal(Currency.unwrap(currency0), traderA, 10 ether);
        deal(Currency.unwrap(currency1), traderA, 10 ether);
        swapRouter.swapExactTokensForTokens({
            amountIn: 0.05 ether,
            amountOutMin: 0,
            zeroForOne: zeroForOne,
            poolKey: poolKey,
            hookData: abi.encode(traderA),
            receiver: traderA,
            deadline: type(uint256).max
        });
        vm.stopPrank();

        // Launch Boost Tax is now permanently disabled on-chain
        assertFalse(hook.launchTaxEnabled(), "10% Launch Tax must auto-disable at 100k MC");
        assertFalse(hook.isLaunchTaxActive(), "isLaunchTaxActive must be false after 100k MC");

        // Subsequent 1.0 WETH swap must pay the standard 4.00% tax (1.25% / 1.25% / 1.20% / 0.30%)
        uint256 dailyBefore = hook.dailyLotteryPot();
        uint256 protocolBefore = hook.protocolPot();
        uint256 burnPotBefore = hook.buybackPot();
        uint256 progBefore2 = progRecipient.balance;

        vm.startPrank(traderB);
        swapRouter.swapExactTokensForTokens({
            amountIn: 1.0 ether,
            amountOutMin: 0,
            zeroForOne: zeroForOne,
            poolKey: poolKey,
            hookData: abi.encode(traderB),
            receiver: traderB,
            deadline: type(uint256).max
        });
        vm.stopPrank();

        assertEq(progRecipient.balance - progBefore2, 0.003 ether, "0.30% Programmable after 100k MC");
        assertEq(hook.dailyLotteryPot() - dailyBefore, 0.00625 ether, "0.625% Daily Lottery after 100k MC");
        assertEq(hook.protocolPot() - protocolBefore, 0.0108 ether, "1.08% Protocol Pot after 100k MC");
        assertEq(hook.buybackPot() - burnPotBefore, 0.0012 ether, "0.12% Buyback Burn Pot after 100k MC");
    }

    function test_LiquidityCustody_90PercentPermanentLock_10PercentMarketing_AndInitialBuy() public {
        // Deploy a fresh token + pool at 20k MC price to test atomic LP seeding + 0.15 ETH initial buy
        vm.startPrank(deployer, deployer);
        InternetRobinLottery irlFresh = new InternetRobinLottery(deployer, 1_000_000_000 ether);
        IRLMarketingVault vaultFresh = new IRLMarketingVault(address(poolManager), address(positionManager), address(irlFresh));

        Currency c0;
        Currency c1;
        uint160 startPrice;
        if (address(irlFresh) < address(weth)) {
            c0 = Currency.wrap(address(irlFresh));
            c1 = Currency.wrap(address(weth));
            startPrice = 7158327914619714881093632;
        } else {
            c0 = Currency.wrap(address(weth));
            c1 = Currency.wrap(address(irlFresh));
            startPrice = 876895058097984813589920800000000;
        }

        PoolKey memory freshKey = PoolKey(c0, c1, 3000, 60, IHooks(hook));
        poolManager.initialize(freshKey, startPrice);

        // Fund vault with 100% of token supply (1,000,000,000 IRL)
        irlFresh.transfer(address(vaultFresh), 1_000_000_000 ether);

        // Seed 90% permanent locked LP + 10% conditional marketing LP
        vaultFresh.seedInitialLiquidity(freshKey);

        assertTrue(vaultFresh.liquiditySeeded(), "Initial liquidity must be marked seeded");
        assertGt(vaultFresh.permanentLiquidity(), 0, "90% permanent locked liquidity must be non-zero");
        assertGt(vaultFresh.marketingLiquidity(), 0, "10% conditional marketing liquidity must be non-zero");
        assertApproxEqAbs(irlFresh.balanceOf(address(poolManager)), 1_000_000_000 ether, 1e15, "PoolManager holds ~100% of initial IRL liquidity");

        // Attempt to withdraw marketing liquidity before price crosses bracket must revert
        uint128 mLiq = vaultFresh.marketingLiquidity();
        vm.expectRevert(
            address(irlFresh) < address(weth)
                ? bytes("Market bracket not reached: IRL not yet converted to WETH (tick < tickUpper)")
                : bytes("Market bracket not reached: IRL not yet converted to WETH (tick > tickLower)")
        );
        vaultFresh.decreaseMarketingLiquidity(mLiq, deployer);

        // Execute atomic initial buy of 0.15 ETH in the same block
        uint256 deployerIrlBefore = irlFresh.balanceOf(deployer);
        uint256 progBefore = progRecipient.balance;

        uint256 irlBought = vaultFresh.executeInitialBuy{value: 0.15 ether}(freshKey, address(weth), 1, deployer);
        vm.stopPrank();

        assertGt(irlBought, 10_000_000 ether, "0.15 ETH initial buy should receive ~16.25M IRL");
        assertEq(irlFresh.balanceOf(deployer) - deployerIrlBefore, irlBought, "Deployer received initial buy IRL");
        assertEq(progRecipient.balance - progBefore, 0.00045 ether, "Programmable received 0.30% of 0.15 ETH initial buy");
    }

    function test_UnclaimedRewards_ClaimableByRecipient_NotMovedToProtocol() public {
        ToggleableEthRecipient revertingUser = new ToggleableEthRecipient();
        vm.deal(address(revertingUser), 10 ether);

        vm.startPrank(deployer);
        hook.launch();
        vm.stopPrank();

        vm.warp(hook.launchTimestamp() + 100);
        uint256 hourId = block.timestamp / 1 hours;

        // revertingUser performs a swap in hourId
        bool zeroForOne = Currency.unwrap(poolKey.currency0) == address(weth);
        vm.startPrank(address(revertingUser));
        deal(Currency.unwrap(currency0), address(revertingUser), 10 ether);
        deal(Currency.unwrap(currency1), address(revertingUser), 10 ether);
        weth.approve(address(permit2), type(uint256).max);
        weth.approve(address(swapRouter), type(uint256).max);
        permit2.approve(address(weth), address(swapRouter), type(uint160).max, type(uint48).max);

        swapRouter.swapExactTokensForTokens({
            amountIn: 1.0 ether,
            amountOutMin: 0,
            zeroForOne: zeroForOne,
            poolKey: poolKey,
            hookData: abi.encode(address(revertingUser)),
            receiver: address(revertingUser),
            deadline: type(uint256).max
        });
        vm.stopPrank();

        uint256 expectedUserReward = hook.hourlyPotByHour(hourId) + hook.userCashbackPerHour(hourId, address(revertingUser));
        assertGt(expectedUserReward, 0, "User must have accrued hourly leaderboard + cashback rewards");

        // Advance to next hour and trigger hourly distribution while revertingUser rejects ETH
        vm.warp((hourId + 1) * 1 hours + 10);
        uint256 protocolBefore = hook.protocolPot();

        hook.performUpkeep(abi.encode(uint8(1), 0));
        hook.performUpkeep(abi.encode(uint8(2), 0));

        // 1. Protocol pot did NOT absorb the failed user payout
        assertEq(hook.protocolPot(), protocolBefore, "Failed user payout must NEVER be moved into protocolPot");

        // 2. Unclaimed reward is credited to revertingUser
        assertEq(hook.unclaimedRewards(address(revertingUser)), expectedUserReward, "Failed payout must be stored in unclaimedRewards");

        // 3. Once revertingUser enables ETH reception, it can claim its exact reward
        revertingUser.setAcceptEth(true);
        uint256 balBefore = address(revertingUser).balance;
        revertingUser.claimFromHook(hook);

        assertEq(address(revertingUser).balance - balBefore, expectedUserReward, "Rightful recipient claimed full unpaid reward");
        assertEq(hook.unclaimedRewards(address(revertingUser)), 0, "unclaimedRewards cleared after claim");
    }

    function test_DelayedDraws_EpochIsolatedLotteryPots() public {
        vm.startPrank(deployer);
        hook.launch();
        vm.stopPrank();

        // Day D0: traderA swaps 1.0 WETH (generates tickets in Day D0 and funds dailyPotByDay[D0])
        uint256 day0 = block.timestamp / 1 days;
        bool zeroForOne = Currency.unwrap(poolKey.currency0) == address(weth);

        vm.startPrank(traderA);
        deal(Currency.unwrap(currency0), traderA, 20 ether);
        deal(Currency.unwrap(currency1), traderA, 20 ether);
        swapRouter.swapExactTokensForTokens({
            amountIn: 1.0 ether,
            amountOutMin: 0,
            zeroForOne: zeroForOne,
            poolKey: poolKey,
            hookData: abi.encode(traderA),
            receiver: traderA,
            deadline: type(uint256).max
        });
        vm.stopPrank();

        uint256 potDay0 = hook.dailyPotByDay(day0);
        assertEq(potDay0, 0.01875 ether, "Day 0 pot must equal 1.875% of Day 0 swap");

        // Warp to Day D1 (delayed keeper execution): traderB swaps 2.0 WETH in Day D1 BEFORE Day D0 draw happens
        // Note: 24h Launch Boost window has now expired, so Day D1 swap pays the 4.00% Standard Tax (0.625% Daily = 0.0125 ETH)
        vm.warp((day0 + 1) * 1 days + 100);
        uint256 day1 = day0 + 1;

        vm.startPrank(traderB);
        deal(Currency.unwrap(currency0), traderB, 20 ether);
        deal(Currency.unwrap(currency1), traderB, 20 ether);
        swapRouter.swapExactTokensForTokens({
            amountIn: 2.0 ether,
            amountOutMin: 0,
            zeroForOne: zeroForOne,
            poolKey: poolKey,
            hookData: abi.encode(traderB),
            receiver: traderB,
            deadline: type(uint256).max
        });
        vm.stopPrank();

        uint256 potDay1 = hook.dailyPotByDay(day1);
        assertEq(potDay1, 0.0125 ether, "Day 1 pot must be isolated in dailyPotByDay[day1]");
        assertEq(hook.dailyPotByDay(day0), potDay0, "Day 0 pot must remain strictly potDay0 without mixing Day 1 funds");

        // Keeper executes delayed Daily Lottery for Day 0
        uint256 traderABalBefore = traderA.balance;
        hook.performUpkeep(abi.encode(uint8(3), day1));
        // Fulfill OpenVRF request #1
        vm.prank(address(openVrf));
        hook.rawFulfillRandomness(1, 777);

        // TraderA (only ticket holder in Day 0) wins strictly potDay0, while potDay1 remains untouched!
        assertEq(traderA.balance - traderABalBefore, potDay0, "Day 0 winner receives strictly Day 0 pot");
        assertEq(hook.dailyPotByDay(day0), 0, "Day 0 pot is now 0");
        assertEq(hook.dailyPotByDay(day1), potDay1, "Day 1 pot is completely preserved for Day 1 draw");
    }

    function test_AntiWhale_AutoDisableAt50kMarketCap() public {
        bool isIrl0 = (address(irl) < address(weth));
        vm.startPrank(deployer);
        hook.setDisableAntiWhaleFromInitialPrice(Constants.SQRT_PRICE_1_1, isIrl0);
        vm.stopPrank();

        assertTrue(hook.limitsEnabled(), "Limits must be active before reaching 50k MC");
        uint160 target50k = hook.disableAntiWhaleSqrtPrice();
        assertGt(target50k, 0, "50k MC threshold must be configured");

        vm.startPrank(deployer);
        hook.setDisableAntiWhalePrice(Constants.SQRT_PRICE_1_1);
        vm.stopPrank();

        vm.warp(hook.launchTimestamp() + 120);
        vm.startPrank(traderA);
        deal(Currency.unwrap(currency0), traderA, 10 ether);
        deal(Currency.unwrap(currency1), traderA, 10 ether);

        bool zeroForOne = Currency.unwrap(poolKey.currency0) == address(weth);
        swapRouter.swapExactTokensForTokens({
            amountIn: 0.1 ether,
            amountOutMin: 0,
            zeroForOne: zeroForOne,
            poolKey: poolKey,
            hookData: abi.encode(traderA),
            receiver: traderA,
            deadline: type(uint256).max
        });
        vm.stopPrank();

        assertFalse(hook.limitsEnabled(), "Limits must be automatically disabled once 50k MC price is reached");
    }

    function test_NFTTicket_OnChainHoldingCapEnforced() public {
        IRLTicketNFT cappedNft = new IRLTicketNFT(deployer);
        vm.startPrank(deployer);
        for (uint256 i = 0; i < 42; i++) {
            cappedNft.mintTicket(traderB);
        }
        uint256 extraTicketId = cappedNft.mintTicket(traderA);
        cappedNft.transferOwnership(address(hook));
        vm.stopPrank();

        assertEq(cappedNft.balanceOf(traderB), 42);

        vm.startPrank(traderA);
        vm.expectRevert("IRLTicketNFT: Weekly ticket holding cap exceeded");
        cappedNft.transferFrom(traderA, traderB, extraTicketId);
        vm.stopPrank();
    }
}
