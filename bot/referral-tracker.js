/**
 * 🏹 Internet Robinhood Lottery ($IRL) — Referral System (Custom Links) & +EV Probability Engine
 *
 * Features:
 * 1. Custom Referral Link Personalization (`https://irlprotocol.xyz/?ref=your-custom-code` or `?ref=0x...`)
 *    - Validates and maps custom slugs (`[a-z0-9_-]{3,24}`) to wallet addresses (`0x...`).
 *    - Allows each wallet to customize its vanity code anytime while preventing hijacking of taken codes.
 * 2. On-Chain + Off-Chain Referral Attribution:
 *    - Extracts 96-byte extended `hookData = abi.encode(trader, referrerAddr, customAliasBytes32)` directly
 *      from Uniswap V4 `UniversalRouter.execute` swap calldata on-chain.
 *    - Tracks referred traders, referred swap volume (ETH), and 25% Protocol Fee Referral Rebates
 *      (0.25% of referred swap volume paid in native ETH) + 10% Leaderboard Score Boost for referees.
 * 3. Real-Time +EV / Probability Alert Generator (English):
 *    - Calculates exact win probabilities (`1 / (N + 1)`) for tonight's Daily Draw + Sunday Mega-Jackpot entry.
 */

const { ethers } = require('ethers');
const fs = require('fs');
const path = require('path');

const ALIAS_REGEX = /^[a-z0-9][a-z0-9_-]{2,23}$/;
const RESERVED_ALIASES = new Set([
    'admin', 'official', 'irl', 'support', 'moderator', 'null', 'undefined', 'system', 'none'
]);

class ReferralAndEvEngine {
    constructor({ stateFilePath, webDistPath } = {}) {
        this.stateFilePath = stateFilePath || path.join(__dirname, 'referrals.json');
        this.webDistPath = webDistPath || null;

        // Maps:
        // aliasToAddress: { "robinhood": "0x1234..." }
        // addressToAlias: { "0x1234...": "robinhood" }
        // refereeToReferrer: { "0xabcd...": "0x1234..." }
        // referrerStats: { "0x1234...": { referredTraders: ["0xabcd..."], totalVolumeWei: "0", totalEarnedWei: "0", paidWei: "0" } }
        this.aliasToAddress = {};
        this.addressToAlias = {};
        this.refereeToReferrer = {};
        this.referrerStats = {};
        this.processedTxs = new Set();

        this.loadState();
    }

    loadState() {
        if (fs.existsSync(this.stateFilePath)) {
            try {
                const raw = JSON.parse(fs.readFileSync(this.stateFilePath, 'utf8'));
                this.aliasToAddress = raw.aliasToAddress || {};
                this.addressToAlias = raw.addressToAlias || {};
                this.refereeToReferrer = raw.refereeToReferrer || {};
                this.referrerStats = raw.referrerStats || {};
                if (Array.isArray(raw.processedTxs)) {
                    this.processedTxs = new Set(raw.processedTxs);
                }
            } catch (err) {
                console.error('[ReferralEngine] Error loading state:', err.message);
            }
        }
    }

    saveState() {
        try {
            const payload = {
                updatedAt: Math.floor(Date.now() / 1000),
                aliasToAddress: this.aliasToAddress,
                addressToAlias: this.addressToAlias,
                refereeToReferrer: this.refereeToReferrer,
                referrerStats: this.referrerStats,
                processedTxs: Array.from(this.processedTxs).slice(-2000)
            };
            fs.writeFileSync(this.stateFilePath, JSON.stringify(payload, null, 2), 'utf8');

            if (this.webDistPath && fs.existsSync(this.webDistPath)) {
                const publicPath = path.join(this.webDistPath, 'referrals.json');
                fs.writeFileSync(publicPath, JSON.stringify(this.getPublicSnapshot(), null, 2), 'utf8');
            }
        } catch (err) {
            console.error('[ReferralEngine] Error saving state:', err.message);
        }
    }

    /**
     * Validates and registers a custom referral code (`?ref=custom_alias`) for a wallet address.
     */
    registerCustomAlias(rawAlias, walletAddress) {
        if (!walletAddress || !ethers.isAddress(walletAddress)) {
            return { ok: false, error: 'Invalid EVM wallet address.' };
        }
        const normalizedAddr = ethers.getAddress(walletAddress).toLowerCase();
        const alias = String(rawAlias || '').trim().toLowerCase();

        if (!ALIAS_REGEX.test(alias)) {
            return {
                ok: false,
                error: 'Custom code must be 3–24 characters using only letters, numbers, dashes (-), or underscores (_).'
            };
        }
        if (alias.startsWith('0x') || RESERVED_ALIASES.has(alias)) {
            return { ok: false, error: 'This referral code is reserved. Please pick another custom handle.' };
        }

        const existingOwner = this.aliasToAddress[alias];
        if (existingOwner && existingOwner.toLowerCase() !== normalizedAddr) {
            return { ok: false, error: `The code "${alias}" is already taken by another wallet.` };
        }

        // Remove previous alias if this wallet had one
        const oldAlias = this.addressToAlias[normalizedAddr];
        if (oldAlias && oldAlias !== alias) {
            delete this.aliasToAddress[oldAlias];
        }

        this.aliasToAddress[alias] = normalizedAddr;
        this.addressToAlias[normalizedAddr] = alias;
        this._ensureReferrerEntry(normalizedAddr);
        this.saveState();

        return {
            ok: true,
            alias,
            wallet: normalizedAddr,
            referralUrl: `https://irlprotocol.xyz/?ref=${alias}`
        };
    }

