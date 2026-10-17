import React from 'react';
import { TicketIcon, TrophyIcon, WalletIcon, ZapIcon } from './Icons';

export default function PersonalOverview({ 
  account, 
  onConnect, 
  ticketsCount = 0,
  dailyTicketsInPlay = 0,
  sundayTicketsInPlay = 177,
  estimatedRewardEth = "0.000", 
  userVolumeEth = "0.000",
  onClaim,
  isClaiming = false,
  onOpenQuickMint
}) {
  const totalDaily = Math.max(1, Number(dailyTicketsInPlay) || 1);
  const userWinSharePct = ticketsCount > 0 ? Math.min(100, (ticketsCount / totalDaily) * 100).toFixed(1) : '0.0';
  const nextTicketDailyOdds = ((1 / (Number(dailyTicketsInPlay || 0) + 1)) * 100).toFixed(1);

  if (!account) {
    return null;
  }

  return (
    <div className="personal-overview-card">
      <div className="personal-stat-col">
        <div className="stat-label-wrap">
          <TicketIcon size={16} color="var(--color-gold)" />
          <span>Today&apos;s VIP Bearer Passes</span>
        </div>
        <div className="stat-value-wrap" style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
          <div className="mini-ticket-thumb-wrap vip-pass-mini" style={{ width: '32px', height: '32px', minWidth: '32px', maxWidth: '32px', borderRadius: '7px', overflow: 'hidden', border: '1px solid rgba(230, 194, 165, 0.45)', flexShrink: 0, display: 'inline-flex', boxShadow: '0 2px 8px rgba(0,0,0,0.6)' }}>
            <img src="/nft_ticket_4.jpg" alt="VIP NFT Pass" className="mini-ticket-thumb" style={{ width: '100%', height: '100%', maxWidth: '32px', maxHeight: '32px', objectFit: 'cover', display: 'block' }} />
          </div>
          <span className="stat-value">{ticketsCount}</span>
          <span className="stat-unit">Active NFT Tickets ({userWinSharePct}% Win Share)</span>
        </div>
        <span className="stat-subtext">Entered in tonight&apos;s verifiable OpenVRF draw</span>
      </div>

      <div className="stat-divider"></div>

      <div className="personal-stat-col">
        <div className="stat-label-wrap">
          <TrophyIcon size={16} color="var(--color-mint)" />
          <span>Boosted Score This Hour</span>
        </div>
        <div className="stat-value-wrap">
          <span className="stat-value">{userVolumeEth}</span>
          <span className="stat-unit">WETH</span>
        </div>
        <span className="stat-subtext">Includes up to +50% Staker Boost + 0.4375% (1.3125% Launch) Hourly Cashback</span>
      </div>

      <div className="stat-divider"></div>

      <div className="personal-claim-col">
        <div className="claim-info">
          <span className="claim-label">Pending Rewards (Hourly + Unclaimed Fallback)</span>
          <div className="claim-amount-row">
            <span className="claim-amount">{estimatedRewardEth}</span>
            <span className="claim-unit">ETH</span>
          </div>
        </div>
        <div style={{ display: 'flex', gap: '10px', flexWrap: 'wrap' }}>
          {onOpenQuickMint && (
            <button
              type="button"
              onClick={() => onOpenQuickMint(3)}
              className="btn-hud-secondary"
            >
              <ZapIcon size={14} />
              <span>+Mint Tickets</span>
            </button>
          )}
          <button 
            onClick={onClaim} 
            disabled={isClaiming || Number(estimatedRewardEth) === 0} 
            className="btn-claim-rewards"
          >
            {isClaiming ? 'Claiming in progress...' : 'Claim My Rewards'}
          </button>
        </div>
      </div>
    </div>
  );
}
