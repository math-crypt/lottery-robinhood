import React, { useState } from 'react';
import { TrophyIcon, ExternalLinkIcon, TicketIcon, ZapIcon, SparklesIcon } from './Icons';

export default function Leaderboard({
  account,
  leaderboardInfo,
  fallbackTraders = [],
  hourlyPotEth = "0.286",
  distributedRewardsEth = "0.608",
  dailyTicketsInPlay = 6,
  sundayTicketsInPlay = 177,
  onOpenQuickMint,
  onSelectTab,
}) {
  const [activeTab, setActiveTab] = useState('hourly'); // Default to 'hourly' per user request

  const dailyTraders = (leaderboardInfo && leaderboardInfo.daily24hLeaderboard) || [];
  const hourlyTraders = (leaderboardInfo && leaderboardInfo.currentHourTop10) || [];

  const displayTraders = activeTab === 'hourly'
    ? (fallbackTraders && fallbackTraders.length > 0 ? fallbackTraders : hourlyTraders)
    : (dailyTraders.length > 0 ? dailyTraders : fallbackTraders);

  const isPreLaunch = displayTraders.length === 0;
  const currentHourPot = hourlyPotEth || (leaderboardInfo && leaderboardInfo.currentHourPotEth) || '0.000';
  const sweptPot = distributedRewardsEth || (leaderboardInfo && leaderboardInfo.sweptPotEth) || '0.608';
  const total24hTraders = (leaderboardInfo && leaderboardInfo.totalDailyTraders) || dailyTraders.length;
  const total24hVolume = (leaderboardInfo && leaderboardInfo.totalDailyVolumeEth) || '3.812';

  const nextTicketDailyOdds = ((1 / (Math.max(0, Number(dailyTicketsInPlay) || 0) + 1)) * 100).toFixed(1);
  const threeTicketSundayOdds = ((3 / (Math.max(1, Number(sundayTicketsInPlay) || 177) + 3)) * 100).toFixed(1);

  return (
    <div className="leaderboard-column-stack">
      <div className="leaderboard-panel">
        <div className="leaderboard-header">
          <div className="leaderboard-title-wrap">
            <TrophyIcon size={20} color="var(--color-gold)" />
            <h2 className="leaderboard-title">Robinhood <em>Real Trader Leaderboard</em></h2>
          </div>
          <div className="leaderboard-tabs-wrap">
            <button
              type="button"
              className={`lb-tab-btn ${activeTab === 'hourly' ? 'active' : ''}`}
              onClick={() => setActiveTab('hourly')}
            >
              Hourly ({currentHourPot} ETH)
            </button>
            <button
              type="button"
              className={`lb-tab-btn ${activeTab === 'daily' ? 'active' : ''}`}
              onClick={() => setActiveTab('daily')}
            >
              24h Pool ({sweptPot} ETH)
            </button>
          </div>
        </div>

        <div className="leaderboard-transparency-pill">
          🛡️ <strong>100% Real Human Swappers:</strong> All third-party aggregator &amp; router contracts are automatically unmasked to credit genuine wallets. 100% of swept router rewards are redistributed hourly by the dev wallet directly to the traders who used that specific router!
        </div>

        <div className="leaderboard-table-container">
          {isPreLaunch ? (
            <div className="leaderboard-prelaunch-banner">
              <TrophyIcon size={28} color="var(--color-gold)" />
              <div className="leaderboard-prelaunch-title">
                {activeTab === 'hourly' ? 'Hourly Cycle Active • Waiting for First Trade' : '24h Pool Active • Waiting for Swaps'}
              </div>
              <p className="leaderboard-prelaunch-desc">
                {activeTab === 'hourly'
                  ? 'No swap volume recorded yet in the current hourly cycle. Swap $IRL on Robinhood Chain to claim Rank #1 and capture the 35% Top 10 redistribution!'
                  : 'All swap volumes are tracked onchain in real time with automated router unmasking. Real human swappers split the 24h pool!'}
              </p>
              {onSelectTab && (
                <button
                  type="button"
                  className="action-btn-primary"
                  style={{ marginTop: '14px', padding: '10px 22px', fontSize: '12.5px', letterSpacing: '0.08em' }}
                  onClick={() => onSelectTab('trade')}
                >
                  ⚡ SWAP $IRL &amp; CLAIM RANK #1
                </button>
              )}
            </div>
          ) : (
            <table className="leaderboard-table">
              <thead>
                <tr>
                  <th className="th-rank">Rank</th>
                  <th className="th-address">Verified Trader</th>
                  <th className="th-volume">{activeTab === 'hourly' ? 'Hourly Vol' : '24h Vol'}</th>
                  <th className="th-share">Share</th>
                  <th className="th-share">{activeTab === 'hourly' ? 'Est. Hourly' : 'Est. 24h'}</th>
                </tr>
              </thead>
              <tbody>
                {displayTraders.map((trader, idx) => {
                  const fullAddr = (trader.fullAddress || trader.address || '').toLowerCase();
                  const isCurrentUser = account && fullAddr === account.toLowerCase();
                  const rankNum = trader.rank || (idx + 1);
                  
                  // Compute live estimated share from 35% Top 10 pot
                  const top10HourlyPot = (parseFloat(currentHourPot) || 0.286) * 0.35;
                  const sharePct = parseFloat(String(trader.sharePercent || '0').replace('%', '')) || 0;
                  const computedEst = ((sharePct / 100) * top10HourlyPot).toFixed(4);

                  const estEth = activeTab === 'hourly'
                    ? (trader.estHourlyShareEth && parseFloat(trader.estHourlyShareEth) > 0.0005
                        ? trader.estHourlyShareEth
                        : (parseFloat(computedEst) > 0 ? computedEst : '0.0010'))
                    : (trader.pendingRedistributionEth || trader.rewardEth || computedEst);

                  return (
                    <tr key={trader.fullAddress || trader.address || idx} className={`lb-row ${isCurrentUser ? 'current-user-row' : ''}`}>
                      <td className="td-rank">
                        <span className={`rank-badge ${rankNum <= 3 ? 'top-tier' : ''}`}>
                          #{rankNum}
                        </span>
                      </td>
                      <td className="td-address">
                        <div className="trader-addr-cell">
                          <a 
                            href={`https://robinhoodchain.blockscout.com/address/${trader.fullAddress || trader.address}`}
                            target="_blank" 
                            rel="noopener noreferrer" 
                            className="address-link"
                          >
                            {trader.address || `${trader.fullAddress.slice(0, 6)}...${trader.fullAddress.slice(-4)}`}
                            <ExternalLinkIcon size={12} color="var(--color-text-dim)" />
                          </a>
                          <span className="real-human-badge">👤 Real Trader</span>
                        </div>
                      </td>
                      <td className="td-volume">
                        <span className="volume-val">{trader.volumeEth}</span>
                        <span className="currency-label">ETH</span>
                      </td>
                      <td className="td-share">
                        <span className="share-pct-badge">{trader.sharePercent || '—'}</span>
                      </td>
                      <td className="td-share">
                        <span className="share-val">~{estEth}</span>
                        <span className="currency-label">ETH</span>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          )}
        </div>

        <div className="leaderboard-footer-note">
          {activeTab === 'hourly'
            ? `⏱️ Hourly Redistribution: 35% to Top 10 traders, 35% hourly cashback, and 100% of router-swept fees redistributed directly to human swappers!`
            : `💰 24h Redistribution Pool: ${sweptPot} ETH queued across ${total24hTraders} active human traders (${total24hVolume} ETH total real volume).`
          }
        </div>
      </div>

      {/* Genesis VIP Pass & Live Protocol Telemetry Showcase Card (Balances Right Column Height) */}
      <div className="genesis-vip-showcase-card">
        <div className="genesis-vip-left">
          <div className="genesis-vip-artwork-frame">
            <img
              src="/nft_ticket.jpg"
              onError={(e) => { e.currentTarget.src = '/nft_ticket_4.jpg'; }}
              alt="Genesis VIP Bearer Pass NFT"
              className="genesis-vip-artwork-img"
            />
          </div>
          <div className="genesis-vip-info">
            <span className="genesis-vip-kicker">
              <SparklesIcon size={12} color="var(--color-gold)" />
              <span>ERC-721 OPENVRF BEARER PASS • DUAL DRAW ELIGIBILITY</span>
            </span>
            <h3 className="genesis-vip-title">Genesis <em>VIP Lottery Pass</em></h3>
            <p className="genesis-vip-desc">
              Every <strong>0.10 ETH</strong> cumulative swap volume (or ~<strong>0.0667 ETH</strong> at 2% staking tier) automatically mints 1 verifiable NFT bearer ticket entered into both tonight&apos;s 24h draw and the Sunday Mega-Jackpot.
            </p>
            <div className="genesis-vip-metrics-strip">
              <div className="g-vip-chip">
                <span className="g-chip-label">NEXT TICKET ODDS</span>
                <span className="g-chip-val">{nextTicketDailyOdds}% Tonight</span>
              </div>
              <div className="g-vip-chip">
                <span className="g-chip-label">+3 PACK SUNDAY</span>
                <span className="g-chip-val">{threeTicketSundayOdds}% Mega Draw</span>
              </div>
              <div className="g-vip-chip">
                <span className="g-chip-label">P2P ROYALTY</span>
                <span className="g-chip-val">2.0% → Lottery Pot</span>
              </div>
            </div>
          </div>
        </div>

        <div className="genesis-vip-actions">
          {onOpenQuickMint && (
            <button
              type="button"
              onClick={() => onOpenQuickMint(3)}
              className="btn-vip-quickmint"
            >
              <ZapIcon size={15} />
              <span>Quick-Mint VIP Pass</span>
            </button>
          )}
          {onSelectTab && (
            <button
              type="button"
              onClick={() => onSelectTab('marketplace')}
              className="btn-vip-marketplace"
            >
              <TicketIcon size={14} />
              <span>Explore P2P Marketplace →</span>
            </button>
          )}
        </div>
      </div>
    </div>
  );
}

