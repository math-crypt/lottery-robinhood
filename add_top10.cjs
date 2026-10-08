const fs = require('fs');

function updateFile(filename) {
    let code = fs.readFileSync(filename, 'utf8');

    code = code.replace(
        '"event HourlyRewardsDistributed(uint256 currentHour, uint256 totalPotDistributed)"',
        '"event HourlyRewardsDistributed(uint256 currentHour, uint256 totalPotDistributed)",\n  "function topTradersPerHour(uint256, uint256) view returns (address)",\n  "function userVolumePerHour(uint256, address) view returns (uint256)"'
    );

    const top10Cmd = `
bot.command('top10', async (ctx) => {
    try {
        const currentHour = Math.floor(Date.now() / 3600000);
        let text = '🏆 *Top 10 Traders of the Hour* 🏆\\n\\n';
        
        let traders = [];
        for (let i = 0; i < 10; i++) {
            const addr = await hookContract.topTradersPerHour(currentHour, i);
            if (addr !== '0x0000000000000000000000000000000000000000') {
                const vol = await hookContract.userVolumePerHour(currentHour, addr);
                traders.push({ addr, vol: ethers.formatEther(vol) });
            }
        }
        
        if (traders.length === 0) {
            text += 'No traders yet this hour! Be the first to secure the #1 spot and grab the ETH rewards! 🚀';
        } else {
            traders.sort((a, b) => parseFloat(b.vol) - parseFloat(a.vol));
            traders.forEach((t, i) => {
                const shortAddr = t.addr.substring(0, 6) + '...' + t.addr.substring(38);
                text += \`\${i + 1}️⃣ \${shortAddr} - \${parseFloat(t.vol).toFixed(2)} $IRL Volume\\n\`;
            });
            text += '\\n*Top traders share 50% of the Hourly Reward Pot!*';
        }
        
        ctx.reply(text, { parse_mode: 'Markdown' });
    } catch (e) {
        console.error(e);
        ctx.reply('❌ Unable to fetch Top 10 data right now.');
    }
});
`;

    code = code.replace(/bot\.command\('pot'/g, top10Cmd.trim() + "\n\nbot.command('pot'");
    fs.writeFileSync(filename, code);
}

updateFile('bot/index.js');
updateFile('bot/test-bot.js');
console.log("Done");
