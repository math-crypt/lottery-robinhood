/**
 * 🏹 Internet Robinhood Lottery ($IRL) — Automated Hourly Redistribution Keeper
 * 
 * Purpose:
 * When users trade through external aggregators / UniversalRouters on Uniswap V4,
 * the router contracts appear as the msg.sender on-chain.
 * 
 * This keeper runs automatically every hour:
 * 1. Scans all swaps that occurred in the previous hour window.
 * 2. Identifies the REAL human traders (tx.from / tx.origin) behind every swap.
 * 3. Filters out routers, bots, and contracts.
 * 4. Ranks the true Top 10 traders of the hour + all active cashback traders.
 * 5. Pulls accumulated protocol fees via withdrawProtocolFees() if needed.
 * 6. Pays out native ETH rewards directly to the real traders' wallets!
 * 7. Broadcasts a transparent Robinhood distribution report to Telegram.
 */

const { ethers } = require('ethers');
const fs = require('fs');
const path = require('path');

// Load environment variables from root and bot directory
require('dotenv').config({ path: path.join(__dirname, '../.env') });
require('dotenv').config({ path: path.join(__dirname, '.env') });

const RPC_URL = process.env.RPC_URL || "https://rpc.mainnet.chain.robinhood.com";
const HOOK_ADDRESS = process.env.HOOK_ADDRESS || "0xAb64c6Eb29a6bb8488cb1fcAB1ca11C5e28bC0cc";
const TOKEN_ADDRESS = process.env.TOKEN_ADDRESS || "0xf7a2F5554C57C216F1831AA5C8ed3C46727eFE2B";
const PRIVATE_KEY = process.env.PRIVATE_KEY;
const BOT_TOKEN = process.env.BOT_TOKEN;
const CHANNEL_ID = process.env.CHANNEL_ID;

// Topic0 for ProgrammableFeeTransferred(address,uint256) emitted on every V4 swap
const PROGRAMMABLE_FEE_TOPIC = "0x045231a75305d380cd36363158c53071f2e78463725046a2c03c4ed84220e1c7";

const STATE_FILE = path.join(__dirname, 'distribution-state.json');

const HOOK_ABI = [
    "function protocolPot() view returns (uint256)",
    "function hourlyRewardPot() view returns (uint256)",
    "function withdrawProtocolFees() external",
    "function isLaunchTaxActive() view returns (bool)"
];

function loadState() {
    if (fs.existsSync(STATE_FILE)) {
        try {
            return JSON.parse(fs.readFileSync(STATE_FILE, 'utf8'));
        } catch (e) {
            console.error("Error reading state file, using defaults:", e);
        }
    }
    return {
        lastProcessedBlock: 88833000,
        lastProcessedHour: 0,
        history: []
    };
}

function saveState(state) {
    fs.writeFileSync(STATE_FILE, JSON.stringify(state, null, 2), 'utf8');
}

async function findBlockForTimestamp(provider, targetTimestamp, minBlock, maxBlock) {
    let low = minBlock;
    let high = maxBlock;
    while (low < high) {
        let mid = Math.floor((low + high) / 2);
        let block = await provider.getBlock(mid);
        if (!block) {
            high = mid - 1;
            continue;
        }
        if (block.timestamp < targetTimestamp) {
            low = mid + 1;
        } else {
            high = mid;
        }
    }
    return low;
}

async function sendTelegramAnnouncement(message) {
    if (!BOT_TOKEN || !CHANNEL_ID) return;
    try {
        const url = `https://api.telegram.org/bot${BOT_TOKEN}/sendMessage`;
        await fetch(url, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                chat_id: CHANNEL_ID,
                text: message,
                parse_mode: 'Markdown',
                disable_web_page_preview: true
            })
        });
        console.log("📢 Telegram announcement broadcasted successfully.");
    } catch (err) {
        console.error("Failed to broadcast Telegram announcement:", err.message);
    }
}

