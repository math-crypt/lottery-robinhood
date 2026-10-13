// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

interface IIRLHookQuota {
    function getMaxWeeklyTicketsLimit(address user) external view returns (uint256);
}

/**
 * @title IRL Ticket NFT
 * @dev NFT contract representing lottery tickets.
 * Only the owner (which will be the Uniswap V4 Hook contract) can mint new tickets.
 * Secondary transfers enforce the recipient's dynamic weekly holding limit (42 to 70 tickets).
 */
contract IRLTicketNFT is ERC721, Ownable {
    uint256 private _nextTokenId;

    constructor(address initialOwner) ERC721("IRL Lottery Ticket", "IRLT") Ownable(initialOwner) {
        // Start token IDs at 1
        _nextTokenId = 1;
    }

    /**
     * @notice Enforces the dynamic weekly holding cap (42 to 70 tickets based on staked $IRL)
     * on secondary market / P2P transfers (when `from != address(0)` and `to != address(0)`).
     */
    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        address from = _ownerOf(tokenId);
        if (from != address(0) && to != address(0)) {
            address hookAddr = owner();
            if (hookAddr.code.length > 0) {
                (bool ok, bytes memory data) = hookAddr.staticcall(
                    abi.encodeWithSelector(IIRLHookQuota.getMaxWeeklyTicketsLimit.selector, to)
                );
                if (ok && data.length >= 32) {
                    uint256 maxWeekly = abi.decode(data, (uint256));
                    require(balanceOf(to) + 1 <= maxWeekly, "IRLTicketNFT: Weekly ticket holding cap exceeded");
                }
            }
        }
        return super._update(to, tokenId, auth);
    }

    /**
     * @notice Mints a new lottery ticket to the specified address.
     * @dev Only callable by the Hook (the owner of this contract).
     * @param to The address receiving the ticket.
     * @return tokenId The ID of the minted ticket.
     */
    function mintTicket(address to) external onlyOwner returns (uint256) {
        uint256 tokenId = _nextTokenId++;
        _mint(to, tokenId);
        return tokenId;
    }

    /**
     * @notice Returns the total number of tickets minted so far.
     */
    function totalTicketsMinted() external view returns (uint256) {
        return _nextTokenId - 1;
    }

    // Optional: Set a base URI for visual tickets later
    string private _baseTokenURI;

    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    function setBaseURI(string memory baseURI) external onlyOwner {
        _baseTokenURI = baseURI;
    }
}
