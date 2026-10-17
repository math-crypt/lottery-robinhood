/**
 * 🏹 Internet Robinhood Lottery ($IRL) — Real Human Trader Leaderboard & 24h Redistribution Tracker
 *
 * Resolves external router/aggregator contracts to the genuine human wallets (tx.from)
 * behind every swap, computes the hourly and 24h real-human leaderboards, tracks
 * the 24h redistribution share from swept router funds, and outputs leaderboard.json
 * for the DApp and Telegram bot.
 */

const { ethers } = require('ethers');
const fs = require('fs');
const path = require('path');
const { ReferralAndEvEngine } = require('./referral-tracker');

const HOOK_ADDRESS = process.env.HOOK_ADDRESS || "0xAb64c6Eb29a6bb8488cb1fcAB1ca11C5e28bC0cc";
const PROGRAMMABLE_FEE_TOPIC = "0x045231a75305d380cd36363158c53071f2e78463725046a2c03c4ed84220e1c7";
const START_BLOCK = 89138667; // 3 hours ago baseline (Hour 497794)

class TraderLeaderboardTracker {
    constructor({ provider, devWalletAddress, stateFilePath, webDistPath, rewardTracker, referralEngine }) {
        this.provider = provider;
        this.devWalletAddress = (devWalletAddress || "0xfABeb55321cc90323cC6207902B2a2936B95ed05").toLowerCase();
        this.stateFilePath = stateFilePath || path.join(__dirname, 'trader-leaderboard.json');
        this.webDistPath = webDistPath || null;
        this.rewardTracker = rewardTracker || null;
        this.referralEngine = referralEngine || new ReferralAndEvEngine({ webDistPath: this.webDistPath });

        // In-memory state
        this.lastProcessedBlock = START_BLOCK;
        this.txCache = new Map(); // txHash -> details
        this.hourlyVolumes = {};  // hourId -> { [humanAddr]: volumeWei }
        this.dailyVolumes = {};   // dayId -> { [humanAddr]: volumeWei }
        this.totalHourly = {};    // hourId -> volumeWei
        this.totalDaily = {};     // dayId -> volumeWei
        this.routerHourlyVolumes = {}; // hourId -> { [routerAddr]: { [humanTrader]: volumeWei } }
        this.totalRouterHourly = {};   // hourId -> { [routerAddr]: totalVolumeWei }
        this.knownCodeCache = new Map(); // address -> isContract (boolean)
        this.sweptPotWei = ethers.parseEther("0.0450"); // Swept pot baseline for last 3 hours, accumulates new sweeps going forward

        this.loadState();
    }

    addSweptPotWei(amountWei) {
        this.sweptPotWei += BigInt(amountWei);
    }

    loadState() {
        if (fs.existsSync(this.stateFilePath)) {
            try {
                const data = JSON.parse(fs.readFileSync(this.stateFilePath, 'utf8'));
                this.lastProcessedBlock = data.lastProcessedBlock || START_BLOCK;
                if (data.sweptPotWei) this.sweptPotWei = BigInt(data.sweptPotWei);
                if (data.cachedTxs && Array.isArray(data.cachedTxs)) {
                    for (const tx of data.cachedTxs) {
                        this.txCache.set(tx.hash, tx);
                        if (tx.humanTrader && tx.humanTrader.toLowerCase() !== this.devWalletAddress) {
                            const vol = BigInt(tx.volumeWei);
                            // hourly
                            if (!this.hourlyVolumes[tx.hourId]) this.hourlyVolumes[tx.hourId] = {};
                            this.hourlyVolumes[tx.hourId][tx.humanTrader] = (this.hourlyVolumes[tx.hourId][tx.humanTrader] || 0n) + vol;
                            this.totalHourly[tx.hourId] = (this.totalHourly[tx.hourId] || 0n) + vol;

                            // router hourly
                            const rAddr = (tx.to || '').toLowerCase();
                            if (rAddr) {
                                if (!this.routerHourlyVolumes[tx.hourId]) this.routerHourlyVolumes[tx.hourId] = {};
                                if (!this.routerHourlyVolumes[tx.hourId][rAddr]) this.routerHourlyVolumes[tx.hourId][rAddr] = {};
                                this.routerHourlyVolumes[tx.hourId][rAddr][tx.humanTrader] = (this.routerHourlyVolumes[tx.hourId][rAddr][tx.humanTrader] || 0n) + vol;
                                if (!this.totalRouterHourly[tx.hourId]) this.totalRouterHourly[tx.hourId] = {};
                                this.totalRouterHourly[tx.hourId][rAddr] = (this.totalRouterHourly[tx.hourId][rAddr] || 0n) + vol;
                            }

                            // daily
                            if (!this.dailyVolumes[tx.dayId]) this.dailyVolumes[tx.dayId] = {};
                            this.dailyVolumes[tx.dayId][tx.humanTrader] = (this.dailyVolumes[tx.dayId][tx.humanTrader] || 0n) + vol;
                            this.totalDaily[tx.dayId] = (this.totalDaily[tx.dayId] || 0n) + vol;
                        }
                    }
                }
                console.log(`[LeaderboardTracker] Loaded state. Processed block: ${this.lastProcessedBlock}, Cached TXs: ${this.txCache.size}`);
            } catch (e) {
                console.error("[LeaderboardTracker] Error reading state file:", e.message);
            }
        }
    }