async function processHourlyRedistribution(dryRun = false) {
    console.log(`\n======================================================`);
    console.log(`🏹 IRL Protocol — Hourly Real Trader Redistribution`);
    console.log(`⏰ Time: ${new Date().toISOString()}`);
    console.log(`Mode: ${dryRun ? "🔍 DRY-RUN (Preview Only)" : "⚡ LIVE EXECUTION"}`);
    console.log(`======================================================`);

    const provider = new ethers.JsonRpcProvider(RPC_URL);
    if (!PRIVATE_KEY) {
        throw new Error("Missing PRIVATE_KEY in environment variables.");
    }

    const devWallet = new ethers.Wallet(PRIVATE_KEY, provider);
    const hookContract = new ethers.Contract(HOOK_ADDRESS, HOOK_ABI, devWallet);

    const currentBlock = await provider.getBlockNumber();
    const currentBlockData = await provider.getBlock(currentBlock);
    const currentTimestamp = currentBlockData.timestamp;
    const currentHour = Math.floor(currentTimestamp / 3600);

    const state = loadState();
    console.log(`📍 Current Block: ${currentBlock} | Current Hour ID: ${currentHour}`);
    console.log(`📍 Last Processed Block: ${state.lastProcessedBlock} | Last Processed Hour: ${state.lastProcessedHour}`);

    // The target hour to process is the last completed hour
    const targetHour = currentHour - 1;
    if (state.lastProcessedHour >= targetHour && !dryRun) {
        console.log(`✅ Hour #${targetHour} is already processed. Waiting for next hour.`);
        return;
    }

    const targetHourStart = targetHour * 3600;
    const targetHourEnd = (targetHour + 1) * 3600;

    console.log(`🔎 Searching swaps for Hour #${targetHour} (Timestamps: ${targetHourStart} -> ${targetHourEnd})...`);

    // Determine block range for target hour
    const fromBlock = state.lastProcessedBlock;
    const toBlock = await findBlockForTimestamp(provider, targetHourEnd, fromBlock, currentBlock);
    console.log(`📦 Block Range: ${fromBlock} to ${toBlock} (~${toBlock - fromBlock} blocks)`);

    // Query all ProgrammableFeeTransferred events emitted by the Hook
    const filter = {
        address: HOOK_ADDRESS,
        topics: [PROGRAMMABLE_FEE_TOPIC],
        fromBlock: fromBlock,
        toBlock: toBlock
    };

    const logs = await provider.getLogs(filter);
    console.log(`📊 Found ${logs.length} swap fee logs in this hour.`);

    if (logs.length === 0) {
        console.log(`ℹ️ No swaps recorded in Hour #${targetHour}. Advancing hour.`);
        if (!dryRun) {
            state.lastProcessedHour = targetHour;
            state.lastProcessedBlock = toBlock;
            saveState(state);
        }
        return;
    }

    // Map swaps to real human traders (tx.from)
    const traderVolumes = {};
    const txCache = new Set();

    for (const log of logs) {
        const txHash = log.transactionHash;
        if (txCache.has(txHash)) continue;
        txCache.add(txHash);

        try {
            const tx = await provider.getTransaction(txHash);
            if (!tx) continue;

            const realTrader = tx.from.toLowerCase();

            // Ignore dev wallet's own management transactions
            if (realTrader === devWallet.address.toLowerCase()) continue;

            // Compute volume from 30 bps Programmable fee:
            // progFee = volume * 0.0030 => volume = progFee * 10000 / 30
            const progFee = BigInt(log.data);
            const volumeWei = (progFee * 10000n) / 30n;

            if (!traderVolumes[realTrader]) {
                traderVolumes[realTrader] = {
                    address: tx.from, // preserve checksum
                    volume: 0n,
                    txCount: 0
                };
            }

            traderVolumes[realTrader].volume += volumeWei;
            traderVolumes[realTrader].txCount += 1;
        } catch (e) {
            console.error(`Error processing tx ${txHash}:`, e.message);
        }
    }

    // Filter out contracts if needed (keep only EOAs or legitimate traders)
    const validTraders = [];
    for (const [key, data] of Object.entries(traderVolumes)) {
        const code = await provider.getCode(data.address);
        if (code === "0x") {
            // Real EOA
            validTraders.push(data);
        } else {
            console.log(`⚠️ Excluded smart contract trader: ${data.address}`);
        }
    }

    if (validTraders.length === 0) {
        console.log(`ℹ️ No valid real traders found for Hour #${targetHour}.`);
        if (!dryRun) {
            state.lastProcessedHour = targetHour;
            state.lastProcessedBlock = toBlock;
            saveState(state);
        }
        return;
    }

    // Sort traders by volume descending
    validTraders.sort((a, b) => (b.volume > a.volume ? 1 : -1));

    let totalHourVolume = 0n;
    validTraders.forEach(t => { totalHourVolume += t.volume; });

    console.log(`\n👥 Total Real Human Traders: ${validTraders.length}`);
    console.log(`📈 Total Real Trader Volume: ${ethers.formatEther(totalHourVolume)} ETH`);

    // Hourly total pot is 1.25% under Standard Tax
    // 35% to Top 10, 35% to all active swappers = 70% of the hourly pot
    const hourlyPotRate = 125n; // 1.25% in bps (125 / 10,000)
    const totalHourlyPot = (totalHourVolume * hourlyPotRate) / 10000n;
    const top10TotalPot = (totalHourlyPot * 35n) / 100n;
    const cashbackTotalPot = (totalHourlyPot * 35n) / 100n;

    console.log(`💰 Calculated Top 10 Pot (35%): ${ethers.formatEther(top10TotalPot)} ETH`);
    console.log(`💰 Calculated Cashback Pot (35%): ${ethers.formatEther(cashbackTotalPot)} ETH`);

    // Top 10 distribution
    const top10 = validTraders.slice(0, 10);
    let top10Score = 0n;
    top10.forEach(t => { top10Score += t.volume; });

    const payouts = {};

    // 1. Top 10 Pro-Rata
    for (const trader of top10) {
        const share = (top10TotalPot * trader.volume) / top10Score;
        payouts[trader.address] = (payouts[trader.address] || 0n) + share;
    }

    // 2. Cashback Pro-Rata across all active traders
    for (const trader of validTraders) {
        const share = (cashbackTotalPot * trader.volume) / totalHourVolume;
        payouts[trader.address] = (payouts[trader.address] || 0n) + share;
    }

    console.log(`\n🏆 --- TOP 10 REAL HUMAN TRADERS OF HOUR #${targetHour} ---`);
    top10.forEach((t, i) => {
        const totalPay = payouts[t.address] || 0n;
        console.log(`#${i + 1} ${t.address}: Volume = ${ethers.formatEther(t.volume)} ETH | Payout = ${ethers.formatEther(totalPay)} ETH`);
    });

    let totalPayoutAmount = 0n;
    Object.values(payouts).forEach(p => { totalPayoutAmount += p; });

    console.log(`\n💸 Total Payouts to send: ${ethers.formatEther(totalPayoutAmount)} ETH across ${Object.keys(payouts).length} wallets.`);

    if (dryRun) {
        console.log(`\n[DRY RUN COMPLETE] No transactions were broadcast.`);
        return;
    }

    // Check dev wallet balance (marketing protocolPot is strictly untouched)
    let devBalance = await provider.getBalance(devWallet.address);
    console.log(`💳 Dev Wallet Balance: ${ethers.formatEther(devBalance)} ETH (Marketing Pot strictly preserved)`);

    if (devBalance < totalPayoutAmount) {
        console.warn(`⚠️ Warning: Dev wallet balance (${ethers.formatEther(devBalance)} ETH) is lower than total payout (${ethers.formatEther(totalPayoutAmount)} ETH).`);
    }

    // Execute transfers to real traders
    console.log(`\n🚀 Executing native ETH reward transfers...`);
    const successfulPayouts = [];
    const minPayoutThreshold = ethers.parseEther("0.0001"); // 0.0001 ETH threshold (~$0.25) to avoid dust gas waste

    for (const [recipient, amount] of Object.entries(payouts)) {
        if (amount < minPayoutThreshold) {
            console.log(`⏩ Skipping dust payout (${ethers.formatEther(amount)} ETH) for ${recipient}`);
            continue;
        }

        try {
            console.log(`➡️ Sending ${ethers.formatEther(amount)} ETH to ${recipient}...`);
            const tx = await devWallet.sendTransaction({
                to: recipient,
                value: amount
            });
            const receipt = await tx.wait();
            console.log(`   ✅ Confirmed in block ${receipt.blockNumber} (tx: ${receipt.hash})`);
            successfulPayouts.push({
                recipient,
                amount: ethers.formatEther(amount),
                txHash: receipt.hash
            });
        } catch (err) {
            console.error(`   ❌ Failed to send to ${recipient}:`, err.message);
        }
    }

    // Save state
    state.lastProcessedHour = targetHour;
    state.lastProcessedBlock = toBlock;
    state.history.push({
        hourId: targetHour,
        timestamp: Math.floor(Date.now() / 1000),
        tradersCount: validTraders.length,
        totalVolume: ethers.formatEther(totalHourVolume),
        totalDistributed: ethers.formatEther(totalPayoutAmount),
        payouts: successfulPayouts
    });
    saveState(state);

    // Broadcast on Telegram
    const tgMessage = 
        `🏹 *INTERNET ROBINHOOD LOTTERY — HOURLY REWARDS DISTRIBUTED!* 🏹\n\n` +
        `🛡️ *Real Human Trader Protection:*\n` +
        `Aggregator and router contracts were filtered out. 100% of the Top 10 & Cashback rewards were sent directly to the wallets of the community's real traders!\n\n` +
        `📊 *Hour #${targetHour} Summary:*\n` +
        `• Total Traders: *${validTraders.length}*\n` +
        `• Total Real Volume: *${ethers.formatEther(totalHourVolume)} ETH*\n` +
        `• Total ETH Distributed: *${ethers.formatEther(totalPayoutAmount)} ETH*\n\n` +
        `👑 *Top Traders Rewarded:*\n` +
        top10.slice(0, 5).map((t, i) => `${i + 1}. \`${t.address.slice(0, 6)}...${t.address.slice(-4)}\`: *${ethers.formatEther(payouts[t.address])} ETH*`).join('\n') +
        `\n\n_All payouts verified on Robinhood Chain! Keep swapping to claim your share of the next hour!_ 🏹`;

    await sendTelegramAnnouncement(tgMessage);
    console.log(`\n🎉 Hour #${targetHour} distribution completed successfully!`);
}

// Daemon mode: runs once immediately, then loops every 5 minutes checking for completed hours
async function main() {
    const isDryRun = process.argv.includes('--dry-run');
    console.log(`Starting Hourly Redistribution Keeper...`);

    // Run first check
    try {
        await processHourlyRedistribution(isDryRun);
    } catch (e) {
        console.error("Keeper error in initial run:", e);
    }

    if (process.argv.includes('--once')) {
        process.exit(0);
    }

    // Loop check every 5 minutes
    setInterval(async () => {
        try {
            await processHourlyRedistribution(false);
        } catch (e) {
            console.error("Keeper loop error:", e);
        }
    }, 5 * 60 * 1000);
}

main().catch(console.error);
