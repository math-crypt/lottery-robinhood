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

#### The $IRL V2 Solution
The **Internet Robinhood Lottery ($IRL) V2** re-engineers tokenomics from first principles with **Uniswap V4 Custom Accounting Hooks**:
1. **Zero Chart Sell Pressure (*Swap-and-Liquify*):** All ecosystem taxes are collected natively in WETH directly from the AMM liquidity pool via `PoolManager.take()`. The contract **never** dumps $IRL tokens on the chart.
2. **Strict Human EOA Attribution & Bot/Contract Exclusion:** `_resolveTrader` inspects verified router buyer contexts (`signedRouteContext()` / `IMsgSender.msgSender()`), verifies `hookData` (`decoded == tx.origin` and `code.length == 0` to prevent multi-wallet Sybil spoofing in atomic multi-swap contracts), and strictly falls back to `tx.origin` whenever `sender` is a contract. Smart contracts, routers, and bots (`code.length > 0`) can **never** receive NFT lottery tickets.
3. **DApp Ticket Claim & 24h P2P Marketplace Relisting:** Earned tickets queued in `claimableTickets[beneficiary]` can be claimed on the DApp (`claimPendingTickets` / `claimPendingTicketsTo`). If left unclaimed after **24 hours**, `relistExpiredClaimableTickets` puts them back into play on the **P2P Marketplace** (`IRLTicketNFT`) where they are valid for that day's **24h Daily Lottery draw**; if unsold on the P2P market and drawn as the winner, **100% of the prize is routed to the Dev Wallet (`owner()`)**.
4. **Equitable Real Yield Streaming, Hybrid 24h Staking & Sherwood Co-Staking Guild (`0.1%` Zero-Lock):** 30% of all hourly swap pots stream directly into native ETH dividends for eligible stakers (`0.1%` to `2.0%` tiers). Small holders (`< 0.1%` supply) can pool any amount of `$IRL` in **`IRLSherwoodGuildVault.sol`**, which unlocks free staking ticket claims as soon as **`0.1%` of supply (`1,000,000 $IRL`)** is deposited **without ever locking the Guild's supply for 24 hours** (`unstakeUnlockTime == 0`).
5. **Native On-Chain Referral Engine (`96-byte hookData`):** Binds referrers permanently on-chain, streaming an automatic **`0.25%` (`25 bps`) native ETH commission** to the referrer on every swap (deducted from `protocolPot` share) and granting the referred trader a **`+10%` Hourly Leaderboard Score Boost**.
6. **Automated Hourly V4 Buyback & Burn (`0.50%` Launch Boost $\rightarrow$ `0.20%` Standard to `0xdead`) & 10-Tier Auto-Withdrawing LP Vault:** Accumulates in `buybackPot` on every swap and executes as a consolidated Uniswap V4 buyback & burn once per hour while automatically checking and withdrawing reached `2%` single-sided LP tiers (`100% ETH`) to the developer wallet.

---

## 2. Verified Smart Contract & DApp Directory

All smart contracts are developed with **Solidity 0.8.26**, optimized with low-level storage slot packing, `mintBatch` ticket issuance, single-call leaderboard views (`getHourlyLeaderboard`), and audited for zero reentrancy risks:

| Component | File Path | Standard | Key Architectural Role |
| :--- | :--- | :--- | :--- |
| **$IRL Token** | [`src/InternetRobinLottery.sol`](src/InternetRobinLottery.sol) | ERC-20 + EIP-7572 | Fixed-supply 1B token (`18` decimals, zero external mints, `0%` transfer tax, on-chain `contractURI()` metadata, Hook-level Anti-Whale only). |
| **V4 Lottery Hook (V2)** | [`src/IRLUniswapV4Hook.sol`](src/IRLUniswapV4Hook.sol) | Uniswap V4 Hook | Collects native swap tax (**10.00% Launch Boost** $\rightarrow$ **4.00% Standard Tax**), enforces human EOA attribution & Anti-Sybil `hookData`, runs the on-chain referral engine (`0.25% ETH` + `+10% Score`), manages 24h P2P ticket relisting, 7-day reward rollover, 24h VRF timeout recovery, and triggers OpenVRF. |
| **Real Yield Staking** | [`src/IRLStaking.sol`](src/IRLStaking.sol) | MasterChef Real Yield | Continuous native ETH dividend pool streaming 30% of hourly pots across `[0.1%, 2.0%]` eligible staker tiers with Hybrid 24h Free-Ticket Claim and zero-lock exemption for `IRLSherwoodGuildVault`. |
| **Sherwood Co-Staking Guild** | [`src/IRLSherwoodGuildVault.sol`](src/IRLSherwoodGuildVault.sol) | Pooled Co-Staking Vault | Allows small holders (`< 1M $IRL`) to pool tokens with zero minimum, unlock the `30%` ETH Real Yield stream, claim Guild lottery tickets as soon as **`0.1%` (`1,000,000 $IRL`)** is deposited with **zero 24h supply lock**, and share Daily (`>= 8h` staked) & Weekly (`>= 24h` staked) lottery jackpots. |
| **Lottery Tickets & Market** | [`src/IRLTicketNFT.sol`](src/IRLTicketNFT.sol) | ERC-721 + P2P Market | Dynamic NFT raffle tickets with default on-chain `tokenURI` JSON metadata, `mintBatch`, built-in P2P Marketplace (`listTicket` / `listRelistedTicket` / `buyTicket`), 2.0% Lottery Tax routing, and weekly holding caps (`42`–`70`). |
| **10-Tier LP & Marketing Vault** | [`src/IRLMarketingVault.sol`](src/IRLMarketingVault.sol) | 80/20 LP Custody & Auto-Vault | Seeds `100%` of the 1B `$IRL` supply into Uniswap V4 `PoolManager`: **80% (`800M $IRL`) permanently locked forever** (`PERMANENT_LOCKED_SALT`) and **20% (`200M $IRL`) split across 10 single-sided LP tiers of 2% each** (`40k, 70k, 100k, 250k, 500k, 750k, 1M, 1.5M, 2M, 5M` MC) that automatically withdraw **100% ETH** to `owner` as each milestone is crossed. |
| **Web3 DApp ("High-Roller Lounge")** | [`dapp/`](dapp/) | React + Vite + Ethers v6 | Official Web3 interface featuring live pot telemetry, V4 swap terminal with `96-byte` referral `hookData`, `+EV` probability calculator, Staking & Sherwood Guild Sanctuary, 3D P2P Ticket Marketplace, and Referral Dashboard. |
| **OpenVRF Router** | `lib/openvrf` | Decentralized Oracle | Supplies tamper-proof BLS randomness for daily lotteries and Sunday Mega-Jackpot draws. |