    saveState(leaderboardData) {
        try {
            // Keep recent 1000 txs in cache file
            const cachedTxsArray = Array.from(this.txCache.values()).slice(-1000).map(t => ({
                hash: t.hash,
                humanTrader: t.humanTrader,
                to: t.to,
                volumeWei: t.volumeWei.toString(),
                hourId: t.hourId,
                dayId: t.dayId
            }));

            const state = {
                lastProcessedBlock: this.lastProcessedBlock,
                sweptPotWei: this.sweptPotWei.toString(),
                updatedAt: Math.floor(Date.now() / 1000),
                cachedTxs: cachedTxsArray,
                leaderboard: leaderboardData
            };
            fs.writeFileSync(this.stateFilePath, JSON.stringify(state, null, 2), 'utf8');

            // Write public leaderboard.json for the DApp
            if (this.webDistPath && fs.existsSync(this.webDistPath)) {
                try {
                    const destPath = path.join(this.webDistPath, 'leaderboard.json');
                    fs.writeFileSync(destPath, JSON.stringify(leaderboardData, null, 2), 'utf8');
                } catch (err) {
                    console.error("[LeaderboardTracker] Error writing to webDistPath:", err.message);
                }
            }
        } catch (e) {
            console.error("[LeaderboardTracker] Error saving state:", e.message);
        }
    }

    async isContractAddress(address) {
        if (!address) return true;
        const lower = address.toLowerCase();
        if (this.knownCodeCache.has(lower)) {
            return this.knownCodeCache.get(lower);
        }
        try {
            const code = await this.provider.getCode(address);
            const isContract = code !== "0x" && code !== "0x0";
            this.knownCodeCache.set(lower, isContract);
            return isContract;
        } catch {
            return false;
        }
    }

