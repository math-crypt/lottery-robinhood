import React, { useState, useEffect, useRef } from 'react';
import { ClockIcon, SparklesIcon, TrophyIcon, FlameIcon, VaultIcon, ZapIcon, TicketIcon } from './Icons';

/**
 * 60 FPS Inertia Odometer Hook: smoothly interpolates numeric strings on load & on-chain updates
 */
function useInertiaNumber(rawStr, decimals = 3, isInteger = false) {
  const cleanTarget = parseFloat(String(rawStr || '0').replace(/[^0-9.-]/g, '')) || 0;
  const [displayVal, setDisplayVal] = useState(cleanTarget);
  const prevRef = useRef(cleanTarget);

  useEffect(() => {
    const startVal = prevRef.current;
    const endVal = cleanTarget;
    if (Math.abs(endVal - startVal) < 0.0001) {
      setDisplayVal(endVal);
      prevRef.current = endVal;
      return;
    }
    let rafId = null;
    const duration = 650;
    const startTime = performance.now();

    const step = (now) => {
      const t = Math.min(1, (now - startTime) / duration);
      const ease = 1 - Math.pow(1 - t, 3);
      const current = startVal + (endVal - startVal) * ease;
      setDisplayVal(current);
      if (t < 1) {
        rafId = requestAnimationFrame(step);
      } else {
        prevRef.current = endVal;
      }
    };

    rafId = requestAnimationFrame(step);
    return () => {
      if (rafId) cancelAnimationFrame(rafId);
    };
  }, [cleanTarget]);

  if (isInteger) {
    return Math.round(displayVal).toLocaleString('en-US');
  }
  return displayVal.toFixed(decimals);
}

/**
 * 60 FPS Hardware-Accelerated HTML5 Canvas: OpenVRF Quantum Ring Visualizer
 * Renders orbiting active tickets, simulated user tickets, and cryptographic VRF sweep.
 */
