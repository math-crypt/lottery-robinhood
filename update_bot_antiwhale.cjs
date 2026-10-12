const fs = require('fs');

['bot/index.js'].forEach(file => {
    let botCode = fs.readFileSync(file, 'utf8');
    
    // Replace the entire about command to ensure it's fully updated
    const aboutRegex = /bot\.command\('about', \(ctx\) => \{[\s\S]*?\}\);/;
    
    const newAboutCmd = `bot.command('about', (ctx) => {
    const text = \`🏹 *About Internet Robinhood Lottery ($IRL)* 🏹

We steal from the whales to give back to the community! $IRL is an innovative DeFi ecosystem running on the Robinhood Chain, utilizing cutting-edge **Uniswap V4 Hooks** to create a fair, gamified, and highly rewarding environment.

🌟 *Core Mechanics:*

1️⃣ **The Daily Lottery (Chainlink VRF)**
Trade $IRL to accumulate volume. Every time you cross the volume threshold, an **NFT Ticket** is automatically minted to your wallet. Every day, a Chainlink VRF oracle draws a random winning ticket, and the holder instantly receives the entire Daily Lottery Pot in ETH!

2️⃣ **Hourly Rewards (The Robinhood Split)**
The 1% Hourly Reward Pot is split in two:
- **0.5%** is automatically redistributed to all traders as **Instant Cashback** on every single trade!
- **0.5%** is shared among **ALL Active Traders** at the end of the hour, perfectly proportional to your "Volume Score". No fixed limits, everyone wins!

3️⃣ **Staking Volume Multiplier**
Stake your $IRL tokens to unlock powerful boosts! Stakers receive **bonus NFT Tickets** for the daily lottery, and get up to a **1.5x Multiplier** on their Volume Score. Earn a massive share of the Hourly Pot without needing to over-trade!

4️⃣ **Automated Anti-Whale Protection**
To protect early liquidity, strict maximum transaction sizes and wallet holdings are enforced at launch. **These limits automatically disable once the Market Cap reaches $40k**, unleashing the whales dynamically without manual developer intervention!

*Zero Sell Pressure*: All ecosystem taxes are collected natively in WETH directly from the liquidity pool (Swap-and-Liquify via V4). The chart never dumps to fund the lottery!

Use /tokenomics to see the exact tax breakdown, or /contracts to verify our code.\`;
    ctx.reply(text, { parse_mode: 'Markdown' });
});`;

    botCode = botCode.replace(aboutRegex, newAboutCmd);
    fs.writeFileSync(file, botCode);
});
console.log("Bot about command updated");