---

## 3. The Uniswap V4 Hook Tax Breakdown (10% Launch Boost [Max 24h or < $100k MC] $\rightarrow$ 4.0% Standard Tax)

To ignite massive early prize pots from the very first hour, day, and week of trading while guaranteeing a strictly bounded, non-resettable launch window and fixed market-cap cutoffs, the Uniswap V4 Hook features a **two-phase automatic tax schedule**:

1. **🚀 Phase 1 — 10.00% Launch Boost Tax (First 24 Hours OR Up to $100,000 Market Cap):**
   - **0.30% Immutable Programmable.market Fee (`30 bps`):** Hardcoded to `0xD88539d3c4C460136a733A3Fd60cf6BF269079da`, charged once per buy, sell, and internal buyback.
   - **3.75% Hourly Stream (`35/35/30`):** Supercharges the first hourly pots (`1.3125%` Top 10 Traders / `1.3125%` Active Swappers Cashback / `1.125%` Stakers Real Yield in ETH).
   - **3.75% Epoch-Isolated Dual Lottery Engine (OpenVRF):** Supercharges the first Daily 24h Grand Jackpot (`1.875%` into `dailyPotByDay[dayId]`) and the first Sunday Mega-Jackpot (`1.875%` into `weeklyPotByWeek[weekId]`).
   - **2.20% Protocol, Referrals & Deflation:** **`1.70%`** protocol/marketing & gas upkeep (`protocolPot`, including `0.25%` on-chain referral commission when applicable) + **`0.50%` (`50 bps`)** Hourly Batched V4 Buyback & Burn to `0xdead` (`buybackPot`).
   - *Fixed 24h Expiry & Fixed $100k MC Permanent Drop:* The `10.00%` Launch Boost Tax drops **permanently and irreversibly** to the **4.00% Standard Tax** as soon as **EITHER 24 hours elapses since `launchTimestamp` (`LAUNCH_TAX_DURATION = 24 hours`) OR the pool reaches the fixed $100,000 Market Cap cutoff** (`disableLaunchTaxSqrtPrice`, `5.0x` from initial $20k MC, set once at initialization and non-adjustable thereafter) — whichever comes first!

2. **⚡ Phase 2 — 4.00% Standard Cruise Tax (Permanent After 24h or $100,000 Market Cap):**

```text
    10.00% Launch Boost Tax (Max 24h OR < $100k MC)  ──►  4.00% Standard Tax (Permanent ≥ 24h or $100k MC)
                                                     │
          ┌──────────────────────────────────────────┼──────────────────────────────────┬────────────────────────────────┐
          ▼                                          ▼                                  ▼                                ▼
0.30% Programmable.market Fee            3.75% ➔ 1.25% Hourly (35/35/30)    3.75% ➔ 1.25% Dual Lottery       2.20% ➔ 1.20% Protocol & Burn
 └── 30 bps Once on Buy/Sell/Buyback      ├── 35% Top 10 Volume Traders      ├── 50% Daily 24h (OpenVRF)      ├── 1.70% ➔ 1.00% Protocol & Ref
     (Immutable 0xD885...79da)            ├── 35% Active Swapper Cashback    └── 50% Sunday Mega-Jackpot      └── 0.50% ➔ 0.20% Hourly V4 Burn
                                          └── 30% Stakers Real Yield (ETH)                                         (Swapped WETH -> $IRL to 0xdead)
```

### ⚡ 1. 0.30% Immutable Programmable.market Platform Fee (`30 bps` at Launch & Cruise)
- Enforced at **exactly `0.30%` (`30 bps`) once** on normal buys, normal sells, and internal buybacks (`executeBuybackAndBurn`) directly to the immutable constant `PROGRAMMABLE_FEE_RECIPIENT = 0xD88539d3c4C460136a733A3Fd60cf6BF269079da` without double-charging.

### ⏱️ 2. Hourly Stream (`3.75%` Launch Boost $\rightarrow$ `1.25%` Standard: 35% Top 10 / 35% Cashback / 30% Stakers)
- **35% Top 10 of the Hour (`topTradersPerHour`):** Distributed strictly among the **Top 10 traders of that hour** (`1.3125%` Boost / `0.4375%` Standard), ranked and weighted by their **Staking-Boosted Volume Score** (`+0%` to `+50%` staking bonus up to `2.0%` staked, plus **`+10%` Referral Boost** if referred).
- **35% Active Swapper Hourly Cashback:** Distributed to **all traders who traded during the hour** (**`1.3125%` cashback during Launch Boost**, then **`0.4375%` standard cashback**), accumulated throughout the hour and **distributed once per hour** during the automated hourly upkeep.
- **30% Native ETH Real Yield (`0.1%` to `2.0%` Staking Tiers):** Streamed in native ETH (`1.125%` Boost / `0.375%` Standard) to `$IRL` stakers ranked between **`0.1%` (`1,000,000 $IRL` minimum)** and **`2.0%` (`20,000,000 $IRL` maximum cap per wallet)** — including the **Sherwood Co-Staking Guild (`IRLSherwoodGuildVault.sol`)** for small holders — via the `IRLStaking` MasterChef `accEthPerShare` engine.
- **Fail-Safe Unpaid Rewards Protection (`unclaimedRewards` & 7-Day Rollover):** If a recipient wallet rejects native ETH during hourly distribution, lottery fulfillment, or referral payouts, their unpaid reward is credited to `unclaimedRewards[recipient]` (tracked in `totalUnclaimedLiabilities`). The beneficiary (or their delegate) can claim it at any time via `claimUnclaimedRewards()`, `claimUnclaimedRewardsTo(beneficiary, recipient)`, or as ERC-20 WETH via `claimUnclaimedRewardsAsWETH(beneficiary, recipient)`. If left unclaimed for **7 days (`UNCLAIMED_REWARD_EXPIRY`)**, `rollOverExpiredReward(beneficiary)` rolls it back into the active Daily Lottery Pot.

