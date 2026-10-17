export const ROBINHOOD_CHAIN = {
  id: 4663,
  name: 'Robinhood Chain',
  network: 'robinhood-l2',
  nativeCurrency: {
    name: 'Ether',
    symbol: 'ETH',
    decimals: 18,
  },
  rpcUrls: {
    default: {
      http: [
        'https://rpc.mainnet.chain.robinhood.com',
        'https://robinhood-rpc.publicnode.com',
      ],
    },
    public: {
      http: [
        'https://rpc.mainnet.chain.robinhood.com',
        'https://robinhood-rpc.publicnode.com',
      ],
    },
  },
  blockExplorers: {
    default: { name: 'Robinhood Blockscout', url: 'https://robinhoodchain.blockscout.com' },
  },
};

export const DETERMINISTIC_LAUNCH_ADDRESSES = {
  TOKEN: '0xf7a2F5554C57C216F1831AA5C8ed3C46727eFE2B', // InternetRobinLottery ($IRL) - Deterministic CREATE2
  HOOK: '0xAb64c6Eb29a6bb8488cb1fcAB1ca11C5e28bC0cc', // IRLUniswapV4Hook (0x00CC flags) - Deterministic CREATE2
  STAKING: '0x15958AC04ABA8D58C21BfD2760315A6a7D9E395d', // IRLStaking (Real Yield Sanctuary) - Deterministic CREATE2
  TICKETS: '0x837170cDdED801F491855405CbcfDA1211d812D7', // IRLTicketNFT (ERC-721 + P2P Marketplace) - Deterministic CREATE2
  MARKETING_VAULT: '0xC463C57029A5F18f3A6B080AE7ef4e9B3A4F0073', // IRLMarketingVault (90% Permanent LP + 10% Conditional Vault)
  OPENVRF_ROUTER: '0x001d6D0934d1abca6Da8F2FE82b2829E60cBeb0f', // OpenVRF (Drand quicknet BLS12-381 Coordinator)
  SHERWOOD_GUILD: '0x7cAbcd316cC661b78c331b04A5EA929D5c97347c', // IRLSherwoodGuildVault (Small-Stakers Co-Staking & Shared Lottery Pool)
};

// Live Mainnet Deployed Addresses on Robinhood Chain (4663)
export const CONTRACT_ADDRESSES = {
  TOKEN: '0xf7a2F5554C57C216F1831AA5C8ed3C46727eFE2B',
  HOOK: '0xAb64c6Eb29a6bb8488cb1fcAB1ca11C5e28bC0cc',
  STAKING: '0x15958AC04ABA8D58C21BfD2760315A6a7D9E395d',
  TICKETS: '0x837170cDdED801F491855405CbcfDA1211d812D7',
  MARKETING_VAULT: '0xC463C57029A5F18f3A6B080AE7ef4e9B3A4F0073',
  OPENVRF_ROUTER: '0x001d6D0934d1abca6Da8F2FE82b2829E60cBeb0f',
  SHERWOOD_GUILD: '0x7cAbcd316cC661b78c331b04A5EA929D5c97347c',
};

export const V4_INFRASTRUCTURE = {
  POOL_ID: '0x1848c9b63c7733c421b2db31bcb606ad75d505d281f7377dc170b082dbe989cb',
  WETH: '0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73',
  POOL_MANAGER: '0x8366a39CC670B4001A1121B8F6A443A643e40951',
  POSITION_MANAGER: '0x4529A01c7A0410167c5740C487A8DE60232617bf',
  STATE_VIEW: '0xF3334192D15450CdD385c8B70e03f9A6bD9E673b',
  UNIVERSAL_ROUTER: '0x53bf6b0684ec7ef91e1387da3d1a1769bc5a6f77',
  PROGRAMMABLE_UNIVERSAL_ROUTER: '0x06AfBA43Fd06227fA663b0DAecF536f6EaA6bf99',
  V4_QUOTER: '0x8Dc178eFB8111BB0973Dd9d722ebeFF267c98F94',
  PERMIT2: '0x000000000022D473030F116dDEE9F6B43aC78BA3',
  ATOMIC_EXECUTOR: '0xe21827818Fea1F14d59929CAE36a93c0B44e0aE1',
  FEE_RECIPIENT: '0xD88539d3c4C460136a733A3Fd60cf6BF269079da',
  POOL_KEY: {
    currency0: '0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73',
    currency1: '0xf7a2F5554C57C216F1831AA5C8ed3C46727eFE2B',
    fee: 3000,
    tickSpacing: 60,
    hooks: '0xAb64c6Eb29a6bb8488cb1fcAB1ca11C5e28bC0cc',
  },
};

