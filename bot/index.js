const { Telegraf, Markup } = require('telegraf');
const { ethers } = require('ethers');
require('dotenv').config();

const bot = new Telegraf(process.env.BOT_TOKEN);
const provider = new ethers.JsonRpcProvider(process.env.RPC_URL);

// Contract Addresses
const HOOK_ADDRESS = process.env.HOOK_ADDRESS;
const NFT_ADDRESS = process.env.NFT_ADDRESS;
const TOKEN_ADDRESS = process.env.TOKEN_ADDRESS || "0xYourTokenAddress";

// Explorer URL Base
const EXPLORER_URL = process.env.EXPLORER_URL || "https://explorer.robinhood.com";

// Simple ABIs
const hookAbi = [
  "function lotteryPot() view returns (uint256)",
  "function hourlyRewardPot() view returns (uint256)",
  "event LotteryWinnerDrawn(address indexed winner, uint256 tokenId, uint256 prize)",
  "event HourlyRewardsDistributed(uint256 currentHour, uint256 totalPotDistributed)"
];

const nftAbi = [
  "function totalTicketsMinted() view returns (uint256)"
];

const hookContract = new ethers.Contract(HOOK_ADDRESS, hookAbi, provider);
const nftContract = new ethers.Contract(NFT_ADDRESS, nftAbi, provider);

// Channel ID to announce events
const CHANNEL_ID = process.env.CHANNEL_ID;

// --- Bot Commands ---

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

bot.command('tickets', async (ctx) => {
    try {
        const total = await nftContract.totalTicketsMinted();
        ctx.reply(`🎟️ Currently, *${total.toString()} tickets* have been generated for today's lottery!`, { parse_mode: 'Markdown' });
    } catch (error) {
        console.error(error);
        ctx.reply("❌ Unable to read contract data.");
    }
});

bot.command('pot', async (ctx) => {
    try {
        const lotteryPot = await hookContract.lotteryPot();
        const rewardPot = await hookContract.hourlyRewardPot();
        
        const lotteryEth = parseFloat(ethers.formatEther(lotteryPot)).toFixed(4);
        const rewardEth = parseFloat(ethers.formatEther(rewardPot)).toFixed(4);
        
        ctx.reply(`💰 *Current Prize Pots* 💰\n\n🏆 Today's Lottery: ${lotteryEth} ETH\n⏱️ Hourly Rewards: ${rewardEth} ETH`, { parse_mode: 'Markdown' });
    } catch (error) {
        console.error(error);
        ctx.reply("❌ Unable to read contract data.");
    }
});

// --- Event Listeners ---

async function setupListeners() {
    console.log("Listening for Smart Contract events...");

    hookContract.on("LotteryWinnerDrawn", async (winner, tokenId, prize, event) => {
        const prizeEth = parseFloat(ethers.formatEther(prize)).toFixed(4);
        const txHash = event.log.transactionHash;
        
        const message = `🎉 *NEW LOTTERY WINNER!* 🎉\n\nTicket #${tokenId.toString()} was just drawn by Chainlink VRF!\n\n👤 Winner: \`${winner}\`\n💸 Prize: *${prizeEth} ETH* transferred instantly!\n\nCongratulations to the winner! 🏹`;
        
        if(CHANNEL_ID) {
            try {
                const msg = await bot.telegram.sendMessage(CHANNEL_ID, message, { 
                    parse_mode: 'Markdown',
                    ...Markup.inlineKeyboard([
                        Markup.button.url('🔍 View Transaction on Robinhood Scan', `${EXPLORER_URL}/tx/${txHash}`)
                    ])
                });
                await bot.telegram.pinChatMessage(CHANNEL_ID, msg.message_id);
            } catch (error) {
                console.error("Error sending or pinning message:", error);
            }
        }
    });

    hookContract.on("HourlyRewardsDistributed", (currentHour, totalPotDistributed, event) => {
        const txHash = event.log.transactionHash;
        const message = `⏱️ *HOURLY REWARDS DISTRIBUTED* ⏱️\n\nThe hourly pot has just been automatically airdropped to the Top Traders and the community!\n\nTrade $IRL to participate in the next distribution! 🏹`;
        
        if(CHANNEL_ID) {
            bot.telegram.sendMessage(CHANNEL_ID, message, { 
                parse_mode: 'Markdown',
                ...Markup.inlineKeyboard([
                    Markup.button.url('🔍 View Distribution on Robinhood Scan', `${EXPLORER_URL}/tx/${txHash}`)
                ])
            }).catch(console.error);
        }
    });
}

bot.launch().then(() => {
    console.log("Telegram Bot successfully started!");
    
    // Set bot commands menu
    bot.telegram.setMyCommands([
        { command: 'about', description: 'Learn about the Internet Robin Lottery project' },
        { command: 'tokenomics', description: 'View the taxes and pot distributions' },
        { command: 'contracts', description: 'View official smart contract addresses' },
        { command: 'tickets', description: 'View the number of lottery tickets in play' },
        { command: 'pot', description: 'View the current size of the prize pots' }
    ]).catch(console.error);

    setupListeners();
}).catch(console.error);

// Enable graceful stop
process.once('SIGINT', () => bot.stop('SIGINT'));
process.once('SIGTERM', () => bot.stop('SIGTERM'));
