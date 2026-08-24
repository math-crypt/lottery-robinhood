# Internet Robin Lottery ($IRL)

![Robinhood Chain](https://img.shields.io/badge/Network-Robinhood_Chain-green)
![Uniswap V4](https://img.shields.io/badge/Uniswap-V4_Hook-pink)
![Foundry](https://img.shields.io/badge/Built_with-Foundry-blue)

Internet Robin Lottery ($IRL) is an innovative decentralized token ecosystem built on the **Robinhood Chain** (Arbitrum L2), leveraging **Uniswap V4 Hooks** to provide seamless volume-based rewards and a daily on-chain lottery driven by NFT tickets.

## 🎯 Vision

Traditional reward tokens heavily rely on internal contract taxes that create artificial sell pressure ("dumping") when rewards are distributed. $IRL solves this by utilizing a cutting-edge Uniswap V4 Hook to perform **Swap-and-Liquify**.

The base ERC20 token (`InternetRobinLottery.sol`) is completely tax-free and secure. All taxes are collected and instantly converted to **WETH** during the swap routing process by the V4 Hook, ensuring that the reward and lottery pools are filled with native gas tokens, protecting the $IRL chart from constant inflationary selling.

## ⚙️ Tokenomics & Mechanics

- **Network:** Robinhood Chain
- **Token:** $IRL
- **Main Pool:** `IRL / WETH`
- **Total Tax:** 3% on Swaps
  - **1% Lottery Pool:** Automatically converted to WETH.
  - **1% Volume Rewards:** Automatically converted to WETH.
- **1% Protocol / LP:** Covers Chainlink VRF and Automation gas fees.

### 🛡️ Fair Launch & Anti-Whale Mechanics
To protect early investors from sniper bots and massive whales controlling the supply, the Hook strictly enforces on-chain limits during the launch phase (Discovery Phase):
- **Max Transaction:** `1%` of Total Supply per swap.
- **Max Wallet:** `2%` of Total Supply per wallet.
- **Removable Limits:** The contract owner can permanently disable these limits by calling `removeLimits()` once the ecosystem's Market Cap reaches a healthy and stable threshold, allowing institutional volume to enter safely.

### 🏆 Hourly Volume Rewards
Instead of rewarding passive "whales" holding the token, the protocol rewards active ecosystem participants. The 1% Volume Reward pot is distributed **every hour** in ETH:
- **50% of the pot** is automatically airdropped to the **Top 10 traders** (by volume) of that hour (distribution is proportional to their volume inside the Top 10 to encourage competition).
- **50% of the pot** is distributed proportionally to **all traders** who contributed to the volume during that hour.
*(To prevent blockchain gas limits, mass-distribution is handled via a queue system automatically processed by **Chainlink Automation Keepers**. No website claiming required!)*

### 🎟️ Daily On-Chain Lottery (NFT Tickets)
- Users receive **1 NFT Lottery Ticket** (`IRLTicketNFT` ERC721) minted directly to their wallet for every `0.1 ETH` of qualifying trading volume.
- Maximum of 5 NFT tickets per wallet per day to maintain fairness.
- Daily draws are executed automatically via **Chainlink Automation** and secured by **Chainlink VRF** (Verifiable Random Function).
- Chainlink VRF draws a winning `TokenId` and the owner of that specific NFT receives the accumulated ETH lottery pot!

### 🤖 Telegram Bot Integration
The Smart Contracts are designed with transparency and community engagement in mind. The Uniswap V4 Hook emits highly specific `Events` tailored for off-chain Telegram Bots to track the ecosystem in real-time:
- `Top10Updated`: Live Leaderboard updates on every swap.
- `TicketMinted`: Live notification when someone earns a Lottery NFT.
- `LotteryWinnerDrawn`: Massive celebration alert when the daily VRF draw finds a winner.

### 🛡️ Security & Trust (Anti-Rug)
To ensure the absolute safety of investor funds, the $IRL ecosystem strictly adheres to DeFi security standards:
- **Locked Liquidity:** Initial LP tokens (WETH/IRL) will be cryptographically locked in a public third-party locker for 12 months at launch.
- **Pure ERC20:** The `$IRL` token is a pure, unmodified standard ERC20. There are absolutely **no `mint()`** or **`blacklist()`** functions. The 1 Billion supply is fixed forever.
- **Renounced Ownership:** Once the initial Market Cap is stabilized and the Anti-Whale `removeLimits()` is executed, the contract ownership will be permanently renounced (`renounceOwnership()`), rendering the code immutable.
- **Public & Verifiable:** All Hook, NFT, and VRF logic is 100% open-source and will be verified on the block explorer for community auditing.

## 🛠️ Development (Foundry)

This project is built using [Foundry](https://getfoundry.sh/) and the official Uniswap v4-template.

### Prerequisites
- [Foundry](https://getfoundry.sh/)

### Build & Test
```shell
# Install dependencies
forge install

# Compile contracts
forge build

# Run tests
forge test
```