export const V4_LIVE_TEST_POOLS = {
  IRL: {
    key: 'IRL',
    label: '🏹 $IRL (Official V4 Hook)',
    symbol: '$IRL',
    pairTitle: '$IRL / WETH',
    tokenAddress: '0xf7a2F5554C57C216F1831AA5C8ed3C46727eFE2B',
    hookAddress: '0xAb64c6Eb29a6bb8488cb1fcAB1ca11C5e28bC0cc',
    poolId: '0x1848c9b63c7733c421b2db31bcb606ad75d505d281f7377dc170b082dbe989cb',
    dexscreenerUrl: 'https://dexscreener.com/robinhood/0x1848c9b63c7733c421b2db31bcb606ad75d505d281f7377dc170b082dbe989cb',
    programmableUrl: 'https://programmable.market/token/0xf7a2F5554C57C216F1831AA5C8ed3C46727eFE2B?chain=4663',
  },
  V4: {
    key: 'V4',
    label: '🧪 Test Live V4 ($V4)',
    symbol: '$V4',
    pairTitle: '$V4 / ETH (Live V4 Hook Test)',
    tokenAddress: '0xC60bA256B44334A0Cd2C7242E98B88f031abB006',
    hookAddress: '0x720e649549F7BC2118aCBA9F4C9ae6fCC7586080',
    poolId: '0x3df16f271060e4941c0386047def159f42e629dc0455db623c5b363eeacbcc1d',
    dexscreenerUrl: 'https://dexscreener.com/robinhood/0x3df16f271060e4941c0386047def159f42e629dc0455db623c5b363eeacbcc1d',
    programmableUrl: 'https://programmable.market/token/0xC60bA256B44334A0Cd2C7242E98B88f031abB006?chain=4663',
  },
  XILO: {
    key: 'XILO',
    label: '🧪 Test Live V4 ($XILO)',
    symbol: '$XILO',
    pairTitle: '$XILO / ETH (Live V4 Hook Test)',
    tokenAddress: '0xb195A5E62505fAbfD752b06cD5E2519b21FC2d91',
    hookAddress: '0x1d17C804b4AEf49B772c88693730b6faB41Fe0cC',
    poolId: '0x42ec1363a3799fa48e951ccff51628ff8338223d16d5a11bc99be33d4f77afa7',
    dexscreenerUrl: 'https://dexscreener.com/robinhood/0x42ec1363a3799fa48e951ccff51628ff8338223d16d5a11bc99be33d4f77afa7',
    programmableUrl: 'https://programmable.market/token/0xb195A5E62505fAbfD752b06cD5E2519b21FC2d91?chain=4663',
  },
};

export const TOKEN_CA = CONTRACT_ADDRESSES.TOKEN;
export const POOL_ID = V4_INFRASTRUCTURE.POOL_ID;

export const TOKEN_ABI = [
  'function name() view returns (string)',
  'function symbol() view returns (string)',
  'function decimals() view returns (uint8)',
  'function balanceOf(address owner) view returns (uint256)',
  'function approve(address spender, uint256 value) returns (bool)',
  'function allowance(address owner, address spender) view returns (uint256)',
  'function transfer(address to, uint256 amount) returns (bool)',
];

export const STAKING_ABI = [
  'function MIN_ELIGIBLE_STAKE() view returns (uint256)',
  'function MAX_ELIGIBLE_STAKE() view returns (uint256)',
  'function STAKE_COOLDOWN() view returns (uint256)',
  'function hookContract() view returns (address)',
  'function stake(uint256 amount)',
  'function unstake(uint256 amount)',
  'function claimYield() returns (uint256)',
  'function pendingYield(address user) view returns (uint256)',
  'function stakedBalance(address user) view returns (uint256)',
  'function eligibleStake(address user) view returns (uint256)',
  'function totalStaked() view returns (uint256)',
  'function totalEligibleStaked() view returns (uint256)',
  'function unallocatedYield() view returns (uint256)',
  'function lastStakedTimestamp(address user) view returns (uint256)',
  'function unstakeUnlockTime(address user) view returns (uint256)',
  'function isCooldownMet(address user) view returns (bool)',
  'function isUnstakeUnlocked(address user) view returns (bool)',
  'function accEthPerShare() view returns (uint256)',
  'function getStakedAmount(address user) view returns (uint256)',
  'event Staked(address indexed user, uint256 amount)',
  'event Unstaked(address indexed user, uint256 amount)',
  'event YieldClaimed(address indexed user, uint256 amount)',
  'event YieldDistributed(uint256 amount, uint256 newAccEthPerShare)',
  'event InstantTicketsClaimLockApplied(address indexed user, uint256 unlockTime)',
];

