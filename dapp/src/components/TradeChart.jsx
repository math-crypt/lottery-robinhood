import React, { useState, useEffect } from 'react';
import { ethers } from 'ethers';
import { 
  ArrowDownUpIcon, 
  SlidersIcon, 
  CheckIcon, 
  ShieldCheckIcon, 
  TicketIcon,
  ExternalLinkIcon 
} from './Icons';
import {
  CONTRACT_ADDRESSES,
  ROBINHOOD_CHAIN,
  V4_INFRASTRUCTURE,
  V4_LIVE_TEST_POOLS,
} from '../constants/contracts';

const RPC_URL = 'https://rpc.mainnet.chain.robinhood.com';
const DEFAULT_IRL_PER_ETH = 58_110_586;
const DEFAULT_IRL_PRICE_USD = 0.000045;

const coder = ethers.AbiCoder.defaultAbiCoder();
const routerIface = new ethers.Interface([
  'function execute(bytes commands, bytes[] inputs, uint256 deadline) payable',
]);
const quoterIface = new ethers.Interface([
  'function quoteExactInputSingle(tuple(tuple(address currency0, address currency1, uint24 fee, int24 tickSpacing, address hooks) poolKey, bool zeroForOne, uint128 exactAmount, bytes hookData) params) external returns (uint256 amountOut, uint256 gasEstimate)',
]);
const stateViewIface = new ethers.Interface([
  'function getSlot0(bytes32 poolId) view returns (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee)',
]);
const erc20Iface = new ethers.Interface([
  'function allowance(address owner, address spender) view returns (uint256)',
  'function approve(address spender, uint256 value) returns (bool)',
]);
const permit2Iface = new ethers.Interface([
  'function allowance(address user, address token, address spender) view returns (uint160 amount, uint48 expiration, uint48 nonce)',
  'function approve(address token, address spender, uint160 amount, uint48 expiration) external',
]);

async function rpcCall(method, params) {
  const res = await fetch(RPC_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ jsonrpc: '2.0', id: 1, method, params }),
  });
  const json = await res.json();
  if (json.error) {
    throw new Error(json.error.message || 'RPC error');
  }
  return json.result;
}

async function waitForTxReceipt(txHash, maxAttempts = 30) {
  for (let i = 0; i < maxAttempts; i++) {
    try {
      const rec = await rpcCall('eth_getTransactionReceipt', [txHash]);
      if (rec && rec.blockNumber) {
        return rec;
      }
    } catch (_) {}
    await new Promise((r) => setTimeout(r, 1500));
  }
  return null;
}

