const fs = require('fs');

let code = fs.readFileSync('src/IRLUniswapV4Hook.sol', 'utf8');

// 1. Add StateLibrary Import
code = code.replace(
    'import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";',
    'import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";\nimport {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";'
);

// 2. Add using StateLibrary
code = code.replace(
    'using CurrencyLibrary for Currency;',
    'using CurrencyLibrary for Currency;\n    using StateLibrary for IPoolManager;'
);

// 3. Add targetPrice state variable
code = code.replace(
    'bool public limitsEnabled = true;',
    'bool public limitsEnabled = true;\n    uint160 public disableAntiWhaleSqrtPrice;'
);

// 4. Add admin setter for target price
const setter = `    function setDisableAntiWhalePrice(uint160 _price) external onlyOwner {
        disableAntiWhaleSqrtPrice = _price;
    }\n\n    function`;
code = code.replace('    function', setter);

// 5. Update _afterSwap to check the price and disable limits
const antiWhaleOld = `        // Anti-Whale
        if (limitsEnabled) {
            require(volume <= MAX_TX_AMOUNT, "Anti-Whale: Max TX exceeded");
        }`;

const antiWhaleNew = `        // Anti-Whale Auto-Disable
        if (limitsEnabled) {
            require(volume <= MAX_TX_AMOUNT, "Anti-Whale: Max TX exceeded");
            
            if (disableAntiWhaleSqrtPrice > 0) {
                (uint160 sqrtPriceX96, , , ) = poolManager.getSlot0(key.toId());
                if (sqrtPriceX96 >= disableAntiWhaleSqrtPrice) {
                    limitsEnabled = false;
                }
            }
        }`;

code = code.replace(antiWhaleOld, antiWhaleNew);

fs.writeFileSync('src/IRLUniswapV4Hook.sol', code);
console.log("Hook updated");
