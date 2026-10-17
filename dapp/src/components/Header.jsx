import React from 'react';
import { BowIcon, WalletIcon, ChartIcon, BookOpenIcon, TrophyIcon, TicketIcon } from './Icons';
import { ROBINHOOD_CHAIN } from '../constants/contracts';

export default function Header({ 
  account, 
  isConnecting, 
  onConnect, 
  onDisconnect, 
  chainId, 
  onSwitchNetwork,
  activeTab = 'dashboard',
  onSelectTab
}) {
  const isWrongNetwork = account && chainId !== ROBINHOOD_CHAIN.id;

  return (
    <header className="header header-consolidated">
      <div className="header-top-row header-single-bar">
        {/* LEFT: Brand Logo & Title */}
        <div className="header-brand" onClick={() => onSelectTab && onSelectTab('dashboard')} style={{ cursor: 'pointer' }}>
          <div className="brand-logo-ring">
            <div className="logo-aurora-halo" aria-hidden="true"></div>
            <img src="/logo_4.jpg" onError={(e) => { e.currentTarget.src = '/logo_lounge_2.png'; }} alt="IRL Logo" className="brand-logo-img" />
          </div>
          <div className="brand-text">
            <div className="brand-title-row">
              <span className="brand-title">INTERNET ROBINHOOD LOTTERY</span>
            </div>
            <span className="brand-sub">Uniswap V4 Hook • OpenVRF Protocol</span>
          </div>
        </div>

        {/* CENTER: 5 Navigation Tabs Merged Directly into Main Header Bar */}
        <nav className="header-nav-tabs header-nav-inline" aria-label="Primary Navigation">
          <button 
            onClick={() => onSelectTab('dashboard')} 
            className={`nav-tab-btn ${activeTab === 'dashboard' ? 'active' : ''}`}
          >
            <TrophyIcon size={15} />
            <span>Dashboard &amp; Pots</span>
          </button>
          <button 
            onClick={() => onSelectTab('trade')} 
            className={`nav-tab-btn ${activeTab === 'trade' ? 'active' : ''}`}
          >
            <ChartIcon size={15} />
            <span>Trade</span>
            <span className="nav-tag-badge">4% Tax</span>
          </button>
          <button 
            onClick={() => onSelectTab('marketplace')} 
            className={`nav-tab-btn ${activeTab === 'marketplace' ? 'active' : ''}`}
          >
            <TicketIcon size={15} />
            <span>Marketplace</span>
            <span className="nav-tag-badge gold">P2P</span>
          </button>
          <button 
            onClick={() => onSelectTab('referral')} 
            className={`nav-tab-btn ${activeTab === 'referral' ? 'active' : ''}`}
          >
            <BowIcon size={15} />
            <span>Referral</span>
            <span className="nav-tag-badge">+10% Boost</span>
          </button>
          <button 
            onClick={() => onSelectTab('whitepaper')} 
            className={`nav-tab-btn ${activeTab === 'whitepaper' ? 'active' : ''}`}
          >
            <BookOpenIcon size={15} />
            <span>Whitepaper</span>
          </button>
        </nav>

        {/* RIGHT: Network Status + Connect Wallet */}
        <div className="header-actions">
          <div className="network-badge">
            <span className="pulse-dot"></span>
            <span>Robinhood L2</span>
          </div>

          <div className="header-wallet-wrap">
            {isWrongNetwork ? (
              <button onClick={onSwitchNetwork} className="btn-switch-network">
                Switch Network
              </button>
            ) : account ? (
              <div className="wallet-connected-pill">
                <span className="wallet-address">
                  {account.substring(0, 6)}...{account.substring(account.length - 4)}
                </span>
                <button onClick={onDisconnect} className="btn-disconnect" title="Disconnect wallet">
                  ×
                </button>
              </div>
            ) : (
              <button onClick={onConnect} disabled={isConnecting} className="btn-connect-wallet">
                <WalletIcon size={16} />
                <span>{isConnecting ? 'Connecting...' : 'Connect Wallet'}</span>
              </button>
            )}
          </div>
        </div>
      </div>
    </header>
  );
}

