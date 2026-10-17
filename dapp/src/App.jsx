import React, { useState, useEffect, useCallback } from 'react';
import Header from './components/Header';
import EvAlertBanner from './components/EvAlertBanner';
import PotSanctuary from './components/PotSanctuary';
import PersonalOverview from './components/PersonalOverview';
import StakingVault from './components/StakingVault';
import ReferralPanel from './components/ReferralPanel';
import Leaderboard from './components/Leaderboard';
import TradeChart from './components/TradeChart';
import Whitepaper from './components/Whitepaper';
import Marketplace from './components/Marketplace';
import Footer from './components/Footer';
import { ROBINHOOD_CHAIN, CONTRACT_ADDRESSES } from './constants/contracts';
import './App.css';

const VALID_TABS = ['dashboard', 'trade', 'marketplace', 'referral', 'whitepaper'];
const RPC_URL = 'https://rpc.mainnet.chain.robinhood.com';

const pad32 = (hexNoPrefix) => hexNoPrefix.padStart(64, '0');
const addrWord = (addr) => pad32(String(addr || '').toLowerCase().replace(/^0x/, ''));
const uintWord = (n) => pad32(BigInt(n).toString(16));
const parseHexBigInt = (hex) => {
  if (!hex || hex === '0x' || hex === '0x0') return 0n;
  try {
    return BigInt(hex);
  } catch {
    return 0n;
  }
};
const formatEthStr = (wei, decimals = 3) => {
  const num = Number(wei) / 1e18;
  return num.toFixed(decimals);
};

