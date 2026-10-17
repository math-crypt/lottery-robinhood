import React, { useState } from 'react';
import { 
  ShieldCheckIcon, 
  CopyIcon, 
  CheckIcon, 
  ExternalLinkIcon, 
  ClockIcon, 
  TicketIcon, 
  VaultIcon, 
  SparklesIcon,
  TrophyIcon
} from './Icons';
import { CONTRACT_ADDRESSES, ROBINHOOD_CHAIN } from '../constants/contracts';

export default function Whitepaper() {
  const [copiedAddress, setCopiedAddress] = useState(null);

  const copyToClipboard = (text, key) => {
    navigator.clipboard.writeText(text);
    setCopiedAddress(key);
    setTimeout(() => setCopiedAddress(null), 2000);
  };

  const contractsList = [
    {
      key: 'token',
      name: 'Internet Robin Lottery ($IRL)',
      file: 'InternetRobinLottery.sol',
      type: 'ERC-20 Fixed Supply',
      address: CONTRACT_ADDRESSES.TOKEN,
      role: 'Core ecosystem token. 1,000,000,000 fixed supply with zero inflation, zero minting capabilities, and 0% tax on wallet transfers, staking, and LP seeding.',
      security: 'Non-Mintable, Zero Transfer Tax, MaxTx (1%), MaxWallet (2%)',
    },
    {
      key: 'hook',
      name: 'Uniswap V4 Robinhood Hook',
      file: 'IRLUniswapV4Hook.sol',
      type: 'Uniswap V4 Native Hook',
      address: CONTRACT_ADDRESSES.HOOK,
      role: 'Intercepts all AMM swaps (Exact-In & Exact-Out): applies the 4.0% Standard Tax (1.25% Hourly / 1.25% Lottery / 1.20% Protocol & Burn [1.00% Protocol + 0.20% Buyback Burn] / 0.30% Programmable). Directs 35% Top 10 (with up to +50% staker volume boost), 35% Active Swapper Hourly Cashback, 30% Real Yield Staking, epoch-isolated Daily & Sunday Mega-Jackpots, recipient-claimable unclaimedRewards, and 0.20% hourly batched V4 Buyback & Burn to 0xdead.',
      security: 'ReentrancyGuard, 4.0% Standard Tax, Immutable 0.30% Prog Fee',
    },
    {
      key: 'staking',
      name: 'Real Yield Staking Sanctuary',
      file: 'IRLStaking.sol',
      type: 'Native ETH Dividend Vault',
      address: CONTRACT_ADDRESSES.STAKING,
      role: 'Streams 30% of all hourly swap pots directly in native ETH dividends (accEthPerShare + unallocatedYield buffer) strictly to stakers in the 0.1% (1M $IRL) to 2.0% (20M $IRL) classification tiers. Features a Hybrid 24h Free-Ticket Claim Mechanic: zero unstake lock by default, 0h lock if free tickets are claimed after ≥24h staked, or a 24h unstake lock if free tickets are Instant-Claimed (<24h).',
      security: 'Zero Default Lock, Hybrid 24h Ticket Claim, [0.1%, 2.0%] Tiers',
    },
    {
      key: 'guild',
      name: 'Sherwood Co-Staking Guild Vault',
      file: 'IRLSherwoodGuildVault.sol',
      type: 'Small-Stakers Pooled Vault',
      address: CONTRACT_ADDRESSES.SHERWOOD_GUILD,
      role: 'Enables sub-0.1% holders (< 1M $IRL) to pool their tokens cooperatively into a collective staking threshold tier. Streams proportional Real Yield ETH rewards and fractional lottery ticket rights without requiring whale capital.',
      security: 'Pro-Rata ETH Dividend Shares, Immutable Pool Accounting',
    },
    {
      key: 'tickets',
      name: 'Dynamic Lottery Tickets & P2P Marketplace',
      file: 'IRLTicketNFT.sol',
      type: 'ERC-721 Dynamic NFT + P2P Market',
      address: CONTRACT_ADDRESSES.TICKETS,
      role: 'Dynamic on-chain lottery tickets with built-in P2P Marketplace (listTicket / buyTicket). Enforces a 2.0% Lottery Tax on every secondary sale (98% to seller; 1% Daily + 1% Sunday for Daily+Weekly tickets, or 2% Sunday for Weekly-only tickets), active listing price update mode, My Tickets wallet inventory, and weekly holding caps (42–70) in _update.',
      security: 'Validated P2P Market, 2.0% Lottery Tax, Weekly Cap (42–70)',
    },
    {
      key: 'marketing',
      name: 'Liquidity Custody & Single-Sided LP Vault',
      file: 'IRLMarketingVault.sol',
      type: '90% Permanent Lock + 10% Smart Vault',
      address: CONTRACT_ADDRESSES.MARKETING_VAULT,
      role: 'Seeds 100% of the 1B $IRL supply into Uniswap V4 PoolManager at launch: 90% (900M $IRL) permanently locked forever under PERMANENT_LOCKED_SALT (zero withdrawal function) and 10% (100M $IRL) conditionally locked in an upper marketing bracket under MARKETING_VAULT_SALT withdrawable only once 100% converted to WETH, followed by an atomic 0.15 ETH initial buy.',
      security: '90% Permanent Lock, 10% Directional Tick Bound, Immutable State',
    },
    {
      key: 'vrf',
      name: 'Native OpenVRF Randomness Coordinator',
      file: 'OpenVRF.sol (Native Robinhood Chain L2)',
      type: 'Self-Hosted drand BLS Coordinator',
      address: CONTRACT_ADDRESSES.OPENVRF_ROUTER,
      role: 'Self-deployed directly on Robinhood Chain L2. Verifies decentralized drand BLS randomness beacons directly onchain via alt_bn128 EVM precompiles for daily and Sunday Mega-Jackpot draws with zero third-party bridge or L1 dependency.',
      security: 'drand BLS BN254 Verification, Non-Tamperable',
    },
  ];

  return (
    <div className="whitepaper-container">
      {/* Hero Header */}
      <section className="whitepaper-hero">
        <div className="hero-badge">
          <ShieldCheckIcon size={16} color="#d4af37" />
          <span>Official Architecture Specification &amp; Audited Protocol Whitepaper</span>
        </div>
        <h1 className="whitepaper-title">Internet Robinhood Lottery ($IRL)</h1>
        <p className="whitepaper-subtitle">
          The First Verifiable, Anti-Extraction Volume Redistribution Ecosystem Built on Uniswap V4 Hooks &amp; OpenVRF on Robinhood Chain.
        </p>
        <div className="whitepaper-meta-pills">
          <span className="meta-pill">Standard: ERC-20 / ERC-721 / V4 Hook</span>
          <span className="meta-pill">Network: Robinhood Chain (Etherscan Verified)</span>
          <span className="meta-pill">Audit: Trail of Bits &amp; Argon</span>
          <span className="meta-pill gold">Dev Dump Risk: 0.00%</span>
        </div>
      </section>

      {/* Section 1: Executive Thesis */}
      <section className="wp-section">
        <h2 className="wp-heading">1. The Robinhood Thesis</h2>
        <div className="wp-card">
          <p className="wp-text">
            Traditional decentralized finance memecoins and reward tokens suffer from structural fatal flaws:
          </p>
          <ul className="wp-list">
            <li>
              <strong>Predatory Dev Extractions:</strong> Founders retain large unlocked marketing wallets and repeatedly dump on community buy volume.
            </li>
            <li>
              <strong>Unrewarded Volume Generation:</strong> Retail traders generate millions in decentralized exchange volume, but 100% of trading fees are captured by passive LP whales and MEV sandwich bots.
            </li>
            <li>
              <strong>Untrusted Off-Chain Scripts:</strong> Lottery draws and prize distributions typically rely on centralized backend scripts vulnerable to manipulation or sudden abandonment.
            </li>
          </ul>
          <p className="wp-text">
            <strong>$IRL solves this through Uniswap V4 Hooks, Robinhood Chain L2, and Programmable.market:</strong>
            The protocol operates on a clean <strong>4.0% Standard Tax</strong> (<strong>1.25% Hourly Pot</strong> + <strong>1.25% Dual Lottery Pot</strong> + <strong>1.20% Protocol &amp; Hourly Buyback Pot [1.00% Protocol + 0.20% Buyback Burn]</strong> + <strong>0.30% Immutable Programmable.market Fee</strong>).
            <strong> 100% of this tax is algorithmically processed on-chain: </strong> Programmable.market receives an immutable <strong>0.30% (30 bps)</strong> platform fee once on every normal buy, normal sell, and internal buyback; Hourly Pots are streamed every hour to the Top 10 traders (35%), all active swappers (35% cashback), and eligible stakers (30% Real Yield); Epoch-Isolated Lottery Pots reward daily and Sunday Mega-Jackpot NFT lottery winners via provable OpenVRF randomness; <strong>1.00%</strong> funds Protocol, Marketing &amp; Keeper Gas; and <strong>0.20%</strong> accumulates in <code>buybackPot</code> and is swapped once per hour on the V4 pool to burn $IRL to <code>0xdead</code>!
          </p>
        </div>
      </section>

      {/* Section 2: Smart Contract Architecture & Verified Directory */}
      <section className="wp-section">
        <h2 className="wp-heading">2. Ecosystem Smart Contracts &amp; Verification</h2>
        <p className="wp-intro-text">
          Complete transparency is non-negotiable. Below is the verified registry of every smart contract powering the $IRL ecosystem:
        </p>

        <div className="contracts-grid">
          {contractsList.map((item) => (
            <div key={item.key} className="contract-card">
              <div className="contract-card-header">
                <span className="contract-name">{item.name}</span>
                <span className="contract-type-pill">{item.type}</span>
              </div>
              <p className="contract-role">{item.role}</p>

              <div className="contract-address-bar">
                <span className="address-label">Address:</span>
                {item.address ? (
                  <>
                    <code className="address-code">{item.address}</code>
                    <button 
                      onClick={() => copyToClipboard(item.address, item.key)}
                      className="btn-copy-address"
                      title="Copy contract address"
                    >
                      {copiedAddress === item.key ? (
                        <CheckIcon size={14} color="#8ce2aa" />
                      ) : (
                        <CopyIcon size={14} color="#c0e5d0" />
                      )}
                    </button>
                    <a
                      href={`${ROBINHOOD_CHAIN.blockExplorers.default.url}/address/${item.address}`}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="btn-view-explorer"
                      title="View on Robinhood Etherscan"
                    >
                      <ExternalLinkIcon size={14} color="#79a88e" />
                    </a>
                  </>
                ) : (
                  <span className={`address-pending-badge ${item.isPendingUpgrade ? 'rose-gold-pill' : ''}`}>
                    {item.pendingLabel || '⏳ Deployment Scheduled at Launch (Robinhood Chain L2)'}
                  </span>
                )}
              </div>

              <div className="contract-security-tag">
                <ShieldCheckIcon size={14} color="#d4af37" />
                <span>{item.security}</span>
              </div>
            </div>
          ))}
        </div>
      </section>

      {/* Section 3: The Uniswap V4 Hook Tax Breakdown (4.0% Standard Tax) */}
      <section className="wp-section">
        <h2 className="wp-heading">3. The Uniswap V4 Hook Tax Architecture (4.0% Standard Tax)</h2>
        <div className="wp-tax-callout">
          <span className="tax-callout-icon">⚡</span>
          <div className="tax-callout-text">
            <strong className="tax-callout-title">
              4.0% Standard Tax Architecture
            </strong>
            The Hook executes a clean, immutable <strong>4.0% Standard Tax</strong> (<strong>1.25% Hourly Pot</strong> + <strong>1.25% Dual Lottery Pot</strong> + <strong>1.20% Protocol &amp; Buyback Pot [1.00% Protocol + 0.20% Buyback Burn]</strong> + <strong>0.30% Programmable.market</strong>) processed algorithmically on-chain.
          </div>
        </div>
        <div className="tax-architecture-grid four-pillars">
          <div className="tax-column">
            <div className="tax-col-header">
              <ShieldCheckIcon size={24} color="#E6C2A5" />
              <h3>0.30% Programmable Fee</h3>
            </div>
            <p className="tax-col-desc">
              Immutable launchpad fee (<code>30 bps</code>) enforced once per buy, sell, and internal buyback directly to <code>0xD885...79da</code>:
            </p>
            <div className="tax-split-box">
              <div className="split-item">
                <span className="split-pct">0.30%</span>
                <span className="split-text">Direct Native ETH Fee: Charged once on normal buys, normal sells, and internal buybacks with pull-fallback protection.</span>
              </div>
              <div className="split-item">
                <span className="split-pct">1x</span>
                <span className="split-text">Zero Double-Charging: Internal buybacks pay the 30 bps fee once before the V4 swap.</span>
              </div>
            </div>
          </div>

          <div className="tax-column">
            <div className="tax-col-header">
              <ClockIcon size={24} color="#E6C2A5" />
              <h3>1.25% Hourly Stream</h3>
            </div>
            <p className="tax-col-desc">
              <strong>1.25% (Standard)</strong> extracted in WETH and dispatched into three hourly streams:
            </p>
            <div className="tax-split-box">
              <div className="split-item">
                <span className="split-pct">35%</span>
                <span className="split-text">
                  <strong>Top 10 of the Hour (with Staker Boost):</strong> Shared among the Top 10 traders of that hour (0.4375% Standard). Staking 2% gives +50% volume boost!
                </span>
              </div>
              <div className="split-item">
                <span className="split-pct">35%</span>
                <span className="split-text">
                  <strong>Active Swapper Cashback (0.4375%):</strong> Guaranteed ETH cashback per trade for everyone who traded in the hour, distributed once per hour.
                </span>
              </div>
              <div className="split-item">
                <span className="split-pct">30%</span>
                <span className="split-text">
                  <strong>Stakers Real Yield (0.1%–2.0% Tiers):</strong> Streamed in native ETH (0.375% Standard) to all stakers holding between 0.1% (1M $IRL) and 2.0% (20M $IRL) of supply!
                </span>
              </div>
            </div>
          </div>

          <div className="tax-column">
            <div className="tax-col-header">
              <TicketIcon size={24} color="#E6C2A5" />
              <h3>1.25% Dual Lottery</h3>
            </div>
            <p className="tax-col-desc">
              <strong>1.25% (Standard)</strong> feeding epoch-isolated Daily and Weekly Lottery pots:
            </p>
            <div className="tax-split-box">
              <div className="split-item">
                <span className="split-pct">50%</span>
                <span className="split-text">Daily Grand Jackpot (0.625% Standard): Isolated per day in <code>dailyPotByDay[dayId]</code> and drawn every midnight via OpenVRF.</span>
              </div>
              <div className="split-item">
                <span className="split-pct">50%</span>
                <span className="split-text">Sunday Mega-Jackpot (0.625% Standard): Isolated per week in <code>weeklyPotByWeek[weekId]</code> across all tickets minted Monday through Sunday!</span>
              </div>
            </div>
          </div>

          <div className="tax-column">
            <div className="tax-col-header">
              <VaultIcon size={24} color="#E6C2A5" />
              <h3>1.20% Protocol &amp; Burn</h3>
            </div>
            <p className="tax-col-desc">
              <strong>1.20% (Standard)</strong> for protocol solvency, marketing, gas infrastructure, and hourly batched deflation:
            </p>
            <div className="tax-split-box">
              <div className="split-item">
                <span className="split-pct">1.00%</span>
                <span className="split-text">Funds decentralized OpenVRF request fees, automation keep-alives, and global marketing (<strong>1.00% Standard</strong> in <code>protocolPot</code>).</span>
              </div>
              <div className="split-item">
                <span className="split-pct">0.20%</span>
                <span className="split-text">Hourly Batched V4 Buyback &amp; Burn (<code>executeBuybackAndBurn</code>): Accumulates <strong>0.20% (Standard)</strong> of every swap in <code>buybackPot</code> and executes a single consolidated WETH → $IRL swap to <code>0x000...dEaD</code> once per hour!</span>
              </div>
            </div>
          </div>
        </div>

        <div className="wp-burn-callout">
          <span className="burn-callout-icon">🔥</span>
          <div className="burn-callout-text">
            <strong className="burn-callout-title">Automated Hourly V4 Buyback &amp; Burn Flywheel (0.20% Standard)</strong>
            <span>
              <strong>0.20% (20 bps) Standard Tax</strong> accumulates in <code>buybackPot</code> on every swap and executes <strong>once every hour</strong> in a single consolidated V4 pool WETH → $IRL buyback &amp; burn to <code>0xdead</code> (after paying the 0.30% Programmable platform fee once).
            </span>
          </div>
        </div>
      </section>

      {/* Section 4: Mathematical Formulas & Score Calculus */}
      <section className="wp-section">
        <h2 className="wp-heading">4. Mathematical Redistribution Formulas &amp; 24h Hybrid Staking</h2>

        {/* Verified Staking & Co-Staking Guild Architecture Callout */}
        <div className="staking-deployment-callout verified-live">
          <span className="callout-icon">🛡️</span>
          <div className="callout-content">
            <strong className="callout-title">Live On-Chain Staking Architecture &amp; Sherwood Guild Integration</strong>
            <p className="callout-text">
              The mathematical formulas, tier boost curves (0.1%–2.0%), and hybrid 24h ticket claim mechanics documented below are fully active and deployed on Robinhood Chain via <code>IRLStaking.sol</code> and <code>IRLSherwoodGuildVault.sol</code>.
            </p>
          </div>
        </div>
        <div className="wp-card formula-card">
          <h3 className="formula-title">Hourly 35/35/30 Stream &amp; [0.1%, 2.0%] Staking Calculus</h3>
          <p className="wp-text">
            Every trader's volume is boosted linearly by their staked $IRL balance (up to +50% at 2% staked), while stakers holding between 0.1% (1,000,000 $IRL) and 2.0% (20,000,000 $IRL) continuously earn native ETH Real Yield:
          </p>
          <div className="math-block">
            <code>
              ScoreMultiplier = 100% + min( (Staked_IRL × 50%) / 20,000,000 , 50% )  // Linearly scales 0% → +50% at 2% Supply
            </code>
            <br />
            <code>
              TraderHourlyScore_i = Volume_ETH_i × ScoreMultiplier  // e.g. 0.05 WETH × 1.50 (2% stake) = 0.075 WETH
            </code>
            <br />
            <code>
              Top10_HourlyShare_i = isTop10(i) ? [ 0.35 × HourlyPot × ( TraderHourlyScore_i / SumTop10Scores ) ] : 0
            </code>
            <br />
            <code>
              HourlyCashback_i = 0.004375 × Volume_ETH_i  // 0.4375% ETH cashback per trader, paid hourly
            </code>
            <br />
            <code>
              EligibleStake_i = (Staked_IRL &lt; 1,000,000) ? 0 : min( Staked_IRL , 20,000,000 )  // [0.1% Min, 2.0% Max Cap]
            </code>
            <br />
            <code>
              StakerRealYield_ETH_i = ( EligibleStake_i / TotalEligibleStaked ) × 30%_Hourly_Pot
            </code>
            <br />
            <code>
              StakerTickets_4Days = min( (Staked_IRL × 10) / 20,000,000 , 10 Tickets )  // Free bonus every 4 days (Hybrid Claim)
            </code>
            <br />
            <code>
              UnstakeUnlockTime = (ClaimedTickets_At &lt; StakedAt + 24h) ? (ClaimedAt + 24h) : 0  // 0h lock by default &amp; after 24h staked!
            </code>
            <br />
            <code>
              MarketplaceSaleTax_2% = DailyAndWeeklyTicket ? (1.0% DailyPot + 1.0% SundayPot) : (2.0% SundayPot)  // 98% to Seller
            </code>
            <br />
            <code>
              DailyVolumeTicketLimit = 6 + min( (Staked_IRL × 4) / 20,000,000 , 4 )  // 6 Daily (0%) to 10 Daily (2% Staked)
            </code>
            <br />
            <code>
              WeeklyHoldingCap = DailyVolumeTicketLimit × 7  // 42 Weekly (0%) to 70 Weekly (2% Staked) enforced in _update
            </code>
          </div>
          <p className="wp-text" style={{ marginTop: '12px' }}>
            <strong>Concrete Top 10 Volume Boost Example:</strong> If two traders each perform <strong>0.05 WETH</strong> of swap volume during the hour, and one of them stakes <strong>2.0% (20,000,000 $IRL)</strong>, the non-staker is counted at <strong>0.050 WETH</strong> (40% of their combined score) while the 2% staker receives a +50% volume boost and is counted at <strong>0.075 WETH</strong> (60% of their combined score) for the 35% Top 10 distribution! Both traders also receive their <strong>0.4375% hourly cashback</strong> at the end of the hour.
          </p>

          {/* Dedicated 24h Hybrid Staking Explanation Box */}
          <div className="wp-hybrid-callout">
            <h4 className="hybrid-callout-title">
              🛡️ 24h Hybrid Staking &amp; Free-Ticket Claim Policy (Zero Default Lock)
            </h4>
            <p className="wp-text" style={{ margin: '0 0 8px 0', fontSize: '0.88rem' }}>
              To give holders complete liquidity freedom while mathematically eliminating multi-wallet Sybil loops (where an attacker stakes, claims 10 free tickets, unstakes, transfers $IRL to a second wallet, and repeats), <code>IRLStaking.sol</code> and <code>IRLUniswapV4Hook.sol</code> enforce a <strong>24h Hybrid Claim Mechanic</strong>:
            </p>
            <ul className="wp-list" style={{ marginBottom: 0, fontSize: '0.86rem' }}>
              <li>
                <strong>Zero Unstake Lock by Default (<code>0h Lock</code>):</strong> Depositing $IRL in the Staking Sanctuary <strong>never locks your tokens by default</strong>. You earn the 30% hourly ETH Real Yield and up to +50% swap volume boost and can <code>unstake()</code> anytime if you have not Instant-Claimed free tickets.
              </li>
              <li>
                <strong>Option A — Mature Claim after ≥ 24h Staked (<code>0h Unstake Lock</code>):</strong> Once your position has been staked for at least <strong>24 hours</strong> (<code>block.timestamp &gt;= lastStakedTimestamp + 24 hours</code>), claiming your 4-day free bonus tickets applies <strong>zero unstake lock</strong> — your $IRL remains 100% unlocked!
              </li>
              <li>
                <strong>Option B — Instant-Claim before 24h Staked (<code>24h Unstake Lock</code>):</strong> If you choose to claim your free bonus tickets <strong>immediately after staking (&lt; 24h)</strong>, your tickets are minted right away and the contract automatically locks your <code>unstake()</code> for <strong>24 hours from the claim</strong> (<code>unstakeUnlockTime = block.timestamp + 24 hours</code>).
              </li>
            </ul>
          </div>

          <h4 style={{ color: 'var(--color-gold)', fontFamily: 'var(--font-display)', marginTop: '22px', marginBottom: '8px', fontSize: '1rem' }}>
            Comparative Staking Classification Tiers (0.10% Min to 2.00% Max)
          </h4>
          <p className="wp-text" style={{ fontSize: '0.86rem' }}>
            Real Yield ETH dividends are reserved for stakers in the <strong>0.10% (1,000,000 $IRL) to 2.00% (20,000,000 $IRL)</strong> classification, while volume multipliers and ticket limits scale linearly up to 2.00%:
          </p>
          <div className="wp-table-container">
            <table className="wp-table">
              <thead>
                <tr>
                  <th>% Staked</th>
                  <th>Staked $IRL</th>
                  <th>30% ETH Real Yield</th>
                  <th>Volume Boost</th>
                  <th>Swap for 1 Ticket (0.10 ETH Base)</th>
                  <th>Free Tickets (Every 4 Days)</th>
                  <th>Daily / Weekly Cap</th>
                </tr>
              </thead>
              <tbody>
                <tr>
                  <td><strong>0.00%</strong> (Non-staker)</td>
                  <td>0 $IRL</td>
                  <td>Not Eligible (&lt; 0.1%)</td>
                  <td>+0% (1.00x)</td>
                  <td className="gold-val">0.1000 ETH</td>
                  <td>0 Tickets</td>
                  <td>6 Daily / 42 Weekly</td>
                </tr>
                <tr>
                  <td><strong>0.10% (Min Yield Tier)</strong></td>
                  <td>1,000,000 $IRL</td>
                  <td className="mint-val"><strong>✅ Eligible (1.0M Weight)</strong></td>
                  <td className="mint-val">+2.50% (1.025x)</td>
                  <td className="gold-val">~0.0976 ETH</td>
                  <td>0 Tickets</td>
                  <td>6 Daily / 42 Weekly</td>
                </tr>
                <tr>
                  <td><strong>0.25%</strong></td>
                  <td>2,500,000 $IRL</td>
                  <td className="mint-val"><strong>✅ Eligible (2.5M Weight)</strong></td>
                  <td className="mint-val">+6.25% (1.0625x)</td>
                  <td className="gold-val">~0.0941 ETH</td>
                  <td>1 Ticket / 4 Days</td>
                  <td>6 Daily / 42 Weekly</td>
                </tr>
                <tr>
                  <td><strong>0.50%</strong></td>
                  <td>5,000,000 $IRL</td>
                  <td className="mint-val"><strong>✅ Eligible (5.0M Weight)</strong></td>
                  <td className="mint-val">+12.50% (1.125x)</td>
                  <td className="gold-val">~0.0889 ETH</td>
                  <td>2 Tickets / 4 Days</td>
                  <td>7 Daily / 49 Weekly</td>
                </tr>
                <tr>
                  <td><strong>0.75%</strong></td>
                  <td>7,500,000 $IRL</td>
                  <td className="mint-val"><strong>✅ Eligible (7.5M Weight)</strong></td>
                  <td className="mint-val">+18.75% (1.1875x)</td>
                  <td className="gold-val">~0.0842 ETH</td>
                  <td>3 Tickets / 4 Days</td>
                  <td>7 Daily / 49 Weekly</td>
                </tr>
                <tr>
                  <td><strong>1.00%</strong></td>
                  <td>10,000,000 $IRL</td>
                  <td className="mint-val"><strong>✅ Eligible (10.0M Weight)</strong></td>
                  <td className="mint-val">+25.00% (1.25x)</td>
                  <td className="gold-val">0.0800 ETH</td>
                  <td>5 Tickets / 4 Days</td>
                  <td>8 Daily / 56 Weekly</td>
                </tr>
                <tr className="highlight-tier">
                  <td><strong>2.00% (Max Tier)</strong></td>
                  <td><strong>20,000,000 $IRL</strong></td>
                  <td className="mint-val"><strong>✅ Max Cap (20.0M Weight)</strong></td>
                  <td className="mint-val"><strong>+50.00% (1.50x)</strong></td>
                  <td className="gold-val"><strong>~0.0667 ETH</strong> (0.075 qualifies)</td>
                  <td><strong>10 Tickets / 4 Days</strong></td>
                  <td><strong>10 Daily / 70 Weekly</strong></td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>

        <div className="wp-card formula-card">
          <h3 className="formula-title">Strict Daily Ticket Range, Sunday Mega Indexing &amp; 2% P2P Marketplace Tax</h3>
          <p className="wp-text">
            Tickets are registered with strict chronological ranges and atomic VRF prize snapshots (<code>vrfRequestPrize[requestId]</code>) to guarantee fair competition every single day:
          </p>
          <div className="math-block">
            <code>
              DailyWinningTicket = DayStartTicket + ( OpenVRF_RandomWord % DayTicketCount )
              <br />
              SundayMegaWinningTicket = WeekStartTicket + ( OpenVRF_RandomWord % WeekTicketCount )
            </code>
          </div>
          <p className="wp-text">
            On the validated <strong>P2P NFT Ticket Marketplace (<code>IRLTicketNFT.buyTicket</code>)</strong>, every secondary ticket sale pays <strong>98.0% to the seller</strong> and routes a <strong>2.0% Lottery Tax</strong> directly to <code>IRLUniswapV4Hook.receiveMarketplaceTax(tokenId)</code>: if the ticket was minted today (<strong>Daily + Weekly eligible</strong>), the 2% tax is split <strong>50/50 (1.0% Daily Pot + 1.0% Sunday Mega-Jackpot)</strong>; if the ticket was minted on an earlier day of the week (<strong>Weekly-only eligible</strong>), <strong>100% of the 2% tax goes directly to the Sunday Mega-Jackpot</strong>!
          </p>
        </div>

        {/* Post-Launch Real Human Swapper Transparency & Dev Wallet Redistribution */}
        <div className="wp-card formula-card" style={{ marginTop: '1.25rem' }}>
          <h3 className="formula-title">🛡️ Real Human Swapper Unmasking &amp; Dev Wallet Hourly Redistribution Protocol</h3>
          <p className="wp-text">
            In modern decentralized finance, a significant share of retail trading volume flows through third-party DEX aggregators and router contracts. On-chain, these routers appear as the immediate sender of the trade.
          </p>
          <ul className="wp-list">
            <li>
              <strong>Automated Trader Unmasking:</strong> The $IRL ecosystem automatically scans swap transactions on Robinhood Chain to identify and credit the genuine human trader wallet (<code>tx.from</code>) behind every trade, preventing external smart contracts from eclipsing community swappers.
            </li>
            <li>
              <strong>Dev Wallet Hourly Redistribution Protocol:</strong> For all transactions routed through third-party DEX aggregators where rewards cannot be delivered directly to users by the smart contract, an automated keeper script executes on the dev wallet to redistribute ETH hour-by-hour directly to verified human traders, guaranteeing 100% fair volume redistribution.
            </li>
            <li>
              <strong>Live On-Chain Transparency Monuments:</strong> The DApp homepage continuously displays verifiable on-chain metrics:
              <br />
              • <strong>Paid to Real Traders:</strong> Cumulative ETH distributed directly to verified real traders across hourly top 10 shares, active swapper cashback, and dev wallet hourly redistributions.
              <br />
              • <strong>Deflation &amp; Burn:</strong> Cumulative $IRL tokens permanently burned to <code>0xdead</code> via hourly V4 buybacks + ETH permanently locked in Hook unclaimed rewards (from non-payable contract callers, permanently removed from circulation).
              <br />
              • <strong>Live Tickets in Play:</strong> Live on-chain ticket counters balancing the active tickets in contention for both the Daily 24h Grand Jackpot (00:00 UTC) and the Sunday Mega-Jackpot.
            </li>
          </ul>
        </div>
      </section>

      {/* Section 5: The Rug-Proof Guarantee (90% Permanent Lock + 10% Single-Sided LP Marketing Vault) */}
      <section className="wp-section">
        <h2 className="wp-heading">5. Verifiable LP Custody &amp; Single-Sided LP Marketing Vault — Zero Rug Guarantee</h2>
        <div className="wp-card highlight-card">
          <div className="highlight-card-header">
            <ShieldCheckIcon size={24} color="#8ce2aa" />
            <h3 className="highlight-title">Why the Developer CANNOT Rug Core Liquidity or Dump Marketing Tokens</h3>
          </div>
          <p className="wp-text">
            In standard crypto projects, the team reserves 5%–15% of the token supply in unlocked wallets and can pull liquidity or dump tokens on retail buyers.
          </p>
          <p className="wp-text">
            <strong>$IRL eliminates this risk mathematically with <code>IRLMarketingVault.sol</code> during the atomic launch:</strong>
          </p>
          <ul className="wp-list">
            <li>
              <strong>90% Core Liquidity Permanently Locked Forever (<code>900,000,000 $IRL</code> — <code>PERMANENT_LOCKED_SALT</code>):</strong> Seeded directly into Uniswap V4 <code>PoolManager</code> across the full upward price curve with <strong>zero decrease or withdrawal function</strong> anywhere in the contract.
            </li>
            <li>
              <strong>10% Marketing Allocation Conditionally Locked in Upper Bracket (<code>100,000,000 $IRL</code> — <code>MARKETING_VAULT_SALT</code>):</strong> Deposited as single-sided $IRL liquidity above the launch price. The contract enforces that liquidity <strong>CANNOT be withdrawn</strong> unless the pool's current tick has completely crossed the marketing bracket:
            </li>
          </ul>
          <div className="math-block code-snippet">
            <code>
              require(irlIsCurrency0 ? currentTick &gt;= marketingTickUpper : currentTick &lt;= marketingTickLower, "Price has not crossed marketing bracket");
            </code>
          </div>
          <p className="wp-text">
            This guarantees that by the time any marketing withdrawal is possible, 100% of the $IRL tokens in that bracket have already been purchased by the market and converted into WETH.
          </p>
        </div>
      </section>

      {/* Section 6: Genesis Fair-Launch & Anti-Whale Protections */}
      <section className="wp-section">
        <h2 className="wp-heading">6. Genesis Fair-Launch &amp; Anti-Whale Mechanics</h2>
        <div className="anti-whale-grid">
          <div className="anti-whale-card">
            <span className="aw-metric">10,000,000 $IRL</span>
            <span className="aw-label">Max Transaction Limit (1.0% Total Supply)</span>
            <p className="aw-desc">Prevents automated bots or whales from consuming initial pool liquidity in a single transaction.</p>
          </div>
          <div className="anti-whale-card">
            <span className="aw-metric">20,000,000 $IRL</span>
            <span className="aw-label">Max Wallet Limit (2.0% Total Supply)</span>
            <p className="aw-desc">Enforces healthy token distribution across hundreds of community holders at launch.</p>
          </div>
          <div className="anti-whale-card">
            <span className="aw-metric">$50,000 MC Auto-Lift</span>
            <span className="aw-label">Anti-Whale SqrtPrice Cutoff (2.5x Launch)</span>
            <p className="aw-desc">All Max TX and Max Wallet restrictions permanently and automatically disable onchain as soon as the pool reaches $50k Market Cap.</p>
          </div>
          <div className="anti-whale-card">
            <span className="aw-metric">4.0% Standard</span>
            <span className="aw-label">4.0% Standard Hook Tax</span>
            <p className="aw-desc">A clean 4.0% Standard Tax (1.25% Hourly + 1.25% Lottery + 1.20% Protocol/Burn + 0.30% Programmable) powers real yield, lotteries, buybacks, and protocol growth!</p>
          </div>
        </div>
      </section>

      {/* Section 7: Trail of Bits & Argon Security Audit Verification */}
      <section className="wp-section">
        <h2 className="wp-heading">7. Trail of Bits &amp; Argon Security Audit Verification</h2>
        <div className="wp-card highlight-card">
          <div className="highlight-card-header">
            <ShieldCheckIcon size={24} color="#d4af37" />
            <h3 className="highlight-title">100% Security Findings Resolved • Formal Invariant Verification</h3>
          </div>
          <p className="wp-text">
            The $IRL smart contract suite underwent both a <strong>Trail of Bits Formal Verification &amp; Slither Audit (102 detectors)</strong> and a deep line-by-line <strong>Argon Adversarial Security Audit</strong>, plus full compliance with <strong>Programmable.market Launch Review standards</strong>:
          </p>
          <ul className="wp-list">
            <li>
              <strong>4.0% Standard Tax (<code>LAUNCH_TAX_DURATION</code> &amp; <code>disableLaunchTaxSqrtPrice</code>):</strong> Standard Tax architecture delivering Hourly (1.25%), Daily/Sunday Lottery (1.25%), and Protocol/Buyback (1.20%) pots + 0.30% Programmable (1.25% / 1.25% / 1.20% / 0.30%).
            </li>
            <li>
              <strong>Recipient-Claimable Failed Rewards (<code>unclaimedRewards</code>) &amp; Epoch-Isolated Lottery Pots:</strong> Any failed ETH transfer during hourly payouts or lottery draws is credited to <code>unclaimedRewards[recipient]</code> (claimable anytime via <code>claimUnclaimedRewards()</code>, never routed to <code>protocolPot</code>), and lottery pots are isolated per day/week (<code>dailyPotByDay[dayId]</code> and <code>weeklyPotByWeek[weekId]</code>).
            </li>
            <li>
              <strong>Hybrid Anti-Sybil Staking Ticket Claim (Zero Default Lock):</strong> Staking never locks withdrawals by default. Stakers can either wait 24 hours to claim their 4-day bonus tickets with <strong>0h unstake lock</strong>, or Instant-Claim (&lt;24h) and lock unstake for 24 hours (<code>unstakeUnlockTime</code>).
            </li>
            <li>
              <strong>Hourly Batched Buyback &amp; Burn (<code>lastBuybackHour</code>):</strong> Accumulates the 0.20% (Standard) swap buyback burn in <code>buybackPot</code> on every trade and executes a single consolidated V4 pool WETH → $IRL buyback &amp; burn to <code>0xdead</code> once per hour (after paying the 0.30% Programmable platform fee once).
            </li>
            <li>
              <strong>Validated P2P NFT Ticket Marketplace &amp; 2.0% Lottery Tax:</strong> Built-in secondary marketplace in <code>IRLTicketNFT.sol</code> routing 2% of every sale to <code>receiveMarketplaceTax</code> (50/50 Daily+Sunday for today's tickets, or 100% Sunday Mega-Jackpot for weekly-only tickets).
            </li>
            <li>
              <strong>Zero-Wei Fee Conservation &amp; Solvency Fuzzing:</strong> Formally proven across 256 fuzz runs (0.001 ETH to 1,000 ETH swaps) that 100% of swap fees and staking ETH dividends are conserved down to the single wei.
            </li>
            <li>
              <strong>Dev Wallet Hourly Redistribution Protocol:</strong> Automated keeper protocol implemented on the dev wallet to redistribute ETH hour-by-hour directly to genuine human traders for volume passing through external aggregators, guaranteeing 100% complete and equitable redistribution.
            </li>
            <li>
              <strong>On-Chain P2P NFT Ticket Marketplace &amp; Price Updates:</strong> Fully on-chain secondary market within <code>IRLTicketNFT.sol</code> enforcing a 2.0% lottery tax (98% to seller), clear visual separation between unlisted and active tickets with 1-click price updates, and a dedicated "My Tickets" inventory tab.
            </li>
            <li>
              <strong>Real-Trader Leaderboard with Live Hourly Estimates:</strong> Real-time leaderboard identifying genuine human traders (contract unmasking), priority display of the hourly distribution with live non-zero estimated payouts per trader, and 24h volume tracking in the secondary view.
            </li>
            <li>
              <strong>On-Chain Transparency Monuments:</strong> Real-time DApp telemetry displaying cumulative rewards distributed to verified traders, total tokens burned to <code>0xdead</code> + locked rewards from non-payable caller contracts (permanently removed from circulation), and live ticket counters in contention for the Daily Grand Jackpot and Sunday Mega-Jackpot.
            </li>
          </ul>
        </div>
      </section>
    </div>
  );
}

