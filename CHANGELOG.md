# Changelog

All notable changes to this project will be documented in this file. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

### Added
- **OpenVRF Integration**: Migrated the Lottery Hook from Chainlink VRF to the native, `drand`-backed OpenVRF architecture required by Robinhood Chain.
- Submodule `lib/openvrf` added to support the new `RandomnessConsumer` interface.

### Changed
- `IRLUniswapV4Hook.sol` now inherits from `RandomnessConsumer` instead of `VRFConsumerBaseV2`.
- `DeployLotteryEcosystem.s.sol` updated to inject the OpenVRF Router address and removed legacy Chainlink variables.
- Hardcoded `WETH` and `PoolManager` addresses specific to the Robinhood Chain (Chain ID 4663).
- **Staking Mechanics (Phase 2.5):** Created `IRLStaking.sol` and integrated it into the V4 Hook.
- Added Staking Multipliers in Hook: +1 max lottery ticket per 10k IRL staked.
- Added Staking Multipliers in Hook: +1% bonus on hourly volume rewards per 10k IRL staked (capped at +50%).
- **Deployment Script (Phase 3):** Created `DeployLotteryEcosystem.s.sol` which handles full ecosystem deployment, Hook mining, and precise pool initialization for a 20k USD Market Cap launch.
- Initialized project management files (`AUDIT_PLAN.md`, `BACKLOG.md`).
- Set up AI agent development rules (`.agents/AGENTS.md`).
- Validated "Volume Rewards Token" tokenomics (3% Tax, VRF, Volume redistribution).
- Defined target network (Robinhood Chain).
- Added *Swap-and-Liquify* mechanic: taxes are converted to ETH by the contract for the lottery and rewards to prevent sell pressure.
- Planned transparency infrastructure (Whitepaper & Public GitHub).
- Authored Grant Proposal for early ecosystem funding on Arbitrum / Robinhood.
- Developed `InternetRobinLottery.sol` (base ERC20) and `IRLTicketNFT.sol` (ERC721).
- Developed `IRLUniswapV4Hook.sol` core mechanics: real-time Top 10 leaderboard sorting and volume tracking.
- Integrated Chainlink VRF in Hook for daily NFT lottery winner selection.
- Integrated Chainlink Keepers (Automation) for automated hourly airdrops of the 1% volume reward pot.
- Designed structured Solidity `Events` specifically for future Telegram Bot integration.
- Added comprehensive swap simulation test in `IRLUniswapV4Hook.t.sol` using Foundry, proving NFT minting and top 10 mechanics.
- Added Removable Anti-Whale Launch Mechanics (`MAX_TX_AMOUNT` and `MAX_WALLET_AMOUNT`) to `IRLUniswapV4Hook.sol` to protect early liquidity.
- **V4 Custom Accounting**: Completely refactored the tax collection to natively extract WETH on both exactIn and exactOut swaps using `BEFORE_SWAP_RETURNS_DELTA` and `AFTER_SWAP_RETURNS_DELTA` with `PoolManager.take()`.
- Added `protocolPot` and `withdrawProtocolFees()` to ensure the developer can safely extract the 1% unassigned tax.

### Fixed
- Fixed bug in Hook where a single large swap only minted 1 NFT instead of multiple tickets when crossing multiple volume thresholds simultaneously.
- **Logic:** Fixed a critical state variable bug in `IRLUniswapV4Hook.sol` where the hourly distribution queue (`_processQueueBatch`) was reading off the reset data for the new hour instead of the completed hour due to premature state update of `lastProcessedHour`.
- **Logic:** Replaced placeholder `TODO` in `_afterSwap` with actual simulated volume tax distribution (splitting the 3% into `lotteryPot` and `hourlyRewardPot` state variables).
- **Security:** Added `ReentrancyGuard` to prevent reentrancy attacks during ETH distribution in automated functions (`performUpkeep`).
- **Security:** Replaced stubbed prize distribution with live, secure ETH transfers (`.call{value: prize}("")`) for daily lottery winners and top 10 queue batches.

### Changed
- Refactored NFT Ticket staking scaling: Volume threshold is now tracked in WETH rather than tokens (0.05 WETH threshold) to prevent instant cap-outs. Maximum bonus tickets via staking is now exponentially capped (x2 required for each additional max ticket).
- **NFT Independence:** Separated Volume tickets and Staking tickets. Staking tickets are now independent of the volume base limit (which is capped strictly at 6 tickets/day).
- Added `claimDailyStakingTickets()` to allow stakers to freely mint their daily bonus tickets without trading. If they trade, it auto-mints to save gas.
- Restored simpler tech stack badges (Robinhood Chain, Uniswap V4, Foundry) in `README.md`.
- Reverted VRF Lottery to a pure Push payout (`call{value}`). If the transfer fails, the ETH elegantly falls back into the `protocolPot` instead of reverting the Chainlink callback.
- **Testing:** Executed a massive 500-user per hour simulation. Verified Upkeep scaling with batches of 50 costing only ~69k gas.
- **Logic:** Fixed skip-hour bug in Upkeep where multi-hour gaps would only process the latest hour.
- **Docs:** Added SYSTEM_ARCHITECTURE.md with complete project overview.
- Cleaned test suite from git tracking.
- **Testing:** Resolved block gas limit bottlenecks in massive testing scenarios by adjusting daily simulated swaps (from 1000 to 300) to safely test the end-to-end full deployment scale without reverting local Foundry VM.
