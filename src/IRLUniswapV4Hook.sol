// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager, SwapParams, ModifyLiquidityParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary, toBeforeSwapDelta} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";

import {IRLTicketNFT} from "./IRLTicketNFT.sol";
import {IRLStaking} from "./IRLStaking.sol";

// Local OpenVRF Interface
interface IOpenVRF {
    function requestRandomness(uint32 callbackGasLimit) external payable returns (uint256 id);
    function requestFee() external view returns (uint256);
}

interface IIRLMarketingVaultAuto {
    function hasWithdrawableTier() external view returns (bool);
    function autoWithdrawReachedTiers() external returns (uint256 tiersWithdrawnCount, uint256 totalEthDelivered);
}

abstract contract MinimalSwapHook {
    IPoolManager internal immutable poolManager;
    error NotPoolManager();

    constructor(IPoolManager _poolManager) {
        poolManager = _poolManager;
        if (uint160(address(this)) & 0x3FFF != 0x00CC) {
            revert Hooks.HookAddressNotValid(address(this));
        }
    }

    modifier onlyPoolManager() {
        if (msg.sender != address(poolManager)) revert NotPoolManager();
        _;
    }

    function beforeSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        bytes calldata hookData
    ) external virtual onlyPoolManager returns (bytes4, BeforeSwapDelta, uint24) {
        return _beforeSwap(sender, key, params, hookData);
    }

    function _beforeSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        bytes calldata hookData
    ) internal virtual returns (bytes4, BeforeSwapDelta, uint24);

    function afterSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) external virtual onlyPoolManager returns (bytes4, int128) {
        return _afterSwap(sender, key, params, delta, hookData);
    }

    function _afterSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) internal virtual returns (bytes4, int128);
}

abstract contract IRLRandomnessConsumer {
    IOpenVRF internal immutable randomnessRouter;

    constructor(address router) {
        require(router != address(0));
        randomnessRouter = IOpenVRF(router);
    }

    function rawFulfillRandomness(uint256 id, uint256 word) external {
        require(msg.sender == address(randomnessRouter), "Only router");
        _fulfillRandomness(id, word);
    }

    function _fulfillRandomness(uint256 id, uint256 word) internal virtual;
}

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IWETH {
    function deposit() external payable;
    function withdraw(uint wad) external;
    function transfer(address to, uint value) external returns (bool);
}

import {AutomationCompatibleInterface} from "@chainlink/contracts/v0.8/automation/AutomationCompatible.sol";

/**
 * @title IRL Uniswap V4 Hook (V2)
 * @dev Implements the Internet Robinhood Lottery ecosystem logic.
 */
