# Development Plan - Lottery Robinhood Token

## 🎯 Objective
Develop a smart contract ecosystem for a "Lottery" and "Robinhood" redistribution token on Robinhood Chain (Arbitrum L2).

## 📋 Development Phases

- [x] Framework Selection: Solidity (Foundry).
- [x] Tokenomics Definition:
  - Network: **Robinhood Chain** (Arbitrum L2, EVM-compatible, Gas: ETH).
  - Architecture: **Uniswap V4 Hook**. Taxes and reward logic handled natively in a V4 Hook.
  - Tax (3%): 1% Lottery, 1% Volume Rewards, 1% LP/Marketing.
  - Tax Management: Hook intercepts the swap, collects the tax, and converts it to ETH (*Swap-and-Liquify*).
  - Volume Rewards Mechanic: Distributed every hour. 50% to the Top 10 traders of the hour, 50% proportionally to all traders of the hour. (Requires a claim/pull pattern to prevent gas limit issues).
  - Lottery Mechanic: Volume tracking via the Hook. VRF & Automation draws (via Chainlink).
- [x] Base ERC20 Contract Creation.

### Phase 1.5: Infrastructure & Transparency
- [x] Draft Whitepaper / Grant Proposal (mechanics, tokenomics, vision).
- [x] Setup public GitHub repository with a clear README.

### Phase 2: Specific Mechanics (Lottery & Robinhood V4 Hook)
- [x] Implement tax collection system in the V4 Hook (`afterSwap`).
- [x] Implement Lottery mechanic (NFT Tickets, Chainlink VRF).
- [x] Implement Robinhood mechanic (Top 10 leaderboard, Chainlink Keepers).
- [x] Unit and Integration Tests (Simulation of V4 Swap & Volume Tracking).

### Phase 2.5: Staking Mechanics
- [x] Implement Token Staking Contract / Logic.
- [x] Update Lottery mechanics to grant extra chances/tickets based on staked amounts.
- [x] Update Volume Reward mechanics to grant a percentage bonus based on staked amounts.

### Phase 3: Deployment & Verification
- [x] Deployment Script (Testnet) & Initial Liquidity setup (20k MC via V4 Hook).
- [ ] Contract Verification.
- [x] Transaction simulations and tax/lottery verification.

---

## 📝 Session Log

- **2026-08-24**: 
  - Initialized tracking files (AUDIT_PLAN, CHANGELOG, BACKLOG) and agent rules. 
  - Tokenomics validation (3% Tax: 1% Lottery, 1% Volume Rewards, 1% LP/Marketing).
  - Defined architecture: **Robinhood Chain (Arbitrum L2)**, **Uniswap V4 Hook**, Chainlink VRF & Keepers.
  - Authored Grant Proposal for funding.
  - Built core Smart Contracts (`InternetRobinLottery.sol`, `IRLTicketNFT.sol`, `IRLUniswapV4Hook.sol`).
  - Added NFT Minting logic, Telegram Events, and removable Anti-Whale protections (Max Tx / Max Wallet).
  - Executed successful Foundry simulations (`IRLUniswapV4Hook.t.sol`), testing swap tracking and NFT payouts.
  - Received external ZAUTH audit (62/100). Implemented critical security fixes (ReentrancyGuard, active ETH distributions, Pot variables).
  - Pushed all progress to public GitHub.
  
- **2026-10-08**:
  - Updated plan to include new ideas from user: a staking mechanism for bonus lottery chances and reward percentages, and a 20k Market Cap deployment via V4 Hook.
  - Added Phase 2.5 for Staking Mechanics and updated Phase 3 in AUDIT_PLAN.md.
  - **Refactored V4 Hook for Real Tax Collection (Swap-and-Liquify)**: Implemented advanced `BEFORE_SWAP_RETURNS_DELTA` and `AFTER_SWAP_RETURNS_DELTA` to natively intercept and extract WETH on both Buys and Sells natively using V4 `PoolManager.take()`.
  - Reverted Lottery to a pure Push pattern that gracefully ignores failures (unclaimed ETH falls back to the Developer protocol pot) to keep user experience frictionless.
  - Updated deployment and test scripts to accommodate new WETH hook arguments and dynamic flags.

- **2026-10-09**:
  - Updated README.md logos to the previous simpler badges.
  - Setup and executed `SimulationEcosystem.t.sol` to simulate the full ecosystem (swaps, tax collection, hourly distributions, end-of-day lottery).
  - Fixed Uniswap V4 Permit2 approvals for WETH in test environments.
  - Fixed a critical state variable bug in `IRLUniswapV4Hook.sol` where the hourly distribution queue was reading off the reset data for the new hour instead of the completed hour.
  - Rebalanced the NFT Ticket staking logic: Tracked volume in WETH (0.05 WETH threshold per ticket) to prevent inflated volume calculations. Capped maximum staking tickets exponentially (x2 required for each additional max ticket).
