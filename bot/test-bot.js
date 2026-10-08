const { Telegraf, Markup } = require('telegraf');
require('dotenv').config();

const bot = new Telegraf(process.env.BOT_TOKEN);
const EXPLORER_URL = process.env.EXPLORER_URL || "https://explorer.robinhood.com";
const HOOK_ADDRESS = process.env.HOOK_ADDRESS || "0xHookAddress";
const TOKEN_ADDRESS = process.env.TOKEN_ADDRESS || "0xTokenAddress";
const NFT_ADDRESS = process.env.NFT_ADDRESS || "0xNftAddress";

bot.start((ctx) => {
    ctx.reply('Welcome to the official Internet Robin Lottery ($IRL) bot! 🏹\n\nUse the menu to explore the project, check the pots, or view the contracts.');
});

bot.command('about', (ctx) => {
    const text = `🏹 *About Internet Robin Lottery ($IRL)* 🏹\n\nWe steal from the whales to give to the community! $IRL is an innovative DeFi ecosystem running on the Robinhood Chain.\n\nBy holding and trading $IRL, you automatically participate in a revolutionary redistribution system powered by Uniswap V4 Hooks.`;
    ctx.reply(text, { parse_mode: 'Markdown' });
});

bot.command('tokenomics', (ctx) => {
    const text = `📊 *$IRL Tokenomics & Taxes* 📊\n\nThere is a strict *3% tax* on every swap (buys and sells), extracted natively in WETH:\n\n🏆 *1% Daily Lottery*: 100% of this pot goes to a random ticket holder every day via Chainlink VRF!\n⏱️ *1% Hourly Rewards*: Distributed back to the Top 10 Traders of the hour.\n⚙️ *1% Protocol*: Used to pay for Chainlink VRF gas, automation upkeep, and marketing.\n\nNo tokens are dumped on the chart; taxes are collected cleanly in WETH!`;
    ctx.reply(text, { parse_mode: 'Markdown' });
});

bot.command('contracts', (ctx) => {
    const text = `📜 *Official Smart Contracts* 📜\n\nVerify our code directly on Robinhood Scan:\n\n🪙 *$IRL Token*: \`${TOKEN_ADDRESS}\`\n🪝 *Uniswap V4 Hook*: \`${HOOK_ADDRESS}\`\n🎟️ *NFT Tickets*: \`${NFT_ADDRESS}\`\n\n_Make sure you only interact with these official addresses!_`;
    ctx.reply(text, { parse_mode: 'Markdown', ...Markup.inlineKeyboard([
        Markup.button.url('View Hook on Explorer', `${EXPLORER_URL}/address/${HOOK_ADDRESS}`)
    ])});
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
        { command: 'about', description: 'Learn about the Internet Robin Lottery project' },
        { command: 'tokenomics', description: 'View the taxes and pot distributions' },
        { command: 'contracts', description: 'View official smart contract addresses' },
        { command: 'tickets', description: 'View the number of lottery tickets in play' },
        { command: 'pot', description: 'View the current size of the prize pots' },
        { command: 'test', description: 'Test the automatic announcements' }
    ]).catch(console.error);
}).catch(console.error);

process.once('SIGINT', () => bot.stop('SIGINT'));
process.once('SIGTERM', () => bot.stop('SIGTERM'));
