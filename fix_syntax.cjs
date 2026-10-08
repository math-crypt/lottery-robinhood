const fs = require('fs');

['bot/index.js', 'bot/test-bot.js'].forEach(file => {
    let code = fs.readFileSync(file, 'utf8');
    code = code.replace(/Call the `approve` function:/g, 'Call the \\`approve\\` function:');
    code = code.replace(/- `spender`:/g, '- \\`spender\\`:');
    code = code.replace(/- `amount`:/g, '- \\`amount\\`:');
    code = code.replace(/call `stake`/g, 'call \\`stake\\`');
    fs.writeFileSync(file, code);
});
console.log("Fixed");