function OpenVrfQuantumCanvas({
  sundayTickets = 177,
  simulatedTickets = 3,
  sundayOddsPct = '1.7',
  dailyOddsPct = '60.0',
}) {
  const canvasRef = useRef(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    let rafId = null;
    let angle = 0;
    const size = 192;
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    canvas.width = size * dpr;
    canvas.height = size * dpr;
    ctx.scale(dpr, dpr);

    const cx = size / 2;
    const cy = size / 2;
    const outerR = 82;
    const innerR = 62;

    const totalPool = Math.max(1, Number(sundayTickets) + Number(simulatedTickets));
    const rawShareAngle = (Number(simulatedTickets) / totalPool) * Math.PI * 2;
    const userShareAngle = Math.max(0.22, rawShareAngle);
    const visibleNodes = Math.min(36, Math.max(8, totalPool));
    const simNodeCount = Math.max(
      1,
      Math.round((Number(simulatedTickets) / totalPool) * visibleNodes)
    );

    const render = () => {
      ctx.clearRect(0, 0, size, size);
      angle += 0.008;

      // 1. Subtle Ambient Radial Core Glow
      const coreGrad = ctx.createRadialGradient(cx, cy, 8, cx, cy, outerR + 12);
      coreGrad.addColorStop(0, 'rgba(230, 194, 165, 0.14)');
      coreGrad.addColorStop(0.6, 'rgba(14, 86, 58, 0.10)');
      coreGrad.addColorStop(1, 'rgba(2, 7, 5, 0)');
      ctx.fillStyle = coreGrad;
      ctx.beginPath();
      ctx.arc(cx, cy, outerR + 12, 0, Math.PI * 2);
      ctx.fill();

      // 2. Precision Swiss Chronograph Outer Ticks (60 ticks)
      for (let i = 0; i < 60; i++) {
        const tickAngle = (i / 60) * Math.PI * 2 + angle * 0.25;
        const isMajor = i % 5 === 0;
        const r1 = isMajor ? outerR - 5 : outerR - 2.5;
        const r2 = outerR + 1.5;
        ctx.strokeStyle = isMajor ? 'rgba(243, 213, 186, 0.45)' : 'rgba(230, 194, 165, 0.16)';
        ctx.lineWidth = isMajor ? 1.4 : 0.8;
        ctx.beginPath();
        ctx.moveTo(cx + Math.cos(tickAngle) * r1, cy + Math.sin(tickAngle) * r1);
        ctx.lineTo(cx + Math.cos(tickAngle) * r2, cy + Math.sin(tickAngle) * r2);
        ctx.stroke();
      }

      // 3. Base Inner Track Ring
      ctx.strokeStyle = 'rgba(230, 194, 165, 0.14)';
      ctx.lineWidth = 4;
      ctx.beginPath();
      ctx.arc(cx, cy, innerR, 0, Math.PI * 2);
      ctx.stroke();

      // 4. Highlighted User Win-Probability Sector Arc (Rose Gold -> Champagne)
      const startArc = -Math.PI / 2 + Math.sin(angle * 0.7) * 0.15;
      const endArc = startArc + userShareAngle;
      const arcGrad = ctx.createLinearGradient(0, 0, size, size);
      arcGrad.addColorStop(0, '#FFF2E2');
      arcGrad.addColorStop(0.5, '#E6C2A5');
      arcGrad.addColorStop(1, '#CD7F32');
      ctx.strokeStyle = arcGrad;
      ctx.lineWidth = 5.5;
      ctx.lineCap = 'round';
      ctx.beginPath();
      ctx.arc(cx, cy, innerR, startArc, endArc);
      ctx.stroke();

      // 5. Sweeping OpenVRF Radar Verification Beam
      const beamAngle = angle * 1.8;
      ctx.strokeStyle = 'rgba(255, 242, 226, 0.35)';
      ctx.lineWidth = 1.2;
      ctx.beginPath();
      ctx.moveTo(cx, cy);
      ctx.lineTo(cx + Math.cos(beamAngle) * outerR, cy + Math.sin(beamAngle) * outerR);
      ctx.stroke();

      // 6. Orbiting Ticket Nodes (User Simulated Nodes vs Pool Nodes)
      for (let i = 0; i < visibleNodes; i++) {
        const nodeAngle = (i / visibleNodes) * Math.PI * 2 - angle * 0.6;
        const nx = cx + Math.cos(nodeAngle) * (outerR - 10);
        const ny = cy + Math.sin(nodeAngle) * (outerR - 10);
        const isUserNode = i < simNodeCount;

        ctx.beginPath();
        ctx.arc(nx, ny, isUserNode ? 3.4 : 2.0, 0, Math.PI * 2);
        ctx.fillStyle = isUserNode ? '#FFF2E2' : 'rgba(230, 194, 165, 0.32)';
        ctx.fill();

        if (isUserNode) {
          ctx.beginPath();
          ctx.arc(nx, ny, 6.5, 0, Math.PI * 2);
          ctx.fillStyle = 'rgba(243, 213, 186, 0.22)';
          ctx.fill();
        }
      }

      rafId = requestAnimationFrame(render);
    };

    rafId = requestAnimationFrame(render);
    return () => {
      if (rafId) cancelAnimationFrame(rafId);
    };
  }, [sundayTickets, simulatedTickets]);

  return (
    <div className="openvrf-quantum-ring-box" title="Live OpenVRF Probability Visualizer">
      <canvas ref={canvasRef} className="openvrf-quantum-canvas" />
      <div className="openvrf-ring-center-hud">
        <span className="ring-hud-kicker">SUNDAY ODDS</span>
        <span className="ring-hud-odds">{sundayOddsPct}%</span>
        <span className="ring-hud-sub">TONIGHT: {dailyOddsPct}%</span>
      </div>
    </div>
  );
}

