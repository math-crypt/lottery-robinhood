import fs from 'fs';

let code = fs.readFileSync('src/IRLUniswapV4Hook.sol', 'utf8');

const target = `            (bool success, ) = trader.call{value: cashback}("");
            if (!success) {
                protocolPot += cashback;
            }`;

const replacement = `            uint256 currentHour = block.timestamp / 1 hours;
            userCashbackPerHour[currentHour][trader] += cashback;
            if (!traderRecordedPerHour[currentHour][trader]) {
                traderRecordedPerHour[currentHour][trader] = true;
                allTradersPerHour[currentHour].push(trader);
            }`;

code = code.split(target).join(replacement);

fs.writeFileSync('src/IRLUniswapV4Hook.sol', code);
console.log("Done");
