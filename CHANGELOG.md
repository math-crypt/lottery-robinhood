# Changelog

All notable changes to this project will be documented in this file. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]
### Added
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

### Fixed
- Fixed bug in Hook where a single large swap only minted 1 NFT instead of multiple tickets when crossing multiple volume thresholds simultaneously.