export default function App() {
  const rawTab = typeof window !== 'undefined' ? new URLSearchParams(window.location.search).get('tab') : null;
  const initialTab = VALID_TABS.includes(rawTab) ? rawTab : 'dashboard';
  const [activeTab, setActiveTab] = useState(initialTab);
  const [account, setAccount] = useState(null);
  const [chainId, setChainId] = useState(null);
  const [isConnecting, setIsConnecting] = useState(false);
  const [isClaiming, setIsClaiming] = useState(false);
  const [isStakingProcessing, setIsStakingProcessing] = useState(false);
  const [globalToast, setGlobalToast] = useState(null);

  // Active Referral Link Attribution (?ref=custom-handle&r=0xWallet)
  const [activeReferral, setActiveReferral] = useState(() => {
    try {
      if (typeof window === 'undefined') return null;
      const params = new URLSearchParams(window.location.search);
      const urlRef = (params.get('ref') || '').trim().toLowerCase().replace(/[^a-z0-9_-]/g, '');
      const urlAddr = (params.get('r') || '').trim();
      if (urlRef.length >= 3) {
        const refObj = {
          code: urlRef.slice(0, 24),
          referrerAddress: /^0x[a-fA-F0-9]{40}$/.test(urlAddr) ? urlAddr : null,
        };
        localStorage.setItem('irl_active_referral', JSON.stringify(refObj));
        return refObj;
      }
      const saved = localStorage.getItem('irl_active_referral');
      return saved ? JSON.parse(saved) : null;
    } catch {
      return null;
    }
  });

  // Live reactive on-chain state
  const [hourlyPotEth, setHourlyPotEth] = useState("0.286");
  const [lotteryPotEth, setLotteryPotEth] = useState("0.004");
  const [sundayPotEth, setSundayPotEth] = useState("0.700");
  const [dailyTicketsInPlay, setDailyTicketsInPlay] = useState(6);
  const [sundayTicketsInPlay, setSundayTicketsInPlay] = useState(177);
  const [burnedSupplyIrl, setBurnedSupplyIrl] = useState("9,867,860");
  const [treasuryFeesEth, setTreasuryFeesEth] = useState("0.497");
  const [programmableFeesEth, setProgrammableFeesEth] = useState("0.065");
  const [distributedRewardsEth, setDistributedRewardsEth] = useState("0.608");
  const [lockedUnclaimedEth, setLockedUnclaimedEth] = useState("0.255");
  const [launchTimestamp, setLaunchTimestamp] = useState(1792027210);
  const [topTraders, setTopTraders] = useState([]);
  const [leaderboardInfo, setLeaderboardInfo] = useState(null);

  const [userBalanceEth, setUserBalanceEth] = useState("0.0000");
  const [userBalanceIrl, setUserBalanceIrl] = useState("0");
  const [userStakedIrl, setUserStakedIrl] = useState("0");
  const [lastStakedTimestamp, setLastStakedTimestamp] = useState(0);
  const [unstakeUnlockTime, setUnstakeUnlockTime] = useState(0);
  const [claimedStakingTickets, setClaimedStakingTickets] = useState(0);
  const [userClaimableYieldEth, setUserClaimableYieldEth] = useState("0.000");
  const [estimatedRewardEth, setEstimatedRewardEth] = useState("0.000");
  const [userVolumeEth, setUserVolumeEth] = useState("0.000");
  const [ticketsCount, setTicketsCount] = useState(0);

  // Sherwood Co-Staking Guild state (IRLSherwoodGuildVault.sol)
  const [totalGuildStakedIrl, setTotalGuildStakedIrl] = useState("1450000");
  const [userGuildStakedIrl, setUserGuildStakedIrl] = useState("0");
  const [userGuildPendingEth, setUserGuildPendingEth] = useState("0.0000");
  const [guildTicketCount, setGuildTicketCount] = useState(1);
  const [userGuildStakedDurationSec, setUserGuildStakedDurationSec] = useState(0);
  const [userGuildEligibleDaily8h, setUserGuildEligibleDaily8h] = useState(false);
  const [userGuildEligibleWeekly1d, setUserGuildEligibleWeekly1d] = useState(false);

  function showToast(msg) {
    setGlobalToast(msg);
    setTimeout(() => setGlobalToast(null), 4000);
  }

  const refreshOnChainState = useCallback(async () => {
    try {
      const nowSec = Math.floor(Date.now() / 1000);
      const nowHourId = Math.floor(nowSec / 3600);
      const nowDayId = Math.floor(nowSec / 86400);
      const nowWeekId = Math.floor((nowSec + 3 * 86400) / (7 * 86400));
      const batch = [
        { jsonrpc: '2.0', id: 1, method: 'eth_call', params: [{ to: CONTRACT_ADDRESSES.HOOK, data: '0x770b1036' }, 'latest'] }, // dailyLotteryPot()
        { jsonrpc: '2.0', id: 2, method: 'eth_call', params: [{ to: CONTRACT_ADDRESSES.HOOK, data: '0xca0bf0cc' }, 'latest'] }, // sundayMegaPot()
        { jsonrpc: '2.0', id: 3, method: 'eth_call', params: [{ to: CONTRACT_ADDRESSES.HOOK, data: '0xba27ad89' }, 'latest'] }, // hourlyRewardPot()
        { jsonrpc: '2.0', id: 4, method: 'eth_call', params: [{ to: CONTRACT_ADDRESSES.HOOK, data: '0x545475d4' }, 'latest'] }, // protocolPot()
        { jsonrpc: '2.0', id: 5, method: 'eth_call', params: [{ to: CONTRACT_ADDRESSES.HOOK, data: '0x3f2a4cce' }, 'latest'] }, // programmableFeePot()
        { jsonrpc: '2.0', id: 6, method: 'eth_call', params: [{ to: CONTRACT_ADDRESSES.HOOK, data: '0x65cf7c9b' }, 'latest'] }, // launchTimestamp()
        { jsonrpc: '2.0', id: 7, method: 'eth_call', params: [{ to: CONTRACT_ADDRESSES.TOKEN, data: '0x70a08231' + addrWord('0x000000000000000000000000000000000000dEaD') }, 'latest'] }, // burned 0xdead
        { jsonrpc: '2.0', id: 8, method: 'eth_call', params: [{ to: CONTRACT_ADDRESSES.HOOK, data: '0xb771f02d' + uintWord(nowHourId) }, 'latest'] }, // getTopTraders(hourId)
        { jsonrpc: '2.0', id: 9, method: 'eth_call', params: [{ to: CONTRACT_ADDRESSES.HOOK, data: '0x33873c75' + uintWord(nowHourId) }, 'latest'] }, // hourlyPotByHour(hourId)
        { jsonrpc: '2.0', id: 19, method: 'eth_call', params: [{ to: CONTRACT_ADDRESSES.HOOK, data: '0x51e5cdcd' + uintWord(nowDayId) }, 'latest'] }, // dayStartTicketId(dayId)
        { jsonrpc: '2.0', id: 20, method: 'eth_call', params: [{ to: CONTRACT_ADDRESSES.HOOK, data: '0xbb179bdd' + uintWord(nowDayId) }, 'latest'] }, // dayEndTicketId(dayId)
        { jsonrpc: '2.0', id: 21, method: 'eth_call', params: [{ to: CONTRACT_ADDRESSES.HOOK, data: '0x121fad1a' + uintWord(nowWeekId) }, 'latest'] }, // weekStartTicketId(weekId)
        { jsonrpc: '2.0', id: 22, method: 'eth_call', params: [{ to: CONTRACT_ADDRESSES.HOOK, data: '0xf2dd775a' + uintWord(nowWeekId) }, 'latest'] }, // weekEndTicketId(weekId)
        { jsonrpc: '2.0', id: 23, method: 'eth_call', params: [{ to: CONTRACT_ADDRESSES.TICKETS, data: '0xd7a5e84f' }, 'latest'] }, // totalTicketsMinted()
        { jsonrpc: '2.0', id: 24, method: 'eth_call', params: [{ to: CONTRACT_ADDRESSES.SHERWOOD_GUILD, data: '0x0291d5ef' }, 'latest'] }, // totalGuildStaked()
        { jsonrpc: '2.0', id: 25, method: 'eth_call', params: [{ to: CONTRACT_ADDRESSES.SHERWOOD_GUILD, data: '0xf33afb1e' }, 'latest'] }, // getGuildTicketCount()
      ];

      if (account) {
        batch.push(
          { jsonrpc: '2.0', id: 10, method: 'eth_call', params: [{ to: CONTRACT_ADDRESSES.TOKEN, data: '0x70a08231' + addrWord(account) }, 'latest'] }, // balanceOf
          { jsonrpc: '2.0', id: 11, method: 'eth_call', params: [{ to: CONTRACT_ADDRESSES.STAKING, data: '0x60217267' + addrWord(account) }, 'latest'] }, // stakedBalance
          { jsonrpc: '2.0', id: 12, method: 'eth_call', params: [{ to: CONTRACT_ADDRESSES.STAKING, data: '0xc7bf1980' + addrWord(account) }, 'latest'] }, // pendingYield
          { jsonrpc: '2.0', id: 13, method: 'eth_call', params: [{ to: CONTRACT_ADDRESSES.STAKING, data: '0x71de48ea' + addrWord(account) }, 'latest'] }, // lastStakedTimestamp
          { jsonrpc: '2.0', id: 14, method: 'eth_call', params: [{ to: CONTRACT_ADDRESSES.STAKING, data: '0x3170a7fb' + addrWord(account) }, 'latest'] }, // unstakeUnlockTime
          { jsonrpc: '2.0', id: 15, method: 'eth_call', params: [{ to: CONTRACT_ADDRESSES.TICKETS, data: '0x70a08231' + addrWord(account) }, 'latest'] }, // tickets balanceOf
          { jsonrpc: '2.0', id: 16, method: 'eth_call', params: [{ to: CONTRACT_ADDRESSES.HOOK, data: '0x5d71edc7' + uintWord(nowHourId) + addrWord(account) }, 'latest'] }, // userHourlyScore
          { jsonrpc: '2.0', id: 17, method: 'eth_call', params: [{ to: CONTRACT_ADDRESSES.HOOK, data: '0x949813b8' + addrWord(account) }, 'latest'] }, // unclaimedRewards
          { jsonrpc: '2.0', id: 18, method: 'eth_getBalance', params: [account, 'latest'] }, // native ETH balance
          { jsonrpc: '2.0', id: 26, method: 'eth_call', params: [{ to: CONTRACT_ADDRESSES.SHERWOOD_GUILD, data: '0x60217267' + addrWord(account) }, 'latest'] }, // guild stakedBalance
          { jsonrpc: '2.0', id: 27, method: 'eth_call', params: [{ to: CONTRACT_ADDRESSES.SHERWOOD_GUILD, data: '0xc7bf1980' + addrWord(account) }, 'latest'] }, // guild pendingYield
          { jsonrpc: '2.0', id: 28, method: 'eth_call', params: [{ to: CONTRACT_ADDRESSES.SHERWOOD_GUILD, data: '0x3ec5e882' + addrWord(account) }, 'latest'] } // getUserLotteryEligibility
        );
      }

      const res = await fetch(RPC_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(batch),
      });
      if (!res.ok) return;
      const arr = await res.json();
      const byId = {};
      for (const item of arr) byId[item.id] = item.result;

      const dailyWei = parseHexBigInt(byId[1]);
      const sundayWei = parseHexBigInt(byId[2]);
      const hourlyWei = parseHexBigInt(byId[3]);
      const protoWei = parseHexBigInt(byId[4]);
      const progFallbackWei = parseHexBigInt(byId[5]);
      const launchTs = Number(parseHexBigInt(byId[6]));
      const deadIrlWei = parseHexBigInt(byId[7]);
      const hourPotWei = parseHexBigInt(byId[9]) || hourlyWei;

      setLotteryPotEth(formatEthStr(dailyWei, 3));
      setSundayPotEth(formatEthStr(sundayWei, 3));
      setHourlyPotEth(formatEthStr(hourlyWei, 3));
      setTreasuryFeesEth(formatEthStr(protoWei, 3));

      // Programmable 0.30% is transferred directly on every swap; estimate total routed from lottery pot (0.30 / 1.875 of daily pot) + fallback
      const estimatedProgWei = progFallbackWei + (dailyWei * 300n) / 1875n;
      setProgrammableFeesEth(formatEthStr(estimatedProgWei, 3));

      if (launchTs > 0) setLaunchTimestamp(launchTs);
      const deadTokens = Math.floor(Number(deadIrlWei) / 1e18);
      if (deadTokens > 0) setBurnedSupplyIrl(deadTokens.toLocaleString('en-US'));

      // Daily and Sunday ticket range counts in play
      const dStart = parseHexBigInt(byId[19]);
      const dEnd = parseHexBigInt(byId[20]);
      const wStart = parseHexBigInt(byId[21]);
      const wEnd = parseHexBigInt(byId[22]);
      const totalMinted = parseHexBigInt(byId[23]);

      let dailyTix = 0;
      if (dEnd >= dStart && dStart > 0n) {
        dailyTix = Number(dEnd - dStart + 1n);
      } else if (dStart > 0n && totalMinted >= dStart) {
        dailyTix = Number(totalMinted - dStart + 1n);
      }
      setDailyTicketsInPlay(dailyTix);

      let sundayTix = 0;
      if (wEnd >= wStart && wStart > 0n) {
        sundayTix = Number(wEnd - wStart + 1n);
      } else if (wStart > 0n && totalMinted >= wStart) {
        sundayTix = Number(totalMinted - wStart + 1n);
      } else if (totalMinted > 0n) {
        sundayTix = Number(totalMinted);
      }
      setSundayTicketsInPlay(sundayTix);

      // Fetch pre-computed real-human leaderboard & rewards ledger (unmasking router contracts)
      try {
        const lbRes = await fetch(`/leaderboard.json?t=${Date.now()}`);
        if (lbRes.ok) {
          const lbData = await lbRes.json();
          setLeaderboardInfo(lbData);
          if (lbData.distributedRewardsEth) setDistributedRewardsEth(lbData.distributedRewardsEth);
          if (lbData.lockedUnclaimedEth) setLockedUnclaimedEth(lbData.lockedUnclaimedEth);
        }
      } catch (_) {}

      // Decode dynamic address[] from getTopTraders(hourId)
      const rawTradersHex = (byId[8] || '').replace(/^0x/, '');
      if (rawTradersHex.length >= 128) {
        const count = parseInt(rawTradersHex.slice(64, 128), 16);
        const addrs = [];
        for (let i = 0; i < count && i < 10; i++) {
          const word = rawTradersHex.slice(128 + i * 64, 192 + i * 64);
          if (word.length === 64) {
            addrs.push('0x' + word.slice(24));
          }
        }
        if (addrs.length > 0) {
          const scoreBatch = addrs.map((a, idx) => ({
            jsonrpc: '2.0',
            id: 100 + idx,
            method: 'eth_call',
            params: [{ to: CONTRACT_ADDRESSES.HOOK, data: '0x5d71edc7' + uintWord(nowHourId) + addrWord(a) }, 'latest'],
          }));
          const sRes = await fetch(RPC_URL, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(scoreBatch),
          });
          if (sRes.ok) {
            const sArr = await sRes.json();
            const sMap = {};
            for (const it of sArr) sMap[it.id] = parseHexBigInt(it.result);
            const scored = addrs.map((a, idx) => ({
              fullAddress: a,
              address: `${a.slice(0, 6)}...${a.slice(-4)}`,
              scoreWei: sMap[100 + idx] || 0n,
            }));
            scored.sort((x, y) => (y.scoreWei > x.scoreWei ? 1 : y.scoreWei < x.scoreWei ? -1 : 0));
            const totalTop10Score = scored.reduce((acc, x) => acc + x.scoreWei, 0n);
            const top10PotEth = (Number(hourPotWei) / 1e18) * 0.35;

            setTopTraders(
              scored.map((item, i) => {
                const shareRatio = totalTop10Score > 0n ? Number(item.scoreWei) / Number(totalTop10Score) : 0;
                return {
                  rank: i + 1,
                  fullAddress: item.fullAddress,
                  address: item.address,
                  volumeEth: (Number(item.scoreWei) / 1e18).toFixed(3),
                  rewardEth: (top10PotEth * shareRatio).toFixed(4),
                };
              })
            );
          }
        }
      }

      // Sherwood Guild global stats (if contract deployed on-chain)
      const guildTotalWei = parseHexBigInt(byId[24]);
      if (guildTotalWei > 0n) {
        setTotalGuildStakedIrl(String(Math.floor(Number(guildTotalWei) / 1e18)));
      }
      if (byId[25] && byId[25] !== '0x') {
        setGuildTicketCount(Number(parseHexBigInt(byId[25])));
      }

      if (account) {
        const balIrl = Math.floor(Number(parseHexBigInt(byId[10])) / 1e18);
        const stkIrl = Math.floor(Number(parseHexBigInt(byId[11])) / 1e18);
        const pendYieldWei = parseHexBigInt(byId[12]);
        const lastStkTs = Number(parseHexBigInt(byId[13]));
        const unlockTs = Number(parseHexBigInt(byId[14]));
        const tCount = Number(parseHexBigInt(byId[15]));
        const uScoreWei = parseHexBigInt(byId[16]);
        const unclaimedWei = parseHexBigInt(byId[17]);
        const ethBalWei = parseHexBigInt(byId[18]);

        setUserBalanceEth(formatEthStr(ethBalWei, 4));
        setUserBalanceIrl(String(balIrl));
        setUserStakedIrl(String(stkIrl));
        setUserClaimableYieldEth(formatEthStr(pendYieldWei, 4));
        setLastStakedTimestamp(lastStkTs);
        setUnstakeUnlockTime(unlockTs);
        setTicketsCount(tCount);
        setUserVolumeEth(formatEthStr(uScoreWei, 4));
        setEstimatedRewardEth(formatEthStr(unclaimedWei, 4));

        if (byId[26] && byId[26] !== '0x') {
          const gUserIrl = Math.floor(Number(parseHexBigInt(byId[26])) / 1e18);
          setUserGuildStakedIrl(String(gUserIrl));
        }
        if (byId[27] && byId[27] !== '0x') {
          const gPendWei = parseHexBigInt(byId[27]);
          setUserGuildPendingEth(formatEthStr(gPendWei, 4));
        }
        const rawElig = (byId[28] || '').replace(/^0x/, '');
        if (rawElig.length >= 64 * 6) {
          const d8h = parseInt(rawElig.slice(64, 128), 16) !== 0;
          const w1d = parseInt(rawElig.slice(128, 192), 16) !== 0;
          const durSec = parseInt(rawElig.slice(320, 384), 16);
          setUserGuildEligibleDaily8h(d8h);
          setUserGuildEligibleWeekly1d(w1d);
          setUserGuildStakedDurationSec(durSec);
        }
      }
    } catch (err) {
      console.error('Error refreshing on-chain state:', err);
    }
  }, [account]);

  useEffect(() => {
    refreshOnChainState();
    const timer = setInterval(refreshOnChainState, 6000);
    return () => clearInterval(timer);
  }, [refreshOnChainState]);

  // EVM wallet detection (MetaMask, Rabby, Coinbase Wallet)
  useEffect(() => {
    if (window.ethereum) {
      window.ethereum.request({ method: 'eth_accounts' })
        .then((accounts) => {
          if (accounts.length > 0) {
            setAccount(accounts[0]);
          }
        })
        .catch(console.error);

      window.ethereum.request({ method: 'eth_chainId' })
        .then((id) => setChainId(parseInt(id, 16)))
        .catch(console.error);

      const handleAccountsChanged = (accounts) => {
        setAccount(accounts.length > 0 ? accounts[0] : null);
      };

      const handleChainChanged = (id) => {
        setChainId(parseInt(id, 16));
      };

      window.ethereum.on('accountsChanged', handleAccountsChanged);
      window.ethereum.on('chainChanged', handleChainChanged);

      return () => {
        window.ethereum.removeListener('accountsChanged', handleAccountsChanged);
        window.ethereum.removeListener('chainChanged', handleChainChanged);
      };
    }
  }, []);

  async function connectWallet() {
    if (!window.ethereum) {
      showToast("Please install an EVM-compatible Web3 wallet (MetaMask, Rabby Wallet, Coinbase Wallet).");
      return;
    }

    setIsConnecting(true);
    try {
      const accounts = await window.ethereum.request({ method: 'eth_requestAccounts' });
      if (accounts.length > 0) {
        setAccount(accounts[0]);
      }
      const currentChain = await window.ethereum.request({ method: 'eth_chainId' });
      setChainId(parseInt(currentChain, 16));
    } catch (err) {
      console.error("Wallet connection error:", err);
    } finally {
      setIsConnecting(false);
    }
  }

  function disconnectWallet() {
    setAccount(null);
  }

  async function switchNetwork() {
    if (!window.ethereum) return;
    try {
      await window.ethereum.request({
        method: 'wallet_switchEthereumChain',
        params: [{ chainId: `0x${ROBINHOOD_CHAIN.id.toString(16)}` }],
      });
    } catch (switchError) {
      if (switchError.code === 4902) {
        try {
          await window.ethereum.request({
            method: 'wallet_addEthereumChain',
            params: [
              {
                chainId: `0x${ROBINHOOD_CHAIN.id.toString(16)}`,
                chainName: ROBINHOOD_CHAIN.name,
                nativeCurrency: ROBINHOOD_CHAIN.nativeCurrency,
                rpcUrls: ROBINHOOD_CHAIN.rpcUrls.default.http,
                blockExplorerUrls: [ROBINHOOD_CHAIN.blockExplorers.default.url],
              },
            ],
          });
        } catch (addError) {
          console.error("Error adding network to wallet:", addError);
        }
      }
    }
  }

  async function handleClaim() {
    if (!account) return;
    if (chainId !== ROBINHOOD_CHAIN.id) {
      await switchNetwork();
      return;
    }
    setIsClaiming(true);
    try {
      await window.ethereum.request({
        method: 'eth_sendTransaction',
        params: [{
          from: account,
          to: CONTRACT_ADDRESSES.HOOK,
          data: '0xe189d3a4', // claimUnclaimedRewards()
        }],
      });
      showToast(`Claimed ${estimatedRewardEth} ETH rewards to your wallet!`);
      setTimeout(refreshOnChainState, 2500);
    } catch (err) {
      showToast(err?.message || 'Claim transaction cancelled.');
    } finally {
      setIsClaiming(false);
    }
  }

  async function handleClaimYield() {
    if (!account) return;
    if (chainId !== ROBINHOOD_CHAIN.id) {
      await switchNetwork();
      return;
    }
    try {
      await window.ethereum.request({
        method: 'eth_sendTransaction',
        params: [{
          from: account,
          to: CONTRACT_ADDRESSES.STAKING,
          data: '0x406cf229', // claimYield()
        }],
      });
      showToast(`Claimed ${userClaimableYieldEth} ETH Staking Real Yield to your wallet!`);
      setTimeout(refreshOnChainState, 2500);
    } catch (err) {
      showToast(err?.message || 'Yield claim cancelled.');
    }
  }

  async function handleStake(amount) {
    if (!account || !amount) return;
    if (chainId !== ROBINHOOD_CHAIN.id) {
      await switchNetwork();
      return;
    }
    setIsStakingProcessing(true);
    try {
      const amountWei = BigInt(Math.floor(Number(amount))) * (10n ** 18n);
      // 1. Check allowance
      const allowRes = await fetch(RPC_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          jsonrpc: '2.0',
          id: 1,
          method: 'eth_call',
          params: [{ to: CONTRACT_ADDRESSES.TOKEN, data: '0xdd62ed3e' + addrWord(account) + addrWord(CONTRACT_ADDRESSES.STAKING) }, 'latest'],
        }),
      });
      const allowJson = await allowRes.json();
      const currentAllow = parseHexBigInt(allowJson.result);
      if (currentAllow < amountWei) {
        showToast('Step 1/2: Approving $IRL for Staking Vault...');
        await window.ethereum.request({
          method: 'eth_sendTransaction',
          params: [{
            from: account,
            to: CONTRACT_ADDRESSES.TOKEN,
            data: '0x095ea7b3' + addrWord(CONTRACT_ADDRESSES.STAKING) + uintWord(amountWei),
          }],
        });
        await new Promise((r) => setTimeout(r, 2500));
      }

      showToast('Staking $IRL into Real Yield Sanctuary...');
      await window.ethereum.request({
        method: 'eth_sendTransaction',
        params: [{
          from: account,
          to: CONTRACT_ADDRESSES.STAKING,
          data: '0xa694fc3a' + uintWord(amountWei),
        }],
      });
      showToast(`Deposit sent: ${Number(amount).toLocaleString()} $IRL staked!`);
      setTimeout(refreshOnChainState, 2500);
    } catch (err) {
      showToast(err?.message || 'Staking transaction cancelled.');
    } finally {
      setIsStakingProcessing(false);
    }
  }

  async function handleClaimStakingTickets({ isInstant, count }) {
    if (!account || !count || count <= 0) return;
    if (chainId !== ROBINHOOD_CHAIN.id) {
      await switchNetwork();
      return;
    }
    setIsStakingProcessing(true);
    try {
      await window.ethereum.request({
        method: 'eth_sendTransaction',
        params: [{
          from: account,
          to: CONTRACT_ADDRESSES.HOOK,
          data: '0xc516c776', // claimStakingTickets()
        }],
      });
      showToast(
        isInstant
          ? `Instant Claim sent: +${count} free staking tickets (24h unstake lock applied)!`
          : `Mature Claim sent: +${count} free staking tickets with 0h unstake lock!`
      );
      setTimeout(refreshOnChainState, 2500);
    } catch (err) {
      showToast(err?.message || 'Ticket claim cancelled.');
    } finally {
      setIsStakingProcessing(false);
    }
  }


  async function handleWithdraw(amount) {
    if (!account || !amount) return;
    const nowSec = Math.floor(Date.now() / 1000);
    if (unstakeUnlockTime > nowSec) {
      const remHours = Math.ceil((unstakeUnlockTime - nowSec) / 3600);
      showToast(`Withdrawal locked for ~${remHours}h because you Instant-Claimed free staking tickets before 24h.`);
      return;
    }
    if (chainId !== ROBINHOOD_CHAIN.id) {
      await switchNetwork();
      return;
    }
    setIsStakingProcessing(true);
    try {
      const amountWei = BigInt(Math.floor(Number(amount))) * (10n ** 18n);
      await window.ethereum.request({
        method: 'eth_sendTransaction',
        params: [{
          from: account,
          to: CONTRACT_ADDRESSES.STAKING,
          data: '0x2e17de78' + uintWord(amountWei), // unstake(uint256)
        }],
      });
      showToast(`Withdrawal sent: ${Number(amount).toLocaleString()} $IRL returning to your wallet.`);
      setTimeout(refreshOnChainState, 2500);
    } catch (err) {
      showToast(err?.message || 'Withdrawal transaction cancelled.');
    } finally {
      setIsStakingProcessing(false);
    }
  }

  async function handleGuildDeposit(amount) {
    if (!account || !amount) return;
    if (chainId !== ROBINHOOD_CHAIN.id) {
      await switchNetwork();
      return;
    }
    setIsStakingProcessing(true);
    try {
      const amountWei = BigInt(Math.floor(Number(amount))) * (10n ** 18n);
      const allowRes = await fetch(RPC_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          jsonrpc: '2.0',
          id: 1,
          method: 'eth_call',
          params: [{ to: CONTRACT_ADDRESSES.TOKEN, data: '0xdd62ed3e' + addrWord(account) + addrWord(CONTRACT_ADDRESSES.SHERWOOD_GUILD) }, 'latest'],
        }),
      });
      const allowJson = await allowRes.json();
      const currentAllow = parseHexBigInt(allowJson.result);
      if (currentAllow < amountWei) {
        showToast('Step 1/2: Approving $IRL for Sherwood Co-Staking Guild...');
        await window.ethereum.request({
          method: 'eth_sendTransaction',
          params: [{
            from: account,
            to: CONTRACT_ADDRESSES.TOKEN,
            data: '0x095ea7b3' + addrWord(CONTRACT_ADDRESSES.SHERWOOD_GUILD) + uintWord(amountWei),
          }],
        });
        await new Promise((r) => setTimeout(r, 2500));
      }

      showToast('Depositing $IRL into Sherwood Co-Staking Guild...');
      await window.ethereum.request({
        method: 'eth_sendTransaction',
        params: [{
          from: account,
          to: CONTRACT_ADDRESSES.SHERWOOD_GUILD,
          data: '0xb6b55f25' + uintWord(amountWei), // deposit(uint256)
        }],
      });
      setUserGuildStakedIrl((prev) => String((Number(prev) || 0) + Math.floor(Number(amount))));
      setTotalGuildStakedIrl((prev) => String((Number(prev) || 0) + Math.floor(Number(amount))));
      showToast(`Guild Deposit sent: ${Number(amount).toLocaleString()} $IRL pooled (Zero Lock)!`);
      setTimeout(refreshOnChainState, 2500);
    } catch (err) {
      showToast(err?.message || 'Guild deposit cancelled.');
    } finally {
      setIsStakingProcessing(false);
    }
  }

  async function handleGuildWithdraw(amount) {
    if (!account || !amount) return;
    if (chainId !== ROBINHOOD_CHAIN.id) {
      await switchNetwork();
      return;
    }
    setIsStakingProcessing(true);
    try {
      const amountWei = BigInt(Math.floor(Number(amount))) * (10n ** 18n);
      await window.ethereum.request({
        method: 'eth_sendTransaction',
        params: [{
          from: account,
          to: CONTRACT_ADDRESSES.SHERWOOD_GUILD,
          data: '0x2e1a7d4d' + uintWord(amountWei), // withdraw(uint256)
        }],
      });
      setUserGuildStakedIrl("0");
      showToast(`Guild withdrawal sent: ${Number(amount).toLocaleString()} $IRL returning to your wallet.`);
      setTimeout(refreshOnChainState, 2500);
    } catch (err) {
      showToast(err?.message || 'Guild withdrawal cancelled.');
    } finally {
      setIsStakingProcessing(false);
    }
  }

  async function handleGuildClaimYield() {
    if (!account) return;
    if (chainId !== ROBINHOOD_CHAIN.id) {
      await switchNetwork();
      return;
    }
    try {
      await window.ethereum.request({
        method: 'eth_sendTransaction',
        params: [{
          from: account,
          to: CONTRACT_ADDRESSES.SHERWOOD_GUILD,
          data: '0x7a095823', // claimGuildYield()
        }],
      });
      showToast(`Claimed ${userGuildPendingEth} ETH Sherwood Guild Real Yield to your wallet!`);
      setTimeout(refreshOnChainState, 2500);
    } catch (err) {
      showToast(err?.message || 'Guild yield claim cancelled.');
    }
  }

  async function handleGuildClaimTickets() {
    if (!account) return;
    if (chainId !== ROBINHOOD_CHAIN.id) {
      await switchNetwork();
      return;
    }
    try {
      await window.ethereum.request({
        method: 'eth_sendTransaction',
        params: [{
          from: account,
          to: CONTRACT_ADDRESSES.SHERWOOD_GUILD,
          data: '0xddc7e460', // claimGuildStakingTickets()
        }],
      });
      setGuildTicketCount((prev) => prev + 1);
      showToast('Claimed free Staking NFT Lottery Tickets for the Sherwood Guild contract!');
      setTimeout(refreshOnChainState, 2500);
    } catch (err) {
      showToast(err?.message || 'Guild ticket claim cancelled.');
    }
  }

  const [quickMintOpen, setQuickMintOpen] = useState(false);
  const [quickMintPack, setQuickMintPack] = useState(3);

  function handleSelectTab(nextTab) {
    if (!VALID_TABS.includes(nextTab)) return;
    if (typeof document !== 'undefined' && typeof document.startViewTransition === 'function') {
      document.startViewTransition(() => {
        setActiveTab(nextTab);
      });
    } else {
      setActiveTab(nextTab);
    }
  }

  function handleOpenQuickMint(ticketsToSim = 3) {
    setQuickMintPack(Number(ticketsToSim) || 3);
    setQuickMintOpen(true);
  }

  function handleSwapSuccess() {
    setTimeout(refreshOnChainState, 2000);
  }

  function handleBuyTicket() {
    setTimeout(refreshOnChainState, 2000);
  }

  function handleListTicket() {
    setTimeout(refreshOnChainState, 2000);
  }

  const activeDailyPool = Math.max(0, Number(dailyTicketsInPlay) || 0);
  const activeSundayPool = Math.max(0, Number(sundayTicketsInPlay) || 0);
  const drawerDailyOdds = ((quickMintPack / (activeDailyPool + quickMintPack)) * 100).toFixed(1);
  const drawerSundayOdds = ((quickMintPack / (activeSundayPool + quickMintPack)) * 100).toFixed(1);
  const drawerReqEth = (quickMintPack * 0.10).toFixed(2);
  const drawerCashbackEth = (Number(drawerReqEth) * 0.004375).toFixed(5);

  return (
    <div className="app-container">
      {/* Zero-Lag GPU Ambient Backdrop: Pure Transform/Opacity Radial Layers */}
      <div className="lounge-ambient-backdrop" aria-hidden="true">
        <div className="aurora-orb aurora-orb-primary"></div>
        <div className="aurora-orb aurora-orb-emerald"></div>
        <div className="aurora-orb aurora-orb-secondary"></div>
      </div>

      {globalToast && (
        <div
          style={{
            position: 'fixed',
            bottom: '32px',
            right: '28px',
            zIndex: 9999,
            background: 'rgba(2, 7, 5, 0.96)',
            backdropFilter: 'blur(16px)',
            borderRadius: '20px',
            padding: '16px 26px',
            color: '#FFF2E2',
            fontSize: '0.88rem',
            boxShadow: '0 24px 60px rgba(0,0,0,0.9), inset 0 0 0 1px rgba(230, 194, 165, 0.32)',
            maxWidth: '440px',
          }}
        >
          {globalToast}
        </div>
      )}

      {/* Top Scrolling +EV Win Probability Marquee Banner */}
      <EvAlertBanner
        dailyTicketsInPlay={dailyTicketsInPlay}
        lotteryPotEth={lotteryPotEth}
        sundayPotEth={sundayPotEth}
        hourlyPotEth={hourlyPotEth}
        activeReferral={activeReferral}
        onSelectTab={handleSelectTab}
        onOpenQuickMint={handleOpenQuickMint}
      />

      <Header 
        account={account}
        isConnecting={isConnecting}
        onConnect={connectWallet}
        onDisconnect={disconnectWallet}
        chainId={chainId}
        onSwitchNetwork={switchNetwork}
        activeTab={activeTab}
        onSelectTab={handleSelectTab}
      />

      <main key={activeTab} className="lounge-main-stage" style={{ display: 'flex', flexDirection: 'column', gap: '32px' }}>
        {/* VIEW 1: Dashboard & Pots Sanctuary */}
        {activeTab === 'dashboard' && (
          <>
            <PotSanctuary 
              hourlyPotEth={hourlyPotEth} 
              lotteryPotEth={lotteryPotEth}
              sundayPotEth={sundayPotEth}
              dailyTicketsInPlay={dailyTicketsInPlay}
              sundayTicketsInPlay={sundayTicketsInPlay}
              burnedSupplyIrl={burnedSupplyIrl}
              treasuryFeesEth={treasuryFeesEth}
              programmableFeesEth={programmableFeesEth}
              distributedRewardsEth={distributedRewardsEth}
              lockedUnclaimedEth={lockedUnclaimedEth}
              launchTimestamp={launchTimestamp}
              onOpenQuickMint={handleOpenQuickMint}
            />

            <PersonalOverview 
              account={account}
              onConnect={connectWallet}
              ticketsCount={ticketsCount}
              dailyTicketsInPlay={dailyTicketsInPlay}
              sundayTicketsInPlay={sundayTicketsInPlay}
              estimatedRewardEth={estimatedRewardEth}
              userVolumeEth={userVolumeEth}
              onClaim={handleClaim}
              isClaiming={isClaiming}
              onOpenQuickMint={handleOpenQuickMint}
            />

            <div className="dashboard-interactive-grid">
              <StakingVault 
                account={account}
                userBalanceIrl={userBalanceIrl}
                userStakedIrl={userStakedIrl}
                userClaimableYieldEth={userClaimableYieldEth}
                lastStakedTimestamp={lastStakedTimestamp}
                unstakeUnlockTime={unstakeUnlockTime}
                claimedStakingTickets={claimedStakingTickets}
                totalGuildStakedIrl={totalGuildStakedIrl}
                userGuildStakedIrl={userGuildStakedIrl}
                userGuildPendingEth={userGuildPendingEth}
                guildTicketCount={guildTicketCount}
                userGuildStakedDurationSec={userGuildStakedDurationSec}
                userGuildEligibleDaily8h={userGuildEligibleDaily8h}
                userGuildEligibleWeekly1d={userGuildEligibleWeekly1d}
                onStake={handleStake}
                onWithdraw={handleWithdraw}
                onClaimYield={handleClaimYield}
                onClaimStakingTickets={handleClaimStakingTickets}
                onGuildDeposit={handleGuildDeposit}
                onGuildWithdraw={handleGuildWithdraw}
                onGuildClaimYield={handleGuildClaimYield}
                onGuildClaimTickets={handleGuildClaimTickets}
                isProcessing={isStakingProcessing}
              />

              <Leaderboard 
                account={account} 
                leaderboardInfo={leaderboardInfo} 
                fallbackTraders={topTraders}
                hourlyPotEth={hourlyPotEth}
                distributedRewardsEth={distributedRewardsEth}
                dailyTicketsInPlay={dailyTicketsInPlay}
                sundayTicketsInPlay={sundayTicketsInPlay}
                onOpenQuickMint={handleOpenQuickMint}
                onSelectTab={handleSelectTab}
              />
            </div>
          </>
        )}

        {/* VIEW 2: Trade & Interactive Chart */}
        {activeTab === 'trade' && (
          <TradeChart 
            account={account}
            onConnect={connectWallet}
            chainId={chainId}
            onSwitchNetwork={switchNetwork}
            userBalanceEth={userBalanceEth}
            userBalanceIrl={userBalanceIrl}
            userStakedIrl={userStakedIrl}
            dailyTicketsInPlay={dailyTicketsInPlay}
            sundayPotEth={sundayPotEth}
            lotteryPotEth={lotteryPotEth}
            activeReferral={activeReferral}
            onSwapSuccess={handleSwapSuccess}
          />
        )}

        {/* VIEW 3: Whitepaper & Transparent Architecture */}
        {activeTab === 'whitepaper' && (
          <Whitepaper />
        )}

        {/* VIEW 4: Daily Ticket Marketplace */}
        {activeTab === 'marketplace' && (
          <Marketplace 
            account={account}
            onConnect={connectWallet}
            chainId={chainId}
            onSwitchNetwork={switchNetwork}
            ticketsCount={ticketsCount}
            dailyTicketsInPlay={dailyTicketsInPlay}
            sundayTicketsInPlay={sundayTicketsInPlay}
            userStakedIrl={userStakedIrl}
            onBuyTicket={handleBuyTicket}
            onListTicket={handleListTicket}
          />
        )}

        {/* VIEW 5: Robinhood Referral Program (Custom Links & +10% Boost) */}
        {activeTab === 'referral' && (
          <ReferralPanel
            account={account}
            onConnect={connectWallet}
            leaderboardInfo={leaderboardInfo}
            activeReferral={activeReferral}
            onApplyReferralCode={(rawCode) => {
              const clean = String(rawCode || '').trim().toLowerCase().replace(/[^a-z0-9_-]/g, '').slice(0, 24);
              if (clean.length >= 3) {
                const resolvedAddr = leaderboardInfo?.referrals?.aliasToAddress?.[clean] || (/^0x[a-fA-F0-9]{40}$/.test(rawCode) ? rawCode : null);
                const refObj = { code: clean, referrerAddress: resolvedAddr };
                setActiveReferral(refObj);
                try { localStorage.setItem('irl_active_referral', JSON.stringify(refObj)); } catch (_) {}
                showToast(`Activated Referral Code @${clean} (+10% Hourly Leaderboard Boost)!`);
              }
            }}
          />
        )}
      </main>

      {/* SLIDE-OVER QUANTUM QUICK-MINT & +EV SIMULATOR DRAWER */}
      {quickMintOpen && (
        <div className="quantum-drawer-backdrop" onClick={() => setQuickMintOpen(false)}>
          <aside className="quantum-quick-drawer" onClick={(e) => e.stopPropagation()}>
            <div className="q-drawer-header">
              <div>
                <span className="q-drawer-kicker">INSTANT UNISWAP V4 EXECUTION</span>
                <h3 className="q-drawer-title">Quantum Quick-Mint &amp; +EV Simulator</h3>
              </div>
              <button
                type="button"
                className="q-drawer-close"
                onClick={() => setQuickMintOpen(false)}
                aria-label="Close Quick-Mint Drawer"
              >
                ×
              </button>
            </div>

            <div className="q-drawer-pass-preview">
              <div className="q-drawer-pass-thumb">
                <img
                  src="/nft_ticket_4.jpg"
                  alt="Genesis VIP Pass"
                  style={{ width: '92px', height: '92px', objectFit: 'cover', borderRadius: '14px', display: 'block' }}
                />
              </div>
              <div className="q-drawer-pass-stats">
                <span className="q-pass-badge">OPENVRF VERIFIED • ERC-721 PASS</span>
                <div className="q-pass-odds-row">
                  <div>
                    <div className="q-pass-odds-big">{drawerDailyOdds}%</div>
                    <span className="q-pass-odds-sub">
                      Tonight&apos;s 24h Draw ({quickMintPack} / {activeDailyPool + quickMintPack} Tickets)
                    </span>
                  </div>
                  <div className="q-pass-odds-divider" />
                  <div>
                    <div className="q-pass-odds-big secondary">{drawerSundayOdds}%</div>
                    <span className="q-pass-odds-sub">
                      Sunday Mega Draw ({quickMintPack} / {activeSundayPool + quickMintPack} Tickets)
                    </span>
                  </div>
                </div>
              </div>
            </div>

            <div className="q-drawer-pack-selector">
              <span className="q-section-label">SELECT VIP TICKET BUNDLE (0.10 ETH VOLUME / TICKET)</span>
              <div className="q-pack-grid">
                {[
                  { count: 1, eth: '0.10', tag: 'Single Pass' },
                  { count: 3, eth: '0.30', tag: 'Optimal +EV' },
                  { count: 6, eth: '0.60', tag: 'Max Daily Cap' },
                ].map((pk) => {
                  const dOdds = ((pk.count / (activeDailyPool + pk.count)) * 100).toFixed(1);
                  const sOdds = ((pk.count / (activeSundayPool + pk.count)) * 100).toFixed(1);
                  return (
                    <button
                      key={pk.count}
                      type="button"
                      onClick={() => setQuickMintPack(pk.count)}
                      className={`q-pack-card ${quickMintPack === pk.count ? 'active' : ''}`}
                    >
                      <span className="q-pack-tag">{pk.tag}</span>
                      <strong className="q-pack-count">+{pk.count} Ticket{pk.count > 1 ? 's' : ''}</strong>
                      <span className="q-pack-eth">~{pk.eth} ETH Vol</span>
                      <span className="q-pack-odds">{dOdds}% Daily • {sOdds}% Sun</span>
                    </button>
                  );
                })}
              </div>
            </div>

            <div className="q-drawer-telemetry-list">
              <div className="q-telemetry-row">
                <span>Daily 24h Jackpot Pool ({activeDailyPool} Active Tickets)</span>
                <strong>{lotteryPotEth} ETH</strong>
              </div>
              <div className="q-telemetry-row">
                <span>Sunday Mega-Jackpot Pool ({activeSundayPool} Active Tickets)</span>
                <strong>{sundayPotEth} ETH</strong>
              </div>
              <div className="q-telemetry-row">
                <span>Instant Swap Cashback (0.4375%)</span>
                <strong>+{drawerCashbackEth} ETH</strong>
              </div>
              <div className="q-telemetry-row">
                <span>Active Referral Boost</span>
                <strong>{activeReferral?.code ? `@${activeReferral.code} (+10% Score)` : 'None (Standard 1.0x)'}</strong>
              </div>
            </div>

            <div className="q-drawer-actions">
              {!account ? (
                <button
                  type="button"
                  onClick={() => {
                    connectWallet();
                  }}
                  className="btn-swap-execute"
                  style={{ width: '100%', padding: '16px' }}
                >
                  Connect Wallet to Mint +{quickMintPack} Tickets
                </button>
              ) : (
                <button
                  type="button"
                  onClick={() => {
                    setQuickMintOpen(false);
                    handleSelectTab('trade');
                    showToast(`Loaded +${quickMintPack} Ticket Swap Pack (~${drawerReqEth} ETH) in Trade Arena!`);
                  }}
                  className="btn-swap-execute"
                  style={{ width: '100%', padding: '16px' }}
                >
                  ⚡ Go to Swap Terminal (~{drawerReqEth} ETH for +{quickMintPack} Tickets)
                </button>
              )}
              <button
                type="button"
                onClick={() => {
                  setQuickMintOpen(false);
                  handleSelectTab('marketplace');
                }}
                className="q-drawer-secondary-btn"
              >
                Or Buy Tickets on P2P Marketplace (2.0% Lottery Tax) →
              </button>
            </div>
          </aside>
        </div>
      )}

      <Footer />
    </div>
  );
}
