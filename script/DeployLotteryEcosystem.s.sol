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

    // Constants for 20k Market Cap (Assuming 1 ETH = $3000 -> 20k$ = 6.666 ETH)
    // Supply = 1,000,000,000 IRL
    // If IRL is token0 and WETH is token1: 1 IRL = 6.666e-9 WETH
    uint160 constant SQRT_PRICE_IRL_TOKEN0 = 6468798150493635593361817; 
    
    // If WETH is token0 and IRL is token1: 1 WETH = 150,000,000 IRL
    uint160 constant SQRT_PRICE_IRL_TOKEN1 = 970314407886407000000000000000000;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        // Mock WETH for Testnet
        address weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; // Adjust this if needed
        address poolManager = 0x8C4BcBE6b9eF47855f2d37c07bE0d59A518B24e0; // Adjust for V4 Pool Manager
        
        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy Core Contracts
        console2.log("Deploying InternetRobinLottery...");
        InternetRobinLottery irl = new InternetRobinLottery(deployer, 1_000_000_000 ether);
        
        console2.log("Deploying IRLTicketNFT...");
        IRLTicketNFT nft = new IRLTicketNFT();
        
        console2.log("Deploying IRLStaking...");
        IRLStaking staking = new IRLStaking(address(irl));

        // 2. Mine Hook Address
        uint160 flags = uint160(Hooks.AFTER_SWAP_FLAG);
        address vrfCoordinator = 0x8103B0A8A00be2DDC778e6e7eaa21791Cd364625; // Dummy VRF
        uint64 subId = 1;
        bytes32 keyHash = 0x474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c;
        
        bytes memory constructorArgs = abi.encode(
            IPoolManager(poolManager), 
            address(nft), 
            address(staking), 
            vrfCoordinator, 
            subId, 
            keyHash
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
            vrfCoordinator, 
            subId, 
            keyHash
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
