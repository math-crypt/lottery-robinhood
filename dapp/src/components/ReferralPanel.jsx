import React, { useState, useEffect } from 'react';
import { SparklesIcon, ShieldCheckIcon, TrophyIcon, CheckIcon } from './Icons';

const ALIAS_REGEX = /^[a-z0-9][a-z0-9_-]{2,23}$/;

export default function ReferralPanel({
  account,
  onConnect,
  leaderboardInfo = null,
  activeReferral = null,
  onApplyReferralCode,
}) {
  const [customAlias, setCustomAlias] = useState('');
  const [manualWallet, setManualWallet] = useState('');
  const [savedAlias, setSavedAlias] = useState('');
  const [friendCodeInput, setFriendCodeInput] = useState('');
  const [statusMessage, setStatusMessage] = useState(null);
  const [copiedType, setCopiedType] = useState(null);

  const effectiveWallet = (account || manualWallet || '').trim().toLowerCase();
  const isValidWallet = /^0x[a-fA-F0-9]{40}$/.test(effectiveWallet);

  // Sync saved alias from on-chain/bot leaderboard snapshot or localStorage
  useEffect(() => {
    if (!effectiveWallet) return;
    const serverAlias = leaderboardInfo?.referrals?.addressToAlias?.[effectiveWallet];
    const localMapRaw = localStorage.getItem('irl_custom_referral_aliases');
    let localAlias = '';
    if (localMapRaw) {
      try {
        const parsed = JSON.parse(localMapRaw);
        localAlias = parsed[effectiveWallet] || '';
      } catch (_) {}
    }
    const resolved = serverAlias || localAlias;
    if (resolved) {
      setSavedAlias(resolved);
      if (!customAlias) setCustomAlias(resolved);
    }
  }, [effectiveWallet, leaderboardInfo]);

  const handleSaveCustomAlias = (e) => {
    e.preventDefault();
    if (!isValidWallet) {
      setStatusMessage({ type: 'error', text: 'Please connect your Web3 wallet or enter a valid 0x wallet address first.' });
      return;
    }
    const cleanAlias = customAlias.trim().toLowerCase();
    if (!ALIAS_REGEX.test(cleanAlias) || cleanAlias.startsWith('0x')) {
      setStatusMessage({
        type: 'error',
        text: 'Custom handle must be 3–24 characters using only lowercase letters, numbers, dashes (-), or underscores (_).',
      });
      return;
    }

    // Check if taken by another wallet in public snapshot
    const existingOwner = leaderboardInfo?.referrals?.aliasToAddress?.[cleanAlias];
    if (existingOwner && existingOwner.toLowerCase() !== effectiveWallet) {
      setStatusMessage({
        type: 'error',
        text: `The handle "@${cleanAlias}" is already registered by another wallet.`,
      });
      return;
    }

    try {
      const localMapRaw = localStorage.getItem('irl_custom_referral_aliases');
      const map = localMapRaw ? JSON.parse(localMapRaw) : {};
      map[effectiveWallet] = cleanAlias;
      map[`alias:${cleanAlias}`] = effectiveWallet;
      localStorage.setItem('irl_custom_referral_aliases', JSON.stringify(map));
    } catch (_) {}

    setSavedAlias(cleanAlias);
    setStatusMessage({
      type: 'success',
      text: `Custom referral handle @${cleanAlias} saved! Your personalized link is ready to share.`,
    });
  };

  // Build referral URLs:
  // 1. Vanity short URL (`https://irlprotocol.xyz/?ref=alias`)
  // 2. Self-verifying instant link (`https://irlprotocol.xyz/?ref=alias&r=0xWallet`) so even before bot sync, any browser resolves `0xWallet`!
  const activeHandle = savedAlias || (ALIAS_REGEX.test(customAlias.trim().toLowerCase()) ? customAlias.trim().toLowerCase() : '');
  const isSyncedOnServer = Boolean(
    activeHandle &&
    leaderboardInfo?.referrals?.aliasToAddress?.[activeHandle]?.toLowerCase() === effectiveWallet
  );

  const primaryReferralUrl = isValidWallet
    ? activeHandle
      ? isSyncedOnServer
        ? `https://irlprotocol.xyz/?ref=${activeHandle}`
        : `https://irlprotocol.xyz/?ref=${activeHandle}&r=${effectiveWallet}`
      : `https://irlprotocol.xyz/?ref=${effectiveWallet}`
    : 'https://irlprotocol.xyz/?ref=your-custom-name';

  const cleanVanityDisplayUrl = isValidWallet
    ? `https://irlprotocol.xyz/?ref=${activeHandle || effectiveWallet.slice(0, 10)}`
    : 'https://irlprotocol.xyz/?ref=your-custom-name';

  const copyToClipboard = (text, label) => {
    if (navigator.clipboard) {
      navigator.clipboard.writeText(text);
      setCopiedType(label);
      setTimeout(() => setCopiedType(null), 2500);
    }
  };

  const handleApplyFriendCode = (e) => {
    e.preventDefault();
    const clean = friendCodeInput.trim();
    if (!clean) return;
    if (onApplyReferralCode) {
      onApplyReferralCode(clean);
      setFriendCodeInput('');
    }
  };

  // Find current user's referrer stats if available
  const topReferrers = leaderboardInfo?.referrals?.topReferrers || [];
  const myStats = isValidWallet
    ? topReferrers.find((r) => r.address?.toLowerCase() === effectiveWallet)
    : null;

  return (
    <section className="referral-sanctuary-panel" id="referral-sanctuary">
      <div className="vault-header referral-vault-header">
        <div className="vault-title-wrap">
          <SparklesIcon size={24} color="#E6C2A5" />
          <h2 className="vault-title referral-hero-title">
            Robinhood <em>Referral Sanctuary</em>
          </h2>
        </div>
        <div className="vault-status-badge referral-status-badge">
          <ShieldCheckIcon size={14} color="#E6C2A5" />
          <span>0.25% Native ETH Commission • +10% Referee Score Boost • On-Chain HookData</span>
        </div>
      </div>

      <p className="vault-desc referral-vault-desc">
        Personalize your custom referral link (<code>?ref=your-custom-code</code>) and invite traders to{' '}
        <strong>irlprotocol.xyz</strong>. You earn <strong>0.25% of all referred swap volume in native ETH</strong>{' '}
        (25% of the Protocol Fee share streamed hourly), while every friend who trades through your link automatically receives a{' '}
        <strong>+10% Hourly Leaderboard Volume Boost</strong> encoded directly in Uniswap V4 <code>hookData</code>!
      </p>

      {/* Dual Value Proposition Highlight Pills */}
      <div className="referral-value-pills-row">
        <div className="ref-val-pill rose-gold">
          <span className="ref-val-icon">💎</span>
          <span className="ref-val-text">
            <strong>Your Commission:</strong> 0.25% Native ETH on All Referred Volume (25% Protocol Share)
          </span>
        </div>
        <div className="ref-val-pill bronze">
          <span className="ref-val-icon">⚡</span>
          <span className="ref-val-text">
            <strong>Friend Benefit:</strong> +10% Hourly Leaderboard Volume Boost (V4 HookData)
          </span>
        </div>
      </div>

      {/* Active Referee Banner if user clicked someone's link */}
      {activeReferral && activeReferral.code && (
        <div className="referral-active-banner">
          <div style={{ display: 'flex', alignItems: 'center', gap: '10px', flexWrap: 'wrap' }}>
            <CheckIcon size={18} color="#E6C2A5" />
            <span>
              <strong>Active Referral Bonus:</strong> Linked to referrer{' '}
              <code style={{ color: '#E6C2A5' }}>@{activeReferral.code}</code>
              {activeReferral.referrerAddress ? ` (${activeReferral.referrerAddress.slice(0, 6)}...${activeReferral.referrerAddress.slice(-4)})` : ''}
              {' '}— Your swaps receive an automatic <strong>+10% Hourly Leaderboard Score Boost</strong>!
            </span>
          </div>
        </div>
      )}

      <div className="referral-grid-layout">
        {/* Left Card: Custom Referral Link Personalization */}
        <div className="referral-builder-card">
          <div className="ref-card-header">
            <span className="ref-step-pill">STEP 1 • CUSTOMIZE YOUR HANDLE</span>
            <span className="ref-wallet-bound-tag">
              {isValidWallet ? `Bound to ${effectiveWallet.slice(0, 6)}...${effectiveWallet.slice(-4)}` : 'Connect or Enter Wallet'}
            </span>
          </div>

          {!account && (
            <div className="ref-manual-wallet-wrap">
              <label className="ref-field-label">
                Your Robinhood Chain Wallet Address (0x...) or Connect Wallet:
              </label>
              <div style={{ display: 'flex', gap: '8px' }}>
                <input
                  type="text"
                  value={manualWallet}
                  onChange={(e) => setManualWallet(e.target.value)}
                  placeholder="0xYourWalletAddress..."
                  className="referral-text-input"
                />
                <button type="button" onClick={onConnect} className="btn-ref-secondary">
                  Connect
                </button>
              </div>
            </div>
          )}

          <form onSubmit={handleSaveCustomAlias} className="ref-alias-form">
            <label className="ref-field-label">
              Choose Your Custom Referral Code (3–24 chars: letters, numbers, <code>-</code>, <code>_</code>):
            </label>
            <div className="referral-input-group unified-obsidian-chamber">
              <span className="referral-url-prefix">irlprotocol.xyz/?ref=</span>
              <input
                type="text"
                value={customAlias}
                onChange={(e) => setCustomAlias(e.target.value.toLowerCase().replace(/[^a-z0-9_-]/g, ''))}
                placeholder="robinhood-king"
                maxLength={24}
                className="referral-handle-input"
              />
              <button type="submit" className="btn-save-alias">
                Save Handle
              </button>
            </div>
          </form>

          {statusMessage && (
            <div className={`ref-status-box ${statusMessage.type}`}>
              {statusMessage.text}
            </div>
          )}

          {/* Generated Link Display & 1-Click Share */}
          <div className="referral-generated-box">
            <div className="ref-gen-top-row">
              <span className="ref-gen-label">
                YOUR PERSONALIZED REFERRAL LINK
              </span>
              <span className="ref-gen-handle">
                {activeHandle ? `@${activeHandle}` : 'Default Wallet Link'}
              </span>
            </div>

            <div className="referral-link-copy-row">
              <code className="referral-link-code" title={primaryReferralUrl}>
                {cleanVanityDisplayUrl}
              </code>
              <button
                type="button"
                onClick={() => copyToClipboard(primaryReferralUrl, 'link')}
                className="btn-copy-ref-link"
              >
                {copiedType === 'link' ? '✓ Copied!' : '📋 Copy Link'}
              </button>
            </div>

            <div className="ref-share-actions-row">
              <a
                href={`https://x.com/intent/tweet?text=${encodeURIComponent(
                  `🏹 Trading $IRL on Robinhood Chain! Only a few tickets in play today for the 00:00 UTC Daily Draw + 0.70 ETH Sunday Mega-Jackpot!\n\nUse my custom referral link for an automatic +10% Hourly Leaderboard Score Boost:\n${primaryReferralUrl}`
                )}`}
                target="_blank"
                rel="noopener noreferrer"
                className="btn-ref-share"
              >
                Share on 𝕏
              </a>
              <a
                href={`https://t.me/share/url?url=${encodeURIComponent(primaryReferralUrl)}&text=${encodeURIComponent(
                  '🏹 Mint $IRL Lottery Tickets with +10% Hourly Leaderboard Volume Boost via my Robinhood Referral Link!'
                )}`}
                target="_blank"
                rel="noopener noreferrer"
                className="btn-ref-share"
              >
                Share on Telegram
              </a>
              {isValidWallet && activeHandle && (
                <button
                  type="button"
                  onClick={() => copyToClipboard(`/setref ${activeHandle} ${effectiveWallet}`, 'tgcmd')}
                  className="btn-ref-share"
                  title="Copy command to also bind your custom code in the official Telegram Bot"
                >
                  {copiedType === 'tgcmd' ? '✓ TG Command Copied!' : '🤖 Copy /setref Bot Cmd'}
                </button>
              )}
            </div>
          </div>
        </div>

        {/* Right Card: My Referral Earnings & Enter Friend's Code */}
        <div className="referral-stats-card">
          <div className="ref-card-header">
            <span className="ref-step-pill">YOUR REFERRAL METRICS &amp; LEADERBOARD</span>
            <TrophyIcon size={16} color="#E6C2A5" />
          </div>

          <div className="referral-metrics-strip">
            <div className="ref-metric-box">
              <span className="ref-stat-label">REFERRED TRADERS</span>
              <span className="ref-stat-val">{myStats ? myStats.referredCount : 0}</span>
              <span className="ref-stat-sub">Bound to your handle</span>
            </div>
            <div className="ref-metric-box">
              <span className="ref-stat-label">REFERRED VOLUME</span>
              <span className="ref-stat-val">
                {myStats ? myStats.totalVolumeEth : '0.000'} <span className="ref-stat-unit">ETH</span>
              </span>
              <span className="ref-stat-sub">Tracked via V4 HookData</span>
            </div>
            <div className="ref-metric-box">
              <span className="ref-stat-label">ETH REFERRAL COMMISSION</span>
              <span className="ref-stat-val gold">
                {myStats ? myStats.totalEarnedEth : '0.0000'} <span className="ref-stat-unit">ETH</span>
              </span>
              <span className="ref-stat-sub">0.25% Volume Share</span>
            </div>
          </div>

          {/* Apply a Friend's Referral Code Manually */}
          <form onSubmit={handleApplyFriendCode} className="ref-friend-form">
            <label className="ref-field-label">
              Have a Friend&apos;s Custom Referral Code? Activate Your +10% Score Boost:
            </label>
            <div style={{ display: 'flex', gap: '8px' }}>
              <input
                type="text"
                value={friendCodeInput}
                onChange={(e) => setFriendCodeInput(e.target.value)}
                placeholder="Enter friend's code (e.g. robinhood) or 0x..."
                className="referral-text-input"
              />
              <button type="submit" className="btn-ref-secondary">
                Activate +10%
              </button>
            </div>
          </form>

          {/* Top Referrers Table matching Homepage Leaderboard aesthetic */}
          <div className="ref-leaderboard-box">
            <div className="ref-table-header-title">
              <span className="ref-table-icon">🏆</span>
              <span>TOP ROBINHOOD REFERRERS (ON-CHAIN VERIFIED)</span>
            </div>

            <div className="ref-table-head-row">
              <span className="ref-col-rank">RANK</span>
              <span className="ref-col-handle">HANDLE / WALLET</span>
              <span className="ref-col-vol">REFERRED VOL</span>
              <span className="ref-col-earned">ETH EARNED</span>
            </div>

            {topReferrers.length === 0 ? (
              <div className="ref-table-empty">
                Custom referral tracking is live! Customize your handle on the left and share your link to claim the #1 spot.
              </div>
            ) : (
              <div className="ref-table-body">
                {topReferrers.slice(0, 4).map((ref, idx) => (
                  <div key={ref.address || idx} className={`ref-table-row rank-${idx + 1}`}>
                    <span className="ref-col-rank">
                      <span className={`ref-rank-badge rank-${idx + 1}`}>#{idx + 1}</span>
                    </span>
                    <span className="ref-col-handle">
                      <code className="ref-handle-tag">@{ref.displayHandle}</code>
                      <span className="ref-count-tag">{ref.referredCount} ref(s)</span>
                    </span>
                    <span className="ref-col-vol">
                      {ref.totalVolumeEth} <span className="ref-unit-sub">ETH</span>
                    </span>
                    <span className="ref-col-earned gold">
                      +{ref.totalEarnedEth} <span className="ref-unit-sub">ETH</span>
                    </span>
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>
      </div>
    </section>
  );
}
