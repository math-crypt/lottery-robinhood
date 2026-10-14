const { Telegraf, Markup } = require('telegraf');
const { ethers } = require('ethers');
require('dotenv').config();

const bot = new Telegraf(process.env.BOT_TOKEN);
const provider = new ethers.JsonRpcProvider(process.env.RPC_URL);
provider.on('error', (err) => console.error('RPC Provider error:', err));

// Contract Addresses
const HOOK_ADDRESS = process.env.HOOK_ADDRESS;
const NFT_ADDRESS = process.env.NFT_ADDRESS;
const TOKEN_ADDRESS = process.env.TOKEN_ADDRESS || "";

// Explorer URL Base
const EXPLORER_URL = process.env.EXPLORER_URL || "https://robin.etherscan.io";

// Simple ABIs
const hookAbi = [
  "function lotteryPot() view returns (uint256)",
  "function dailyLotteryPot() view returns (uint256)",
  "function sundayMegaPot() view returns (uint256)",
  "function hourlyRewardPot() view returns (uint256)",
  "function buybackPot() view returns (uint256)",
  "event LotteryWinnerDrawn(address indexed winner, uint256 tokenId, uint256 prize)",
  "event SundayMegaJackpotDrawn(address indexed winner, uint256 tokenId, uint256 prize)",
  "event HourlyRewardsDistributed(uint256 currentHour, uint256 totalPotDistributed)",
  "function userVolumePerHour(uint256, address) view returns (uint256)"
];

const nftAbi = [
  "function totalTicketsMinted() view returns (uint256)"
];

const isHookValid = ethers.isAddress(HOOK_ADDRESS);
const isNftValid = ethers.isAddress(NFT_ADDRESS);

const hookContract = isHookValid ? new ethers.Contract(HOOK_ADDRESS, hookAbi, provider) : null;
const nftContract = isNftValid ? new ethers.Contract(NFT_ADDRESS, nftAbi, provider) : null;

// Channel ID to announce events
const CHANNEL_ID = process.env.CHANNEL_ID;

// --- Bot Commands ---

bot.start((ctx) => {
    const text = `🏹 *Welcome to Internet Robinhood Lottery ($IRL)* 🏹\n\n` +
        `⏳ *STATUS: PRE-LAUNCH PHASE*\n` +
        `The smart contracts are currently undergoing final audit validations and are *NOT yet deployed on Robinhood Chain*.\n\n` +
        `🚨 *OFFICIAL CHANNELS & LAUNCH UPDATES:*\n` +
        `• 𝕏 *(Twitter)*: [x.com/IRL_Protocol](https://x.com/IRL_Protocol)\n` +
        `• ✈️ *Telegram*: [t.me/InternetRobinhoodLottery](https://t.me/InternetRobinhoodLottery)\n\n` +
        `• *Beware of fake tokens and scammers.* No team member will ever DM you first.\n\n` +
        `Explore the commands below to learn all about the protocol mechanics before liquidity seeding:\n` +
        `/about - Protocol thesis & V4 Hook mechanics\n` +
        `/tokenomics - 10% Launch Boost (24h or <$100k MC) -> 4% Standard Tax\n` +
        `/contracts - Smart contract status\n` +
        `/launch - Official launch status & roadmap\n` +
        `/socials - Official X and Telegram links\n` +
        `/security - 90% permanent locked LP & Single-Sided LP Vault\n` +
        `/stake - Staking Real Yield in native ETH`;
    ctx.reply(text, { 
        parse_mode: 'Markdown',
        ...Markup.inlineKeyboard([
            [Markup.button.url('Follow on 𝕏 (@IRL_Protocol)', 'https://x.com/IRL_Protocol')],
            [Markup.button.url('Telegram Community', 'https://t.me/InternetRobinhoodLottery')]
        ])
    });
});

