const fs = require('fs');

const asciiArtAndSocials = `    /**
     * @notice PROJECT INFO & SOCIALS
     * 
     *      (
     *       \\
     *        )
     * ##-------->  $IRL Lottery
     *        )
     *       /
     *      (
     * 
     * We steal from the whales to give back to the community!
     * 
     * Telegram: t.me/InternetRobinhoodLottery
     * GitHub: https://github.com/math-crypt/lottery-robinhood
     * Website: None (Phase 1 is 100% On-Chain)
     * Twitter: None (Phase 1 is Community Driven)
     */
    string public constant SOCIALS = "Telegram: t.me/InternetRobinhoodLottery | GitHub: https://github.com/math-crypt/lottery-robinhood";`;

// 1. Update InternetRobinLottery.sol
let tokenCode = fs.readFileSync('src/InternetRobinLottery.sol', 'utf8');
tokenCode = tokenCode.replace('Internet Robin Lottery', 'Internet Robinhood Lottery');
tokenCode = tokenCode.replace('ERC20("Internet Robin Lottery", "IRL")', 'ERC20("Internet Robinhood Lottery", "IRL")');
if (!tokenCode.includes('string public constant SOCIALS')) {
    tokenCode = tokenCode.replace('contract InternetRobinLottery is ERC20, Ownable {', 'contract InternetRobinLottery is ERC20, Ownable {\n' + asciiArtAndSocials);
}
fs.writeFileSync('src/InternetRobinLottery.sol', tokenCode);

// 2. Update IRLStaking.sol
let stakingCode = fs.readFileSync('src/IRLStaking.sol', 'utf8');
if (!stakingCode.includes('string public constant SOCIALS')) {
    stakingCode = stakingCode.replace('contract IRLStaking is Ownable, ReentrancyGuard {', 'contract IRLStaking is Ownable, ReentrancyGuard {\n' + asciiArtAndSocials);
}
fs.writeFileSync('src/IRLStaking.sol', stakingCode);

// 3. Update bot/index.js
let botCode = fs.readFileSync('bot/index.js', 'utf8');
const oldWelcome = "We steal from the whales to give back to the community!\\nType /about to learn how our automated Uniswap V4 tax redistribution works";
const newWelcome = "We steal from the whales to give back to the community! 🏹\\n\\n⚠️ *Phase 1 Info*: There is NO website and NO official Twitter yet. Everything happens 100% On-Chain and here in Telegram!\\n\\nType /about to learn how our automated Uniswap V4 tax redistribution works";
botCode = botCode.replace(oldWelcome, newWelcome);

const stakeCmd = `
bot.command('stake', (ctx) => {
    const text = \`🏦 *How to Stake $IRL (Phase 1)* 🏦

⚠️ *Note:* There is NO official website or DApp for Phase 1! Staking is done directly on the Robinhood Scan block explorer. This is the most secure, trustless way to interact with a smart contract.

**Step-by-Step Guide:**
1️⃣ Go to the $IRL Token Contract on Robinhood Scan.
2️⃣ Click "Write Contract" and connect your Web3 Wallet.
3️⃣ Call the \`approve\` function:
   - \`spender\`: The Staking Contract Address
   - \`amount\`: The amount of $IRL you want to stake (with 18 zeros)
4️⃣ Go to the Staking Contract on Robinhood Scan.
5️⃣ Click "Write Contract", connect your wallet, and call \`stake\` with your amount!

*Links will be provided here once contracts are officially deployed.*
\`;
    ctx.reply(text, { parse_mode: 'Markdown' });
});
`;

if (!botCode.includes("bot.command('stake'")) {
    botCode = botCode.replace(/bot\.command\('tickets'/g, stakeCmd.trim() + "\n\nbot.command('tickets'");
}

fs.writeFileSync('bot/index.js', botCode);

// 4. Update bot/test-bot.js
let testBotCode = fs.readFileSync('bot/test-bot.js', 'utf8');
testBotCode = testBotCode.replace(oldWelcome, newWelcome);
if (!testBotCode.includes("bot.command('stake'")) {
    testBotCode = testBotCode.replace(/bot\.command\('tickets'/g, stakeCmd.trim() + "\n\nbot.command('tickets'");
}
fs.writeFileSync('bot/test-bot.js', testBotCode);

console.log("Updated contracts and bot");