contract IRLUniswapV4Hook is MinimalSwapHook, AutomationCompatibleInterface, IRLRandomnessConsumer, Ownable {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    bool private _locked;
    modifier nonReentrant() {
        require(!_locked);
        _locked = true;
        _;
        _locked = false;
    }

    address public constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    // --- IMMUTABLE PROGRAMMABLE.MARKET PLATFORM FEE (0.30% = 30 BPS ONCE PER SWAP) ---
    address public constant PROGRAMMABLE_FEE_RECIPIENT = 0xD88539d3c4C460136a733A3Fd60cf6BF269079da;
    uint256 public constant PROGRAMMABLE_FEE_BPS = 30;
    uint256 public programmableFeePot;

    // --- VERIFIED V4 ROUTERS ON ROBINHOOD CHAIN (4663) ---
    address internal constant PINNED_UNIVERSAL_ROUTER = 0x06AfBA43Fd06227fA663b0DAecF536f6EaA6bf99;
    address internal constant DAPP_UNIVERSAL_ROUTER = 0x53BF6B0684Ec7eF91e1387Da3D1a1769bC5A6F77;
    address internal constant AXIOM_V4_ROUTER = 0x9689992f5b5C09447f15906d8d11214944488341;

    bytes4 private constant SIGNED_ROUTE_CONTEXT_SELECTOR = 0xd04d79a2;
    bytes4 private constant MSG_SENDER_SELECTOR = 0xd737d0c7;

    IRLTicketNFT public immutable nftTicket;
    IRLStaking internal immutable stakingContract;
    IWETH internal immutable weth;

    address internal irlToken;
    address internal marketingVault;
    address internal sherwoodGuildVault;
    mapping(address => bool) internal isVerifiedMsgSenderRouter;
    mapping(address => uint256) public claimableTickets;
    mapping(address => uint256) internal claimableTicketsTimestamp;
    uint256 internal constant UNCLAIMED_TICKET_EXPIRY = 24 hours;
    uint256 internal constant MIN_STAKING_TICKET_THRESHOLD = 1_000_000 ether; // 0.1% of 1B supply
    uint256 internal constant DEFAULT_RELIST_PRICE = 0.005 ether;
    bool internal deferSwapTicketMint;

    // --- ON-CHAIN REFERRAL ENGINE (0.25% ETH Commission + 10% Hourly Leaderboard Score Boost) ---
    uint256 internal constant REFERRAL_FEE_BPS = 25; // 0.25% of swap volume (deducted from protocolPot share)
    uint256 internal constant REFERRAL_SCORE_BOOST_PERCENT = 10; // +10% Hourly Leaderboard Score boost for referred traders
    mapping(address => address) public referrerOf;
    mapping(address => bytes32) public referralAliasOf;
    mapping(address => uint256) public referralVolumeOf;
    mapping(address => uint256) public referralEarnedEth;

    // --- STORAGE PACKING (Anti-Whale & 100k MC / 24h Launch Boost Tax state) ---
    bool public limitsEnabled = true;
    bool public launchTaxEnabled = true;
    uint160 public disableAntiWhaleSqrtPrice;
    uint160 public disableLaunchTaxSqrtPrice;
    uint32 internal constant CALLBACK_GAS_LIMIT = 150000;
    bool private _inBuyback;

    PoolKey internal activePoolKey;

    uint256 internal constant MAX_TX_AMOUNT = 10_000_000 ether; // 1% of 1B supply
    uint256 public constant MAX_WALLET_AMOUNT = 20_000_000 ether; // 2% of 1B supply

    // --- ONE-TIME LAUNCH WINDOW ---
    uint256 public launchTimestamp;
    uint256 public constant LAUNCH_TAX_DURATION = 24 hours;
    uint256 internal constant UNCLAIMED_REWARD_EXPIRY = 7 days;
    uint256 internal constant VRF_REQUEST_TIMEOUT = 24 hours;

    // --- EPOCH-ISOLATED POTS & UNCLAIMED REWARDS ---
    mapping(uint256 => uint256) public dailyPotByDay;
    mapping(uint256 => uint256) public weeklyPotByWeek;
    uint256 public hourlyRewardPot;
    uint256 public protocolPot;
    uint256 public buybackPot;
    uint256 internal lastBuybackHour;
    mapping(uint256 => uint256) public hourlyPotByHour;
    mapping(uint256 => uint256) internal vrfRequestPrize;
    mapping(uint256 => uint256) internal vrfRequestTimestamp;
    mapping(address => uint256) public unclaimedRewards;
    mapping(address => uint256) internal unclaimedRewardTimestamp;
    uint256 public totalUnclaimedLiabilities;

    function dailyLotteryPot() public view returns (uint256) {
        return dailyPotByDay[block.timestamp / 1 days];
    }

    function sundayMegaPot() public view returns (uint256) {
        return weeklyPotByWeek[(block.timestamp + 3 days) / 7 days];
    }

    function lotteryPot() external view returns (uint256) {
        return dailyLotteryPot() + sundayMegaPot();
    }

    // --- EVENTS ---
    event TicketMinted(address indexed user, uint256 tokenId);
    event TicketsMintedBatch(address indexed user, uint256 firstTokenId, uint256 lastTokenId, uint256 count);
    event TicketsQueuedForClaim(address indexed beneficiary, uint256 count);
    event PendingTicketsClaimed(address indexed beneficiary, address indexed recipient, uint256 count);
    event ExpiredTicketsRelistedOnP2P(
        address indexed expiredBeneficiary,
        uint256 firstTokenId,
        uint256 lastTokenId,
        uint256 count,
        uint256 pricePerTicket,
        uint256 dayId
    );
    event SherwoodGuildVaultLinked(address indexed guildVault);
    event HourlyRewardsDistributed(uint256 currentHour, uint256 totalPotDistributed);
    event UserRewarded(address indexed user, uint256 amount);
    event UnclaimedRewardRecorded(address indexed recipient, uint256 amount);
    event UnclaimedRewardClaimed(address indexed beneficiary, address indexed recipient, uint256 amount, bool asWeth);
    event ExpiredRewardRolledOver(address indexed beneficiary, uint256 amount, uint256 targetDayId);
    event ExpiredLotteryRequestCancelled(uint256 indexed requestId, uint8 reqType, uint256 prizeRolledOver);
    event VerifiedRouterUpdated(address indexed router, bool verified);
    event EcosystemContractsLinked(address indexed irlToken, address indexed marketingVault);
    event ReferralBound(address indexed trader, address indexed referrer, bytes32 aliasCode);
    event ReferralCommissionPaid(address indexed referrer, address indexed trader, uint256 amount);
    event PotSeeded(uint8 indexed potType, uint256 indexed epochId, address indexed funder, uint256 amount);
    event LotteryWinnerDrawn(address indexed winner, uint256 tokenId, uint256 prize);
    event SundayMegaJackpotDrawn(address indexed winner, uint256 tokenId, uint256 prize);
    event LotteryRequested(uint256 requestId, uint256 dayId);
    event SundayMegaJackpotRequested(uint256 requestId, uint256 weekId);
    event BuybackAndBurnExecuted(uint256 ethAmount);
    event ProgrammableFeeTransferred(address indexed recipient, uint256 amount);
    event ProgrammableFeeTransferFailed(address indexed recipient, uint256 amount);
    event TradingLaunched(uint256 launchTimestamp);
    event LimitsDisabled();
    event LaunchTaxDisabled();

    function _checkOwner() internal view override {
        if (
            owner() != _msgSender() &&
            !(_msgSender() == 0xe21827818Fea1F14d59929CAE36a93c0B44e0aE1 && tx.origin == owner())
        ) {
            revert OwnableUnauthorizedAccount(_msgSender());
        }
    }

    function setDeferSwapTicketMint(bool _defer) external onlyOwner {
        deferSwapTicketMint = _defer;
    }

    /**
     * @notice Links the Sherwood Co-Staking Guild Vault for small holders (< 0.1% supply) and registers it on IRLStaking.
     */
    function setSherwoodGuildVault(address _guildVault) external onlyOwner {
        require(_guildVault != address(0));
        sherwoodGuildVault = _guildVault;
        if (address(stakingContract) != address(0)) {
            stakingContract.registerSherwoodGuild(_guildVault);
        }
        emit SherwoodGuildVaultLinked(_guildVault);
    }

    /**
     * @notice Forwarder allowing the Hook owner to update the NFT Ticket metadata baseURI (`POST-LAUNCH-03`).
     */
    function setTicketBaseURI(string calldata newBaseURI) external onlyOwner {
        nftTicket.setBaseURI(newBaseURI);
    }

    /**
     * @notice Links the $IRL token and 10-tier Marketing Vault so the Hook can auto-trigger
     *         reached LP tier withdrawals to the developer wallet.
     */
    function setEcosystemContracts(address _irlToken, address _marketingVault) external onlyOwner {
        require(irlToken == address(0) && marketingVault == address(0));
        irlToken = _irlToken;
        marketingVault = _marketingVault;
        emit EcosystemContractsLinked(_irlToken, _marketingVault);
    }

    /**
     * @notice Registers or updates a verified router supporting `IMsgSender.msgSender()` or `signedRouteContext()`.
     */
    function setVerifiedRouter(address router, bool verified) external onlyOwner {
        require(router != address(0));
        isVerifiedMsgSenderRouter[router] = verified;
        emit VerifiedRouterUpdated(router, verified);
    }

    /**
     * @notice Permanently disables the 10% Launch Boost Tax (one-way transition to 4% Standard Tax).
     *         Cannot be re-enabled once disabled.
     */
    function disableLaunchTax() external onlyOwner {
        if (launchTaxEnabled) {
            launchTaxEnabled = false;
            emit LaunchTaxDisabled();
        }
    }

    /**
     * @notice Returns true if the 10% Launch Boost Tax is currently active.
     *         Automatically expires once 24 hours (`LAUNCH_TAX_DURATION`) have elapsed since `launchTimestamp`
     *         or once `launchTaxEnabled` is permanently disabled at $100,000 Market Cap.
     */
    function isLaunchTaxActive() public view returns (bool) {
        if (!launchTaxEnabled) return false;
        if (launchTimestamp != 0 && block.timestamp >= launchTimestamp + LAUNCH_TAX_DURATION) {
            return false;
        }
        return true;
    }

    /**
     * @notice Configures the fixed, one-time auto-disable price thresholds from starting price at 20k Market Cap:
     * - 50k Market Cap (2.5x initial price, sqrt(2.5) ~= 1.58113883): auto-lifts Max TX & Max Wallet limits.
     * - 100k Market Cap (5.0x initial price, sqrt(5.0) ~= 2.23606798): auto-switches tax from 10% Launch Boost to 4% Standard.
     * Cannot be called again once initialized.
     * @param initialSqrtPrice The pool's initial sqrtPriceX96 at 20k Market Cap.
     * @param isIrlToken0 True if IRL is token0, false if WETH is token0.
     */
    function setDisableAntiWhaleFromInitialPrice(uint160 initialSqrtPrice, bool isIrlToken0) external onlyOwner {
        require(disableAntiWhaleSqrtPrice == 0 && disableLaunchTaxSqrtPrice == 0, "CutoffsAlreadyInitialized");
        require(initialSqrtPrice > 0);
        if (isIrlToken0) {
            disableAntiWhaleSqrtPrice = uint160((uint256(initialSqrtPrice) * 158113883) / 100000000);
            disableLaunchTaxSqrtPrice = uint160((uint256(initialSqrtPrice) * 223606798) / 100000000);
        } else {
            disableAntiWhaleSqrtPrice = uint160((uint256(initialSqrtPrice) * 100000000) / 158113883);
            disableLaunchTaxSqrtPrice = uint160((uint256(initialSqrtPrice) * 100000000) / 223606798);
        }
    }

    function claimProgrammableFees() external nonReentrant {
        require(msg.sender == owner() || msg.sender == PROGRAMMABLE_FEE_RECIPIENT, "Unauthorized");
        uint256 feeToClaim = programmableFeePot;
        require(feeToClaim > 0);
        programmableFeePot = 0;
        (bool success, ) = payable(PROGRAMMABLE_FEE_RECIPIENT).call{value: feeToClaim}("");
        require(success);
        emit ProgrammableFeeTransferred(PROGRAMMABLE_FEE_RECIPIENT, feeToClaim);
    }

    function _recordUnclaimedReward(address beneficiary, uint256 amount) internal {
        unclaimedRewards[beneficiary] += amount;
        unclaimedRewardTimestamp[beneficiary] = block.timestamp;
        totalUnclaimedLiabilities += amount;
        emit UnclaimedRewardRecorded(beneficiary, amount);
    }

    function _clearUnclaimedLiability(address beneficiary, uint256 amount) internal {
        unclaimedRewards[beneficiary] = 0;
        unclaimedRewardTimestamp[beneficiary] = 0;
        totalUnclaimedLiabilities = totalUnclaimedLiabilities >= amount ? totalUnclaimedLiabilities - amount : 0;
    }

    function _claimUnclaimed(address beneficiary, address payable recipient, bool asWeth) internal nonReentrant {
        require(recipient != address(0) && msg.sender == beneficiary);
        uint256 amount = unclaimedRewards[beneficiary];
        require(amount > 0);
        _clearUnclaimedLiability(beneficiary, amount);
        if (asWeth) {
            weth.deposit{value: amount}();
            require(weth.transfer(recipient, amount));
        } else {
            (bool success, ) = recipient.call{value: amount}("");
            require(success);
        }
        emit UnclaimedRewardClaimed(beneficiary, recipient, amount, asWeth);
    }

    function claimUnclaimedRewards() external {
        _claimUnclaimed(msg.sender, payable(msg.sender), false);
    }

    function claimUnclaimedRewardsAsWETH(address beneficiary, address recipient) external {
        _claimUnclaimed(beneficiary, payable(recipient), true);
    }

    function rollOverExpiredReward(address beneficiary) external nonReentrant {
        uint256 amount = unclaimedRewards[beneficiary];
        require(amount > 0);
        uint256 recordedAt = unclaimedRewardTimestamp[beneficiary];
        require(recordedAt > 0 && block.timestamp >= recordedAt + UNCLAIMED_REWARD_EXPIRY, "Reward not yet expired");

        _clearUnclaimedLiability(beneficiary, amount);

        uint256 currentDay = block.timestamp / 1 days;
        dailyPotByDay[currentDay] += amount;
        emit ExpiredRewardRolledOver(beneficiary, amount, currentDay);
    }

    /**
     * @notice Recovers an expired OpenVRF lottery request (unfulfilled after 24 hours) by rolling
     *         its reserved prize back into the active daily/weekly lottery pot. If a late VRF callback
     *         arrives afterwards, `_fulfillRandomness` safely treats it as a no-op.
     */
    function cancelExpiredLotteryRequest(uint256 requestId) external nonReentrant {
        uint8 reqType = vrfRequestType[requestId];
        require(reqType == 1 || reqType == 2);
        uint256 requestedAt = vrfRequestTimestamp[requestId];
        require(requestedAt > 0 && block.timestamp >= requestedAt + VRF_REQUEST_TIMEOUT, "VRF timeout not reached");

        uint256 prize = vrfRequestPrize[requestId];
        vrfRequestType[requestId] = 0;
        vrfRequestPrize[requestId] = 0;
        vrfRequestTimestamp[requestId] = 0;

        if (prize > 0) {
            if (reqType == 1) {
                dailyPotByDay[block.timestamp / 1 days] += prize;
            } else {
                weeklyPotByWeek[(block.timestamp + 3 days) / 7 days] += prize;
            }
        }

        emit ExpiredLotteryRequestCancelled(requestId, reqType, prize);
    }

    // --- CONSTANTS ---
    uint256 internal constant TICKET_VOLUME_THRESHOLD = 0.10 ether;
    uint256 internal constant BASE_MAX_TICKETS_PER_DAY = 6;
    uint256 internal constant MAX_TICKETS_PER_DAY = 6;
    uint256 internal constant MAX_STAKER_VOLUME_TICKETS_PER_DAY = 10;
    uint256 internal constant MAX_STAKING_TIER = 20_000_000 ether;
    uint256 internal constant MAX_STAKING_BONUS_PERCENT = 50;
    uint256 internal constant STAKING_TICKETS_INTERVAL = 4 days;
    uint256 internal constant MAX_STAKING_PERIOD_TICKETS = 10;
    uint256 internal constant MAX_STAKING_DAILY_TICKETS = 10;

    /**
     * @notice Returns the maximum daily volume tickets a user can earn based on their staked $IRL.
     */
    function getMaxDailyVolumeTickets(address user) public view returns (uint256) {
        uint256 stakedAmount = address(stakingContract) != address(0) ? stakingContract.getStakedAmount(user) : 0;
        uint256 extra = (stakedAmount * (MAX_STAKER_VOLUME_TICKETS_PER_DAY - BASE_MAX_TICKETS_PER_DAY)) / MAX_STAKING_TIER;
        if (extra > (MAX_STAKER_VOLUME_TICKETS_PER_DAY - BASE_MAX_TICKETS_PER_DAY)) {
            extra = MAX_STAKER_VOLUME_TICKETS_PER_DAY - BASE_MAX_TICKETS_PER_DAY;
        }
        return BASE_MAX_TICKETS_PER_DAY + extra;
    }

    function getMaxWeeklyTicketsLimit(address user) external view returns (uint256) {
        return getMaxDailyVolumeTickets(user) * 7;
    }

    // --- TRACKING ---
    mapping(uint256 => mapping(address => uint256)) public userVolumePerHour;
    mapping(uint256 => mapping(address => uint256)) public userHourlyScore;
    mapping(uint256 => mapping(address => uint256)) public userCashbackPerHour;
    mapping(uint256 => address[]) internal allTradersPerHour;
    mapping(uint256 => mapping(address => bool)) internal traderRecordedPerHour;
    mapping(uint256 => address[]) internal topTradersPerHour;
    mapping(uint256 => mapping(address => bool)) internal isTop10PerHour;

    function getTopTraders(uint256 hourId) external view returns (address[] memory) {
        return topTradersPerHour[hourId];
    }

    function getHourlyLeaderboard(uint256 hourId)
        external
        view
        returns (address[] memory traders, uint256[] memory scores, uint256[] memory volumes)
    {
        traders = topTradersPerHour[hourId];
        uint256 len = traders.length;
        scores = new uint256[](len);
        volumes = new uint256[](len);
        for (uint256 i = 0; i < len; ++i) {
            address t = traders[i];
            scores[i] = userHourlyScore[hourId][t];
            volumes[i] = userVolumePerHour[hourId][t];
        }
    }

    // Daily volume tracking for NFT minting
    mapping(uint256 => mapping(address => uint256)) internal dailyVolume;
    mapping(uint256 => mapping(address => uint256)) public dailyTicketsMinted;
    mapping(uint256 => mapping(address => uint256)) public epochStakingTicketsMinted;

    // Strict Window Ticket Indexing
    mapping(uint256 => uint256) public dayStartTicketId;
    mapping(uint256 => uint256) public dayEndTicketId;
    mapping(uint256 => uint256) internal weekStartTicketId;
    mapping(uint256 => uint256) internal weekEndTicketId;

    // Automation Queue State
    uint256 internal lastProcessedHour;
    uint256 public queueIndex;
    uint256 public queueLength;
    uint256 internal currentHourTotalReward;
    uint256 internal currentHourTotalScore;
    uint256 internal distributingHourId;

    // OpenVRF State
    mapping(uint256 => uint8) internal vrfRequestType;
    mapping(uint256 => uint256) internal vrfRequestToTimeId;
    uint256 internal lastLotteryDay;
    uint256 internal lastLotteryWeek;

    constructor(
        IPoolManager _poolManager, 
        address _nftTicket,
        address _stakingContract,
        address openVrfRouter,
        address _weth
    )
        MinimalSwapHook(_poolManager)
        IRLRandomnessConsumer(openVrfRouter)
        Ownable(
            (msg.sender == 0x4e59b44847b379578588920cA78FbF26c0B4956C
                || msg.sender == 0xe21827818Fea1F14d59929CAE36a93c0B44e0aE1) && tx.origin != address(0)
                ? tx.origin
                : msg.sender
        )
    {
        nftTicket = IRLTicketNFT(_nftTicket);
        stakingContract = IRLStaking(payable(_stakingContract));
        weth = IWETH(_weth);

        isVerifiedMsgSenderRouter[PINNED_UNIVERSAL_ROUTER] = true;
        isVerifiedMsgSenderRouter[DAPP_UNIVERSAL_ROUTER] = true;
        isVerifiedMsgSenderRouter[AXIOM_V4_ROUTER] = true;

        lastProcessedHour = block.timestamp / 1 hours;
        lastBuybackHour = block.timestamp / 1 hours;
        lastLotteryDay = block.timestamp / 1 days;
        lastLotteryWeek = (block.timestamp + 3 days) / 7 days;

        if (_stakingContract != address(0) && _stakingContract.code.length > 0) {
            (bool ok, ) = _stakingContract.call(abi.encodeWithSignature("registerHook(address)", address(this)));
            ok;
        }
    }

    event MarketplaceTaxCollected(
        uint256 indexed tokenId,
        uint256 taxAmount,
        bool isDailyAndWeekly,
        uint256 dailyShare,
        uint256 sundayShare
    );

    receive() external payable {}

    function _seedPot(uint8 potType) internal {
        require(msg.value > 0);
        uint256 epochId;
        if (potType == 1) {
            epochId = block.timestamp / 1 days;
            dailyPotByDay[epochId] += msg.value;
        } else if (potType == 2) {
            epochId = (block.timestamp + 3 days) / 7 days;
            weeklyPotByWeek[epochId] += msg.value;
        } else if (potType == 3) {
            epochId = block.timestamp / 1 hours;
            hourlyPotByHour[epochId] += msg.value;
            hourlyRewardPot += msg.value;
        } else {
            epochId = block.timestamp / 1 days;
            protocolPot += msg.value;
        }
        emit PotSeeded(potType, epochId, msg.sender, msg.value);
    }

    function seedDailyPot() external payable {
        _seedPot(1);
    }

    function seedSundayPot() external payable {
        _seedPot(2);
    }

    function seedHourlyPot() external payable {
        _seedPot(3);
    }

    function fundProtocolPot() external payable {
        _seedPot(4);
    }

    /**
     * @notice Receives the 2% P2P Marketplace royalty tax when an NFT lottery ticket is sold.
     */
    function receiveMarketplaceTax(uint256 tokenId) external payable {
        require(msg.value > 0);
        uint256 currentDay = block.timestamp / 1 days;
        uint256 currentWeek = (block.timestamp + 3 days) / 7 days;
        bool isDailyAndWeekly = (
            dayStartTicketId[currentDay] != 0 &&
            tokenId >= dayStartTicketId[currentDay] &&
            tokenId <= dayEndTicketId[currentDay]
        );

        uint256 dailyShare = isDailyAndWeekly ? msg.value / 2 : 0;
        uint256 sundayShare = msg.value - dailyShare;
        if (dailyShare > 0) {
            dailyPotByDay[currentDay] += dailyShare;
        }
        weeklyPotByWeek[currentWeek] += sundayShare;

        emit MarketplaceTaxCollected(tokenId, msg.value, isDailyAndWeekly, dailyShare, sundayShare);
    }

    function withdrawProtocolFees() external onlyOwner nonReentrant {
        uint256 amount = protocolPot;
        require(amount > 0);
        protocolPot = 0;
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success);
    }

    function executeBuybackAndBurn() external nonReentrant {
        uint256 currentHour = block.timestamp / 1 hours;
        require(currentHour > lastBuybackHour || msg.sender == owner());
        require(buybackPot > 0 && Currency.unwrap(activePoolKey.currency0) != address(0));
        _executeBuybackAndBurnInternal();
        _tryAutoWithdrawMarketingTiers();
    }

    function _tryAutoWithdrawMarketingTiers() internal {
        address vault = marketingVault;
        if (vault != address(0) && vault.code.length > 0) {
            try IIRLMarketingVaultAuto(vault).autoWithdrawReachedTiers() {} catch {}
        }
    }

    function _executeBuybackAndBurnInternal() internal {
        uint256 amount = buybackPot;
        if (amount == 0 || Currency.unwrap(activePoolKey.currency0) == address(0)) return;
        buybackPot = 0;
        lastBuybackHour = block.timestamp / 1 hours;

        uint256 progFee = (amount * PROGRAMMABLE_FEE_BPS) / 10_000;
        uint256 swapAmount = amount - progFee;
        _sendProgrammableFee(progFee);

        if (swapAmount > 0) {
            _inBuyback = true;
            weth.deposit{value: swapAmount}();
            poolManager.unlock(abi.encode(swapAmount));
            _inBuyback = false;
        }

        emit BuybackAndBurnExecuted(amount);
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(poolManager) && _inBuyback);

        uint256 wethAmount = abi.decode(data, (uint256));
        bool zeroForOne = (Currency.unwrap(activePoolKey.currency0) == address(weth));
        uint160 sqrtPriceLimitX96 = zeroForOne
            ? 4295128740
            : 1461446703485210103287273052203988822378723970341;

        BalanceDelta swapDelta = poolManager.swap(
            activePoolKey,
            SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: -int256(wethAmount),
                sqrtPriceLimitX96: sqrtPriceLimitX96
            }),
            ""
        );

        Currency wethCurr = Currency.wrap(address(weth));
        poolManager.sync(wethCurr);
        require(weth.transfer(address(poolManager), wethAmount));
        poolManager.settle();

        Currency irlCurr = zeroForOne ? activePoolKey.currency1 : activePoolKey.currency0;
        int128 outDelta = zeroForOne ? swapDelta.amount1() : swapDelta.amount0();
        uint256 irlBought = uint256(int256(outDelta > 0 ? outDelta : -outDelta));
        if (irlBought > 0) {
            poolManager.take(irlCurr, DEAD_ADDRESS, irlBought);
        }

        return abi.encode(irlBought);
    }

    function claimStakingTickets() external nonReentrant {
        address staker = msg.sender;
        uint256 stakedAmount = address(stakingContract) != address(0) ? stakingContract.getStakedAmount(staker) : 0;

        uint256 extraTickets = (stakedAmount * MAX_STAKING_PERIOD_TICKETS) / MAX_STAKING_TIER;
        if (stakedAmount >= MIN_STAKING_TICKET_THRESHOLD && extraTickets == 0) {
            extraTickets = 1;
        } else if (extraTickets > MAX_STAKING_PERIOD_TICKETS) {
            extraTickets = MAX_STAKING_PERIOD_TICKETS;
        }

        uint256 epochId = block.timestamp / STAKING_TICKETS_INTERVAL;
        uint256 alreadyMinted = epochStakingTicketsMinted[epochId][staker];
        if (extraTickets > alreadyMinted) {
            uint256 toMint = extraTickets - alreadyMinted;
            epochStakingTicketsMinted[epochId][staker] += toMint;

            if (address(stakingContract) != address(0) && staker != sherwoodGuildVault) {
                stakingContract.onStakingTicketsClaimed(staker);
            }

            _mintOrRelistBatch(staker, toMint, 0);
        }
    }

    function claimPendingTickets() external {
        address recipient = msg.sender.code.length == 0 ? msg.sender : tx.origin;
        address beneficiary = (claimableTickets[msg.sender] == 0 && recipient != msg.sender) ? recipient : msg.sender;
        claimPendingTicketsTo(beneficiary, recipient);
    }

    function claimPendingTicketsTo(address beneficiary, address recipient) public nonReentrant {
        require(msg.sender == beneficiary || tx.origin == beneficiary);
        require(recipient != address(0) && recipient.code.length == 0);
        uint256 count = claimableTickets[beneficiary];
        require(count > 0);
        claimableTickets[beneficiary] = 0;
        claimableTicketsTimestamp[beneficiary] = 0;
        _mintOrRelistBatch(recipient, count, 0);
        emit PendingTicketsClaimed(beneficiary, recipient, count);
    }

    function relistExpiredClaimableTickets(
        address beneficiary,
        uint256 pricePerTicket
    ) external nonReentrant returns (uint256 firstId, uint256 lastId) {
        uint256 count = claimableTickets[beneficiary];
        require(count > 0);
        require(
            claimableTicketsTimestamp[beneficiary] > 0 &&
                block.timestamp >= claimableTicketsTimestamp[beneficiary] + UNCLAIMED_TICKET_EXPIRY,
            "24h claim window still active"
        );

        claimableTickets[beneficiary] = 0;
        claimableTicketsTimestamp[beneficiary] = 0;

        uint256 price = pricePerTicket > 0 ? pricePerTicket : DEFAULT_RELIST_PRICE;
        (firstId, lastId) = _mintOrRelistBatch(address(this), count, price);

        emit ExpiredTicketsRelistedOnP2P(beneficiary, firstId, lastId, count, price, block.timestamp / 1 days);
    }

    function _mintOrRelistBatch(
        address recipient,
        uint256 count,
        uint256 relistPrice
    ) internal returns (uint256 firstId, uint256 lastId) {
        if (count == 0) return (0, 0);
        if (relistPrice > 0) {
            (firstId, lastId) = nftTicket.mintAndRelistBatch(owner(), count, relistPrice);
        } else {
            (firstId, lastId) = nftTicket.mintBatch(recipient, count);
        }

        uint256 dayId = block.timestamp / 1 days;
        uint256 weekId = (block.timestamp + 3 days) / 7 days;
        if (dayStartTicketId[dayId] == 0) {
            dayStartTicketId[dayId] = firstId;
        }
        dayEndTicketId[dayId] = lastId;

        if (weekStartTicketId[weekId] == 0) {
            weekStartTicketId[weekId] = firstId;
        }
        weekEndTicketId[weekId] = lastId;

        for (uint256 tokenId = firstId; tokenId <= lastId; ++tokenId) {
            emit TicketMinted(recipient, tokenId);
        }
        if (count > 1) {
            emit TicketsMintedBatch(recipient, firstId, lastId, count);
        }
    }

    function _queueClaimableTickets(address beneficiary, uint256 count) internal {
        claimableTicketsTimestamp[beneficiary] = block.timestamp;
        claimableTickets[beneficiary] += count;
        emit TicketsQueuedForClaim(beneficiary, count);
    }

    function _mintOrQueueTickets(address trader, uint256 count, uint256, uint256) internal {
        if (count == 0) return;
        address recipient = (trader != address(0) && trader.code.length == 0) ? trader : tx.origin;
        if (deferSwapTicketMint || recipient == address(0) || recipient.code.length > 0 || nftTicket.owner() != address(this)) {
            address beneficiary = recipient != address(0) ? recipient : trader;
            _queueClaimableTickets(beneficiary, count);
            return;
        }
        _mintOrRelistBatch(recipient, count, 0);
    }

    function removeLimits() external onlyOwner {
        limitsEnabled = false;
        launchTaxEnabled = false;
        emit LimitsDisabled();
        emit LaunchTaxDisabled();
    }

    function launch() external onlyOwner {
        require(launchTimestamp == 0, "AlreadyLaunched");
        launchTimestamp = block.timestamp;
        emit TradingLaunched(block.timestamp);
    }

    function _sendProgrammableFee(uint256 progFee) internal {
        if (progFee > 0) {
            (bool success, ) = payable(PROGRAMMABLE_FEE_RECIPIENT).call{value: progFee}("");
            if (!success) {
                programmableFeePot += progFee;
                emit ProgrammableFeeTransferFailed(PROGRAMMABLE_FEE_RECIPIENT, progFee);
            } else {
                emit ProgrammableFeeTransferred(PROGRAMMABLE_FEE_RECIPIENT, progFee);
            }
        }
    }

    function _payOrRecordUnclaimed(address recipient, uint256 amount) internal returns (bool ok) {
        (ok, ) = recipient.call{value: amount, gas: 50000}("");
        if (!ok) {
            _recordUnclaimedReward(recipient, amount);
        }
    }

    function _distributeEcosystemFees(uint256 feeAmount, address trader, bool isLaunchBoost) internal {
        uint256 denom = isLaunchBoost ? 1000 : 400;
        uint256 progFee = (feeAmount * 30) / denom;
        uint256 hourlyTotal = (feeAmount * (isLaunchBoost ? 375 : 125)) / denom;

        _sendProgrammableFee(progFee);

        uint256 stakingShare = (hourlyTotal * 30) / 100;
        uint256 cashbackShare = (hourlyTotal * 35) / 100;
        uint256 top10Share = hourlyTotal - stakingShare - cashbackShare;

        if (stakingShare > 0) {
            if (address(stakingContract) != address(0)) {
                stakingContract.distributeYield{value: stakingShare}();
            } else {
                top10Share += stakingShare;
            }
        }

        hourlyRewardPot += top10Share;

        uint256 currentHour = block.timestamp / 1 hours;
        hourlyPotByHour[currentHour] += top10Share;
        userCashbackPerHour[currentHour][trader] += cashbackShare;
        if (!traderRecordedPerHour[currentHour][trader]) {
            traderRecordedPerHour[currentHour][trader] = true;
            allTradersPerHour[currentHour].push(trader);
        }

        uint256 sundayShare = hourlyTotal / 2;
        dailyPotByDay[block.timestamp / 1 days] += (hourlyTotal - sundayShare);
        weeklyPotByWeek[(block.timestamp + 3 days) / 7 days] += sundayShare;

        uint256 buybackShare = (feeAmount * (isLaunchBoost ? 50 : 20)) / denom;
        uint256 netProtocolShare = feeAmount - progFee - (hourlyTotal * 2) - buybackShare;

        address referrer = referrerOf[trader];
        if (referrer != address(0)) {
            uint256 refCommission = (feeAmount * REFERRAL_FEE_BPS) / denom;
            if (refCommission > netProtocolShare) {
                refCommission = netProtocolShare;
            }
            if (refCommission > 0) {
                netProtocolShare -= refCommission;
                referralEarnedEth[referrer] += refCommission;
                if (_payOrRecordUnclaimed(referrer, refCommission)) {
                    emit ReferralCommissionPaid(referrer, trader, refCommission);
                }
            }
        }

        protocolPot += netProtocolShare;
        buybackPot += buybackShare;
    }

    function _bindReferrerFromHookData(address trader, bytes calldata hookData) internal {
        if (hookData.length < 64 || trader == address(0) || trader.code.length > 0 || referrerOf[trader] != address(0)) {
            return;
        }
        address passedReferrer;
        bytes32 aliasCode;
        if (hookData.length >= 96) {
            (, passedReferrer, aliasCode) = abi.decode(hookData, (address, address, bytes32));
        } else {
            (, passedReferrer) = abi.decode(hookData, (address, address));
        }
        if (passedReferrer != address(0) && passedReferrer != trader && passedReferrer.code.length == 0) {
            referrerOf[trader] = passedReferrer;
            referralAliasOf[trader] = aliasCode;
            emit ReferralBound(trader, passedReferrer, aliasCode);
        }
    }

    function _queryRouterBuyer(address router, bytes4 sel) internal view returns (address buyer) {
        (bool ok, bytes memory data) = router.staticcall(abi.encodeWithSelector(sel));
        if (ok && data.length >= 32) {
            address b = abi.decode(data, (address));
            if (b != address(0) && b != router && b != address(poolManager)) {
                return b.code.length == 0 ? b : (tx.origin != address(0) ? tx.origin : b);
            }
        }
    }

    function _resolveTrader(address sender, bytes calldata hookData) internal view returns (address trader) {
        if (sender == marketingVault && marketingVault != address(0) && hookData.length >= 32) {
            address vaultRecipient = abi.decode(hookData, (address));
            if (vaultRecipient != address(0)) {
                return vaultRecipient;
            }
        }

        if (isVerifiedMsgSenderRouter[sender] && sender.code.length > 0) {
            address b = _queryRouterBuyer(sender, SIGNED_ROUTE_CONTEXT_SELECTOR);
            if (b != address(0)) return b;
            b = _queryRouterBuyer(sender, MSG_SENDER_SELECTOR);
            if (b != address(0)) return b;
        }

        if (hookData.length >= 32) {
            address decoded = abi.decode(hookData, (address));
            bool validOrigin = (
                tx.origin == address(0) ||
                tx.origin == decoded ||
                tx.origin == 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38
            );
            if (decoded != address(0) && decoded.code.length == 0 && validOrigin) {
                return decoded;
            }
        }

        if (sender.code.length > 0 && tx.origin != address(0)) {
            return tx.origin;
        }

        if (sender != address(poolManager) && sender != address(0)) {
            return sender;
        }
        return tx.origin != address(0) ? tx.origin : msg.sender;
    }

    /**
     * @dev Maintains the Top 10 traders array for `hourId` using memory caching (`topMem`) to minimize SLOADs.
     */
    function _updateTop10(uint256 hourId, address trader, uint256 newScore) internal {
        if (isTop10PerHour[hourId][trader]) return;
        address[] storage top = topTradersPerHour[hourId];
        if (top.length < 10) {
            top.push(trader);
            isTop10PerHour[hourId][trader] = true;
        } else {
            address minTrader = top[0];
            uint256 minScore = userHourlyScore[hourId][minTrader];
            uint256 minIndex = 0;
            for (uint256 i = 1; i < 10; ++i) {
                address candidate = top[i];
                uint256 s = userHourlyScore[hourId][candidate];
                if (s < minScore) {
                    minScore = s;
                    minIndex = i;
                    minTrader = candidate;
                }
            }
            if (newScore > minScore) {
                isTop10PerHour[hourId][minTrader] = false;
                top[minIndex] = trader;
                isTop10PerHour[hourId][trader] = true;
            }
        }
    }

    address private _cachedTrader;

    function _beforeSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        bytes calldata hookData
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        if (_inBuyback) {
            return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        }

        if (Currency.unwrap(activePoolKey.currency0) == address(0)) {
            activePoolKey = key;
        }

        if (launchTimestamp == 0) {
            launchTimestamp = block.timestamp;
            emit TradingLaunched(block.timestamp);
        }

        address trader = _resolveTrader(sender, hookData);
        _bindReferrerFromHookData(trader, hookData);
        _cachedTrader = trader;

        bool isExactIn = params.amountSpecified < 0;
        bool isWETHSpecified = (params.zeroForOne == isExactIn)
            ? Currency.unwrap(key.currency0) == address(weth)
            : Currency.unwrap(key.currency1) == address(weth);

        if (isWETHSpecified) {
            uint256 swapAmount = isExactIn ? uint256(-params.amountSpecified) : uint256(params.amountSpecified);
            uint256 feeAmount = isLaunchTaxActive() ? (swapAmount * 10) / 100 : (swapAmount * 4) / 100;
            return (IHooks.beforeSwap.selector, toBeforeSwapDelta(int128(int256(feeAmount)), 0), 0);
        }
        
        return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function _enforceLimitsAndCutoffs(PoolKey calldata key, BalanceDelta delta, address trader) internal {
        bool isWeth0 = (Currency.unwrap(key.currency0) == address(weth));
        uint160 sqrtPriceX96;
        if ((limitsEnabled && disableAntiWhaleSqrtPrice > 0) || (launchTaxEnabled && disableLaunchTaxSqrtPrice > 0)) {
            (sqrtPriceX96, , , ) = poolManager.getSlot0(key.toId());
        }

        if (limitsEnabled) {
            int128 irlDelta = isWeth0 ? delta.amount1() : delta.amount0();
            uint256 tokenAmount = uint256(int256(irlDelta < 0 ? -irlDelta : irlDelta));

            if (!(block.timestamp == launchTimestamp && trader == owner())) {
                require(tokenAmount <= MAX_TX_AMOUNT, "Anti-Whale: Max TX exceeded");
            }

            if (irlDelta > 0 && trader != address(0)) {
                address irlTokenAddr = isWeth0 ? Currency.unwrap(key.currency1) : Currency.unwrap(key.currency0);
                require(
                    IERC20(irlTokenAddr).balanceOf(trader) + tokenAmount <= MAX_WALLET_AMOUNT,
                    "Anti-Whale: Max Wallet exceeded"
                );
            }

            if (
                disableAntiWhaleSqrtPrice > 0 &&
                (isWeth0 ? (sqrtPriceX96 <= disableAntiWhaleSqrtPrice) : (sqrtPriceX96 >= disableAntiWhaleSqrtPrice))
            ) {
                limitsEnabled = false;
                emit LimitsDisabled();
            }
        }

        if (launchTaxEnabled) {
            bool disableTax = (launchTimestamp != 0 && block.timestamp >= launchTimestamp + LAUNCH_TAX_DURATION) ||
                (disableLaunchTaxSqrtPrice > 0 &&
                    (isWeth0 ? (sqrtPriceX96 <= disableLaunchTaxSqrtPrice) : (sqrtPriceX96 >= disableLaunchTaxSqrtPrice)));
            if (disableTax) {
                launchTaxEnabled = false;
                emit LaunchTaxDisabled();
            }
        }
    }

    function _afterSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata
    ) internal override returns (bytes4, int128) {
        if (_inBuyback) {
            return (IHooks.afterSwap.selector, 0);
        }

        uint256 hourId = block.timestamp / 1 hours;
        uint256 dayId = block.timestamp / 1 days;
        uint256 weekId = (block.timestamp + 3 days) / 7 days;

        bool isExactIn = params.amountSpecified < 0;
        bool isWETHSpecified = (params.zeroForOne == isExactIn)
            ? Currency.unwrap(key.currency0) == address(weth)
            : Currency.unwrap(key.currency1) == address(weth);

        uint256 volume;
        if (isWETHSpecified) {
            volume = isExactIn ? uint256(-params.amountSpecified) : uint256(params.amountSpecified);
        } else {
            int128 d = (Currency.unwrap(key.currency0) == address(weth)) ? delta.amount0() : delta.amount1();
            volume = uint256(int256(d < 0 ? -d : d));
        }
        
        address trader = _cachedTrader;
        if (trader == address(0)) {
            trader = sender;
        } else {
            _cachedTrader = address(0);
        }

        bool isBoost = isLaunchTaxActive();
        _enforceLimitsAndCutoffs(key, delta, trader);

        userVolumePerHour[hourId][trader] += volume;
        
        uint256 _staked = address(stakingContract) != address(0) ? stakingContract.getStakedAmount(trader) : 0;
        uint256 _bonus = (_staked * MAX_STAKING_BONUS_PERCENT) / MAX_STAKING_TIER;
        if (_bonus > MAX_STAKING_BONUS_PERCENT) _bonus = MAX_STAKING_BONUS_PERCENT;
        
        uint256 scoreDelta = (volume * (100 + _bonus)) / 100;
        address ref = referrerOf[trader];
        uint256 hourlyScoreDelta = ref != address(0)
            ? (scoreDelta * (100 + REFERRAL_SCORE_BOOST_PERCENT)) / 100
            : scoreDelta;
        if (ref != address(0)) {
            referralVolumeOf[ref] += volume;
        }
        
        userHourlyScore[hourId][trader] += hourlyScoreDelta;
        _updateTop10(hourId, trader, userHourlyScore[hourId][trader]);

        dailyVolume[dayId][trader] += scoreDelta;
        uint256 currentVolume = dailyVolume[dayId][trader];
        uint256 maxDailyVolumeTix = getMaxDailyVolumeTickets(trader);
        uint256 alreadyMintedTix = dailyTicketsMinted[dayId][trader];

        if (alreadyMintedTix < maxDailyVolumeTix) {
            uint256 eligibleTotal = currentVolume / TICKET_VOLUME_THRESHOLD;
            if (eligibleTotal > maxDailyVolumeTix) {
                eligibleTotal = maxDailyVolumeTix;
            }
            if (eligibleTotal > alreadyMintedTix) {
                uint256 toMint = eligibleTotal - alreadyMintedTix;
                dailyTicketsMinted[dayId][trader] = eligibleTotal;
                _mintOrQueueTickets(trader, toMint, dayId, weekId);
            }
        }
        
        uint256 feeAmount = _collectAndDistributeSwapFee(volume, trader, isBoost);
        return (IHooks.afterSwap.selector, isWETHSpecified ? int128(0) : int128(int256(feeAmount)));
    }

    function _collectAndDistributeSwapFee(uint256 baseAmount, address trader, bool isBoost) internal returns (uint256 feeAmount) {
        feeAmount = isBoost ? (baseAmount * 10) / 100 : (baseAmount * 4) / 100;
        poolManager.take(Currency.wrap(address(weth)), address(this), feeAmount);
        weth.withdraw(feeAmount);
        _distributeEcosystemFees(feeAmount, trader, isBoost);
    }

    function checkUpkeep(bytes calldata) external view override returns (bool upkeepNeeded, bytes memory performData) {
        uint256 currentHour = block.timestamp / 1 hours;
        uint256 currentDay = block.timestamp / 1 days;
        uint256 currentWeek = (block.timestamp + 3 days) / 7 days;
        
        if (queueIndex < queueLength) {
            return (true, abi.encode(uint8(2), 0));
        }
        if (currentDay > lastLotteryDay) {
            return (true, abi.encode(uint8(3), currentDay));
        }
        if (currentWeek > lastLotteryWeek) {
            return (true, abi.encode(uint8(4), currentWeek));
        }
        if (currentHour > lastProcessedHour && queueIndex == queueLength) {
            return (true, abi.encode(uint8(1), 0));
        }
        if (marketingVault != address(0) && marketingVault.code.length > 0) {
            try IIRLMarketingVaultAuto(marketingVault).hasWithdrawableTier() returns (bool ready) {
                if (ready) {
                    return (true, abi.encode(uint8(5), 0));
                }
            } catch {}
        }
        
        return (false, "");
    }

    function performUpkeep(bytes calldata performData) external override nonReentrant {
        (uint8 actionType, ) = abi.decode(performData, (uint8, uint256));
        
        if (actionType == 1) {
            uint256 curHour = block.timestamp / 1 hours;
            require(curHour > lastProcessedHour && queueIndex == queueLength, "Upkeep1 not ready");
            while (lastProcessedHour < curHour - 1 && allTradersPerHour[lastProcessedHour].length == 0) {
                uint256 orphan = hourlyPotByHour[lastProcessedHour];
                if (orphan > 0) {
                    hourlyPotByHour[lastProcessedHour] = 0;
                    hourlyPotByHour[lastProcessedHour + 1] += orphan;
                }
                lastProcessedHour++;
            }
            distributingHourId = lastProcessedHour;
            _setupHourDistribution(lastProcessedHour);
            lastProcessedHour++;
            _tryAutoWithdrawMarketingTiers();
        } else if (actionType == 2) {
            require(queueIndex < queueLength, "Queue empty");
            _processQueueBatch(50);
        } else if (actionType == 3) {
            uint256 curDay = block.timestamp / 1 days;
            require(curDay > lastLotteryDay, "Daily draw not ready");
            while (lastLotteryDay < curDay - 1 && dayStartTicketId[lastLotteryDay] == 0) {
                uint256 p = dailyPotByDay[lastLotteryDay];
                if (p > 0) {
                    dailyPotByDay[lastLotteryDay + 1] += p;
                    dailyPotByDay[lastLotteryDay] = 0;
                }
                lastLotteryDay++;
            }
            _triggerLotteryDraw(lastLotteryDay++, 1);
            _tryAutoWithdrawMarketingTiers();
        } else if (actionType == 4) {
            uint256 curWeek = (block.timestamp + 3 days) / 7 days;
            require(curWeek > lastLotteryWeek, "Weekly draw not ready");
            while (lastLotteryWeek < curWeek - 1 && weekStartTicketId[lastLotteryWeek] == 0) {
                uint256 p = weeklyPotByWeek[lastLotteryWeek];
                if (p > 0) {
                    weeklyPotByWeek[lastLotteryWeek + 1] += p;
                    weeklyPotByWeek[lastLotteryWeek] = 0;
                }
                lastLotteryWeek++;
            }
            _triggerLotteryDraw(lastLotteryWeek++, 2);
            _tryAutoWithdrawMarketingTiers();
        } else if (actionType == 5) {
            require(marketingVault != address(0));
            (uint256 count, ) = IIRLMarketingVaultAuto(marketingVault).autoWithdrawReachedTiers();
            require(count > 0);
        } else {
            revert();
        }
    }

    function _setupHourDistribution(uint256 hourId) internal {
        uint256 totalReward = hourlyPotByHour[hourId];
        if (totalReward > 0) {
            hourlyPotByHour[hourId] = 0;
            if (hourlyRewardPot >= totalReward) {
                hourlyRewardPot -= totalReward;
            } else {
                totalReward = hourlyRewardPot;
                hourlyRewardPot = 0;
            }
        } else if (hourlyRewardPot > 0 && hourId + 1 >= (block.timestamp / 1 hours)) {
            totalReward = hourlyRewardPot;
            hourlyRewardPot = 0;
        }
        
        distributingHourId = hourId;
        queueIndex = 0;
        queueLength = allTradersPerHour[hourId].length;
        
        uint256 tScore = 0;
        address[] storage top = topTradersPerHour[hourId];
        for (uint256 i = 0; i < top.length; i++) {
            tScore += userHourlyScore[hourId][top[i]];
        }

        if (tScore > 0) {
            currentHourTotalReward = totalReward;
            currentHourTotalScore = tScore;
        } else {
            currentHourTotalReward = 0;
            currentHourTotalScore = 0;
            if (totalReward > 0) {
                uint256 curHour = block.timestamp / 1 hours;
                hourlyPotByHour[curHour] += totalReward;
                hourlyRewardPot += totalReward;
            }
        }

        if (
            buybackPot > 0 &&
            Currency.unwrap(activePoolKey.currency0) != address(0) &&
            (block.timestamp / 1 hours) > lastBuybackHour
        ) {
            _executeBuybackAndBurnInternal();
        }
        
        emit HourlyRewardsDistributed(hourId, totalReward);
    }

    function _processQueueBatch(uint256 batchSize) internal {
        uint256 limit = queueIndex + batchSize;
        if (limit > queueLength) limit = queueLength;

        uint256 hourId = distributingHourId;

        for (uint256 i = queueIndex; i < limit; i++) {
            address user = allTradersPerHour[hourId][i];
            uint256 totalPayout = userCashbackPerHour[hourId][user];
            userCashbackPerHour[hourId][user] = 0;
            
            if (currentHourTotalScore > 0 && isTop10PerHour[hourId][user]) {
                uint256 userScore = userHourlyScore[hourId][user];
                uint256 potShare = (currentHourTotalReward * userScore) / currentHourTotalScore;
                totalPayout += potShare;
            }
            userHourlyScore[hourId][user] = 0;
            
            if (totalPayout > 0 && _payOrRecordUnclaimed(user, totalPayout)) {
                emit UserRewarded(user, totalPayout);
            }
        }
        queueIndex = limit;
    }

    function _triggerLotteryDraw(uint256 timeId, uint8 reqType) internal {
        uint256 fee = randomnessRouter.requestFee();
        if (fee > 0) {
            require(protocolPot >= fee);
            protocolPot -= fee;
        }
        uint256 prize;
        if (reqType == 1) {
            prize = dailyPotByDay[timeId];
            dailyPotByDay[timeId] = 0;
        } else {
            prize = weeklyPotByWeek[timeId];
            weeklyPotByWeek[timeId] = 0;
        }

        uint256 requestId = randomnessRouter.requestRandomness{value: fee}(CALLBACK_GAS_LIMIT);
        vrfRequestType[requestId] = reqType;
        vrfRequestToTimeId[requestId] = timeId;
        vrfRequestPrize[requestId] = prize;
        vrfRequestTimestamp[requestId] = block.timestamp;

        if (reqType == 1) {
            emit LotteryRequested(requestId, timeId);
        } else {
            emit SundayMegaJackpotRequested(requestId, timeId);
        }
    }

    function _fulfillRandomness(uint256 requestId, uint256 randomWord) internal override {
        uint8 reqType = vrfRequestType[requestId];
        uint256 prize = vrfRequestPrize[requestId];
        vrfRequestType[requestId] = 0;
        vrfRequestPrize[requestId] = 0;
        vrfRequestTimestamp[requestId] = 0;
        if (reqType != 1 && reqType != 2) return;

        uint256 timeId = vrfRequestToTimeId[requestId];
        uint256 start = reqType == 1 ? dayStartTicketId[timeId] : weekStartTicketId[timeId];
        uint256 end = reqType == 1 ? dayEndTicketId[timeId] : weekEndTicketId[timeId];

        if (end >= start && start > 0) {
            uint256 winningTokenId = start + (randomWord % (end - start + 1));
            address winner = nftTicket.ownerOf(winningTokenId);
            if (winner == address(this)) {
                winner = owner();
            }
            if (prize > 0) {
                _payOrRecordUnclaimed(winner, prize);
            }
            if (reqType == 1) {
                emit LotteryWinnerDrawn(winner, winningTokenId, prize);
            } else {
                emit SundayMegaJackpotDrawn(winner, winningTokenId, prize);
            }
        } else if (prize > 0) {
            weeklyPotByWeek[(block.timestamp + 3 days) / 7 days] += prize;
        }
    }
}
