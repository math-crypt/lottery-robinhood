const { Telegraf, Markup } = require('telegraf');
require('dotenv').config();

const bot = new Telegraf(process.env.BOT_TOKEN);
const EXPLORER_URL = process.env.EXPLORER_URL || "https://explorer.robinhood.com";
const HOOK_ADDRESS = process.env.HOOK_ADDRESS || "0xHookAddress";
const TOKEN_ADDRESS = process.env.TOKEN_ADDRESS || "0xTokenAddress";
const NFT_ADDRESS = process.env.NFT_ADDRESS || "0xNftAddress";

bot.start((ctx) => {
    ctx.reply('Welcome to the official Internet Robinhood Lottery ($IRL) bot! 🏹\n\nUse the menu to explore the project, check the pots, or view the contracts.');
});

bot.on('new_chat_members', (ctx) => {
    const newMembers = ctx.message.new_chat_members;
    for (const member of newMembers) {
        if (member.is_bot) continue;
        const name = member.first_name || 'Robinhood';
        ctx.reply(`Welcome to the Internet Robinhood Lottery ($IRL) community, ${name}! 🏹\n\nWe steal from the whales to give back to the community! 🏹\n\n⚠️ *Phase 1 Info*: There is NO website and NO official Twitter yet. Everything happens 100% On-Chain and here in Telegram!\n\nType /about to learn how our automated Uniswap V4 tax redistribution works, or check the menu to view the active prize pots.`);
    }
});

bot.command('about', (ctx) => {
    const text = `🏹 *About Internet Robinhood Lottery ($IRL)* 🏹\n\nWe steal from the whales to give back to the community! $IRL is an innovative DeFi ecosystem running on the Robinhood Chain, utilizing cutting-edge **Uniswap V4 Hooks** to create a fair, gamified, and highly rewarding environment.\n\n🌟 *Core Mechanics:*\n\n1️⃣ **The Daily Lottery (Chainlink VRF)**\nTrade $IRL to accumulate volume. Every time you cross the volume threshold, an **NFT Ticket** is automatically minted to your wallet. Every day, a Chainlink VRF oracle draws a random winning ticket, and the holder instantly receives the entire Daily Lottery Pot in ETH!\n\n2️⃣ **Hourly Rewards (The Robinhood Split)**\nThe 1% Hourly Reward Pot is split in two: **50%** is airdropped to the Top 10 traders of the hour, and the other **50%** is automatically redistributed to all traders on every single trade! The more volume you generate, the higher your rank, and the bigger your share of the ETH airdrops.\n\n3️⃣ **Staking Multipliers**\nStake your $IRL tokens to unlock powerful boosts! Stakers receive **bonus NFT Tickets** for the daily lottery and up to a **50% bonus multiplier** on their hourly ETH rewards.\n\n4️⃣ **Anti-Whale Protection**\nTo protect early liquidity, strict maximum transaction sizes and wallet holdings are enforced at launch, ensuring a fair distribution starting from our $20k initial Market Cap.\n\n*Zero Sell Pressure*: All ecosystem taxes are collected natively in WETH directly from the liquidity pool (Swap-and-Liquify via V4). The chart never dumps to fund the lottery!\n\nUse /tokenomics to see the exact tax breakdown, or /contracts to verify our code.`;
    ctx.reply(text, { parse_mode: 'Markdown' });
});

bot.command('tokenomics', (ctx) => {
    const text = `📊 *$IRL Tokenomics & Taxes* 📊\n\nThere is a strict *3% tax* on every swap (buys and sells), extracted natively in WETH:\n\n🏆 *1% Daily Lottery*: 100% of this pot goes to a random ticket holder every day via Chainlink VRF!\n⏱️ *1% Hourly Rewards*: Split 50/50! Half goes to the **Global Trader Pool** (shared proportionally to your Volume Score), and the other half is automatically redistributed to all traders on every trade.\n⚙️ *1% Protocol*: Used to pay for Chainlink VRF gas, automation upkeep, and marketing.\n\nNo tokens are dumped on the chart; taxes are collected cleanly in WETH!`;
    ctx.reply(text, { parse_mode: 'Markdown' });
});

