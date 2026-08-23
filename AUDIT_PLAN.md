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
- [ ] Base ERC20 Contract Creation.

### Phase 1.5: Infrastructure & Transparency
- [ ] Draft Whitepaper (mechanics, tokenomics, vision).
- [x] Setup public GitHub repository with a clear README.

### Phase 2: Specific Mechanics (Lottery & Robinhood V4 Hook)
- [ ] Implement tax collection system in the V4 Hook (`afterSwap`).
- [ ] Implement Lottery mechanic (random selection, participation conditions via VRF).
- [ ] Implement Robinhood mechanic (redistribution, burn, or charity wallet).
- [ ] Unit and Integration Tests.

### Phase 3: Deployment & Verification
- [ ] Deployment Script (Testnet).
- [ ] Contract Verification.
- [ ] Transaction simulations and tax/lottery verification.

---

## 📝 Session Log

- **2026-08-24**: 
  - Initialized tracking files (AUDIT_PLAN, CHANGELOG, BACKLOG) and agent rules. 
  - Tokenomics validation (3% Tax: 1% Lottery, 1% Volume Rewards, 1% LP/Marketing).
  - Architectural decisions: Project will be deployed on **Robinhood Chain (L2 Arbitrum)** as a **Uniswap V4 Hook** to enable *Swap-and-Liquify* into ETH without impacting the ERC20.
  - Foundry installed successfully and Uniswap V4 template initialized. Ready to code the Hook!
