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
    ctx.reply('Welcome to the official Internet Robinhood Lottery ($IRL) bot! 🏹\n\nUse the menu to explore the project, check the pots, or view the contracts.');
});

bot.on('new_chat_members', (ctx) => {
    const newMembers = ctx.message.new_chat_members;
    for (const member of newMembers) {
        // Prevent welcoming other bots
        if (member.is_bot) continue;
        const name = member.first_name || 'Robinhood';
        ctx.reply(`Welcome to the Internet Robinhood Lottery ($IRL) community, ${name}! 🏹\n\nWe steal from the whales to give back to the community!\nType /about to learn how our automated Uniswap V4 tax redistribution works, or check the menu to view the active prize pots.`);
    }
});

bot.command('about', (ctx) => {
    const text = `🏹 *About Internet Robinhood Lottery ($IRL)* 🏹\n\nWe steal from the whales to give back to the community! $IRL is an innovative DeFi ecosystem running on the Robinhood Chain, utilizing cutting-edge **Uniswap V4 Hooks** to create a fair, gamified, and highly rewarding environment.\n\n🌟 *Core Mechanics:*\n\n1️⃣ **The Daily Lottery (Chainlink VRF)**\nTrade $IRL to accumulate volume. Every time you cross the volume threshold, an **NFT Ticket** is automatically minted to your wallet. Every day, a Chainlink VRF oracle draws a random winning ticket, and the holder instantly receives the entire Daily Lottery Pot in ETH!\n\n2️⃣ **Hourly Top Trader Rewards**\nThe Top 10 traders of every hour automatically share the Hourly Reward Pot. The more volume you generate, the higher your rank, and the bigger your share of the ETH airdrop.\n\n3️⃣ **Staking Multipliers**\nStake your $IRL tokens to unlock powerful boosts! Stakers receive **bonus NFT Tickets** for the daily lottery and up to a **50% bonus multiplier** on their hourly ETH rewards.\n\n4️⃣ **Anti-Whale Protection**\nTo protect early liquidity, strict maximum transaction sizes and wallet holdings are enforced at launch, ensuring a fair distribution starting from our $20k initial Market Cap.\n\n*Zero Sell Pressure*: All ecosystem taxes are collected natively in WETH directly from the liquidity pool (Swap-and-Liquify via V4). The chart never dumps to fund the lottery!\n\nUse /tokenomics to see the exact tax breakdown, or /contracts to verify our code.`;
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
        { command: 'about', description: 'Learn about the Internet Robinhood Lottery project' },
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
