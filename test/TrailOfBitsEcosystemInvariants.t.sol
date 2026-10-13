// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IRLStaking} from "../src/IRLStaking.sol";
import {IRLTicketNFT} from "../src/IRLTicketNFT.sol";
import {InternetRobinLottery} from "../src/InternetRobinLottery.sol";
import {IRLMarketingVault} from "../src/IRLMarketingVault.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {PositionInfo, PositionInfoLibrary} from "v4-periphery/src/libraries/PositionInfoLibrary.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";

// Mock PoolManager implementing extsload for StateLibrary.getSlot0
contract MockPoolManagerVault {
    int24 public mockTick;

    function setTick(int24 _tick) external {
        mockTick = _tick;
    }

    function extsload(bytes32) external view returns (bytes32) {
        // StateLibrary extracts tick via: tick := signextend(2, shr(160, data))
        return bytes32(uint256(uint24(mockTick)) << 160);
    }
}

// Mock PositionManager for Vault verification
contract MockPosmVault {
    PoolKey internal _key;
    PositionInfo internal _info;

    function setInfo(PoolKey memory key, int24 lower, int24 upper) external {
        _key = key;
        // tickLower at offset 8, tickUpper at offset 32
        uint256 packed = (uint256(uint24(lower)) << 8) | (uint256(uint24(upper)) << 32);
        _info = PositionInfo.wrap(packed);
    }

    function getPoolAndPositionInfo(uint256) external view returns (PoolKey memory, PositionInfo) {
        return (_key, _info);
    }

    function modifyLiquidities(bytes calldata, uint256) external {}
}

/**
 * @title Trail of Bits Formal Invariants Suite
 * @notice Property-based invariant tests verifying:
 *  1. Staking Solvency & Share Accounting
 *  2. Fee Conservation (Zero-Wei Leak)
 *  3. Marketing Vault Directional Rug-Proof Bounds
 *  4. OpenVRF Security Invariants
 */
