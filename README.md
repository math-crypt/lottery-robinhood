# 🏹 Internet Robinhood Lottery ($IRL)

![Robinhood Chain](https://img.shields.io/badge/Network-Robinhood_Chain-green) ![Uniswap V4](https://img.shields.io/badge/Uniswap-V4_Hook-pink) ![Foundry](https://img.shields.io/badge/Built_with-Foundry-blue)

```text
     (
      \
       )
##-------->  $IRL Lottery
       )
      /
     (
```

**We steal from the whales to give back to the community!**

$IRL is an innovative DeFi ecosystem running natively on the Robinhood Chain, utilizing cutting-edge **Uniswap V4 Hooks** to create a fair, gamified, and highly rewarding environment.

---

## ⚠️ Phase 1: 100% On-Chain, Zero Trust Required

There is currently **NO official website or DApp**.
Everything in Phase 1 happens **100% On-Chain**, directly on the Robinhood Scan block explorer, and is coordinated via our official Telegram bot.
- No phishing risk
- Fully verified open-source contracts
- Unstoppable logic

Join the community: [t.me/InternetRobinhoodLottery](https://t.me/InternetRobinhoodLottery)

---

## 🌟 Core Mechanics (Powered by Uniswap V4)

All mechanics are built directly into the Uniswap V4 Liquidity Pool via a custom Hook. There are zero external dependencies to execute tokenomics, meaning the chart never dumps to fund rewards!

### 1️⃣ The Daily Lottery (OpenVRF)
Trade $IRL to accumulate volume. Every time you cross the volume threshold, an **NFT Ticket** is automatically minted to your wallet.
Every day, an **OpenVRF** oracle draws a random winning ticket, and the holder instantly receives the entire **1% Daily Lottery Pot** in ETH!

### 2️⃣ Hourly Rewards (Dynamic Global Score)
The 1% Hourly Reward Pot is split in two:
- **0.5%** is automatically redistributed to all traders as **Instant Cashback** on every single trade!
- **0.5%** is shared among **ALL Active Traders** at the end of the hour, perfectly proportional to your "Volume Score". There is no fixed "Top 10" limit—if 5,000 people trade, 5,000 people get a share of the pot!

### 3️⃣ Staking Multipliers
Stake your $IRL tokens in the official Staking Contract to unlock powerful boosts:
- **Bonus NFT Tickets** for the daily lottery.
- Up to a **1.5x Multiplier** on your Volume Score! Earn a massive share of the Hourly Pot without needing to over-trade.

### 4️⃣ Transparent Liquidity & Marketing (100% Rug-Proof)
To guarantee complete safety for all investors, we use the most advanced DeFi security architecture on Uniswap V4:

- **90% Base Liquidity (BURNED)** 🔥
  The main liquidity pool NFT is permanently burned (sent to `0x000...dEaD`). This means the core trading liquidity is locked forever. **It is mathematically impossible to rug-pull the LP.** Users can trade safely for eternity!

- **10% Marketing Liquidity (SMART VAULT)** 🧠
  Instead of keeping marketing tokens in a dev wallet (which creates dump risks), 100% of the marketing supply is deployed as *Single-Sided Liquidity* in the V4 pool, far above the launch price.
  These tokens are locked in the `IRLMarketingVault` smart contract. 
  **The Vault mathematically blocks the dev from withdrawing IRL tokens.** The dev can ONLY collect ETH once the market naturally buys those tokens at higher market caps.
  ➡️ *Zero red candles. Zero dump risk. 100% organic transparent growth.*

---

## 📊 Tokenomics

Strict **3% tax** on every swap (buys and sells), extracted natively in WETH:

- 🏆 **1% Daily Lottery**: Airdropped to a random ticket holder daily.
- ⏱️ **1% Hourly Rewards**: Split 50/50 between the Global Trader Pool and Instant Cashback.
- ⚙️ **1% Protocol**: Used to pay for OpenVRF gas, automation upkeep, and marketing.

*Initial Market Cap: $20,000 with strict Anti-Whale max transaction limits at launch.*

---

## 🛠️ Developer Resources

- **Token Contract**: `src/InternetRobinLottery.sol`
- **V4 Hook Engine**: `src/IRLUniswapV4Hook.sol`
- **Staking Contract**: `src/IRLStaking.sol`
- **NFT Tickets**: `src/IRLTicketNFT.sol`
- **Telegram Bot**: `bot/index.js`
