const fs = require('fs');

let code = fs.readFileSync('src/IRLUniswapV4Hook.sol', 'utf8');

// 1. Add new state variables and replace old ones
code = code.replace('mapping(uint256 => mapping(address => uint256)) public userVolumePerHour;\n    mapping(uint256 => address[10]) public topTradersPerHour;',
`mapping(uint256 => mapping(address => uint256)) public userVolumePerHour;
    mapping(uint256 => mapping(address => uint256)) public userHourlyScore;
    mapping(uint256 => uint256) public totalHourlyScore;`);

// Add currentHourTotalReward and currentHourTotalScore to Automation Queue State
code = code.replace('uint256 public queueRewardPerUser;',
`uint256 public currentHourTotalReward;
    uint256 public currentHourTotalScore;`);

// 2. Remove event Top10Updated
code = code.replace('event Top10Updated(address indexed user, uint256 volume, uint256 currentHour);\n', '');

// 3. In _afterSwap, replace leaderboard logic
const leaderboardOld = `        // Leaderboard
        userVolumePerHour[hourId][trader] += volume;
        _updateTop10(hourId, trader, userVolumePerHour[hourId][trader]);`;

const leaderboardNew = `        // Dynamic Score Leaderboard
        userVolumePerHour[hourId][trader] += volume;
        
        uint256 _staked = address(stakingContract) != address(0) ? stakingContract.getStakedAmount(trader) : 0;
        uint256 _bonus = (_staked / 10_000 ether);
        if (_bonus > 50) _bonus = 50;
        
        uint256 scoreMultiplier = 100 + _bonus;
        uint256 scoreDelta = (volume * scoreMultiplier) / 100;
        
        userHourlyScore[hourId][trader] += scoreDelta;
        totalHourlyScore[hourId] += scoreDelta;`;

code = code.replace(leaderboardOld, leaderboardNew);

// 4. Remove _updateTop10 function completely
const top10FuncStart = code.indexOf('    function _updateTop10(uint256 hourId');
const top10FuncEnd = code.indexOf('    }', top10FuncStart) + 5;
if (top10FuncStart !== -1) {
    // Need to find the exact end of the function. Let's use regex.
    code = code.replace(/    function _updateTop10[\s\S]*?    }\n/, '');
}

// 5. Replace _setupHourDistribution
const setupOld = `    function _setupHourDistribution(uint256 hourId) internal {
        uint256 totalReward = hourlyRewardPot;
        hourlyRewardPot = 0;
        
        address[] memory traders = allTradersPerHour[hourId];
        delete currentQueue;
        
        for (uint256 i = 0; i < traders.length; i++) {
            currentQueue.push(traders[i]);
        }
        
        uint256 top10Count = 0;
        address[10] memory top10 = topTradersPerHour[hourId];
        for (uint256 i = 0; i < 10; i++) {
            if (top10[i] != address(0)) {
                top10Count++;
            }
        }
        
        if (top10Count > 0) {
            queueRewardPerUser = totalReward / top10Count;
        } else {
            queueRewardPerUser = 0;
            protocolPot += totalReward;
        }
        
        queueIndex = 0;
        emit HourlyRewardsDistributed(hourId, totalReward);
    }`;

const setupNew = `    function _setupHourDistribution(uint256 hourId) internal {
        uint256 totalReward = hourlyRewardPot;
        hourlyRewardPot = 0;
        
        address[] memory traders = allTradersPerHour[hourId];
        delete currentQueue;
        
        for (uint256 i = 0; i < traders.length; i++) {
            currentQueue.push(traders[i]);
        }
        
        uint256 tScore = totalHourlyScore[hourId];
        if (tScore > 0) {
            currentHourTotalReward = totalReward;
            currentHourTotalScore = tScore;
        } else {
            currentHourTotalReward = 0;
            currentHourTotalScore = 0;
            protocolPot += totalReward;
        }
        
        queueIndex = 0;
        emit HourlyRewardsDistributed(hourId, totalReward);
    }`;
code = code.replace(setupOld, setupNew);

// 6. Replace _processQueueBatch
const processOld = `    function _processQueueBatch(uint256 batchSize) internal {
        uint256 limit = queueIndex + batchSize;
        if (limit > currentQueue.length) limit = currentQueue.length;

        uint256 hourId = lastProcessedHour;
        address[10] memory top10 = topTradersPerHour[hourId];

        for (uint256 i = queueIndex; i < limit; i++) {
            address user = currentQueue[i];
            uint256 totalPayout = userCashbackPerHour[hourId][user];
            
            bool isTop10 = false;
            for (uint256 j = 0; j < 10; j++) {
                if (top10[j] == user) {
                    isTop10 = true;
                    break;
                }
            }
            
            if (isTop10 && queueRewardPerUser > 0) {
                uint256 stakedAmount = address(stakingContract) != address(0) ? stakingContract.getStakedAmount(user) : 0;
                uint256 bonusPercentage = (stakedAmount / 10_000 ether);
                if (bonusPercentage > 50) bonusPercentage = 50;
                
                uint256 top10Reward = queueRewardPerUser + ((queueRewardPerUser * bonusPercentage) / 100);
                totalPayout += top10Reward;
            }
            
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
    }`;

const processNew = `    function _processQueueBatch(uint256 batchSize) internal {
        uint256 limit = queueIndex + batchSize;
        if (limit > currentQueue.length) limit = currentQueue.length;

        uint256 hourId = lastProcessedHour;

        for (uint256 i = queueIndex; i < limit; i++) {
            address user = currentQueue[i];
            uint256 totalPayout = userCashbackPerHour[hourId][user];
            
            if (currentHourTotalScore > 0) {
                uint256 userScore = userHourlyScore[hourId][user];
                uint256 potShare = (currentHourTotalReward * userScore) / currentHourTotalScore;
                totalPayout += potShare;
            }
            
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
    }`;
code = code.replace(processOld, processNew);

fs.writeFileSync('src/IRLUniswapV4Hook.sol', code);
console.log("Hook refactored");
