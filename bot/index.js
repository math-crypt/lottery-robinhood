const { Telegraf } = require('telegraf');
const { ethers } = require('ethers');
require('dotenv').config();

const bot = new Telegraf(process.env.BOT_TOKEN);
const provider = new ethers.JsonRpcProvider(process.env.RPC_URL);

// Contract Addresses
const HOOK_ADDRESS = process.env.HOOK_ADDRESS;
const NFT_ADDRESS = process.env.NFT_ADDRESS;

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

bot.start((ctx) => ctx.reply('Welcome to the official Internet Robin Lottery ($IRL) bot! 🏹\n\nAvailable commands:\n/tickets - View the number of lottery tickets in play\n/pot - View the current size of the prize pots'));

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

// Setup Event Listeners
async function setupListeners() {
    console.log("Listening for Smart Contract events...");

    hookContract.on("LotteryWinnerDrawn", async (winner, tokenId, prize, event) => {
        const prizeEth = parseFloat(ethers.formatEther(prize)).toFixed(4);
        const message = `🎉 *NEW LOTTERY WINNER!* 🎉\n\nTicket #${tokenId.toString()} was just drawn by Chainlink VRF!\n\n👤 Winner: \`${winner}\`\n💸 Prize: *${prizeEth} ETH* transferred instantly!\n\nCongratulations to the winner! 🏹`;
        
        if(CHANNEL_ID) {
            try {
                const msg = await bot.telegram.sendMessage(CHANNEL_ID, message, { parse_mode: 'Markdown' });
                // Pin the winning message
                await bot.telegram.pinChatMessage(CHANNEL_ID, msg.message_id);
            } catch (error) {
                console.error("Error sending or pinning message:", error);
            }
        }
    });

    hookContract.on("HourlyRewardsDistributed", (currentHour, totalPotDistributed, event) => {
        const message = `⏱️ *HOURLY REWARDS DISTRIBUTED* ⏱️\n\nThe hourly pot has just been automatically airdropped to the Top Traders and the community!\n\nTrade $IRL to participate in the next distribution! 🏹`;
        
        if(CHANNEL_ID) {
            bot.telegram.sendMessage(CHANNEL_ID, message, { parse_mode: 'Markdown' }).catch(console.error);
        }
    });
}

bot.launch().then(() => {
    console.log("Telegram Bot successfully started!");
    
    // Set bot commands menu
    bot.telegram.setMyCommands([
        { command: 'tickets', description: 'View the number of lottery tickets in play' },
        { command: 'pot', description: 'View the current size of the prize pots' }
    ]).catch(console.error);

    setupListeners();
}).catch(console.error);

// Enable graceful stop
process.once('SIGINT', () => bot.stop('SIGINT'));
process.once('SIGTERM', () => bot.stop('SIGTERM'));
