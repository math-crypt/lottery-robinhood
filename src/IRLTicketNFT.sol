// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title IRL Ticket NFT
 * @dev NFT contract representing lottery tickets.
 * Only the owner (which will be the Uniswap V4 Hook contract) can mint new tickets.
 */
contract IRLTicketNFT is ERC721, Ownable {
    uint256 private _nextTokenId;

    // Optional: We can add an event if needed, but ERC721 already emits Transfer(address(0), to, tokenId) on mint.

    constructor(address initialOwner) ERC721("IRL Lottery Ticket", "IRLT") Ownable(initialOwner) {
        // Start token IDs at 1
        _nextTokenId = 1;
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
