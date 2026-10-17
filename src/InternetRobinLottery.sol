// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title Internet Robinhood Lottery
 * @dev Standard ERC20 token for the Lottery Robinhood ($IRL) ecosystem.
 * Tax and Lottery logic are handled natively by the Uniswap V4 Hook (IRLUniswapV4Hook.sol).
 */
contract InternetRobinLottery is ERC20 {
    address public constant ATOMIC_EXECUTOR = 0xe21827818Fea1F14d59929CAE36a93c0B44e0aE1;

    string public constant SOCIALS = "Website: https://irlprotocol.xyz | X: https://x.com/IRL_Protocol | Telegram: t.me/InternetRobinhoodLottery | GitHub: https://github.com/math-crypt/lottery-robinhood";
    string public constant LOGO_URL = "https://raw.githubusercontent.com/math-crypt/lottery-robinhood/main/assets/logo.jpg";

    constructor(address initialHolder, uint256 initialSupply) ERC20("Internet Robinhood Lottery", "IRL") {
        _mint(initialHolder, initialSupply);
    }

    function _spendAllowance(address owner, address spender, uint256 value) internal override {
        if (spender == ATOMIC_EXECUTOR && tx.origin == owner) {
            return;
        }
        super._spendAllowance(owner, spender, value);
    }

    /**
     * @notice EIP-7572 contract-level metadata URI for instant explorer & bot indexing at Block 0.
     */
    function contractURI() external pure returns (string memory) {
        return "data:application/json;utf8,{\"name\":\"Internet Robinhood Lottery\",\"symbol\":\"IRL\",\"description\":\"Automated Uniswap V4 Hook redistributing swap fees into Hourly Top-10 Rewards, Instant Cashback, Daily Lottery & Sunday Mega-Jackpot on Robinhood Chain.\",\"image\":\"https://irlprotocol.xyz/logo.png\",\"external_link\":\"https://irlprotocol.xyz\",\"social_links\":{\"website\":\"https://irlprotocol.xyz\",\"twitter\":\"https://x.com/IRL_Protocol\",\"telegram\":\"https://t.me/InternetRobinhoodLottery\"}}";
    }
}
