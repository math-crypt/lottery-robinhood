import React, { useState, useEffect, useCallback, useMemo } from 'react';
import { ethers } from 'ethers';
import { TicketIcon, SparklesIcon, ShieldCheckIcon, ClockIcon, WalletIcon } from './Icons';
import {
  CONTRACT_ADDRESSES,
  ROBINHOOD_CHAIN,
  TICKETS_ABI,
  HOOK_ABI,
} from '../constants/contracts';

const RPC_URL = 'https://rpc.mainnet.chain.robinhood.com';
const LAUNCH_BLOCK = '0x54af900'; // Block ~88800000 (launch epoch)

const ticketIface = new ethers.Interface(TICKETS_ABI);
const hookIface = new ethers.Interface(HOOK_ABI);

async function rpcCall(method, params) {
  try {
    const res = await fetch(RPC_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ jsonrpc: '2.0', id: Date.now(), method, params }),
    });
    if (!res.ok) throw new Error(`RPC HTTP error: ${res.status}`);
    const json = await res.json();
    if (json.error) throw new Error(json.error.message || 'RPC Call Error');
    return json.result;
  } catch (err) {
    console.warn(`rpcCall (${method}) warning:`, err.message);
    throw err;
  }
}

async function waitForTxReceipt(txHash, maxAttempts = 30) {
  for (let i = 0; i < maxAttempts; i++) {
    try {
      const rec = await rpcCall('eth_getTransactionReceipt', [txHash]);
      if (rec && rec.blockNumber) return rec;
    } catch (_) {}
    await new Promise((r) => setTimeout(r, 1500));
  }
  return null;
}

