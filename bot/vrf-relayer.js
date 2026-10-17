/**
 * Minimal OpenVRF relayer for the $IRL Hook.
 *
 * The dev wallet is the only authorized OpenVRF relayer, so lottery requests created by
 * Hook.performUpkeep(3/4) are only settled when this module calls OpenVRF.fulfill().
 * It relays EVERY request as soon as its Drand round is published, without looking at the
 * outcome: the random word is fixed by (Drand round, requestId) and cannot be influenced.
 */
const { ethers } = require('ethers');

const CHAIN_HASH = '04f1e9062b8a81f848fded9c12306733282b2727ecced50032187751166ec8c3';
const GENESIS = 1727521075n;
const PERIOD = 3n;
const MAX_CALLBACK_GAS = 1_000_000n;
const DRAND_URLS = (process.env.DRAND_URLS ||
    'https://api.drand.sh,https://api2.drand.sh,https://api3.drand.sh,https://drand.cloudflare.com')
    .split(',').map((u) => u.trim()).filter(Boolean);

const vrfAbi = [
    'function nextRequestId() view returns (uint256)',
    'function requests(uint256) view returns (address consumer,uint64 round,uint32 callbackGasLimit,bool fulfilled,bool delivered,uint256 randomWord,uint256 fee)',
    'function fulfill(uint256 id, bytes signature)',
    'function retryCallback(uint256 id, uint32 callbackGasLimit)'
];

async function fetchDrandSignature(round, log) {
    for (const base of DRAND_URLS) {
        try {
            const res = await fetch(`${base.replace(/\/$/, '')}/${CHAIN_HASH}/public/${round}`, {
                signal: AbortSignal.timeout(10000)
            });
            if (!res.ok) continue;
            const body = await res.json();
            if (String(body.round) !== String(round) || !/^[0-9a-f]{128}$/i.test(body.signature || '')) continue;
            return `0x${body.signature}`;
        } catch (_) {
            log(`[VRF] Drand endpoint failed: ${base}`);
        }
    }
    throw new Error(`No Drand signature available for round ${round}`);
}

const hookIface = new ethers.Interface([
    'event LotteryWinnerDrawn(address indexed winner, uint256 tokenId, uint256 prize)',
    'event SundayMegaJackpotDrawn(address indexed winner, uint256 tokenId, uint256 prize)'
]);

function createVrfRelayer({ provider, wallet, vrfAddress, consumer, log = console.log, onDrawSettled = null }) {
    const vrf = new ethers.Contract(vrfAddress, vrfAbi, wallet);
    let cursor = 1n; // lowest request id not yet confirmed delivered

    async function relayPending() {
        const next = await vrf.nextRequestId();
        if (cursor >= next) return [];
        const now = BigInt((await provider.getBlock('latest')).timestamp);
        const results = [];

        for (let id = cursor; id < next; id++) {
            const req = await vrf.requests(id);
            const done = req.delivered || req.consumer.toLowerCase() !== consumer.toLowerCase();
            if (done) {
                if (id === cursor) cursor = id + 1n;
                continue;
            }
            const readyAt = GENESIS + (req.round - 1n) * PERIOD;
            if (now < readyAt) continue;

            let tx;
            if (!req.fulfilled) {
                const sig = await fetchDrandSignature(req.round, log);
                await vrf.fulfill.staticCall(id, sig);
                const gas = await vrf.fulfill.estimateGas(id, sig);
                log(`[VRF] Fulfilling request ${id} (round ${req.round})...`);
                tx = await vrf.fulfill(id, sig, { gasLimit: (gas * 13n) / 10n });
            } else {
                // Same random word, more callback gas (must be >= the original limit).
                let retryGas = req.callbackGasLimit * 2n;
                if (retryGas > MAX_CALLBACK_GAS) retryGas = MAX_CALLBACK_GAS;
                log(`[VRF] Retrying callback for request ${id} with ${retryGas} gas...`);
                tx = await vrf.retryCallback(id, retryGas, { gasLimit: retryGas + 300_000n });
            }
            const rec = await tx.wait();
            const after = await vrf.requests(id);
            log(`[VRF] Request ${id}: tx ${rec.hash}, delivered=${after.delivered}`);

            // Parse draw event directly from receipt logs for immediate notification
            if (rec && rec.logs && typeof onDrawSettled === 'function') {
                for (const logItem of rec.logs) {
                    try {
                        const parsed = hookIface.parseLog(logItem);
                        if (parsed && (parsed.name === 'LotteryWinnerDrawn' || parsed.name === 'SundayMegaJackpotDrawn')) {
                            log(`[VRF] Detected ${parsed.name} in tx ${rec.hash}, triggering instant announcement...`);
                            await onDrawSettled({
                                name: parsed.name,
                                winner: parsed.args[0],
                                tokenId: parsed.args[1],
                                prize: parsed.args[2],
                                txHash: rec.hash,
                                receipt: rec
                            });
                        }
                    } catch (_) {}
                }
            }

            results.push({ id, hash: rec.hash, delivered: after.delivered });
            if (after.delivered && id === cursor) cursor = id + 1n;
        }
        return results;
    }

    return { relayPending };
}

module.exports = { createVrfRelayer, fetchDrandSignature };