export const HOOK_ABI = [
  'function dailyLotteryPot() view returns (uint256)',
  'function sundayMegaPot() view returns (uint256)',
  'function dailyPotByDay(uint256 dayId) view returns (uint256)',
  'function weeklyPotByWeek(uint256 weekId) view returns (uint256)',
  'function lotteryPot() view returns (uint256)',
  'function hourlyRewardPot() view returns (uint256)',
  'function hourlyPotByHour(uint256 hourId) view returns (uint256)',
  'function buybackPot() view returns (uint256)',
  'function lastBuybackHour() view returns (uint256)',
  'function launchTimestamp() view returns (uint256)',
  'function LAUNCH_TAX_DURATION() view returns (uint256)',
  'function launchTaxEnabled() view returns (bool)',
  'function isLaunchTaxActive() view returns (bool)',
  'function disableLaunchTaxSqrtPrice() view returns (uint160)',
  'function disableAntiWhaleSqrtPrice() view returns (uint160)',
  'function PROGRAMMABLE_FEE_RECIPIENT() view returns (address)',
  'function PROGRAMMABLE_FEE_BPS() view returns (uint256)',
  'function protocolPot() view returns (uint256)',
  'function programmableFeePot() view returns (uint256)',
  'function unclaimedRewards(address user) view returns (uint256)',
  'function claimUnclaimedRewards()',
  'function claimStakingTickets()',
  'function claimDailyStakingTickets()',
  'function executeBuybackAndBurn()',
  'function receiveMarketplaceTax(uint256 tokenId) payable',
  'function getTopTraders(uint256 hourId) view returns (address[])',
  'function isTop10PerHour(uint256 hourId, address user) view returns (bool)',
  'function getMaxDailyVolumeTickets(address user) view returns (uint256)',
  'function getMaxDailyTicketsLimit(address user) view returns (uint256)',
  'function getMaxWeeklyTicketsLimit(address user) view returns (uint256)',
  'function userVolumePerHour(uint256 hour, address user) view returns (uint256)',
  'function userHourlyScore(uint256 hour, address user) view returns (uint256)',
  'function totalHourlyScore(uint256 hour) view returns (uint256)',
  'function userCashbackPerHour(uint256 hour, address user) view returns (uint256)',
  'function dayStartTicketId(uint256 dayId) view returns (uint256)',
  'function dayEndTicketId(uint256 dayId) view returns (uint256)',
  'function weekStartTicketId(uint256 weekId) view returns (uint256)',
  'function weekEndTicketId(uint256 weekId) view returns (uint256)',
  'event TicketMinted(address indexed user, uint256 tokenId)',
  'event HourlyRewardsDistributed(uint256 currentHour, uint256 totalPotDistributed)',
  'event LotteryWinnerDrawn(address indexed winner, uint256 tokenId, uint256 prize)',
  'event SundayMegaJackpotDrawn(address indexed winner, uint256 tokenId, uint256 prize)',
  'event BuybackAndBurnExecuted(uint256 ethAmount)',
  'event LaunchTaxDisabled()',
  'event MarketplaceTaxCollected(uint256 indexed tokenId, uint256 taxAmount, bool isDailyAndWeekly, uint256 dailyShare, uint256 sundayShare)',
];

