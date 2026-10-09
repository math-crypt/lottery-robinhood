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

contract DeployLotteryEcosystem is Script {
    using CurrencyLibrary for Currency;

    // Constants for 20k Market Cap (Current ETH Price ~ $2450 -> 20k$ = 8.163 ETH)
    // Supply = 1,000,000,000 IRL
    // If IRL is token0 and WETH is token1: 1 IRL = 8.163e-9 WETH
    uint160 constant SQRT_PRICE_IRL_TOKEN0 = 7158327914619714881093632; 
    
    // If WETH is token0 and IRL is token1: 1 WETH = 122,500,000 IRL
    uint160 constant SQRT_PRICE_IRL_TOKEN1 = 876895058097984813589920800000000;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        // Robinhood Chain Addresses (Chain ID 4663)
        address weth = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73; 
        address poolManager = 0x8366a39cc670b4001a1121b8f6a443a643e40951; 
        
        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy Core Contracts
        console2.log("Deploying InternetRobinLottery...");
        InternetRobinLottery irl = new InternetRobinLottery(deployer, 1_000_000_000 ether);
        
        console2.log("Deploying IRLTicketNFT...");
        IRLTicketNFT nft = new IRLTicketNFT();
        
        console2.log("Deploying IRLStaking...");
        IRLStaking staking = new IRLStaking(address(irl));

        // 2. Mine Hook Address
        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG | 
            Hooks.AFTER_SWAP_FLAG | 
            Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG | 
            Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        );
        // OpenVRF Router on Robinhood Chain
        address openVrfRouter = vm.envAddress("ROBINHOOD_OPENVRF_ROUTER"); 
        
        bytes memory constructorArgs = abi.encode(
            IPoolManager(poolManager), 
            address(nft), 
            address(staking), 
            openVrfRouter, 
            weth
        );

        // CREATE2 Factory (standard forge testnet factory)
        address CREATE2_FACTORY = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
        
        console2.log("Mining Hook Address...");
        (address hookAddress, bytes32 salt) = HookMiner.find(
            CREATE2_FACTORY, 
            flags, 
            type(IRLUniswapV4Hook).creationCode, 
            constructorArgs
        );

        console2.log("Deploying IRLUniswapV4Hook...");
        IRLUniswapV4Hook hook = new IRLUniswapV4Hook{salt: salt}(
            IPoolManager(poolManager), 
            address(nft), 
            address(staking), 
            openVrfRouter, 
            weth
        );
        require(address(hook) == hookAddress, "Hook Address mismatch");

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
        IPoolManager(poolManager).initializePool(poolKey, startingPrice, new bytes(0));

        // Note: For initial liquidity provision, a PositionManager call would follow here.
        // The script sets the exact price which acts as the 20k MC valuation for the token!

        vm.stopBroadcast();
        
        console2.log("--- Deployment Successful ---");
        console2.log("IRL Token:", address(irl));
        console2.log("IRL NFT:", address(nft));
        console2.log("IRL Staking:", address(staking));
        console2.log("IRL Hook:", address(hook));
    }
}
