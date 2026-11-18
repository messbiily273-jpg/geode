// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IAgentID {
    function balanceOf(address owner) external view returns (uint256);
}

/// @title Geode - mine a rock, reveal what is inside
/// @notice Supply 50,000. Max 5 per wallet.
///         Agent ID (.ai) holders get their FIRST mint FREE.
///         After the free mint, each NFT costs 0.0006 BNB (~Rp 7.000).
///         Non Agent ID wallets pay 0.0006 BNB for every mint.
/// @notice Each NFT is a unique mined rock chunk. The mineral inside
///         (Iron, Quartz, Copper, Gold, Diamond) is decided off-chain
///         from the minter wallet + tokenId hash and rendered by the backend.
/// @notice Mining power: holding more Ore NFTs (and rarer ones) boosts
///         mining. Mining Power is an on-metadata attribute per token.
/// @notice 5% creator royalty (ERC-2981) on secondary sales, paid to owner.
contract Geode is ERC721, ERC2981, Ownable {
    uint256 public constant MAX_SUPPLY = 50000;
    uint256 public constant MAX_PER_WALLET = 5;
    uint256 public constant MINT_PRICE = 0.0006 ether;

    // Binance Agent ID (.ai) registry on BNB Chain.
    IAgentID public constant AGENT_ID = IAgentID(0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F);

    uint256 private _nextTokenId = 1;
    string private _baseTokenURI;
    bool public mintActive;

    uint256 public totalMinted;
    mapping(address => uint256) public mintedBy;
    mapping(uint256 => string) private _tokenURIs;

    event Minted(address indexed to, uint256 indexed tokenId);
    event TokenURISet(uint256 indexed tokenId, string uri);
    event BaseURIUpdated(string baseURI);
    event MintStateChanged(bool active);

    constructor(string memory initialBaseURI) ERC721("Geode", "GEODE") Ownable(msg.sender) {
        _baseTokenURI = initialBaseURI;
        _setDefaultRoyalty(msg.sender, 500);
    }

    /// @notice Mint 1-5 Ore NFTs. Agent ID holders mint their first one free.
    function mint(uint256 count) external payable {
        require(mintActive, "Mint is not active");
        require(count >= 1 && count <= MAX_PER_WALLET, "Mint 1-5 at a time");
        require(mintedBy[msg.sender] + count <= MAX_PER_WALLET, "Max 5 per wallet");
        require(totalMinted + count <= MAX_SUPPLY, "Supply sold out");

        uint256 cost;
        if (mintedBy[msg.sender] == 0 && AGENT_ID.balanceOf(msg.sender) > 0) {
            // Agent ID holder: first mint free, the rest paid.
            cost = (count - 1) * MINT_PRICE;
        } else {
            cost = count * MINT_PRICE;
        }
        require(msg.value >= cost, "Insufficient BNB");

        for (uint256 i = 0; i < count; i++) {
            uint256 tokenId = _nextTokenId;
            _nextTokenId++;
            totalMinted++;
            mintedBy[msg.sender]++;
            _safeMint(msg.sender, tokenId);
            emit Minted(msg.sender, tokenId);
        }

        // Refund any overpayment.
        if (msg.value > cost) {
            (bool ok, ) = payable(msg.sender).call{value: msg.value - cost}("");
            require(ok, "Refund failed");
        }
    }

    /// @notice Agent mint: the owner (Geode agent) mints 1-5 Geode NFTs
    ///         directly to `to`. The free-mint rule is checked against
    ///         `to` (not the caller): if `to` holds an Agent ID and has
    ///         never minted, their first Geode is free.
    ///         This is how minting works on the Geode website: visitors
    ///         paste their wallet address into a prompt, and the agent
    ///         mints to them. No wallet connect needed.
    function mintFor(address to, uint256 count) external payable onlyOwner {
        require(mintActive, "Mint is not active");
        require(to != address(0), "Invalid recipient");
        require(count >= 1 && count <= MAX_PER_WALLET, "Mint 1-5 at a time");
        require(mintedBy[to] + count <= MAX_PER_WALLET, "Max 5 per wallet");
        require(totalMinted + count <= MAX_SUPPLY, "Supply sold out");

        uint256 cost;
        if (mintedBy[to] == 0 && AGENT_ID.balanceOf(to) > 0) {
            // Agent ID holder: first mint free, the rest paid.
            cost = (count - 1) * MINT_PRICE;
        } else {
            cost = count * MINT_PRICE;
        }
        require(msg.value >= cost, "Insufficient BNB");

        for (uint256 i = 0; i < count; i++) {
            uint256 tokenId = _nextTokenId;
            _nextTokenId++;
            totalMinted++;
            mintedBy[to]++;
            _safeMint(to, tokenId);
            emit Minted(to, tokenId);
        }

        // Refund any overpayment.
        if (msg.value > cost) {
            (bool ok, ) = payable(msg.sender).call{value: msg.value - cost}("");
            require(ok, "Refund failed");
        }
    }

    /// @notice How much a mint of `count` costs for `wallet` right now.
    function mintCost(address wallet, uint256 count) external view returns (uint256) {
        if (mintedBy[wallet] == 0 && AGENT_ID.balanceOf(wallet) > 0 && count >= 1) {
            return (count - 1) * MINT_PRICE;
        }
        return count * MINT_PRICE;
    }

    function totalSupply() external view returns (uint256) {
        return _nextTokenId - 1;
    }

    function setMintActive(bool active) external onlyOwner {
        mintActive = active;
        emit MintStateChanged(active);
    }

    function setTokenURI(uint256 tokenId, string calldata uri) external onlyOwner {
        _requireOwned(tokenId);
        _tokenURIs[tokenId] = uri;
        emit TokenURISet(tokenId, uri);
    }

    function setBaseURI(string calldata newBaseURI) external onlyOwner {
        _baseTokenURI = newBaseURI;
        emit BaseURIUpdated(newBaseURI);
    }

    function setDefaultRoyalty(address receiver, uint96 feeNumerator) external onlyOwner {
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC2981) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        string memory customURI = _tokenURIs[tokenId];
        if (bytes(customURI).length > 0) {
            return customURI;
        }
        return string(abi.encodePacked(_baseURI(), _toString(tokenId)));
    }

    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    function withdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "Nothing to withdraw");
        (bool ok, ) = payable(owner()).call{value: balance}("");
        require(ok, "Withdraw failed");
    }

    receive() external payable {}
}
