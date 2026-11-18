// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {GeodeMarketplace} from "../src/GeodeMarketplace.sol";

/// @notice Minimal Geode-like ERC721 used instead of a mainnet fork.
contract MockGeode is ERC721 {
    constructor() ERC721("MockGeode", "MGEODE") {}

    function mint(address to, uint256 tokenId) external {
        _mint(to, tokenId);
    }
}

/// @notice Malicious buyer: tries to reenter buy() from onERC721Received
///         while the outer buy() is still running, targeting a second listing.
contract BuyerAttacker is IERC721Receiver {
    GeodeMarketplace public marketplace;
    uint256 public secondTokenId;
    uint256 public secondPrice;
    bool public reentryAttempted;
    bool public reentrySucceeded;

    constructor(address _marketplace) {
        marketplace = GeodeMarketplace(_marketplace);
    }

    function setTarget(uint256 tokenId, uint256 price) external {
        secondTokenId = tokenId;
        secondPrice = price;
    }

    function onERC721Received(address, address, uint256, bytes calldata) external override returns (bytes4) {
        if (!reentryAttempted) {
            reentryAttempted = true;
            (bool ok, ) = address(marketplace).call{value: secondPrice}(
                abi.encodeWithSignature("buy(uint256)", secondTokenId)
            );
            reentrySucceeded = ok;
        }
        return this.onERC721Received.selector;
    }

    receive() external payable {}
}

/// @notice Malicious seller: tries to reenter buy() from receive() when the
///         marketplace pays out the seller proceeds, targeting another listing.
contract SellerAttacker is IERC721Receiver {
    GeodeMarketplace public marketplace;
    uint256 public targetTokenId;
    uint256 public targetPrice;
    bool public reentryAttempted;
    bool public reentrySucceeded;

    constructor(address _marketplace) {
        marketplace = GeodeMarketplace(_marketplace);
    }

    function setTarget(uint256 tokenId, uint256 price) external {
        targetTokenId = tokenId;
        targetPrice = price;
    }

    function onERC721Received(address, address, uint256, bytes calldata) external override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    receive() external payable {
        if (!reentryAttempted) {
            reentryAttempted = true;
            (bool ok, ) = address(marketplace).call{value: targetPrice}(
                abi.encodeWithSignature("buy(uint256)", targetTokenId)
            );
            reentrySucceeded = ok;
        }
    }
}

