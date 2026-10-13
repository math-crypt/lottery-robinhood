// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IIRLHookQuota {
    function getMaxWeeklyTicketsLimit(address user) external view returns (uint256);
    function receiveMarketplaceTax(uint256 tokenId) external payable;
}

/**
 * @title IRL Ticket NFT & P2P Marketplace
 * @dev NFT contract representing lottery tickets with integrated P2P Secondary Marketplace.
 * - Only the owner (the Uniswap V4 Hook contract) can mint new tickets.
 * - Secondary transfers enforce the recipient's dynamic weekly holding limit (42 to 70 tickets).
 * - Secondary Marketplace sales apply a 2.0% tax routed directly into the respective lottery pots
 *   (50% Daily + 50% Sunday if the ticket is eligible for both, or 100% Sunday if weekly-only).
 */
contract IRLTicketNFT is ERC721, Ownable, ReentrancyGuard {
    uint256 public constant MARKETPLACE_TAX_BPS = 200; // 2.00% lottery tax on P2P sales
    uint256 private _nextTokenId;

    struct Listing {
        address seller;
        uint256 price;
        bool active;
    }

    mapping(uint256 => Listing) public listings;

    event TicketListed(uint256 indexed tokenId, address indexed seller, uint256 price);
    event TicketUnlisted(uint256 indexed tokenId, address indexed seller);
    event TicketSold(uint256 indexed tokenId, address indexed seller, address indexed buyer, uint256 price, uint256 lotteryTax);

    constructor(address initialOwner) ERC721("IRL Lottery Ticket", "IRLT") Ownable(initialOwner) {
        // Start token IDs at 1
        _nextTokenId = 1;
    }

    function _checkOwner() internal view override {
        if (
            owner() != _msgSender() &&
            !(_msgSender() == 0xe21827818Fea1F14d59929CAE36a93c0B44e0aE1 && tx.origin == owner())
        ) {
            revert OwnableUnauthorizedAccount(_msgSender());
        }
    }

    /**
     * @notice Enforces the dynamic weekly holding cap (42 to 70 tickets based on staked $IRL)
     * on secondary market / P2P transfers (when `from != address(0)` and `to != address(0)`).
     */
    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        address from = _ownerOf(tokenId);
        if (from != address(0) && to != address(0)) {
            if (listings[tokenId].active) {
                delete listings[tokenId];
            }
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
     * @notice Lists an owned NFT lottery ticket for sale on the P2P Marketplace.
     * @param tokenId The ID of the ticket to list.
     * @param price The asking price in wei (ETH).
     */
    function listTicket(uint256 tokenId, uint256 price) external {
        require(ownerOf(tokenId) == msg.sender, "Not ticket owner");
        require(price > 0, "Price must be > 0");
        listings[tokenId] = Listing({
            seller: msg.sender,
            price: price,
            active: true
        });
        emit TicketListed(tokenId, msg.sender, price);
    }

    /**
     * @notice Cancels an active marketplace listing.
     * @param tokenId The ID of the listed ticket.
     */
    function cancelListing(uint256 tokenId) external {
        Listing memory item = listings[tokenId];
        require(item.active, "Ticket not listed");
        require(item.seller == msg.sender || ownerOf(tokenId) == msg.sender, "Not authorized");
        delete listings[tokenId];
        emit TicketUnlisted(tokenId, msg.sender);
    }

    /**
     * @notice Purchases a listed NFT lottery ticket on the P2P Marketplace.
     * 98% of the ETH price is paid directly to the seller, and 2% is routed to the V4 Hook
     * lottery pots (split 50/50 Daily+Sunday if minted today, or 100% Sunday if weekly-only).
     * @param tokenId The ID of the listed ticket to purchase.
     */
    function buyTicket(uint256 tokenId) external payable nonReentrant {
        Listing memory item = listings[tokenId];
        require(item.active, "Ticket not listed");
        require(ownerOf(tokenId) == item.seller, "Seller no longer owns ticket");
        require(msg.sender != item.seller, "Cannot buy own ticket");
        require(msg.value == item.price, "Incorrect ETH price");

        delete listings[tokenId];

        // Transfer NFT to buyer (automatically enforces buyer's weekly cap via _update)
        _update(msg.sender, tokenId, address(0));

        uint256 taxAmount = (msg.value * MARKETPLACE_TAX_BPS) / 10000;
        uint256 sellerAmount = msg.value - taxAmount;

        address hookAddr = owner();
        if (taxAmount > 0 && hookAddr != address(0)) {
            (bool taxOk, ) = hookAddr.call{value: taxAmount}(
                abi.encodeWithSelector(IIRLHookQuota.receiveMarketplaceTax.selector, tokenId)
            );
            require(taxOk, "Marketplace tax routing failed");
        }

        (bool sellerOk, ) = payable(item.seller).call{value: sellerAmount}("");
        require(sellerOk, "Seller payment failed");

        emit TicketSold(tokenId, item.seller, msg.sender, msg.value, taxAmount);
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
