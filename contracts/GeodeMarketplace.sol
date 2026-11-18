// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title GeodeMarketplace
/// @notice Fixed-price marketplace for Geode NFTs (ERC721) on BNB Chain.
/// @dev Fee is taken in basis points (250 = 2.5%) on every sale and paid to
///      feeRecipient in the same transaction as the seller payout. The
///      contract never holds user funds longer than a single call: there is
///      no deposit, no escrow balance and no withdraw function. The NFT
///      stays with the seller until the moment of sale.
contract GeodeMarketplace is ReentrancyGuard, Ownable {
    /// @notice The Geode NFT contract traded on this marketplace.
    IERC721 public immutable nftContract;
    /// @notice Address receiving the marketplace fee on every sale.
    address public immutable feeRecipient;
    /// @notice Marketplace fee in basis points (250 = 2.5%). Max 10000.
    uint256 public immutable feeBps;

    uint256 public constant MAX_FEE_BPS = 10000;

    struct Listing {
        address seller;
        uint256 price;
        bool active;
    }

    mapping(uint256 => Listing) private _listings;

    event Listed(uint256 indexed tokenId, address indexed seller, uint256 price);
    event Cancelled(uint256 indexed tokenId, address indexed seller);
    event Sold(uint256 indexed tokenId, address indexed seller, address indexed buyer, uint256 price);

    error ZeroAddress();
    error FeeTooHigh();
    error NotTokenOwner();
    error PriceMustBePositive();
    error AlreadyListed();
    error NotApproved();
    error ListingNotActive();
    error NotSellerOrOwner();
    error CannotBuyOwnListing();
    error IncorrectPayment();
    error TransferFailed();

    /// @param _nftContract Address of the Geode ERC721 contract.
    /// @param _feeRecipient Address receiving the fee on every sale.
    /// @param _feeBps Fee in basis points (250 = 2.5%).
    constructor(address _nftContract, address _feeRecipient, uint256 _feeBps) Ownable(msg.sender) {
        if (_nftContract == address(0) || _feeRecipient == address(0)) revert ZeroAddress();
        if (_feeBps > MAX_FEE_BPS) revert FeeTooHigh();
        nftContract = IERC721(_nftContract);
        feeRecipient = _feeRecipient;
        feeBps = _feeBps;
    }

    /// @notice List a Geode NFT for sale at a fixed price.
    /// @dev The seller keeps the NFT; the marketplace only needs approval
    ///      (per-token approval or operator approval) to transfer it on sale.
    /// @param tokenId Token to list.
    /// @param price Sale price in wei. Must be > 0.
    function list(uint256 tokenId, uint256 price) external {
        if (nftContract.ownerOf(tokenId) != msg.sender) revert NotTokenOwner();
        if (price == 0) revert PriceMustBePositive();
        if (_listings[tokenId].active) revert AlreadyListed();
        if (
            nftContract.getApproved(tokenId) != address(this) &&
            !nftContract.isApprovedForAll(msg.sender, address(this))
        ) revert NotApproved();

        _listings[tokenId] = Listing({seller: msg.sender, price: price, active: true});
        emit Listed(tokenId, msg.sender, price);
    }

    /// @notice Cancel an active listing. Only the seller or the contract owner.
    /// @param tokenId Token whose listing is cancelled.
    function cancelListing(uint256 tokenId) external {
        Listing storage listing = _listings[tokenId];
        if (!listing.active) revert ListingNotActive();
        if (msg.sender != listing.seller && msg.sender != owner()) revert NotSellerOrOwner();

        listing.active = false;
        emit Cancelled(tokenId, listing.seller);
    }

    /// @notice Buy a listed NFT. `msg.value` must equal the listing price exactly.
    /// @dev Checks-effects-interactions + nonReentrant. The listing is
    ///      deactivated before any external call. Seller payout and fee
    ///      payout happen in this same transaction; no funds stay behind.
    /// @param tokenId Token to buy.
    function buy(uint256 tokenId) external payable nonReentrant {
        Listing storage listing = _listings[tokenId];
        if (!listing.active) revert ListingNotActive();
        if (msg.value != listing.price) revert IncorrectPayment();
        if (msg.sender == listing.seller) revert CannotBuyOwnListing();

        address seller = listing.seller;
        uint256 price = listing.price;

        // Effects: deactivate first, before any external call.
        listing.active = false;

        uint256 fee = (price * feeBps) / MAX_FEE_BPS;
        uint256 sellerAmount = price - fee;

        // Interactions: NFT to buyer, then payouts. Any failure reverts
        // the whole sale, so the listing stays deactivated only on success
        // (a revert rolls the deactivation back too).
        nftContract.safeTransferFrom(seller, msg.sender, tokenId);

        (bool sellerOk, ) = payable(seller).call{value: sellerAmount}("");
        if (!sellerOk) revert TransferFailed();
        (bool feeOk, ) = payable(feeRecipient).call{value: fee}("");
        if (!feeOk) revert TransferFailed();

        emit Sold(tokenId, seller, msg.sender, price);
    }

    /// @notice Get the listing for a token.
    /// @return seller Listing seller (address(0) if never listed).
    /// @return price Listing price in wei.
    /// @return active Whether the listing is currently active.
    function getListing(uint256 tokenId) external view returns (address seller, uint256 price, bool active) {
        Listing storage listing = _listings[tokenId];
        return (listing.seller, listing.price, listing.active);
    }

    /// @notice Marketplace fee in basis points.
    function getFeeBps() external view returns (uint256) {
        return feeBps;
    }
}