contract GeodeMarketplaceTest is Test {
    MockGeode public nft;
    GeodeMarketplace public market;

    address public seller = makeAddr("seller");
    address public buyer = makeAddr("buyer");
    address public other = makeAddr("other");
    address public constant FEE_RECIPIENT = 0x7bD068B471E60c24F6F544F77E500A4D8D4F4Ee9;
    uint256 public constant FEE_BPS = 250;

    function setUp() public {
        nft = new MockGeode();
        market = new GeodeMarketplace(address(nft), FEE_RECIPIENT, FEE_BPS);
        vm.deal(buyer, 100 ether);
        vm.deal(other, 100 ether);
        vm.deal(seller, 1 ether);
        vm.deal(address(this), 100 ether);
    }

    function _mintAndList(uint256 tokenId, address _seller, uint256 price) internal {
        nft.mint(_seller, tokenId);
        vm.prank(_seller);
        nft.approve(address(market), tokenId);
        vm.prank(_seller);
        market.list(tokenId, price);
    }

    // ---- Happy path ----

    function test_ListBuyHappyPath() public {
        _mintAndList(1, seller, 1 ether);

        (address s, uint256 p, bool a) = market.getListing(1);
        assertEq(s, seller);
        assertEq(p, 1 ether);
        assertTrue(a);

        uint256 sellerBefore = seller.balance;
        uint256 feeBefore = FEE_RECIPIENT.balance;

        vm.prank(buyer);
        market.buy{value: 1 ether}(1);

        assertEq(nft.ownerOf(1), buyer);
        assertEq(seller.balance, sellerBefore + 0.975 ether);
        assertEq(FEE_RECIPIENT.balance, feeBefore + 0.025 ether);
        assertEq(address(market).balance, 0, "marketplace must not hold funds");

        (, , bool activeAfter) = market.getListing(1);
        assertFalse(activeAfter);
    }

    // ---- Cancel ----

    function test_CancelThenBuyReverts() public {
        _mintAndList(1, seller, 1 ether);

        vm.prank(seller);
        market.cancelListing(1);

        (, , bool active) = market.getListing(1);
        assertFalse(active);

        vm.prank(buyer);
        vm.expectRevert(GeodeMarketplace.ListingNotActive.selector);
        market.buy{value: 1 ether}(1);
    }

    function test_CancelByOwner() public {
        _mintAndList(1, seller, 1 ether);
        // Test contract deployed the marketplace, so it is the owner.
        market.cancelListing(1);
        (, , bool active) = market.getListing(1);
        assertFalse(active);
    }

    function test_CancelByStrangerReverts() public {
        _mintAndList(1, seller, 1 ether);
        vm.prank(other);
        vm.expectRevert(GeodeMarketplace.NotSellerOrOwner.selector);
        market.cancelListing(1);
    }

    // ---- Buy reverts ----

    function test_BuyWrongPriceTooLowReverts() public {
        _mintAndList(1, seller, 1 ether);
        vm.prank(buyer);
        vm.expectRevert(GeodeMarketplace.IncorrectPayment.selector);
        market.buy{value: 0.5 ether}(1);
    }

    function test_BuyWrongPriceTooHighReverts() public {
        _mintAndList(1, seller, 1 ether);
        vm.prank(buyer);
        vm.expectRevert(GeodeMarketplace.IncorrectPayment.selector);
        market.buy{value: 1.5 ether}(1);
    }

    function test_BuyOwnListingReverts() public {
        _mintAndList(1, seller, 1 ether);
        vm.prank(seller);
        vm.expectRevert(GeodeMarketplace.CannotBuyOwnListing.selector);
        market.buy{value: 1 ether}(1);
    }

    function test_DoubleBuyReverts() public {
        _mintAndList(1, seller, 1 ether);
        vm.prank(buyer);
        market.buy{value: 1 ether}(1);

        vm.prank(other);
        vm.expectRevert(GeodeMarketplace.ListingNotActive.selector);
        market.buy{value: 1 ether}(1);
    }

    function test_BuyUnlistedReverts() public {
        nft.mint(seller, 1);
        vm.prank(buyer);
        vm.expectRevert(GeodeMarketplace.ListingNotActive.selector);
        market.buy{value: 1 ether}(1);
    }

    // ---- List reverts ----

    function test_NonOwnerListReverts() public {
        nft.mint(seller, 1);
        vm.prank(buyer);
        vm.expectRevert(GeodeMarketplace.NotTokenOwner.selector);
        market.list(1, 1 ether);
    }

    function test_ListPriceZeroReverts() public {
        nft.mint(seller, 1);
        vm.prank(seller);
        nft.approve(address(market), 1);
        vm.prank(seller);
        vm.expectRevert(GeodeMarketplace.PriceMustBePositive.selector);
        market.list(1, 0);
    }

    function test_ListWithoutApprovalReverts() public {
        nft.mint(seller, 1);
        vm.prank(seller);
        vm.expectRevert(GeodeMarketplace.NotApproved.selector);
        market.list(1, 1 ether);
    }

    function test_ListTwiceReverts() public {
        _mintAndList(1, seller, 1 ether);
        vm.prank(seller);
        vm.expectRevert(GeodeMarketplace.AlreadyListed.selector);
        market.list(1, 2 ether);
    }

    function test_RelistAfterCancelWorks() public {
        _mintAndList(1, seller, 1 ether);
        vm.prank(seller);
        market.cancelListing(1);
        vm.prank(seller);
        market.list(1, 2 ether);
        (, uint256 p, bool a) = market.getListing(1);
        assertEq(p, 2 ether);
        assertTrue(a);
    }

    // ---- Fee math ----

    function test_FeeMathOneEther() public {
        _mintAndList(1, seller, 1 ether);
        uint256 sellerBefore = seller.balance;
        uint256 feeBefore = FEE_RECIPIENT.balance;

        vm.prank(buyer);
        market.buy{value: 1 ether}(1);

        uint256 fee = (1 ether * FEE_BPS) / 10000;
        assertEq(fee, 0.025 ether);
        assertEq(FEE_RECIPIENT.balance, feeBefore + fee);
        assertEq(seller.balance, sellerBefore + (1 ether - fee));
        assertEq(seller.balance, sellerBefore + 0.975 ether);
    }

    function test_FeeMathSmallOddPrice() public {
        // 0.0006 BNB is the Geode mint price; fee must be exact, no rounding windfall.
        uint256 price = 0.0006 ether;
        _mintAndList(1, seller, price);
        uint256 sellerBefore = seller.balance;
        uint256 feeBefore = FEE_RECIPIENT.balance;

        vm.prank(buyer);
        market.buy{value: price}(1);

        uint256 fee = (price * FEE_BPS) / 10000;
        assertEq(fee, 0.000015 ether, "fee = 0.0006 * 250 / 10000");
        assertEq(FEE_RECIPIENT.balance, feeBefore + fee);
        assertEq(seller.balance, sellerBefore + 0.000585 ether);
        assertEq(seller.balance, sellerBefore + (price - fee));
        assertEq(address(market).balance, 0);
    }

    function test_FeeMathTinyPriceRounding() public {
        // 101 wei: fee = 101*250/10000 = 2 wei (integer division rounds down),
        // seller gets 99 wei. No wei is created or lost.
        uint256 price = 101;
        _mintAndList(1, seller, price);
        uint256 sellerBefore = seller.balance;
        uint256 feeBefore = FEE_RECIPIENT.balance;

        vm.prank(buyer);
        market.buy{value: price}(1);

        assertEq(FEE_RECIPIENT.balance, feeBefore + 2);
        assertEq(seller.balance, sellerBefore + 99);
        assertEq(address(market).balance, 0);
    }

    // ---- Views / config ----

    function test_Getters() public view {
        assertEq(address(market.nftContract()), address(nft));
        assertEq(market.feeRecipient(), FEE_RECIPIENT);
        assertEq(market.getFeeBps(), FEE_BPS);
        assertEq(market.feeBps(), FEE_BPS);
        assertEq(market.owner(), address(this));
    }

    function test_ConstructorRejectsZeroAddresses() public {
        vm.expectRevert(GeodeMarketplace.ZeroAddress.selector);
        new GeodeMarketplace(address(0), FEE_RECIPIENT, FEE_BPS);
        vm.expectRevert(GeodeMarketplace.ZeroAddress.selector);
        new GeodeMarketplace(address(nft), address(0), FEE_BPS);
    }

    function test_ConstructorRejectsFeeOver100Percent() public {
        vm.expectRevert(GeodeMarketplace.FeeTooHigh.selector);
        new GeodeMarketplace(address(nft), FEE_RECIPIENT, 10001);
    }

    // ---- Reentrancy ----

    function test_ReentrancyViaOnERC721ReceivedFails() public {
        // Attacker buys token 1; inside onERC721Received it tries to also
        // buy token 2 (a live listing). The reentrant buy must fail.
        BuyerAttacker attacker = new BuyerAttacker(address(market));
        vm.deal(address(attacker), 10 ether);

        _mintAndList(1, seller, 1 ether);
        _mintAndList(2, seller, 1 ether);
        attacker.setTarget(2, 1 ether);

        attackerBuy(attacker, 1, 1 ether);

        assertTrue(attacker.reentryAttempted(), "attacker should have tried to reenter");
        assertFalse(attacker.reentrySucceeded(), "reentrant buy must fail");
        assertEq(nft.ownerOf(1), address(attacker), "outer buy still completes");
        assertEq(nft.ownerOf(2), seller, "second token must NOT change hands");
        (, , bool active2) = market.getListing(2);
        assertTrue(active2, "second listing must stay active");
        assertEq(address(market).balance, 0);
    }

    function test_ReentrancyViaSellerReceiveFails() public {
        // Attacker is the seller of token 1. When the marketplace pays it,
        // its receive() tries to buy token 2 (a live listing). Must fail.
        SellerAttacker attacker = new SellerAttacker(address(market));
        vm.deal(address(attacker), 10 ether);

        _mintAndList(1, address(attacker), 1 ether);
        _mintAndList(2, seller, 1 ether);
        attacker.setTarget(2, 1 ether);

        uint256 attackerBefore = address(attacker).balance;
        vm.prank(buyer);
        market.buy{value: 1 ether}(1);

        assertTrue(attacker.reentryAttempted(), "attacker should have tried to reenter");
        assertFalse(attacker.reentrySucceeded(), "reentrant buy must fail");
        assertEq(nft.ownerOf(1), buyer, "outer buy still completes");
        assertEq(nft.ownerOf(2), seller, "second token must NOT change hands");
        (, , bool active2) = market.getListing(2);
        assertTrue(active2, "second listing must stay active");
        // Attacker received exactly its 0.975 ether seller proceeds, nothing extra.
        assertEq(address(attacker).balance, attackerBefore + 0.975 ether);
        assertEq(address(market).balance, 0);
    }

    // Attacker contracts have no test-only helper to call buy from an EOA
    // context; route the outer buy through a prank on the attacker address.
    function attackerBuy(BuyerAttacker attacker, uint256 tokenId, uint256 price) internal {
        vm.prank(address(attacker));
        market.buy{value: price}(tokenId);
    }

    // ---- Deployment gas (measurement helper, not a behaviour test) ----

    function test_DeploymentGas() public {
        uint256 gasBefore = gasleft();
        GeodeMarketplace m = new GeodeMarketplace(address(nft), FEE_RECIPIENT, FEE_BPS);
        uint256 gasUsed = gasBefore - gasleft();
        emit log_named_uint("deployment gas (approx, forge test env)", gasUsed);
        assertTrue(address(m) != address(0));
    }
}
