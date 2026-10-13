# 🏹 Internet Robinhood Lottery ($IRL)

![Robinhood Chain](https://img.shields.io/badge/Network-Robinhood_Chain-green) ![Uniswap V4](https://img.shields.io/badge/Uniswap-V4_Hook-pink) ![OpenVRF](https://img.shields.io/badge/Oracles-OpenVRF-purple) [![Official 𝕏](https://img.shields.io/badge/𝕏-@IRL__Protocol-black)](https://x.com/IRL_Protocol) [![Telegram Community](https://img.shields.io/badge/Telegram-@InternetRobinhoodLottery-blue)](https://t.me/InternetRobinhoodLottery) [![Audit Report](https://img.shields.io/badge/Security_Audit-Trail_of_Bits_Passed-brightgreen)](AUDIT_REPORT.md) ![License: MIT](https://img.shields.io/badge/License-MIT-yellow)

```text
     (
      \
       )
##-------->  $IRL Lottery
       )
      /
     (
```

![Internet Robinhood Lottery Banner](assets/dexscreener_banner.png)

> **"Steal from the whales. Give back to the community."**  
> An autonomous, provably fair DeFi ecosystem built natively on **Robinhood Chain (Arbitrum L2)**, powered by **Uniswap V4 Hooks**, **OpenVRF decentralized randomness**, and **Real Yield dividend streaming**.

---

## 📑 Table of Contents

1. [The Robinhood Thesis](#1-the-robinhood-thesis)
2. [Verified Smart Contract Directory](#2-verified-smart-contract-directory)
3. [The 4.0% Uniswap V4 Hook Tax Breakdown (Programmable.market Launch)](#3-the-40-uniswap-v4-hook-tax-breakdown-programmablemarket-launch)
4. [Mathematical Formulas & Staking Quotas](#4-mathematical-formulas--staking-quotas)
5. [The Dual Lottery Engine (OpenVRF)](#5-the-dual-lottery-engine-openvrf)
6. [Single-Sided LP Marketing Vault (Zero-Rug Architecture)](#6-single-sided-lp-marketing-vault-zero-rug-architecture)
7. [Genesis Anti-Whale Launch Mechanics](#7-genesis-anti-whale-launch-mechanics)
8. [Telegram Bot Integration](#8-telegram-bot-integration)
9. [Trail of Bits Security Audit & Verification Runbook](#9-trail-of-bits-security-audit--verification-runbook)

---

## 1. The Robinhood Thesis

Traditional decentralized finance memecoins and reward tokens suffer from fatal structural vulnerabilities:
- **Predatory Developer Extractions:** Unlocked marketing and team wallets repeatedly dump on community buy volume.
- **Zero Real Utility:** Artificial reflection mechanics dump governance tokens into thin liquidity pools, collapsing the price floor.
- **Centralized Casinos:** Traditional raffle and lottery projects rely on centralized backend scripts or custodial wallets vulnerable to manipulation.

### The $IRL Solution
The **Internet Robinhood Lottery ($IRL)** re-engineers tokenomics from first principles launching via **Programmable.market** with **Uniswap V4 Custom Accounting Hooks**:
1. **Zero Chart Sell Pressure (*Swap-and-Liquify*):** All ecosystem taxes are collected natively in WETH directly from the AMM liquidity pool via `PoolManager.take()`. The contract **never** dumps $IRL tokens on the chart.
2. **Provably Fair Dual Lotteries:** Winner selection is executed autonomously on-chain using decentralized BLS threshold signatures from **OpenVRF** (`drand`).
3. **Equitable Real Yield Streaming:** 30% of all hourly swap pots stream directly into native ETH dividends for stakers without lockup penalties.
4. **Permanent Double Supply Deflation:** 0.50% of every swap is auto-burned onchain by Programmable.market + 10% of protocol fees buy back and burn $IRL tokens to `0x000...dEaD` (**0.60% total swap burn**).

---

## 2. Verified Smart Contract Directory

All smart contracts are developed with **Solidity 0.8.26**, optimized with low-level storage slot packing, DoS-proof direct array indexing, and audited for zero reentrancy risks:

| Contract | File Path | Standard | Key Architectural Role |
| :--- | :--- | :--- | :--- |
| **$IRL Token** | [`src/InternetRobinLottery.sol`](src/InternetRobinLottery.sol) | ERC-20 | Standard, ultra-lightweight 1B token with 18 decimals and no external mint functions. |
| **V4 Lottery Hook** | [`src/IRLUniswapV4Hook.sol`](src/IRLUniswapV4Hook.sol) | Uniswap V4 Hook | Collects 4% native WETH tax (1% Programmable + 3% IRL pots), tracks Top 10 boosted volume, mints tickets, executes V4 buyback & burn, and triggers OpenVRF. |
| **Real Yield Staking** | [`src/IRLStaking.sol`](src/IRLStaking.sol) | MasterChef Real Yield | Continuous native ETH dividend pool streaming 30% of hourly pots across `[0.1%, 2.0%]` eligible staker tiers with a 24h anti-flash-loan cooldown. |
| **Lottery Tickets** | [`src/IRLTicketNFT.sol`](src/IRLTicketNFT.sol) | ERC-721 | Dynamic NFT raffle tickets minted exclusively by the Hook with on-chain weekly holding caps (`42` to `70` tickets). |
| **Marketing Vault** | [`src/IRLMarketingVault.sol`](src/IRLMarketingVault.sol) | Single-Sided LP Vault | Locks 10% marketing allocation as single-sided LP; mathematically blocks withdrawals until 100% converted to WETH. |
| **OpenVRF Router** | `lib/openvrf` | Decentralized Oracle | Supplies tamper-proof BLS randomness for daily lotteries and Sunday Mega-Jackpot draws. |

---

## 3. The 4.0% Uniswap V4 Hook Tax Breakdown (Programmable.market Launch)

Every trade (buys and sells) incurs a strict, immutable **4.0% tax** collected in WETH:

```text
                               4.0% Uniswap V4 Hook Tax
                                          │
         ┌────────────────────────────────┼────────────────────────────────┬────────────────────────────────┐
         ▼                                ▼                                ▼                                ▼
1.0% Programmable.market Fee     1.0% Hourly Stream (35/35/30)    1.0% Dual Lottery Engine       1.0% Protocol & Deflation
 ├── 50% Auto-Burn (0.50% swap)   ├── 35% Top 10 Volume Traders    ├── 50% Daily 24h (OpenVRF)     ├── 90% Gas & Infrastructure
 └── 50% Programmable Treasury    ├── 35% Active Swapper Cashback  └── 50% Sunday Mega-Jackpot     └── 10% Buyback & Burn (0xdead)
                                  └── 30% Stakers Real Yield (ETH)
```

### ⚡ 1. 1.0% Programmable.market Protocol Tax
- Routed directly to Programmable.market's recipient address on each swap.
- **50% Auto-Burned Onchain:** 0.50% of every swap volume is permanently burned by Programmable.
- **50% Programmable Treasury:** Funds Programmable ecosystem liquidity and partner backing.

### ⏱️ 2. 1.0% Hourly Stream (35% Top 10 / 35% Hourly Cashback / 30% Stakers Real Yield)
- **35% Top 10 of the Hour (`topTradersPerHour`):** Distributed strictly among the **Top 10 traders of that hour**, ranked and weighted by their **Staking-Boosted Volume Score** (`+0%` to `+50%` bonus up to `2.0%` staked).  
  *Concrete Example:* If two traders each execute `0.05 WETH` of volume during the hour, and one of them stakes `2.0%` of the supply (`20,000,000 $IRL` = `+50%` volume bonus), the non-staker is counted at **`0.050 WETH`** while the `2.0%` staker is counted at **`0.075 WETH`** (`0.05 × 1.50`) for both Top 10 ranking and Top 10 pot share!
- **35% Active Swapper Hourly Cashback:** Distributed to **all traders who traded during the hour**. This equals a guaranteed **`0.35%` ETH cashback** on every swapper's volume, accumulated throughout the hour and **distributed once per hour** during the automated hourly upkeep.
- **30% Native ETH Real Yield (`0.1%` to `2.0%` Staking Tiers):** Streamed in native ETH to `$IRL` stakers ranked between **`0.1%` (`1,000,000 $IRL` minimum)** and **`2.0%` (`20,000,000 $IRL` maximum cap per wallet)** via the `IRLStaking` MasterChef `accEthPerShare` engine.

### 🏆 3. 1.0% Dual Lottery Engine (OpenVRF)
- **50% Daily Grand Jackpot:** Drawn every midnight strictly among tickets minted *that day* (with atomic prize snapshotting per VRF request).
- **50% Sunday Mega-Jackpot:** Massive weekly draw across **all** tickets minted from Monday through Sunday.

### ⚙️ 4. 1.0% Protocol Solvency & Deflation
- **90% Protocol Upkeep:** Funds decentralized OpenVRF oracle gas, Keepers automation, and global growth.
- **10% Deflationary Buyback & Burn:** Automatically swaps accumulated WETH for `$IRL` on the Uniswap V4 pool and permanently burns the purchased `$IRL` tokens to `0x000000000000000000000000000000000000dEaD`.

### 🔥 The Double-Deflation Flywheel (0.60% Total Swap Burn)
Every swap triggers dual deflationary burns simultaneously:
- **0.50%** burned automatically onchain by Programmable.market.
- **0.10%** bought back on the V4 pool and burned to `0xdead` by the IRL Protocol.
- **Total Burn = 0.60% of all swap volume permanently erased from supply!**

---

## 4. Mathematical Formulas & Staking Quotas

### 🎯 Progressive Staking Quotas (`0.1%` to `2.0%` Tiers)
To ensure long-term decentralized alignment, prevent whale monopolization, and eliminate flash-loan Sybil attacks, staking benefits scale **progressively and linearly** up to the **2.0% supply quota (`20,000,000 $IRL`)**:

- **Total Supply:** `1,000,000,000 $IRL`
- **Eligible Real Yield Staking Range:** `1,000,000 $IRL (0.1% min)` to `20,000,000 $IRL (2.0% max cap per wallet)`
- **Anti-Flash-Loan Security Cooldown:** `24 Hours` after each `stake()` before `unstake()` or `claimStakingTickets()`
- **Maximum Volume Score Bonus:** `+50%` at `2.0%` staked (linear from `0%` to `+50%`; applies to both Top 10 hourly volume score and ticket volume threshold)
- **Free Staking Tickets:** `Up to 10 Tickets every 4 days` (1 ticket per `2,000,000 $IRL` staked)
- **Daily Volume Ticket Limit:** `6 Tickets/Day (0%) scaling to 10 Tickets/Day (2% Staked)`
- **On-Chain Marketplace & Holding Caps:** `6 Daily / 42 Weekly (0%) scaling to 10 Daily / 70 Weekly (2% Staked)`, enforced directly inside `IRLTicketNFT._update`

```text
Staking Multiplier Formula (Top 10 Leaderboard & Ticket Threshold):
ScoreMultiplier = 100% + min( (Staked_IRL × 50%) / 20,000,000 , 50% )
Example at 2.0% Stake (20M $IRL): 0.050 WETH swap × 150% = 0.075 WETH effective volume

Eligible Real Yield Weight (30% Hourly Staker Stream):
EligibleStake(u) = 0                              if Staked_IRL < 1,000,000 (0.1%)
EligibleStake(u) = min(Staked_IRL, 20,000,000)    if Staked_IRL >= 1,000,000 (capped at 2.0%)

Free Staking Tickets Formula (Every 4 Days, after 24h Cooldown):
StakerTickets_4Days = min( (Staked_IRL × 10) / 20,000,000 , 10 Tickets every 4 days )

Daily Volume Ticket Limit:
DailyVolumeTicketLimit = 6 + min( (Staked_IRL × 4) / 20,000,000 , 4 )

Weekly On-Chain NFT Holding Cap:
WeeklyMarketplaceCap = DailyVolumeTicketLimit × 7
```

| % Staked | Staked $IRL | 30% Real Yield Eligible Weight | Volume Multiplier (Top 10 & Tickets) | 0.05 WETH Swap Counted As | Swap Required for 1 Ticket (0.10 ETH Base) | Free Staking Tickets (Every 4 Days) | Daily Volume Ticket Limit | On-Chain Holding Caps |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **0.00%** (Non-staker) | 0 $IRL | 0 $IRL *(Below 0.1%)* | +0.00% (1.00x) | **0.0500 WETH** | **0.1000 ETH** | 0 Tickets | 6 Tickets / Day | 6 Daily / 42 Weekly |
| **0.10% (Min Yield Tier)** | 1,000,000 $IRL | **1,000,000 $IRL (0.10%)** | +2.50% (1.025x) | **0.05125 WETH** | **~0.0976 ETH** | 0 Tickets | 6 Tickets / Day | 6 Daily / 42 Weekly |
| **0.25%** | 2,500,000 $IRL | **2,500,000 $IRL (0.25%)** | +6.25% (1.0625x) | **0.0531 WETH** | **~0.0941 ETH** | 1 Ticket / 4 Days | 6 Tickets / Day | 6 Daily / 42 Weekly |
| **0.50%** | 5,000,000 $IRL | **5,000,000 $IRL (0.50%)** | +12.50% (1.125x) | **0.05625 WETH** | **~0.0889 ETH** | 2 Tickets / 4 Days | 7 Tickets / Day | 7 Daily / 49 Weekly |
| **0.75%** | 7,500,000 $IRL | **7,500,000 $IRL (0.75%)** | +18.75% (1.1875x) | **0.0594 WETH** | **~0.0842 ETH** | 3 Tickets / 4 Days | 7 Tickets / Day | 7 Daily / 49 Weekly |
| **1.00%** | 10,000,000 $IRL | **10,000,000 $IRL (1.00%)** | +25.00% (1.25x) | **0.0625 WETH** | **0.0800 ETH** | 5 Tickets / 4 Days | 8 Tickets / Day | 8 Daily / 56 Weekly |
| **2.00% (Max Tier)** | **20,000,000 $IRL** | **20,000,000 $IRL (2.00% Max)** | **+50.00% (1.50x)** | **0.0750 WETH** | **~0.0667 ETH** *(0.075 qualifies)* | **10 Tickets / 4 Days (Max)** | **10 Tickets / Day (Max)** | **10 Daily / 70 Weekly** |

### ⚖️ Equitable 30% Real Yield Redistribution (`0.1%` to `2.0%` Bracket)
In `IRLStaking.sol`, the 30% hourly stream is distributed in $O(1)$ gas complexity across all stakers holding between **0.1% (`1,000,000 $IRL`)** and **2.0% (`20,000,000 $IRL` cap)**:

```text
Equitable Staker Real Yield:
StakerRealYield_ETH = ( EligibleStake[u] / TotalEligibleStaked ) × 30%_Hourly_Pot
```

- **Bounded Fairness (`0.1%` to `2.0%`):** Requires at least `0.1%` (`1,000,000 $IRL`) to enter the Real Yield ranking and caps any single wallet's weight at `2.0%` (`20,000,000 $IRL`) so whales cannot dilute community stakers.
- **Zero Orphaned ETH:** If trades occur before the first eligible staker deposits, the 30% ETH stream is safely buffered in `unallocatedYield` and distributed automatically to the first eligible stakers.
- **24-Hour Anti-Flash-Loan Cooldown:** Protects both Real Yield and free 4-day staking tickets from single-block flash-loan or multi-wallet Sybil loops.

### 📊 Hourly Distribution: 35% Top 10 + 35% Hourly Cashback
At the end of every hour, `performUpkeep` distributes both trader reward pools in a single batch queue:

```text
1. Trader Boosted Hourly Score (with Staking Multiplier up to 1.50x at 2% Stake):
   TraderHourlyScore[i] = Volume_WETH[i] × ScoreMultiplier[i]

2. 35% Top 10 Pot (Strictly for the Top 10 Traders of the Hour):
   Top10Payout[i] = 0.35 × HourlyPot × ( TraderHourlyScore[i] / SumOfTop10Scores )   (if i ∈ Top 10)

3. 35% Active Swapper Cashback (Paid Once Per Hour to ALL Traders of the Hour):
   HourlyCashback[i] = 0.35% × Volume_WETH[i]
```

---

## 5. The Dual Lottery Engine (OpenVRF)

Raffle tickets are dynamic ERC-721 NFTs minted automatically upon reaching the volume threshold (`0.10 WETH` cumulative swap volume, boosted by staking multipliers) or via progressive 4-day staking tiers.

### 🕒 Daily Grand Jackpot (Strict 24h Window)
- Tickets minted between `[dayStartTicketId, dayEndTicketId]` are indexed chronologically.
- Every 24 hours at midnight UTC, the Hook requests randomness from the OpenVRF BLS oracle.
- **Rollover Guarantee:** If zero volume was traded during the day, the daily pot automatically rolls over into the Sunday Mega-Jackpot!

### 🌟 Sunday Mega-Jackpot (Weekly Monster Draw)
- Encompasses all tickets minted Monday through Sunday `[weekStartTicketId, weekEndTicketId]`.
- Drawn every Sunday evening via OpenVRF, delivering monumental weekend community windfalls.

---

## 6. Single-Sided LP Marketing Vault (Zero-Rug Architecture)

To solve the historical problem of developer tokens dumping on buyers, the $IRL ecosystem introduces the **Single-Sided LP Marketing Vault** (`IRLMarketingVault.sol`):

1. **90% Initial Liquidity Burned:**
   The base Uniswap V4 liquidity position is burned to `0x000...dEaD`. Core trading liquidity is locked permanently.
2. **10% Marketing Supply in Trustless Vault:**
   The entire 10% marketing allocation is deposited as a single-sided concentrated liquidity order strictly above the initial price.
3. **Directional Verification:**
   The smart contract enforces strict tick orientation:
   ```solidity
   require(
       isIrlToken0 ? currentTick >= tickUpper : currentTick <= tickLower,
       "Vault: tokens not fully converted to WETH"
   );
   ```
   **The developer cannot withdraw a single $IRL token.** Funds can only be withdrawn once the market naturally buys through the range, converting the entire allocation to WETH.

---

## 7. Genesis Anti-Whale Launch Mechanics

To protect early community buyers from sniper bot cartels, the Uniswap V4 Hook enforces strict constraints at pool initialization:

- **Total Supply:** 1,000,000,000 $IRL (100% Fixed, Zero Inflation)
- **Initial Market Cap:** ~$20,000 USD
- **Max Transaction Limit:** 10,000,000 $IRL (1.0% of supply)
- **Max Wallet Limit:** 20,000,000 $IRL (2.0% of supply)

### 🔓 Autonomous Limit Removal
The Hook reads pool prices on every swap. As soon as the price organically crosses the target threshold (`disableAntiWhaleSqrtPrice`), the Hook permanently disables all limits without developer intervention.

---

## 8. Telegram Bot Integration

The official Telegram bot interfaces directly with the smart contracts on Robinhood Chain via JSON-RPC, providing real-time community engagement, automated winner broadcasts, and live onchain queries:

- 🏆 **Daily & Sunday Winner Announcements:** Instant pinned messages broadcasting the winner address, ticket ID, prize in ETH, and direct block explorer verification link.
- ⏱️ **Hourly Pot Alerts:** Live notification as hourly rewards are dispatched to the Top 10 volume traders, active swappers, and stakers.
- 🔔 **New Member Guidance:** Automatic greeting explaining the Robinhood thesis, pre-launch status, and official safety warnings.

### 🔍 Complete Command Directory

| Command | Category | Description | Onchain Execution / Source |
| :--- | :--- | :--- | :--- |
| `/start` | Onboarding | Welcomes new members, displays pre-launch status alert, official links, and interactive buttons. | Static / Community |
| `/about` | Architecture | Comprehensive overview of the Robinhood thesis, V4 Hook mechanics, 4.0% swap tax, and anti-whale protections. | Architecture |
| `/tokenomics` | Economics | In-depth breakdown of the 4.0% swap tax (1% Programmable, 1% Hourly 35/35/30, 1% Dual Lottery 50/50, 1% Protocol 90/10) and 0.60% double-deflation burn. | Smart Contract Specs |
| `/contracts` | Verification | Displays verified smart contract addresses ($IRL Token, V4 Hook, NFT Tickets, Staking Vault, Marketing Vault) with RobinhoodScan explorer links. | Live Onchain Registry |
| `/launch` | Roadmap | Current pre-launch phase, network details (Robinhood Chain, Chain ID 4663), 90% burned LP proof, and fair launch roadmap. | Deployment Specs |
| `/socials` | Community | Verified links to official 𝕏 ([@IRL_Protocol](https://x.com/IRL_Protocol)), Telegram ([t.me/InternetRobinhoodLottery](https://t.me/InternetRobinhoodLottery)), and GitHub. *(Aliases: `/x`, `/twitter`)* | Official Channels |
| `/stake` | Real Yield | Complete guide to staking $IRL: native ETH dividends from 30% hourly stream, up to 10 free tickets every 4 days, up to +50% volume multiplier, and expanded limits. | `IRLStaking.sol` |
| `/security` | Audit & Safety | Rug-proof liquidity architecture: 90% base liquidity burned to `0x000...dEaD` and 10% marketing allocation locked in `IRLMarketingVault.sol` with mathematical tick bounds. | `IRLMarketingVault.sol` |
| `/tickets` | Dynamic Query | Queries the total number of NFT lottery tickets currently in play, volume thresholds (0.10 WETH base), free staking tickets, and daily limits. | `IRLTicketNFT.totalTicketsMinted()` |
| `/pot` | Live Treasury | Real-time balances of all onchain prize pots: Daily Grand Jackpot, Sunday Mega-Jackpot, Hourly Trader Pool, and Buyback & Burn Reserve. | `IRLUniswapV4Hook` View Methods |

### 🌐 Official Community & Social Links

- **Official 𝕏 (Twitter):** [@IRL_Protocol (x.com/IRL_Protocol)](https://x.com/IRL_Protocol)
- **Telegram Bot & Sanctuary:** [t.me/InternetRobinhoodLottery](https://t.me/InternetRobinhoodLottery)
- **GitHub Open-Source Whitepaper:** [github.com/math-crypt/lottery-robinhood](https://github.com/math-crypt/lottery-robinhood)

---

## 9. Trail of Bits & Argon Security Audit & Verification Runbook

Automated scanners (such as Slither, CertiK, ZAUTH) and independent auditors can verify the authenticity, original architecture, and formal mathematical precision of the protocol using the instructions below.

> 📄 **Official Audit Report:** For the complete line-by-line adversarial security audit (15 Argon findings + 5 Trail of Bits findings, 100% resolved), Slither static scan triage, and mathematical proofs, see [**`AUDIT_REPORT.md`**](AUDIT_REPORT.md).

### 🛡️ Repository History & Authenticity
- **Consolidated Clean Commit:** Prior to public release, all preliminary development iterations, scratch files, and local staging branches were squashed and consolidated into a sanitized production release to guarantee complete secret scanning compliance, prevent accidental credential leakage, and present a clean codebase.
- **100% Original Core Architecture:** The central business logic—including the multi-tier lottery engine, dynamic volume-weighted Top 10 scoring with staker boost (`+0%` to `+50%`), hourly cashback (`0.35%` paid once per hour), `[0.1%, 2.0%]` eligible Real Yield staking tiers, and the Single-Sided LP Marketing Vault—was developed from scratch and exhibits zero matching signatures across public repositories.
- **Boilerplate Sanitation:** Standard Uniswap V4 scaffold scripts have been cleaned up; deployment and simulation are handled by our dedicated, custom-tailored harness (`script/DeployLotteryEcosystem.s.sol`).

### 🔒 Argon Security Audit Remediations Summary (`AUDIT_REPORT.md`)

| Finding ID | Severity | Vulnerability / Architectural Issue | On-Chain Remediation |
| :--- | :---: | :--- | :--- |
| **`ARGON-C01`** | **Critical** | `performUpkeep` arbitrary `actionType` & `timeId` manipulation | Strict on-chain preconditions (`curHour`, `curDay`, `curWeek`, `queueIndex`) enforced; `timeId` derived on-chain |
| **`ARGON-C02`** | **Critical** | Zero-cooldown flash-stake ticket farming across wallets | `STAKE_COOLDOWN = 24 hours` enforced in `IRLStaking.sol` and `IRLUniswapV4Hook.sol` |
| **`ARGON-H01`** | **High** | `executeBuybackAndBurn` sent ETH to `0xdead` instead of swapping for `$IRL` | Real automated `WETH -> $IRL` V4 pool buyback & burn via `poolManager.unlock` + `unlockCallback` |
| **`ARGON-H02`** | **High** | `hookData` trader identity & anti-snipe whitelist spoofing | `_resolveTrader` blocks spoofing of protocol contracts, `owner`/`devWallet`, and whitelisted addresses |
| **`ARGON-H03`** | **High** | Exact-Out swaps reverted due to `$IRL` vs `WETH` tax leg mismatch | Fixed `_afterSwap` when `isWETHUnspecified == true` to tax the exact WETH delta |
| **`ARGON-H04`** | **High** | Hourly 35% Top 10 pot distributed to all swappers instead of Top 10 | Implemented sorted `topTradersPerHour[hourId]` (max 10) with linear staking volume multiplier (`+50%` at `2%` staked) |
| **`ARGON-M01`** | **Medium** | Deployment script passed `poolManager` as `positionManager` | Separated `POSITION_MANAGER` env variable with strict address inequality check |
| **`ARGON-M02`** | **Medium** | ETH yield lost when `totalEligibleStaked == 0` & `[0.1%, 2.0%]` tier enforcement | Added `unallocatedYield` pre-stake buffer and enforced `[1M, 20M $IRL]` (`0.1%` to `2.0%`) eligible staking bounds |
| **`ARGON-M03`** | **Medium** | Non-zero OpenVRF `requestFee` could consume lottery pot ETH | Deducted `requestFee` from `protocolPot` and added `setCallbackGasLimit` (`[25k, 1M]`) |
| **`ARGON-M04`** | **Medium** | VRF prize race condition & Sunday Mega-Jackpot zero-ticket loss | Snapshotted prize in `vrfRequestPrize[requestId]` and preserved `sundayMegaPot` on 0-ticket weeks |
| **`ARGON-M05`** | **Medium** | Multi-hour `hourlyRewardPot` co-mingling during batch payout | Isolated hourly pots in `hourlyPotByHour[hourId]` |
| **`ARGON-L01..L04`** | **Low** | Bot copy/listeners, `SOCIALS` URL, invariant fuzz assertion, NFT secondary cap | Enforced weekly holding cap (`42`–`70` tickets) in `IRLTicketNFT._update`, updated bot & invariant suite |

### 🧪 Comprehensive Verification Suite (46/46 Passing Tests)

The repository includes a comprehensive Foundry simulation, invariant, and security test suite covering multi-day, weekly, and monthly protocol dynamics:

```bash
# Clone the repository
git clone https://github.com/math-crypt/lottery-robinhood.git
cd lottery-robinhood

# Install dependencies
forge install

# Run the complete test suite
forge test -v
```

#### Key Scenarios & Invariants Tested:
1. **Trail of Bits & Argon Formal Invariants (`test/TrailOfBitsEcosystemInvariants.t.sol`):**
   - **Staking Solvency & `[0.1%, 2.0%]` Tier Bounds:** Fuzzing proves `stakingToken.balanceOf(staking) >= totalStaked`, `address(staking).balance >= pendingAlice + pendingBob`, pre-stake `unallocatedYield` buffering, and strict `[1,000,000, 20,000,000] $IRL` (`0.1%` to `2.0%`) eligible weight boundaries across 256 random runs.
   - **Fee Conservation:** Formally proves zero wei leakage across arbitrary swap amounts from 0.001 ETH to 1000 ETH (`totalAccounted == swapFee`).
   - **Single-Sided LP Directional Rug-Proof:** Proves dev cannot withdraw IRL tokens before the entire position is converted into WETH (`tick >= tickUpper` or `tick <= tickLower`).
   - **OpenVRF Router Exclusivity:** Confirms unauthorized callers are unconditionally rejected (`"Only router"`).
2. **1-Minute Anti-Snipe Tax, Spoof Prevention & Automated 50k MC Cutoff (`test/AntiSnipeTaxValidation.t.sol`):**
   - Validates automated launch on first swap, sniper 90% dev / 1% programmable tax routing, whitelist bypass, `_resolveTrader` anti-spoofing protection, 60s expiration, and 50k MC auto-disable.
3. **Argon Audit Remediation & Top 10 Staker Boost Suite (`test/IRLProtocolScenarios.t.sol`):**
   - Validates `performUpkeep` preconditions, 24h staking cooldown, real Uniswap V4 `WETH -> $IRL` buyback & burn to `0xdead`, Exact-Out swaps, and the **35/35/30 Hourly Stream** (proving that two traders swapping `0.05 WETH` where one stakes `2%` are scored at `0.050 WETH` vs `0.075 WETH`, splitting the 35% Top 10 pot `40% / 60%`, while each receives `0.35%` hourly cashback and `30%` flows to `[0.1%, 2.0%]` stakers).
4. **1-Day, 1-Week & 1-Month Continuous Flywheels (`test/IRLProtocolScenarios.t.sol`):**
   - Simulates 24h, 7-day, and 30-day continuous volume, midnight OpenVRF draws, 4-day epoch staking ticket claims, zero-trade rollovers, and native ETH Real Yield streaming.
5. **Native OpenVRF Deployment & BLS Verification (`test/OpenVRFDeploymentAndIntegration.t.sol`):**
   - Verifies native OpenVRF coordinator on Robinhood Chain L2 with Drand round 1000 BLS cryptographic signature validation via EVM pairing precompiles (`0x06`, `0x07`, `0x08`).

#### 📊 Complete 46-Test Verification Matrix (100% Pass Rate)

| Test Suite | Test Function | Result | Validation Scope |
| :--- | :--- | :---: | :--- |
| **Trail of Bits Invariants** | `test_Invariant_FeeConservation_ZeroWeiLeak_Fuzz` | **PASS** | Formal zero-wei fee conservation across 256 fuzz runs (0.001 to 1000 ETH) |
| **Trail of Bits Invariants** | `test_Invariant_MarketingVault_DirectionalRugProof_Token0` | **PASS** | Proves dev cannot withdraw IRL liquidity when tick < tickUpper (token0 pair) |
| **Trail of Bits Invariants** | `test_Invariant_MarketingVault_DirectionalRugProof_Token1` | **PASS** | Proves dev cannot withdraw IRL liquidity when tick > tickLower (token1 pair) |
| **Trail of Bits Invariants** | `test_Invariant_OpenVRF_RouterExclusivity` | **PASS** | Proves unauthorized callers are unconditionally rejected with `"Only router"` |
| **Trail of Bits Invariants** | `test_Invariant_StakingSolvency_Fuzz` | **PASS** | Proves 100% staking & ETH yield solvency across 256 fuzz runs |
| **Trail of Bits Invariants** | `test_Invariant_StakingUnallocatedYieldBuffered` | **PASS** | Validates pre-stake `unallocatedYield` buffer & `[0.1%, 2.0%]` (`1M`–`20M $IRL`) tier bounds |
| **Anti-Snipe & Anti-Whale** | `test_AntiSnipe_NonWhitelistedSniper_Pays90PercentDevAnd1PercentProg` | **PASS** | 91% total swap tax during 1st minute on non-whitelisted snipers |
| **Anti-Snipe & Anti-Whale** | `test_AntiSnipe_WhitelistedAddress_PaysNormalTax` | **PASS** | Whitelisted addresses pay standard 4.0% ecosystem tax |
| **Anti-Snipe & Anti-Whale** | `test_AntiSnipe_AfterOneMinute_EveryonePaysNormalTax` | **PASS** | Tax automatically deactivates after 60s for all traders |
| **Anti-Snipe & Anti-Whale** | `test_AntiSnipe_AutoLaunchOnFirstSwap_WithoutManualCall` | **PASS** | First swap automatically sets `launchTimestamp` without manual tx |
| **Anti-Snipe & Anti-Whale** | `test_AntiWhale_AutoDisableAt50kMarketCap` | **PASS** | All Max TX/Wallet limits auto-disable permanently at 50k MC (2.5x launch) |
| **Anti-Snipe & Anti-Whale** | `test_AntiSnipe_BatchWhitelist` | **PASS** | Efficient batch whitelisting of launch partners |
| **Anti-Snipe & Anti-Whale** | `test_AntiSnipe_FallbackDevPotIfCallFails` | **PASS** | Dev tax safely buffers into fallback pot if transfer fails |
| **Anti-Snipe & Anti-Whale** | `test_AntiSnipe_RemoveLimitsDisablesAntiSnipeImmediately` | **PASS** | Manual or price-based limit removal immediately deactivates restrictions |
| **Anti-Snipe & Anti-Whale** | `test_AntiSnipe_SpoofedHookDataRejected` | **PASS** | Blocks `hookData` spoofing of whitelisted/protocol addresses during anti-snipe |
| **OpenVRF Integration** | `test_OpenVRF_Deployment_Parameters` | **PASS** | Native OpenVRF coordinator initialization, owner, relayer authorization & 0 fees |
| **OpenVRF Integration** | `test_OpenVRF_ConsumerAuthorization` | **PASS** | Strict access control on consumers and callback gas limit boundaries (25k-1M gas) |
| **OpenVRF Integration** | `test_OpenVRF_CryptographicDrandFulfillment` | **PASS** | Real Drand round 1000 BLS cryptographic signature verification via EVM pairing precompiles |
| **OpenVRF Integration** | `test_IRLUniswapV4Hook_DailyLottery_EndToEndWithOpenVRF` | **PASS** | Full 24h daily draw: swaps -> 4% tax -> tickets -> upkeep -> OpenVRF -> instant ETH payout |
| **OpenVRF Integration** | `test_IRLUniswapV4Hook_SundayMegaJackpot_EndToEndWithOpenVRF` | **PASS** | Full 7-day Sunday Mega-Jackpot draw with multiple traders, upkeep and OpenVRF distribution |
| **OpenVRF Integration** | `test_Security_UnauthorizedCallerCannotSpoofRandomness` | **PASS** | Hook rejects unauthorized callers attempting to spoof randomness with `"Only router"` |
| **Stress & Validation** | `testStaking_HalfTierAndLinearCalculations` | **PASS** | Half-tier staking (10M $IRL = 1% supply) linear scaling (caps, multipliers, free tickets) & Real Yield claim |
| **Stress & Validation** | `testFeeDistribution_PreciseWeiCalculationsAcrossTxSizes` | **PASS** | Exact 4% swap tax distribution down to the single wei across 1.0 ETH, 0.1 ETH, and 10.0 ETH swaps |
| **Stress & Validation** | `testNFTVolumeLimits_NonStakerVsHalfStakerVsFullStaker` | **PASS** | Strict daily volume ticket caps (6 for 0%, 8 for 1%, 10 for 2%) with zero extra tickets on excess volume |
| **Stress & Validation** | `testHourlyRewards_MassiveBatchQueueStressTest_60Traders` | **PASS** | Queue stress test with 60+ traders exceeding 50-item batch limit, proving Top 10 + cashback multi-batch execution |
| **Stress & Validation** | `testDailyAndWeeklyLottery_MassiveScale_50Traders` | **PASS** | Massive dual lottery with 50 traders generating hundreds of tickets over 7 days with OpenVRF payouts |
| **Stress & Validation** | `testTelegramBot_AllContractViewQueries` | **PASS** | Validates all RPC read methods invoked by `bot/index.js` (`getPendingJackpotAmounts`, `getHourlyState`, etc.) |
| **Stress & Validation** | `testDeveloperVault_SingleSidedLPRugProofAndWETHClaim` | **PASS** | Single-Sided LP anti-rug tick invariant and fee collection of accumulated WETH to dev wallet |
| **Stress & Validation** | `test_NFTTicket_OnChainHoldingCapEnforced` | **PASS** | Enforces dynamic weekly NFT holding caps (`42` to `70` tickets) on secondary P2P transfers |
| **Protocol Scenarios** | `testSimulation_1Day_HourlyAndDailyDraw` | **PASS** | 24 consecutive hours of trading, volume rewards, midnight OpenVRF randomness fulfillment, and winner payout |
| **Protocol Scenarios** | `testSimulation_1Week_DailyDrawsAndSundayMegaJackpot` | **PASS** | 7 daily cycles, 4-day epoch staking ticket claims, zero-trade rollover to Sunday, and Sunday Mega-Jackpot |
| **Protocol Scenarios** | `testSimulation_1Month_ContinuousFlywheel` | **PASS** | 30-day flywheel, continuous staking yield accumulation in native ETH, and 10% V4 buyback & burn to `0xdead` |
| **Protocol Scenarios** | `testSecurityHardening_RevertingWinnerAndFallbackPots` | **PASS** | Recipient address validation, buffering when recipient reverts, and zero-stuck ETH when winner reverts |
| **Protocol Scenarios** | `testSecurityFixes_AuditRemediationSuite` | **PASS** | Validates `performUpkeep` guards, 24h cooldown, V4 `WETH -> $IRL` buyback, Exact-Out swaps & `0.05 -> 0.075 WETH` Top 10 boost |
| **Hook Unit Tests** | `testAfterSwapTracksVolume` | **PASS** | Hook `afterSwap` volume accumulation and volume-weighted trader scoring |
| **Hook Unit Tests** | `testDailyVolumeLimitsNonStakerVsStaker` | **PASS** | Daily ticket quotas (6 vs 10) and weekly holding quotas (42 vs 70) |
| **Hook Unit Tests** | `testStakerTicketVolumeMultiplierAnd4DayEpoch` | **PASS** | Staking multipliers (+50%), 24h cooldown, and 4-day epoch free ticket claims |
| **Ecosystem Simulation** | `testProgrammableFeeRoutingAndClaiming` | **PASS** | 1.0% fee forwarding to Programmable.market, buffer accumulation, and recipient claiming |
| **Ecosystem Simulation** | `testFullSimulationWithLogs` | **PASS** | End-to-end trace with detailed console logging across swaps and distributions |
| **Ecosystem Simulation** | `testMassiveSimulation` | **PASS** | Multi-agent heavy trading simulation validating long-term protocol solvency |
| **Position Manager** | `test_burn` | **PASS** | Uniswap V4 PositionManager position burning |
| **Position Manager** | `test_decreaseLiquidity` | **PASS** | Uniswap V4 PositionManager liquidity reduction |
| **Position Manager** | `test_increaseLiquidity` | **PASS** | Uniswap V4 PositionManager liquidity addition |
| **Position Manager** | `test_increaseLiquidityNative` | **PASS** | Uniswap V4 PositionManager native ETH liquidity addition |
| **Position Manager** | `test_mintLiquidity` | **PASS** | Uniswap V4 PositionManager position minting |
| **Position Manager** | `test_mintLiquidityNative` | **PASS** | Uniswap V4 PositionManager native ETH position minting |

---

## 🛡️ License & Verification

This project is licensed under the [MIT License](LICENSE).  
Smart contracts are open source, fully verified, and transparent on Robinhood Chain.


