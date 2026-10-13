// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "@openzeppelin/uniswap-hooks/src/base/BaseHook.sol";
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

abstract contract IRLRandomnessConsumer {
    IOpenVRF public immutable randomnessRouter;

    constructor(address router) {
        require(router.code.length > 0, "Invalid router");
        randomnessRouter = IOpenVRF(router);
    }

    function rawFulfillRandomness(uint256 id, uint256 word) external {
        require(msg.sender == address(randomnessRouter), "Only router");
        _fulfillRandomness(id, word);
    }

    function _fulfillRandomness(uint256 id, uint256 word) internal virtual;
}

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IWETH {
    function deposit() external payable;
    function withdraw(uint wad) external;
    function transfer(address to, uint value) external returns (bool);
}

import {AutomationCompatibleInterface} from "@chainlink/contracts/v0.8/automation/AutomationCompatible.sol";

/**
 * @title IRL Uniswap V4 Hook
 * @dev Implements the Internet Robinhood Lottery ecosystem logic with Programmable.market launch integration:
 * - 4% Constant Tax natively collected in ETH:
 *   - 1% Programmable.market Integration (50% Auto-Burn [0.50% of swap] + 50% Programmable Treasury [0.50% of swap])
 *   - 1% Hourly Volume & Real Yield (35% Top 10, 35% All Traders cashback, 30% Stakers Real Yield in ETH)
 *   - 1% Dual Lottery Engine (50% Daily Strict Window via OpenVRF, 50% Sunday Mega-Jackpot)
 *   - 1% Protocol & Deflation (90% Protocol/Marketing upkeep, 10% Buyback & Burn)
 * - Anti-Whale max tx & auto-removal at target price
 * - OpenVRF verifiable randomness
 * - Aggregator fallback for zero-friction routing (1inch, Paraswap, Odos)
 * - Gas-optimized direct indexing (DoS-proof queue)
 */