    /**
     * Resolves either a custom alias (`robinhood`) or a raw wallet address (`0x...`) to a normalized wallet address.
     */
    resolveReferrer(refCodeOrAddress) {
        if (!refCodeOrAddress) return null;
        const clean = String(refCodeOrAddress).trim().toLowerCase();
        if (ethers.isAddress(clean)) {
            return clean;
        }
        // Support composite format `alias:0xAddress` for instant zero-latency resolution
        if (clean.includes(':')) {
            const [slug, addr] = clean.split(':');
            if (ethers.isAddress(addr)) {
                const normAddr = addr.toLowerCase();
                if (ALIAS_REGEX.test(slug) && !this.aliasToAddress[slug]) {
                    this.registerCustomAlias(slug, normAddr);
                }
                return normAddr;
            }
        }
        return this.aliasToAddress[clean] || null;
    }

    _ensureReferrerEntry(addr) {
        const lower = addr.toLowerCase();
        if (!this.referrerStats[lower]) {
            this.referrerStats[lower] = {
                referredTraders: [],
                totalVolumeWei: "0",
                totalEarnedWei: "0",
                paidWei: "0"
            };
        }
        return this.referrerStats[lower];
    }

    /**
     * Links a referee wallet to a referrer (either via alias or wallet address).
     * Self-referrals are strictly rejected. First referrer is locked permanently.
     */
    bindReferee(refereeWallet, refCodeOrAddress) {
        if (!refereeWallet || !ethers.isAddress(refereeWallet)) {
            return { ok: false, error: 'Invalid referee wallet.' };
        }
        const referee = refereeWallet.toLowerCase();
        const referrer = this.resolveReferrer(refCodeOrAddress);
        if (!referrer) {
            return { ok: false, error: 'Unknown referral code or address.' };
        }
        if (referee === referrer) {
            return { ok: false, error: 'Self-referral is not allowed.' };
        }

        if (this.refereeToReferrer[referee]) {
            return {
                ok: true,
                alreadyBound: true,
                referee,
                referrer: this.refereeToReferrer[referee],
                referrerAlias: this.addressToAlias[this.refereeToReferrer[referee]] || null
            };
        }

        this.refereeToReferrer[referee] = referrer;
        const entry = this._ensureReferrerEntry(referrer);
        if (!entry.referredTraders.includes(referee)) {
            entry.referredTraders.push(referee);
        }
        this.saveState();

        return {
            ok: true,
            alreadyBound: false,
            referee,
            referrer,
            referrerAlias: this.addressToAlias[referrer] || null
        };
    }

    /**
     * Decodes extended 96-byte `hookData = abi.encode(trader, referrerAddr, customAliasBytes32)`
     * from a swap transaction's input data (`tx.data`), if present.
     */
    extractReferralFromTxData(txData, humanTrader) {
        if (!txData || typeof txData !== 'string' || txData.length < 200 || !humanTrader) {
            return null;
        }
        try {
            const traderHex = humanTrader.toLowerCase().replace(/^0x/, '').padStart(64, '0');
            const lowerData = txData.toLowerCase();
            const idx = lowerData.indexOf(traderHex);
            if (idx === -1) return null;

            // Check if there is a 96-byte hookData payload starting at `idx`:
            // In ABI encoding of `bytes hookData`, the 32-byte length word precedes `traderHex`.
            // If length is 0x60 (96 bytes), word 0 = trader, word 1 = referrerAddr, word 2 = aliasBytes32.
            const lenWordStart = idx - 64;
            if (lenWordStart < 2) return null;
            const lenHex = lowerData.slice(lenWordStart, idx);
            const byteLen = parseInt(lenHex, 16);
            if (byteLen !== 64 && byteLen !== 96) return null;

            const word1Hex = lowerData.slice(idx + 64, idx + 128);
            if (word1Hex.length !== 64) return null;
            const rawReferrer = '0x' + word1Hex.slice(24);
            let referrerAddr = (ethers.isAddress(rawReferrer) && rawReferrer !== ethers.ZeroAddress)
                ? rawReferrer.toLowerCase()
                : null;

            let extractedAlias = null;
            if (byteLen === 96) {
                const word2Hex = '0x' + lowerData.slice(idx + 128, idx + 192);
                if (word2Hex.length === 66 && word2Hex !== ethers.ZeroHash) {
                    try {
                        extractedAlias = ethers.decodeBytes32String(word2Hex).trim().toLowerCase();
                    } catch (_) {}
                }
            }

            if (extractedAlias && referrerAddr && !this.aliasToAddress[extractedAlias]) {
                this.registerCustomAlias(extractedAlias, referrerAddr);
            } else if (extractedAlias && !referrerAddr) {
                referrerAddr = this.resolveReferrer(extractedAlias);
            }

            return { referrerAddr, alias: extractedAlias };
        } catch (_) {
            return null;
        }
    }

