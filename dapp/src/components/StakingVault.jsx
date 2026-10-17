import React, { useState } from 'react';
import { VaultIcon, SparklesIcon, ShieldCheckIcon, TrophyIcon, ClockIcon } from './Icons';

// Staking Architecture Constants (Matching audited IRLUniswapV4Hook.sol & IRLStaking.sol)
const TOTAL_SUPPLY_IRL = 1_000_000_000;
const MIN_ELIGIBLE_STAKE_IRL = 1_000_000; // 0.10% minimum tier required for 30% ETH Real Yield
const MAX_STAKING_TIER_IRL = 20_000_000;  // 2.00% maximum tier cap for 100% bonuses & Real Yield weight
const MAX_BONUS_PERCENT = 50;             // +50% max multiplier on hourly volume (Top 10 & Tickets)
const MAX_BONUS_TICKETS = 10;             // +10 free tickets every 4 days at full 2% tier
const ESTIMATED_GLOBAL_STAKED_IRL = 80_000_000; // Estimated total eligible staked pool

export default function StakingVault({ 
  account, 
  userBalanceIrl = "0", 
  userStakedIrl = "0",
  userClaimableYieldEth = "0.000",
  lastStakedTimestamp = 0,
  unstakeUnlockTime = 0,
  claimedStakingTickets = 0,
  totalGuildStakedIrl = "1450000",
  userGuildStakedIrl = "0",
  userGuildPendingEth = "0.0000",
  guildTicketCount = 0,
  userGuildStakedDurationSec = 0,
  userGuildEligibleDaily8h = false,
  userGuildEligibleWeekly1d = false,
  onStake,
  onWithdraw,
  onClaimYield,
  onClaimStakingTickets,
  onGuildDeposit,
  onGuildWithdraw,
  onGuildClaimYield,
  onGuildClaimTickets,
  isProcessing = false
}) {
  // 'individual' (1M-20M tier) or 'guild' (Sherwood Co-Staking Guild for <1M small holders)
  const [vaultMode, setVaultMode] = useState('individual');
  // Default to 1,000,000 $IRL (0.10% min eligible tier) so the interactive simulator is immediately active
  const [stakeAmount, setStakeAmount] = useState("1000000");
  const [guildDepositAmount, setGuildDepositAmount] = useState("100000");
  const [isClaimingYield, setIsClaimingYield] = useState(false);
  const [yieldClaimedToast, setYieldClaimedToast] = useState(null);
  const [policyOpen, setPolicyOpen] = useState(false);

  const numBalance = Math.max(0, Number(userBalanceIrl) || 0);
  const numStaked = Math.max(0, Number(userStakedIrl) || 0);
  const numInput = Math.max(0, Number(stakeAmount) || 0);
  const numGuildTotal = Math.max(0, Number(totalGuildStakedIrl) || 0);
  const numGuildUser = Math.max(0, Number(userGuildStakedIrl) || 0);
  const numGuildInput = Math.max(0, Number(guildDepositAmount) || 0);
  const projectedGuildTotal = Math.min(MAX_STAKING_TIER_IRL, numGuildTotal + numGuildInput);
  const projectedGuildUser = numGuildUser + numGuildInput;
  const projectedUserGuildSharePct = projectedGuildTotal > 0
    ? ((projectedGuildUser / projectedGuildTotal) * 100).toFixed(2)
    : "0.00";
  const isGuildThresholdUnlocked = projectedGuildTotal >= MIN_ELIGIBLE_STAKE_IRL;
  const projectedGuildTicketsPer4d = Math.min(
    MAX_BONUS_TICKETS,
    Math.max(isGuildThresholdUnlocked ? 1 : 0, Math.floor((projectedGuildTotal / MAX_STAKING_TIER_IRL) * MAX_BONUS_TICKETS))
  );
  const userGuildHoursStaked = (Number(userGuildStakedDurationSec || 0) / 3600).toFixed(1);

  // Projected total staked (current staked + simulated/input stake amount)
  const projectedTotalStaked = numInput > 0 ? (numStaked + numInput) : numStaked;
  const supplyPct = ((projectedTotalStaked / TOTAL_SUPPLY_IRL) * 100).toFixed(2);

  // Progressive calculation matching IRLUniswapV4Hook.sol:
  // Linearly scales from 0% to 2.0% of total supply (20,000,000 $IRL)
  const progressRatio = Math.min(1.0, projectedTotalStaked / MAX_STAKING_TIER_IRL);
  const calculatedBonusTickets = Math.min(MAX_BONUS_TICKETS, Math.floor(progressRatio * MAX_BONUS_TICKETS));
  const calculatedBonusPercent = Math.min(MAX_BONUS_PERCENT, Number((progressRatio * MAX_BONUS_PERCENT).toFixed(2)));

  // Current staked free tickets eligibility (up to 10 every 4 days)
  const currentStakedRatio = Math.min(1.0, numStaked / MAX_STAKING_TIER_IRL);
  const currentEligibleTickets = Math.min(MAX_BONUS_TICKETS, Math.floor(currentStakedRatio * MAX_BONUS_TICKETS));
  const claimableFreeTickets = Math.max(0, currentEligibleTickets - claimedStakingTickets);

  // Top 10 & Ticket Volume Boost concrete calculations
  const boosted005Volume = (0.05 * (1 + calculatedBonusPercent / 100)).toFixed(4);
  const swapRequiredFor1Ticket = (0.10 / (1 + calculatedBonusPercent / 100)).toFixed(4);

  // On-chain [0.1%, 2.0%] Eligible Staking Weight (matching IRLStaking._computeEligibleWeight)
  const currentEligibleWeight = numStaked < MIN_ELIGIBLE_STAKE_IRL ? 0 : Math.min(MAX_STAKING_TIER_IRL, numStaked);
  const projectedEligibleWeight = projectedTotalStaked < MIN_ELIGIBLE_STAKE_IRL
    ? 0
    : Math.min(MAX_STAKING_TIER_IRL, projectedTotalStaked);
  const isProjectedYieldEligible = projectedEligibleWeight >= MIN_ELIGIBLE_STAKE_IRL;

  // Daily & Weekly Ticket Holding Caps (6 to 10 Daily / 42 to 70 Weekly enforced in IRLTicketNFT._update)
  const calculatedMaxDailyTickets = Math.floor(6 + progressRatio * 4);
  const calculatedMaxWeeklyTickets = calculatedMaxDailyTickets * 7;

  // Equitable pro-rata pool share for the 30% Real Yield stream (bounded by [0.1%, 2.0%] eligible weight)
  const currentStakedSharePercent = currentEligibleWeight > 0 
    ? ((currentEligibleWeight / (ESTIMATED_GLOBAL_STAKED_IRL + currentEligibleWeight)) * 100).toFixed(2)
    : "0.00";
  const projectedStakedSharePercent = projectedEligibleWeight > 0
    ? ((projectedEligibleWeight / (ESTIMATED_GLOBAL_STAKED_IRL + projectedEligibleWeight)) * 100).toFixed(2)
    : "0.00";

  // Hybrid Anti-Sybil Ticket Claim & Unstake Lock Mechanics (Matching IRLStaking.sol & IRLUniswapV4Hook.sol):
  // - Staking alone NEVER locks unstake (unstakeUnlockTime == 0 by default).
  // - If user has staked >= 24h (86400s), claiming free tickets applies ZERO unstake lock.
  // - If user claims free tickets < 24h after staking (Instant Claim), unstake is locked for 24h (unstakeUnlockTime = now + 86400).
  const nowSec = Math.floor(Date.now() / 1000);
  const hasStaked24h = lastStakedTimestamp > 0 && nowSec >= lastStakedTimestamp + 86400;
  const maturityHoursLeft = (lastStakedTimestamp > 0 && !hasStaked24h)
    ? Math.max(1, Math.ceil((lastStakedTimestamp + 86400 - nowSec) / 3600))
    : 0;
  const isUnstakeLocked = unstakeUnlockTime > nowSec;
  const unstakeLockHoursLeft = isUnstakeLocked ? Math.max(1, Math.ceil((unstakeUnlockTime - nowSec) / 3600)) : 0;

  function handleSliderChange(e) {
    const val = Math.max(0, Math.min(MAX_STAKING_TIER_IRL, Number(e.target.value) || 0));
    setStakeAmount(String(val));
  }

  function handleInputChange(e) {
    const raw = e.target.value;
    if (raw === '') {
      setStakeAmount('');
      return;
    }
    const clean = Math.max(0, Number(raw) || 0);
    setStakeAmount(String(clean));
  }

  function handlePresetTier(amountIrl) {
    setStakeAmount(String(amountIrl));
  }

  function handleMax() {
    setStakeAmount(String(numBalance > 0 ? numBalance : MAX_STAKING_TIER_IRL));
  }

  function handleClaimYieldClick() {
    if (!account) return;
    setIsClaimingYield(true);
    setTimeout(() => {
      if (onClaimYield) onClaimYield();
      setYieldClaimedToast(`Successfully claimed ${userClaimableYieldEth} ETH Real Yield to your wallet!`);
      setIsClaimingYield(false);
      setTimeout(() => setYieldClaimedToast(null), 4000);
    }, 1200);
  }

  const sliderValue = Math.min(MAX_STAKING_TIER_IRL, numInput);

  return (
    <div className="staking-vault-panel staking-vault-compact">
      {yieldClaimedToast && (
        <div className="market-toast-banner" style={{ marginBottom: '12px' }}>
          <SparklesIcon size={16} color="var(--color-gold)" />
          <span>{yieldClaimedToast}</span>
        </div>
      )}

      <div className="vault-header">
        <div className="vault-title-wrap">
          <VaultIcon size={20} color="var(--color-gold)" />
          <h2 className="vault-title">The $IRL <em>Real Yield Sanctuary</em></h2>
        </div>
        <div className="vault-status-badge">
          <ShieldCheckIcon size={13} color="var(--color-gold)" />
          <span>0.1%–2.0% Tier • 0h Default Lock</span>
        </div>
      </div>

      {/* Mode Switcher: Individual Staking (1M-20M) vs Sherwood Co-Staking Guild (<1M Small Holders) */}
      <div className="vault-mode-tabs">
        <button
          type="button"
          onClick={() => setVaultMode('individual')}
          className={`vault-mode-btn ${vaultMode === 'individual' ? 'active' : ''}`}
        >
          <span>🏛️ Individual Sanctuary (1M–20M $IRL)</span>
        </button>
        <button
          type="button"
          onClick={() => setVaultMode('guild')}
          className={`vault-mode-btn guild ${vaultMode === 'guild' ? 'active' : ''}`}
        >
          <span>🏹 Sherwood Co-Staking Guild (&lt; 1M $IRL)</span>
        </button>
      </div>

      {/* SHERWOOD CO-STAKING GUILD PANEL (For Small Stakers < 1,000,000 $IRL) */}
      {vaultMode === 'guild' && (
        <div className="sherwood-guild-card">
          <div className="guild-banner-head">
            <div>
              <span className="guild-badge-pill">IRLSherwoodGuildVault.sol • Co-Staking + Shared Lottery Tickets</span>
              <h3 className="guild-title">🏹 Sherwood Co-Staking Guild — Pool $IRL, Claim Guild Tickets &amp; Share ETH Jackpots</h3>
            </div>
            <div className="guild-threshold-pill">
              {isGuildThresholdUnlocked
                ? '✅ ≥ 1,000,000 $IRL Unlocked (Active ETH + Tickets)'
                : `⏳ ${(MIN_ELIGIBLE_STAKE_IRL - projectedGuildTotal).toLocaleString()} $IRL to 1M Threshold`}
            </div>
          </div>

          <p className="guild-desc">
            Holders with <strong>less than 1,000,000 $IRL (&lt; 0.1% supply)</strong> can deposit <strong>any amount of $IRL (&gt; 0, zero minimum!)</strong> into <code>IRLSherwoodGuildVault</code> to pool into <code>IRLStaking.sol</code>, capture the <strong>30% Hourly ETH Real Yield</strong>, and share <strong>100% of any Daily or Sunday Jackpot won by a Guild Ticket</strong> (8h daily / 24h Sunday maturity).
          </p>

          {/* Guild Unclaimed ETH Dividend Card */}
          <div className="real-yield-dividend-card" style={{ borderColor: 'rgba(230, 194, 165, 0.4)' }}>
            <div className="ry-left">
              <span className="ry-label">Your Claimable Sherwood Guild Yield + Lottery Jackpots</span>
              <div className="ry-amount-row">
                <span className="ry-amount-val">{userGuildPendingEth} ETH</span>
                <span className="ry-amount-usd">≈ ${(parseFloat(userGuildPendingEth || '0') * 2640).toFixed(2)} USD</span>
              </div>
              <span className="ry-note">
                Your Guild stake: <strong>{numGuildUser.toLocaleString()} $IRL</strong> ({projectedUserGuildSharePct}% of Guild Pool).
              </span>
            </div>
            <button
              type="button"
              onClick={() => onGuildClaimYield && onGuildClaimYield()}
              disabled={!account || isProcessing || parseFloat(userGuildPendingEth || '0') <= 0}
              className="btn-claim-yield"
            >
              Claim Guild ETH
            </button>
          </div>

          {/* Guild Lottery Ticket & 8h / 1d Eligibility Box */}
          <div className="guild-ticket-eligibility-box">
            <div style={{ flex: '1 1 280px' }}>
              <div style={{ fontSize: '0.8rem', fontWeight: 700, color: 'var(--color-gold)', marginBottom: '4px' }}>
                🎟️ Guild Tickets: {guildTicketCount} Owned (Up to {projectedGuildTicketsPer4d} Free / 4d)
              </div>
              <div style={{ fontSize: '0.73rem', color: '#EAEAEA', lineHeight: 1.45 }}>
                • Daily Draw (≥8h): <strong style={{ color: userGuildEligibleDaily8h ? 'var(--color-mint)' : '#E6C2A5' }}>{numGuildUser > 0 ? (userGuildEligibleDaily8h ? `✅ Eligible (${userGuildHoursStaked}h)` : `⏳ ${userGuildHoursStaked}h/8h`) : 'Stake to Qualify'}</strong>
                {' '}• Sunday Draw (≥24h): <strong style={{ color: userGuildEligibleWeekly1d ? 'var(--color-mint)' : '#E6C2A5' }}>{numGuildUser > 0 ? (userGuildEligibleWeekly1d ? `✅ Eligible (${userGuildHoursStaked}h)` : `⏳ ${userGuildHoursStaked}h/24h`) : 'Stake to Qualify'}</strong>
              </div>
            </div>
            <button
              type="button"
              onClick={() => onGuildClaimTickets && onGuildClaimTickets()}
              disabled={!account || isProcessing || !isGuildThresholdUnlocked}
              className="btn-claim-yield"
            >
              🎟️ Claim Guild Tickets
            </button>
          </div>

          {/* Guild Stats Inline Row */}
          <div className="vault-current-stats vault-inline-balances-strip" style={{ marginTop: '12px' }}>
            <div className="v-stat-card inline-stat-cell">
              <span className="v-stat-label">Total Guild Pooled</span>
              <span className="v-stat-val">{numGuildTotal.toLocaleString()} <span className="v-stat-unit">$IRL</span></span>
              <span className="v-stat-sub">Cap: 20M $IRL (2.0%)</span>
            </div>
            <div className="v-stat-card inline-stat-cell">
              <span className="v-stat-label">Your Guild Deposit</span>
              <span className="v-stat-val">{numGuildUser.toLocaleString()} <span className="v-stat-unit">$IRL</span></span>
              <span className="v-stat-sub">Zero Minimum</span>
            </div>
            <div className="v-stat-card inline-stat-cell">
              <span className="v-stat-label">Projected Share</span>
              <span className="v-stat-val">{projectedUserGuildSharePct}% <span className="v-stat-unit">Guild</span></span>
              <span className="v-stat-sub">ETH + Jackpots</span>
            </div>
          </div>

          {/* Small-Holder Deposit Input & Presets */}
          <div className="stake-control-box" style={{ marginTop: '12px' }}>
            <div className="stake-input-row">
              <div className="input-wrap">
                <input
                  type="number"
                  value={guildDepositAmount}
                  onChange={(e) => setGuildDepositAmount(e.target.value)}
                  placeholder="100000"
                  className="stake-amount-input"
                  min="0"
                  step="10000"
                />
                <span className="input-token-label">$IRL</span>
              </div>
              <button
                type="button"
                onClick={() => setGuildDepositAmount(String(numBalance > 0 ? numBalance : 500000))}
                className="btn-max-badge"
              >
                MAX
              </button>
            </div>

            <div className="tier-preset-pills-row">
              {[
                { label: '25k', val: 25_000 },
                { label: '50k', val: 50_000 },
                { label: '100k', val: 100_000 },
                { label: '250k', val: 250_000 },
                { label: '500k', val: 500_000 },
                { label: '750k', val: 750_000 },
              ].map((preset) => {
                const isActive = numGuildInput === preset.val;
                return (
                  <button
                    key={preset.val}
                    type="button"
                    onClick={() => setGuildDepositAmount(String(preset.val))}
                    className={`tier-preset-pill ${isActive ? 'active' : ''}`}
                  >
                    {preset.label}
                  </button>
                );
              })}
            </div>
          </div>

          <div className="vault-actions-row" style={{ marginTop: '12px' }}>
            <button
              type="button"
              onClick={() => onGuildDeposit && onGuildDeposit(guildDepositAmount)}
              disabled={!account || isProcessing || numGuildInput <= 0}
              className="btn-stake-action"
            >
              {isProcessing
                ? 'Processing Transaction...'
                : !account
                  ? 'Connect Wallet to Join Sherwood Guild'
                  : `Deposit ${numGuildInput.toLocaleString()} $IRL to Sherwood Guild`}
            </button>

            {numGuildUser > 0 && (
              <button
                type="button"
                onClick={() => onGuildWithdraw && onGuildWithdraw(numGuildUser)}
                disabled={!account || isProcessing}
                className="btn-withdraw-action"
              >
                Withdraw {numGuildUser.toLocaleString()} $IRL from Guild
              </button>
            )}
          </div>
        </div>
      )}

      {/* Real Yield Dividend Banner */}
      <div className="real-yield-dividend-card compact-dividend-strip">
        <div className="ry-left">
          <span className="ry-label">Accumulated Real Yield (30% Hourly Stream)</span>
          <div className="ry-amount-row">
            <span className="ry-amount-val">{userClaimableYieldEth} ETH</span>
            <span className="ry-amount-usd">≈ ${(parseFloat(userClaimableYieldEth) * 2450).toFixed(2)} USD</span>
          </div>
          <span className="ry-note">
            Eligible weight: <strong>{currentEligibleWeight.toLocaleString()} $IRL</strong> ({currentStakedSharePercent}% pool share).
          </span>
        </div>
        <button 
          onClick={handleClaimYieldClick}
          disabled={!account || isClaimingYield || parseFloat(userClaimableYieldEth) === 0}
          className="btn-claim-yield"
        >
          {isClaimingYield ? 'Claiming...' : 'Claim Real Yield ETH'}
        </button>
      </div>

      {/* Compacted Single-Row Inline Balance Strip (Replaces 3 Bulky Boxes) */}
      <div className="vault-current-stats vault-inline-balances-strip">
        <div className="v-stat-card inline-stat-cell">
          <span className="v-stat-label">Your Staked $IRL</span>
          <span className="v-stat-val">{numStaked.toLocaleString()} <span className="v-stat-unit">$IRL</span></span>
          <span className="v-stat-sub">
            {((numStaked / TOTAL_SUPPLY_IRL) * 100).toFixed(2)}% supply • {isUnstakeLocked ? `Locked ${unstakeLockHoursLeft}h` : 'Unlocked'}
          </span>
        </div>
        <div className="v-stat-card inline-stat-cell">
          <span className="v-stat-label">Available Wallet Balance</span>
          <span className="v-stat-val">{numBalance.toLocaleString()} <span className="v-stat-unit">$IRL</span></span>
          <span className="v-stat-sub">{((numBalance / TOTAL_SUPPLY_IRL) * 100).toFixed(2)}% of total supply</span>
        </div>
        <div className="v-stat-card inline-stat-cell">
          <span className="v-stat-label">Eligible Yield Weight</span>
          <span className="v-stat-val">{currentStakedSharePercent}% <span className="v-stat-unit">Pool</span></span>
          <span className="v-stat-sub">Capped [1M – 20M $IRL]</span>
        </div>
      </div>

      {/* Interactive Staking Amount & Tier Slider (0% to 2.0% Supply = 0 to 20,000,000 $IRL) */}
      <div className="stake-control-box compact-stake-controls">
        <div className="stake-control-header-row">
          <span className="stake-calc-title">
            Stake Amount &amp; Tier Calculator (0.00% to 2.00% Supply)
          </span>
          <span className="stake-calc-pct">
            {supplyPct}% Supply • {isProjectedYieldEligible ? `✅ ${(progressRatio * 100).toFixed(0)}% Max Bonus` : '⚠️ Min 1M for Yield'}
          </span>
        </div>

        <div className="stake-input-row">
          <div className="input-wrap">
            <input 
              type="number" 
              value={stakeAmount}
              onChange={handleInputChange}
              placeholder="1000000"
              className="stake-amount-input"
              min="0"
              step="100000"
            />
            <span className="input-token-label">$IRL</span>
          </div>
          <button onClick={handleMax} className="btn-max-badge" title="Set to 2.0% Max Tier (or Wallet Max)">
            {numBalance > 0 ? 'MAX' : '2% MAX'}
          </button>
        </div>

        {/* Fluid Controlled Slider (0 to 20,000,000 $IRL in 100,000 $IRL steps) */}
        <div className="slider-row">
          <input 
            type="range" 
            min="0" 
            max={MAX_STAKING_TIER_IRL}
            step="100000"
            value={sliderValue}
            onChange={handleSliderChange} 
            className="stake-slider"
          />
          <div className="slider-marks">
            <span onClick={() => handlePresetTier(0)} style={{ cursor: 'pointer' }}>0%</span>
            <span onClick={() => handlePresetTier(1_000_000)} style={{ cursor: 'pointer', color: 'var(--color-rosegold-light)' }}>0.1% (1M)</span>
            <span onClick={() => handlePresetTier(5_000_000)} style={{ cursor: 'pointer' }}>0.5% (5M)</span>
            <span onClick={() => handlePresetTier(10_000_000)} style={{ cursor: 'pointer' }}>1.0% (10M)</span>
            <span onClick={() => handlePresetTier(20_000_000)} style={{ cursor: 'pointer', color: 'var(--color-gold)' }}>2.0% (20M)</span>
          </div>
        </div>

        {/* Quick Tier Preset Pills */}
        <div className="tier-preset-pills-row">
          {[
            { label: '0.10% (1M)', val: 1_000_000 },
            { label: '0.25% (2.5M)', val: 2_500_000 },
            { label: '0.50% (5M)', val: 5_000_000 },
            { label: '1.00% (10M)', val: 10_000_000 },
            { label: '2.00% Max (20M)', val: 20_000_000 },
          ].map((preset) => {
            const isActive = numInput === preset.val;
            return (
              <button
                key={preset.val}
                type="button"
                onClick={() => handlePresetTier(preset.val)}
                className={`tier-preset-pill ${isActive ? 'active' : ''}`}
              >
                {preset.label}
              </button>
            );
          })}
        </div>
      </div>

      {/* Compact 2x2 Live Projection Grid */}
      <div className="vault-benefits-projection compact-2x2-grid">
        <div className="benefit-item">
          <span className="benefit-icon-ring">
            <SparklesIcon size={14} color="var(--color-gold)" />
          </span>
          <div className="benefit-text">
            <span className="benefit-val">+{calculatedBonusPercent}% Volume Boost</span>
            <span className="benefit-sub">
              0.05 ETH swap = <strong>{boosted005Volume} WETH</strong> score (~{swapRequiredFor1Ticket} ETH / ticket).
            </span>
          </div>
        </div>

        <div className="benefit-item">
          <span className="benefit-icon-ring">
            <TrophyIcon size={14} color="var(--color-gold)" />
          </span>
          <div className="benefit-text">
            <span className="benefit-val">
              {isProjectedYieldEligible
                ? `~${projectedStakedSharePercent}% of 30% ETH Pool`
                : '0.00% Yield (Min 1M $IRL)'}
            </span>
            <span className="benefit-sub">
              {isProjectedYieldEligible
                ? `Weight: ${projectedEligibleWeight.toLocaleString()} $IRL [0.1%–2.0%]`
                : 'Stake ≥ 1,000,000 $IRL (0.10%) to unlock Real Yield.'}
            </span>
          </div>
        </div>

        <div className="benefit-item">
          <span className="benefit-icon-ring">
            <SparklesIcon size={14} color="var(--color-gold)" />
          </span>
          <div className="benefit-text">
            <span className="benefit-val">+{calculatedBonusTickets} Free Tickets / 4d</span>
            <span className="benefit-sub">
              0h lock after 24h staked, or Instant Claim with 24h lock.
            </span>
          </div>
        </div>

        <div className="benefit-item">
          <span className="benefit-icon-ring">
            <ShieldCheckIcon size={14} color="var(--color-gold)" />
          </span>
          <div className="benefit-text">
            <span className="benefit-val">{calculatedMaxDailyTickets} Daily / {calculatedMaxWeeklyTickets} Weekly Cap</span>
            <span className="benefit-sub">
              Expanded NFT ticket holding cap (vs 6/42 standard).
            </span>
          </div>
        </div>
      </div>

      {/* Collapsible Accordion for Hybrid Staking & Free Ticket Policy */}
      <div className={`policy-accordion-box ${policyOpen ? 'open' : ''}`}>
        <button
          type="button"
          className="policy-accordion-trigger"
          onClick={() => setPolicyOpen(!policyOpen)}
          aria-expanded={policyOpen}
        >
          <div className="policy-trigger-left">
            <ClockIcon size={15} color="var(--color-gold)" />
            <span>
              <strong>Hybrid Staking &amp; Free Ticket Policy</strong> — 0h Default Unstake Lock • 24h Maturity
            </span>
          </div>
          <span className="policy-trigger-chevron">{policyOpen ? '▴ Hide' : '▾ Details'}</span>
        </button>

        {policyOpen && (
          <div className="policy-accordion-body">
            <p className="policy-accordion-text">
              Staking NEVER locks your $IRL by default (withdraw anytime). Wait <strong>24h of staking</strong> to claim your free tickets with <strong>0h lock (Zero Lock)</strong>, or use <strong>Instant Claim (&lt;24h)</strong> to receive them immediately and lock unstake for 24h!
            </p>

            {numStaked >= 2_000_000 && (
              <div className="policy-free-ticket-claim-row">
                <div>
                  <span style={{ color: 'var(--color-gold)', fontWeight: 700, fontSize: '0.8rem' }}>
                    Free 4-Day Staking Tickets: {claimedStakingTickets} / {currentEligibleTickets} Claimed
                  </span>
                  <span style={{ display: 'block', fontSize: '0.73rem', color: 'var(--color-text-secondary)', marginTop: '2px' }}>
                    {hasStaked24h
                      ? '✅ 24h Staking Maturity Reached — Zero Lock!'
                      : `⚡ Staked < 24h (${maturityHoursLeft}h left) — Instant Claim locks unstake for 24h.`}
                  </span>
                </div>
                <button
                  type="button"
                  disabled={!account || isProcessing || claimableFreeTickets === 0}
                  onClick={() => onClaimStakingTickets && onClaimStakingTickets({ isInstant: !hasStaked24h, count: claimableFreeTickets })}
                  className="btn-claim-free-tickets"
                >
                  {claimableFreeTickets === 0
                    ? `All ${currentEligibleTickets} Free Tickets Claimed`
                    : hasStaked24h
                      ? `🎟️ Claim +${claimableFreeTickets} Tickets (Zero Lock)`
                      : `⚡ Instant Claim +${claimableFreeTickets} Tickets (24h Lock)`}
                </button>
              </div>
            )}
          </div>
        )}
      </div>

      {/* Actions */}
      <div className="vault-actions-row">
        <button 
          onClick={() => onStake && onStake(stakeAmount)} 
          disabled={!account || isProcessing || numInput === 0 || (numBalance > 0 && numInput > numBalance)}
          className="btn-stake-action"
        >
          {isProcessing ? 'Processing Transaction...' : !account ? 'Connect Wallet to Stake' : `Deposit ${numInput.toLocaleString()} $IRL (Zero Unstake Lock)`}
        </button>

        {numStaked > 0 && (
          <button 
            onClick={() => onWithdraw && onWithdraw(numStaked)} 
            disabled={!account || isProcessing || isUnstakeLocked}
            className="btn-withdraw-action"
            title={isUnstakeLocked ? `24h Instant-Ticket Unstake Lock Active (${unstakeLockHoursLeft}h remaining)` : 'Withdraw staked $IRL anytime'}
          >
            {isUnstakeLocked ? `Unstake Locked (${unstakeLockHoursLeft}h — Instant Tickets Claimed)` : 'Withdraw from Staking (Unlocked)'}
          </button>
        )}
      </div>
    </div>
  );
}


