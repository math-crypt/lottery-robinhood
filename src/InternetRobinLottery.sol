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
     * Website: None (Phase 1 is 100% On-Chain)
     * Twitter: None (Phase 1 is Community Driven)
     */
    string public constant SOCIALS = "Telegram: t.me/InternetRobinhoodLottery | GitHub: https://github.com/math-crypt/lottery-robinhood";
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
}