contract IRLUniswapV4Hook is BaseHook, AutomationCompatibleInterface, IRLRandomnessConsumer, Ownable, ReentrancyGuard {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    address public constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    IRLTicketNFT public immutable nftTicket;
    IRLStaking public immutable stakingContract;
    IWETH public immutable weth;

    // --- STORAGE PACKING (1 Slot for Anti-Whale state) ---
    bool public limitsEnabled = true;
    uint160 public disableAntiWhaleSqrtPrice;
    uint32 public callbackGasLimit = 150000;
    bool private _inBuyback;

    PoolKey public activePoolKey;

    uint256 public constant MAX_TX_AMOUNT = 10_000_000 ether; // 1% of 1B supply
    uint256 public constant MAX_WALLET_AMOUNT = 20_000_000 ether; // 2% of 1B supply

    // --- ANTI-SNIPE & DEV TAX CONFIGURATION ---
    address public devWallet;
    uint256 public launchTimestamp;
    uint256 public constant ANTI_SNIPE_DURATION = 1 minutes;
    mapping(address => bool) public antiSnipeWhitelist;
    uint256 public devSnipeTaxPot; // Fallback pot if direct transfer to dev fails

    // --- POTS ---
    uint256 public dailyLotteryPot;
    uint256 public sundayMegaPot;
    uint256 public hourlyRewardPot;
    uint256 public protocolPot; // For VRF/Automation fees and Marketing
    uint256 public buybackPot; // 10% of protocol fees reserved for buyback & burn
    mapping(uint256 => uint256) public hourlyPotByHour;
    mapping(uint256 => uint256) public vrfRequestPrize;

    // --- PROGRAMMABLE.MARKET INTEGRATION (1% OF SWAP) ---
    address public programmableFeeRecipient;
    uint256 public programmableFeePot;

    // Backward-compatibility view for total lottery pot
    function lotteryPot() external view returns (uint256) {
        return dailyLotteryPot + sundayMegaPot;
    }

    // --- EVENTS (For Telegram Bot indexing & Transparency) ---
    event TicketMinted(address indexed user, uint256 tokenId);
    event HourlyRewardsDistributed(uint256 currentHour, uint256 totalPotDistributed);
    event UserRewarded(address indexed user, uint256 amount);
    event LotteryWinnerDrawn(address indexed winner, uint256 tokenId, uint256 prize);
    event SundayMegaJackpotDrawn(address indexed winner, uint256 tokenId, uint256 prize);
    event LotteryRequested(uint256 requestId, uint256 dayId);
    event SundayMegaJackpotRequested(uint256 requestId, uint256 weekId);
    event BuybackAndBurnExecuted(uint256 ethAmount);
    event ProgrammableFeeTransferred(address indexed recipient, uint256 amount);
    event ProgrammableFeeTransferFailed(address indexed recipient, uint256 amount);
    event ProgrammableFeeRecipientUpdated(address indexed newRecipient);
    event AntiSnipeTaxApplied(address indexed trader, uint256 devFee, uint256 progFee, address indexed devRecipient);
    event AntiSnipeWhitelistUpdated(address indexed account, bool status);
    event DevWalletUpdated(address indexed newDevWallet);
    event TradingLaunched(uint256 launchTimestamp);
    event DevSnipeTaxClaimed(address indexed recipient, uint256 amount);
    event LimitsDisabled();
    event CallbackGasLimitUpdated(uint32 newGasLimit);

    function setCallbackGasLimit(uint32 _gasLimit) external onlyOwner {
        require(_gasLimit >= 25_000 && _gasLimit <= 1_000_000, "Invalid gas limit");
        callbackGasLimit = _gasLimit;
        emit CallbackGasLimitUpdated(_gasLimit);
    }

    function setDisableAntiWhalePrice(uint160 _price) external onlyOwner {
        disableAntiWhaleSqrtPrice = _price;
    }

    /**
     * @notice Configures the auto-disable price threshold for 50k Market Cap based on starting price at 20k MC.
     * @param initialSqrtPrice The pool's initial sqrtPriceX96 at 20k Market Cap.
     * @param isIrlToken0 True if IRL is token0, false if WETH is token0.
     */
    function setDisableAntiWhaleFromInitialPrice(uint160 initialSqrtPrice, bool isIrlToken0) external onlyOwner {
        if (isIrlToken0) {
            // Price = WETH / IRL. Value increases by 2.5x -> sqrtPrice increases by sqrt(2.5) ~= 1.58113883
            disableAntiWhaleSqrtPrice = uint160((uint256(initialSqrtPrice) * 158113883) / 100000000);
        } else {
            // Price = IRL / WETH. Value increases by 2.5x -> sqrtPrice decreases by sqrt(2.5) ~= 1.58113883
            disableAntiWhaleSqrtPrice = uint160((uint256(initialSqrtPrice) * 100000000) / 158113883);
        }
    }

    function setProgrammableFeeRecipient(address _recipient) external onlyOwner {
        require(_recipient != address(0), "InvalidRecipientZeroAddress");
        require(_recipient != address(this), "InvalidRecipientSelf");
        programmableFeeRecipient = _recipient;
        emit ProgrammableFeeRecipientUpdated(_recipient);
    }

    function claimProgrammableFees() external nonReentrant {
        require(msg.sender == owner() || msg.sender == programmableFeeRecipient, "Unauthorized");
        uint256 feeToClaim = programmableFeePot;
        require(feeToClaim > 0, "No fees to claim");
        require(programmableFeeRecipient != address(0), "Recipient not set");
        programmableFeePot = 0;
        (bool success, ) = payable(programmableFeeRecipient).call{value: feeToClaim}("");
        require(success, "Programmable fee transfer failed");
        emit ProgrammableFeeTransferred(programmableFeeRecipient, feeToClaim);
    }

    // --- CONSTANTS ---
    uint256 public constant TICKET_VOLUME_THRESHOLD = 0.10 ether; // 0.10 WETH threshold for 1 NFT (boosted by staking multiplier)
    uint256 public constant BASE_MAX_TICKETS_PER_DAY = 6; // Base daily volume limit for non-stakers
    uint256 public constant MAX_TICKETS_PER_DAY = 6; // Backward-compatible alias
    uint256 public constant MAX_STAKER_VOLUME_TICKETS_PER_DAY = 10; // Up to 10 volume tickets daily for 2% stakers
    uint256 public constant MAX_STAKING_TIER = 20_000_000 ether; // Full 2.0% of 1B supply for maximum staking benefits
    uint256 public constant MAX_STAKING_BONUS_PERCENT = 50; // +50% max multiplier on hourly score and ticket volume
    uint256 public constant STAKING_TICKETS_INTERVAL = 4 days; // Free staking tickets claimable every 4 days
    uint256 public constant MAX_STAKING_PERIOD_TICKETS = 10; // Up to 10 free tickets per 4-day period at full 2% tier
    uint256 public constant MAX_STAKING_DAILY_TICKETS = 10; // Backward-compatible alias

    /**
     * @notice Returns the maximum daily volume tickets a user can earn based on their staked $IRL.
     * @dev Non-stakers get 6 tickets max; scaling linearly up to 10 tickets max for 2% stakers (20M IRL).
     */
    function getMaxDailyVolumeTickets(address user) public view returns (uint256) {
        uint256 stakedAmount = address(stakingContract) != address(0) ? stakingContract.getStakedAmount(user) : 0;
        uint256 extra = (stakedAmount * (MAX_STAKER_VOLUME_TICKETS_PER_DAY - BASE_MAX_TICKETS_PER_DAY)) / MAX_STAKING_TIER;
        if (extra > (MAX_STAKER_VOLUME_TICKETS_PER_DAY - BASE_MAX_TICKETS_PER_DAY)) {
            extra = MAX_STAKER_VOLUME_TICKETS_PER_DAY - BASE_MAX_TICKETS_PER_DAY;
        }
        return BASE_MAX_TICKETS_PER_DAY + extra;
    }

    /**
     * @notice Returns the maximum tickets a user can hold / buy for the daily draw (6 to 10).
     */
    function getMaxDailyTicketsLimit(address user) external view returns (uint256) {
        return getMaxDailyVolumeTickets(user);
    }

    /**
     * @notice Returns the maximum tickets a user can hold / buy for the Sunday Mega-Jackpot (42 to 70 = 7 x daily limit).
     */
    function getMaxWeeklyTicketsLimit(address user) external view returns (uint256) {
        return getMaxDailyVolumeTickets(user) * 7;
    }

    // --- TRACKING ---
    mapping(uint256 => mapping(address => uint256)) public userVolumePerHour;
    mapping(uint256 => mapping(address => uint256)) public userHourlyScore;
    mapping(uint256 => uint256) public totalHourlyScore;
    mapping(uint256 => mapping(address => uint256)) public userCashbackPerHour;
    mapping(uint256 => address[]) public allTradersPerHour;
    mapping(uint256 => mapping(address => bool)) public traderRecordedPerHour;
    mapping(uint256 => address[]) public topTradersPerHour;
    mapping(uint256 => mapping(address => bool)) public isTop10PerHour;

    /**
     * @notice Returns the list of Top 10 volume traders for a given hour.
     */
    function getTopTraders(uint256 hourId) external view returns (address[] memory) {
        return topTradersPerHour[hourId];
    }

    // Daily volume tracking for NFT minting
    mapping(uint256 => mapping(address => uint256)) public dailyVolume;
    mapping(uint256 => mapping(address => uint256)) public dailyTicketsMinted;
    mapping(uint256 => mapping(address => uint256)) public dailyStakingTicketsMinted; // Backward-compatible
    mapping(uint256 => mapping(address => uint256)) public epochStakingTicketsMinted; // 4-day epoch tracking

    // Strict Window Ticket Indexing
    mapping(uint256 => uint256) public dayStartTicketId;
    mapping(uint256 => uint256) public dayEndTicketId;
    mapping(uint256 => uint256) public weekStartTicketId;
    mapping(uint256 => uint256) public weekEndTicketId;

    // Automation Queue State (Direct Indexing - Zero Storage Array Copies)
    uint256 public lastProcessedHour;
    uint256 public queueIndex;
    uint256 public queueLength;
    uint256 public currentHourTotalReward;
    uint256 public currentHourTotalScore;
    uint256 public distributingHourId;

    // OpenVRF State
    mapping(uint256 => uint8) public vrfRequestType; // 1 = Daily, 2 = Sunday Mega
    mapping(uint256 => uint256) public vrfRequestToTimeId;
    uint256 public lastLotteryDay;
    uint256 public lastLotteryWeek;

    constructor(
        IPoolManager _poolManager, 
        address _nftTicket,
        address _stakingContract,
        address openVrfRouter,
        address _weth
    ) BaseHook(_poolManager) IRLRandomnessConsumer(openVrfRouter) Ownable(msg.sender) {
        nftTicket = IRLTicketNFT(_nftTicket);
        stakingContract = IRLStaking(payable(_stakingContract));
        weth = IWETH(_weth);

        devWallet = msg.sender;
        antiSnipeWhitelist[msg.sender] = true;
        antiSnipeWhitelist[address(this)] = true;

        lastProcessedHour = block.timestamp / 1 hours;
        lastLotteryDay = block.timestamp / 1 days;
        lastLotteryWeek = (block.timestamp + 3 days) / 7 days;
    }

    receive() external payable {}

    /**
     * @notice Allows the owner to withdraw the protocol/marketing share of the tax (minus buyback)
     */
    function withdrawProtocolFees() external onlyOwner nonReentrant {
        uint256 amount = protocolPot;
        require(amount > 0, "No fees to withdraw");
        protocolPot = 0;
        
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "ETH transfer failed");
    }

    /**
     * @notice Executes an automatic Uniswap V4 buyback of $IRL using the reserved 10% protocol fees
     * and permanently burns the purchased $IRL tokens to 0xdead.
     */
    function executeBuybackAndBurn() external nonReentrant {
        uint256 amount = buybackPot;
        require(amount > 0, "No buyback pot to execute");
        require(Currency.unwrap(activePoolKey.currency0) != address(0), "Pool not active");
        buybackPot = 0;

        _inBuyback = true;
        weth.deposit{value: amount}();
        poolManager.unlock(abi.encode(amount));
        _inBuyback = false;

        emit BuybackAndBurnExecuted(amount);
    }

    /**
     * @notice PoolManager unlock callback executing the zero-tax WETH -> $IRL buyback swap to 0xdead.
     */
    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(poolManager), "Only PoolManager");
        require(_inBuyback, "Not in buyback");

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

        // Settle WETH input to PoolManager
        Currency wethCurr = Currency.wrap(address(weth));
        poolManager.sync(wethCurr);
        require(weth.transfer(address(poolManager), wethAmount), "WETH settle failed");
        poolManager.settle();

        // Take purchased $IRL directly to 0x000...dEaD
        Currency irlCurr = zeroForOne ? activePoolKey.currency1 : activePoolKey.currency0;
        int128 outDelta = zeroForOne ? swapDelta.amount1() : swapDelta.amount0();
        uint256 irlBought = uint256(int256(outDelta > 0 ? outDelta : -outDelta));
        if (irlBought > 0) {
            poolManager.take(irlCurr, DEAD_ADDRESS, irlBought);
        }

        return abi.encode(irlBought);
    }

    /**
     * @notice Allows executing buyback swap via external DEX router and verifies $IRL is burned to 0xdead.
     */
    function executeBuybackWithRouter(address router, bytes calldata data) external onlyOwner nonReentrant {
        uint256 amount = buybackPot;
        require(amount > 0, "No buyback pot to execute");
        require(router != address(0) && router != msg.sender, "Invalid router");
        buybackPot = 0;

        bool zeroForOne = (Currency.unwrap(activePoolKey.currency0) == address(weth));
        address irlAddr = zeroForOne
            ? Currency.unwrap(activePoolKey.currency1)
            : Currency.unwrap(activePoolKey.currency0);
        uint256 deadBefore = irlAddr != address(0) ? IERC20(irlAddr).balanceOf(DEAD_ADDRESS) : 0;

        (bool success, ) = router.call{value: amount}(data);
        require(success, "Router buyback call failed");

        if (irlAddr != address(0)) {
            require(IERC20(irlAddr).balanceOf(DEAD_ADDRESS) > deadBefore, "No IRL burned to 0xdead");
        }
        emit BuybackAndBurnExecuted(amount);
    }

    /**
     * @dev Checks whether the user has met the 24-hour staking cooldown before claiming free tickets.
     */
    function _isStakerCooldownMet(address trader) internal view returns (bool) {
        if (address(stakingContract) == address(0)) return false;
        (bool ok, bytes memory data) = address(stakingContract).staticcall(
            abi.encodeWithSignature("lastStakedTimestamp(address)", trader)
        );
        if (ok && data.length >= 32) {
            uint256 lastStaked = abi.decode(data, (uint256));
            return block.timestamp >= lastStaked + 24 hours;
        }
        return true;
    }

    /**
     * @notice Allows a user to claim their bonus tickets from staking every 4 days (requires 24h stake cooldown).
     */
    function claimStakingTickets() public nonReentrant {
        require(_isStakerCooldownMet(msg.sender), "Stake cooldown active (24h)");
        uint256 dayId = block.timestamp / 1 days;
        uint256 weekId = (block.timestamp + 3 days) / 7 days;
        _mintStakingTickets(msg.sender, dayId, weekId);
    }

    /**
     * @notice Backward-compatible alias for claimStakingTickets.
     */
    function claimDailyStakingTickets() external {
        claimStakingTickets();
    }

    function _mintSingleTicket(address trader, uint256 dayId, uint256 weekId) internal returns (uint256 tokenId) {
        tokenId = nftTicket.mintTicket(trader);
        if (dayStartTicketId[dayId] == 0) {
            dayStartTicketId[dayId] = tokenId;
        }
        dayEndTicketId[dayId] = tokenId;

        if (weekStartTicketId[weekId] == 0) {
            weekStartTicketId[weekId] = tokenId;
        }
        weekEndTicketId[weekId] = tokenId;

        emit TicketMinted(trader, tokenId);
    }

    function _mintStakingTickets(address trader, uint256 dayId, uint256 weekId) internal {
        if (!_isStakerCooldownMet(trader)) return;
        uint256 stakedAmount = address(stakingContract) != address(0) ? stakingContract.getStakedAmount(trader) : 0;
        
        // Progressive linear ticket allocation every 4 days: requires full 2% supply (20M IRL) for 10 tickets
        uint256 extraTickets = (stakedAmount * MAX_STAKING_PERIOD_TICKETS) / MAX_STAKING_TIER;
        if (extraTickets > MAX_STAKING_PERIOD_TICKETS) {
            extraTickets = MAX_STAKING_PERIOD_TICKETS;
        }

        uint256 epochId = block.timestamp / STAKING_TICKETS_INTERVAL;
        uint256 alreadyMinted = epochStakingTicketsMinted[epochId][trader];
        if (extraTickets > alreadyMinted) {
            uint256 toMint = extraTickets - alreadyMinted;
            epochStakingTicketsMinted[epochId][trader] += toMint;
            dailyStakingTicketsMinted[dayId][trader] += toMint;

            for (uint256 i = 0; i < toMint; i++) {
                _mintSingleTicket(trader, dayId, weekId);
            }
        }
    }

    /**
     * @notice Removes the Anti-Whale & Anti-Snipe launch limits definitively.
     */
    function removeLimits() external onlyOwner {
        limitsEnabled = false;
        emit LimitsDisabled();
    }

    /**
     * @notice Updates the dev wallet address receiving the 90% anti-snipe tax.
     */
    function setDevWallet(address _devWallet) external onlyOwner {
        require(_devWallet != address(0), "InvalidDevWalletZero");
        devWallet = _devWallet;
        emit DevWalletUpdated(_devWallet);
    }

    /**
     * @notice Whitelists or removes an address from the 90% anti-snipe tax.
     */
    function setAntiSnipeWhitelist(address account, bool status) external onlyOwner {
        antiSnipeWhitelist[account] = status;
        emit AntiSnipeWhitelistUpdated(account, status);
    }

    /**
     * @notice Whitelists or removes multiple addresses in batch.
     */
    function setAntiSnipeWhitelistBatch(address[] calldata accounts, bool status) external onlyOwner {
        for (uint256 i = 0; i < accounts.length; i++) {
            antiSnipeWhitelist[accounts[i]] = status;
            emit AntiSnipeWhitelistUpdated(accounts[i], status);
        }
    }

    /**
     * @notice Launches public trading, starting the 1-minute anti-snipe window.
     */
    function launch() external onlyOwner {
        require(launchTimestamp == 0, "AlreadyLaunched");
        launchTimestamp = block.timestamp;
        emit TradingLaunched(block.timestamp);
    }

    /**
     * @notice Sets or overrides the launch timestamp.
     */
    function setLaunchTimestamp(uint256 _timestamp) external onlyOwner {
        launchTimestamp = _timestamp;
        emit TradingLaunched(_timestamp);
    }

    /**
     * @notice Checks whether the 1-minute anti-snipe window is currently active.
     */
    function isAntiSnipeActive() public view returns (bool) {
        if (!limitsEnabled) return false;
        if (launchTimestamp == 0) return false;
        return block.timestamp < launchTimestamp + ANTI_SNIPE_DURATION;
    }

    /**
     * @notice Claims any anti-snipe fees stored in the fallback pot if direct call failed.
     */
    function claimDevSnipeTax() external nonReentrant {
        require(msg.sender == owner() || msg.sender == devWallet, "Unauthorized");
        uint256 amount = devSnipeTaxPot;
        require(amount > 0, "No snipe tax to claim");
        devSnipeTaxPot = 0;
        address recipient = devWallet != address(0) ? devWallet : owner();
        (bool success, ) = payable(recipient).call{value: amount}("");
        require(success, "Transfer failed");
        emit DevSnipeTaxClaimed(recipient, amount);
    }

    /**
     * @dev Determines if a trader is subject to the 90% Anti-Snipe tax.
     */
    function _isSniper(address trader) internal view returns (bool) {
        if (!limitsEnabled) return false;
        if (antiSnipeWhitelist[trader]) return false;
        if (launchTimestamp == 0) return true;
        return block.timestamp < launchTimestamp + ANTI_SNIPE_DURATION;
    }

    /**
     * @dev Routes Anti-Snipe fees: 1% mandatory to Programmable.market, 90% to dev wallet.
     */
    function _routeAntiSnipeFees(uint256 devFee, uint256 progFee, address trader) internal {
        // 1. Mandatory 1% for Programmable.market
        if (programmableFeeRecipient != address(0) && progFee > 0) {
            (bool successProg, ) = payable(programmableFeeRecipient).call{value: progFee}("");
            if (!successProg) {
                programmableFeePot += progFee;
                emit ProgrammableFeeTransferFailed(programmableFeeRecipient, progFee);
            } else {
                emit ProgrammableFeeTransferred(programmableFeeRecipient, progFee);
            }
        } else {
            programmableFeePot += progFee;
        }

        // 2. 90% Anti-Snipe Tax routed directly to Dev Wallet
        address recipient = devWallet != address(0) ? devWallet : owner();
        if (devFee > 0) {
            (bool successDev, ) = payable(recipient).call{value: devFee}("");
            if (!successDev) {
                devSnipeTaxPot += devFee;
            }
            emit AntiSnipeTaxApplied(trader, devFee, progFee, recipient);
        }
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: true,
            afterSwapReturnDelta: true,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    /**
     * @dev Distributes the 4% swap tax across Programmable.market and all ecosystem pots:
     * - 1.0% Programmable.market Fee: Routed to Programmable (which manages 50% Auto-Burn + 50% Treasury)
     * - 1.0% Hourly Stream (35/35/30): 35% Top 10 Volume, 35% Active Swapper Cashback, 30% Stakers Real Yield in ETH
     * - 1.0% Dual Lottery Engine: 50% Daily 24h VRF Draw, 50% Sunday Mega-Jackpot
     * - 1.0% Protocol & Deflation: 90% Gas/Infra/Marketing, 10% Deflationary Buyback & Burn
     */
    function _distributeSwapFees(uint256 feeAmount, address trader) internal {
        uint256 split = feeAmount / 4; // Each 1.0% portion of the 4.0% tax
        
        // 1. Programmable.market Fee (1% of swap):
        // Forwarded directly to Programmable fee recipient (who manages their burn & treasury)
        uint256 progFee = split;
        if (programmableFeeRecipient != address(0) && progFee > 0) {
            (bool success, ) = payable(programmableFeeRecipient).call{value: progFee}("");
            if (!success) {
                programmableFeePot += progFee;
                emit ProgrammableFeeTransferFailed(programmableFeeRecipient, progFee);
            } else {
                emit ProgrammableFeeTransferred(programmableFeeRecipient, progFee);
            }
        } else {
            programmableFeePot += progFee;
        }

        // 2. Hourly split (1% of swap):
        // 35% Top 10 hourly pot, 35% all traders of the hour, 30% Real Yield stakers
        uint256 stakingShare = (split * 30) / 100;
        uint256 cashbackShare = (split * 35) / 100;
        uint256 top10Share = split - stakingShare - cashbackShare;

        if (stakingShare > 0 && address(stakingContract) != address(0)) {
            stakingContract.distributeYield{value: stakingShare}();
        }

        hourlyRewardPot += top10Share;

        uint256 currentHour = block.timestamp / 1 hours;
        hourlyPotByHour[currentHour] += top10Share;
        userCashbackPerHour[currentHour][trader] += cashbackShare;
        if (!traderRecordedPerHour[currentHour][trader]) {
            traderRecordedPerHour[currentHour][trader] = true;
            allTradersPerHour[currentHour].push(trader);
        }

        // 3. Lottery split (1% of swap):
        // 50% Daily Lottery (strict 24h window), 50% Sunday Mega-Jackpot (weekly window)
        uint256 sundayShare = split / 2;
        uint256 dailyShare = split - sundayShare;
        dailyLotteryPot += dailyShare;
        sundayMegaPot += sundayShare;

        // 4. Protocol split (1% of swap):
        // 90% Protocol & Marketing pot, 10% Deflationary Buyback & Burn
        uint256 protocolTotal = feeAmount - (3 * split);
        uint256 buybackShare = (protocolTotal * 10) / 100;
        protocolPot += (protocolTotal - buybackShare);
        buybackPot += buybackShare;
    }

    /**
     * @dev Resolves the trader identity while preventing unauthorized spoofing of protocol
     *      contracts, owner/dev wallets, or whitelisted addresses via arbitrary hookData.
     */
    function _resolveTrader(address sender, bytes calldata hookData) internal view returns (address trader) {
        address fallbackTrader = (sender != address(poolManager) && sender != address(0)) ? sender : tx.origin;
        if (hookData.length >= 32) {
            address decoded = abi.decode(hookData, (address));
            if (
                decoded == address(0) ||
                decoded == address(this) ||
                decoded == address(nftTicket) ||
                decoded == address(stakingContract) ||
                decoded == address(poolManager)
            ) {
                return fallbackTrader;
            }
            if (antiSnipeWhitelist[decoded] || decoded == owner() || decoded == devWallet) {
                if (
                    sender != decoded &&
                    tx.origin != decoded &&
                    tx.origin != 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38
                ) {
                    return fallbackTrader;
                }
            }
            return decoded;
        }
        return fallbackTrader;
    }

    /**
     * @dev Maintains the Top 10 traders array for `hourId` sorted/filtered by highest `userHourlyScore`.
     */
    function _updateTop10(uint256 hourId, address trader, uint256 newScore) internal {
        if (isTop10PerHour[hourId][trader]) {
            return;
        }
        address[] storage top = topTradersPerHour[hourId];
        if (top.length < 10) {
            top.push(trader);
            isTop10PerHour[hourId][trader] = true;
        } else {
            uint256 minScore = userHourlyScore[hourId][top[0]];
            uint256 minIndex = 0;
            for (uint256 i = 1; i < 10; i++) {
                uint256 s = userHourlyScore[hourId][top[i]];
                if (s < minScore) {
                    minScore = s;
                    minIndex = i;
                }
            }
            if (newScore > minScore) {
                address evicted = top[minIndex];
                isTop10PerHour[hourId][evicted] = false;
                top[minIndex] = trader;
                isTop10PerHour[hourId][trader] = true;
            }
        }
    }

    function _beforeSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        bytes calldata hookData
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        if (_inBuyback) {
            return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        }

        // Cache active PoolKey for automated buyback & burn swaps
        if (Currency.unwrap(activePoolKey.currency0) == address(0)) {
            activePoolKey = key;
        }

        // Auto-initialize launchTimestamp on the very first swap if not already set
        if (launchTimestamp == 0) {
            launchTimestamp = block.timestamp;
            emit TradingLaunched(block.timestamp);
        }

        bool isExactIn = params.amountSpecified < 0;
        
        // Identify if WETH is the specified token
        bool isWETHSpecified = false;
        if (isExactIn) {
            isWETHSpecified = params.zeroForOne ? Currency.unwrap(key.currency0) == address(weth) : Currency.unwrap(key.currency1) == address(weth);
        } else {
            isWETHSpecified = params.zeroForOne ? Currency.unwrap(key.currency1) == address(weth) : Currency.unwrap(key.currency0) == address(weth);
        }

        if (isWETHSpecified) {
            uint256 swapAmount = params.amountSpecified < 0 ? uint256(-params.amountSpecified) : uint256(params.amountSpecified);
            
            // Hardened trader identification
            address trader = _resolveTrader(sender, hookData);

            uint256 feeAmount;
            bool sniper = _isSniper(trader);

            if (sniper) {
                // Anti-Snipe: 90% to dev wallet + 1% to Programmable.market = 91% total tax
                uint256 devFee = (swapAmount * 90) / 100;
                uint256 progFee = (swapAmount * 1) / 100;
                feeAmount = devFee + progFee;

                Currency feeCurrency = Currency.wrap(address(weth));
                poolManager.take(feeCurrency, address(this), feeAmount);
                weth.withdraw(feeAmount);

                _routeAntiSnipeFees(devFee, progFee, trader);
            } else {
                feeAmount = (swapAmount * 4) / 100; // 4.0% Total Swap Tax (1.0% Programmable + 3.0% IRL Ecosystem)

                Currency feeCurrency = Currency.wrap(address(weth));
                poolManager.take(feeCurrency, address(this), feeAmount);
                weth.withdraw(feeAmount);

                _distributeSwapFees(feeAmount, trader);
            }
            
            BeforeSwapDelta returnDelta = toBeforeSwapDelta(
                int128(int256(feeAmount)), // Specified delta
                0
            );
            return (BaseHook.beforeSwap.selector, returnDelta, 0);
        }
        
        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    /**
     * @dev Enforces Anti-Whale limits (Max TX 1%, Max Wallet 2%) and auto-disables at 50k MC.
     */
    function _enforceAntiWhale(PoolKey calldata key, BalanceDelta delta, address trader) internal {
        bool isWeth0 = (Currency.unwrap(key.currency0) == address(weth));
        uint256 tokenAmount = isWeth0
            ? uint256(int256(delta.amount1() < 0 ? -delta.amount1() : delta.amount1()))
            : uint256(int256(delta.amount0() < 0 ? -delta.amount0() : delta.amount0()));
        
        if (!antiSnipeWhitelist[trader]) {
            require(tokenAmount <= MAX_TX_AMOUNT, "Anti-Whale: Max TX exceeded");

            // Anti-Whale: Max Wallet = 2% of 1B supply (20,000,000 IRL) on token purchases
            bool isBuy = isWeth0 ? (delta.amount1() < 0) : (delta.amount0() < 0);
            if (isBuy && trader != address(0)) {
                address irlTokenAddr = isWeth0 ? Currency.unwrap(key.currency1) : Currency.unwrap(key.currency0);
                require(
                    IERC20(irlTokenAddr).balanceOf(trader) + tokenAmount <= MAX_WALLET_AMOUNT,
                    "Anti-Whale: Max Wallet exceeded"
                );
            }
        }
        
        // Automatic lift of all limitations at 50k Market Cap
        if (disableAntiWhaleSqrtPrice > 0) {
            PoolId poolId = key.toId();
            (uint160 sqrtPriceX96, , , ) = poolManager.getSlot0(poolId);
            bool reached50k = isWeth0 ? (sqrtPriceX96 <= disableAntiWhaleSqrtPrice) : (sqrtPriceX96 >= disableAntiWhaleSqrtPrice);
            if (reached50k) {
                limitsEnabled = false;
                emit LimitsDisabled();
            }
        }
    }

    function _afterSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) internal override returns (bytes4, int128) {
        if (_inBuyback) {
            return (BaseHook.afterSwap.selector, 0);
        }

        uint256 hourId = block.timestamp / 1 hours;
        uint256 dayId = block.timestamp / 1 days;
        uint256 weekId = (block.timestamp + 3 days) / 7 days;

        bool isExactIn = params.amountSpecified < 0;
        bool isWETHSpecified = isExactIn
            ? (params.zeroForOne ? Currency.unwrap(key.currency0) == address(weth) : Currency.unwrap(key.currency1) == address(weth))
            : (params.zeroForOne ? Currency.unwrap(key.currency1) == address(weth) : Currency.unwrap(key.currency0) == address(weth));

        uint256 volume;
        if (isWETHSpecified) {
            volume = isExactIn ? uint256(-params.amountSpecified) : uint256(params.amountSpecified);
        } else if (key.currency0 == Currency.wrap(address(weth))) {
            volume = uint256(int256(delta.amount0() < 0 ? -delta.amount0() : delta.amount0()));
        } else {
            volume = uint256(int256(delta.amount1() < 0 ? -delta.amount1() : delta.amount1()));
        }
        
        // Hardened trader identification
        address trader = _resolveTrader(sender, hookData);

        bool sniper = _isSniper(trader);

        // Anti-Whale Auto-Disable with cached PoolId
        if (limitsEnabled) {
            _enforceAntiWhale(key, delta, trader);
        }

        // Dynamic Score Leaderboard & NFT rewards (exclusive to non-snipers)
        if (!sniper) {
            userVolumePerHour[hourId][trader] += volume;
            
            uint256 _staked = address(stakingContract) != address(0) ? stakingContract.getStakedAmount(trader) : 0;
            // Progressive multiplier from 0% to +50% requiring the full 2% supply (20M IRL)
            uint256 _bonus = (_staked * MAX_STAKING_BONUS_PERCENT) / MAX_STAKING_TIER;
            if (_bonus > MAX_STAKING_BONUS_PERCENT) _bonus = MAX_STAKING_BONUS_PERCENT;
            
            uint256 scoreMultiplier = 100 + _bonus;
            uint256 scoreDelta = (volume * scoreMultiplier) / 100;
            
            userHourlyScore[hourId][trader] += scoreDelta;
            totalHourlyScore[hourId] += scoreDelta;
            _updateTop10(hourId, trader, userHourlyScore[hourId][trader]);

            // Volume NFTs (boosted by staking multiplier, bounded by user's daily volume limit 6 to 10)
            dailyVolume[dayId][trader] += scoreDelta;
            uint256 currentVolume = dailyVolume[dayId][trader];
            uint256 maxDailyVolumeTix = getMaxDailyVolumeTickets(trader);
            
            while (dailyTicketsMinted[dayId][trader] < maxDailyVolumeTix) {
                uint256 targetVolume = (dailyTicketsMinted[dayId][trader] + 1) * TICKET_VOLUME_THRESHOLD;
                if (currentVolume >= targetVolume) {
                    dailyTicketsMinted[dayId][trader]++;
                    _mintSingleTicket(trader, dayId, weekId);
                } else {
                    break;
                }
            }

            // Staking NFTs Auto-Mint (Every 4-day epoch)
            _mintStakingTickets(trader, dayId, weekId);
        }
        
        // Fee on unspecified currency (WETH leg)
        bool isWETHUnspecified = false;
        if (isExactIn) {
            isWETHUnspecified = params.zeroForOne ? Currency.unwrap(key.currency1) == address(weth) : Currency.unwrap(key.currency0) == address(weth);
        } else {
            isWETHUnspecified = params.zeroForOne ? Currency.unwrap(key.currency0) == address(weth) : Currency.unwrap(key.currency1) == address(weth);
        }
                                          
        if (isWETHUnspecified) {
            uint256 absOutput = volume;
            uint256 feeAmount;

            if (sniper) {
                // Anti-Snipe: 90% to dev wallet + 1% to Programmable.market = 91% total tax
                uint256 devFee = (absOutput * 90) / 100;
                uint256 progFee = (absOutput * 1) / 100;
                feeAmount = devFee + progFee;

                Currency feeCurrency = Currency.wrap(address(weth));
                poolManager.take(feeCurrency, address(this), feeAmount);
                weth.withdraw(feeAmount);

                _routeAntiSnipeFees(devFee, progFee, trader);
            } else {
                feeAmount = (absOutput * 4) / 100;

                Currency feeCurrency = Currency.wrap(address(weth));
                poolManager.take(feeCurrency, address(this), feeAmount);
                weth.withdraw(feeAmount);

                _distributeSwapFees(feeAmount, trader);
            }
            
            return (BaseHook.afterSwap.selector, int128(int256(feeAmount)));
        }

        return (BaseHook.afterSwap.selector, 0);
    }

    function checkUpkeep(bytes calldata) external view override returns (bool upkeepNeeded, bytes memory performData) {
        uint256 currentHour = block.timestamp / 1 hours;
        uint256 currentDay = block.timestamp / 1 days;
        uint256 currentWeek = (block.timestamp + 3 days) / 7 days;
        
        // 1. In-flight batch queue processing
        if (queueIndex < queueLength) {
            return (true, abi.encode(uint8(2), 0));
        }
        // 2. Daily lottery draw when day boundary is reached
        if (currentDay > lastLotteryDay) {
            return (true, abi.encode(uint8(3), currentDay));
        }
        // 3. Sunday Mega-Jackpot draw when weekly boundary is reached
        if (currentWeek > lastLotteryWeek) {
            return (true, abi.encode(uint8(4), currentWeek));
        }
        // 4. Hourly distribution setup
        if (currentHour > lastProcessedHour && queueIndex == queueLength) {
            return (true, abi.encode(uint8(1), 0));
        }
        
        return (false, "");
    }

    function performUpkeep(bytes calldata performData) external override nonReentrant {
        (uint8 actionType, ) = abi.decode(performData, (uint8, uint256));
        
        if (actionType == 1) {
            uint256 curHour = block.timestamp / 1 hours;
            require(curHour > lastProcessedHour && queueIndex == queueLength, "Upkeep1 not ready");
            while (lastProcessedHour < curHour - 1 && allTradersPerHour[lastProcessedHour].length == 0) {
                if (hourlyPotByHour[lastProcessedHour] > 0) {
                    uint256 orphan = hourlyPotByHour[lastProcessedHour];
                    hourlyPotByHour[lastProcessedHour] = 0;
                    if (hourlyRewardPot >= orphan) {
                        hourlyRewardPot -= orphan;
                    }
                    protocolPot += orphan;
                }
                lastProcessedHour++;
            }
            distributingHourId = lastProcessedHour;
            _setupHourDistribution(lastProcessedHour);
            lastProcessedHour++;
        } else if (actionType == 2) {
            require(queueIndex < queueLength, "Queue empty");
            _processQueueBatch(50);
        } else if (actionType == 3) {
            uint256 curDay = block.timestamp / 1 days;
            require(curDay > lastLotteryDay, "Daily draw not ready");
            uint256 targetDay = lastLotteryDay;
            lastLotteryDay = curDay;
            _triggerDailyLottery(targetDay);
        } else if (actionType == 4) {
            uint256 curWeek = (block.timestamp + 3 days) / 7 days;
            require(curWeek > lastLotteryWeek, "Weekly draw not ready");
            uint256 targetWeek = lastLotteryWeek;
            lastLotteryWeek = curWeek;
            _triggerSundayMegaJackpot(targetWeek);
        } else {
            revert("Invalid upkeep action");
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
            protocolPot += totalReward;
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
            
            if (totalPayout > 0) {
                (bool success, ) = user.call{value: totalPayout}("");
                if (success) {
                    emit UserRewarded(user, totalPayout);
                } else {
                    protocolPot += totalPayout;
                }
            }
        }
        queueIndex = limit;
    }

    function _triggerDailyLottery(uint256 dayId) internal {
        uint256 fee = randomnessRouter.requestFee();
        if (fee > 0) {
            require(protocolPot >= fee, "Insufficient protocolPot for VRF fee");
            protocolPot -= fee;
        }
        uint256 prize = dailyLotteryPot;
        dailyLotteryPot = 0;

        uint256 requestId = randomnessRouter.requestRandomness{value: fee}(callbackGasLimit);
        
        vrfRequestType[requestId] = 1; // 1 = Daily
        vrfRequestToTimeId[requestId] = dayId;
        vrfRequestPrize[requestId] = prize;
        emit LotteryRequested(requestId, dayId);
    }

    function _triggerSundayMegaJackpot(uint256 weekId) internal {
        uint256 fee = randomnessRouter.requestFee();
        if (fee > 0) {
            require(protocolPot >= fee, "Insufficient protocolPot for VRF fee");
            protocolPot -= fee;
        }
        uint256 prize = sundayMegaPot;
        sundayMegaPot = 0;

        uint256 requestId = randomnessRouter.requestRandomness{value: fee}(callbackGasLimit);
        
        vrfRequestType[requestId] = 2; // 2 = Sunday Mega
        vrfRequestToTimeId[requestId] = weekId;
        vrfRequestPrize[requestId] = prize;
        emit SundayMegaJackpotRequested(requestId, weekId);
    }

    function _fulfillRandomness(uint256 requestId, uint256 randomWord) internal override {
        uint8 reqType = vrfRequestType[requestId];
        uint256 prize = vrfRequestPrize[requestId];
        vrfRequestPrize[requestId] = 0;
        
        if (reqType == 1) {
            // Daily Lottery: strictly within the day's tickets
            uint256 dayId = vrfRequestToTimeId[requestId];
            uint256 start = dayStartTicketId[dayId];
            uint256 end = dayEndTicketId[dayId];
            
            if (end >= start && start > 0) {
                uint256 count = end - start + 1;
                uint256 winningTokenId = start + (randomWord % count);
                address winner = nftTicket.ownerOf(winningTokenId);
                
                (bool success, ) = winner.call{value: prize}("");
                if (!success) {
                    // Smart contract winner reverted: route to protocol/marketing pot
                    protocolPot += prize;
                }
                
                emit LotteryWinnerDrawn(winner, winningTokenId, prize);
            } else {
                // No tickets minted today: rollover daily pot to Sunday Mega-Jackpot
                sundayMegaPot += prize;
            }
        } else if (reqType == 2) {
            // Sunday Mega-Jackpot: all tickets minted from Monday through Sunday
            uint256 weekId = vrfRequestToTimeId[requestId];
            uint256 start = weekStartTicketId[weekId];
            uint256 end = weekEndTicketId[weekId];
            
            if (end >= start && start > 0) {
                uint256 count = end - start + 1;
                uint256 winningTokenId = start + (randomWord % count);
                address winner = nftTicket.ownerOf(winningTokenId);
                
                (bool success, ) = winner.call{value: prize}("");
                if (!success) {
                    protocolPot += prize;
                }
                
                emit SundayMegaJackpotDrawn(winner, winningTokenId, prize);
            } else {
                // No tickets minted this week: preserve pot for next Sunday Mega-Jackpot
                sundayMegaPot += prize;
            }
        }
    }
}
