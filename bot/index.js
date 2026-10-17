const { Telegraf, Markup } = require('telegraf');
const { ethers } = require('ethers');
const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '.env'), override: true });

const bot = new Telegraf(process.env.BOT_TOKEN);
const RPC_URL = process.env.RPC_URL || "https://rpc.mainnet.chain.robinhood.com";
const provider = new ethers.JsonRpcProvider(RPC_URL, 4663, { staticNetwork: true });
provider.pollingInterval = 30000;
provider.on('error', (err) => console.error('RPC Provider error:', err));
const { createVrfRelayer } = require('./vrf-relayer');
const { createRewardTracker } = require('./reward-tracker');
const { sweepRouters, sweepSingleContract, scanAndRegisterContractTicketHolders } = require('./router-sweeper');
const { TraderLeaderboardTracker } = require('./trader-leaderboard');
const { ReferralAndEvEngine } = require('./referral-tracker');
const fs = require('fs');
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function waitForReceipt(prov, txHash, maxAttempts = 30) {
    for (let i = 0; i < maxAttempts; i++) {
        await sleep(3500);
        try {
            const r = await prov.getTransactionReceipt(txHash);
            if (r && r.blockNumber) return r;
        } catch (_) {}
    }
    throw new Error(`Timeout waiting for receipt of ${txHash}`);
}

// Official Deterministic CREATE2 Contract Addresses (Robinhood Chain 4663)
const TOKEN_ADDRESS = process.env.TOKEN_ADDRESS || "0xf7a2F5554C57C216F1831AA5C8ed3C46727eFE2B";
const HOOK_ADDRESS = process.env.HOOK_ADDRESS || "0xAb64c6Eb29a6bb8488cb1fcAB1ca11C5e28bC0cc";
const NFT_ADDRESS = process.env.NFT_ADDRESS || "0x837170cDdED801F491855405CbcfDA1211d812D7";
const STAKING_ADDRESS = process.env.STAKING_ADDRESS || "0x15958AC04ABA8D58C21BfD2760315A6a7D9E395d";
const MARKETING_VAULT_ADDRESS = process.env.MARKETING_VAULT_ADDRESS || "0xC463C57029A5F18f3A6B080AE7ef4e9B3A4F0073";
const OPENVRF_ADDRESS = process.env.OPENVRF_ADDRESS || "0x001d6D0934d1abca6Da8F2FE82b2829E60cBeb0f";
const POOL_ID = process.env.POOL_ID || "0x1848c9b63c7733c421b2db31bcb606ad75d505d281f7377dc170b082dbe989cb";

// Explorer & DEX URLs
const EXPLORER_URL = process.env.EXPLORER_URL || "https://robinhoodchain.blockscout.com";
const DEXSCREENER_URL = `https://dexscreener.com/robinhood/${POOL_ID}`;
const PROGRAMMABLE_URL = `https://programmable.market/token/${TOKEN_ADDRESS}?chain=4663`;

// Simple ABIs
const hookAbi = [
  "function lotteryPot() view returns (uint256)",
  "function dailyLotteryPot() view returns (uint256)",
  "function sundayMegaPot() view returns (uint256)",
  "function dailyPotByDay(uint256) view returns (uint256)",
  "function weeklyPotByWeek(uint256) view returns (uint256)",
  "function hourlyRewardPot() view returns (uint256)",
  "function buybackPot() view returns (uint256)",
  "function lastBuybackHour() view returns (uint256)",
  "function dayStartTicketId(uint256) view returns (uint256)",
  "function dayEndTicketId(uint256) view returns (uint256)",
  "function weekStartTicketId(uint256) view returns (uint256)",
  "function weekEndTicketId(uint256) view returns (uint256)",
  "function receiveMarketplaceTax(uint256 tokenId) external payable",
  "function executeBuybackAndBurn() external",
  "function checkUpkeep(bytes) view returns (bool upkeepNeeded, bytes performData)",
  "function performUpkeep(bytes) external",
  "event LotteryWinnerDrawn(address indexed winner, uint256 tokenId, uint256 prize)",
  "event SundayMegaJackpotDrawn(address indexed winner, uint256 tokenId, uint256 prize)",
  "event HourlyRewardsDistributed(uint256 currentHour, uint256 totalPotDistributed)",
  "event BuybackAndBurnExecuted(uint256 ethAmount)",
  "function userVolumePerHour(uint256, address) view returns (uint256)",
  "function queueIndex() view returns (uint256)",
  "function queueLength() view returns (uint256)",
  "event UnclaimedRewardRecorded(address indexed recipient, uint256 amount)",
  "event UserRewarded(address indexed user, uint256 amount)",
  "function distributingHourId() view returns (uint256)",
  "function getTopTraders(uint256 hourId) view returns (address[])"
];

const tokenAbi = [
  "function balanceOf(address) view returns (uint256)",
  "event Transfer(address indexed from, address indexed to, uint256 value)"
];

const nftAbi = [
  "function totalTicketsMinted() view returns (uint256)",
  "function ownerOf(uint256) view returns (address)"
];

const DEAD_ADDRESS = "0x000000000000000000000000000000000000dEaD";
const isHookValid = ethers.isAddress(HOOK_ADDRESS);
const isNftValid = ethers.isAddress(NFT_ADDRESS);
const isTokenValid = ethers.isAddress(TOKEN_ADDRESS);

const hookContract = isHookValid ? new ethers.Contract(HOOK_ADDRESS, hookAbi, provider) : null;
const nftContract = isNftValid ? new ethers.Contract(NFT_ADDRESS, nftAbi, provider) : null;
const tokenContract = isTokenValid ? new ethers.Contract(TOKEN_ADDRESS, tokenAbi, provider) : null;
const rewardTracker = isHookValid ? createRewardTracker({ provider, hookAddress: HOOK_ADDRESS, chunk: 35000 }) : null;
const WEB_DIST_PATH = fs.existsSync('/home/ubuntu/lottery-robinhood/dapp_dist')
    ? '/home/ubuntu/lottery-robinhood/dapp_dist'
    : path.join(__dirname, '../dapp/public');
const referralEngine = new ReferralAndEvEngine({ webDistPath: WEB_DIST_PATH });
const leaderboardTracker = isHookValid ? new TraderLeaderboardTracker({
    provider,
    devWalletAddress: process.env.DEV_WALLET_ADDRESS || "0xfABeb55321cc90323cC6207902B2a2936B95ed05",
    webDistPath: WEB_DIST_PATH,
    rewardTracker,
    referralEngine
}) : null;
const fmtEth = (wei) => parseFloat(ethers.formatEther(wei)).toFixed(4);

async function fetchLiveEvStats() {
    if (!hookContract || !nftContract) {
        return ReferralAndEvEngine.computeEvAlertStats();
    }
    const nowSec = Math.floor(Date.now() / 1000);
    const dayId = Math.floor(nowSec / 86400);
    const weekId = Math.floor((nowSec + 3 * 86400) / (7 * 86400));

    const [dailyPot, sundayPot, hourlyPot, dStart, dEnd, wStart, wEnd, totalMinted] = await Promise.all([
        hookContract.dailyPotByDay(dayId),
        hookContract.weeklyPotByWeek(weekId),
        hookContract.hourlyRewardPot(),
        hookContract.dayStartTicketId(dayId),
        hookContract.dayEndTicketId(dayId),
        hookContract.weekStartTicketId(weekId),
        hookContract.weekEndTicketId(weekId),
        nftContract.totalTicketsMinted()
    ]);

    let dailyTicketsInPlay = 0;
    if (dEnd >= dStart && dStart > 0n) {
        dailyTicketsInPlay = Number(dEnd - dStart + 1n);
    } else if (dStart > 0n && totalMinted >= dStart) {
        dailyTicketsInPlay = Number(totalMinted - dStart + 1n);
    }

    let sundayTicketsInPlay = 0;
    if (wEnd >= wStart && wStart > 0n) {
        sundayTicketsInPlay = Number(wEnd - wStart + 1n);
    } else if (wStart > 0n && totalMinted >= wStart) {
        sundayTicketsInPlay = Number(totalMinted - wStart + 1n);
    } else {
        sundayTicketsInPlay = Number(totalMinted);
    }

    return ReferralAndEvEngine.computeEvAlertStats({
        dailyTicketsInPlay,
        sundayTicketsInPlay,
        dailyPotEth: ethers.formatEther(dailyPot),
        sundayPotEth: ethers.formatEther(sundayPot),
        hourlyPotEth: ethers.formatEther(hourlyPot),
        dayStartTicketId: Number(dStart),
        dayEndTicketId: Number(dEnd)
    });
}