    /**
     * Records a swap's volume for referral accounting.
     * - Referrer earns 0.25% of referred swap volume in native ETH (25% of the 1.00% Protocol Pot share).
     * - Referee receives a +10% Leaderboard Score Boost.
     */
    recordSwapVolume({ txHash, humanTrader, volumeWei, txData = null }) {
        if (!humanTrader || !volumeWei || BigInt(volumeWei) <= 0n) return null;
        const referee = humanTrader.toLowerCase();

        if (txHash && this.processedTxs.has(txHash.toLowerCase())) {
            const existingRef = this.refereeToReferrer[referee];
            return existingRef ? { referrer: existingRef, boostedVolumeWei: (BigInt(volumeWei) * 110n) / 100n } : null;
        }

        // 1. Check if transaction calldata carries an embedded referral tag
        if (!this.refereeToReferrer[referee] && txData) {
            const extracted = this.extractReferralFromTxData(txData, referee);
            if (extracted && (extracted.referrerAddr || extracted.alias)) {
                this.bindReferee(referee, extracted.referrerAddr || extracted.alias);
            }
        }

        const referrer = this.refereeToReferrer[referee];
        if (!referrer || referrer === referee) return null;

        if (txHash) {
            this.processedTxs.add(txHash.toLowerCase());
        }

        const vol = BigInt(volumeWei);
        // 0.25% of swap volume (= 25 bps = 25% of the 1.00% Protocol Pot)
        const rewardWei = (vol * 25n) / 10000n;
        const entry = this._ensureReferrerEntry(referrer);
        if (!entry.referredTraders.includes(referee)) {
            entry.referredTraders.push(referee);
        }
        entry.totalVolumeWei = (BigInt(entry.totalVolumeWei || "0") + vol).toString();
        entry.totalEarnedWei = (BigInt(entry.totalEarnedWei || "0") + rewardWei).toString();

        this.saveState();

        return {
            referrer,
            referrerAlias: this.addressToAlias[referrer] || null,
            rewardWei,
            boostedVolumeWei: (vol * 110n) / 100n // +10% Leaderboard score boost for referred trader
        };
    }

    getPublicSnapshot() {
        const leaderboard = Object.entries(this.referrerStats)
            .map(([addr, st]) => {
                const volWei = BigInt(st.totalVolumeWei || "0");
                const earnedWei = BigInt(st.totalEarnedWei || "0");
                const alias = this.addressToAlias[addr] || null;
                return {
                    address: addr,
                    shortAddress: `${addr.slice(0, 6)}...${addr.slice(-4)}`,
                    alias,
                    displayHandle: alias ? `@${alias}` : `${addr.slice(0, 6)}...${addr.slice(-4)}`,
                    referralLink: `https://irlprotocol.xyz/?ref=${alias || addr}`,
                    referredCount: (st.referredTraders || []).length,
                    totalVolumeWei: volWei.toString(),
                    totalVolumeEth: parseFloat(ethers.formatEther(volWei)).toFixed(4),
                    totalEarnedEth: parseFloat(ethers.formatEther(earnedWei)).toFixed(5)
                };
            })
            .filter(item => item.referredCount > 0 || item.alias !== null)
            .sort((a, b) => (BigInt(b.totalVolumeWei) > BigInt(a.totalVolumeWei) ? 1 : -1));

        return {
            updatedAt: Math.floor(Date.now() / 1000),
            aliasToAddress: this.aliasToAddress,
            addressToAlias: this.addressToAlias,
            refereeToReferrer: this.refereeToReferrer,
            topReferrers: leaderboard.slice(0, 25)
        };
    }