### 🏆 3. Epoch-Isolated Dual Lottery Engine (`3.75%` Launch Boost $\rightarrow$ `1.25%` Standard via OpenVRF), 24h P2P Ticket Relisting & 2.0% P2P Marketplace Tax
- **50% Daily Grand Jackpot (`1.875%` at Launch $\rightarrow$ `0.625%` Standard):** Accumulated in `dailyPotByDay[dayId]` (and directly seedable at any time via `seedDailyPot()`) and drawn every midnight strictly among tickets minted or relisted *that day* (`[dayStartTicketId[dayId], dayEndTicketId[dayId]]`).
- **50% Sunday Mega-Jackpot (`1.875%` at Launch $\rightarrow$ `0.625%` Standard):** Accumulated in `weeklyPotByWeek[weekId]` (directly seedable via `seedSundayPot()`) and drawn every Sunday across **all** tickets minted from Monday through Sunday (`[weekStartTicketId[weekId], weekEndTicketId[weekId]]`).
- **24-Hour Unclaimed Ticket Relisting on P2P Marketplace (`relistExpiredClaimableTickets`):** If tickets put aside in `claimableTickets[beneficiary]` are not claimed within **24 hours (`UNCLAIMED_TICKET_EXPIRY`)**, they are minted into Hook custody, registered in today's `dayStartTicketId[currentDay] .. dayEndTicketId[currentDay]` range (making them **100% valid for the active 24h Daily Lottery draw**), and listed for sale on the **P2P Marketplace (`IRLTicketNFT.listRelistedTicket`)**. If bought on the P2P market, the buyer owns the ticket and competes in the 24h draw; if **unsold** on the P2P market and drawn as the winning ticket (`winner == address(this)`), **100% of the lottery prize is sent to the Dev Wallet (`owner()`)**.
- **24-Hour VRF Timeout Recovery (`cancelExpiredLotteryRequest`):** If an OpenVRF request remains unfulfilled for `24 hours`, its locked prize is safely returned to the active lottery pot and any late callback becomes a no-op.
- **Validated P2P Ticket Marketplace (`IRLTicketNFT.buyTicket`):** Every secondary ticket sale on the P2P Marketplace pays **98.0% to the seller** and routes a **2.0% Lottery Tax** directly into the epoch-isolated lottery pots via `IRLUniswapV4Hook.receiveMarketplaceTax(tokenId)`.

### ⚙️ 4. Protocol Solvency, Native On-Chain Referrals & Hourly Batched Deflation (`2.20%` Launch Boost $\rightarrow$ `1.20%` Standard)
- **Protocol, Marketing, VRF Gas Upkeep & `0.25%` On-Chain Referrals (`1.70%` Boost $\rightarrow$ `1.00%` Standard):** Funds decentralized OpenVRF oracle gas (`withdrawProtocolFeesAmount` allows partial withdrawals so VRF fee reserves always remain funded), Keepers automation, and pays **`0.25%` (`25 bps`) of swap volume in native ETH** directly to the trader's on-chain referrer (`referrerOf[trader]`).
- **Hourly Batched V4 Buyback & Burn (`0.50%` Boost $\rightarrow$ `0.20%` Standard in `buybackPot`):** Consolidated once per hour into a single `WETH -> $IRL` swap on the Uniswap V4 pool burned permanently to `0x000000000000000000000000000000000000dEaD`.

---

## 4. Mathematical Formulas, Staking Quotas & Sherwood Co-Staking Guild

### 🎯 Progressive Staking Quotas (`0.1%` to `2.0%` Tiers), Sherwood Guild & Hybrid 24h Free-Ticket Claim
To ensure long-term decentralized alignment, prevent whale monopolization, and empower small holders (`< 0.1%` supply), staking benefits scale **progressively** from **`0.1%` (`1,000,000 $IRL`)** up to the **2.0% supply quota (`20,000,000 $IRL`)**:

- **Total Supply:** `1,000,000,000 $IRL`
- **Minimum Threshold for Real Yield & First Staking Ticket (`0.1%` Supply):** `1,000,000 $IRL` (`MIN_STAKING_TICKET_THRESHOLD = 1_000_000 ether` unlocks at least **1 free ticket** every 4 days, scaling up to **10 tickets** at `20,000,000 $IRL`).
- **🏹 Sherwood Co-Staking Guild for Small Holders (`IRLSherwoodGuildVault.sol`):**
  - Small holders (`< 1,000,000 $IRL`) can deposit **any amount (`> 0`)** into the Sherwood Guild.
  - As soon as the Guild's pooled balance reaches **`0.1%` of supply (`1,000,000 $IRL`)**, the Guild has the right to claim its free staking lottery tickets immediately with **ZERO 24h lock on the Guild's supply (`unstakeUnlockTime == 0`)** — small holders remain free to unstake at any time!
  - When a Guild ticket wins a lottery draw, the ETH jackpot is shared pro-rata among Guild members who are **still staking at the exact moment of the draw** and have staked for **`>= 8 hours`** (Daily Lottery) or **`>= 24 hours`** (Weekly Sunday Mega-Jackpot).
- **Hybrid 24h Staking & Free-Ticket Claim Mechanic for Individual Stakers (`IRLStaking.sol` & `IRLUniswapV4Hook.sol`):**
  - **Zero Unstake Lock by Default (`0h Lock`):** Depositing `$IRL` into `stake()` **never** locks `unstake()`.
  - **Option A — Mature Claim (`>= 24h` Staked $\rightarrow$ `0h Lock`):** Once an individual staker has staked for `>= 24 hours`, they claim their free tickets with **zero unstake lock**.
  - **Option B — Instant Claim (`< 24h` Staked $\rightarrow$ `24h Lock`):** If an individual staker claims free tickets before 24h of staking, their `unstake()` is locked for 24 hours (`unstakeUnlockTime[user] = block.timestamp + 24 hours`).
- **Maximum Volume Score Bonus:** `+50%` at `2.0%` staked (plus `+10%` on-chain referral boost).
- **Free Staking Tickets:** `1 Ticket at 0.1% (1,000,000 $IRL) scaling up to 10 Tickets every 4 days at 2.0% (20,000,000 $IRL)`.
- **Daily Volume Ticket Limit:** `6 Tickets/Day (0%) scaling to 10 Tickets/Day (2% Staked)`.
- **On-Chain Marketplace & Holding Caps:** `6 Daily / 42 Weekly (0%) scaling to 10 Daily / 70 Weekly (2% Staked)`, enforced directly inside `IRLTicketNFT._update`.

