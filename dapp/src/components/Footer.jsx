import React, { useState } from 'react';
import { ExternalLinkIcon, ShieldCheckIcon, CopyIcon, CheckIcon, XIcon, TelegramIcon } from './Icons';
import { TOKEN_CA, ROBINHOOD_CHAIN } from '../constants/contracts';

export default function Footer() {
  const [copied, setCopied] = useState(false);
  const isPreLaunch = !TOKEN_CA || TOKEN_CA === '';
  const shortCA = isPreLaunch ? '0x181... (Pending)' : `${TOKEN_CA.substring(0, 6)}...${TOKEN_CA.substring(TOKEN_CA.length - 4)}`;

  const copyCA = () => {
    if (isPreLaunch) {
      navigator.clipboard.writeText('0x181... (Internet Robinhood Lottery - Official Contract Deployment Scheduled on Robinhood Chain)');
    } else {
      navigator.clipboard.writeText(TOKEN_CA);
    }
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <footer className="footer-section">
      <div className="footer-inner">
        <div className="footer-summary-col">
          <div className="footer-brand-title">INTERNET ROBINHOOD <em>LOTTERY</em> ($IRL)</div>
          <p className="footer-brand-desc">
            Systematic volume redistribution protocol powered by Uniswap V4 Hooks and provably fair OpenVRF lottery on Robinhood Chain.
          </p>

          {/* Relocated Contract Address Pill & Social Links */}
          <div className="footer-pills-bar">
            <div className="header-ca-container footer-ca-pill" title="Official $IRL Contract Address">
              <div className="ca-badge-label">
                <span className={`ca-dot ${isPreLaunch ? 'warning' : ''}`}></span>
                <span>$IRL CA</span>
              </div>
              <button onClick={copyCA} className="ca-copy-btn" title="Click to copy contract address">
                <span className="ca-address-text">{shortCA}</span>
                {copied ? (
                  <span className="ca-copied-feedback">
                    <CheckIcon size={13} color="#E6C2A5" />
                    <span>Copied</span>
                  </span>
                ) : (
                  <CopyIcon size={13} color="#E6C2A5" />
                )}
              </button>
              <a
                href={isPreLaunch ? `${ROBINHOOD_CHAIN.blockExplorers.default.url}` : `${ROBINHOOD_CHAIN.blockExplorers.default.url}/token/${TOKEN_CA}`}
                target="_blank"
                rel="noopener noreferrer"
                className="ca-explorer-link"
                title="Inspect token contract on Robinhood Explorer"
              >
                <ExternalLinkIcon size={13} color="#A89F91" />
              </a>
            </div>

            <div className="header-social-pills footer-social-pills">
              <a
                href="https://x.com/IRL_Protocol"
                target="_blank"
                rel="noopener noreferrer"
                className="social-btn-x"
                title="Official 𝕏 (@IRL_Protocol)"
              >
                <XIcon size={13} color="#EAEAEA" />
                <span>@IRL_Protocol</span>
              </a>
              <a
                href="https://t.me/InternetRobinhoodLottery"
                target="_blank"
                rel="noopener noreferrer"
                className="social-btn-tg"
                title="Official Telegram Community"
              >
                <TelegramIcon size={13} color="#E6C2A5" />
                <span>Telegram</span>
              </a>
            </div>
          </div>

          <div className="security-guarantee-pill">
            <ShieldCheckIcon size={14} color="var(--color-gold)" />
            <span>100% Transparent Single-Sided LP Vault • Zero Rug-Pull Risk</span>
          </div>
        </div>

        <div className="footer-links-col">
          <span className="footer-links-title">Resources &amp; Verification</span>
          <div className="footer-links-list">
            <a href="https://x.com/IRL_Protocol" target="_blank" rel="noopener noreferrer" className="f-link">
              <span>Official 𝕏 (@IRL_Protocol)</span>
              <ExternalLinkIcon size={12} />
            </a>
            <a href="https://t.me/InternetRobinhoodLottery" target="_blank" rel="noopener noreferrer" className="f-link">
              <span>Official Telegram Community</span>
              <ExternalLinkIcon size={12} />
            </a>
            <a href="https://robin.etherscan.io" target="_blank" rel="noopener noreferrer" className="f-link">
              <span>Robinhood Etherscan</span>
              <ExternalLinkIcon size={12} />
            </a>
            <a href="https://dexscreener.com" target="_blank" rel="noopener noreferrer" className="f-link">
              <span>DexScreener Live Chart</span>
              <ExternalLinkIcon size={12} />
            </a>
            <a href="https://github.com/math-crypt/lottery-robinhood" target="_blank" rel="noopener noreferrer" className="f-link">
              <span>GitHub Verified Repository</span>
              <ExternalLinkIcon size={12} />
            </a>
          </div>
        </div>
      </div>

      <div className="footer-bottom-line">
        <span>© 2026 Internet Robinhood Lottery. Deployed on Robinhood Chain (Arbitrum L2).</span>
        <span>“Steal from the whales. Give back to the community.”</span>
      </div>
    </footer>
  );
}