bot.command('contracts', (ctx) => {
    const text = `📜 *Official Smart Contracts* 📜\n\nVerify our code directly on Robinhood Scan:\n\n🪙 *$IRL Token*: \`${TOKEN_ADDRESS}\`\n🪝 *Uniswap V4 Hook*: \`${HOOK_ADDRESS}\`\n🎟️ *NFT Tickets*: \`${NFT_ADDRESS}\`\n\n_Make sure you only interact with these official addresses!_`;
    ctx.reply(text, { parse_mode: 'Markdown', ...Markup.inlineKeyboard([
        Markup.button.url('View Hook on Explorer', `${EXPLORER_URL}/address/${HOOK_ADDRESS}`)
    ])});
});

bot.command('stake', (ctx) => {
    const text = `🏦 *How to Stake $IRL (Phase 1)* 🏦

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
`;
    ctx.reply(text, { parse_mode: 'Markdown' });
});

bot.command('tickets', (ctx) => {
    ctx.reply(`🎟️ Currently, *142 tickets* have been generated for today's lottery!`, { parse_mode: 'Markdown' });
});



bot.command('pot', (ctx) => {
    ctx.reply(`💰 *Current Prize Pots* 💰\n\n🏆 Today's Lottery: 1.4500 ETH\n⏱️ Hourly Rewards: 0.8500 ETH`, { parse_mode: 'Markdown' });
});

bot.command('test', async (ctx) => {
    const chatId = ctx.chat.id;
    const dummyTx = "0x9876543210abcdef9876543210abcdef9876543210abcdef9876543210abcdef";
    
    // Announce Lottery Winner
    const messageWinner = `🎉 *NEW LOTTERY WINNER!* 🎉\n\nTicket #89 was just drawn by Chainlink VRF!\n\n👤 Winner: \`0x1234...abcd\`\n💸 Prize: *1.4500 ETH* transferred instantly!\n\nCongratulations to the winner! 🏹`;
    const msg = await ctx.reply(messageWinner, { 
        parse_mode: 'Markdown',
        ...Markup.inlineKeyboard([
            Markup.button.url('🔍 View Transaction on Robinhood Scan', `${EXPLORER_URL}/tx/${dummyTx}`)
        ])
    });
    
    try {
        await bot.telegram.pinChatMessage(chatId, msg.message_id);
    } catch(e) {}

    // Announce Hourly Rewards
    const messageRewards = `⏱️ *HOURLY REWARDS DISTRIBUTED* ⏱️\n\nThe hourly pot has just been automatically airdropped to the Top Traders and the community!\n\nTrade $IRL to participate in the next distribution! 🏹`;
    await ctx.reply(messageRewards, { 
        parse_mode: 'Markdown',
        ...Markup.inlineKeyboard([
            Markup.button.url('🔍 View Distribution on Robinhood Scan', `${EXPLORER_URL}/tx/${dummyTx}`)
        ])
    });
});

bot.launch().then(() => {
    console.log("Test Bot is running! Go to Telegram and type /test or /about to see the new messages.");
    bot.telegram.setMyCommands([
        { command: 'about', description: 'Learn about the Internet Robinhood Lottery project' },
        { command: 'tokenomics', description: 'View the taxes and pot distributions' },
        { command: 'contracts', description: 'View official smart contract addresses' },
        { command: 'tickets', description: 'View the number of lottery tickets in play' },
        { command: 'pot', description: 'View the current size of the prize pots' },
        { command: 'test', description: 'Test the automatic announcements' }
    ]).catch(console.error);
}).catch(console.error);

process.once('SIGINT', () => bot.stop('SIGINT'));
process.once('SIGTERM', () => bot.stop('SIGTERM'));