function ledgerText(s) {
    const totalRealTraders = s.toWallets + s.toContracts;
    return `🧾 *Where reward ETH went (on-chain ledger)*\n\n` +
        `✅ *Paid & Queued to Real Traders: ${fmtEth(totalRealTraders)} ETH*\n` +
        `   • _Direct wallets & random community casino drops_\n` +
        `   • _Router rewards reclaimed by Keeper & queued for 24h redistribution_\n\n` +
        `🔒 *Locked in Hook (Routers rejecting ETH / Burned): ${fmtEth(s.lockedTotal)} ETH*\n` +
        `   • _Non-payable routers (Axiom Bot & direct Uniswap UI)_\n\n` +
        `Locked ETH stays inside the Hook and is permanently out of circulation. Trade on [irlprotocol.xyz](https://irlprotocol.xyz) so rewards reach YOUR wallet directly! 🏹`;
}

let isDeployedCache = false;
async function isContractLive() {
  if (isDeployedCache) return true;
  try {
    const code = await provider.getCode(HOOK_ADDRESS);
    if (code && code !== "0x") {
      isDeployedCache = true;
      return true;
    }
  } catch (_) {}
  return false;
}

// Channel ID to announce events
const CHANNEL_ID = process.env.CHANNEL_ID;

// --- Bot Commands ---