export default function Marketplace({ 
  account, 
  onConnect, 
  chainId,
  onSwitchNetwork,
  ticketsCount = 0, 
  dailyTicketsInPlay = 2,
  sundayTicketsInPlay = 177,
  userStakedIrl = "0",
  onBuyTicket, 
  onListTicket 
}) {
  const [activeFilter, setActiveFilter] = useState('all'); // 'all' | 'daily' | 'sunday' | 'my_listings' | 'my_tickets'
  const [isListingOpen, setIsListingOpen] = useState(false);
  const [listPrice, setListPrice] = useState('0.020');
  const [selectedTicketToList, setSelectedTicketToList] = useState('');
  const [customTicketId, setCustomTicketId] = useState('');
  const [purchaseToast, setPurchaseToast] = useState(null);
  const [isTransacting, setIsTransacting] = useState(false);
  const [actionStepText, setActionStepText] = useState('');
  const [isLoading, setIsLoading] = useState(true);

  // On-Chain State
  const [listings, setListings] = useState([]);
  const [userOwnedTickets, setUserOwnedTickets] = useState([]);
  const [dayRange, setDayRange] = useState({ start: 1, end: 1 });
  const [totalMinted, setTotalMinted] = useState(0);

  // Staking ratio calculus (20M $IRL = 2% max tier)
  const staked = parseFloat(userStakedIrl || 0);
  const maxTier = 20000000;
  const stakingRatio = Math.min(1, Math.max(0, isNaN(staked) ? 0 : staked / maxTier));

  // Daily ticket holding limit: 6 for non-staker, scaling linearly to 10 for 2% staker
  const maxDailyTickets = Math.floor(6 + stakingRatio * 4);
  // Weekly ticket holding limit: 42 (6×7) for non-staker, scaling up to 70 (10×7) for 2% staker
  const maxWeeklyTickets = maxDailyTickets * 7;

  const showToast = useCallback((msg, ms = 5000) => {
    setPurchaseToast(msg);
    setTimeout(() => setPurchaseToast(null), ms);
  }, []);

  // Compute 2% Marketplace Lottery Tax breakdown
  function computeTaxBreakdown(priceStr, isDailyEligible) {
    const p = parseFloat(priceStr);
    const price = !isNaN(p) && p > 0 ? p : 0;
    const totalTax = price * 0.02; // 2.0% Marketplace Lottery Tax
    const sellerNet = price - totalTax; // 98.0% to Seller
    const dailyTax = isDailyEligible ? totalTax / 2 : 0; // 1.0% Daily if Daily+Weekly, 0% if Weekly-only
    const sundayTax = isDailyEligible ? totalTax - dailyTax : totalTax; // 1.0% Sunday if Daily+Weekly, 2.0% if Weekly-only
    return {
      price,
      totalTax: isNaN(totalTax) ? 0 : totalTax,
      sellerNet: isNaN(sellerNet) ? 0 : sellerNet,
      dailyTax: isNaN(dailyTax) ? 0 : dailyTax,
      sundayTax: isNaN(sundayTax) ? 0 : sundayTax
    };
  }

  // Refresh On-Chain Marketplace & Ticket State
  const fetchMarketplaceState = useCallback(async () => {
    try {
      const curDay = Math.floor(Date.now() / 1000 / 86400);

      // 1. Fetch Day ticket boundaries & total minted
      const startCall = hookIface.encodeFunctionData('dayStartTicketId', [curDay]);
      const endCall = hookIface.encodeFunctionData('dayEndTicketId', [curDay]);
      const totalCall = ticketIface.encodeFunctionData('totalTicketsMinted');

      const [startHex, endHex, totalHex] = await Promise.all([
        rpcCall('eth_call', [{ to: CONTRACT_ADDRESSES.HOOK, data: startCall }, 'latest']).catch(() => '0x0'),
        rpcCall('eth_call', [{ to: CONTRACT_ADDRESSES.HOOK, data: endCall }, 'latest']).catch(() => '0x0'),
        rpcCall('eth_call', [{ to: CONTRACT_ADDRESSES.TICKETS, data: totalCall }, 'latest']).catch(() => '0x0'),
      ]);

      const startId = startHex && startHex !== '0x' ? Number(hookIface.decodeFunctionResult('dayStartTicketId', startHex)[0]) : 1;
      const endId = endHex && endHex !== '0x' ? Number(hookIface.decodeFunctionResult('dayEndTicketId', endHex)[0]) : 1;
      const totalCount = totalHex && totalHex !== '0x' ? Number(ticketIface.decodeFunctionResult('totalTicketsMinted', totalHex)[0]) : 0;

      setDayRange({ start: startId, end: endId });
      setTotalMinted(totalCount);

      // 2. Fetch all TicketListed events to discover active marketplace listings
      const listedTopic = ethers.id('TicketListed(uint256,address,uint256)');
      const listedLogs = await rpcCall('eth_getLogs', [{
        address: CONTRACT_ADDRESSES.TICKETS,
        topics: [listedTopic],
        fromBlock: LAUNCH_BLOCK,
        toBlock: 'latest',
      }]).catch(() => []);

      const candidateListedIds = [...new Set((listedLogs || []).map(log => Number(BigInt(log.topics[1]))))];

      const activeListings = [];
      for (const tid of candidateListedIds) {
        try {
          const listCall = ticketIface.encodeFunctionData('listings', [tid]);
          const listHex = await rpcCall('eth_call', [{ to: CONTRACT_ADDRESSES.TICKETS, data: listCall }, 'latest']);
          const [seller, priceWei, active] = ticketIface.decodeFunctionResult('listings', listHex);

          if (active) {
            const ownerCall = ticketIface.encodeFunctionData('ownerOf', [tid]);
            const ownerHex = await rpcCall('eth_call', [{ to: CONTRACT_ADDRESSES.TICKETS, data: ownerCall }, 'latest']);
            const [currentOwner] = ticketIface.decodeFunctionResult('ownerOf', ownerHex);

            if (currentOwner.toLowerCase() === seller.toLowerCase()) {
              const priceEth = ethers.formatEther(priceWei);
              const isDaily = startId > 0 && tid >= startId && tid <= endId;
              activeListings.push({
                id: tid,
                seller: `${seller.slice(0, 6)}...${seller.slice(-4)}`,
                rawSeller: seller,
                priceWei,
                priceEth,
                priceUsd: `$${(parseFloat(priceEth) * 2450).toFixed(2)}`,
                mintDay: isDaily ? 'Daily + Sunday' : 'Sunday Mega Only',
                isDailyEligible: isDaily,
                isSundayEligible: true,
                rarityBonus: isDaily ? 'Daily + Sunday Mega Eligible' : 'Sunday Mega-Jackpot Only',
                verified: true,
              });
            }
          }
        } catch (_) {}
      }
      setListings(activeListings);

      // 3. Fetch tickets owned by connected account
      if (account) {
        const transferTopic = ethers.id('Transfer(address,address,uint256)');
        const toTopic = ethers.zeroPadValue(account, 32);
        const transferLogs = await rpcCall('eth_getLogs', [{
          address: CONTRACT_ADDRESSES.TICKETS,
          topics: [transferTopic, null, toTopic],
          fromBlock: LAUNCH_BLOCK,
          toBlock: 'latest',
        }]).catch(() => []);

        const candidateTokenIds = [...new Set((transferLogs || []).map(l => Number(BigInt(l.topics[3]))))];
        const owned = [];

        for (const tid of candidateTokenIds) {
          try {
            const oCall = ticketIface.encodeFunctionData('ownerOf', [tid]);
            const oHex = await rpcCall('eth_call', [{ to: CONTRACT_ADDRESSES.TICKETS, data: oCall }, 'latest']);
            const [o] = ticketIface.decodeFunctionResult('ownerOf', oHex);
            if (o.toLowerCase() === account.toLowerCase()) {
              owned.push(tid);
            }
          } catch (_) {}
        }
        owned.sort((a, b) => a - b);
        setUserOwnedTickets(owned);

        // Safely set default selected ticket if needed without causing dependency loop
        setSelectedTicketToList(prev => {
          if (owned.length > 0 && (!prev || !owned.includes(Number(prev)))) {
            return String(owned[0]);
          }
          return prev;
        });
      } else {
        setUserOwnedTickets([]);
      }
    } catch (err) {
      console.error('Error fetching marketplace state:', err);
    } finally {
      setIsLoading(false);
    }
  }, [account]);

  useEffect(() => {
    fetchMarketplaceState();
    const interval = setInterval(fetchMarketplaceState, 12000);
    return () => clearInterval(interval);
  }, [fetchMarketplaceState]);

  // Create on-chain listing
  async function handleCreateListing(e) {
    if (e && e.preventDefault) e.preventDefault();
    if (!account) {
      if (onConnect) onConnect();
      return;
    }
    if (chainId !== ROBINHOOD_CHAIN.id && onSwitchNetwork) {
      await onSwitchNetwork();
      return;
    }
    if (typeof window === 'undefined' || !window.ethereum) {
      showToast('Web3 wallet provider not detected. Please connect MetaMask or Rabby.');
      return;
    }

    const resolvedId = customTicketId ? Number(customTicketId) : Number(selectedTicketToList);
    if (!resolvedId || isNaN(resolvedId) || resolvedId <= 0) {
      showToast('Please select or enter a valid ticket number.');
      return;
    }
    const numericPrice = parseFloat(listPrice);
    if (!numericPrice || isNaN(numericPrice) || numericPrice <= 0) {
      showToast('Please enter a valid positive asking price in ETH.');
      return;
    }

    setIsTransacting(true);
    setActionStepText('Confirm listing in your Web3 wallet...');
    try {
      const priceWei = ethers.parseEther(listPrice);
      const calldata = ticketIface.encodeFunctionData('listTicket', [resolvedId, priceWei]);

      const txHash = await window.ethereum.request({
        method: 'eth_sendTransaction',
        params: [{
          from: account,
          to: CONTRACT_ADDRESSES.TICKETS,
          data: calldata,
        }],
      });

      setActionStepText('Confirming listing on Robinhood Chain...');
      await waitForTxReceipt(txHash);

      setIsListingOpen(false);
      setCustomTicketId('');
      showToast(`Ticket #${resolvedId} listed on-chain for ${listPrice} ETH (98% net to you, 2% Lottery Tax on sale)!`);
      if (onListTicket) onListTicket();
      await fetchMarketplaceState();
    } catch (err) {
      showToast(err?.message || 'Listing transaction cancelled.');
    } finally {
      setIsTransacting(false);
      setActionStepText('');
    }
  }

  // Cancel on-chain listing
  async function handleCancelListing(tokenId) {
    if (!account) {
      if (onConnect) onConnect();
      return;
    }
    if (chainId !== ROBINHOOD_CHAIN.id && onSwitchNetwork) {
      await onSwitchNetwork();
      return;
    }
    if (typeof window === 'undefined' || !window.ethereum) {
      showToast('Web3 wallet provider not detected.');
      return;
    }

    setIsTransacting(true);
    setActionStepText(`Confirm cancellation of Ticket #${tokenId} in wallet...`);
    try {
      const calldata = ticketIface.encodeFunctionData('cancelListing', [tokenId]);

      const txHash = await window.ethereum.request({
        method: 'eth_sendTransaction',
        params: [{
          from: account,
          to: CONTRACT_ADDRESSES.TICKETS,
          data: calldata,
        }],
      });

      setActionStepText(`Confirming cancellation of Ticket #${tokenId} on-chain...`);
      await waitForTxReceipt(txHash);

      showToast(`Listing for Ticket #${tokenId} cancelled successfully!`);
      await fetchMarketplaceState();
    } catch (err) {
      showToast(err?.message || 'Cancellation transaction cancelled.');
    } finally {
      setIsTransacting(false);
      setActionStepText('');
    }
  }

  // Buy listed ticket on-chain
  async function handleBuy(listing) {
    if (!account) {
      if (onConnect) onConnect();
      return;
    }
    if (chainId !== ROBINHOOD_CHAIN.id && onSwitchNetwork) {
      await onSwitchNetwork();
      return;
    }
    if (typeof window === 'undefined' || !window.ethereum) {
      showToast('Web3 wallet provider not detected.');
      return;
    }
    if (account.toLowerCase() === listing.rawSeller.toLowerCase()) {
      showToast("You cannot buy your own listing. Use 'Cancel Listing' instead.");
      return;
    }

    const currentTCount = Number(ticketsCount) || 0;
    if (listing.isDailyEligible && currentTCount >= maxDailyTickets) {
      showToast(`Daily holding limit reached (${maxDailyTickets}/day). Non-stakers are capped at 6; stake up to 2% $IRL to unlock 10 daily tickets!`);
      return;
    }

    if (listing.isSundayEligible && currentTCount >= maxWeeklyTickets) {
      showToast(`Weekly holding limit reached (${maxWeeklyTickets}/week). Non-stakers are capped at 42 (6×7); stake up to 2% $IRL to unlock 70 weekly tickets (10×7)!`);
      return;
    }

    setIsTransacting(true);
    setActionStepText(`Confirm purchase of Ticket #${listing.id} for ${listing.priceEth} ETH in wallet...`);
    try {
      const calldata = ticketIface.encodeFunctionData('buyTicket', [listing.id]);

      const txHash = await window.ethereum.request({
        method: 'eth_sendTransaction',
        params: [{
          from: account,
          to: CONTRACT_ADDRESSES.TICKETS,
          value: '0x' + BigInt(listing.priceWei).toString(16),
          data: calldata,
        }],
      });

      setActionStepText(`Confirming purchase of Ticket #${listing.id} on Robinhood Chain...`);
      await waitForTxReceipt(txHash);

      const taxInfo = computeTaxBreakdown(listing.priceEth, listing.isDailyEligible);
      const taxMsg = listing.isDailyEligible
        ? `2% Tax (${taxInfo.totalTax.toFixed(4)} ETH) routed 50/50: +${taxInfo.dailyTax.toFixed(4)} ETH Daily Pot & +${taxInfo.sundayTax.toFixed(4)} ETH Sunday Pot!`
        : `2% Tax (${taxInfo.totalTax.toFixed(4)} ETH) routed 100% to Sunday Mega-Jackpot!`;

      showToast(`Ticket #${listing.id} purchased for ${listing.priceEth} ETH (98% to seller • ${taxMsg})`);
      if (onBuyTicket) onBuyTicket();
      await fetchMarketplaceState();
    } catch (err) {
      showToast(err?.message || 'Purchase transaction cancelled.');
    } finally {
      setIsTransacting(false);
      setActionStepText('');
    }
  }

  // Filter listings
  const filteredListings = useMemo(() => {
    return (listings || []).filter(item => {
      if (activeFilter === 'daily') return item.isDailyEligible;
      if (activeFilter === 'sunday') return !item.isDailyEligible && item.isSundayEligible;
      if (activeFilter === 'my_listings') {
        return account && item.rawSeller.toLowerCase() === account.toLowerCase();
      }
      return true;
    });
  }, [listings, activeFilter, account]);

  // Accurate live odds calculation synchronized with on-chain daily & Sunday pools
  const totalDailyEst = Math.max(1, Number(dailyTicketsInPlay) || (dayRange.end >= dayRange.start && dayRange.start > 0 ? dayRange.end - dayRange.start + 1 : 2));
  const totalWeeklyEst = Math.max(1, Number(sundayTicketsInPlay) || totalMinted || 177);
  const ownedCount = Math.max(0, Number(ticketsCount) || 0);
  const userDailyOdds = ownedCount > 0
    ? Math.min(100, (ownedCount / Math.max(ownedCount, totalDailyEst)) * 100).toFixed(1)
    : ((1 / (totalDailyEst + 1)) * 100).toFixed(1);
  const userSundayOdds = ownedCount > 0
    ? Math.min(100, (ownedCount / Math.max(ownedCount, totalWeeklyEst)) * 100).toFixed(1)
    : ((1 / (totalWeeklyEst + 1)) * 100).toFixed(1);

  // Floor price dynamically computed from active listings
  const floorPriceEth = useMemo(() => {
    if (!listings || listings.length === 0) return null;
    const validPrices = listings.map(l => parseFloat(l.priceEth)).filter(p => !isNaN(p) && p > 0);
    if (validPrices.length === 0) return null;
    return Math.min(...validPrices).toFixed(3);
  }, [listings]);

  // Group user's owned tickets into unlisted vs already listed
  const myActiveListingsMap = useMemo(() => {
    const m = new Map();
    if (!account || !listings) return m;
    listings.forEach(l => {
      if (l.rawSeller && l.rawSeller.toLowerCase() === account.toLowerCase()) {
        m.set(l.id, l);
      }
    });
    return m;
  }, [listings, account]);

  const unlistedOwnedTickets = useMemo(() => {
    if (!account || !userOwnedTickets) return [];
    return userOwnedTickets.filter(id => !myActiveListingsMap.has(id));
  }, [userOwnedTickets, myActiveListingsMap, account]);

  const listedOwnedTickets = useMemo(() => {
    if (!account || !userOwnedTickets) return [];
    return userOwnedTickets.filter(id => myActiveListingsMap.has(id));
  }, [userOwnedTickets, myActiveListingsMap, account]);

  const targetTicketId = customTicketId ? Number(customTicketId) : Number(selectedTicketToList);
  const selectedListingInfo = targetTicketId ? myActiveListingsMap.get(targetTicketId) : null;
  const isSelectedDaily = dayRange.start > 0 && targetTicketId >= dayRange.start && targetTicketId <= dayRange.end;
  const modalTaxPreview = computeTaxBreakdown(listPrice, isSelectedDaily);

  const [inspectedId, setInspectedId] = useState(1);
  const [podiumTilt, setPodiumTilt] = useState({ rx: 0, ry: 0, gx: 50, gy: 35 });

  const activeInspectedId = useMemo(() => {
    if (inspectedId) return inspectedId;
    if (listings && listings.length > 0) return listings[0].id;
    if (userOwnedTickets && userOwnedTickets.length > 0) return userOwnedTickets[0];
    return 1;
  }, [inspectedId, listings, userOwnedTickets]);

  const handlePodiumMove = (e) => {
    const rect = e.currentTarget.getBoundingClientRect();
    const nx = (e.clientX - rect.left) / rect.width - 0.5;
    const ny = (e.clientY - rect.top) / rect.height - 0.5;
    setPodiumTilt({
      rx: Number((-ny * 16).toFixed(2)),
      ry: Number((nx * 16).toFixed(2)),
      gx: Number((((e.clientX - rect.left) / rect.width) * 100).toFixed(1)),
      gy: Number((((e.clientY - rect.top) / rect.height) * 100).toFixed(1)),
    });
  };

  const handlePodiumLeave = () => {
    setPodiumTilt({ rx: 0, ry: 0, gx: 50, gy: 35 });
  };

  return (
    <div className="marketplace-container">
      {/* Toast Alert */}
      {purchaseToast && (
        <div className="market-toast-banner">
          <SparklesIcon size={16} color="var(--color-gold)" />
          <span>{purchaseToast}</span>
        </div>
      )}

      {/* Transaction Progress Banner */}
      {isTransacting && (
        <div className="market-toast-banner" style={{ background: 'rgba(140, 226, 170, 0.15)', borderColor: 'var(--color-mint)' }}>
          <ClockIcon size={16} color="var(--color-mint)" />
          <span style={{ color: 'var(--color-mint)', fontWeight: 600 }}>{actionStepText}</span>
        </div>
      )}

      {/* Interactive 3D Holographic Showcase & Live Exchange Telemetry */}
      <div className="market-hero-card market-3d-showcase-hero">
        <div className="market-hero-left">
          <div className="market-tag-pill">
            <ShieldCheckIcon size={14} color="var(--color-gold)" />
            <span>Protocol Validated • 2.0% Lottery Tax Active</span>
          </div>
          <h2 className="market-title">
            VIP Pass <span className="market-title-italic">P2P Exchange</span>
          </h2>
          <p className="market-live-subtitle">
            Interactive 3D ERC-721 Bearer Pass Vault • <strong>98% Net to Seller</strong> • <strong>2.0% Tax</strong> Routed Directly to Daily &amp; Sunday Jackpots.
          </p>
          <div className="salon-spec-drawer">
            <p className="market-desc">
              Buy, sell, and trade physical-grade ERC-721 VIP lottery passes directly on-chain via <code>IRLTicketNFT.sol</code>. Every secondary sale applies a <strong>2.0% Lottery Tax</strong> (<strong>98% to seller</strong>): <strong>Daily + Weekly tickets</strong> split the 2% tax <strong>50/50</strong> (1% Daily Pot + 1% Sunday Mega-Jackpot), while <strong>Weekly-Only tickets</strong> route <strong>100% of the 2% tax</strong> directly to the Sunday Mega-Jackpot! Holding caps (<strong>6–10 daily / 42–70 weekly</strong>) are strictly enforced on-chain in <code>_update</code>.
            </p>
          </div>

          <div className="market-stats-row">
            <div className="market-stat-box">
              <span className="m-stat-lbl">Floor Price</span>
              <span className="m-stat-val gold">{floorPriceEth ? `${floorPriceEth} ETH` : 'No Listings'}</span>
              <span className="m-stat-sub">{floorPriceEth ? `~$${(parseFloat(floorPriceEth) * 2450).toFixed(2)} USD • 2% Royalty` : 'List a Ticket'}</span>
            </div>
            <div className="market-stat-box">
              <span className="m-stat-lbl">Holding Quota</span>
              <span className="m-stat-val gold">{ownedCount} / {maxDailyTickets} Today</span>
              <span className="m-stat-sub">Max {maxWeeklyTickets} Weekly ({maxDailyTickets}×7)</span>
            </div>
            <div className="market-stat-box">
              <span className="m-stat-lbl">{ownedCount > 0 ? 'Your Live Odds' : '+1 Ticket Odds'}</span>
              <span className="m-stat-val mint">{userDailyOdds}% Tonight</span>
              <span className="m-stat-sub">{userSundayOdds}% on Sunday ({totalWeeklyEst} Pool)</span>
            </div>
          </div>
        </div>

        {/* Interactive 3D Holographic Certificate Inspector Podium */}
        <div
          className="vip-pass-3d-podium"
          onMouseMove={handlePodiumMove}
          onMouseLeave={handlePodiumLeave}
          title="Move cursor to inspect 3D Genesis VIP Raffle Pass"
        >
          <div
            className="vip-pass-3d-card"
            style={{
              transform: `perspective(950px) rotateX(${podiumTilt.rx}deg) rotateY(${podiumTilt.ry}deg)`,
            }}
          >
            <img
              src="/nft_ticket_4_clean.jpg"
              alt="3D Genesis VIP Pass Showcase"
              className="vip-pass-3d-img"
              style={{ width: '256px', height: '256px', objectFit: 'cover', display: 'block' }}
            />
            <span className="ticket-canvas-live-id">
              GENESIS #{String(activeInspectedId).padStart(4, '0')}
            </span>
            <div
              className="vip-pass-3d-glare"
              style={{
                background: `radial-gradient(circle at ${podiumTilt.gx}% ${podiumTilt.gy}%, rgba(255, 242, 226, 0.32) 0%, transparent 62%)`,
              }}
            />
          </div>
          <div className="vip-podium-caption">
            <span>3D HOLOGRAPHIC INSPECTOR • PASS #{String(activeInspectedId).padStart(4, '0')}</span>
          </div>
        </div>
      </div>

      {/* Action & Filter Toolbar */}
      <div className="market-toolbar">
        <div className="market-filter-pills">
          <button 
            onClick={() => setActiveFilter('all')} 
            className={`filter-pill ${activeFilter === 'all' ? 'active' : ''}`}
          >
            All Active ({listings.length})
          </button>
          <button 
            onClick={() => setActiveFilter('daily')} 
            className={`filter-pill ${activeFilter === 'daily' ? 'active' : ''}`}
          >
            Daily + Weekly ({listings.filter(l => l.isDailyEligible).length})
          </button>
          <button 
            onClick={() => setActiveFilter('sunday')} 
            className={`filter-pill ${activeFilter === 'sunday' ? 'active' : ''}`}
          >
            Weekly Only ({listings.filter(l => !l.isDailyEligible).length})
          </button>
          {account && (
            <button 
              onClick={() => setActiveFilter('my_listings')} 
              className={`filter-pill ${activeFilter === 'my_listings' ? 'active' : ''}`}
            >
              My Listings ({listings.filter(l => l.rawSeller.toLowerCase() === account.toLowerCase()).length})
            </button>
          )}
          {account && (
            <button 
              onClick={() => setActiveFilter('my_tickets')} 
              className={`filter-pill ${activeFilter === 'my_tickets' ? 'active' : ''}`}
            >
              My Tickets ({userOwnedTickets.length})
            </button>
          )}
        </div>

        <div className="market-actions-right">
          <button 
            onClick={() => {
              if (!account) {
                if (onConnect) onConnect();
              } else {
                if (unlistedOwnedTickets.length > 0) {
                  setSelectedTicketToList(String(unlistedOwnedTickets[0]));
                  setCustomTicketId('');
                } else if (listedOwnedTickets.length > 0) {
                  setSelectedTicketToList(String(listedOwnedTickets[0]));
                  setCustomTicketId('');
                  const ex = myActiveListingsMap.get(listedOwnedTickets[0]);
                  if (ex) setListPrice(ex.priceEth);
                }
                setIsListingOpen(true);
              }
            }}
            className="btn-list-ticket"
          >
            <TicketIcon size={16} />
            <span>
              {!account 
                ? 'Connect to List' 
                : unlistedOwnedTickets.length > 0 
                  ? `List a Ticket (${unlistedOwnedTickets.length} Available)` 
                  : `Manage Price (${userOwnedTickets.length} Listed)`}
            </span>
          </button>
        </div>
      </div>

      {/* Listing Modal */}
      {isListingOpen && (
        <div className="modal-backdrop" onClick={() => !isTransacting && setIsListingOpen(false)}>
          <div className="market-modal-box" onClick={e => e.stopPropagation()}>
            <div className="modal-head">
              <h3>{selectedListingInfo ? `Update Price for Ticket #${targetTicketId}` : 'List Ticket on P2P Marketplace'}</h3>
              <button 
                onClick={() => !isTransacting && setIsListingOpen(false)} 
                className="modal-close-btn"
                disabled={isTransacting}
              >
                ×
              </button>
            </div>
            <form onSubmit={handleCreateListing} className="modal-form">
              <label className="form-lbl">Select Ticket to List or Update</label>
              {unlistedOwnedTickets.length > 0 && (
                <div style={{ marginBottom: '12px' }}>
                  <span style={{ fontSize: '0.74rem', color: 'var(--color-mint)', fontWeight: 600, display: 'block', marginBottom: '6px' }}>
                    Available Tickets ({unlistedOwnedTickets.length} Not Yet Listed):
                  </span>
                  <div className="ticket-select-pills" style={{ display: 'flex', flexWrap: 'wrap', gap: '6px', maxHeight: '90px', overflowY: 'auto' }}>
                    {unlistedOwnedTickets.map(id => (
                      <button 
                        key={id} 
                        type="button"
                        onClick={() => {
                          setSelectedTicketToList(String(id));
                          setCustomTicketId('');
                        }}
                        className={`select-ticket-pill ${selectedTicketToList === String(id) && !customTicketId ? 'active' : ''}`}
                        disabled={isTransacting}
                      >
                        Pass #{id}
                      </button>
                    ))}
                  </div>
                </div>
              )}

              {listedOwnedTickets.length > 0 && (
                <div style={{ marginBottom: '12px' }}>
                  <span style={{ fontSize: '0.74rem', color: 'var(--color-gold)', fontWeight: 600, display: 'block', marginBottom: '6px' }}>
                    {unlistedOwnedTickets.length === 0 ? 'All Your Tickets Are Currently Listed:' : 'Already Listed (Click to Update Price):'}
                  </span>
                  <div className="ticket-select-pills" style={{ display: 'flex', flexWrap: 'wrap', gap: '6px', maxHeight: '90px', overflowY: 'auto' }}>
                    {listedOwnedTickets.map(id => {
                      const lInfo = myActiveListingsMap.get(id);
                      return (
                        <button 
                          key={id} 
                          type="button"
                          onClick={() => {
                            setSelectedTicketToList(String(id));
                            setCustomTicketId('');
                            if (lInfo) setListPrice(lInfo.priceEth);
                          }}
                          className={`select-ticket-pill ${selectedTicketToList === String(id) && !customTicketId ? 'active' : ''}`}
                          style={{ borderColor: 'rgba(230, 194, 165, 0.45)' }}
                          disabled={isTransacting}
                        >
                          Pass #{id} ({lInfo?.priceEth} ETH)
                        </button>
                      );
                    })}
                  </div>
                </div>
              )}

              {userOwnedTickets.length === 0 && (
                <div style={{ marginBottom: '10px' }}>
                  <p style={{ color: 'var(--color-text-dim)', fontSize: '0.82rem', marginBottom: '8px' }}>
                    Enter Ticket ID manually:
                  </p>
                  <input
                    type="number"
                    min="1"
                    placeholder="e.g. 70"
                    value={customTicketId}
                    onChange={e => {
                      setCustomTicketId(e.target.value);
                      setSelectedTicketToList('');
                    }}
                    className="stake-amount-input"
                    disabled={isTransacting}
                  />
                </div>
              )}

              {selectedListingInfo && (
                <div style={{
                  padding: '8px 12px',
                  borderRadius: '6px',
                  background: 'rgba(230, 194, 165, 0.12)',
                  border: '1px solid var(--color-gold)',
                  fontSize: '0.78rem',
                  color: '#EAEAEA',
                  marginBottom: '10px'
                }}>
                  <strong style={{ color: 'var(--color-gold)' }}>Notice:</strong> Ticket #{targetTicketId} is already listed for <strong>{selectedListingInfo.priceEth} ETH</strong>. Submitting will update its asking price on-chain.
                </div>
              )}

              {targetTicketId > 0 && (
                <div style={{
                  marginTop: '8px',
                  padding: '8px 12px',
                  borderRadius: '6px',
                  background: 'rgba(230, 194, 165, 0.08)',
                  border: '1px solid rgba(230, 194, 165, 0.25)',
                  fontSize: '0.78rem',
                  color: '#EAEAEA',
                  display: 'flex',
                  justifyContent: 'space-between'
                }}>
                  <span>Eligibility:</span>
                  <strong style={{ color: isSelectedDaily ? 'var(--color-mint)' : 'var(--color-gold)' }}>
                    {isSelectedDaily ? 'Daily Draw + Sunday Mega' : 'Sunday Mega-Jackpot Only'}
                  </strong>
                </div>
              )}

              <label className="form-lbl" style={{ marginTop: '14px' }}>Asking Price (ETH)</label>
              <div className="input-wrap">
                <input 
                  type="number" 
                  step="0.001" 
                  min="0.001" 
                  value={listPrice}
                  onChange={e => setListPrice(e.target.value)}
                  className="stake-amount-input"
                  disabled={isTransacting}
                  required
                />
                <span className="input-token-label">ETH</span>
              </div>
              <span className="form-sub-note">
                Seller receives <strong>98.0% ({(modalTaxPreview?.sellerNet || 0).toFixed(4)} ETH)</strong>. 2.0% Lottery Tax ({(modalTaxPreview?.totalTax || 0).toFixed(4)} ETH) routes {isSelectedDaily ? `50/50 (+${(modalTaxPreview?.dailyTax || 0).toFixed(4)} ETH Daily Pot & +${(modalTaxPreview?.sundayTax || 0).toFixed(4)} ETH Sunday Mega Pot)` : `100% (+${(modalTaxPreview?.sundayTax || 0).toFixed(4)} ETH to Sunday Mega Pot)`}.
              </span>

              <div className="modal-btn-row">
                <button 
                  type="button" 
                  onClick={() => setIsListingOpen(false)} 
                  className="btn-cancel"
                  disabled={isTransacting}
                >
                  Cancel
                </button>
                <button 
                  type="submit" 
                  className="btn-confirm-list"
                  disabled={isTransacting || (!selectedTicketToList && !customTicketId)}
                >
                  {isTransacting ? 'Processing...' : selectedListingInfo ? `Update Asking Price (${listPrice} ETH)` : 'Confirm On-Chain Listing'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* VIEW: My Tickets Tab */}
      {activeFilter === 'my_tickets' ? (
        <div className="tickets-grid">
          {userOwnedTickets.length === 0 ? (
            <div className="market-empty-state">
              <TicketIcon size={36} color="var(--color-gold)" />
              <p style={{ fontWeight: 600, color: 'var(--color-gold)', marginTop: '8px' }}>
                No VIP Bearer Passes in Connected Wallet
              </p>
              <p style={{ maxWidth: '520px', color: 'var(--color-text-secondary)', fontSize: '0.85rem', lineHeight: '1.6' }}>
                You have not minted or purchased any lottery tickets yet. Trade $\ge 0.10$ ETH in the Trade Terminal, claim free staking tickets in the Sanctuary, or purchase an active listing below to participate!
              </p>
            </div>
          ) : (
            userOwnedTickets.map(tid => {
              const isDaily = dayRange.start > 0 && tid >= dayRange.start && tid <= dayRange.end;
              const isAlreadyListed = listings.some(l => l.id === tid && l.rawSeller.toLowerCase() === (account || '').toLowerCase());
              return (
                <div
                  key={tid}
                  className="ticket-card vip-physical-pass"
                  onMouseEnter={() => setInspectedId(tid)}
                >
                  <div className="vip-pass-foil-shimmer" aria-hidden="true"></div>
                  <div className="ticket-card-header">
                    <div className="ticket-id-tag">
                      <TicketIcon size={14} color="var(--color-gold)" />
                      <span>VIP PASS #{tid}</span>
                    </div>
                    <span className="ticket-status-badge">
                      <ClockIcon size={12} />
                      <span>{isDaily ? 'Daily + Sunday' : 'Sunday Mega Only'}</span>
                    </span>
                  </div>

                  <div className="ticket-art-canvas">
                    <img src="/nft_ticket_4_clean.jpg" alt={`IRL Ticket #${tid}`} className="ticket-cover-img" />
                    <span className="ticket-canvas-live-id">
                      GENESIS #{String(tid).padStart(4, '0')}
                    </span>
                  </div>

                  <div className="ticket-info-row" style={{ marginTop: '8px' }}>
                    <div className="ticket-seller-wrap">
                      <span className="t-label">Pass Status</span>
                      <span className="t-val" style={{ color: isAlreadyListed ? 'var(--color-gold)' : 'var(--color-mint)' }}>
                        {isAlreadyListed ? 'Listed on Marketplace' : 'Unlisted in Vault'}
                      </span>
                    </div>
                    <div className="ticket-price-wrap">
                      <span className="t-label">Edition</span>
                      <span className="t-val" style={{ color: 'var(--color-rosegold-light)', fontSize: '0.82rem' }}>Hot-Foil ERC-721</span>
                    </div>
                  </div>

                  <div style={{ marginTop: '12px' }}>
                    {isAlreadyListed ? (
                      <button 
                        onClick={() => handleCancelListing(tid)} 
                        className="btn-cancel-listing"
                        disabled={isTransacting}
                      >
                        Cancel Listing #{tid}
                      </button>
                    ) : (
                      <button 
                        onClick={() => {
                          setSelectedTicketToList(String(tid));
                          setCustomTicketId('');
                          setIsListingOpen(true);
                        }} 
                        className="btn-buy-ticket"
                        disabled={isTransacting}
                      >
                        List Ticket #{tid} for Sale
                      </button>
                    )}
                  </div>
                </div>
              );
            })
          )}
        </div>
      ) : (
        /* VIEW: Active Listings Grid */
        <div className="tickets-grid">
          {isLoading ? (
            <div className="market-empty-state">
              <ClockIcon size={36} color="var(--color-gold)" />
              <p style={{ fontWeight: 600, color: 'var(--color-gold)', marginTop: '8px' }}>
                Connecting to High-Roller Lounge P2P Exchange...
              </p>
              <p style={{ maxWidth: '480px', color: 'var(--color-text-secondary)', fontSize: '0.85rem' }}>
                Verifying live smart contract listings and on-chain ownership via <code>IRLTicketNFT</code>.
              </p>
            </div>
          ) : filteredListings.length === 0 ? (
            <div className="market-empty-state">
              <TicketIcon size={36} color="var(--color-gold)" />
              <p style={{ fontWeight: 600, color: 'var(--color-gold)', marginTop: '8px' }}>
                No Tickets Currently Listed — P2P Marketplace Protocol Active (2.0% Lottery Tax)
              </p>
              <p style={{ maxWidth: '520px', color: 'var(--color-text-secondary)', fontSize: '0.85rem', lineHeight: '1.6' }}>
                All listed tickets have been purchased or no sellers have listed tickets in this view yet. Every secondary sale enforces a 2.0% Lottery Tax directly into the Daily &amp; Sunday Mega-Jackpot pools via <code>IRLUniswapV4Hook.receiveMarketplaceTax</code>.
              </p>
              {account && userOwnedTickets.length > 0 && (
                <button 
                  onClick={() => setIsListingOpen(true)}
                  className="btn-list-ticket"
                  style={{ marginTop: '14px' }}
                >
                  <TicketIcon size={16} />
                  <span>List One of Your {userOwnedTickets.length} Tickets</span>
                </button>
              )}
            </div>
          ) : (
            filteredListings.map(listing => {
              const taxInfo = computeTaxBreakdown(listing.priceEth, listing.isDailyEligible);
              const isMyListing = account && listing.rawSeller.toLowerCase() === account.toLowerCase();

              return (
                <div
                  key={listing.id}
                  className="ticket-card vip-physical-pass"
                  onMouseEnter={() => setInspectedId(listing.id)}
                >
                  <div className="vip-pass-foil-shimmer" aria-hidden="true"></div>
                  <div className="ticket-card-header">
                    <div className="ticket-id-tag">
                      <TicketIcon size={14} color="var(--color-gold)" />
                      <span>VIP PASS #{listing.id}</span>
                    </div>
                    <span className="ticket-status-badge">
                      <ClockIcon size={12} />
                      <span>{listing.mintDay}</span>
                    </span>
                  </div>

                  {/* Physical VIP Pass Artwork with Dynamic Ticket ID */}
                  <div className="ticket-art-canvas">
                    <img src="/nft_ticket_4_clean.jpg" alt={`IRL Ticket #${listing.id}`} className="ticket-cover-img" />
                    <span className="ticket-canvas-live-id">
                      GENESIS #{String(listing.id).padStart(4, '0')}
                    </span>
                  </div>

                  {/* Price & Meta */}
                  <div className="ticket-info-row">
                    <div className="ticket-seller-wrap">
                      <span className="t-label">SELLER (98% NET)</span>
                      <span className="t-val">{isMyListing ? 'You' : listing.seller}</span>
                    </div>
                    <div className="ticket-price-wrap">
                      <span className="t-label">PRICE</span>
                      <div className="ticket-price-val-group">
                        <span className="t-price-eth">{listing.priceEth} ETH</span>
                        <span className="t-price-usd">({listing.priceUsd})</span>
                      </div>
                    </div>
                  </div>

                  {/* 2% Protocol Jackpot Royalty Divider */}
                  <div className="ticket-card-royalty-line">
                    <span className="royalty-label">2% Protocol Jackpot Royalty</span>
                    <span className="royalty-amount">({taxInfo.totalTax.toFixed(4)} ETH)</span>
                  </div>

                  {/* Action Button: Cancel if owner, Buy if not */}
                  {isMyListing ? (
                    <button 
                      onClick={() => handleCancelListing(listing.id)} 
                      className="btn-cancel-listing"
                      disabled={isTransacting}
                    >
                      {isTransacting ? 'Processing...' : `Cancel Listing #${listing.id}`}
                    </button>
                  ) : (
                    <button 
                      onClick={() => handleBuy(listing)} 
                      className="btn-buy-ticket"
                      disabled={isTransacting}
                    >
                      {!account ? 'Connect to Buy' : isTransacting ? 'Processing...' : `Buy Ticket #${listing.id} (${listing.priceEth} ETH)`}
                    </button>
                  )}
                </div>
              );
            })
          )}
        </div>
      )}
    </div>
  );
}