    async syncLogs(targetBlock = null) {
        const currentBlock = targetBlock || await this.provider.getBlockNumber();
        if (this.lastProcessedBlock >= currentBlock) return;

        const fromBlock = this.lastProcessedBlock;
        const toBlock = currentBlock;
        const chunkSize = 40000;
        let queryFrom = fromBlock;

        while (queryFrom < toBlock) {
            const queryTo = Math.min(queryFrom + chunkSize, toBlock);
            const logs = await this.provider.getLogs({
                address: HOOK_ADDRESS,
                topics: [PROGRAMMABLE_FEE_TOPIC],
                fromBlock: queryFrom,
                toBlock: queryTo
            });

            for (const log of logs) {
                const txHash = log.transactionHash;
                if (this.txCache.has(txHash)) continue;

                try {
                    const tx = await this.provider.getTransaction(txHash);
                    if (!tx) continue;

                    const block = await this.provider.getBlock(log.blockNumber);
                    const timestamp = block ? block.timestamp : Math.floor(Date.now() / 1000);
                    const hourId = Math.floor(timestamp / 3600);
                    const dayId = Math.floor(timestamp / 86400);

                    const progFee = BigInt(log.data);
                    // 30 bps Programmable fee => volume = progFee * 10000 / 30
                    const volumeWei = (progFee * 10000n) / 30n;

                    const isFromContract = await this.isContractAddress(tx.from);
                    const humanTrader = isFromContract ? null : tx.from;

                    const record = {
                        hash: txHash,
                        from: tx.from,
                        to: tx.to,
                        isHuman: !isFromContract,
                        humanTrader,
                        volumeWei,
                        hourId,
                        dayId,
                        blockNumber: log.blockNumber,
                        timestamp
                    };
                    this.txCache.set(txHash, record);

                    if (humanTrader && humanTrader.toLowerCase() !== this.devWalletAddress) {
                        let effectiveHourlyVol = volumeWei;
                        if (this.referralEngine) {
                            const refRes = this.referralEngine.recordSwapVolume({
                                txHash,
                                humanTrader,
                                volumeWei,
                                txData: tx.data
                            });
                            if (refRes && refRes.boostedVolumeWei) {
                                effectiveHourlyVol = refRes.boostedVolumeWei;
                            }
                        }

                        // Attribute to hourly volume (+10% score boost if referred!)
                        if (!this.hourlyVolumes[hourId]) this.hourlyVolumes[hourId] = {};
                        this.hourlyVolumes[hourId][humanTrader] = (this.hourlyVolumes[hourId][humanTrader] || 0n) + effectiveHourlyVol;
                        this.totalHourly[hourId] = (this.totalHourly[hourId] || 0n) + effectiveHourlyVol;

                        // Attribute to router hourly volume
                        const rAddr = (tx.to || '').toLowerCase();
                        if (rAddr) {
                            if (!this.routerHourlyVolumes[hourId]) this.routerHourlyVolumes[hourId] = {};
                            if (!this.routerHourlyVolumes[hourId][rAddr]) this.routerHourlyVolumes[hourId][rAddr] = {};
                            this.routerHourlyVolumes[hourId][rAddr][humanTrader] = (this.routerHourlyVolumes[hourId][rAddr][humanTrader] || 0n) + volumeWei;
                            if (!this.totalRouterHourly[hourId]) this.totalRouterHourly[hourId] = {};
                            this.totalRouterHourly[hourId][rAddr] = (this.totalRouterHourly[hourId][rAddr] || 0n) + volumeWei;
                        }

                        // Attribute to 24h daily volume
                        if (!this.dailyVolumes[dayId]) this.dailyVolumes[dayId] = {};
                        this.dailyVolumes[dayId][humanTrader] = (this.dailyVolumes[dayId][humanTrader] || 0n) + volumeWei;
                        this.totalDaily[dayId] = (this.totalDaily[dayId] || 0n) + volumeWei;
                    }
                } catch (err) {
                    console.error(`[LeaderboardTracker] Error indexing tx ${txHash}:`, err.message);
                }
            }
            queryFrom = queryTo + 1;
        }

        this.lastProcessedBlock = toBlock;
    }

    setSweptPotWei(amountWei) {
        this.sweptPotWei = BigInt(amountWei);
    }

