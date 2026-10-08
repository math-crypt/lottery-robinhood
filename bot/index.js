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

bot.start((ctx) => ctx.reply('Bienvenue sur le bot officiel de Internet Robin Lottery ($IRL) ! 🏹\n\nCommandes disponibles :\n/tickets - Voir le nombre de tickets de loterie en jeu\n/pot - Voir la taille actuelle des cagnottes'));

bot.command('tickets', async (ctx) => {
    try {
        const total = await nftContract.totalTicketsMinted();
        ctx.reply(`🎟️ Actuellement, *${total.toString()} tickets* ont été générés pour la loterie d'aujourd'hui !`, { parse_mode: 'Markdown' });
    } catch (error) {
        console.error(error);
        ctx.reply("❌ Impossible de lire les données du contrat.");
    }
});

bot.command('pot', async (ctx) => {
    try {
        const lotteryPot = await hookContract.lotteryPot();
        const rewardPot = await hookContract.hourlyRewardPot();
        
        const lotteryEth = parseFloat(ethers.formatEther(lotteryPot)).toFixed(4);
        const rewardEth = parseFloat(ethers.formatEther(rewardPot)).toFixed(4);
        
        ctx.reply(`💰 *Cagnottes Actuelles* 💰\n\n🏆 Loterie du jour : ${lotteryEth} ETH\n⏱️ Récompenses horaires : ${rewardEth} ETH`, { parse_mode: 'Markdown' });
    } catch (error) {
        console.error(error);
        ctx.reply("❌ Impossible de lire les données du contrat.");
    }
});

// Setup Event Listeners
async function setupListeners() {
    console.log("Listening for Smart Contract events...");

    hookContract.on("LotteryWinnerDrawn", (winner, tokenId, prize, event) => {
        const prizeEth = parseFloat(ethers.formatEther(prize)).toFixed(4);
        const message = `🎉 *NOUVEAU GAGNANT DE LA LOTERIE !* 🎉\n\nLe ticket #${tokenId.toString()} vient d'être tiré au sort par Chainlink VRF !\n\n👤 Gagnant : \`${winner}\`\n💸 Gain : *${prizeEth} ETH* transférés instantanément !\n\nFélicitations au gagnant ! 🏹`;
        
        if(CHANNEL_ID) {
            bot.telegram.sendMessage(CHANNEL_ID, message, { parse_mode: 'Markdown' }).catch(console.error);
        }
    });

    hookContract.on("HourlyRewardsDistributed", (currentHour, totalPotDistributed, event) => {
        const message = `⏱️ *RÉCOMPENSES HORAIRES DISTRIBUÉES* ⏱️\n\nLa cagnotte de l'heure vient d'être airdroppée automatiquement aux Top Traders et à la communauté !\n\nTradez $IRL pour participer à la prochaine distribution ! 🏹`;
        
        if(CHANNEL_ID) {
            bot.telegram.sendMessage(CHANNEL_ID, message, { parse_mode: 'Markdown' }).catch(console.error);
        }
    });
}

bot.launch().then(() => {
    console.log("Bot Telegram démarré avec succès !");
    setupListeners();
}).catch(console.error);

// Enable graceful stop
process.once('SIGINT', () => bot.stop('SIGINT'));
process.once('SIGTERM', () => bot.stop('SIGTERM'));