export default function TradeChart({ 
  account, 
  onConnect, 
  chainId, 
  onSwitchNetwork, 
  userBalanceEth = "0.0000",
  userBalanceIrl = "0", 
  userStakedIrl = "0",
  dailyTicketsInPlay = 6,
  sundayPotEth = "0.700",
  lotteryPotEth = "0.004",
  activeReferral = null,
  onSwapSuccess 
}) {
  const isWrongNetwork = account && chainId !== ROBINHOOD_CHAIN.id;
  const [tradeMode, setTradeMode] = useState('buy'); // 'buy' or 'sell'
  const [payAmount, setPayAmount] = useState('');
  const [slippage, setSlippage] = useState('4.5');
  const [showSettings, setShowSettings] = useState(false);
  const [isSwapping, setIsSwapping] = useState(false);
  const [swapStepText, setSwapStepText] = useState('');
  const [swapToast, setSwapToast] = useState(null);
  const [liveDexPair, setLiveDexPair] = useState(null);
  const [isFetchingDex, setIsFetchingDex] = useState(false);
  const [liveIrlPerEth, setLiveIrlPerEth] = useState(DEFAULT_IRL_PER_ETH);
  const [quotedOutput, setQuotedOutput] = useState(null);

  const activePool = V4_LIVE_TEST_POOLS.IRL;

  // Poll on-chain StateView.getSlot0(POOL_ID)
  useEffect(() => {
    let cancelled = false;
    async function syncPoolState() {
      try {
        const slot0Data = stateViewIface.encodeFunctionData('getSlot0', [V4_INFRASTRUCTURE.POOL_ID]);
        const batch = [
          { jsonrpc: '2.0', id: 1, method: 'eth_call', params: [{ to: V4_INFRASTRUCTURE.STATE_VIEW, data: slot0Data }, 'latest'] },
        ];
        const resp = await fetch(RPC_URL, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(batch),
        });
        if (!resp.ok) return;
        const arr = await resp.json();
        const byId = {};
        for (const item of arr) byId[item.id] = item.result;

        if (byId[1] && byId[1] !== '0x') {
          const [sqrtPriceX96] = stateViewIface.decodeFunctionResult('getSlot0', byId[1]);
          const Q96 = 2n ** 96n;
          const rate = Number((sqrtPriceX96 * sqrtPriceX96 * 10000n) / (Q96 * Q96)) / 10000;
          if (!cancelled && rate > 0) {
            setLiveIrlPerEth(rate);
          }
        }
      } catch (_) {}
    }
    syncPoolState();
    const timer = setInterval(syncPoolState, 6000);
    return () => {
      cancelled = true;
      clearInterval(timer);
    };
  }, []);

  // Fetch live DexScreener metrics for $IRL Uniswap V4 Hook pool on Robinhood Chain (4663)
  useEffect(() => {
    let cancelled = false;
    async function fetchDexData() {
      setIsFetchingDex(true);
      try {
        const pairResp = await fetch(`https://api.dexscreener.com/latest/dex/pairs/robinhood/${activePool.poolId}`);
        if (pairResp.ok) {
          const pairJson = await pairResp.json();
          const foundPair = pairJson?.pair || pairJson?.pairs?.[0] || null;
          if (!cancelled && foundPair) {
            setLiveDexPair(foundPair);
            setIsFetchingDex(false);
            return;
          }
        }
        const tokenResp = await fetch(`https://api.dexscreener.com/latest/dex/tokens/${activePool.tokenAddress}`);
        if (tokenResp.ok) {
          const tokenJson = await tokenResp.json();
          const rhPair = (tokenJson?.pairs || []).find((p) => p.chainId === 'robinhood') || tokenJson?.pairs?.[0] || null;
          if (!cancelled) {
            setLiveDexPair(rhPair);
          }
        }
      } catch (_) {
        if (!cancelled) setLiveDexPair(null);
      } finally {
        if (!cancelled) setIsFetchingDex(false);
      }
    }
    fetchDexData();
    const interval = setInterval(fetchDexData, 15000);
    return () => {
      cancelled = true;
      clearInterval(interval);
    };
  }, [activePool.poolId, activePool.tokenAddress]);

  const activePriceUsd = liveDexPair?.priceUsd ? parseFloat(liveDexPair.priceUsd) : DEFAULT_IRL_PRICE_USD;
  const activeChange24h = liveDexPair?.priceChange?.h24 !== undefined ? parseFloat(liveDexPair.priceChange.h24) : 0.0;
  const activeVol24h = liveDexPair?.volume?.h24 !== undefined ? parseFloat(liveDexPair.volume.h24) : 0;
  const activeMarketCap = liveDexPair?.marketCap || liveDexPair?.fdv || Math.round(activePriceUsd * 1_000_000_000);
  const activeLiquidityUsd = liveDexPair?.liquidity?.usd || 0;

  const numericPay = parseFloat(payAmount) || 0;
  const isBuy = tradeMode === 'buy';

  // Live On-Chain V4Quoter quote whenever payAmount or tradeMode changes
  useEffect(() => {
    let cancelled = false;
    if (!numericPay || numericPay <= 0) {
      setQuotedOutput(null);
      return;
    }
    const timer = setTimeout(async () => {
      try {
        const exactAmount = ethers.parseEther(String(numericPay));
        if (exactAmount <= 0n) return;
        const callData = quoterIface.encodeFunctionData('quoteExactInputSingle', [
          {
            poolKey: {
              currency0: V4_INFRASTRUCTURE.WETH,
              currency1: CONTRACT_ADDRESSES.TOKEN,
              fee: 3000,
              tickSpacing: 60,
              hooks: CONTRACT_ADDRESSES.HOOK,
            },
            zeroForOne: isBuy,
            exactAmount,
            hookData: '0x',
          },
        ]);
        const resHex = await rpcCall('eth_call', [{ to: V4_INFRASTRUCTURE.V4_QUOTER, data: callData }, 'latest']);
        const [amountOutWei] = quoterIface.decodeFunctionResult('quoteExactInputSingle', resHex);
        if (!cancelled) {
          setQuotedOutput(Number(ethers.formatEther(amountOutWei)));
        }
      } catch (_) {
        if (!cancelled) setQuotedOutput(null);
      }
    }, 220);
    return () => {
      cancelled = true;
      clearTimeout(timer);
    };
  }, [numericPay, isBuy]);

  // Staking Volume Boost (0% to +50% linearly up to 20,000,000 $IRL = 2% supply)
  const MAX_STAKING_CAP = 20_000_000;
  const currentStaked = Number(userStakedIrl) || 0;
  const stakingBonusPct = Math.min(50, (currentStaked / MAX_STAKING_CAP) * 50);
  const rawEthVolume = isBuy ? numericPay : (numericPay / liveIrlPerEth);
  const boostedEthVolume = rawEthVolume * (1 + stakingBonusPct / 100);
  const maxDailyVolumeTickets = Math.min(10, 6 + Math.floor((currentStaked * 4) / MAX_STAKING_CAP));
  const earnedTicketsFromSwap = Math.min(maxDailyVolumeTickets, Math.floor(boostedEthVolume / 0.10));
  const cashbackRate = 0.004375;
  const estimatedHourlyCashbackEth = rawEthVolume * cashbackRate;

  // Hook Tax: 4.0% Standard Tax
  const hookTaxPercentage = 4.0;
  const taxFactor = (100 - hookTaxPercentage) / 100;

  let estimatedReceive = 0;
  if (numericPay > 0) {
    if (quotedOutput !== null && quotedOutput > 0) {
      estimatedReceive = quotedOutput;
    } else if (isBuy) {
      estimatedReceive = numericPay * liveIrlPerEth * taxFactor;
    } else {
      estimatedReceive = (numericPay / liveIrlPerEth) * taxFactor;
    }
  }

  // Set quick percentage from real wallet balance
  const handleQuickPercent = (pct) => {
    if (isBuy) {
      const rawEthBal = Math.max(0, parseFloat(userBalanceEth) || 0);
      const spendableEth = pct === 100 ? Math.max(0, rawEthBal - 0.0005) : rawEthBal * (pct / 100);
      setPayAmount(spendableEth > 0 ? spendableEth.toFixed(4) : '0');
    } else {
      const maxIrl = Math.max(0, Number(userBalanceIrl) || 0);
      const amount = Math.floor(maxIrl * (pct / 100));
      setPayAmount(amount > 0 ? amount.toString() : '0');
    }
  };

  // Switch Trade Direction
  const toggleDirection = () => {
    setTradeMode((prev) => (prev === 'buy' ? 'sell' : 'buy'));
    setPayAmount('');
    setQuotedOutput(null);
  };

  // Execute Real On-Chain Uniswap V4 Swap via UniversalRouter
  const handleExecuteSwap = async () => {
    if (!account) {
      onConnect();
      return;
    }
    if (isWrongNetwork) {
      onSwitchNetwork();
      return;
    }
    if (!numericPay || numericPay <= 0) {
      setSwapToast("Please enter a valid positive swap amount.");
      setTimeout(() => setSwapToast(null), 3000);
      return;
    }

    setIsSwapping(true);
    try {
      const amountInWei = ethers.parseEther(String(numericPay));
      const deadlineSec = BigInt(Math.floor(Date.now() / 1000) + 1200);
      const ADDRESS_THIS = '0x0000000000000000000000000000000000000002';
      const CONTRACT_BALANCE = 1n << 255n;
      const refAddr = activeReferral?.referrerAddress && ethers.isAddress(activeReferral.referrerAddress)
        ? activeReferral.referrerAddress
        : ethers.ZeroAddress;
      const refAliasHex = activeReferral?.code
        ? ethers.encodeBytes32String(String(activeReferral.code).slice(0, 31))
        : ethers.ZeroHash;
      const hookData = (refAddr !== ethers.ZeroAddress || refAliasHex !== ethers.ZeroHash)
        ? coder.encode(['address', 'address', 'bytes32'], [account, refAddr, refAliasHex])
        : coder.encode(['address'], [account]);

      const slipPct = Math.max(0.5, parseFloat(slippage) || 4.5);
      const estOutWei = estimatedReceive > 0
        ? ethers.parseEther(isBuy ? String(Math.floor(estimatedReceive)) : estimatedReceive.toFixed(18))
        : 0n;
      const minAmountOutWei = (estOutWei * BigInt(Math.max(0, Math.floor((100 - slipPct) * 100)))) / 10000n;

      if (isBuy) {
        // BUY $IRL WITH NATIVE ETH (0x0b WRAP_ETH + 0x10 V4_SWAP)
        setSwapStepText('Confirm Swap in Wallet...');
        const wrapInput = coder.encode(['address', 'uint256'], [ADDRESS_THIS, CONTRACT_BALANCE]);
        const exactInputSingleParams = coder.encode(
          [
            'tuple(tuple(address currency0, address currency1, uint24 fee, int24 tickSpacing, address hooks) poolKey, bool zeroForOne, uint128 amountIn, uint128 amountOutMinimum, bytes hookData)',
          ],
          [
            {
              poolKey: {
                currency0: V4_INFRASTRUCTURE.WETH,
                currency1: CONTRACT_ADDRESSES.TOKEN,
                fee: 3000,
                tickSpacing: 60,
                hooks: CONTRACT_ADDRESSES.HOOK,
              },
              zeroForOne: true,
              amountIn: amountInWei,
              amountOutMinimum: minAmountOutWei,
              hookData,
            },
          ]
        );
        const settleParams = coder.encode(['address', 'uint256', 'bool'], [V4_INFRASTRUCTURE.WETH, 0n, false]);
        const takeParams = coder.encode(['address', 'address', 'uint256'], [CONTRACT_ADDRESSES.TOKEN, account, 0n]);
        const v4SwapInput = coder.encode(
          ['bytes', 'bytes[]'],
          ['0x060b0e', [exactInputSingleParams, settleParams, takeParams]]
        );
        const calldata = routerIface.encodeFunctionData('execute', [
          '0x0b10',
          [wrapInput, v4SwapInput],
          deadlineSec,
        ]);

        const txHash = await window.ethereum.request({
          method: 'eth_sendTransaction',
          params: [
            {
              from: account,
              to: V4_INFRASTRUCTURE.UNIVERSAL_ROUTER,
              value: '0x' + amountInWei.toString(16),
              data: calldata,
            },
          ],
        });

        setSwapStepText('Confirming on Robinhood Chain...');
        await waitForTxReceipt(txHash);

        const outputFormatted = `${Math.floor(estimatedReceive).toLocaleString()} $IRL`;
        setSwapToast(`Buy Confirmed! Received ~${outputFormatted} (TX: ${txHash.slice(0, 10)}...)`);
        setTimeout(() => setSwapToast(null), 5000);
      } else {
        // SELL $IRL FOR NATIVE ETH VIA PERMIT2 + UNIVERSAL_ROUTER (0x10 V4_SWAP + 0x0c UNWRAP_WETH)
        // Step 1: Check ERC20 allowance to Permit2
        setSwapStepText('Checking $IRL Allowance...');
        const allowCall = erc20Iface.encodeFunctionData('allowance', [account, V4_INFRASTRUCTURE.PERMIT2]);
        const allowHex = await rpcCall('eth_call', [{ to: CONTRACT_ADDRESSES.TOKEN, data: allowCall }, 'latest']);
        const [erc20Allowance] = erc20Iface.decodeFunctionResult('allowance', allowHex);

        if (erc20Allowance < amountInWei) {
          setSwapStepText('Step 1/3: Approve $IRL for Permit2...');
          const approveData = erc20Iface.encodeFunctionData('approve', [
            V4_INFRASTRUCTURE.PERMIT2,
            ethers.MaxUint256,
          ]);
          const appTxHash = await window.ethereum.request({
            method: 'eth_sendTransaction',
            params: [{ from: account, to: CONTRACT_ADDRESSES.TOKEN, data: approveData }],
          });
          await waitForTxReceipt(appTxHash);
        }

        // Step 2: Check Permit2 allowance to UniversalRouter
        const p2AllowCall = permit2Iface.encodeFunctionData('allowance', [
          account,
          CONTRACT_ADDRESSES.TOKEN,
          V4_INFRASTRUCTURE.UNIVERSAL_ROUTER,
        ]);
        const p2AllowHex = await rpcCall('eth_call', [{ to: V4_INFRASTRUCTURE.PERMIT2, data: p2AllowCall }, 'latest']);
        const [p2Amount, p2Exp] = permit2Iface.decodeFunctionResult('allowance', p2AllowHex);
        const nowSec = BigInt(Math.floor(Date.now() / 1000));

        if (p2Amount < amountInWei || p2Exp <= nowSec + 60n) {
          setSwapStepText('Step 2/3: Authorize UniversalRouter...');
          const maxUint160 = (1n << 160n) - 1n;
          const maxUint48 = (1n << 48n) - 1n;
          const p2ApproveData = permit2Iface.encodeFunctionData('approve', [
            CONTRACT_ADDRESSES.TOKEN,
            V4_INFRASTRUCTURE.UNIVERSAL_ROUTER,
            maxUint160,
            maxUint48,
          ]);
          const p2TxHash = await window.ethereum.request({
            method: 'eth_sendTransaction',
            params: [{ from: account, to: V4_INFRASTRUCTURE.PERMIT2, data: p2ApproveData }],
          });
          await waitForTxReceipt(p2TxHash);
        }

        // Step 3: Execute V4 Sell ($IRL -> WETH -> Unwrap to Native ETH)
        setSwapStepText('Confirm Sell in Wallet...');
        const exactInputSingleParams = coder.encode(
          [
            'tuple(tuple(address currency0, address currency1, uint24 fee, int24 tickSpacing, address hooks) poolKey, bool zeroForOne, uint128 amountIn, uint128 amountOutMinimum, bytes hookData)',
          ],
          [
            {
              poolKey: {
                currency0: V4_INFRASTRUCTURE.WETH,
                currency1: CONTRACT_ADDRESSES.TOKEN,
                fee: 3000,
                tickSpacing: 60,
                hooks: CONTRACT_ADDRESSES.HOOK,
              },
              zeroForOne: false,
              amountIn: amountInWei,
              amountOutMinimum: minAmountOutWei,
              hookData,
            },
          ]
        );
        const settleParams = coder.encode(['address', 'uint256', 'bool'], [CONTRACT_ADDRESSES.TOKEN, 0n, true]);
        const takeParams = coder.encode(['address', 'address', 'uint256'], [V4_INFRASTRUCTURE.WETH, ADDRESS_THIS, 0n]);
        const v4SwapInput = coder.encode(
          ['bytes', 'bytes[]'],
          ['0x060b0e', [exactInputSingleParams, settleParams, takeParams]]
        );
        const unwrapInput = coder.encode(['address', 'uint256'], [account, minAmountOutWei]);
        const sellCalldata = routerIface.encodeFunctionData('execute', [
          '0x100c',
          [v4SwapInput, unwrapInput],
          deadlineSec,
        ]);

        const txHash = await window.ethereum.request({
          method: 'eth_sendTransaction',
          params: [
            {
              from: account,
              to: V4_INFRASTRUCTURE.UNIVERSAL_ROUTER,
              data: sellCalldata,
            },
          ],
        });

        setSwapStepText('Confirming on Robinhood Chain...');
        await waitForTxReceipt(txHash);

        const outputFormatted = `${estimatedReceive.toFixed(5)} ETH`;
        setSwapToast(`Sell Confirmed! Received ~${outputFormatted} (TX: ${txHash.slice(0, 10)}...)`);
        setTimeout(() => setSwapToast(null), 5000);
      }

      if (onSwapSuccess) {
        onSwapSuccess({
          isBuy,
          payAmount: numericPay,
          receiveAmount: estimatedReceive,
          rawEthVolume,
          boostedEthVolume,
          earnedTickets: earnedTicketsFromSwap,
        });
      }
      setPayAmount('');
      setQuotedOutput(null);
    } catch (err) {
      const msg = err?.message || 'Swap transaction cancelled or failed.';
      setSwapToast(msg.length > 110 ? msg.slice(0, 110) + '...' : msg);
      setTimeout(() => setSwapToast(null), 4500);
    } finally {
      setIsSwapping(false);
      setSwapStepText('');
    }
  };

  const priceDecimals = activePriceUsd >= 0.01 ? 4 : activePriceUsd >= 0.0001 ? 6 : 7;

  return (
    <div className="trade-chart-sanctuary">
      {/* Toast Notification */}
      {swapToast && (
        <div className="trade-toast">
          <CheckIcon size={18} color="#8ce2aa" />
          <span>{swapToast}</span>
        </div>
      )}

      {/* Main Grid: Chart on Left, Swap Terminal on Right */}
      <div className="trade-grid">
        {/* Left Column: Live Market Stats & Candlestick Chart */}
        <section className="chart-panel">
          {/* Header Stats Bar */}
          <div className="market-stats-header">
            <div className="market-pair-title" style={{ flexWrap: 'wrap', gap: '8px' }}>
              <span className="pair-names">{activePool.pairTitle}</span>
              <span className="pool-badge">Uniswap V4 Hook • Live</span>
            </div>

            <div className="market-metrics-row">
              <div className="metric-pill">
                <span className="metric-label">PRICE</span>
                <span className="metric-value highlight">${activePriceUsd.toFixed(priceDecimals)}</span>
              </div>
              <div className="metric-pill">
                <span className="metric-label">24H CHANGE</span>
                <span className="metric-value" style={{ color: activeChange24h >= 0 ? '#4ADE80' : '#F87171' }}>
                  {liveDexPair ? `${activeChange24h >= 0 ? '+' : ''}${activeChange24h.toFixed(2)}%` : '+0.00% (Live)'}
                </span>
              </div>
              <div className="metric-pill">
                <span className="metric-label">CA / HOOK</span>
                <span className="metric-value">
                  {`${activePool.tokenAddress.slice(0, 6)}...${activePool.tokenAddress.slice(-4)}`}
                </span>
              </div>
              <div className="metric-pill">
                <span className="metric-label">LIQUIDITY</span>
                <span className="metric-value">
                  {liveDexPair && activeLiquidityUsd > 0 ? `$${Math.round(activeLiquidityUsd).toLocaleString()}` : '90% Locked LP'}
                </span>
              </div>
              <div className="metric-pill">
                <span className="metric-label">24H VOLUME</span>
                <span className="metric-value">
                  {liveDexPair ? `$${Math.round(activeVol24h).toLocaleString()}` : 'Live on V4'}
                </span>
              </div>
              <div className="metric-pill">
                <span className="metric-label">MARKET CAP</span>
                <span className="metric-value">
                  ${Math.round(activeMarketCap).toLocaleString()}
                </span>
              </div>
            </div>
          </div>

          {/* Chart Display Area: Official DexScreener V4 Live Chart with Recessed Obsidian Bezel */}
          <div className="dexscreener-obsidian-bezel">
            <iframe
              title={`DexScreener ${activePool.pairTitle}`}
              src={`https://dexscreener.com/robinhood/${activePool.poolId}?embed=1&theme=dark&trades=0&info=0`}
              style={{ width: '100%', height: '390px', border: 'none', display: 'block' }}
              allow="clipboard-write"
            />

            <div className="dexscreener-footer-toolbar">
              <span className="dex-pool-id">
                Robinhood Chain (4663) V4 PoolId: <code>{activePool.poolId.slice(0, 14)}...{activePool.poolId.slice(-8)}</code>
                {isFetchingDex ? ' (Syncing...)' : ' • Live On-Chain'}
              </span>
              <div className="dex-footer-actions">
                <a
                  href={activePool.dexscreenerUrl}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="dex-footer-link"
                >
                  <span>Open DexScreener ({activePool.symbol})</span>
                  <ExternalLinkIcon size={12} />
                </a>
                <a
                  href={activePool.programmableUrl}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="dex-footer-link"
                >
                  <span>Open Programmable.market</span>
                  <ExternalLinkIcon size={12} />
                </a>
              </div>
            </div>
          </div>

          {/* Bottom Module: LIVE +EV PROBABILITY CALCULATOR paired with 4-bar tax split indicator */}
          <div className="trade-bottom-ev-module">
            {/* Live +EV Win Probability Calculator */}
            <div className="trade-ev-card">
              <div className="trade-ev-header">
                <span className="trade-ev-title">🚨 LIVE +EV PROBABILITY CALCULATOR</span>
                <span className="trade-ev-badge">{Math.max(0, Number(dailyTicketsInPlay) || 0)} Tickets Today</span>
              </div>
              <div className="trade-ev-body">
                Minting <strong>{earnedTicketsFromSwap > 0 ? earnedTicketsFromSwap : 1} ticket{(earnedTicketsFromSwap > 1) ? 's' : ''}</strong> right now gives you a{' '}
                <strong style={{ color: '#4ADE80' }}>
                  {(((earnedTicketsFromSwap > 0 ? earnedTicketsFromSwap : 1) / (Math.max(0, Number(dailyTicketsInPlay) || 0) + (earnedTicketsFromSwap > 0 ? earnedTicketsFromSwap : 1))) * 100).toFixed(1)}% chance
                </strong>{' '}
                to win Tonight&apos;s 00:00 UTC Daily Draw ({lotteryPotEth} ETH) + Sunday&apos;s{' '}
                <strong>{sundayPotEth} ETH (~${Math.round((parseFloat(sundayPotEth) || 0.7) * 2640).toLocaleString()})</strong> Mega-Jackpot!
              </div>
            </div>

            {/* Visual 4-Bar Tax Split Indicator */}
            <div className="tax-split-widget">
              <div className="tax-split-header">
                <span className="tax-split-title">UNISWAP V4 HOOK TAX (4.00%)</span>
                <span className="tax-split-sub">100% On-Chain Automated</span>
              </div>
              <div className="tax-split-bar-track">
                <div className="tax-bar-segment seg-hourly" style={{ width: '31.25%' }} title="1.25% Hourly Stream" />
                <div className="tax-bar-segment seg-jackpot" style={{ width: '31.25%' }} title="1.25% Daily & Sunday Lotteries" />
                <div className="tax-bar-segment seg-vault" style={{ width: '30%' }} title="1.20% Protocol & Buyback" />
                <div className="tax-bar-segment seg-prog" style={{ width: '7.5%' }} title="0.30% Programmable.market" />
              </div>
              <div className="tax-split-legend">
                <span className="legend-chip"><span className="dot dot-hourly" /> 1.25% Hourly</span>
                <span className="legend-chip"><span className="dot dot-jackpot" /> 1.25% Jackpots</span>
                <span className="legend-chip"><span className="dot dot-vault" /> 1.20% Vault+Burn</span>
                <span className="legend-chip"><span className="dot dot-prog" /> 0.30% Prog</span>
              </div>
            </div>
          </div>
        </section>

        {/* Right Column: Swap / Trade Terminal */}
        <section className="swap-terminal-panel">
          <div className="swap-header">
            <div className="swap-title-group">
              <span className="swap-heading">Trade $IRL</span>
              <span className="swap-subheading">Uniswap V4 UniversalRouter Execution</span>
            </div>
            <button 
              onClick={() => setShowSettings(!showSettings)} 
              className={`btn-settings-toggle ${showSettings ? 'active' : ''}`}
              title="Trade settings & slippage"
            >
              <SlidersIcon size={16} />
            </button>
          </div>

          {/* Slippage Settings Drawer */}
          {showSettings && (
            <div className="slippage-settings-box">
              <span className="settings-label">Slippage Tolerance:</span>
              <div className="slippage-options">
                {['1.0', '4.5', '10.5'].map((val) => (
                  <button
                    key={val}
                    onClick={() => setSlippage(val)}
                    className={`slippage-pill ${slippage === val ? 'active' : ''}`}
                  >
                    {val}% {val === '10.5' ? '(<$100k MC / <24h)' : val === '4.5' ? '(≥$100k MC / ≥24h)' : ''}
                  </button>
                ))}
              </div>
              <span className="settings-hint">
                4.5% is recommended for Standard Cruise mode (4% V4 Hook Tax).
              </span>
            </div>
          )}

          {/* Buy / Sell Mode Tabs */}
          <div className="trade-type-tabs">
            <button
              onClick={() => { setTradeMode('buy'); setPayAmount(''); setQuotedOutput(null); }}
              className={`type-tab-btn buy ${isBuy ? 'active' : ''}`}
            >
              Buy $IRL
            </button>
            <button
              onClick={() => { setTradeMode('sell'); setPayAmount(''); setQuotedOutput(null); }}
              className={`type-tab-btn sell ${!isBuy ? 'active' : ''}`}
            >
              Sell $IRL
            </button>
          </div>

          {/* Pay Input Box */}
          <div className="swap-box">
            <div className="swap-box-header">
              <span className="box-role-label">You Pay</span>
              <span className="box-balance">
                Balance: {isBuy ? `${userBalanceEth} ETH` : `${Number(userBalanceIrl).toLocaleString()} $IRL`}
              </span>
            </div>

            <div className="swap-input-row">
              <input
                type="number"
                placeholder="0.0"
                value={payAmount}
                onChange={(e) => setPayAmount(e.target.value)}
                className="swap-numeric-input"
                min="0"
                step="any"
              />
              <div className="token-badge">
                <span className="token-symbol">{isBuy ? 'ETH' : '$IRL'}</span>
              </div>
            </div>

            {/* Quick Percentage Pills */}
            <div className="quick-pct-row">
              {[25, 50, 75, 100].map((pct) => (
                <button
                  key={pct}
                  onClick={() => handleQuickPercent(pct)}
                  className="quick-pct-btn"
                >
                  {pct === 100 ? 'MAX' : `${pct}%`}
                </button>
              ))}
            </div>
          </div>

          {/* Direction Switch Button */}
          <div className="swap-divider">
            <button 
              onClick={toggleDirection} 
              className="btn-flip-direction"
              title="Reverse swap direction"
            >
              <ArrowDownUpIcon size={16} />
            </button>
          </div>

          {/* Receive Output Box */}
          <div className="swap-box">
            <div className="swap-box-header">
              <span className="box-role-label">You Receive (Est.)</span>
              <span className="box-balance">
                Rate: 1 ETH ≈ {Math.round(liveIrlPerEth).toLocaleString()} $IRL
              </span>
            </div>

            <div className="swap-input-row">
              <input
                type="text"
                readOnly
                value={estimatedReceive > 0 ? (isBuy ? Math.floor(estimatedReceive).toLocaleString() : estimatedReceive.toFixed(5)) : '0.0'}
                className="swap-numeric-input read-only"
              />
              <div className="token-badge">
                <span className="token-symbol">{isBuy ? '$IRL' : 'ETH'}</span>
              </div>
            </div>
          </div>

          {/* Compact Swap Details (3-Line Summary + Collapsible Tax Details) */}
          <div className="trade-transparency-card">
            {/* Line 1: Instant Cashback Rebate */}
            <div className="transparency-row">
              <span className="t-label">Instant Cashback Rebate (0.4375%)</span>
              <span className="t-val green">
                {estimatedHourlyCashbackEth > 0 ? `+${estimatedHourlyCashbackEth.toFixed(5)} WETH` : '0.00000 WETH'}
              </span>
            </div>

            {/* Line 2: Minimum Output */}
            <div className="transparency-row">
              <span className="t-label">Minimum Output ({slippage}% Slippage)</span>
              <span className="t-val">
                {estimatedReceive > 0 
                  ? (isBuy 
                      ? `${Math.floor(estimatedReceive * (1 - parseFloat(slippage)/100)).toLocaleString()} $IRL`
                      : `${(estimatedReceive * (1 - parseFloat(slippage)/100)).toFixed(5)} ETH`)
                  : '0.0'}
              </span>
            </div>

            {/* Line 3: Uniswap V4 Hook Tax (4.00%) with Collapsible Drawer */}
            <details className="swap-tax-details-drawer">
              <summary className="transparency-row swap-tax-summary">
                <span className="t-label">Uniswap V4 Hook Tax (4.00%)</span>
                <span className="t-val highlight">
                  {hookTaxPercentage.toFixed(2)}% <span className="drawer-indicator">▾</span>
                </span>
              </summary>
              <div className="tax-sub-breakdown">
                <div className="tax-sub-item">
                  <span>↳ Hourly Stream (Top 10 / Cashback / Stakers):</span>
                  <span className="highlight">1.25%</span>
                </div>
                <div className="tax-sub-item">
                  <span>↳ Daily 24h &amp; Sunday Mega-Jackpot (OpenVRF):</span>
                  <span className="highlight">1.25%</span>
                </div>
                <div className="tax-sub-item">
                  <span>↳ Protocol Vault (1.00% Upkeep + 0.20% Hourly Buyback):</span>
                  <span>1.20%</span>
                </div>
                <div className="tax-sub-item">
                  <span>↳ Programmable.market (Platform Fee):</span>
                  <span className="highlight-green">0.30%</span>
                </div>
                <div className="tax-buyback-note">
                  🔥 <strong>0.20% Automated Buyback:</strong> Accumulated &amp; burned hourly to <code>0xdead</code>.
                </div>
              </div>
            </details>

            {/* Extra Qualification or Referral Badges */}
            {earnedTicketsFromSwap > 0 && (
              <div className="lottery-qualification-badge">
                <TicketIcon size={14} color="#E6C2A5" />
                <span>+{earnedTicketsFromSwap} Daily NFT Lottery Ticket{earnedTicketsFromSwap > 1 ? 's' : ''} earned ({boostedEthVolume.toFixed(4)} WETH)!</span>
              </div>
            )}

            {activeReferral?.code && (
              <div className="swap-referral-badge">
                <span>🔗 Referral Link Active: <code>?ref={activeReferral.code}</code></span>
                <strong>+10% Score Boost</strong>
              </div>
            )}
          </div>

          {/* Main Swap CTA Button */}
          {!account ? (
            <button onClick={onConnect} className="btn-terminal-cta">
              Connect Wallet to Trade
            </button>
          ) : isWrongNetwork ? (
            <button onClick={onSwitchNetwork} className="btn-terminal-cta warning">
              Switch to Robinhood Chain
            </button>
          ) : (
            <button 
              onClick={handleExecuteSwap} 
              disabled={isSwapping || !numericPay || numericPay <= 0}
              className={`btn-terminal-cta ${isBuy ? 'buy' : 'sell'}`}
            >
              {isSwapping 
                ? (swapStepText || 'Processing V4 Hook Swap...') 
                : isBuy 
                  ? `Swap ETH for $IRL` 
                  : `Swap $IRL for ETH`}
            </button>
          )}
        </section>
      </div>
    </div>
  );
}