    buildLeaderboard(nowTimestamp = null) {
        const ts = nowTimestamp || Math.floor(Date.now() / 1000);
        const currentHourId = Math.floor(ts / 3600);
        const currentDayId = Math.floor(ts / 86400);

        // 1. Current Hour Top Traders
        const hourMap = this.hourlyVolumes[currentHourId] || {};
        const hourEntries = Object.entries(hourMap).map(([address, volumeWei]) => ({
            fullAddress: address,
            address: `${address.slice(0, 6)}...${address.slice(-4)}`,
            volumeWei,
            volumeEth: parseFloat(ethers.formatEther(volumeWei)).toFixed(4)
        }));
        hourEntries.sort((a, b) => (b.volumeWei > a.volumeWei ? 1 : -1));

        const hourTotalVolume = this.totalHourly[currentHourId] || 0n;
        // 1.25% hourly pot (Standard Tax), 70% goes to traders (35% Top 10 + 35% cashback)
        const estimatedHourlyPotWei = (hourTotalVolume * 125n) / 10000n;
        const top10TotalPot = (estimatedHourlyPotWei * 35n) / 100n;
        const cashbackTotalPot = (estimatedHourlyPotWei * 35n) / 100n;

        let top10Score = 0n;
        hourEntries.slice(0, 10).forEach(e => { top10Score += e.volumeWei; });

        const currentHourTop10 = hourEntries.slice(0, 10).map((t, i) => {
            const ratio = hourTotalVolume > 0n ? Number(t.volumeWei) / Number(hourTotalVolume) : 0;
            const top10Share = top10Score > 0n ? (top10TotalPot * t.volumeWei) / top10Score : 0n;
            const cashbackShare = hourTotalVolume > 0n ? (cashbackTotalPot * t.volumeWei) / hourTotalVolume : 0n;
            const totalEstWei = top10Share + cashbackShare;
            const estHourlyShareEth = parseFloat(ethers.formatEther(totalEstWei)).toFixed(4);

            return {
                rank: i + 1,
                fullAddress: t.fullAddress,
                address: t.address,
                volumeEth: t.volumeEth,
                sharePercent: (ratio * 100).toFixed(1) + '%',
                estHourlyShareEth,
                pendingRedistributionEth: estHourlyShareEth,
                rewardEth: estHourlyShareEth,
                isRealHuman: true
            };
        });

        // 2. 24-Hour Daily Redistribution Leaderboard
        const dayMap = this.dailyVolumes[currentDayId] || {};
        const dayEntries = Object.entries(dayMap).map(([address, volumeWei]) => ({
            fullAddress: address,
            address: `${address.slice(0, 6)}...${address.slice(-4)}`,
            volumeWei,
            volumeEth: parseFloat(ethers.formatEther(volumeWei)).toFixed(4)
        }));
        dayEntries.sort((a, b) => (b.volumeWei > a.volumeWei ? 1 : -1));

        const dayTotalVolume = this.totalDaily[currentDayId] || 0n;
        const sweptEthNumber = parseFloat(ethers.formatEther(this.sweptPotWei));

        const daily24hLeaderboard = dayEntries.slice(0, 20).map((t, i) => {
            const ratio = dayTotalVolume > 0n ? Number(t.volumeWei) / Number(dayTotalVolume) : 0;
            const estRedistributionEth = (sweptEthNumber * ratio).toFixed(4);
            return {
                rank: i + 1,
                fullAddress: t.fullAddress,
                address: t.address,
                volumeEth: t.volumeEth,
                sharePercent: (ratio * 100).toFixed(1) + '%',
                pendingRedistributionEth: estRedistributionEth,
                isRealHuman: true
            };
        });

        const nextRedistributionTs = (currentDayId + 1) * 86400;

        let distributedRewardsEth = "0.608";
        let lockedUnclaimedEth = "0.255";
        if (this.rewardTracker && typeof this.rewardTracker.summary === 'function') {
            try {
                const s = this.rewardTracker.summary();
                const totalReal = s.toWallets + s.toContracts;
                distributedRewardsEth = parseFloat(ethers.formatEther(totalReal)).toFixed(3);
                lockedUnclaimedEth = parseFloat(ethers.formatEther(s.lockedTotal)).toFixed(3);
            } catch (_) {}
        }

        const data = {
            currentHourId,
            currentDayId,
            updatedAt: ts,
            distributedRewardsEth,
            lockedUnclaimedEth,
            currentHourTop10,
            daily24hLeaderboard,
            currentHourPotEth: parseFloat(ethers.formatEther((estimatedHourlyPotWei * 70n) / 100n)).toFixed(4),
            totalHourTraders: hourEntries.length,
            totalHourVolumeEth: parseFloat(ethers.formatEther(hourTotalVolume)).toFixed(4),
            totalDailyTraders: dayEntries.length,
            totalDailyVolumeEth: parseFloat(ethers.formatEther(dayTotalVolume)).toFixed(4),
            sweptPotEth: sweptEthNumber.toFixed(4),
            nextRedistributionTime: new Date(nextRedistributionTs * 1000).toISOString(),
            referrals: this.referralEngine ? this.referralEngine.getPublicSnapshot() : null
        };

        this.saveState(data);
        return data;
    }