bot.start((ctx) => {
    const text = `🏹 *Welcome to Internet Robinhood Lottery ($IRL)* 🏹\n\n` +
        `🟢 *STATUS: LIVE ON ROBINHOOD CHAIN (4663)!*\n` +
        `🪙 *Official CA*: \`${TOKEN_ADDRESS}\`\n` +
        `🪝 *V4 Hook*: \`${HOOK_ADDRESS}\`\n\n` +
        `🎲 *ON-CHAIN LOTTERIES & HOURLY ETH REWARDS:*\n` +
        `• *Daily 24h Jackpot (00:00 UTC)* & *Sunday Mega-Jackpot* powered by Drand OpenVRF!\n` +
        `• *Hourly ETH Stream*: 35% Top 10 Traders + 35% Active Swappers Cashback + 30% Staker Real Yield!\n` +
        `• ⚡ *Trade on the DApp* at [irlprotocol.xyz](https://irlprotocol.xyz) so your wallet receives 100% of your NFT Tickets (≥ 0.10 ETH) & hourly rewards!\n\n` +
        `🌐 *OFFICIAL LINKS:*\n` +
        `• 🖥️ *DApp Sanctuary*: [irlprotocol.xyz](https://irlprotocol.xyz)\n` +
        `• 📈 *DexScreener*: [Live V4 Chart](${DEXSCREENER_URL})\n` +
        `• ⚡ *Programmable*: [Trade $IRL](${PROGRAMMABLE_URL})\n` +
        `• 𝕏 *(Twitter)*: [x.com/IRL_Protocol](https://x.com/IRL_Protocol)\n` +
        `• ✈️ *Telegram*: [t.me/InternetRobinhoodLottery](https://t.me/InternetRobinhoodLottery)\n\n` +
        `Explore the commands below:\n` +
        `/odds - Live win probabilities & +EV lottery calculator\n` +
        `/referral - Create custom referral link & earn 0.25% ETH\n` +
        `/guild - Sherwood Co-Staking Guild for small holders (<1M $IRL)\n` +
        `/jackpot - How to enter & win daily and weekly jackpots\n` +
        `/pot - Live prize pots (Daily, Sunday Mega-Jackpot, Hourly, Burn)\n` +
        `/ledger - Where reward ETH went (Wallets, Bots, Locked)\n` +
        `/tickets - Total NFT Lottery Tickets in play\n` +
        `/contracts - Verified on-chain smart contract addresses\n` +
        `/tokenomics - 4.0% Standard Tax breakdown\n` +
        `/stake - Staking Real Yield in native ETH\n` +
        `/security - 90% permanent locked LP & Single-Sided LP Vault\n` +
        `/about - Protocol thesis & V4 Hook mechanics`;
    ctx.reply(text, { 
        parse_mode: 'Markdown',
        ...Markup.inlineKeyboard([
            [Markup.button.url('🖥️ Open DApp (irlprotocol.xyz)', 'https://irlprotocol.xyz')],
            [Markup.button.url('📈 DexScreener Chart', DEXSCREENER_URL), Markup.button.url('⚡ Programmable', PROGRAMMABLE_URL)],
            [Markup.button.url('Follow on 𝕏 (@IRL_Protocol)', 'https://x.com/IRL_Protocol')]
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
            `🟢 *$IRL IS LIVE ON ROBINHOOD CHAIN!*\n` +
            `🪙 *CA*: \`${TOKEN_ADDRESS}\`\n\n` +
            `🎲 *24h Daily Jackpot (00:00 UTC), Sunday Mega-Jackpot & Hourly ETH Rewards!*\n` +
            `⚡ Trade on the DApp to mint NFT Lottery Tickets directly to your wallet!\n\n` +
            `🖥️ *DApp*: [irlprotocol.xyz](https://irlprotocol.xyz/)\n` +
            `📈 *Chart*: [DexScreener](${DEXSCREENER_URL})\n\n` +
            `Type /pot, /ledger, /tickets, or /contracts to inspect the live on-chain pots! 🏹`,
            { parse_mode: 'Markdown', disable_web_page_preview: true }
        ).catch(console.error);
    }
});

bot.command('about', (ctx) => {
    const text = `🏹 *About Internet Robinhood Lottery ($IRL)* 🏹

We steal from the whales to give back to the community! $IRL is an innovative DeFi ecosystem launching via **Programmable.market** on the Robinhood Chain, utilizing cutting-edge **Uniswap V4 Hooks** to create a fair, gamified, and hyper-rewarding environment.

⚡ *4.0% Standard Tax Architecture:*
Swaps carry a clean **4.0% Standard Tax** (\`1.25%\` Hourly Pot + \`1.25%\` Lottery Pots + \`1.00%\` Protocol Pot + \`0.20%\` Buyback & Burn + \`0.30%\` Programmable.market platform fee):

1️⃣ **0.30% Immutable Programmable.market Platform Fee**
- 0.30% (30 bps) routed immutably to Programmable.market once on every buy, sell, and internal buyback!

2️⃣ **Epoch-Isolated Daily Lottery & Sunday Mega-Jackpot (1.25% via OpenVRF)**
Trade $IRL to earn NFT Tickets (0.10 WETH threshold per ticket, boosted up to +50% by staking). 
- Every midnight, a winner is drawn strictly among tickets minted *that day* (\`dailyPotByDay[dayId]\`).
- Every Sunday evening, the **Sunday Mega-Jackpot** is drawn among all tickets minted Monday through Sunday (\`weeklyPotByWeek[weekId]\`)!

3️⃣ **Hourly Rewards (1.25%: 35% Top 10 / 35% Cashback / 30% Real Yield Staking)**
- **35% Top 10 of the Hour**: Distributed strictly among the Top 10 traders of the hour, boosted by staking volume multipliers (up to +50% at 2% staked: e.g. 0.05 WETH traded = 0.075 WETH score!).
- **35% Hourly Trader Cashback**: Distributed once per hour to all active traders of that hour (0.4375% ETH cashback).
- **30% Stakers Real Yield**: Streamed as native ETH dividends across eligible $IRL stakers ranked from 0.1% (1M $IRL) to 2.0% (20M $IRL max tier)!

4️⃣ **Protocol Solvency & Hourly Batched Deflation (1.20%)**
- **1.00% Standard** for OpenVRF gas, automated keep-alives, and marketing (\`protocolPot\`).
- **0.20% Standard** dedicated to **Hourly Batched $IRL Buyback & Burn** (\`buybackPot\` swapped once per hour on V4 to \`0xdead\`)!

5️⃣ **Automated Anti-Whale Protection (< $50k MC)**
Max transaction (1%) and max wallet (2%) dynamically protect the pool at launch and auto-disable at the fixed $50k Market Cap cutoff.

*Zero Sell Pressure*: All ecosystem taxes are collected natively in WETH directly from the liquidity pool (Swap-and-Liquify via V4). The chart never dumps to fund rewards!

Use /tokenomics to see the exact tax breakdown, or /contracts to verify our code.`;
    ctx.reply(text, { parse_mode: 'Markdown' });
});

bot.command('tokenomics', (ctx) => {
    const text = `📊 *$IRL Tokenomics & Taxes* 📊

All taxes are collected natively from the Uniswap V4 Hook:
• ⚡ **4.0% Standard Tax:** \`1.25%\` Hourly + \`1.25%\` Lottery + \`1.00%\` Protocol + \`0.20%\` Buyback & Burn + \`0.30%\` Programmable.

⚡ *0.30% Programmable.market Platform Fee (Immutable)*:
  • Hardcoded 0.30% (30 bps) once on every buy, sell, and internal buyback to \`0xD88539d3c4C460136a733A3Fd60cf6BF269079da\`.

🏆 *1.25% Epoch-Isolated Dual Lottery Pot*:
  • 50% for the **Daily Lottery** (0.625% Standard via OpenVRF).
  • 50% for the **Sunday Mega-Jackpot** (0.625% Standard).

⏱️ *1.25% Hourly Redistribution (35/35/30)*:
  • 35% for the **Top 10 Volume Traders** of the hour (0.4375% Standard, boosted up to +50% by staking).
  • 35% for **All Active Traders** of the hour (0.4375% ETH cashback distributed once per hour).
  • 30% for **Eligible Stakers (0.1% to 2.0% tiers)** streamed as native ETH Real Yield (0.375% Standard)!

⚙️ *1.20% Protocol & Deflation*:
  • **1.00%** for OpenVRF gas, automated keep-alives, and marketing (\`protocolPot\`).
  • **0.20%** dedicated to **Hourly Batched Buyback & Burn** (accumulated in \`buybackPot\` and swapped WETH -> $IRL to \`0xdead\` once per hour)!

*Zero Chart Sell Pressure*: Taxes are intercepted natively by the V4 Hook, so the $IRL chart never dumps to fund rewards!`;
    ctx.reply(text, { parse_mode: 'Markdown' });
});

bot.command('contracts', async (ctx) => {
    const live = await isContractLive();
    if (!live) {
        const text = `📜 *Official Smart Contracts (Status: Pre-Launch)* 📜\n\n` +
            `⚠️ *Contracts are NOT yet live on Robinhood Chain!*\n\n` +
            `The contracts are finalized, audited, and approved for deterministic CREATE2 deployment:\n` +
            `• 🪙 *$IRL Token*: Audited & Deterministic (Revealed at Launch)\n` +
            `• 🪝 *Uniswap V4 Hook*: Audited & Deterministic (0x...C0cc)\n` +
            `• 🎟️ *NFT Tickets & Marketplace*: ERC-721 Provably Fair Tickets\n` +
            `• 🏦 *Real Yield Staking Vault*: MasterChef ETH Dividend Model\n` +
            `• 🛡️ *90% Locked LP & Marketing Vault*: 90% Permanent Locked LP + 10% Conditional Upper Bracket\n\n` +
            `🔔 *Stay connected in this group!* The verified on-chain addresses will appear here automatically the exact second the atomic launch transaction is signed. *Do NOT buy any fake token before our official announcement.*`;
        return ctx.reply(text, { parse_mode: 'Markdown' });
    }
    const text = `📜 *Official Smart Contracts (LIVE on Robinhood Chain)* 📜\n\n` +
        `Verify our contracts directly on Robinhood Blockscout:\n\n` +
        `🪙 *$IRL Token (CA)*: \`${TOKEN_ADDRESS}\`\n` +
        `🪝 *Uniswap V4 Hook*: \`${HOOK_ADDRESS}\`\n` +
        `🎟️ *NFT Tickets & Marketplace*: \`${NFT_ADDRESS}\`\n` +
        `🏦 *Real Yield Staking Vault*: \`${STAKING_ADDRESS}\`\n` +
        `🛡️ *LP & Marketing Vault (90% Locked)*: \`${MARKETING_VAULT_ADDRESS}\`\n` +
        `🎲 *OpenVRF Coordinator*: \`${OPENVRF_ADDRESS}\`\n\n` +
        `_Make sure you only interact with these official addresses!_`;
    ctx.reply(text, {
        parse_mode: 'Markdown',
        ...Markup.inlineKeyboard([
            [Markup.button.url('📈 DexScreener Chart', DEXSCREENER_URL), Markup.button.url('⚡ Trade on Programmable', PROGRAMMABLE_URL)],
            [Markup.button.url('🔍 View $IRL on Blockscout', `${EXPLORER_URL}/address/${TOKEN_ADDRESS}`)]
        ])
    });
});

bot.command('launch', async (ctx) => {
    const live = await isContractLive();
    const statusLine = live
        ? `4️⃣ **Current Status**: 🟢 *LIVE ON ROBINHOOD CHAIN!*`
        : `4️⃣ **Current Status**: *Pre-Launch Phase (Approved by Programmable.market)*.`;
    const text = `🚀 *$IRL Launch Status & Roadmap* 🚀\n\n` +
        `1️⃣ **Contract Code**: 100% complete, gas-optimized, and security audited.\n` +
        `2️⃣ **Network**: Robinhood Chain (Arbitrum L2, Chain ID 4663).\n` +
        `3️⃣ **Fair Launch**: 90% of total supply (900M $IRL) is permanently locked forever in PoolManager via IRLMarketingVault, with 10% (100M $IRL) conditionally locked in the Single-Sided Upper Marketing Bracket.\n` +
        `${statusLine}\n\n` +
        `📢 *Official Links:*\n` +
        `• 𝕏: [x.com/IRL_Protocol](https://x.com/IRL_Protocol)\n` +
        `• Telegram: [t.me/InternetRobinhoodLottery](https://t.me/InternetRobinhoodLottery)\n` +
        (live ? `• DexScreener: [View Live V4 Pool](${DEXSCREENER_URL})\n` : `\nTurn on notifications so you don't miss it! 🏹`);
    ctx.reply(text, { 
        parse_mode: 'Markdown',
        ...Markup.inlineKeyboard([
            [Markup.button.url('Follow on 𝕏 (@IRL_Protocol)', 'https://x.com/IRL_Protocol')],
            ...(live ? [[Markup.button.url('📈 Live Chart (DexScreener)', DEXSCREENER_URL)]] : [])
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
    const live = await isContractLive();
    if (!nftContract || !live) {
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

bot.command(['jackpot', 'howtoplay', 'rules'], (ctx) => {
    const text = `🏹 *HOW TO ENTER & WIN THE $IRL JACKPOTS* 🏹\n\n` +
        `You do *NOT* need to hold ETH to win! All you need is an on-chain NFT Lottery Ticket in your wallet.\n\n` +
        `When your ticket is drawn by OpenVRF, the jackpot prize in native ETH is sent directly to your wallet automatically! 💰\n\n` +
        `There are 3 ways to get your Lottery Tickets:\n\n` +
        `1️⃣ *METHOD 1: TRADE ON THE DAPP (Instant Mint)*\n` +
        `• Swap $IRL on our official DApp: [irlprotocol.xyz](https://irlprotocol.xyz)\n` +
        `• Every *0.10 ETH* of volume automatically mints an official NFT Lottery Ticket directly to your wallet!\n` +
        `• ⚠️ *IMPORTANT*: Always use the DApp ([irlprotocol.xyz](https://irlprotocol.xyz)) instead of external aggregators so your wallet address is verified by the V4 Hook to receive both your NFT tickets AND your 35% hourly ETH cashback!\n\n` +
        `2️⃣ *METHOD 2: BUY ON P2P MARKETPLACE (Secondary Market)*\n` +
        `• Buy or sell existing NFT tickets directly from other community members on our decentralized P2P Marketplace at [irlprotocol.xyz](https://irlprotocol.xyz).\n` +
        `• Instant peer-to-peer settlement in native ETH — pick up tickets at floor price or trade your entry anytime!\n\n` +
        `3️⃣ *METHOD 3: STAKE $IRL (Free Tickets & Real Yield)*\n` +
        `• Stake your $IRL tokens in the Staking Sanctuary on [irlprotocol.xyz](https://irlprotocol.xyz)\n` +
        `• Stakers can claim *FREE bonus NFT tickets every 4 days* (up to 10 free tickets depending on your staking tier)!\n` +
        `• Plus, you earn passive Real Yield dividends streamed continuously in native ETH.\n\n` +
        `🎲 *THE JACKPOT DRAWS:*\n` +
        `• 🎯 *Daily 24h Jackpot*: Drawn every midnight (00:00 UTC) across all tickets minted that day.\n` +
        `• 🌟 *Sunday Mega-Jackpot*: Big weekend draw pooling tickets from Monday through Sunday!\n` +
        `• 🛡️ *100% Provably Fair*: All winners selected on-chain by Drand OpenVRF randomness.\n\n` +
        `👉 Check tickets in play: /tickets\n` +
        `👉 Check live prize pots: /pot\n` +
        `👉 Get tickets now: [irlprotocol.xyz](https://irlprotocol.xyz)`;

    ctx.reply(text, {
        parse_mode: 'Markdown',
        disable_web_page_preview: true,
        ...Markup.inlineKeyboard([
            [Markup.button.url('🖥️ Open DApp & Get Tickets', 'https://irlprotocol.xyz'), Markup.button.url('🎟️ P2P Ticket Market', 'https://irlprotocol.xyz')],
            [Markup.button.url('📈 DexScreener Chart', DEXSCREENER_URL)]
        ])
    }).catch(console.error);
});

bot.command('pot', async (ctx) => {
    const live = await isContractLive();
    if (!hookContract || !live) {
        return ctx.reply(
            `💰 *Internet Robinhood Lottery Prize Pots (Pre-Launch)* 💰\n\n` +
            `⏳ *Status*: Contracts are *not yet live onchain*. Prize pots will start accumulating natively in ETH as soon as liquidity is seeded via Programmable.market!\n\n` +
            `⚡ *Programmable 0.30% Fee*: 30 bps routed immutably to Programmable.market once per buy/sell/buyback\n` +
            `🏆 *Daily Lottery Pot*: 50% of the lottery tax (1.875% Boost ➔ 0.625% Standard via OpenVRF)\n` +
            `🌟 *Sunday Mega-Jackpot*: 50% of the lottery tax (1.875% Boost ➔ 0.625% Standard drawn every Sunday)\n` +
            `⏱️ *Hourly Redistribution*: 3.75% Boost ➔ 1.25% Standard (35% Top 10 / 35% Cashback / 30% Stakers Real Yield)\n` +
            `🔥 *Hourly V4 Buyback & Burn*: 0.50% Boost ➔ 0.20% Standard swapped WETH -> $IRL to 0xdead every hour!\n\n` +
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
        
        ctx.reply(`💰 *Current Ecosystem Pots* 💰\n\n🏆 Today's Daily Lottery: ${dailyEth} ETH\n🌟 Sunday Mega-Jackpot: ${sundayEth} ETH\n⏱️ Hourly Trader Pool: ${rewardEth} ETH\n🔥 Buyback & Burn Reserve: ${buybackEth} ETH\n\n🧾 See where rewards went: /ledger`, { parse_mode: 'Markdown' });
    } catch (error) {
        console.error(error);
        ctx.reply("❌ Unable to read contract data.");
    }
});

bot.command('ledger', async (ctx) => {
    if (!rewardTracker) return ctx.reply("Ledger not available yet.");
    try {
        const s = await rewardTracker.sync();
        ctx.reply(ledgerText(s), { parse_mode: 'Markdown' });
    } catch (error) {
        console.error(error);
        ctx.reply("❌ Unable to read the reward ledger right now.");
    }
});

bot.command(['leaderboard', 'top'], async (ctx) => {
    if (!leaderboardTracker) return ctx.reply("Leaderboard is not available yet.");
    try {
        await leaderboardTracker.syncLogs();
        const lb = leaderboardTracker.buildLeaderboard();
        if (!lb || (lb.currentHourTop10.length === 0 && lb.daily24hLeaderboard.length === 0)) {
            return ctx.reply("📊 Leaderboard is syncing with Robinhood Chain... Please try again in a few moments!");
        }

        const hourlyLines = lb.currentHourTop10.slice(0, 10).map((t) => 
            `*#${t.rank}* \`${t.address}\` • *${t.volumeEth} ETH* (${t.sharePercent}) ➔ ~*${t.estHourlyShareEth} ETH*`
        ).join('\n') || '_No swaps recorded in this hourly cycle yet._';

        const dailyLines = lb.daily24hLeaderboard.slice(0, 5).map((t) => 
            `*#${t.rank}* \`${t.address}\` • *${t.volumeEth} ETH* (${t.sharePercent}) ➔ ~*${t.pendingRedistributionEth} ETH*`
        ).join('\n');

        const message = 
            `🏆 *IRL Protocol — Real Human Trader Leaderboard* 🏹\n\n` +
            `🛡️ _All third-party aggregator & router contracts are automatically unmasked to credit the genuine wallets behind every trade!_\n\n` +
            `⏱️ *CURRENT HOUR TOP TRADERS (${lb.currentHourPotEth || '0.0000'} ETH Pot):*\n` +
            `👥 Active Hourly Traders: *${lb.totalHourTraders}* | Volume: *${lb.totalHourVolumeEth} ETH*\n` +
            hourlyLines +
            `\n\n💰 *24H REDISTRIBUTION QUEUE (${lb.sweptPotEth} ETH Pot):*\n` +
            dailyLines +
            `\n\n⚡ *Protocol Update:* Swept router fees are now distributed *hour-by-hour* by the Dev Wallet directly to the traders who used each router!\n` +
            `🌐 *Full Live Leaderboard:* https://irlprotocol.xyz`;

        ctx.reply(message, {
            parse_mode: 'Markdown',
            disable_web_page_preview: true,
            ...Markup.inlineKeyboard([
                [Markup.button.url('🖥️ Open DApp Leaderboard', 'https://irlprotocol.xyz')]
            ])
        });
    } catch (err) {
        console.error(err);
        ctx.reply("❌ Unable to load leaderboard right now.");
    }
});

bot.command(['odds', 'ev', 'probability'], async (ctx) => {
    try {
        const stats = await fetchLiveEvStats();
        const message = ReferralAndEvEngine.buildTelegramEvAlertMessage(stats);
        ctx.reply(message, {
            parse_mode: 'Markdown',
            disable_web_page_preview: true,
            ...Markup.inlineKeyboard([
                [Markup.button.url(`⚡ Mint 1 Ticket Now (${stats.oneTicketDailyOddsPct}% Win Odds)`, 'https://irlprotocol.xyz/?tab=trade')],
                [Markup.button.url('🎟️ P2P Ticket Market', 'https://irlprotocol.xyz/?tab=marketplace'), Markup.button.url('📈 DexScreener Chart', DEXSCREENER_URL)]
            ])
        });
    } catch (err) {
        console.error(err);
        ctx.reply("❌ Unable to calculate live lottery probabilities right now.");
    }
});

bot.command(['referral', 'ref', 'referrals'], (ctx) => {
    const snap = referralEngine.getPublicSnapshot();
    const topList = (snap.topReferrers || []).slice(0, 5).map((r, i) =>
        `*#${i + 1}* \`${r.displayHandle}\` • *${r.referredCount} trader(s)* • *${r.totalVolumeEth} ETH vol* ➔ *${r.totalEarnedEth} ETH earned*`
    ).join('\n') || '_No referrals recorded yet. Be the #1 Robinhood Referrer!_';

    const message =
        `🏹 *$IRL ROBINHOOD REFERRAL PROGRAM (CUSTOM LINKS)* 🏹\n\n` +
        `Invite traders to https://irlprotocol.xyz using your personalized referral link and earn *native ETH every hour*!\n\n` +
        `💎 *REFERRAL REWARDS & BONUSES:*\n` +
        `• 💰 *Referrer Earns*: *0.25% of all referred swap volume in native ETH* (25% of the Protocol Fee share streamed directly to your wallet)!\n` +
        `• ⚡ *Referee Bonus*: Your invited friends automatically get a *+10% Hourly Leaderboard Score Boost* on every trade!\n` +
        `• ✨ *Custom Link Handle*: Personalize your link on the DApp Referral Tab or right here on Telegram:\n` +
        `  👉 \`/setref <your-custom-code> <0xYourWallet>\`\n` +
        `  Example: \`/setref robinhood 0x1234...5678\` ➔ \`https://irlprotocol.xyz/?ref=robinhood\`\n\n` +
        `🏆 *TOP ROBINHOOD REFERRERS:*\n` +
        topList +
        `\n\n🔗 *Create your custom link on the DApp:* https://irlprotocol.xyz/?tab=referral`;

    ctx.reply(message, {
        parse_mode: 'Markdown',
        disable_web_page_preview: true,
        ...Markup.inlineKeyboard([
            [Markup.button.url('🔗 Open Referral Program Tab on DApp', 'https://irlprotocol.xyz/?tab=referral')]
        ])
    });
});

bot.command('setref', (ctx) => {
    const parts = (ctx.message?.text || '').trim().split(/\s+/);
    if (parts.length < 3) {
        return ctx.reply(
            `✨ *Customize Your Referral Link* ✨\n\n` +
            `Usage: \`/setref <custom-code> <0xYourWalletAddress>\`\n` +
            `Example: \`/setref sherwood-king 0xfABeb55321cc90323cC6207902B2a2936B95ed05\`\n\n` +
            `• Code must be 3–24 characters (\`a-z\`, \`0-9\`, \`-\`, \`_\`).`,
            { parse_mode: 'Markdown' }
        );
    }
    const rawAlias = parts[1];
    const walletAddr = parts[2];
    const res = referralEngine.registerCustomAlias(rawAlias, walletAddr);
    if (!res.ok) {
        return ctx.reply(`❌ *Referral Setup Error*: ${res.error}`, { parse_mode: 'Markdown' });
    }
    if (leaderboardTracker) {
        leaderboardTracker.buildLeaderboard();
    }
    ctx.reply(
        `✅ *Custom Referral Link Activated!* 🏹\n\n` +
        `• *Custom Handle*: \`@${res.alias}\`\n` +
        `• *Bound Wallet*: \`${res.wallet}\`\n` +
        `• *Your Personalized Link*:\n\`${res.referralUrl}\`\n\n` +
        `Share your link anywhere — every trader who swaps through it earns a *+10% Leaderboard Bonus* and streams *0.25% in native ETH* to your wallet!`,
        { parse_mode: 'Markdown', disable_web_page_preview: true }
    );
});

bot.command(['guild', 'costake'], (ctx) => {
    const text =
        `🏹 *THE SHERWOOD CO-STAKING GUILD (SMALL HOLDERS POOL)* 🏹\n\n` +
        `Hold less than *1,000,000 $IRL (0.1% supply)*? You can now earn native ETH Real Yield AND share Guild Lottery Jackpots with *ZERO minimum deposit*!\n\n` +
        `📍 *Live Guild Vault Contract*: \`0x7cAbcd316cC661b78c331b04A5EA929D5c97347c\`\n\n` +
        `⚙️ *HOW THE SHERWOOD GUILD VAULT WORKS:*\n` +
        `1️⃣ *Pool Together*: Small holders deposit any amount of $IRL (even 25,000 or 100,000 $IRL) into \`IRLSherwoodGuildVault.sol\`.\n` +
        `2️⃣ *30% Hourly ETH Real Yield*: Once the Guild reaches \`1,000,000 $IRL\` pooled, it unlocks the main \`IRLStaking\` Sanctuary stream and distributes 100% of harvested ETH pro-rata (\`accEthPerShare\`).\n` +
        `3️⃣ *Guild Staking Lottery Tickets*: The Guild contract claims free Staking NFT Lottery Tickets directly for the contract (\`claimGuildStakingTickets\`).\n` +
        `4️⃣ *Lottery Jackpot Sharing Rules (8h Daily / 1d Weekly)*:\n` +
        `   • 🎟️ *Daily Lottery Win*: Shared pro-rata among members who staked *≥ 8 hours* on the day of the valid ticket AND are *still staking at the 00:00 UTC draw*!\n` +
        `   • 🏆 *Sunday Mega-Jackpot Win*: Shared pro-rata among members who staked *≥ 1 day (24 hours)* on the week of the valid ticket AND are *still staking at the Sunday draw*!\n\n` +
        `🖥️ *Join the Sherwood Guild on the DApp:* https://irlprotocol.xyz`;

    ctx.reply(text, {
        parse_mode: 'Markdown',
        disable_web_page_preview: true,
        ...Markup.inlineKeyboard([
            [Markup.button.url('🏹 Open Sherwood Guild Vault', 'https://irlprotocol.xyz')]
        ])
    });
});

// --- Event Listeners & Automated Keeper ---

const announcedBurnTxs = new Set();

async function announceBuybackAndBurn(ethAmount, txHash) {
    if (!CHANNEL_ID || !txHash || announcedBurnTxs.has(txHash.toLowerCase())) return;
    announcedBurnTxs.add(txHash.toLowerCase());

    try {
        const ethSpent = parseFloat(ethers.formatEther(ethAmount)).toFixed(4);
        let irlBurnedTx = "0";
        let totalBurnedIrl = "0";

        try {
            const receipt = await provider.getTransactionReceipt(txHash);
            if (receipt && tokenContract) {
                for (const log of receipt.logs) {
                    if (log.address.toLowerCase() === TOKEN_ADDRESS.toLowerCase()) {
                        try {
                            const parsed = tokenContract.interface.parseLog(log);
                            if (
                                parsed &&
                                parsed.name === "Transfer" &&
                                parsed.args.to.toLowerCase() === DEAD_ADDRESS.toLowerCase()
                            ) {
                                irlBurnedTx = Math.floor(parseFloat(ethers.formatEther(parsed.args.value))).toLocaleString('en-US');
                            }
                        } catch (_) {}
                    }
                }
            }
            if (tokenContract) {
                const deadBal = await tokenContract.balanceOf(DEAD_ADDRESS);
                totalBurnedIrl = Math.floor(parseFloat(ethers.formatEther(deadBal))).toLocaleString('en-US');
            }
        } catch (innerErr) {
            console.error("Error parsing burn receipt:", innerErr.message);
        }

        const message =
            `🔥🔥 *$IRL UNISWAP V4 BUYBACK & BURN EXECUTED!* 🔥🔥\n\n` +
            `The Uniswap V4 Hook just executed an automated market buy on the pool (printing a green candle) and permanently destroyed the purchased tokens!\n\n` +
            `💰 *ETH Market Buy*: *${ethSpent} ETH*\n` +
            `🔥 *$IRL Burned Now*: *${irlBurnedTx} $IRL*\n` +
            `💀 *Total Burned Forever*: *${totalBurnedIrl} $IRL*\n` +
            `⚱️ *Burn Address*: \`${DEAD_ADDRESS}\`\n` +
            `🔗 *TX Hash*: \`${txHash}\`\n\n` +
            `Zero contract token dumps — 100% native ETH buy pressure + permanent deflation every hour! 🏹🚀`;

        const msg = await bot.telegram.sendMessage(CHANNEL_ID, message, {
            parse_mode: 'Markdown',
            ...Markup.inlineKeyboard([
                [Markup.button.url('🔍 View Burn TX on Explorer', `${EXPLORER_URL}/tx/${txHash}`)],
                [Markup.button.url('📈 DexScreener Chart', DEXSCREENER_URL), Markup.button.url('🖥️ Open DApp', 'https://irlprotocol.xyz')]
            ])
        });
        await bot.telegram.pinChatMessage(CHANNEL_ID, msg.message_id).catch(() => {});
    } catch (err) {
        console.error("Failed to announce Buyback & Burn:", err);
    }
}

const processedDrawTxs = new Set([
    '0xf45b58db1e1e26ee14daebb5b0c750ee47c996099a9a0edeb9f4ecc77ae8f93e'.toLowerCase()
]);

async function announceDraw(title, winner, tokenId, prize, eventOrTxHash) {
    const txHash = typeof eventOrTxHash === 'string'
        ? eventOrTxHash
        : (eventOrTxHash && eventOrTxHash.log ? eventOrTxHash.log.transactionHash : (eventOrTxHash && eventOrTxHash.transactionHash ? eventOrTxHash.transactionHash : ''));

    if (txHash && processedDrawTxs.has(txHash.toLowerCase())) return;
    if (txHash) processedDrawTxs.add(txHash.toLowerCase());

    const prizeEth = fmtEth(prize);
    let outcome;
    try {
        const isContract = (await provider.getCode(winner)) !== '0x';
        if (!isContract) {
            outcome = `👤 *Winner*: \`${winner}\`\n💸 *Prize*: *${prizeEth} ETH* transferred instantly!\n\nCongratulations! 🏹`;
        } else {
            let locked = false;
            if (txHash) {
                try {
                    const receipt = await provider.getTransactionReceipt(txHash);
                    if (receipt && receipt.logs) {
                        const lockedTopic = hookContract.interface.getEvent('UnclaimedRewardRecorded').topicHash;
                        locked = receipt.logs.some((l) => l.topics[0] === lockedTopic);
                    }
                } catch (_) {}
            }
            outcome = `🤖 Winning ticket is held by a router / aggregator contract: \`${winner}\`\n` +
                (locked
                    ? `🔒 The contract rejects ETH, so the *${prizeEth} ETH* prize stays locked inside the Hook (out of circulation).`
                    : `⚠️ The *${prizeEth} ETH* prize went to that contract, not to a community member.`) +
                `\n\nThis is exactly why trading on irlprotocol.xyz matters: tickets minted there go to YOUR wallet. 🏹`;
        }
    } catch (_) {
        outcome = `👤 *Winner*: \`${winner}\`\n💸 *Prize*: *${prizeEth} ETH*`;
    }

    const message = `${title}\n\n🎫 *Ticket #${tokenId.toString()}* was drawn by OpenVRF (provably fair, Drand).\n\n${outcome}`;
    if (!CHANNEL_ID) return;
    try {
        const buttons = [];
        if (txHash) {
            buttons.push([Markup.button.url('🔍 View Draw Transaction', `${EXPLORER_URL}/tx/${txHash}`)]);
        }
        buttons.push([Markup.button.url('🌐 Trade on DApp to Own Your Tickets', 'https://irlprotocol.xyz')]);

        const msg = await bot.telegram.sendMessage(CHANNEL_ID, message, {
            parse_mode: 'Markdown',
            disable_web_page_preview: true,
            ...Markup.inlineKeyboard(buttons)
        });
        await bot.telegram.pinChatMessage(CHANNEL_ID, msg.message_id).catch(() => {});
        console.log(`[AnnounceDraw] Successfully broadcasted ${title} for ticket #${tokenId.toString()} (tx: ${txHash})`);
    } catch (error) {
        console.error("[AnnounceDraw] Error sending draw message:", error.message);
    }
}

async function setupListeners() {
    if (!hookContract) {
        console.log("Hook contract address not configured yet. Event listeners disabled until deployment.");
        return;
    }
    console.log("Listening for Smart Contract events...");
    if (rewardTracker) {
        rewardTracker.sync().then(() => {
            console.log("[Ledger] Initial sync complete.");
            if (leaderboardTracker) leaderboardTracker.buildLeaderboard();
        }).catch((err) => console.error("[Ledger] Initial sync failed:", err.message));
        setInterval(() => {
            rewardTracker.sync().then(() => {
                if (leaderboardTracker) leaderboardTracker.buildLeaderboard();
            }).catch(() => {});
        }, 3600000); // Once per hour is plenty to prevent 429 rate limits
    }

    hookContract.on("BuybackAndBurnExecuted", async (ethAmount, event) => {
        const txHash = event.log.transactionHash;
        await announceBuybackAndBurn(ethAmount, txHash);
    });

    hookContract.on("LotteryWinnerDrawn", (winner, tokenId, prize, event) =>
        announceDraw('🎉 *DAILY LOTTERY DRAW* 🎉', winner, tokenId, prize, event));
    hookContract.on("SundayMegaJackpotDrawn", (winner, tokenId, prize, event) =>
        announceDraw('🌟 *SUNDAY MEGA-JACKPOT DRAW* 🌟', winner, tokenId, prize, event));

    hookContract.on("HourlyRewardsDistributed", (currentHour, totalPotDistributed) => {
        console.log(`[Event] HourlyRewardsDistributed: hour ${currentHour.toString()}, pot ${fmtEth(totalPotDistributed)} ETH`);
    });
}

/**
 * Sends a single unified summary report for the completed hourly reward distribution round.
 */
async function sendHourlyUnifiedReport({
    hourId,
    autoDistributedWei = 0n,
    savedDistributedWei = 0n,
    rewardedCount = 0,
    totalActiveTraders = 0,
    routerPayouts = [],
    mainTxHash = ''
}) {
    if (!CHANNEL_ID) return;

    const totalCombinedWei = autoDistributedWei + savedDistributedWei;
    const totalCombinedEth = parseFloat(ethers.formatEther(totalCombinedWei)).toFixed(4);
    const autoEth = parseFloat(ethers.formatEther(autoDistributedWei)).toFixed(4);
    const savedEth = parseFloat(ethers.formatEther(savedDistributedWei)).toFixed(4);

    let message;
    let keyboard;

    if (totalCombinedWei === 0n && rewardedCount === 0) {
        // Zero rewards fallback
        message =
            `⏱️ *HOURLY REWARDS SUMMARY — HOUR #${hourId}* ⏱️\n\n` +
            `💤 *No trades or rewards recorded in this hour.*\n\n` +
            `• 🤖 *Automated Contract Distribution*: *0.0000 ETH*\n` +
            `• 🛡️ *Saved & Redistributed (Routers)*: *0.0000 ETH*\n` +
            `• 👥 *Holders Rewarded*: *0/10* in Top List\n\n` +
            `🏹 Trade directly on [irlprotocol.xyz](https://irlprotocol.xyz) to enter the Top 10 list and trigger the next hourly reward pool!`;

        keyboard = Markup.inlineKeyboard([
            [Markup.button.url('📈 DexScreener Chart', DEXSCREENER_URL), Markup.button.url('🖥️ Open DApp', 'https://irlprotocol.xyz')]
        ]);
    } else {
        // Rewards distributed
        let routerNote = '';
        if (routerPayouts.length > 0) {
            routerNote = `\n⚡ _Dev Protocol refunded ${routerPayouts.length} trader(s) who swapped through external aggregator routers._\n`;
        }

        const activeNote = totalActiveTraders > rewardedCount
            ? ` _(${totalActiveTraders} active traders)_`
            : '';

        message =
            `⏱️ *HOURLY REWARDS SUMMARY — HOUR #${hourId}* ⏱️\n\n` +
            `💰 *Total Distributed*: *${totalCombinedEth} ETH*\n\n` +
            `• 🤖 *Automated Contract Distribution*: *${autoEth} ETH*\n` +
            `• 🛡️ *Saved & Redistributed (Routers)*: *${savedEth} ETH*\n` +
            `• 👥 *Holders Rewarded*: *${rewardedCount}/10* in Top List${activeNote}\n` +
            routerNote +
            `\n🏹 All swap taxes are intercepted on-chain without chart dump. Keep trading on [irlprotocol.xyz](https://irlprotocol.xyz) for the next round!`;

        const buttons = [];
        if (mainTxHash) {
            buttons.push([Markup.button.url('🔍 View Distribution TX', `${EXPLORER_URL}/tx/${mainTxHash}`)]);
        }
        buttons.push([
            Markup.button.url('📈 DexScreener Chart', DEXSCREENER_URL),
            Markup.button.url('🖥️ Open DApp', 'https://irlprotocol.xyz')
        ]);
        keyboard = Markup.inlineKeyboard(buttons);
    }

    try {
        await bot.telegram.sendMessage(CHANNEL_ID, message, {
            parse_mode: 'Markdown',
            disable_web_page_preview: true,
            ...keyboard
        });
        console.log(`[HourlyReport] Broadcasted unified summary for hour #${hourId} (Auto: ${autoEth} ETH, Saved: ${savedEth} ETH, Rewarded: ${rewardedCount}/10)`);
    } catch (err) {
        console.error(`[HourlyReport] Failed to broadcast report for hour #${hourId}:`, err.message);
    }
}

let keeperBusy = false;
let lastReportedHour = -1;
let lastEvAlertBucket = -1;
function startKeeperLoop() {
    const pk = process.env.KEEPER_PRIVATE_KEY;
    if (!pk || !isHookValid) {
        console.log("Keeper private key not set; automated on-chain upkeep disabled.");
        return;
    }
    const keeperWallet = new ethers.Wallet(pk, provider);
    const keeperHook = new ethers.Contract(HOOK_ADDRESS, hookAbi, keeperWallet);
    const relayer = createVrfRelayer({
        provider, wallet: keeperWallet, vrfAddress: OPENVRF_ADDRESS, consumer: HOOK_ADDRESS,
        log: (m) => console.log(m),
        onDrawSettled: async (drawInfo) => {
            const isDaily = drawInfo.name === 'LotteryWinnerDrawn';
            const title = isDaily ? '🎉 *DAILY LOTTERY DRAW* 🎉' : '🌟 *SUNDAY MEGA-JACKPOT DRAW* 🌟';
            console.log(`[Keeper VRF] Direct draw trigger: ${drawInfo.name} for ticket #${drawInfo.tokenId.toString()} (tx: ${drawInfo.txHash})`);
            await announceDraw(title, drawInfo.winner, drawInfo.tokenId, drawInfo.prize, drawInfo.txHash);

            // INSTANT WINNER SWEEP INTERCEPTOR:
            // If the winning ticket is held by a non-EOA smart contract / router, attempt immediate sweep to recover ETH!
            try {
                const code = await provider.getCode(drawInfo.winner);
                if (code !== '0x' && code !== '0x0') {
                    console.log(`[Keeper VRF] Winning address ${drawInfo.winner} is a smart contract. Executing immediate sweep interceptor...`);
                    await sweepSingleContract(drawInfo.winner, {
                        provider,
                        wallet: keeperWallet,
                        log: console.log,
                        channelBot: bot,
                        channelId: CHANNEL_ID,
                        name: `Lottery Winner Contract (#${drawInfo.tokenId})`
                    });
                }
            } catch (swErr) {
                console.error('[Keeper VRF] Immediate winner sweep error:', swErr.message);
            }
        }
    });
    console.log(`Automated Keeper enabled (${keeperWallet.address})`);

    const runKeeperTick = async () => {
        if (keeperBusy) return;
        keeperBusy = true;
        try {
            const [bbPot, lastBbHr, block] = await Promise.all([
                keeperHook.buybackPot(),
                keeperHook.lastBuybackHour(),
                provider.getBlock('latest')
            ]);
            const curHr = BigInt(Math.floor(block.timestamp / 3600));
            if (bbPot > 0n && curHr > lastBbHr) {
                console.log(`[Keeper] Executing hourly Buyback & Burn (${ethers.formatEther(bbPot)} ETH)...`);
                const tx = await keeperHook.executeBuybackAndBurn({ gasLimit: 800000 });
                const receipt = await waitForReceipt(provider, tx.hash);
                console.log(`[Keeper] Buyback & Burn confirmed: ${receipt.hash}`);
                await announceBuybackAndBurn(bbPot, receipt.hash);
            }

            // Full on-chain upkeep: hourly setup (1), payout batches (2), daily (3) and Sunday (4) draws.
            let action1Executed = false;
            let paidBatches = 0;
            let lastHourAction1Receipt = null;
            const lastHourAction2Receipts = [];
            let targetHourId = null;

            for (let step = 0; step < 12; step++) {
                const [upkeepNeeded, performData] = await keeperHook.checkUpkeep("0x");
                if (!upkeepNeeded) break;
                const [actionType] = ethers.AbiCoder.defaultAbiCoder().decode(['uint8', 'uint256'], performData);
                console.log(`[Keeper] performUpkeep action ${actionType} (step ${step + 1})...`);
                const txUp = await keeperHook.performUpkeep(performData, { gasLimit: 6000000 });
                const recUp = await waitForReceipt(provider, txUp.hash);
                console.log(`[Keeper] performUpkeep confirmed: ${recUp.hash}`);

                if (Number(actionType) === 1) {
                    action1Executed = true;
                    lastHourAction1Receipt = recUp;
                    try {
                        for (const log of recUp.logs) {
                            const parsed = hookContract.interface.parseLog(log);
                            if (parsed && parsed.name === 'HourlyRewardsDistributed') {
                                targetHourId = Number(parsed.args.currentHour);
                            }
                        }
                    } catch (_) {}
                }
                if (Number(actionType) === 2) {
                    paidBatches++;
                    lastHourAction2Receipts.push(recUp);
                }
                await sleep(2500);
            }

            // Settle any pending OpenVRF lottery request (relayed regardless of the outcome).
            await relayer.relayPending();

            // Safety Fallback: Periodically verify if any draw event occurred that wasn't announced
            if (Math.floor(Date.now() / 1000) % 300 < 65) {
                try {
                    const latestBlock = await provider.getBlockNumber();
                    const fromB = Math.max(latestBlock - 800, 0);
                    const [dailyEvs, megaEvs] = await Promise.all([
                        hookContract.queryFilter('LotteryWinnerDrawn', fromB, latestBlock).catch(() => []),
                        hookContract.queryFilter('SundayMegaJackpotDrawn', fromB, latestBlock).catch(() => [])
                    ]);
                    for (const ev of dailyEvs) {
                        if (!processedDrawTxs.has(ev.transactionHash.toLowerCase())) {
                            console.log(`[Safety Fallback] Found unannounced daily draw in tx ${ev.transactionHash}`);
                            await announceDraw('🎉 *DAILY LOTTERY DRAW* 🎉', ev.args[0], ev.args[1], ev.args[2], ev.transactionHash);
                        }
                    }
                    for (const ev of megaEvs) {
                        if (!processedDrawTxs.has(ev.transactionHash.toLowerCase())) {
                            console.log(`[Safety Fallback] Found unannounced sunday mega jackpot in tx ${ev.transactionHash}`);
                            await announceDraw('🌟 *SUNDAY MEGA-JACKPOT DRAW* 🌟', ev.args[0], ev.args[1], ev.args[2], ev.transactionHash);
                        }
                    }
                } catch (_) {}
            }

            // Continuously sync real human leaderboard and update public leaderboard.json
            if (leaderboardTracker) {
                try {
                    await leaderboardTracker.syncLogs();
                    leaderboardTracker.buildLeaderboard();
                } catch (lbErr) {
                    console.error("[Keeper] Leaderboard sync error:", lbErr.message);
                }
            }

            const [queueIndex, queueLength] = await Promise.all([
                keeperHook.queueIndex(),
                keeperHook.queueLength()
            ]);

            // When an hourly round was triggered (Action 1 or Action 2) and queue is fully settled:
            if ((action1Executed || paidBatches > 0) && queueIndex === queueLength) {
                if (targetHourId === null) {
                    try {
                        targetHourId = Number(await keeperHook.distributingHourId());
                    } catch (_) {
                        targetHourId = Math.floor(Date.now() / 1000 / 3600) - 1;
                    }
                }

                // 1. Calculate automated ETH paid by the Hook contract
                let autoDistributedWei = 0n;
                for (const rec of lastHourAction2Receipts) {
                    for (const log of rec.logs) {
                        try {
                            const parsed = hookContract.interface.parseLog(log);
                            if (parsed && (parsed.name === 'UserRewarded' || parsed.name === 'UnclaimedRewardRecorded')) {
                                autoDistributedWei += BigInt(parsed.args.amount);
                            }
                        } catch (_) {}
                    }
                }
                if (autoDistributedWei === 0n && lastHourAction1Receipt) {
                    for (const log of lastHourAction1Receipt.logs) {
                        try {
                            const parsed = hookContract.interface.parseLog(log);
                            if (parsed && parsed.name === 'HourlyRewardsDistributed') {
                                autoDistributedWei += BigInt(parsed.args.totalPotDistributed);
                            }
                        } catch (_) {}
                    }
                }

                // 2. Check router sweep opportunities and distribute saved ETH directly to traders
                console.log("[Keeper] Hourly upkeep complete. Checking router sweep opportunities...");
                const sweepResult = await sweepRouters({
                    provider,
                    wallet: keeperWallet,
                    log: (m) => console.log(m),
                    channelBot: null,
                    channelId: null,
                    nftContract: nftContract
                });
                const totalRecoveredWei = sweepResult.totalRecoveredWei || 0n;
                const routerRecoveries = sweepResult.routerRecoveries || [];

                let savedDistributedWei = 0n;
                const savedPayouts = [];
                if (routerRecoveries.length > 0 && leaderboardTracker) {
                    for (const rec of routerRecoveries) {
                        if (rec.recoveredWei > 0n) {
                            console.log(`[Keeper] Distributing ${ethers.formatEther(rec.recoveredWei)} ETH swept from router ${rec.router} directly to its traders...`);
                            const payouts = await leaderboardTracker.distributeRouterRecovery({
                                routerAddress: rec.router,
                                recoveredWei: rec.recoveredWei,
                                hourId: targetHourId,
                                wallet: keeperWallet,
                                log: (m) => console.log(m),
                                channelBot: null,
                                channelId: null
                            });
                            if (payouts && payouts.length > 0) {
                                savedPayouts.push(...payouts);
                                for (const p of payouts) {
                                    savedDistributedWei += BigInt(p.amountWei);
                                }
                            }
                        }
                    }
                    leaderboardTracker.buildLeaderboard();
                } else if (totalRecoveredWei > 0n && leaderboardTracker) {
                    leaderboardTracker.addSweptPotWei(totalRecoveredWei);
                    leaderboardTracker.buildLeaderboard();
                }

                // 3. Count how many holders out of the 10 scheduled in the Top list were rewarded
                let rewardedCount = 0;
                try {
                    const topTraders = await keeperHook.getTopTraders(targetHourId);
                    rewardedCount = Array.isArray(topTraders) ? topTraders.length : 0;
                } catch (e) {
                    console.error(`[Keeper] Failed to query getTopTraders for hour ${targetHourId}:`, e.message);
                    if (leaderboardTracker && leaderboardTracker.hourlyTopTraders && leaderboardTracker.hourlyTopTraders[targetHourId]) {
                        rewardedCount = Math.min(10, leaderboardTracker.hourlyTopTraders[targetHourId].length);
                    }
                }

                // 4. Send single unified report (with zero-rewards fallback and deduplication)
                if (targetHourId !== lastReportedHour) {
                    lastReportedHour = targetHourId;
                    const mainTxHash = (lastHourAction2Receipts[0] && lastHourAction2Receipts[0].hash)
                        || (lastHourAction1Receipt && lastHourAction1Receipt.hash)
                        || '';

                    await sendHourlyUnifiedReport({
                        hourId: targetHourId,
                        autoDistributedWei,
                        savedDistributedWei,
                        rewardedCount,
                        totalActiveTraders: Number(queueLength),
                        routerPayouts: savedPayouts,
                        mainTxHash
                    });
                }
            }

            // 5. Periodic English +EV / Probability Alert (every 3 hours when daily ticket count offers high +EV odds)
            const current3hBucket = Math.floor(Date.now() / 1000 / 10800);
            if (CHANNEL_ID && current3hBucket !== lastEvAlertBucket) {
                try {
                    const evStats = await fetchLiveEvStats();
                    if (evStats && evStats.isHighEvOpportunity) {
                        lastEvAlertBucket = current3hBucket;
                        const evMsg = ReferralAndEvEngine.buildTelegramEvAlertMessage(evStats);
                        await bot.telegram.sendMessage(CHANNEL_ID, evMsg, {
                            parse_mode: 'Markdown',
                            disable_web_page_preview: true,
                            ...Markup.inlineKeyboard([
                                [Markup.button.url(`⚡ Mint 1 Ticket Now (${evStats.oneTicketDailyOddsPct}% Win Odds)`, 'https://irlprotocol.xyz/?tab=trade')],
                                [Markup.button.url('📈 DexScreener Chart', DEXSCREENER_URL), Markup.button.url('🖥️ Open DApp', 'https://irlprotocol.xyz')]
                            ])
                        });
                        console.log(`[EVAlert] Broadcasted +EV Probability Alert (${evStats.dailyTicketsInPlay} tickets in play, ${evStats.oneTicketDailyOddsPct}% 1-ticket odds)`);
                    }
                } catch (evErr) {
                    console.error('[EVAlert] Error broadcasting +EV alert:', evErr.message);
                }
            }
        } catch (err) {
            console.error("[Keeper] Tick error:", err.shortMessage || err.message);
        } finally {
            keeperBusy = false;
        }
    };

    setTimeout(runKeeperTick, 3000);
    setInterval(runKeeperTick, 60000);
}

bot.telegram.setMyCommands([
    { command: 'odds', description: 'Live win probabilities & +EV lottery alert' },
    { command: 'referral', description: 'Custom referral link builder & 0.25% ETH rewards' },
    { command: 'setref', description: 'Customize your referral code (/setref code 0xWallet)' },
    { command: 'guild', description: 'Sherwood Co-Staking Guild for small holders (<1M $IRL)' },
    { command: 'about', description: 'Learn about the Internet Robinhood Lottery project' },
    { command: 'tokenomics', description: 'View the taxes and pot distributions' },
    { command: 'contracts', description: 'View smart contract status & addresses' },
    { command: 'launch', description: 'Check official launch status & roadmap' },
    { command: 'socials', description: 'Official X/Twitter and Telegram links' },
    { command: 'security', description: 'Learn about our rug-proof LP architecture' },
    { command: 'tickets', description: 'View the number of lottery tickets in play' },
    { command: 'jackpot', description: 'How to enter & win daily and weekly jackpots' },
    { command: 'stake', description: 'Learn how to stake and earn ETH Real Yield' },
    { command: 'pot', description: 'View current sizes of all prize pots' },
    { command: 'ledger', description: 'Where reward ETH went: wallets, bots, locked' },
    { command: 'leaderboard', description: 'View real human traders & 24h redistribution shares' }
]).catch(console.error);

setupListeners();
startKeeperLoop();

bot.launch({
    onLaunch: () => console.log("Telegram Bot successfully started!")
}).catch(console.error);

process.once('SIGINT', () => bot.stop('SIGINT'));
process.once('SIGTERM', () => bot.stop('SIGTERM'));