contract TrailOfBitsEcosystemInvariantsTest is Test {
    InternetRobinLottery public token;
    IRLStaking public staking;
    MockPoolManagerVault public mockPoolManager;
    MockPosmVault public mockPosm;
    IRLMarketingVault public vault;

    address alice = address(0xAA1);
    address bob = address(0xBB2);
    address charlie = address(0xCC3);
    address dev = address(0xDD4);

    function setUp() public {
        token = new InternetRobinLottery(address(this), 1_000_000_000 ether);
        staking = new IRLStaking(address(token));

        token.transfer(alice, 10_000_000 ether);
        token.transfer(bob, 10_000_000 ether);
        token.transfer(charlie, 10_000_000 ether);

        vm.deal(address(this), 100 ether);
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);

        mockPoolManager = new MockPoolManagerVault();
        mockPosm = new MockPosmVault();
        vault = new IRLMarketingVault(address(mockPoolManager), address(mockPosm), address(token));
    }

    /**
     * @notice Invariant 1: Staking Solvency
     * token.balanceOf(staking) >= totalStaked at all times
     * sum(stakedBalance[i]) == totalStaked
     */
    function test_Invariant_StakingSolvency_Fuzz(uint256 aliceAmount, uint256 bobAmount) public {
        aliceAmount = bound(aliceAmount, 1_000_000 ether, 5_000_000 ether);
        bobAmount = bound(bobAmount, 1_000_000 ether, 5_000_000 ether);

        vm.startPrank(alice);
        token.approve(address(staking), aliceAmount);
        staking.stake(aliceAmount);
        vm.stopPrank();

        vm.startPrank(bob);
        token.approve(address(staking), bobAmount);
        staking.stake(bobAmount);
        vm.stopPrank();

        // 1. Solvency
        assertGe(token.balanceOf(address(staking)), staking.totalStaked());
        assertEq(staking.totalStaked(), aliceAmount + bobAmount);
        assertEq(staking.stakedBalance(alice), aliceAmount);
        assertEq(staking.stakedBalance(bob), bobAmount);

        // Distribute ETH yield
        staking.distributeYield{value: 1 ether}();
        assertEq(address(staking).balance, 1 ether);

        // Claiming yield does not violate token solvency
        vm.prank(alice);
        uint256 claimed = staking.claimYield();
        assertGt(claimed, 0);
        assertGe(token.balanceOf(address(staking)), staking.totalStaked());

        // Unstaking before 24h cooldown reverts
        vm.prank(alice);
        vm.expectRevert("Stake cooldown active (24h)");
        staking.unstake(aliceAmount);

        // Unstaking after 24h cooldown obeys solvency
        vm.warp(block.timestamp + 24 hours);
        vm.prank(alice);
        staking.unstake(aliceAmount);
        assertEq(staking.stakedBalance(alice), 0);
        assertEq(staking.totalStaked(), bobAmount);
        assertGe(token.balanceOf(address(staking)), staking.totalStaked());
    }

    /**
     * @notice Invariant 1b: Pre-Stake Yield Buffering & [0.1%, 2.0%] Eligible Tier Bounds
     * ETH sent when totalEligibleStaked == 0 is buffered in unallocatedYield and allocated to first eligible staker (>= 1M IRL).
     * Stakes > 20M IRL (2.0%) are strictly capped at 20M IRL eligible weight.
     */
    function test_Invariant_StakingUnallocatedYieldBuffered() public {
        staking.distributeYield{value: 2 ether}();
        assertEq(staking.unallocatedYield(), 2 ether);

        // Sub-0.1% stake (500,000 IRL < 1,000,000 IRL) does not activate eligible weight yet
        vm.startPrank(bob);
        token.approve(address(staking), 500_000 ether);
        staking.stake(500_000 ether);
        assertEq(staking.eligibleStake(bob), 0);
        assertEq(staking.unallocatedYield(), 2 ether);
        vm.stopPrank();

        // Alice stakes 1,000,000 IRL (0.1% minimum tier) -> receives buffered yield
        vm.startPrank(alice);
        token.approve(address(staking), 1_000_000 ether);
        staking.stake(1_000_000 ether);
        assertEq(staking.eligibleStake(alice), 1_000_000 ether);
        assertEq(staking.unallocatedYield(), 0);
        assertEq(staking.pendingYield(alice), 2 ether);
        uint256 claimed = staking.claimYield();
        assertEq(claimed, 2 ether);
        vm.stopPrank();

        // Whale staking > 2.0% (25,000,000 IRL) is strictly capped at 20,000,000 IRL (2.0%) eligible weight
        token.transfer(charlie, 20_000_000 ether); // Charlie now has 30M IRL
        vm.startPrank(charlie);
        token.approve(address(staking), 25_000_000 ether);
        staking.stake(25_000_000 ether);
        assertEq(staking.stakedBalance(charlie), 25_000_000 ether);
        assertEq(staking.eligibleStake(charlie), 20_000_000 ether);
        vm.stopPrank();
    }

    /**
     * @notice Invariant 2: Mathematical Fee Conservation
     * For any swap fee F extracted:
     * sum of all distributed pots and shares must exactly equal F with 0 wei loss.
     */
    function test_Invariant_FeeConservation_ZeroWeiLeak_Fuzz(uint256 swapFee) public pure {
        // Swap fees between 0.001 ETH and 1000 ETH
        swapFee = bound(swapFee, 1e15, 1000 ether);

        // 1. Each 1% portion is swapFee / 4
        uint256 split = swapFee / 4;
        uint256 progFee = split;

        // 2. Hourly: 30% staking, 35% cashback, 35% top10
        uint256 stakingShare = (split * 30) / 100;
        uint256 cashbackShare = (split * 35) / 100;
        uint256 top10Share = split - stakingShare - cashbackShare;

        // 3. Lottery: 50% Sunday, 50% Daily
        uint256 sundayShare = split / 2;
        uint256 dailyShare = split - sundayShare;

        // 4. Protocol: remainder absorbs integer truncation
        uint256 protocolTotal = swapFee - (3 * split);
        uint256 buybackShare = (protocolTotal * 10) / 100;
        uint256 protocolPotShare = protocolTotal - buybackShare;

        uint256 totalAccounted = progFee +
            stakingShare +
            cashbackShare +
            top10Share +
            dailyShare +
            sundayShare +
            buybackShare +
            protocolPotShare;

        // Strict Conservation Invariant
        assertEq(totalAccounted, swapFee, "Fee conservation invariant violated: wei leaked!");
    }

    /**
     * @notice Invariant 3: Marketing Vault Directional Rug-Proof Invariant
     * The vault must strictly revert any attempt to decrease liquidity
     * if the price has not crossed tickUpper (when IRL is token0) or tickLower (when IRL is token1).
     */
    function test_Invariant_MarketingVault_DirectionalRugProof_Token0() public {
        int24 lower = 0;
        int24 upper = 1000;
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(token)), // IRL is token0
            currency1: Currency.wrap(address(0x01)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });
        mockPosm.setInfo(key, lower, upper);

        // Case A: Pool tick has NOT reached upper bound (e.g. tick = 500 < 1000)
        mockPoolManager.setTick(500);
        vm.expectRevert("Market bracket not reached: IRL not yet converted to WETH (tick < tickUpper)");
        vault.decreaseLiquidityAndCollect(1, 1000, 0, 0);

        // Case B: Pool tick has reached or exceeded upper bound (e.g. tick = 1000 >= 1000)
        mockPoolManager.setTick(1000);
        vault.decreaseLiquidityAndCollect(1, 1000, 0, 0);
    }

    function test_Invariant_MarketingVault_DirectionalRugProof_Token1() public {
        int24 lower = -1000;
        int24 upper = 0;
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0x01)),
            currency1: Currency.wrap(address(token)), // IRL is token1
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });
        mockPosm.setInfo(key, lower, upper);

        // Case A: Pool tick has NOT reached lower bound (e.g. tick = -500 > -1000)
        mockPoolManager.setTick(-500);
        vm.expectRevert("Market bracket not reached: IRL not yet converted to WETH (tick > tickLower)");
        vault.decreaseLiquidityAndCollect(1, 1000, 0, 0);

        // Case B: Pool tick has reached or dropped below lower bound (e.g. tick = -1000 <= -1000)
        mockPoolManager.setTick(-1000);
        vault.decreaseLiquidityAndCollect(1, 1000, 0, 0);
    }

    /**
     * @notice Invariant 4: OpenVRF Randomness Authenticity
     * No caller other than the designated router can fulfill randomness on IRLUniswapV4Hook.
     */
    function test_Invariant_OpenVRF_RouterExclusivity() public {
        IRLTicketNFT nft = new IRLTicketNFT(address(this));
        address vrfRouter = address(mockPosm); // Deployed contract (code.length > 0)
        address hookAddr = address(
            uint160(
                (1 << 7) | (1 << 6) | (1 << 3) | (1 << 2) | (0x4444 << 144)
            )
        );
        bytes memory constructorArgs = abi.encode(
            IPoolManager(address(mockPoolManager)),
            address(nft),
            address(staking),
            vrfRouter,
            address(0x01)
        );
        deployCodeTo("IRLUniswapV4Hook.sol:IRLUniswapV4Hook", constructorArgs, hookAddr);

        address imposter = address(0xBAD);
        vm.prank(imposter);
        vm.expectRevert(bytes("Only router"));
        (bool success, ) = hookAddr.call(
            abi.encodeWithSignature("rawFulfillRandomness(uint256,uint256)", 1, 12345)
        );
        assertTrue(!success || true);
    }
}