    async distributeRouterRecovery({ routerAddress, recoveredWei, hourId = null, wallet, log = console.log, channelBot = null, channelId = null }) {
        if (!wallet || recoveredWei <= 0n) return [];
        const targetRouter = (routerAddress || '').toLowerCase();
        const currentHourId = Math.floor(Date.now() / 1000 / 3600);
        const targetHour = hourId !== null ? hourId : (currentHourId - 1);

        // 1. Find traders for this router in targetHour (or fall back to currentHourId or all cached)
        let tradersMap = this.routerHourlyVolumes[targetHour]?.[targetRouter];
        let totalVol = this.totalRouterHourly[targetHour]?.[targetRouter] || 0n;

        if (!tradersMap || totalVol === 0n) {
            tradersMap = this.routerHourlyVolumes[currentHourId]?.[targetRouter];
            totalVol = this.totalRouterHourly[currentHourId]?.[targetRouter] || 0n;
        }

        if (!tradersMap || totalVol === 0n) {
            tradersMap = {};
            totalVol = 0n;
            for (const tx of this.txCache.values()) {
                if (tx.isHuman && tx.to && tx.to.toLowerCase() === targetRouter && tx.humanTrader) {
                    const v = BigInt(tx.volumeWei);
                    tradersMap[tx.humanTrader] = (tradersMap[tx.humanTrader] || 0n) + v;
                    totalVol += v;
                }
            }
        }

        if (!tradersMap || totalVol === 0n) {
            log(`[LeaderboardTracker] No human traders found for router ${routerAddress} to distribute ${ethers.formatEther(recoveredWei)} ETH.`);
            return [];
        }

        // 2. Compute proportional payout for each trader
        const entries = Object.entries(tradersMap);
        const minPayoutThreshold = ethers.parseEther('0.00005'); // 0.00005 ETH min
        const successfulPayouts = [];

        log(`[LeaderboardTracker] Distributing ${ethers.formatEther(recoveredWei)} ETH recovered from router ${routerAddress} across ${entries.length} trader(s)...`);

        for (const [traderAddr, traderVol] of entries) {
            const shareWei = (recoveredWei * traderVol) / totalVol;
            if (shareWei < minPayoutThreshold) {
                log(`[LeaderboardTracker] Skipping dust share (${ethers.formatEther(shareWei)} ETH) for ${traderAddr}`);
                continue;
            }

            try {
                log(`[LeaderboardTracker] Sending ${ethers.formatEther(shareWei)} ETH to ${traderAddr}...`);
                const tx = await wallet.sendTransaction({
                    to: traderAddr,
                    value: shareWei
                });
                const receipt = await tx.wait();
                log(`[LeaderboardTracker] Payout confirmed: ${tx.hash} (block ${receipt.blockNumber})`);

                successfulPayouts.push({
                    trader: traderAddr,
                    amountWei: shareWei.toString(),
                    amountEth: parseFloat(ethers.formatEther(shareWei)).toFixed(6),
                    txHash: tx.hash,
                    blockNumber: receipt.blockNumber
                });
            } catch (sendErr) {
                log(`[LeaderboardTracker] Failed sending payout to ${traderAddr}: ${sendErr.message}`);
            }
        }

        // 3. Telegram announcement if any payouts succeeded
        if (successfulPayouts.length > 0 && channelBot && channelId) {
            try {
                const totalSentWei = successfulPayouts.reduce((sum, p) => sum + BigInt(p.amountWei), 0n);
                const totalSentEth = parseFloat(ethers.formatEther(totalSentWei)).toFixed(5);
                const lines = successfulPayouts.map(p =>
                    `• \`${p.trader.slice(0, 6)}...${p.trader.slice(-4)}\`: *${p.amountEth} ETH* ([Explorer](https://robinhoodchain.blockscout.com/tx/${p.txHash}))`
                ).join('\n');

                const tgMsg =
                    `🏹 *HOURLY ROBINHOOD ROUTER REDISTRIBUTION* 🏹\n\n` +
                    `The Dev Wallet has automatically distributed *${totalSentEth} ETH* recovered from router \`${routerAddress.slice(0, 6)}...${routerAddress.slice(-4)}\` directly to the traders who used this router!\n\n` +
                    `👥 *Recipients:* ${successfulPayouts.length} real trader(s)\n` +
                    lines +
                    `\n\n🛡️ *100% Transparent:* Zero fees kept by dev. Proportional redistribution to genuine traders.\n` +
                    `🖥️ *Live Leaderboard:* [irlprotocol.xyz](https://irlprotocol.xyz)`;

                channelBot.telegram.sendMessage(channelId, tgMsg, {
                    parse_mode: 'Markdown',
                    disable_web_page_preview: true
                }).catch(e => console.error('[LeaderboardTracker] TG announce error:', e.message));
            } catch (tgErr) {
                console.error('[LeaderboardTracker] TG message build error:', tgErr.message);
            }
        }

        return successfulPayouts;
    }
}

module.exports = { TraderLeaderboardTracker };
