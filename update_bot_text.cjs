const fs = require('fs');

function updateBot(filename) {
    let code = fs.readFileSync(filename, 'utf8');

    // 1. Remove Top10 command
    code = code.replace(/bot\.command\('top10'[\s\S]*?\}\);\n/, '');

    // 2. Update About command text
    const oldAbout = `2️⃣ **Hourly Rewards (The Robinhood Split)**
The 1% Hourly Reward Pot is split in two: **50%** is airdropped to the Top 10 traders of the hour, and the other **50%** is automatically redistributed to all traders on every single trade! The more volume you generate, the higher your rank, and the bigger your share of the ETH airdrops.

3️⃣ **Staking Multipliers**
Stake your $IRL tokens to unlock powerful boosts! Stakers receive **bonus NFT Tickets** for the daily lottery and up to a **50% bonus multiplier** on their hourly ETH rewards.`;

    const newAbout = `2️⃣ **Hourly Rewards (The Robinhood Split)**
The 1% Hourly Reward Pot is split in two:
- **0.5%** is automatically redistributed to all traders as **Instant Cashback** on every single trade!
- **0.5%** is shared among **ALL Active Traders** at the end of the hour, perfectly proportional to your "Volume Score". No fixed limits, everyone wins!

3️⃣ **Staking Volume Multiplier**
Stake your $IRL tokens to unlock powerful boosts! Stakers receive **bonus NFT Tickets** for the daily lottery, and get up to a **1.5x Multiplier** on their Volume Score. Earn a massive share of the Hourly Pot without needing to over-trade!`;
    
    code = code.replace(oldAbout, newAbout);

    // 3. Update Tokenomics command text
    const oldTok = `⏱️ *1% Hourly Rewards*: Split 50/50! Half goes to the Top 10 Traders of the hour, and the other half is automatically redistributed to all traders on every trade.`;
    const newTok = `⏱️ *1% Hourly Rewards*: Split 50/50! Half goes to the **Global Trader Pool** (shared proportionally to your Volume Score), and the other half is automatically redistributed to all traders on every trade.`;
    code = code.replace(oldTok, newTok);

    fs.writeFileSync(filename, code);
}

updateBot('bot/index.js');
updateBot('bot/test-bot.js');
console.log("Bot updated");