export const TICKETS_ABI = [
  'function name() view returns (string)',
  'function symbol() view returns (string)',
  'function MARKETPLACE_TAX_BPS() view returns (uint256)',
  'function totalTicketsMinted() view returns (uint256)',
  'function balanceOf(address owner) view returns (uint256)',
  'function ownerOf(uint256 tokenId) view returns (address)',
  'function listings(uint256 tokenId) view returns (address seller, uint256 price, bool active)',
  'function listTicket(uint256 tokenId, uint256 price)',
  'function cancelListing(uint256 tokenId)',
  'function buyTicket(uint256 tokenId) payable',
  'function tokenOfOwnerByIndex(address owner, uint256 index) view returns (uint256)',
  'function approve(address to, uint256 tokenId)',
  'function setApprovalForAll(address operator, bool approved)',
  'function isApprovedForAll(address owner, address operator) view returns (bool)',
  'function transferFrom(address from, address to, uint256 tokenId)',
  'event TicketListed(uint256 indexed tokenId, address indexed seller, uint256 price)',
  'event TicketUnlisted(uint256 indexed tokenId, address indexed seller)',
  'event TicketSold(uint256 indexed tokenId, address indexed seller, address indexed buyer, uint256 price, uint256 lotteryTax)',
];

export const SHERWOOD_GUILD_ABI = [
  'function MAX_GUILD_CAPACITY() view returns (uint256)',
  'function MIN_REAL_YIELD_THRESHOLD() view returns (uint256)',
  'function DAILY_LOTTERY_MIN_STAKE_TIME() view returns (uint256)',
  'function WEEKLY_LOTTERY_MIN_STAKE_TIME() view returns (uint256)',
  'function stakingToken() view returns (address)',
  'function mainStaking() view returns (address)',
  'function hookContract() view returns (address)',
  'function totalGuildStaked() view returns (uint256)',
  'function accEthPerShare() view returns (uint256)',
  'function totalEthHarvested() view returns (uint256)',
  'function totalLotteryEthWon() view returns (uint256)',
  'function stakedBalance(address user) view returns (uint256)',
  'function guildStakedBalance(address user) view returns (uint256)',
  'function pendingYield(address user) view returns (uint256)',
  'function pendingGuildYield(address user) view returns (uint256)',
  'function pendingLotteryEth(address user) view returns (uint256)',
  'function stakedSince(address user) view returns (uint256)',
  'function isGuildYieldActive() view returns (bool)',
  'function guildRemainingCapacity() view returns (uint256)',
  'function userShareBps(address user) view returns (uint256)',
  'function getGuildTicketCount() view returns (uint256)',
  'function getGuildTicketIds() view returns (uint256[])',
  'function getGuildStakersCount() view returns (uint256)',
  'function getGuildStats() view returns (uint256 pooledIrl, uint256 eligibleWeightInMain, uint256 totalEthDistributed, uint256 unharvestedMainEth, bool isMainYieldUnlocked, uint256 irlNeededForMinTier, uint256 totalTicketsOwnedByGuild, uint256 totalLotteryWonWei, uint256 activeStakersCount)',
  'function getUserLotteryEligibility(address user) view returns (bool isCurrentlyStaking, bool eligibleForDaily8h, bool eligibleForWeekly1d, uint256 dailyEligibleWeightIrl, uint256 weeklyEligibleWeightIrl, uint256 stakedDurationSeconds)',
  'function stake(uint256 amount)',
  'function deposit(uint256 amount)',
  'function unstake(uint256 amount)',
  'function withdraw(uint256 amount)',
  'function claimYield() returns (uint256)',
  'function claimGuildYield() returns (uint256)',
  'function claimGuildStakingTickets()',
  'function harvestFromMainStaking()',
  'function harvestMainStakingYield()',
  'function settlePendingLotteryJackpots()',
  'event GuildStaked(address indexed user, uint256 amount, uint256 newTotalGuildStaked)',
  'event GuildUnstaked(address indexed user, uint256 amount, uint256 newTotalGuildStaked)',
  'event GuildYieldHarvested(uint256 amount)',
  'event GuildYieldClaimed(address indexed user, uint256 totalAmount, uint256 lotteryPortion)',
  'event GuildTicketsClaimed(address indexed caller, uint256 totalGuildTickets, uint256 timestamp)',
  'event GuildLotteryJackpotRecorded(uint256 indexed jackpotIndex, uint256 amount, bool isWeekly, uint256 drawTimestamp)',
  'event GuildLotteryJackpotSettled(uint256 indexed jackpotIndex, uint256 amount, bool isWeekly, uint256 eligibleStakersCount, uint256 totalEligibleWeight)',
];



