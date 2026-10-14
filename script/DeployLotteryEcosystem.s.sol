// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

import {InternetRobinLottery} from "../src/InternetRobinLottery.sol";
import {IRLTicketNFT} from "../src/IRLTicketNFT.sol";
import {IRLStaking} from "../src/IRLStaking.sol";
import {IRLUniswapV4Hook} from "../src/IRLUniswapV4Hook.sol";
import {IRLMarketingVault} from "../src/IRLMarketingVault.sol";
import {OpenVRF} from "openvrf/OpenVRF.sol";

contract DeployLotteryEcosystem is Script {
    using CurrencyLibrary for Currency;

    // Constants for 20k Market Cap (Current ETH Price ~ $2450 -> 20k$ = 8.163 ETH)
    // Supply = 1,000,000,000 IRL
    // If IRL is token0 and WETH is token1: 1 IRL = 8.163e-9 WETH
    uint160 constant SQRT_PRICE_IRL_TOKEN0 = 7158327914619714881093632; 
    
    // If WETH is token0 and IRL is token1: 1 WETH = 122,500,000 IRL
    uint160 constant SQRT_PRICE_IRL_TOKEN1 = 876895058097984813589920800000000;

    // Contract State to eliminate stack pressure
    address public weth = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;
    address public poolManager = 0x8366a39CC670B4001A1121B8F6A443A643e40951;
    address public openVrfRouter;
    OpenVRF public openVrfContract;

    InternetRobinLottery public irl;
    IRLTicketNFT public nft;
    IRLStaking public staking;
    IRLMarketingVault public vault;
    IRLUniswapV4Hook public hook;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        vm.startBroadcast(deployerPrivateKey);

        // 0. Deploy or Resolve Native OpenVRF Router on Robinhood Chain
        address configuredVrf = vm.envOr("OPENVRF_ROUTER", address(0));
        if (configuredVrf != address(0)) {
            console2.log("Using pre-configured OpenVRF Router:", configuredVrf);
            openVrfRouter = configuredVrf;
            openVrfContract = OpenVRF(configuredVrf);
        } else {
            console2.log("Deploying dedicated Native OpenVRF Router on Robinhood Chain...");
            address relayer = vm.envOr("RELAYER_ADDRESS", deployer);
            uint256 requestFee = vm.envOr("OPENVRF_REQUEST_FEE", uint256(0));
            openVrfContract = new OpenVRF(deployer, relayer, requestFee);
            openVrfRouter = address(openVrfContract);
            console2.log("Native OpenVRF Router deployed at:", openVrfRouter);
        }

        // 1. Deploy Core Contracts
        console2.log("Deploying InternetRobinLottery...");
        irl = new InternetRobinLottery(deployer, 1_000_000_000 ether);
        
        console2.log("Deploying IRLTicketNFT...");
        nft = new IRLTicketNFT(deployer);
        
        console2.log("Deploying IRLStaking...");
        staking = new IRLStaking(address(irl));

        console2.log("Deploying IRLMarketingVault...");
        address positionManager = vm.envOr("POSITION_MANAGER", address(0x4529A01c7A0410167c5740C487A8DE60232617bf));
        require(positionManager != address(0) && positionManager != poolManager, "Invalid PositionManager address");
        vault = new IRLMarketingVault(poolManager, positionManager, address(irl));

        // 2. Mine Hook Address
        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG | 
            Hooks.AFTER_SWAP_FLAG | 
            Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG | 
            Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        );
        
        bytes memory constructorArgs = abi.encode(
            IPoolManager(poolManager), 
            address(nft), 
            address(staking), 
            openVrfRouter, 
            weth
        );

        address CREATE2_FACTORY = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
        
        console2.log("Mining Hook Address...");
        (address hookAddress, bytes32 salt) = HookMiner.find(
            CREATE2_FACTORY, 
            flags, 
            type(IRLUniswapV4Hook).creationCode, 
            constructorArgs
        );

        console2.log("Deploying IRLUniswapV4Hook...");
        hook = new IRLUniswapV4Hook{salt: salt}(
            IPoolManager(poolManager), 
            address(nft), 
            address(staking), 
            openVrfRouter, 
            weth
        );
        require(address(hook) == hookAddress, "Hook Address mismatch");
        
        // Transfer NFT ownership to hook so it can mint and enforce weekly holding caps
        nft.transferOwnership(address(hook));
        // Note: IRLUniswapV4Hook constructor automatically registers itself in IRLStaking

        console2.log("Immutable Programmable Fee Recipient (0.30%):", hook.PROGRAMMABLE_FEE_RECIPIENT());

        // Authorize Hook as OpenVRF consumer
        try openVrfContract.setConsumerAuthorization(hookAddress, true) {
            console2.log("Hook authorized as OpenVRF consumer");
        } catch {
            console2.log("Note: setConsumerAuthorization skipped or requires separate owner execution");
        }

        // 3. Initialize Pool with 20k MC Price
        Currency currency0;
        Currency currency1;
        uint160 startingPrice;

        if (address(irl) < weth) {
            currency0 = Currency.wrap(address(irl));
            currency1 = Currency.wrap(weth);
            startingPrice = SQRT_PRICE_IRL_TOKEN0;
        } else {
            currency0 = Currency.wrap(weth);
            currency1 = Currency.wrap(address(irl));
            startingPrice = SQRT_PRICE_IRL_TOKEN1;
        }

        PoolKey memory poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 3000,
            tickSpacing: 60,
            hooks: hook
        });

        console2.log("Initializing Pool Manager with Market Cap ~20k$...");
        IPoolManager(poolManager).initialize(poolKey, startingPrice);

        // 4. Configure 50k Market Cap Anti-Whale & 100k Market Cap Launch Boost Tax (10% -> 4%, or 24h expiry) Cutoffs
        bool isIrl0 = (address(irl) < weth);
        hook.setDisableAntiWhaleFromInitialPrice(startingPrice, isIrl0);
        console2.log("Configured 50k Market Cap Anti-Whale cutoff:", hook.disableAntiWhaleSqrtPrice());
        console2.log("Configured 100k Market Cap 10% Launch Tax cutoff:", hook.disableLaunchTaxSqrtPrice());

        // 5. Fund Liquidity Vault (90% Permanent Locked + 10% Conditional Marketing) & Seed Initial Liquidity
        bool seedLiquidity = vm.envOr("SEED_INITIAL_LIQUIDITY", true);
        if (seedLiquidity) {
            console2.log("Funding IRLMarketingVault with 1,000,000,000 IRL and seeding 90%/10% liquidity...");
            irl.transfer(address(vault), 1_000_000_000 ether);
            vault.seedInitialLiquidity(poolKey);

            uint256 initialBuyEth = vm.envOr("INITIAL_BUY_ETH", uint256(0.15 ether));
            if (initialBuyEth > 0 && deployer.balance >= initialBuyEth) {
                console2.log("Executing atomic initial buy of ETH:", initialBuyEth);
                vault.executeInitialBuy{value: initialBuyEth}(poolKey, weth, 1, deployer);
            }
        }

        vm.stopBroadcast();
        
        console2.log("--- Deployment Successful ---");
        console2.log("Explorer Base URL: https://robin.etherscan.io");
        console2.log("Native OpenVRF Router:", openVrfRouter);
        console2.log("IRL Token:", address(irl));
        console2.log("IRL NFT:", address(nft));
        console2.log("IRL Staking:", address(staking));
        console2.log("IRL Hook:", address(hook));
        console2.log("IRL Marketing Vault:", address(vault));
    }
}