    /**
     * Computes live +EV & win probability metrics for tonight's Daily Draw + Sunday Mega-Jackpot.
     */
    static computeEvAlertStats({
        dailyTicketsInPlay = 0,
        sundayTicketsInPlay = 0,
        dailyPotEth = "0.0043",
        sundayPotEth = "0.7003",
        hourlyPotEth = "0.0030",
        ethPriceUsd = 2640,
        dayStartTicketId = 0,
        dayEndTicketId = 0
    } = {}) {
        const activeDaily = Math.max(0, Number(dailyTicketsInPlay) || 0);
        const activeSunday = Math.max(activeDaily, Number(sundayTicketsInPlay) || 0);
        const dPot = Math.max(0, parseFloat(dailyPotEth) || 0);
        const sPot = Math.max(0, parseFloat(sundayPotEth) || 0);
        const hPot = Math.max(0, parseFloat(hourlyPotEth) || 0);

        const oneTicketDailyOddsPct = (1 / (activeDaily + 1)) * 100;
        const threeTicketsDailyOddsPct = (3 / (activeDaily + 3)) * 100;
        const sixTicketsDailyOddsPct = (6 / (activeDaily + 6)) * 100;

        const oneTicketSundayOddsPct = (1 / (activeSunday + 1)) * 100;
        const combinedJackpotEth = dPot + sPot;
        const sundayUsd = Math.round(sPot * ethPriceUsd);
        const dailyUsd = Math.round(dPot * ethPriceUsd);
        const combinedUsd = Math.round(combinedJackpotEth * ethPriceUsd);

        const ticketRangeStr = (dayStartTicketId > 0 && dayEndTicketId >= dayStartTicketId)
            ? `(#${dayStartTicketId} to #${dayEndTicketId})`
            : '';

        return {
            dailyTicketsInPlay: activeDaily,
            sundayTicketsInPlay: activeSunday,
            ticketRangeStr,
            dailyPotEth: dPot.toFixed(4),
            sundayPotEth: sPot.toFixed(4),
            hourlyPotEth: hPot.toFixed(4),
            combinedJackpotEth: combinedJackpotEth.toFixed(4),
            dailyUsd,
            sundayUsd,
            combinedUsd,
            oneTicketDailyOddsPct: oneTicketDailyOddsPct.toFixed(1),
            threeTicketsDailyOddsPct: threeTicketsDailyOddsPct.toFixed(1),
            sixTicketsDailyOddsPct: sixTicketsDailyOddsPct.toFixed(1),
            oneTicketSundayOddsPct: oneTicketSundayOddsPct.toFixed(2),
            isHighEvOpportunity: activeDaily < 25
        };
    }

    /**
     * Builds the English Telegram +EV Probability Alert message.
     */
    static buildTelegramEvAlertMessage(stats) {
        const s = stats.oneTicketDailyOddsPct ? stats : ReferralAndEvEngine.computeEvAlertStats(stats);
        const rangeText = s.ticketRangeStr ? ` ${s.ticketRangeStr}` : '';

        return (
            `🚨 *PROBABILITY & +EV ALERT — $IRL DAILY LOTTERY* 🚨\n\n` +
            `Only *${s.dailyTicketsInPlay} ticket${s.dailyTicketsInPlay === 1 ? '' : 's'}* in play today${rangeText}!\n` +
            `Minting *1 ticket* right now gives you a *${s.oneTicketDailyOddsPct}% chance* (1 in ${s.dailyTicketsInPlay + 1}) to win tonight's *00:00 UTC Daily Draw* + an automatic entry for Sunday's *${s.sundayPotEth} ETH (~$${s.sundayUsd.toLocaleString()}) Mega-Jackpot*!\n\n` +
            `🎯 *LIVE WIN PROBABILITY BREAKDOWN:*\n` +
            `• 🎟️ *Mint 1 Ticket (0.10 ETH vol)*: *${s.oneTicketDailyOddsPct}% Chance* tonight!\n` +
            `• 🎟️ *Mint 3 Tickets (0.30 ETH vol)*: *${s.threeTicketsDailyOddsPct}% Chance* tonight!\n` +
            `• 🎟️ *Mint 6 Tickets (0.60 ETH vol)*: *${s.sixTicketsDailyOddsPct}% Chance* tonight!\n\n` +
            `💰 *ACTIVE ON-CHAIN PRIZE POOLS:*\n` +
            `• 🌟 *Sunday Mega-Jackpot*: *${s.sundayPotEth} ETH* (~$${s.sundayUsd.toLocaleString()})\n` +
            `• 🏆 *Today's Daily Pot*: *${s.dailyPotEth} ETH* (Grows on every swap & P2P trade!)\n` +
            `• ⚡ *Hourly Trader Cashback*: *0.4375% Instant ETH Cashback* + *Top 10 Pool*\n\n` +
            `🏹 *Trade now on* https://irlprotocol.xyz so your wallet is encoded in V4 \`hookData\` and NFT tickets mint directly to YOU!`
        );
    }
}

module.exports = { ReferralAndEvEngine };
