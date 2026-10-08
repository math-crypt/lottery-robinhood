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
  "event HourlyRewardsDistributed(uint256 currentHour, uint256 totalPotDistributed)",
  "function topTradersPerHour(uint256, uint256) view returns (address)",
  "function userVolumePerHour(uint256, address) view returns (uint256)"
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
        ctx.reply(`Welcome to the Internet Robinhood Lottery ($IRL) community, ${name}! 🏹\n\nWe steal from the whales to give back to the community! 🏹\n\n⚠️ *Phase 1 Info*: There is NO website and NO official Twitter yet. Everything happens 100% On-Chain and here in Telegram!\n\nType /about to learn how our automated Uniswap V4 tax redistribution works, or check the menu to view the active prize pots.`);
    }
});

bot.command('about', (ctx) => {
    const text = `🏹 *About Internet Robinhood Lottery ($IRL)* 🏹

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

Use /tokenomics to see the exact tax breakdown, or /contracts to verify our code.`;
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