export default function PotSanctuary({ 
  hourlyPotEth = "0.000", 
  lotteryPotEth = "0.000",
  sundayPotEth = "0.000",
  dailyTicketsInPlay = 0,
  sundayTicketsInPlay = 0,
  burnedSupplyIrl = "9,867,860",
  treasuryFeesEth = "0.000",
  programmableFeesEth = "0.000",
  distributedRewardsEth = "0.621",
  lockedUnclaimedEth = "0.256",
  launchTimestamp = 1792027210,
  onOpenQuickMint
}) {
  const [timeLeftHour, setTimeLeftHour] = useState({ minutes: 0, seconds: 0 });
  const [timeLeftDay, setTimeLeftDay] = useState({ hours: 0, minutes: 0, seconds: 0 });
  const [timeLeftSunday, setTimeLeftSunday] = useState({ days: 0, hours: 0, minutes: 0 });
  const [isFirstHourLottery, setIsFirstHourLottery] = useState(false);
  const [simTickets, setSimTickets] = useState(3);
  const [activeMetricDetail, setActiveMetricDetail] = useState(null);

  useEffect(() => {
    function updateCountdowns() {
      const now = new Date();
      const nowSec = Math.floor(now.getTime() / 1000);
      
      // Hourly countdown (end of current hour)
      const endOfHour = new Date(now);
      endOfHour.setMinutes(59, 59, 999);
      const diffHour = Math.max(0, Math.floor((endOfHour - now) / 1000));
      setTimeLeftHour({
        minutes: Math.floor(diffHour / 60),
        seconds: diffHour % 60,
      });

      // First Launch Lottery is 1 hour from launchTimestamp; afterwards standard 24h UTC day
      const firstHourEndSec = (Number(launchTimestamp) || 1792027210) + 3600;
      if (nowSec < firstHourEndSec) {
        setIsFirstHourLottery(true);
        const diffFirst = Math.max(0, firstHourEndSec - nowSec);
        setTimeLeftDay({
          hours: Math.floor(diffFirst / 3600),
          minutes: Math.floor((diffFirst % 3600) / 60),
          seconds: diffFirst % 60,
        });
      } else {
        setIsFirstHourLottery(false);
        const endOfDay = new Date(now);
        endOfDay.setUTCHours(23, 59, 59, 999);
        const diffDay = Math.max(0, Math.floor((endOfDay - now) / 1000));
        setTimeLeftDay({
          hours: Math.floor(diffDay / 3600),
          minutes: Math.floor((diffDay % 3600) / 60),
          seconds: diffDay % 60,
        });
      }

      // Sunday countdown (Next Sunday 23:59:59 UTC)
      const dayOfWeek = now.getUTCDay();
      const daysUntilSunday = (7 - dayOfWeek) % 7;
      const nextSunday = new Date(now);
      nextSunday.setUTCDate(now.getUTCDate() + (daysUntilSunday === 0 && now.getUTCHours() >= 23 ? 7 : daysUntilSunday));
      nextSunday.setUTCHours(23, 59, 59, 999);
      const diffSunday = Math.max(0, Math.floor((nextSunday - now) / 1000));

      setTimeLeftSunday({
        days: Math.floor(diffSunday / 86400),
        hours: Math.floor((diffSunday % 86400) / 3600),
        minutes: Math.floor((diffSunday % 3600) / 60),
      });
    }

    updateCountdowns();
    const interval = setInterval(updateCountdowns, 1000);
    return () => clearInterval(interval);
  }, [launchTimestamp]);

  const format2 = (n) => String(n).padStart(2, '0');

  // 60 FPS Inertia Animated Numbers
  const animSundayEth = useInertiaNumber(sundayPotEth, 3, false);
  const animDailyEth = useInertiaNumber(lotteryPotEth, 3, false);
  const animHourlyEth = useInertiaNumber(hourlyPotEth, 3, false);
  const animDistributedEth = useInertiaNumber(distributedRewardsEth, 3, false);
  const animBurnedIrl = useInertiaNumber(burnedSupplyIrl, 0, true);
  const animTreasuryEth = useInertiaNumber(treasuryFeesEth, 3, false);
  const animProgrammableEth = useInertiaNumber(programmableFeesEth, 3, false);

  // Live Simulated Win Probability against active Daily & Sunday Tickets
  const activeDailyCount = Math.max(0, Number(dailyTicketsInPlay) || 0);
  const activeSundayCount = Math.max(1, Number(sundayTicketsInPlay) || 177);
  const simDailyWinOdds = ((simTickets / (activeDailyCount + simTickets)) * 100).toFixed(1);
  const simSundayWinOdds = ((simTickets / (activeSundayCount + simTickets)) * 100).toFixed(1);
  const simRequiredEth = (simTickets * 0.10).toFixed(2);
  const oneTicketDailyOdds = ((1 / (activeDailyCount + 1)) * 100).toFixed(1);

  return (
    <section className="sanctuary-section spatial-bento-sanctuary">
      {/* Asymmetrical Bento Grid: Dominant Hero Sunday Mega-Jackpot (Span 7 Cols / 2 Rows) + Daily & Hourly Stacked Right */}
      <div className="sanctuary-grid sanctuary-bento-asymmetric">
        {/* 1. SUNDAY MEGA-JACKPOT — DOMINANT BENTO HERO MONUMENT + LIVE OPENVRF CANVAS */}
        <div className="pot-monument mega-weekend featured bento-hero-pot">
          <div className="pot-aurora-glow gold" aria-hidden="true"></div>
          <div className="pot-live-stage">
            <div className="pot-header">
              <div className="pot-title-group">
                <span className="pot-kicker-tag">PRIMARY PROTOCOL JACKPOT • OPENVRF QUANTUM ENGINE</span>
                <span className="pot-label">Sunday <em>Mega-Jackpot</em></span>
              </div>
              <div className="pot-timer-pill mega">
                <TrophyIcon size={15} />
                <span>{`${timeLeftSunday.days}d ${format2(timeLeftSunday.hours)}h ${format2(timeLeftSunday.minutes)}m`}</span>
              </div>
            </div>

            {/* Hero Center Stage: Massive Space Grotesk Number + Live 60FPS OpenVRF Canvas Ring */}
            <div className="hero-quantum-main-row">
              <div className="hero-quantum-left">
                <div className="pot-value-container hero-value-stage">
                  <span className="pot-amount mega">{animSundayEth}</span>
                  <span className="pot-currency mega">ETH</span>
                </div>
                <div className="hero-tickets-status-line">
                  <div className="pot-tickets-pill mega">
                    <TicketIcon size={16} />
                    <span><strong>{sundayTicketsInPlay}</strong> {sundayTicketsInPlay === 1 ? 'ticket' : 'tickets'} in play</span>
                  </div>
                  <span className="hero-meta-chip">1.25% Swap Tax Inflow</span>
                </div>
              </div>

              <OpenVrfQuantumCanvas
                sundayTickets={activeSundayCount}
                simulatedTickets={simTickets}
                sundayOddsPct={simSundayWinOdds}
                dailyOddsPct={simDailyWinOdds}
              />
            </div>

            {/* Interactive +EV Simulator & Instant Quick-Mint Bar */}
            <div className="pot-hero-simulator-bar">
              <div className="sim-presets-group">
                <span className="sim-bar-label">SIMULATE ODDS:</span>
                {[1, 3, 6].map((cnt) => (
                  <button
                    key={cnt}
                    type="button"
                    onClick={() => setSimTickets(cnt)}
                    className={`sim-preset-btn ${simTickets === cnt ? 'active' : ''}`}
                  >
                    +{cnt} Ticket{cnt > 1 ? 's' : ''}
                  </button>
                ))}
              </div>

              <button
                type="button"
                onClick={() => onOpenQuickMint && onOpenQuickMint(simTickets)}
                className="btn-hero-quick-mint"
              >
                <ZapIcon size={15} />
                <span>Quick-Mint +{simTickets} ({simSundayWinOdds}% Sun • {simDailyWinOdds}% Tonight)</span>
              </button>
            </div>
          </div>

          <div className="pot-mechanic-note salon-spec-drawer">
            <p>Epoch-isolated weekly draw (<code>weeklyPotByWeek[weekId]</code>) across all Monday–Sunday tickets (42–70 weekly cap).</p>
          </div>
        </div>

        {/* 2. DAILY 24H JACKPOT — UPPER RIGHT BENTO TILE (Span 5 cols, Row 1) */}
        <div className="pot-monument bento-side-pot">
          <div className="pot-aurora-glow bronze" aria-hidden="true"></div>
          <div className="pot-live-stage">
            <div className="pot-header">
              <div className="pot-title-group">
                <span className="pot-kicker-tag">24H EPOCH POOL • 00:00 UTC</span>
                <span className="pot-label">
                  {isFirstHourLottery ? <>Launch 1h <em>Jackpot</em></> : <>Daily 24h <em>Jackpot</em></>}
                </span>
              </div>
              <div className="pot-timer-pill gold">
                <SparklesIcon size={14} />
                <span>{`${format2(timeLeftDay.hours)}h ${format2(timeLeftDay.minutes)}m ${format2(timeLeftDay.seconds)}s`}</span>
              </div>
            </div>

            <div className="pot-value-container">
              <span className="pot-amount gold">{animDailyEth}</span>
              <span className="pot-currency gold">ETH</span>
            </div>

            <div className="pot-side-interactive-footer">
              <div className="pot-tickets-pill gold">
                <TicketIcon size={15} />
                <span><strong>{dailyTicketsInPlay}</strong> {dailyTicketsInPlay === 1 ? 'ticket' : 'tickets'} in play</span>
              </div>
              <button
                type="button"
                onClick={() => onOpenQuickMint && onOpenQuickMint(1)}
                className="side-pot-action-link"
              >
                <span>+1 Ticket = {oneTicketDailyOdds}% Tonight →</span>
              </button>
            </div>
          </div>

          <div className="pot-mechanic-note salon-spec-drawer">
            <p>Epoch-isolated OpenVRF draw (<code>dailyPotByDay[dayId]</code>) strictly for active-window tickets.</p>
          </div>
        </div>

        {/* 3. HOURLY REDISTRIBUTION — LOWER RIGHT BENTO TILE (Span 5 cols, Row 2) */}
        <div className="pot-monument bento-side-pot">
          <div className="pot-aurora-glow" aria-hidden="true"></div>
          <div className="pot-live-stage">
            <div className="pot-header">
              <div className="pot-title-group">
                <span className="pot-kicker-tag">60M VOLUME FLYWHEEL</span>
                <span className="pot-label">Hourly <em>Redistribution</em></span>
              </div>
              <div className="pot-timer-pill">
                <ClockIcon size={14} />
                <span>{`${format2(timeLeftHour.minutes)}m ${format2(timeLeftHour.seconds)}s`}</span>
              </div>
            </div>

            <div className="pot-value-container">
              <span className="pot-amount">{animHourlyEth}</span>
              <span className="pot-currency">ETH</span>
            </div>

            {/* Live Visual Distribution Bar (35% Top 10 • 35% Cashback • 30% Real Yield) */}
            <div className="hourly-split-bar-wrap">
              <div className="hourly-split-segments">
                <span className="split-seg seg-top10" style={{ width: '35%' }} title="35% Top 10 Traders" />
                <span className="split-seg seg-cashback" style={{ width: '35%' }} title="35% Instant Swap Cashback" />
                <span className="split-seg seg-yield" style={{ width: '30%' }} title="30% Staker Real Yield" />
              </div>
              <div className="hourly-split-legend">
                <span>35% Top 10</span>
                <span>35% Cashback</span>
                <span>30% Real Yield</span>
              </div>
            </div>
          </div>

          <div className="pot-mechanic-note salon-spec-drawer">
            <p>35% Top 10 traders (+50% staker boost) • 35% hourly cashback • 30% ETH Real Yield for [0.1%–2.0%] $IRL stakers.</p>
          </div>
        </div>
      </div>

      {/* LIVE ANIMATED 4.0% UNISWAP V4 HOOK WEALTH FLOW CIRCUIT */}
      <div className="quantum-flow-circuit" aria-hidden="true">
        <div className="circuit-hub-pill">
          <span className="circuit-pulse-dot" />
          <span>LIVE V4 HOOK STREAM • 4.0% SWAP TAX ROUTER (1.25% POTS / 1.25% HOURLY / 1.20% PROTOCOL+BURN / 0.30% PROG)</span>
        </div>
        <div className="circuit-rails-track">
          <div className="circuit-energy-packet packet-1" />
          <div className="circuit-energy-packet packet-2" />
          <div className="circuit-energy-packet packet-3" />
        </div>
      </div>

      {/* Unified Horizontal Glass Telemetry Ribbon (Divided by 1px Vertical Metallic Hairlines) */}
      <div className="sanctuary-metrics-grid telemetry-unified-ribbon">
        {/* Metric 1: Total Rewards Distributed to Traders */}
        <div
          className={`metric-monument ribbon-cell rewards-paid ${activeMetricDetail === 0 ? 'expanded' : ''}`}
          onClick={() => setActiveMetricDetail(activeMetricDetail === 0 ? null : 0)}
        >
          <div className="metric-header">
            <div className="metric-icon-title">
              <div className="metric-icon-wrap rewards-paid">
                <TrophyIcon size={16} />
              </div>
              <span className="metric-label">Paid to Real Traders</span>
            </div>
            <span className="metric-badge rewards-paid">Direct &amp; 24h Queue</span>
          </div>

          <div className="metric-value-row">
            <span className="metric-amount rewards-paid">{animDistributedEth}</span>
            <span className="metric-unit">ETH</span>
          </div>

          <div className="metric-live-sparkbar">
            <div className="sparkbar-fill gold" style={{ width: '78%' }} />
          </div>

          <div className="metric-subnote">
            💸 Total ETH rewards distributed to traders &amp; active swappers: direct wallet cashback, Top 10 hourly distributions, and Keeper router sweeps queued for human redistribution.
          </div>
        </div>

        {/* Metric 2: Live Burned Supply & Unclaimed Locked */}
        <div
          className={`metric-monument ribbon-cell flame ${activeMetricDetail === 1 ? 'expanded' : ''}`}
          onClick={() => setActiveMetricDetail(activeMetricDetail === 1 ? null : 1)}
        >
          <div className="metric-header">
            <div className="metric-icon-title">
              <div className="metric-icon-wrap flame">
                <FlameIcon size={16} />
              </div>
              <span className="metric-label">Deflation &amp; Burn</span>
            </div>
            <span className="metric-badge flame">+{lockedUnclaimedEth} ETH Locked</span>
          </div>

          <div className="metric-value-row">
            <span className="metric-amount flame">{animBurnedIrl}</span>
            <span className="metric-unit">$IRL</span>
          </div>

          <div className="metric-live-sparkbar">
            <div className="sparkbar-fill bronze" style={{ width: '64%' }} />
          </div>

          <div className="metric-subnote">
            🔥 {animBurnedIrl} $IRL burned to <code>0xdead</code> via hourly V4 buybacks + <strong style={{ color: 'var(--color-gold-light)' }}>{lockedUnclaimedEth} ETH</strong> permanently locked in Hook unclaimed rewards.
          </div>
        </div>

        {/* Metric 3: Fees Paid to Treasury */}
        <div
          className={`metric-monument ribbon-cell treasury ${activeMetricDetail === 2 ? 'expanded' : ''}`}
          onClick={() => setActiveMetricDetail(activeMetricDetail === 2 ? null : 2)}
        >
          <div className="metric-header">
            <div className="metric-icon-title">
              <div className="metric-icon-wrap treasury">
                <VaultIcon size={16} />
              </div>
              <span className="metric-label">Treasury &amp; Operations</span>
            </div>
            <span className="metric-badge">1.00% / swap</span>
          </div>

          <div className="metric-value-row">
            <span className="metric-amount">{animTreasuryEth}</span>
            <span className="metric-unit">ETH</span>
          </div>

          <div className="metric-live-sparkbar">
            <div className="sparkbar-fill emerald" style={{ width: '90%' }} />
          </div>

          <div className="metric-subnote">
            🏛️ 90% of supply permanently locked forever + 10% conditional marketing LP inside <code>IRLMarketingVault</code> (mathematical anti-rug bounds) &amp; Keepers/marketing reserves (1.00% Standard).
          </div>
        </div>

        {/* Metric 4: Fees Paid to Programmable */}
        <div
          className={`metric-monument ribbon-cell programmable ${activeMetricDetail === 3 ? 'expanded' : ''}`}
          onClick={() => setActiveMetricDetail(activeMetricDetail === 3 ? null : 3)}
        >
          <div className="metric-header">
            <div className="metric-icon-title">
              <div className="metric-icon-wrap programmable">
                <ZapIcon size={16} />
              </div>
              <span className="metric-label">Programmable Fees</span>
            </div>
            <span className="metric-badge">0.30% Immutable</span>
          </div>

          <div className="metric-value-row">
            <span className="metric-amount">{animProgrammableEth}</span>
            <span className="metric-unit">ETH</span>
          </div>

          <div className="metric-live-sparkbar">
            <div className="sparkbar-fill gold" style={{ width: '45%' }} />
          </div>

          <div className="metric-subnote">
            ⚡ Immutable 0.30% (<code>30 bps</code>) enforced once per buy, sell, and internal buyback directly to <code>0xD885...79da</code> with pull-fallback protection.
          </div>
        </div>
      </div>
    </section>
  );
}

