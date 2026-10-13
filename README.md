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
7. [Genesis Fair-Launch & Anti-Whale Mechanics](#7-genesis-fair-launch--anti-whale-mechanics)
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
3. **Equitable Real Yield Streaming & Hybrid 24h Staking:** 30% of all hourly swap pots stream directly into native ETH dividends for eligible stakers (`0.1%` to `2.0%` tiers). Staking never locks withdrawals by default (`0h` lock); stakers can claim up to 10 free lottery tickets every 4 days either with **0h lock after 24h of staking** (*Mature Claim*) or **immediately upon staking with a 24h unstake lock** (*Instant Claim*).
4. **Permanent Double Supply Deflation (Chart-Clean Hourly Batching):** 0.50% of every swap is auto-burned onchain by Programmable.market + 10% of the 1.0% protocol/dev fee (`0.10%` of swap volume) accumulates in `buybackPot` and executes as a **single consolidated V4 buyback & burn once every hour** to `0x000...dEaD` (**0.60% total swap burn** without spamming the chart with micro-buys on every trade).

---

## 2. Verified Smart Contract Directory

All smart contracts are developed with **Solidity 0.8.26**, optimized with low-level storage slot packing, DoS-proof direct array indexing, and audited for zero reentrancy risks:

| Contract | File Path | Standard | Key Architectural Role |
| :--- | :--- | :--- | :--- |
| **$IRL Token** | [`src/InternetRobinLottery.sol`](src/InternetRobinLottery.sol) | ERC-20 | Standard, ultra-lightweight 1B token with 18 decimals and no external mint functions. |
| **V4 Lottery Hook** | [`src/IRLUniswapV4Hook.sol`](src/IRLUniswapV4Hook.sol) | Uniswap V4 Hook | Collects native WETH tax (**10.0% Launch Boost Tax up to $100k MC**: `3.5%` Hourly + `3.5%` Lottery + `2.0%` Protocol + `1.0%` Programmable $\rightarrow$ auto-switches at **$100k MC** to **4.0% Standard Tax**: `1% / 1% / 1% / 1%`), tracks Top 10 boosted volume, mints tickets, executes batched hourly V4 buyback & burn, and triggers OpenVRF. |
| **Real Yield Staking** | [`src/IRLStaking.sol`](src/IRLStaking.sol) | MasterChef Real Yield | Continuous native ETH dividend pool streaming 30% of hourly pots across `[0.1%, 2.0%]` eligible staker tiers with a Hybrid 24h Free-Ticket Claim Mechanic (zero unstake lock by default; 0h lock if free tickets claimed after ≥24h staked, or 24h lock on Instant-Claim <24h). |
| **Lottery Tickets & Market** | [`src/IRLTicketNFT.sol`](src/IRLTicketNFT.sol) | ERC-721 + P2P Market | Dynamic NFT raffle tickets with built-in P2P Marketplace (`listTicket` / `buyTicket`), 2.0% Lottery Tax routing (`1% Daily + 1% Sunday` for Daily+Weekly tickets or `2% Sunday` for Weekly-only), and weekly holding caps (`42`–`70`). |
| **Marketing Vault** | [`src/IRLMarketingVault.sol`](src/IRLMarketingVault.sol) | Single-Sided LP Vault | Locks 10% marketing allocation as single-sided LP; mathematically blocks withdrawals until 100% converted to WETH. |
| **OpenVRF Router** | `lib/openvrf` | Decentralized Oracle | Supplies tamper-proof BLS randomness for daily lotteries and Sunday Mega-Jackpot draws. |

---

## 3. The Uniswap V4 Hook Tax Breakdown (10% Launch Boost < $100k MC $\rightarrow$ 4.0% Standard Tax)

To ignite massive early prize pots from the very first hour, day, and week of trading, the Uniswap V4 Hook features a **two-phase automatic tax schedule** collected natively in WETH:

1. **🚀 Phase 1 — 10.0% Launch Boost Tax (Up to $100,000 Market Cap):**
   - **3.5% Hourly Stream (`35/35/30`):** Supercharges the first hourly pots (`1.225%` Top 10 Traders / `1.225%` Active Swappers Cashback / `1.05%` Stakers Real Yield in ETH).
   - **3.5% Dual Lottery Engine (OpenVRF):** Supercharges the first Daily 24h Grand Jackpots (`1.75%`) and the first Sunday Mega-Jackpot (`1.75%`).
   - **2.0% Protocol & Deflation:** `90%` (`1.80%`) protocol/marketing & gas upkeep + `10%` (`0.20%`) Hourly Batched V4 Buyback & Burn to `0xdead` (**`0.70%` total swap burn during Launch Boost** when combined with Programmable's `0.50%` burn!).
   - **1.0% Programmable.market Fee:** `50%` Auto-Burn (`0.50%` of swap) + `50%` Programmable Treasury (`0.50%`).
   - *Autonomous $100k MC Cutoff:* As soon as the pool price organically reaches **$100,000 Market Cap** (`disableLaunchTaxSqrtPrice`, `5.0x` from initial $20k MC), `launchTaxEnabled` permanently and automatically disables on-chain (`emit LaunchTaxDisabled()`), transitioning to the **4.0% Standard Tax**!

2. **⚡ Phase 2 — 4.0% Standard Cruise Tax (From $100,000 Market Cap Onward):**

```text
           10.0% Launch Boost Tax (< $100k MC)  ──►  4.0% Standard Tax (≥ $100k MC)
                                           │
          ┌────────────────────────────────┼────────────────────────────────┬────────────────────────────────┐
          ▼                                ▼                                ▼                                ▼
1.0% Programmable.market Fee     3.5% ➔ 1.0% Hourly (35/35/30)    3.5% ➔ 1.0% Dual Lottery       2.0% ➔ 1.0% Protocol & Burn
 ├── 50% Auto-Burn (0.50% swap)   ├── 35% Top 10 Volume Traders    ├── 50% Daily 24h (OpenVRF)     ├── 90% Gas & Infrastructure
 └── 50% Programmable Treasury    ├── 35% Active Swapper Cashback  └── 50% Sunday Mega-Jackpot     └── 10% Hourly Buyback & Burn
                                  └── 30% Stakers Real Yield (ETH)
```

### ⚡ 1. 1.0% Programmable.market Protocol Tax (`1.0%` at Launch & Cruise)
- Routed directly to Programmable.market's recipient address on each swap.
- **50% Auto-Burned Onchain:** 0.50% of every swap volume is permanently burned by Programmable.
- **50% Programmable Treasury:** Funds Programmable ecosystem liquidity and partner backing.

### ⏱️ 2. Hourly Stream (`3.5%` up to $100k MC $\rightarrow$ `1.0%` Standard: 35% Top 10 / 35% Cashback / 30% Stakers)
- **35% Top 10 of the Hour (`topTradersPerHour`):** Distributed strictly among the **Top 10 traders of that hour**, ranked and weighted by their **Staking-Boosted Volume Score** (`+0%` to `+50%` bonus up to `2.0%` staked).  
  *Concrete Example:* If two traders each execute `0.05 WETH` of volume during the hour, and one of them stakes `2.0%` of the supply (`20,000,000 $IRL` = `+50%` volume bonus), the non-staker is counted at **`0.050 WETH`** while the `2.0%` staker is counted at **`0.075 WETH`** (`0.05 × 1.50`) for both Top 10 ranking and Top 10 pot share!
- **35% Active Swapper Hourly Cashback:** Distributed to **all traders who traded during the hour** (**`1.225%` cashback during Launch Boost `< $100k MC`**, then **`0.35%` standard cashback**), accumulated throughout the hour and **distributed once per hour** during the automated hourly upkeep.
- **30% Native ETH Real Yield (`0.1%` to `2.0%` Staking Tiers):** Streamed in native ETH to `$IRL` stakers ranked between **`0.1%` (`1,000,000 $IRL` minimum)** and **`2.0%` (`20,000,000 $IRL` maximum cap per wallet)** via the `IRLStaking` MasterChef `accEthPerShare` engine.

### 🏆 3. Dual Lottery Engine (`3.5%` up to $100k MC $\rightarrow$ `1.0%` Standard via OpenVRF) & 2.0% P2P Marketplace Tax
- **50% Daily Grand Jackpot (`1.75%` at Launch $\rightarrow$ `0.50%` Standard):** Drawn every midnight strictly among tickets minted *that day* (with atomic prize snapshotting per VRF request).
- **50% Sunday Mega-Jackpot (`1.75%` at Launch $\rightarrow$ `0.50%` Standard):** Massive weekly draw across **all** tickets minted from Monday through Sunday.
- **Validated P2P Ticket Marketplace (`IRLTicketNFT.buyTicket`):** Every secondary ticket sale on the P2P Marketplace pays **98.0% to the seller** and routes a **2.0% Lottery Tax** directly into the lottery pots via `IRLUniswapV4Hook.receiveMarketplaceTax(tokenId)`:
  - **Daily + Weekly Ticket (minted today):** Splits the 2% tax **50/50** (`1.0%` to `dailyLotteryPot` + `1.0%` to `sundayMegaPot`).
  - **Weekly-Only Ticket (minted earlier in the week):** Routes **100% of the 2% tax** (`2.0%`) directly to `sundayMegaPot`.

### ⚙️ 4. Protocol Solvency & Hourly Batched Deflation (`2.0%` up to $100k MC $\rightarrow$ `1.0%` Standard)
- **90% Protocol Upkeep:** Funds decentralized OpenVRF oracle gas, Keepers automation, and global growth.
- **10% Hourly Batched Buyback & Burn (`0.20%` of Swap Volume `< $100k MC` $\rightarrow$ `0.10%` Standard):** On every buy and sell, 10% of the protocol/dev fee accumulates in `buybackPot` in native ETH rather than executing micro-swaps on every trade. **Once every hour** (during the automated hourly upkeep or via `executeBuybackAndBurn` gated by `lastBuybackHour`), the entire accumulated `buybackPot` is swapped in a single consolidated `WETH -> $IRL` transaction on the Uniswap V4 pool and permanently burned to `0x000000000000000000000000000000000000dEaD`. This prevents chart clutter from micro-buybacks on every user trade while delivering a clean hourly buyback & burn candle.

### 🔥 The Double-Deflation Flywheel (0.70% Burn at Launch $\rightarrow$ 0.60% Standard Burn)
Every hour combines two complementary deflationary mechanisms:
- **0.50%** burned automatically onchain by Programmable.market on each swap.
- **0.20% (up to $100k MC) / 0.10% (≥ $100k MC)** accumulated in `buybackPot` from the protocol/dev fee and **bought back & burned once per hour** on the V4 pool to `0xdead`.
- **Total Burn = 0.70% during Launch Boost (< $100k MC) and 0.60% permanently thereafter!**

---

## 4. Mathematical Formulas & Staking Quotas

### 🎯 Progressive Staking Quotas (`0.1%` to `2.0%` Tiers) & Hybrid 24h Free-Ticket Claim
To ensure long-term decentralized alignment, prevent whale monopolization, and eliminate flash-loan Sybil attacks **without locking normal stakers from withdrawing**, staking benefits scale **progressively and linearly** up to the **2.0% supply quota (`20,000,000 $IRL`)**:

- **Total Supply:** `1,000,000,000 $IRL`
- **Eligible Real Yield Staking Range:** `1,000,000 $IRL (0.1% min)` to `20,000,000 $IRL (2.0% max cap per wallet)`
- **Hybrid 24h Staking & Free-Ticket Claim Mechanic (`IRLStaking.sol` & `IRLUniswapV4Hook.sol`):**
  - **Zero Unstake Lock by Default (`0h Lock`):** Depositing `$IRL` into `stake()` **never** locks `unstake()`. A holder who stakes to enjoy their volume multiplier (`+2.5%` to `+50%`), expanded ticket caps (`43.4` to `70/week`), or 30% ETH Real Yield can unstake at any time without waiting 24 hours.
  - **Option A — Mature Claim (`>= 24h` Staked $\rightarrow$ `0h Lock`):** Once a staker has kept their `$IRL` staked for at least **24 hours** (`block.timestamp >= lastStakedTimestamp[user] + 24 hours`), they can claim their free staking tickets (up to **10 tickets every 4 days**) with **zero unstake lock** (`0h lock`, remaining free to unstake whenever they want).
  - **Option B — Instant Claim (`< 24h` Staked $\rightarrow$ `24h Lock`):** If a staker wants to claim their **up to 10 free staking tickets immediately** after staking (before 24 hours of staking have elapsed), they can do so right away, which automatically locks their `unstake()` for **24 hours** (`unstakeUnlockTime[user] = block.timestamp + 24 hours`).
  - **Why This Solves Multi-Wallet Sybil Ticket Farming:** Every batch of 10 free staking tickets mathematically requires **24 hours of token immobilization** — either *pre-paid* (Option A: 24h already staked before claiming) or *post-paid* (Option B: 24h unstake lock triggered upon instant claiming) — making it impossible to rotate the same `$IRL` across multiple wallets for infinite free tickets.
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

Free Staking Tickets Formula (Every 4 Days — Hybrid Claim):
StakerTickets_4Days = min( (Staked_IRL × 10) / 20,000,000 , 10 Tickets every 4 days )
UnstakeUnlockTime(u) = (ClaimedAt < StakedAt + 24h) ? (ClaimedAt + 24h) : 0 (Unlocked)

P2P Marketplace 2.0% Lottery Tax Routing:
MarketplaceTax(2%) = DailyAndWeeklyTicket ? (1.0% DailyPot + 1.0% SundayPot) : (2.0% SundayPot)

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
- **Hybrid Anti-Sybil Free Ticket Claim:** Every batch of 10 free staking tickets requires 24 hours of token immobilization — either **pre-paid** (staked ≥ 24h before claiming $\rightarrow$ 0h unstake lock) or **post-paid** (Instant-Claimed at < 24h staked $\rightarrow$ 24h unstake lock), preventing multi-wallet Sybil loops while never locking normal stakers.

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

## 7. Genesis Fair-Launch, Anti-Whale & 10% Launch Boost Mechanics

To ensure healthy token distribution and explosive early reward pots at pool initialization, the Uniswap V4 Hook enforces two autonomous market-cap milestones:

- **Total Supply:** 1,000,000,000 $IRL (100% Fixed, Zero Inflation)
- **Initial Market Cap:** ~$20,000 USD
- **Max Transaction Limit (Up to $50k MC):** 10,000,000 $IRL (1.0% of supply)
- **Max Wallet Limit (Up to $50k MC):** 20,000,000 $IRL (2.0% of supply)
- **10.0% Launch Boost Tax (Up to $100k MC):** Supercharges early prize pools (`3.5%` Hourly Pot + `3.5%` Daily/Sunday Lottery Pots + `2.0%` Protocol/Buyback Pot + `1.0%` Programmable).

### 🔓 Autonomous Market-Cap Cutoffs ($50k MC & $100k MC)
The Hook reads pool prices on every swap (`getSlot0`):
1. **At $50,000 Market Cap (`disableAntiWhaleSqrtPrice`, `2.5x` initial price):** Automatically and permanently disables the `1%` Max TX and `2%` Max Wallet limits (`limitsEnabled = false; emit LimitsDisabled()`).
2. **At $100,000 Market Cap (`disableLaunchTaxSqrtPrice`, `5.0x` initial price):** Automatically and permanently disables the 10% Launch Boost Tax (`launchTaxEnabled = false; emit LaunchTaxDisabled()`), switching to the **4.0% Standard Cruise Tax** (`1% / 1% / 1% / 1%`).

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
| `/tokenomics` | Economics | In-depth breakdown of the 4.0% swap tax (1% Programmable, 1% Hourly 35/35/30, 1% Dual Lottery 50/50, 1% Protocol 90/10) and 0.60% double-deflation burn (with hourly batched protocol buyback). | Smart Contract Specs |
| `/contracts` | Verification | Displays verified smart contract addresses ($IRL Token, V4 Hook, NFT Tickets, Staking Vault, Marketing Vault) with RobinhoodScan explorer links. | Live Onchain Registry |
| `/launch` | Roadmap | Current pre-launch phase, network details (Robinhood Chain, Chain ID 4663), 90% burned LP proof, and fair launch roadmap. | Deployment Specs |
| `/socials` | Community | Verified links to official 𝕏 ([@IRL_Protocol](https://x.com/IRL_Protocol)), Telegram ([t.me/InternetRobinhoodLottery](https://t.me/InternetRobinhoodLottery)), and GitHub. *(Aliases: `/x`, `/twitter`)* | Official Channels |
| `/stake` | Real Yield | Complete guide to staking $IRL: native ETH dividends from 30% hourly stream, Hybrid 24h Free-Ticket Claim (0h lock by default & after 24h staked, or 24h lock on Instant-Claim), up to +50% volume multiplier, and expanded limits. | `IRLStaking.sol` |
| `/security` | Audit & Safety | Rug-proof liquidity architecture: 90% base liquidity burned to `0x000...dEaD` and 10% marketing allocation locked in `IRLMarketingVault.sol` with mathematical tick bounds. | `IRLMarketingVault.sol` |
| `/tickets` | Dynamic Query | Queries the total number of NFT lottery tickets currently in play, volume thresholds (0.10 WETH base), Hybrid 24h free staking tickets, P2P Marketplace 2% Lottery Tax, and daily limits. | `IRLTicketNFT.totalTicketsMinted()` |
| `/pot` | Live Treasury | Real-time balances of all onchain prize pots: Daily Grand Jackpot, Sunday Mega-Jackpot, Hourly Trader Pool, and Hourly Buyback & Burn Reserve. | `IRLUniswapV4Hook` View Methods |

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
- **100% Original Core Architecture:** The central business logic—including the multi-tier lottery engine, dynamic volume-weighted Top 10 scoring with staker boost (`+0%` to `+50%`), hourly cashback (`0.35%` paid once per hour), `[0.1%, 2.0%]` eligible Real Yield staking tiers, Hybrid 24h Free-Ticket Claim, and the Single-Sided LP Marketing Vault—was developed from scratch and exhibits zero matching signatures across public repositories.
- **Boilerplate Sanitation:** Standard Uniswap V4 scaffold scripts have been cleaned up; deployment and simulation are handled by our dedicated, custom-tailored harness (`script/DeployLotteryEcosystem.s.sol`).

### 🔒 Argon Security Audit Remediations Summary (`AUDIT_REPORT.md`)

| Finding ID | Severity | Vulnerability / Architectural Issue | On-Chain Remediation |
| :--- | :---: | :--- | :--- |
| **`ARGON-C01`** | **Critical** | `performUpkeep` arbitrary `actionType` & `timeId` manipulation | Strict on-chain preconditions (`curHour`, `curDay`, `curWeek`, `queueIndex`) enforced; `timeId` derived on-chain |
| **`ARGON-C02`** | **Critical** | Zero-cooldown flash-stake ticket farming across wallets | Hybrid 24h Anti-Sybil Ticket Claim (`unstakeUnlockTime`: 0h lock by default & after ≥24h staked; 24h lock on Instant-Claim <24h) |
| **`ARGON-H01`** | **High** | `executeBuybackAndBurn` sent ETH to `0xdead` instead of swapping for `$IRL` | Real automated hourly batched `WETH -> $IRL` V4 pool buyback & burn (`lastBuybackHour` + hourly upkeep) to `0xdead` |
| **`ARGON-H02`** | **High** | `hookData` trader identity & privileged address spoofing | `_resolveTrader` blocks spoofing of protocol contracts, `owner`/`devWallet`, and privileged addresses |
| **`ARGON-H03`** | **High** | Exact-Out swaps reverted due to `$IRL` vs `WETH` tax leg mismatch | Fixed `_afterSwap` when `isWETHUnspecified == true` to tax the exact WETH delta |
| **`ARGON-H04`** | **High** | Hourly 35% Top 10 pot distributed to all swappers instead of Top 10 | Implemented sorted `topTradersPerHour[hourId]` (max 10) with linear staking volume multiplier (`+50%` at `2%` staked) |
| **`ARGON-M01`** | **Medium** | Deployment script passed `poolManager` as `positionManager` | Separated `POSITION_MANAGER` env variable with strict address inequality check |
| **`ARGON-M02`** | **Medium** | ETH yield lost when `totalEligibleStaked == 0` & `[0.1%, 2.0%]` tier enforcement | Added `unallocatedYield` pre-stake buffer and enforced `[1M, 20M $IRL]` (`0.1%` to `2.0%`) eligible staking bounds |
| **`ARGON-M03`** | **Medium** | Non-zero OpenVRF `requestFee` could consume lottery pot ETH | Deducted `requestFee` from `protocolPot` and added `setCallbackGasLimit` (`[25k, 1M]`) |
| **`ARGON-M04`** | **Medium** | VRF prize race condition & Sunday Mega-Jackpot zero-ticket loss | Snapshotted prize in `vrfRequestPrize[requestId]` and preserved `sundayMegaPot` on 0-ticket weeks |
| **`ARGON-M05`** | **Medium** | Multi-hour `hourlyRewardPot` co-mingling during batch payout | Isolated hourly pots in `hourlyPotByHour[hourId]` |
| **`ARGON-L01..L04`** | **Low** | Bot copy/listeners, `SOCIALS` URL, invariant fuzz assertion, P2P Marketplace & cap | Built-in P2P Marketplace with 2% Lottery Tax (`receiveMarketplaceTax`) & weekly holding cap (`42`–`70` tickets) in `IRLTicketNFT._update` |

### 🧪 Comprehensive Verification Suite (47/47 Passing Tests)

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
   - **Staking Solvency, Hybrid Ticket Claim & `[0.1%, 2.0%]` Tier Bounds:** Fuzzing proves `stakingToken.balanceOf(staking) >= totalStaked`, `address(staking).balance >= pendingAlice + pendingBob`, pre-stake `unallocatedYield` buffering, zero default unstake lock, and strict `[1,000,000, 20,000,000] $IRL` (`0.1%` to `2.0%`) eligible weight boundaries across 256 random runs.
   - **Fee Conservation:** Formally proves zero wei leakage across arbitrary swap amounts from 0.001 ETH to 1000 ETH (`totalAccounted == swapFee`).
   - **Single-Sided LP Directional Rug-Proof:** Proves dev cannot withdraw IRL tokens before the entire position is converted into WETH (`tick >= tickUpper` or `tick <= tickLower`).
   - **OpenVRF Router Exclusivity:** Confirms unauthorized callers are unconditionally rejected (`"Only router"`).
2. **Launch Guard, Spoof Prevention & Automated 50k MC Cutoff (`FairLaunchAndAntiWhaleValidation`):**
   - Validates automated launch on first swap, launch guard fee routing, partner exemptions, `_resolveTrader` anti-spoofing protection, and 50k MC auto-disable.
3. **Argon Audit Remediation, Hybrid Staking & P2P Marketplace 2% Tax (`test/StressAndEcosystemValidation.t.sol`):**
   - Validates `performUpkeep` preconditions, Hybrid Instant-Claim vs 24h Mature Claim (`testStaking_HalfTierAndLinearCalculations`), P2P Marketplace 2.0% Lottery Tax routing (`testMarketplace_2PercentLotteryTaxRouting_DailyAndWeeklyVsWeeklyOnly`), hourly batched Uniswap V4 `WETH -> $IRL` buyback & burn to `0xdead`, Exact-Out swaps, and the **35/35/30 Hourly Stream** (`0.05 -> 0.075 WETH` Top 10 staker boost + `0.35%` hourly cashback + `30%` `[0.1%, 2.0%]` stakers Real Yield).
4. **1-Day, 1-Week & 1-Month Continuous Flywheels (`test/IRLProtocolScenarios.t.sol`):**
   - Simulates 24h, 7-day, and 30-day continuous volume, midnight OpenVRF draws, 4-day epoch staking ticket claims, zero-trade rollovers, and native ETH Real Yield streaming.
5. **Native OpenVRF Deployment & BLS Verification (`test/OpenVRFDeploymentAndIntegration.t.sol`):**
   - Verifies native OpenVRF coordinator on Robinhood Chain L2 with Drand round 1000 BLS cryptographic signature validation via EVM pairing precompiles (`0x06`, `0x07`, `0x08`).

#### 📊 Complete 47-Test Verification Matrix (100% Pass Rate)

| Test Suite | Test Function | Result | Validation Scope |
| :--- | :--- | :---: | :--- |
| **Trail of Bits Invariants** | `test_Invariant_FeeConservation_ZeroWeiLeak_Fuzz` | **PASS** | Formal zero-wei fee conservation across 256 fuzz runs (0.001 to 1000 ETH) |
| **Trail of Bits Invariants** | `test_Invariant_MarketingVault_DirectionalRugProof_Token0` | **PASS** | Proves dev cannot withdraw IRL liquidity when tick < tickUpper (token0 pair) |
| **Trail of Bits Invariants** | `test_Invariant_MarketingVault_DirectionalRugProof_Token1` | **PASS** | Proves dev cannot withdraw IRL liquidity when tick > tickLower (token1 pair) |
| **Trail of Bits Invariants** | `test_Invariant_OpenVRF_RouterExclusivity` | **PASS** | Proves unauthorized callers are unconditionally rejected with `"Only router"` |
| **Trail of Bits Invariants** | `test_Invariant_StakingSolvency_Fuzz` | **PASS** | Proves 100% staking & ETH yield solvency across 256 fuzz runs (with zero default unstake lock) |
| **Trail of Bits Invariants** | `test_Invariant_StakingUnallocatedYieldBuffered` | **PASS** | Validates pre-stake `unallocatedYield` buffer & `[0.1%, 2.0%]` (`1M`–`20M $IRL`) tier bounds |
| **Launch Guard & Anti-Whale** | `test_LaunchGuard_NonExemptBotProtection` | **PASS** | Validates genesis launch guard protection on non-exempt trades |
| **Launch Guard & Anti-Whale** | `test_LaunchGuard_ExemptAddress_PaysNormalTax` | **PASS** | Exempt launch addresses pay standard 4.0% ecosystem tax |
| **Launch Guard & Anti-Whale** | `test_LaunchGuard_PostWindow_EveryonePaysNormalTax` | **PASS** | Launch guard automatically transitions to standard 4.0% tax for all traders |
| **Launch Guard & Anti-Whale** | `test_LaunchGuard_AutoLaunchOnFirstSwap` | **PASS** | First swap automatically sets `launchTimestamp` without manual tx |
| **Launch Guard & Anti-Whale** | `test_AntiWhale_AutoDisableAt50kMarketCap` | **PASS** | All Max TX/Wallet limits auto-disable permanently at 50k MC (2.5x launch) |
| **Launch Guard & Anti-Whale** | `test_LaunchGuard_BatchWhitelist` | **PASS** | Efficient batch registration of launch partners |
| **Launch Guard & Anti-Whale** | `test_LaunchGuard_FallbackPotIfCallFails` | **PASS** | Launch guard fee safely buffers into fallback pot if transfer fails |
| **Launch Guard & Anti-Whale** | `test_LaunchGuard_RemoveLimitsDeactivatesImmediately` | **PASS** | Manual or price-based limit removal immediately deactivates restrictions |
| **Launch Guard & Anti-Whale** | `test_LaunchGuard_SpoofedHookDataRejected` | **PASS** | Blocks `hookData` spoofing of privileged/protocol addresses |
| **OpenVRF Integration** | `test_OpenVRF_Deployment_Parameters` | **PASS** | Native OpenVRF coordinator initialization, owner, relayer authorization & 0 fees |
| **OpenVRF Integration** | `test_OpenVRF_ConsumerAuthorization` | **PASS** | Strict access control on consumers and callback gas limit boundaries (25k-1M gas) |
| **OpenVRF Integration** | `test_OpenVRF_CryptographicDrandFulfillment` | **PASS** | Real Drand round 1000 BLS cryptographic signature verification via EVM pairing precompiles |
| **OpenVRF Integration** | `test_IRLUniswapV4Hook_DailyLottery_EndToEndWithOpenVRF` | **PASS** | Full 24h daily draw: swaps -> 4% tax -> tickets -> upkeep -> OpenVRF -> instant ETH payout |
| **OpenVRF Integration** | `test_IRLUniswapV4Hook_SundayMegaJackpot_EndToEndWithOpenVRF` | **PASS** | Full 7-day Sunday Mega-Jackpot draw with multiple traders, upkeep and OpenVRF distribution |
| **OpenVRF Integration** | `test_Security_UnauthorizedCallerCannotSpoofRandomness` | **PASS** | Hook rejects unauthorized callers attempting to spoof randomness with `"Only router"` |
| **Stress & Validation** | `testStaking_HalfTierAndLinearCalculations` | **PASS** | Hybrid staking claim (Instant Claim locks 24h vs ≥24h Mature Claim 0h lock) & Real Yield claim |
| **Stress & Validation** | `testMarketplace_2PercentLotteryTaxRouting_DailyAndWeeklyVsWeeklyOnly` | **PASS** | P2P Marketplace 2% Lottery Tax routing (50/50 Daily+Sunday vs 100% Sunday Mega-Jackpot) |
| **Stress & Validation** | `testFeeDistribution_PreciseWeiCalculationsAcrossTxSizes` | **PASS** | Exact 4% swap tax distribution down to the single wei across 1.0 ETH, 0.1 ETH, and 10.0 ETH swaps |
| **Stress & Validation** | `testNFTVolumeLimits_NonStakerVsHalfStakerVsFullStaker` | **PASS** | Strict daily volume ticket caps (6 for 0%, 8 for 1%, 10 for 2%) with zero extra tickets on excess volume |
| **Stress & Validation** | `testHourlyRewards_MassiveBatchQueueStressTest_60Traders` | **PASS** | Queue stress test with 60+ traders exceeding 50-item batch limit, proving Top 10 + cashback multi-batch execution |
| **Stress & Validation** | `testDailyAndWeeklyLottery_MassiveScale_50Traders` | **PASS** | Massive dual lottery with 50 traders generating hundreds of tickets over 7 days with OpenVRF payouts |
| **Stress & Validation** | `testTelegramBot_AllContractViewQueries` | **PASS** | Validates all RPC read methods invoked by `bot/index.js` (`getPendingJackpotAmounts`, `getHourlyState`, etc.) |
| **Stress & Validation** | `testDeveloperVault_SingleSidedLPRugProofAndWETHClaim` | **PASS** | Single-Sided LP anti-rug tick invariant and fee collection of accumulated WETH to dev wallet |
| **Stress & Validation** | `test_NFTTicket_OnChainHoldingCapEnforced` | **PASS** | Enforces dynamic weekly NFT holding caps (`42` to `70` tickets) on secondary P2P transfers |
| **Protocol Scenarios** | `testSimulation_1Day_HourlyAndDailyDraw` | **PASS** | 24 consecutive hours of trading, volume rewards, midnight OpenVRF randomness fulfillment, and winner payout |
| **Protocol Scenarios** | `testSimulation_1Week_DailyDrawsAndSundayMegaJackpot` | **PASS** | 7 daily cycles, 4-day epoch staking ticket claims, zero-trade rollover to Sunday, and Sunday Mega-Jackpot |
| **Protocol Scenarios** | `testSimulation_1Month_ContinuousFlywheel` | **PASS** | 30-day flywheel, continuous staking yield accumulation in native ETH, and hourly batched 10% V4 buyback & burn to `0xdead` |
| **Protocol Scenarios** | `testSecurityHardening_RevertingWinnerAndFallbackPots` | **PASS** | Recipient address validation, buffering when recipient reverts, and zero-stuck ETH when winner reverts |
| **Protocol Scenarios** | `testSecurityFixes_AuditRemediationSuite` | **PASS** | Validates `performUpkeep` guards, Hybrid 24h claim lock, hourly V4 `WETH -> $IRL` buyback, Exact-Out swaps & `0.05 -> 0.075 WETH` Top 10 boost |
| **Hook Unit Tests** | `testAfterSwapTracksVolume` | **PASS** | Hook `afterSwap` volume accumulation and volume-weighted trader scoring |
| **Hook Unit Tests** | `testDailyVolumeLimitsNonStakerVsStaker` | **PASS** | Daily ticket quotas (6 vs 10) and weekly holding quotas (42 vs 70) |
| **Hook Unit Tests** | `testStakerTicketVolumeMultiplierAnd4DayEpoch` | **PASS** | Staking multipliers (+50%), Hybrid 24h claim, and 4-day epoch free ticket claims |
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