bot.on('new_chat_members', (ctx) => {
    const newMembers = ctx.message.new_chat_members;
    for (const member of newMembers) {
        if (member.is_bot) continue;
        const rawHandle = member.username 
            ? `@${member.username}` 
            : (member.first_name ? `@${member.first_name}` : '@Robinhood');
        const mention = rawHandle.replace(/([_*`\[\]])/g, '\\$1');
        ctx.reply(
            `Welcome to the Internet Robinhood Lottery ($IRL) community, ${mention}! 🏹\n\n` +
            `⏳ *Note*: The smart contracts are *not yet live*. We are preparing the Robinhood Chain launch via Programmable.market!\n` +
            `🔔 *Stay connected here* to be notified the exact second the official contract is deployed and liquidity is seeded.\n\n` +
            `Type /about or /tokenomics to discover our audited Robinhood mechanics! 🏹`,
            { parse_mode: 'Markdown' }
        ).catch(console.error);
    }
});

bot.command('about', (ctx) => {
    const text = `🏹 *About Internet Robinhood Lottery ($IRL)* 🏹

We steal from the whales to give back to the community! $IRL is an innovative DeFi ecosystem launching via **Programmable.market** on the Robinhood Chain, utilizing cutting-edge **Uniswap V4 Hooks** to create a fair, gamified, and hyper-rewarding environment.

🚀 *10.0% Launch Boost Tax (Max 24h OR < $100k MC) ➔ 4.0% Standard Tax:*
To supercharge the very first hourly, daily, and weekly prize pots at launch, swaps carry a **10.0% Launch Boost Tax** for the **first 24 hours OR up to $100,000 Market Cap** (\`3.75%\` Hourly Pot + \`3.75%\` Lottery Pots + \`2.20%\` Protocol/Buyback Pot + \`0.30%\` Programmable), and then **permanently drop to the 4.0% Standard Tax** (\`1.25% / 1.25% / 1.20% / 0.30%\`) as soon as 24h elapses or $100k MC is reached!

1️⃣ **0.30% Immutable Programmable.market Platform Fee (0.15% Auto-Burn + 0.15% Treasury)**
- 0.30% (30 bps) routed immutably to Programmable.market on every swap (50% = \`0.15%\` permanently burned + 50% = \`0.15%\` Programmable treasury)!

2️⃣ **Epoch-Isolated Daily Lottery & Sunday Mega-Jackpot (3.75% Launch Boost ➔ 1.25% Standard via OpenVRF)**
Trade $IRL to earn NFT Tickets (0.10 WETH threshold per ticket, boosted up to +50% by staking). 
- Every midnight, a winner is drawn strictly among tickets minted *that day* (\`dailyPotByDay[dayId]\`).
- Every Sunday evening, the **Sunday Mega-Jackpot** is drawn among all tickets minted Monday through Sunday (\`weeklyPotByWeek[weekId]\`)!

3️⃣ **Hourly Rewards (3.75% Launch Boost ➔ 1.25% Standard: 35% Top 10 / 35% Cashback / 30% Real Yield Staking)**
- **35% Top 10 of the Hour**: Distributed strictly among the Top 10 traders of the hour, boosted by staking volume multipliers (up to +50% at 2% staked: e.g. 0.05 WETH traded = 0.075 WETH score!).
- **35% Hourly Trader Cashback**: Distributed once per hour to all active traders of that hour (1.3125% ETH cashback during Launch Boost, 0.4375% ETH standard cashback).
- **30% Stakers Real Yield**: Streamed as native ETH dividends across eligible $IRL stakers ranked from 0.1% (1M $IRL) to 2.0% (20M $IRL max tier)!

4️⃣ **Protocol Solvency & Double Deflation (2.20% Launch Boost ➔ 1.20% Standard)**
- **1.75% (Launch Boost) ➔ 0.75% (Standard)** for OpenVRF gas, automated keep-alives, and marketing (\`protocolPot\`).
- **0.45% (45 bps)** dedicated to **Hourly Batched $IRL Buyback & Burn** (\`buybackPot\` swapped once per hour on V4 to \`0xdead\`)!
🔥 *Double Deflation*: \`0.15%\` Programmable burn + \`0.45%\` Protocol Hourly Buyback & Burn = **0.60% of every swap permanently burned forever**!

5️⃣ **Automated Anti-Whale Protection (< $50k MC)**
Max transaction (1%) and max wallet (2%) dynamically protect the pool at launch and auto-disable at $50k Market Cap.

*Zero Sell Pressure*: All ecosystem taxes are collected natively in WETH directly from the liquidity pool (Swap-and-Liquify via V4). The chart never dumps to fund rewards!

Use /tokenomics to see the exact tax breakdown, or /contracts to verify our code.`;
    ctx.reply(text, { parse_mode: 'Markdown' });
});

bot.command('tokenomics', (ctx) => {
    const text = `📊 *$IRL Tokenomics & Taxes* 📊

All taxes are collected natively from the Uniswap V4 Hook in two automatic phases:
• 🚀 **Phase 1 — 10.0% Launch Boost Tax (Max 24h OR Up to $100,000 Market Cap):** Supercharges the first hourly, daily, and weekly reward pots (\`3.75%\` Hourly + \`3.75%\` Lottery + \`2.20%\` Protocol & Burn + \`0.30%\` Programmable).
• ⚡ **Phase 2 — 4.0% Standard Cruise Tax (Permanent after 24h or $100,000 Market Cap):** \`1.25%\` Hourly + \`1.25%\` Lottery + \`1.20%\` Protocol & Burn + \`0.30%\` Programmable.

⚡ *0.30% Programmable.market Platform Fee (Immutable)*:
  • Hardcoded 0.30% (30 bps) once per buy/sell to \`0xD88539d3c4C460136a733A3Fd60cf6BF269079da\`.
  • 50% (\`0.15%\`) permanently auto-burned + 50% (\`0.15%\`) Programmable Treasury!

🏆 *3.75% (Launch Boost) ➔ 1.25% (Standard) Epoch-Isolated Dual Lottery Pot*:
  • 50% for the **Daily Lottery** (1.875% at Launch ➔ 0.625% Standard via OpenVRF).
  • 50% for the **Sunday Mega-Jackpot** (1.875% at Launch ➔ 0.625% Standard).

⏱️ *3.75% (Launch Boost) ➔ 1.25% (Standard) Hourly Redistribution (35/35/30)*:
  • 35% for the **Top 10 Volume Traders** of the hour (1.3125% Boost ➔ 0.4375% Standard, boosted up to +50% by staking).
  • 35% for **All Active Traders** of the hour (1.3125% ETH cashback during Launch Boost ➔ 0.4375% ETH standard cashback distributed once per hour).
  • 30% for **Eligible Stakers (0.1% to 2.0% tiers)** streamed as native ETH Real Yield (1.125% Boost ➔ 0.375% Standard)!

⚙️ *2.20% (Launch Boost) ➔ 1.20% (Standard) Protocol & Deflation*:
  • **1.75% (Launch Boost) ➔ 0.75% (Standard)** for OpenVRF gas, automated keep-alives, and marketing (\`protocolPot\`).
  • **0.45% (45 bps)** dedicated to **Hourly Batched Buyback & Burn** (accumulated in \`buybackPot\` and swapped WETH -> $IRL to \`0xdead\` once per hour)!

🔥 *Double Deflation Flywheel*:
Total *0.60% of every swap is permanently burned* (\`0.15%\` Programmable auto-burn + \`0.45%\` protocol hourly V4 buyback & burn executed once every hour to \`0xdead\`)!

*Zero Chart Sell Pressure*: Taxes are intercepted natively by the V4 Hook, so the $IRL chart never dumps to fund rewards!`;
    ctx.reply(text, { parse_mode: 'Markdown' });
});

bot.command('contracts', (ctx) => {
    if (!isHookValid || !isNftValid) {
        const text = `📜 *Official Smart Contracts (Status: Pre-Launch)* 📜\n\n` +
            `⚠️ *Contracts are NOT yet live on Robinhood Chain!*\n\n` +
            `The contracts are finalized, audited, and scheduled for imminent deployment:\n` +
            `• 🪙 *$IRL Token*: Planned at vanity address starting with \`0x181...\` (IRL in hex)\n` +
            `• 🪝 *Uniswap V4 Hook*: Audited & Deterministic\n` +
            `• 🎟️ *NFT Tickets*: ERC-721 Provably Fair Tickets\n` +
            `• 🏦 *Real Yield Staking Vault*: MasterChef ETH Dividend Model\n` +
            `• 🛡️ *Liquidity & Marketing LP Vault*: 90% Permanent Locked LP + 10% Conditional Upper Bracket\n\n` +
            `🔔 *Stay connected in this group!* The verified onchain addresses will be broadcasted here the moment deployment is executed. *Do NOT buy any token claiming to be $IRL before our official announcement.*`;
        return ctx.reply(text, { parse_mode: 'Markdown' });
    }
    const text = `📜 *Official Smart Contracts* 📜\n\n` +
        `Verify our code directly on Robinhood Etherscan:\n\n` +
        `🪙 *$IRL Token*: \`${TOKEN_ADDRESS}\`\n` +
        `🪝 *Uniswap V4 Hook*: \`${HOOK_ADDRESS}\`\n` +
        `🎟️ *NFT Tickets*: \`${NFT_ADDRESS}\`\n\n` +
        `_Make sure you only interact with these official addresses!_`;
    ctx.reply(text, { parse_mode: 'Markdown', ...Markup.inlineKeyboard([
        Markup.button.url('View Hook on Explorer', `${EXPLORER_URL}/address/${HOOK_ADDRESS}`)
    ])});
});

bot.command('launch', (ctx) => {
    const text = `🚀 *$IRL Launch Status & Roadmap* 🚀\n\n` +
        `1️⃣ **Contract Code**: 100% complete, gas-optimized, and security audited.\n` +
        `2️⃣ **Network**: Robinhood Chain (Arbitrum L2, Chain ID 4663).\n` +
        `3️⃣ **Fair Launch**: 90% of total supply (900M $IRL) is permanently locked forever in PoolManager via IRLMarketingVault, with 10% (100M $IRL) conditionally locked in the Single-Sided Upper Marketing Bracket.\n` +
        `4️⃣ **Current Status**: *Pre-Launch Phase*. Contracts are NOT yet live.\n\n` +
        `📢 *Stay tuned on 𝕏 and Telegram!* The official launch time, Robinhood Etherscan links, and DEX pairs will be announced simultaneously.\n` +
        `• 𝕏: [x.com/IRL_Protocol](https://x.com/IRL_Protocol)\n` +
        `• Telegram: [t.me/InternetRobinhoodLottery](https://t.me/InternetRobinhoodLottery)\n\n` +
        `Turn on notifications so you don't miss it! 🏹`;
    ctx.reply(text, { 
        parse_mode: 'Markdown',
        ...Markup.inlineKeyboard([
            [Markup.button.url('Follow on 𝕏 (@IRL_Protocol)', 'https://x.com/IRL_Protocol')]
        ])
    });
});

bot.command(['socials', 'x', 'twitter'], (ctx) => {
    const text = `🌐 *Official $IRL Social Channels* 🌐\n\n` +
        `• 𝕏 *(Twitter)*: [x.com/IRL_Protocol](https://x.com/IRL_Protocol)\n` +
        `• ✈️ *Telegram*: [t.me/InternetRobinhoodLottery](https://t.me/InternetRobinhoodLottery)\n` +
        `• 💻 *GitHub & Whitepaper*: [github.com/math-crypt/lottery-robinhood](https://github.com/math-crypt/lottery-robinhood)\n\n` +
        `_Always verify you are interacting with these exact official accounts!_ 🏹`;
    ctx.reply(text, { 
        parse_mode: 'Markdown',
        ...Markup.inlineKeyboard([
            [Markup.button.url('Follow on 𝕏 (@IRL_Protocol)', 'https://x.com/IRL_Protocol')],
            [Markup.button.url('Join Telegram Community', 'https://t.me/InternetRobinhoodLottery')]
        ])
    });
});

bot.command('stake', (ctx) => {
    const text = `🏦 *How to Stake $IRL* 🏦

Stake your $IRL tokens in the Real Yield Sanctuary to:
1️⃣ Earn **Native ETH dividends** from 30% of every hourly swap pot (ranked across eligible stakers from 0.1% [1M $IRL] to 2.0% [20M $IRL] max tier).
2️⃣ Receive up to **10 Free NFT Tickets** every 4 days progressively (1 ticket per 2M $IRL staked every 4 days) with our **Hybrid Free-Ticket Claim Mechanic**:
   • *Zero Unstake Lock by Default*: Staking never locks your tokens unless you choose an instant ticket claim!
   • *Option A (Wait 24h Staked)*: Claim your free tickets after 24h of staking with **0h unstake lock** (withdraw anytime).
   • *Option B (Instant Claim <24h)*: Claim your up to 10 free tickets immediately upon staking, which locks unstake for **24 hours**.
3️⃣ Get up to a **+50% (1.5x) Multiplier** on your trading volume for both the Top 10 hourly leaderboard AND ticket minting (e.g. at 2% staked, 0.05 WETH traded counts as 0.075 WETH volume; 0.075 WETH counts as 0.1125 WETH >= 0.10 WETH -> 1 ticket!).
4️⃣ Increase your **Daily Volume Limit up to 10 tickets/day** (vs 6 for non-stakers), completely separate from your free 4-day tickets!
5️⃣ Expand your **Marketplace & Holding Caps** up to 10 daily / 70 weekly tickets (vs 6 daily / 42 weekly for non-stakers), enforced directly on-chain!

_Unlock the maximum bonuses by staking the full 2.0% supply quota (20M $IRL)!_`;
    ctx.reply(text, { parse_mode: 'Markdown' });
});

bot.command('security', (ctx) => {
    const text = `🔒 *Liquidity & Security (100% Rug-Proof)* 🔒

To guarantee complete safety for all investors, we use verifiable on-chain LP custody on Uniswap V4 (\`IRLMarketingVault.sol\`):

1️⃣ **90% Core Liquidity (PERMANENTLY LOCKED FOREVER)** 🔥
900,000,000 $IRL (90% of supply) is seeded into Uniswap V4 \`PoolManager\` under \`PERMANENT_LOCKED_SALT\` with **zero withdrawal or decrease function** in the contract. Core trading liquidity is locked forever. **It is mathematically impossible to rug-pull the LP.**

2️⃣ **10% Marketing Liquidity (CONDITIONAL SMART VAULT)** 🧠
100,000,000 $IRL (10% of supply) is locked as Single-Sided Liquidity in \`IRLMarketingVault\` under \`MARKETING_VAULT_SALT\`.
The Vault mathematically blocks withdrawing IRL tokens. Liquidity can ONLY be withdrawn once market demand has naturally crossed the upper bracket and converted 100% of those tokens into WETH.

➡️ *Zero red candles. Zero dump risk. 100% organic transparent growth.*

You can verify these locks on-chain via the /contracts menu!`;
    ctx.reply(text, { parse_mode: 'Markdown' });
});

bot.command('tickets', async (ctx) => {
    if (!nftContract) {
        return ctx.reply(
            "🎟️ *NFT Tickets & P2P Marketplace (Pre-Launch)*\n\n" +
            "The NFT tickets contract is *not yet live onchain*. It will be activated at the exact moment of launch!\n\n" +
            "🌟 *How it works once live:*\n" +
            "• Every trade ≥ 0.10 WETH volume automatically mints a verifiable onchain NFT ticket (boosted by staking multiplier).\n" +
            "• **Free Staking Tickets (Hybrid Claim)**: Up to 10 free tickets claimable every 4 days (1 ticket per 2M $IRL staked) — claim after 24h staked with **0h lock**, or Instant-Claim (<24h) with a **24h unstake lock**.\n" +
            "• **P2P Marketplace & 2.0% Lottery Tax**: Trade tickets on-chain (98% to seller, 2% Lottery Tax: 1% Daily + 1% Sunday for Daily+Weekly tickets, or 2% Sunday Mega-Jackpot for Weekly-only tickets).\n" +
            "• **Holding Caps**: 6 daily / 42 weekly (6×7) for non-stakers, scaling up to 10 daily / 70 weekly (10×7) for 2% stakers.\n" +
            "• Tickets participate in the Daily Draw (midnight) and Sunday Mega-Jackpot (Sunday evening) via OpenVRF!\n\n" +
            "🔔 *Stay connected to get early tickets at launch!* 🏹",
            { parse_mode: 'Markdown' }
        );
    }
    try {
        const total = await nftContract.totalTicketsMinted();
        ctx.reply(`🎟️ Total Tickets Minted: *${total.toString()} tickets* in play!`, { parse_mode: 'Markdown' });
    } catch (error) {
        console.error(error);
        ctx.reply("❌ Unable to read contract data.");
    }
});

bot.command('pot', async (ctx) => {
    if (!hookContract) {
        return ctx.reply(
            `💰 *Internet Robinhood Lottery Prize Pots (Pre-Launch)* 💰\n\n` +
            `⏳ *Status*: Contracts are *not yet live onchain*. Prize pots will start accumulating natively in ETH as soon as liquidity is seeded via Programmable.market!\n\n` +
            `⚡ *Programmable 0.30% Fee*: 50% (0.15%) Auto-burned on every swap + 50% (0.15%) Treasury\n` +
            `🏆 *Daily Lottery Pot*: 50% of the lottery tax (1.875% Boost ➔ 0.625% Standard via OpenVRF)\n` +
            `🌟 *Sunday Mega-Jackpot*: 50% of the lottery tax (1.875% Boost ➔ 0.625% Standard drawn every Sunday)\n` +
            `⏱️ *Hourly Redistribution*: 3.75% Boost ➔ 1.25% Standard (35% Top 10 / 35% Cashback / 30% Stakers Real Yield)\n` +
            `🔥 *Double Deflation*: 0.60% of every swap permanently burned (0.15% Programmable + 0.45% Hourly V4 Buyback & Burn)!\n\n` +
            `🔔 *Stay connected in the group to catch the launch countdown and first pot drawings!* 🏹`,
            { parse_mode: 'Markdown' }
        );
    }
    try {
        const dailyPot = await hookContract.dailyLotteryPot();
        const sundayPot = await hookContract.sundayMegaPot();
        const rewardPot = await hookContract.hourlyRewardPot();
        const buybackPot = await hookContract.buybackPot();
        
        const dailyEth = parseFloat(ethers.formatEther(dailyPot)).toFixed(4);
        const sundayEth = parseFloat(ethers.formatEther(sundayPot)).toFixed(4);
        const rewardEth = parseFloat(ethers.formatEther(rewardPot)).toFixed(4);
        const buybackEth = parseFloat(ethers.formatEther(buybackPot)).toFixed(4);
        
        ctx.reply(`💰 *Current Ecosystem Pots* 💰\n\n🏆 Today's Daily Lottery: ${dailyEth} ETH\n🌟 Sunday Mega-Jackpot: ${sundayEth} ETH\n⏱️ Hourly Trader Pool: ${rewardEth} ETH\n🔥 Buyback & Burn Reserve: ${buybackEth} ETH`, { parse_mode: 'Markdown' });
    } catch (error) {
        console.error(error);
        ctx.reply("❌ Unable to read contract data.");
    }
});

// --- Event Listeners ---

async function setupListeners() {
    if (!hookContract) {
        console.log("Hook contract address not configured yet. Event listeners disabled until deployment.");
        return;
    }
    console.log("Listening for Smart Contract events...");

    hookContract.on("LotteryWinnerDrawn", async (winner, tokenId, prize, event) => {
        const prizeEth = parseFloat(ethers.formatEther(prize)).toFixed(4);
        const txHash = event.log.transactionHash;
        
        const message = `🎉 *DAILY LOTTERY WINNER!* 🎉\n\nTicket #${tokenId.toString()} was drawn by OpenVRF!\n\n👤 Winner: \`${winner}\`\n💸 Prize: *${prizeEth} ETH* transferred instantly!\n\nCongratulations! 🏹`;
        
        if (CHANNEL_ID) {
            try {
                const msg = await bot.telegram.sendMessage(CHANNEL_ID, message, { 
                    parse_mode: 'Markdown',
                    ...Markup.inlineKeyboard([
                        Markup.button.url('🔍 View Transaction on Robinhood Etherscan', `${EXPLORER_URL}/tx/${txHash}`)
                    ])
                });
                await bot.telegram.pinChatMessage(CHANNEL_ID, msg.message_id);
            } catch (error) {
                console.error("Error sending or pinning message:", error);
            }
        }
    });

    hookContract.on("SundayMegaJackpotDrawn", async (winner, tokenId, prize, event) => {
        const prizeEth = parseFloat(ethers.formatEther(prize)).toFixed(4);
        const txHash = event.log.transactionHash;
        
        const message = `🌟 *SUNDAY MEGA-JACKPOT WINNER!* 🌟\n\nTicket #${tokenId.toString()} won the massive weekly pot!\n\n👤 Winner: \`${winner}\`\n💸 Prize: *${prizeEth} ETH* transferred instantly!\n\nWhat a weekend! 🏹`;
        
        if (CHANNEL_ID) {
            try {
                const msg = await bot.telegram.sendMessage(CHANNEL_ID, message, { 
                    parse_mode: 'Markdown',
                    ...Markup.inlineKeyboard([
                        Markup.button.url('🔍 View Transaction on Robinhood Etherscan', `${EXPLORER_URL}/tx/${txHash}`)
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
        const message = `⏱️ *HOURLY REWARDS DISTRIBUTED* ⏱️\n\nThe hourly pot has just been distributed to Top 10 traders, active swappers, and stakers!\n\nTrade or stake $IRL to participate in the next round! 🏹`;
        
        if (CHANNEL_ID) {
            bot.telegram.sendMessage(CHANNEL_ID, message, { 
                parse_mode: 'Markdown',
                ...Markup.inlineKeyboard([
                    Markup.button.url('🔍 View Distribution on Robinhood Etherscan', `${EXPLORER_URL}/tx/${txHash}`)
                ])
            }).catch(console.error);
        }
    });
}

bot.launch().then(() => {
    console.log("Telegram Bot successfully started!");
    
    bot.telegram.setMyCommands([
        { command: 'about', description: 'Learn about the Internet Robinhood Lottery project' },
        { command: 'tokenomics', description: 'View the taxes and pot distributions' },
        { command: 'contracts', description: 'View smart contract status & addresses' },
        { command: 'launch', description: 'Check official launch status & roadmap' },
        { command: 'socials', description: 'Official X/Twitter and Telegram links' },
        { command: 'security', description: 'Learn about our rug-proof LP architecture' },
        { command: 'tickets', description: 'View the number of lottery tickets in play' },
        { command: 'stake', description: 'Learn how to stake and earn ETH Real Yield' },
        { command: 'pot', description: 'View current sizes of all prize pots' }
    ]).catch(console.error);

    setupListeners();
}).catch(console.error);

process.once('SIGINT', () => bot.stop('SIGINT'));
process.once('SIGTERM', () => bot.stop('SIGTERM'));