```text
Staking Multiplier Formula (Top 10 Leaderboard & Ticket Threshold):
ScoreMultiplier = 100% + min( (Staked_IRL × 50%) / 20,000,000 , 50% )

Eligible Real Yield Weight (30% Hourly Staker Stream):
EligibleStake(u) = 0                              if Staked_IRL < 1,000,000 (0.1%)
EligibleStake(u) = min(Staked_IRL, 20,000,000)    if Staked_IRL >= 1,000,000 (capped at 2.0%)

Free Staking Tickets Formula (Every 4 Days):
StakerTickets_4Days = max(1, (Staked_IRL × 10) / 20,000,000)   for Staked_IRL >= 1,000,000 (0.1%), capped at 10
UnstakeUnlockTime(Guild) = 0 (Never blocks 24h supply for Sherwood Co-Staking Guild)
```

| % Staked | Staked $IRL | 30% Real Yield Eligible Weight | Volume Multiplier (Top 10 & Tickets) | 0.05 WETH Swap Counted As | Swap Required for 1 Ticket (0.10 ETH Base) | Free Staking Tickets (Every 4 Days) | Daily Volume Ticket Limit | On-Chain Holding Caps |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **0.00%** (Non-staker) | 0 $IRL | 0 $IRL *(Below 0.1%)* | +0.00% (1.00x) | **0.0500 WETH** | **0.1000 ETH** | 0 Tickets | 6 Tickets / Day | 6 Daily / 42 Weekly |
| **0.10% (Min Yield & Guild Tier)** | 1,000,000 $IRL | **1,000,000 $IRL (0.10%)** | +2.50% (1.025x) | **0.05125 WETH** | **~0.0976 ETH** | **1 Ticket / 4 Days** | 6 Tickets / Day | 6 Daily / 42 Weekly |
| **0.25%** | 2,500,000 $IRL | **2,500,000 $IRL (0.25%)** | +6.25% (1.0625x) | **0.0531 WETH** | **~0.0941 ETH** | 1 Ticket / 4 Days | 6 Tickets / Day | 6 Daily / 42 Weekly |
| **0.50%** | 5,000,000 $IRL | **5,000,000 $IRL (0.50%)** | +12.50% (1.125x) | **0.05625 WETH** | **~0.0889 ETH** | 2 Tickets / 4 Days | 7 Tickets / Day | 7 Daily / 49 Weekly |
| **0.75%** | 7,500,000 $IRL | **7,500,000 $IRL (0.75%)** | +18.75% (1.1875x) | **0.0594 WETH** | **~0.0842 ETH** | 3 Tickets / 4 Days | 7 Tickets / Day | 7 Daily / 49 Weekly |
| **1.00%** | 10,000,000 $IRL | **10,000,000 $IRL (1.00%)** | +25.00% (1.25x) | **0.0625 WETH** | **0.0800 ETH** | 5 Tickets / 4 Days | 8 Tickets / Day | 8 Daily / 56 Weekly |
| **2.00% (Max Tier)** | **20,000,000 $IRL** | **20,000,000 $IRL (2.00% Max)** | **+50.00% (1.50x)** | **0.0750 WETH** | **~0.0667 ETH** *(0.075 qualifies)* | **10 Tickets / 4 Days (Max)** | **10 Tickets / Day (Max)** | **10 Daily / 70 Weekly** |

---

## 5. The Dual Lottery Engine (OpenVRF)

Raffle tickets are dynamic ERC-721 NFTs minted automatically upon reaching the volume threshold (`0.10 WETH` cumulative swap volume, boosted by staking multipliers), via progressive 4-day staking tiers, or relisted on the P2P Marketplace after 24 hours if left unclaimed in `claimableTickets`.

### 🕒 Daily Grand Jackpot (Strict 24h Epoch-Isolated Window)
- Tickets minted or relisted between `[dayStartTicketId[dayId], dayEndTicketId[dayId]]` are indexed chronologically, and prize funds are isolated per day in `dailyPotByDay[dayId]`.
- Every 24 hours at midnight UTC, the Hook requests randomness from the OpenVRF BLS oracle for the finished day's isolated pot (`dailyPotByDay[targetDay]`).
- **Unsold Relisted Ticket Rule:** If a ticket relisted from expired `claimableTickets` onto the P2P Marketplace is not bought before the draw and is selected as the winning ticket (`nftTicket.ownerOf(winningTokenId) == address(hook)`), **100% of the prize is transferred to the Dev Wallet (`owner()`)**.

### 🌟 Sunday Mega-Jackpot (Weekly Monster Draw)
- Encompasses all tickets minted or relisted Monday through Sunday `[weekStartTicketId[weekId], weekEndTicketId[weekId]]`, with prize funds isolated per week in `weeklyPotByWeek[weekId]`.
- Drawn every Sunday evening via OpenVRF, delivering monumental weekend community windfalls.

---

## 6. Verifiable 80/20 LP Custody & 10-Tier Auto-Withdrawing Dev/Marketing Vault (`IRLMarketingVault.sol`)

To guarantee deep permanent liquidity while funding progressive protocol growth strictly in converted ETH as market-cap milestones are achieved, `100%` of the `1,000,000,000 $IRL` supply is funded into **`IRLMarketingVault.sol`** during the atomic launch and seeded into Uniswap V4 `PoolManager` as **11 verifiable positions**:

1. **80% Core Liquidity Permanently Locked Forever (`800,000,000 $IRL` — `PERMANENT_LOCKED_SALT`):**
   - Seeded across the full upward price curve (`[permTickLower, permTickUpper]`).
   - `IRLMarketingVault` contains **zero withdrawal or decrease function** for `PERMANENT_LOCKED_SALT`. The 80% core liquidity principal is permanently and irreversibly locked in `PoolManager` forever.
2. **20% Multi-Tier Dev/Marketing Vault (`200,000,000 $IRL` — 10 Single-Sided LP Tiers of 2% Each):**
   - Split into **10 independent single-sided `$IRL` concentrated liquidity positions of `20,000,000 $IRL` (`2.0%` of supply) each** (`MARKETING_TIER_BASE_SALT + i`).
   - **10 Exact Market Cap Milestones:**
     - **Tier 0 (`2%`):** `$40,000 MC` (`2.0x` launch price)
     - **Tier 1 (`2%`):** `$70,000 MC` (`3.5x` launch price)
     - **Tier 2 (`2%`):** `$100,000 MC` (`5.0x` launch price)
     - **Tier 3 (`2%`):** `$250,000 MC` (`12.5x` launch price)
     - **Tier 4 (`2%`):** `$500,000 MC` (`25.0x` launch price)
     - **Tier 5 (`2%`):** `$750,000 MC` (`37.5x` launch price)
     - **Tier 6 (`2%`):** `$1,000,000 MC` (`50.0x` launch price)
     - **Tier 7 (`2%`):** `$1,500,000 MC` (`75.0x` launch price)
     - **Tier 8 (`2%`):** `$2,000,000 MC` (`100.0x` launch price)
     - **Tier 9 (`2%`):** `$5,000,000 MC` (`250.0x` launch price)
   - **Automatic 100% ETH Withdrawal by the Contract (`autoWithdrawReachedTiers`):** Once the pool price crosses a tier's upper tick bound, that 2% position is **100% converted into WETH**. The contract automatically withdraws the converted WETH, unwraps it to **100% native ETH**, and transfers it directly to the developer wallet (`owner`) during swaps/upkeeps!
