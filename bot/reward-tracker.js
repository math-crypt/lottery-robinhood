/**
 * Reward ledger for the $IRL Hook, rebuilt from on-chain events.
 *
 * Classifies every ETH reward the Hook has tried to pay (hourly payouts + lottery prizes):
 *   - locked      : credited to unclaimedRewards[recipient] because the recipient rejected ETH
 *                   (e.g. UniversalRouter). Net of any later claimUnclaimedRewards().
 *   - toContracts : delivered to a smart contract (router / aggregator / trading bot).
 *   - toWallets   : delivered to a regular wallet (EOA).
 *
 * Note: "locked" is ETH held inside the Hook that no known path can release. It is NOT a burn
 * of $IRL supply.
 */
const { ethers } = require('ethers');

const LAUNCH_BLOCK = 88826214;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const iface = new ethers.Interface([
    'event UserRewarded(address indexed user, uint256 amount)',
    'event UnclaimedRewardRecorded(address indexed recipient, uint256 amount)',
    'event UnclaimedRewardClaimed(address indexed recipient, uint256 amount)',
    'event LotteryWinnerDrawn(address indexed winner, uint256 tokenId, uint256 prize)',
    'event SundayMegaJackpotDrawn(address indexed winner, uint256 tokenId, uint256 prize)'
]);
const TOPICS = ['UserRewarded', 'UnclaimedRewardRecorded', 'UnclaimedRewardClaimed', 'LotteryWinnerDrawn', 'SundayMegaJackpotDrawn']
    .map((name) => iface.getEvent(name).topicHash);

function createRewardTracker({ provider, hookAddress, fromBlock = LAUNCH_BLOCK, chunk = 50000, log = console.log }) {
    const codeCache = new Map();
    const locked = new Map();
    const state = { nextBlock: fromBlock, toContracts: 0n, toWallets: 0n };
    let syncing = null;

    async function isContract(addr) {
        const key = addr.toLowerCase();
        if (!codeCache.has(key)) codeCache.set(key, (await provider.getCode(addr)) !== '0x');
        return codeCache.get(key);
    }

    async function credit(addr, amount) {
        if (await isContract(addr)) state.toContracts += amount;
        else state.toWallets += amount;
    }

    async function processLogs(logs) {
        const parsed = [];
        for (const l of logs) {
            try { parsed.push({ ev: iface.parseLog(l), tx: l.transactionHash }); } catch (_) {}
        }
        // Lottery prizes that failed also emit UnclaimedRewardRecorded in the same tx.
        const failedInTx = new Set(parsed
            .filter((p) => p.ev.name === 'UnclaimedRewardRecorded')
            .map((p) => `${p.tx}:${p.ev.args[0].toLowerCase()}`));

        for (const { ev, tx } of parsed) {
            const addr = ev.args[0];
            const key = addr.toLowerCase();
            switch (ev.name) {
                case 'UserRewarded':
                    await credit(addr, ev.args[1]);
                    break;
                case 'UnclaimedRewardRecorded':
                    locked.set(key, (locked.get(key) || 0n) + ev.args[1]);
                    break;
                case 'UnclaimedRewardClaimed':
                    locked.set(key, (locked.get(key) || 0n) - ev.args[1]);
                    break;
                default: // LotteryWinnerDrawn / SundayMegaJackpotDrawn
                    if (!failedInTx.has(`${tx}:${key}`)) await credit(addr, ev.args[2]);
            }
        }
    }

    async function doSync() {
        const latest = await provider.getBlockNumber();
        let size = chunk;
        while (state.nextBlock <= latest) {
            const to = Math.min(state.nextBlock + size - 1, latest);
            try {
                const logs = await provider.getLogs({
                    address: hookAddress, fromBlock: state.nextBlock, toBlock: to, topics: [TOPICS]
                });
                await processLogs(logs);
                state.nextBlock = to + 1;
                size = chunk;
                await sleep(250);
            } catch (err) {
                if (size > 1000) {
                    size = Math.floor(size / 2);
                    await sleep(1000);
                    continue;
                }
                log(`[Ledger] getLogs failed at ${state.nextBlock}: ${err.shortMessage || err.message}`);
                await sleep(3000);
                return;
            }
        }
    }

    async function sync() {
        if (!syncing) syncing = doSync().finally(() => { syncing = null; });
        await syncing;
        return summary();
    }

    function summary() {
        const lockedList = [...locked.entries()].filter(([, v]) => v > 0n).sort((a, b) => (b[1] > a[1] ? 1 : -1));
        const lockedTotal = lockedList.reduce((s, [, v]) => s + v, 0n);
        return { lockedTotal, lockedList, toContracts: state.toContracts, toWallets: state.toWallets, syncedTo: state.nextBlock - 1 };
    }

    return { sync, summary };
}

module.exports = { createRewardTracker, LAUNCH_BLOCK };
