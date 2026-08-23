# Lottery Robinhood

![Robinhood Chain](https://img.shields.io/badge/Network-Robinhood_Chain-green)
![Uniswap V4](https://img.shields.io/badge/Uniswap-V4_Hook-pink)
![Foundry](https://img.shields.io/badge/Built_with-Foundry-blue)

Lottery Robinhood is an innovative decentralized token ecosystem built on the **Robinhood Chain** (Arbitrum L2), leveraging **Uniswap V4 Hooks** to provide seamless volume-based rewards and a daily on-chain lottery.

## 🎯 Vision

Traditional reward tokens heavily rely on internal contract taxes that create artificial sell pressure ("dumping") when rewards are distributed. Lottery Robinhood solves this by utilizing a cutting-edge Uniswap V4 Hook to perform **Swap-and-Liquify**.

Taxes are collected and instantly converted to **ETH** during the swap routing process, ensuring that the reward and lottery pools are filled with native gas tokens, protecting the token's chart from constant inflationary selling.

## ⚙️ Tokenomics & Mechanics

- **Network:** Robinhood Chain
- **Total Tax:** 3% on Swaps
  - **1% Lottery Pool:** Automatically converted to ETH.
  - **1% Volume Rewards:** Automatically converted to ETH.
  - **1% Protocol / LP:** Covers Chainlink VRF and Automation gas fees.

### 🏆 Hourly Volume Rewards
Instead of rewarding passive "whales" holding the token, the protocol rewards active ecosystem participants. The 1% Volume Reward pot is distributed **every hour** in ETH:
- **50% of the pot** is distributed to the **Top 10 traders** (by volume) of that hour.
- **50% of the pot** is distributed proportionally to **all traders** who contributed to the volume during that hour.
*(Users claim their accumulated ETH rewards via a secure pull-pattern to ensure network efficiency).*

### 🎟️ Daily On-Chain Lottery
- Users receive **1 Lottery Ticket** for every `0.1 ETH` of qualifying trading volume.
- Maximum of 5 tickets per wallet per day to maintain fairness.
- Daily draws are executed automatically via **Chainlink Automation** and secured by **Chainlink VRF** (Verifiable Random Function).
- The winner receives the accumulated ETH lottery pot.

### 🛡️ Security Features
- **Anti-Sybil & Wash Trading:** Only swaps routed through the official Uniswap V4 Router are eligible for volume tracking and lottery tickets.
- **Gas Optimized:** Native V4 hook integration reduces the gas overhead compared to traditional reflection tokens.

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