3. **Atomic Initial Buy (`0.15 ETH`):**
   - Immediately after seeding the 80% permanent LP + 10×2% tiered vault positions in the same atomic launch plan, `executeInitialBuy` swaps `0.15 ETH` for `$IRL`.

---

## 7. Genesis Fair-Launch, Anti-Whale & 10% Launch Boost Mechanics

To ensure healthy token distribution and explosive early reward pots at pool initialization, the Uniswap V4 Hook enforces clearly bounded, one-time launch limits:

- **Total Supply:** 1,000,000,000 $IRL (100% Fixed, Zero Inflation)
- **Initial Market Cap:** ~$20,000 USD (with atomic `0.15 ETH` initial buy)
- **Max Transaction Limit (Up to $50k MC):** 10,000,000 $IRL (1.0% of supply)
- **Max Wallet Limit (Up to $50k MC):** 20,000,000 $IRL (2.0% of supply)
- **10.00% Launch Boost Tax (Max 24 Hours OR Up to $100k MC):** Supercharges early prize pools (`3.75%` Hourly Pot + `3.75%` Daily/Sunday Lottery Pots + `2.20%` Protocol/Buyback Pot + `0.30%` Programmable).

#### 🔓 Fixed Autonomous Market-Cap & Time Cutoffs ($50k MC & 24h / $100k MC)
The Hook configures `disableAntiWhaleSqrtPrice` (`$50,000 MC`) and `disableLaunchTaxSqrtPrice` (`$100,000 MC`) **once** during initialization via `setDisableAntiWhaleFromInitialPrice` (`CutoffsAlreadyInitialized` on any subsequent call; no owner setter exists to modify them after initialization) and evaluates them on every swap (`getSlot0`):
1. **At $50,000 Market Cap (`disableAntiWhaleSqrtPrice`, `2.5x` initial price):** Automatically and permanently disables the `1%` Max TX (`10M $IRL` on buys and sells) and `2%` Max Wallet (`20M $IRL`, enforced strictly on buys `irlDelta > 0` so holders at the `2%` boundary can always sell freely through the router) limits (`limitsEnabled = false; emit LimitsDisabled()`).
2. **At 24 Hours (`LAUNCH_TAX_DURATION = 24 hours`) OR $100,000 Market Cap (`disableLaunchTaxSqrtPrice`, `5.0x` initial price):** Automatically and permanently disables the 10% Launch Boost Tax (`launchTaxEnabled = false; emit LaunchTaxDisabled()`), switching permanently to the **4.00% Standard Cruise Tax** (`1.25% / 1.25% / 1.00% / 0.20% / 0.30%`). `launchTimestamp` is one-time and non-resettable.

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
| `/about` | Architecture | Comprehensive overview of the Robinhood thesis, V4 Hook mechanics, 10% Launch Boost (24h / $100k MC) $\rightarrow$ 4.0% Standard swap tax, and anti-whale protections. | Architecture |
| `/tokenomics` | Economics | In-depth breakdown of the 4.0% standard swap tax (`0.30%` Programmable, `1.25%` Hourly 35/35/30, `1.25%` Dual Lottery 50/50, `1.00%` Protocol & Keeper Gas, `0.20%` Hourly V4 Buyback & Burn to `0xdead`) and 10.0% Launch Boost (`0.30% / 3.75% / 3.75% / 1.70% / 0.50%`). | Smart Contract Specs |
| `/contracts` | Verification | Displays verified smart contract addresses ($IRL Token, V4 Hook, NFT Tickets, Staking Vault, Marketing Vault) with RobinhoodScan explorer links. | Live Onchain Registry |
| `/launch` | Roadmap | Current pre-launch phase, network details (Robinhood Chain, Chain ID 4663), 90% permanent locked LP + 10% conditional marketing LP proof, and fair launch roadmap. | Deployment Specs |
| `/socials` | Community | Verified links to official 𝕏 ([@IRL_Protocol](https://x.com/IRL_Protocol)), Telegram ([t.me/InternetRobinhoodLottery](https://t.me/InternetRobinhoodLottery)), and GitHub. *(Aliases: `/x`, `/twitter`)* | Official Channels |
| `/stake` | Real Yield | Complete guide to staking $IRL: native ETH dividends from 30% hourly stream, Hybrid 24h Free-Ticket Claim (0h lock by default & after 24h staked, or 24h lock on Instant-Claim), up to +50% volume multiplier, and expanded limits. | `IRLStaking.sol` |
| `/security` | Audit & Safety | Rug-proof liquidity architecture: 90% core liquidity permanently locked in `PoolManager` (`PERMANENT_LOCKED_SALT`) and 10% marketing allocation locked in `IRLMarketingVault.sol` (`MARKETING_VAULT_SALT`) with mathematical tick bounds. | `IRLMarketingVault.sol` |
| `/tickets` | Dynamic Query | Queries the total number of NFT lottery tickets currently in play, volume thresholds (0.10 WETH base), Hybrid 24h free staking tickets, P2P Marketplace 2% Lottery Tax, and daily limits. | `IRLTicketNFT.totalTicketsMinted()` |
| `/pot` | Live Treasury | Real-time balances of all onchain prize pots: Daily Grand Jackpot (`dailyPotByDay`), Sunday Mega-Jackpot (`weeklyPotByWeek`), Hourly Trader Pool, and Hourly Buyback & Burn Reserve. | `IRLUniswapV4Hook` View Methods |

### 🌐 Official Community & Social Links

- **Official 𝕏 (Twitter):** [@IRL_Protocol (x.com/IRL_Protocol)](https://x.com/IRL_Protocol)
- **Telegram Bot & Sanctuary:** [t.me/InternetRobinhoodLottery](https://t.me/InternetRobinhoodLottery)
- **GitHub Open-Source Whitepaper:** [github.com/math-crypt/lottery-robinhood](https://github.com/math-crypt/lottery-robinhood)

---

## 9. Argon v2.0 & Trail of Bits Final Pre-Launch Security Audit & Verification Runbook

Automated scanners (such as Slither, CertiK, ZAUTH) and independent reviewers can verify the authenticity, `CREATE2` provenance, and formal mathematical precision of the finalized Programmable.market launch architecture using the instructions below.

> 📄 **Official Audit Report:** For the complete line-by-line adversarial security audit (**38 / 38 findings & compliance checks verified**: `ARGON-V2-01..09` Programmable.market launch architecture, `ARGON-C01..L04` core adversarial audit, and `TOB-01..05` Trail of Bits formal invariants), EIP-170/EIP-3860 bytecode margins, and mathematical proofs, see [**`AUDIT_REPORT.md`**](AUDIT_REPORT.md).

### 🛡️ Repository History, Provenance & EIP-170 Bytecode Profile
- **Provenance-Verified Custom Launch Plan (`programmable.custom-launch-plan.v1`):** All 6 production contracts (`InternetRobinLottery`, `IRLUniswapV4Hook`, `IRLMarketingVault`, `IRLStaking`, `IRLTicketNFT`, `OpenVRF`) are compiled deterministically under `solc 0.8.26+commit.8a97fa7a` (`evm_version = "cancun"`, `via_ir = true`, `optimizer_runs = 1`) with 100% verified creation and runtime bytecode matching.
- **100% Original Core Architecture:** The central business logic—including the two-phase bounded V4 Hook tax (`10.00% Launch Boost -> 4.00% Standard`), `0.50% -> 0.20%` hourly batched V4 buyback & burn (with `0.30%` Programmable fee deducted once on buys, sells, and internal buybacks), `90% / 10%` verifiable LP custody (`PERMANENT_LOCKED_SALT` & `MARKETING_VAULT_SALT`), fixed launch-price cutoffs, dynamic volume-weighted Top 10 scoring with staker boost (`+0%` to `+50%`), `[0.1%, 2.0%]` eligible Real Yield staking tiers, Hybrid 24h Free-Ticket Claim, and epoch-isolated OpenVRF lottery pots—was engineered from scratch.

| Contract | Source File | Runtime Size (B) | Initcode Size (B) | EIP-170 Margin (`24,576 B`) | EIP-3860 Margin (`49,152 B`) |
| :--- | :--- | :---: | :---: | :---: | :---: |
| **OpenVRF Coordinator** | `lib/openvrf/src/OpenVRF.sol` | `23,167 B` | `23,572 B` | `+1,409 B` | `+25,580 B` |
| **V4 Lottery & Tax Hook** | `src/IRLUniswapV4Hook.sol` | `22,588 B` | `24,182 B` | `+1,988 B` | `+24,970 B` |
| **LP Custody & Marketing Vault** | `src/IRLMarketingVault.sol` | `12,915 B` | `13,323 B` | `+11,661 B` | `+35,829 B` |
| **NFT Ticket & P2P Market** | `src/IRLTicketNFT.sol` | `6,683 B` | `7,640 B` | `+17,893 B` | `+41,512 B` |
| **Real Yield Staking Vault** | `src/IRLStaking.sol` | `4,390 B` | `4,530 B` | `+20,186 B` | `+44,622 B` |
| **$IRL ERC-20 Token** | `src/InternetRobinLottery.sol` | `2,337 B` | `3,407 B` | `+22,239 B` | `+45,745 B` |

### 🔒 Argon v2.0 Final Pre-Launch & Programmable.market Audit Summary (`AUDIT_REPORT.md`)

| Audit ID | Severity | Audited Mechanism / Security Vector | On-Chain Verification & Guarantee |
| :--- | :---: | :--- | :--- |
| **`ARGON-V2-01`** | **High** | One-Time Launch Window, Fixed Cutoffs & `10.00% -> 4.00%` Transition | `launchTimestamp` & price cutoffs (`$50k MC` / `$100k MC`) are one-time and fixed after initialization; `10.00%` drops permanently to `4.00%` at **24h OR `$100,000 MC`** |
| **`ARGON-V2-02`** | **High** | Immutable `0.30%` (`30 bps`) Programmable Fee Across All 3 Paths | Hardcoded `PROGRAMMABLE_FEE_RECIPIENT = 0xD88539d3c4C460136a733A3Fd60cf6BF269079da` (`30 bps` once on normal buys, normal sells, and internal buybacks without double-charging) |
| **`ARGON-V2-03`** | **High** | Hourly V4 Buyback & Burn (`0.50%` Boost / `0.20%` Standard) | `0.50%` (`50 bps` Boost) / `0.20%` (`20 bps` Standard) reserved in `buybackPot`, pays `30 bps` Programmable fee once, and swaps remaining WETH to `$IRL` burned to `0xdead` |
| **`ARGON-V2-04`** | **High** | Verifiable `90% / 10%` LP Custody, Anti-Whale Direction & `0.15 ETH` Buy | `900M $IRL` (`90%`) locked forever (`PERMANENT_LOCKED_SALT`), `100M $IRL` (`10%`) conditional WETH-only LP (`MARKETING_VAULT_SALT`), `0.15 ETH` initial buy, and `irlDelta > 0` buy wallet cap |
| **`ARGON-V2-05`** | **Medium** | Recipient-Protected Pull Fallback (`unclaimedRewards`) | Failed ETH payouts in hourly or lottery distributions credit `unclaimedRewards[recipient]` (`claimUnclaimedRewards()`), never diverting user winnings to `protocolPot` |
| **`ARGON-V2-06`** | **Medium** | Strict Epoch-Isolated Lottery Pots (`dailyPotByDay` / `weeklyPotByWeek`) | Delayed keeper draws isolate `dailyPotByDay[dayId]` and `weeklyPotByWeek[weekId]` so new-epoch swap taxes never bleed into prior draws |
| **`ARGON-V2-07`** | **Medium** | Deterministic `CREATE2` & Atomic Executor Guard | Constructors & `_checkOwner()` / `_spendAllowance()` bind `0xe21827818Fea1F14d59929CAE36a93c0B44e0aE1` strictly to `tx.origin == owner` |
| **`ARGON-C01`** | **Critical** | `performUpkeep` arbitrary `actionType` & `timeId` manipulation | Strict on-chain preconditions (`curHour`, `curDay`, `curWeek`, `queueIndex`) enforced; `targetDay`/`targetWeek` derived on-chain |
| **`ARGON-C02`** | **Critical** | Zero-cooldown flash-stake ticket farming across wallets | Hybrid 24h Anti-Sybil Ticket Claim (`unstakeUnlockTime`: 0h lock by default & after ≥24h staked; 24h lock on Instant-Claim <24h) |
| **`ARGON-H01..H04`** | **High** | Hourly V4 Buyback, `_resolveTrader` Anti-Spoof, Exact-Out & Top 10 | Hourly batched V4 buyback to `0xdead`, `hookData` anti-spoofing, Exact-Out WETH delta fix, and sorted `topTradersPerHour[hourId]` with `+50%` staker boost |
| **`ARGON-M01..M05`** | **Medium** | `PositionManager` separation, `[0.1%, 2.0%]` tiers & VRF isolation | Separate `POSITION_MANAGER`, `unallocatedYield` pre-stake buffer, `[1M, 20M $IRL]` eligible tiers, `vrfRequestPrize` snapshots & `hourlyPotByHour` isolation |
| **`ARGON-L01..L04`** | **Low** | P2P Marketplace `2.0%` Lottery Tax & Weekly Holding Caps | Built-in P2P Marketplace (`98%` seller / `2%` Lottery Tax via `receiveMarketplaceTax`) & weekly holding cap (`42`–`70` tickets) in `IRLTicketNFT._update` |

### 🧪 Comprehensive Verification Suite (46/46 Passing Tests — 100% Pass Rate)

The repository includes an exhaustive Foundry unit, fuzz, formal invariant, and multi-month simulation suite:

```bash
# Clone the repository
git clone https://github.com/math-crypt/lottery-robinhood.git
cd lottery-robinhood

# Install dependencies
forge install

# Run the complete 46-test verification suite and check EIP-170 contract sizes
forge test -v
forge build --sizes
```

#### 📊 Complete 46-Test Verification Matrix (`forge test -v`)

| Test Suite | Test Function | Result | Gas / Fuzz Metric | Validation Scope |
| :--- | :--- | :---: | :---: | :--- |
| **Trail of Bits Invariants** | `test_Invariant_FeeConservation_ZeroWeiLeak_Fuzz` | **PASS** | `256 runs` (`μ: 5,387`) | Formal zero-wei fee conservation across 256 fuzz runs (0.001 to 1,000 ETH) |
| **Trail of Bits Invariants** | `test_Invariant_MarketingVault_DirectionalRugProof_Token0` | **PASS** | `275,828` | Proves dev cannot withdraw IRL liquidity when `tick < marketingTickUpper` (`token0`) |
| **Trail of Bits Invariants** | `test_Invariant_MarketingVault_DirectionalRugProof_Token1` | **PASS** | `276,780` | Proves dev cannot withdraw IRL liquidity when `tick > marketingTickLower` (`token1`) |
| **Trail of Bits Invariants** | `test_Invariant_OpenVRF_RouterExclusivity` | **PASS** | `1,905,528` | Proves unauthorized callers are unconditionally rejected with `"Only router"` |
| **Trail of Bits Invariants** | `test_Invariant_StakingSolvency_Fuzz` | **PASS** | `256 runs` (`μ: 925,289`) | Proves 100% staking & ETH yield solvency across 256 fuzz runs (with 0h default unstake lock) |
| **Trail of Bits Invariants** | `test_Invariant_StakingUnallocatedYieldBuffered` | **PASS** | `839,470` | Validates pre-stake `unallocatedYield` buffer & `[0.1%, 2.0%]` (`1M`–`20M $IRL`) tier bounds |
| **Programmable & Launch Tax** | `test_LaunchWindow_OneTimeNonResettable_And24HourExpiry` | **PASS** | `1,631,384` | One-time `launchTimestamp` (`AlreadyLaunched` on retry) & auto-drop `10% -> 4%` after `24h` |
| **Programmable & Launch Tax** | `test_LaunchTax_10PercentUpTo100kMarketCap_Then4Percent` | **PASS** | `3,102,309` | Exact wei split (`3.75%/3.75%/1.70%/0.50%/0.30%` -> `1.25%/1.25%/1.00%/0.20%/0.30%`) & fixed `$100k MC` cutoff |
| **Programmable & Launch Tax** | `test_LiquidityCustody_90PercentPermanentLock_10PercentMarketing_AndInitialBuy` | **PASS** | `5,302,686` | Verifies `900M` permanent LP lock (`PERMANENT_LOCKED_SALT`), `100M` marketing LP & `0.15 ETH` initial buy |
| **Programmable & Launch Tax** | `test_AntiWhale_BuyCapEnforced_And2PercentBoundaryHolderCanSellViaRouter` | **PASS** | `2,231,212` | Enforces `2%` (`20M $IRL`) wallet cap on buys (`irlDelta > 0`) & proves `2%` boundary holder sells via router |
| **Programmable & Launch Tax** | `test_ProgrammableFee_30BpsOnceOnBuySellAndInternalBuyback` | **PASS** | `2,178,998` | Verifies exact `30 bps` (`0.30%`) Programmable fee delta once on Normal Buy, Normal Sell & Internal Buyback |
| **Programmable & Launch Tax** | `test_UnclaimedRewards_ClaimableByRecipient_NotMovedToProtocol` | **PASS** | `2,325,714` | Failed ETH payouts credit `unclaimedRewards[recipient]` & are claimable via `claimUnclaimedRewards()` |
| **Programmable & Launch Tax** | `test_DelayedDraws_EpochIsolatedLotteryPots` | **PASS** | `2,986,442` | Delayed keeper draws strictly isolate `dailyPotByDay[dayId]` and `weeklyPotByWeek[weekId]` |
| **Programmable & Launch Tax** | `test_AntiWhale_AutoDisableAt50kMarketCap` | **PASS** | `1,584,673` | `1%` Max TX and `2%` Max Wallet limits auto-disable permanently at fixed `$50k MC` (`2.5x` launch) |
| **Programmable & Launch Tax** | `test_NFTTicket_OnChainHoldingCapEnforced` | **PASS** | `4,334,823` | Enforces dynamic weekly NFT holding caps (`42` to `70` tickets) on secondary P2P transfers |
| **OpenVRF Integration** | `test_OpenVRF_Deployment_Parameters` | **PASS** | `35,232` | Native OpenVRF coordinator initialization, owner, relayer authorization & 0 base fees |
| **OpenVRF Integration** | `test_OpenVRF_ConsumerAuthorization` | **PASS** | `149,566` | Strict access control on consumers and callback gas limit boundaries (`25k`–`1M` gas) |
| **OpenVRF Integration** | `test_OpenVRF_CryptographicDrandFulfillment` | **PASS** | `512,478` | Real Drand round 1000 BLS cryptographic signature verification via EVM pairing precompiles |
| **OpenVRF Integration** | `test_IRLUniswapV4Hook_DailyLottery_EndToEndWithOpenVRF` | **PASS** | `2,523,370` | Full 24h daily draw: swaps -> tax -> tickets -> upkeep -> OpenVRF -> instant ETH payout |
| **OpenVRF Integration** | `test_IRLUniswapV4Hook_SundayMegaJackpot_EndToEndWithOpenVRF` | **PASS** | `3,709,945` | Full 7-day Sunday Mega-Jackpot draw with multiple traders, upkeep and OpenVRF distribution |
| **OpenVRF Integration** | `test_Security_UnauthorizedCallerCannotSpoofRandomness` | **PASS** | `34,742` | Hook rejects unauthorized callers attempting to spoof randomness with `"Only router"` |
| **Stress & Validation** | `testStaking_HalfTierAndLinearCalculations` | **PASS** | `3,179,885` | Hybrid staking claim (Instant Claim locks 24h vs ≥24h Mature Claim 0h lock) & Real Yield claim |
| **Stress & Validation** | `testMarketplace_2PercentLotteryTaxRouting_DailyAndWeeklyVsWeeklyOnly` | **PASS** | `1,698,643` | P2P Marketplace 2% Lottery Tax routing (50/50 Daily+Sunday vs 100% Sunday Mega-Jackpot) |
| **Stress & Validation** | `testFeeDistribution_PreciseWeiCalculationsAcrossTxSizes` | **PASS** | `1,353,585` | Exact swap tax distribution down to the single wei (`0.30%` Prog, `1.25%` Hourly, `1.25%` Lottery, `1.00%` Protocol, `0.20%` Burn) |
| **Stress & Validation** | `testNFTVolumeLimits_NonStakerVsHalfStakerVsFullStaker` | **PASS** | `4,112,913` | Strict daily volume ticket caps (`6` for `0%`, `8` for `1%`, `10` for `2%`) with zero excess minting |
| **Stress & Validation** | `testHourlyRewards_MassiveBatchQueueStressTest_60Traders` | **PASS** | `47,815,681` | Queue stress test with 60+ traders exceeding 50-item batch limit, proving Top 10 + cashback payout |
| **Stress & Validation** | `testDailyAndWeeklyLottery_MassiveScale_50Traders` | **PASS** | `145,829,957` | Massive dual lottery with 50 traders generating hundreds of tickets over 7 days with OpenVRF payouts |
| **Stress & Validation** | `testTelegramBot_AllContractViewQueries` | **PASS** | `1,347,325` | Validates all RPC read methods invoked by `bot/index.js` (`dailyLotteryPot`, `sundayMegaPot`, etc.) |
| **Stress & Validation** | `testDeveloperVault_SingleSidedLPRugProofAndWETHClaim` | **PASS** | `3,714,806` | Single-Sided LP anti-rug tick invariant and fee collection of accumulated WETH to dev wallet |
| **Stress & Validation** | `testSecurityFixes_AuditRemediationSuite` | **PASS** | `2,675,633` | Validates `performUpkeep` guards, Hybrid 24h claim lock, hourly V4 `WETH -> $IRL` buyback & Exact-Out swaps |
| **Protocol Scenarios** | `testSimulation_1Day_HourlyAndDailyDraw` | **PASS** | `52,305,540` | 24 consecutive hours of trading, volume rewards, midnight OpenVRF randomness fulfillment, and winner payout |
| **Protocol Scenarios** | `testSimulation_1Week_DailyDrawsAndSundayMegaJackpot` | **PASS** | `10,917,634` | 7 daily cycles, 4-day epoch staking ticket claims, zero-trade rollover to Sunday, and Sunday Mega-Jackpot |
| **Protocol Scenarios** | `testSimulation_1Month_ContinuousFlywheel` | **PASS** | `57,598,694` | 30-day flywheel, continuous staking yield in native ETH, and hourly batched V4 buyback & burn to `0xdead` |
| **Protocol Scenarios** | `testSecurityHardening_RevertingWinnerAndFallbackPots` | **PASS** | `3,503,447` | Reverting winner contract safely credits `unclaimedRewards[winner]` without blocking OpenVRF callback |
| **Hook Unit Tests** | `testAfterSwapTracksVolume` | **PASS** | `1,447,849` | Hook `_afterSwap` volume accumulation and volume-weighted trader scoring |
| **Hook Unit Tests** | `testDailyVolumeLimitsNonStakerVsStaker` | **PASS** | `3,261,296` | Daily ticket quotas (`6` vs `10`) and weekly holding quotas (`42` vs `70`) |
| **Hook Unit Tests** | `testStakerTicketVolumeMultiplierAnd4DayEpoch` | **PASS** | `2,410,393` | Staking multipliers (`+50%`), Hybrid 24h claim, and 4-day epoch free ticket claims |
| **Ecosystem Simulation** | `testProgrammableFeeRoutingAndClaiming` | **PASS** | `2,190,333` | Immutable `0.30%` fee forwarding to Programmable.market, buffer accumulation, and claiming |
| **Ecosystem Simulation** | `testFullSimulationWithLogs` | **PASS** | `3,146,647` | End-to-end trace with detailed console logging across swaps and distributions |
| **Ecosystem Simulation** | `testMassiveSimulation` | **PASS** | `517,029,334` | Multi-agent heavy trading simulation validating long-term protocol solvency |
| **Position Manager** | `test_burn` | **PASS** | `655,943` | Uniswap V4 PositionManager position burning |
| **Position Manager** | `test_decreaseLiquidity` | **PASS** | `664,842` | Uniswap V4 PositionManager liquidity reduction |
| **Position Manager** | `test_increaseLiquidity` | **PASS** | `688,938` | Uniswap V4 PositionManager liquidity addition |
| **Position Manager** | `test_increaseLiquidityNative` | **PASS** | `622,560` | Uniswap V4 PositionManager native ETH liquidity addition |
| **Position Manager** | `test_mintLiquidity` | **PASS** | `481,707` | Uniswap V4 PositionManager position minting |
| **Position Manager** | `test_mintLiquidityNative` | **PASS** | `425,722` | Uniswap V4 PositionManager native ETH position minting |

---

## 🛡️ License & Verification

This project is licensed under the [MIT License](LICENSE).  
Smart contracts are open source, fully verified, and transparent on Robinhood Chain.



