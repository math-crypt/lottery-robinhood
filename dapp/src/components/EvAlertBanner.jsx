import React from 'react';
import { SparklesIcon, TicketIcon, FlameIcon } from './Icons';

/**
 * Live Scrolling +EV & Probability Ticker Banner (English)
 * Calculates real-time win probabilities from active daily tickets in play and live pots.
 */
export default function EvAlertBanner({
  dailyTicketsInPlay = 0,
  lotteryPotEth = "0.004",
  sundayPotEth = "0.700",
  hourlyPotEth = "0.003",
  activeReferral = null,
  onSelectTab,
  onOpenQuickMint,
}) {
  const activeDaily = Math.max(0, Number(dailyTicketsInPlay) || 0);
  const oneTicketOddsPct = ((1 / (activeDaily + 1)) * 100).toFixed(1);
  const threeTicketsOddsPct = ((3 / (activeDaily + 3)) * 100).toFixed(1);
  const sixTicketsOddsPct = ((6 / (activeDaily + 6)) * 100).toFixed(1);

  const sundayEthNum = Math.max(0, parseFloat(sundayPotEth) || 0.7);
  const dailyEthNum = Math.max(0, parseFloat(lotteryPotEth) || 0);
  const sundayUsd = Math.round(sundayEthNum * 2640).toLocaleString();
  const combinedEth = (sundayEthNum + dailyEthNum).toFixed(3);

  const tickerMessages = [
    `🚨 PROBABILITY ALERT (+EV): Only ${activeDaily} ticket${activeDaily === 1 ? '' : 's'} in play today! Minting 1 ticket right now gives you a ${oneTicketOddsPct}% chance (1 in ${activeDaily + 1}) to win tonight's 00:00 UTC Daily Draw + an automatic entry for Sunday's ${sundayEthNum.toFixed(3)} ETH (~$${sundayUsd}) Mega-Jackpot!`,
    `🎯 LIVE WIN ODDS CALCULATOR: Mint 1 Ticket (0.10 ETH vol) = ${oneTicketOddsPct}% Chance Tonight • Mint 3 Tickets (0.30 ETH vol) = ${threeTicketsOddsPct}% Chance • Mint 6 Tickets = ${sixTicketsOddsPct}% Chance!`,
    `⚡ INSTANT TRADER REWARDS: Every 0.10 ETH swap on irlprotocol.xyz mints 1 NFT Lottery Ticket directly to your wallet + streams 0.4375% Instant ETH Cashback + Top 10 Hourly Pool (${hourlyPotEth} ETH)!`,
    `🏹 SHERWOOD CO-STAKING GUILD: Hold under 1,000,000 $IRL? Pool your tokens in the Sherwood Guild Vault with ZERO minimum deposit and share the 30% Hourly Native ETH Real Yield pro-rata!`,
    `🔗 CUSTOM REFERRAL LINKS LIVE: Customize your personal referral handle (?ref=your-name) to earn 0.25% in native ETH on all referred volume while giving your friends a +10% Leaderboard Score Boost!`,
  ];

  // Duplicate messages for seamless infinite CSS marquee loop
  const fullTrack = [...tickerMessages, ...tickerMessages];

  return (
    <div className="ev-alert-marquee-wrapper" role="region" aria-label="Live Probability and EV Alert Ticker">
      <div className="ev-alert-badge-left">
        <span className="ev-pulse-dot" />
        <FlameIcon size={14} color="#041f12" />
        <span>LIVE +EV ODDS: {oneTicketOddsPct}%</span>
      </div>

      <div className="ev-alert-marquee-viewport">
        <div className="ev-alert-marquee-track">
          {fullTrack.map((msg, idx) => (
            <span key={idx} className="ev-alert-marquee-item">
              {msg}
              <span className="ev-alert-separator">✦</span>
            </span>
          ))}
        </div>
      </div>

      <div className="ev-alert-actions-right">
        {activeReferral && activeReferral.code && (
          <span className="ev-referral-active-pill" title={`Referred by ${activeReferral.code}`}>
            🏹 Ref: @{activeReferral.code} (+10% Boost)
          </span>
        )}
        <button
          type="button"
          className="ev-alert-cta-btn"
          onClick={() => (onOpenQuickMint ? onOpenQuickMint(1) : onSelectTab && onSelectTab('trade'))}
        >
          <span>⚡ MINT 1 TICKET ({oneTicketOddsPct}% ODDS)</span>
        </button>
      </div>
    </div>
  );
}
