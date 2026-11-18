// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title Geode (GEO)
/// @notice The mining reward token for Geode. Miners earn GEO by finding
/// hashes on the Mine page; GEO can be withdrawn to a wallet daily and
/// exchanged. Fixed supply, minted once to the owner at deploy. The owner
/// distributes GEO as mining rewards and seeds liquidity from this supply.
/// @dev No further minting. No taxes, no pausing, no blacklist.
contract GEO is ERC20, Ownable {
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 ether; // 1B GEO

    constructor() ERC20("Geode", "GEO") Ownable(msg.sender) {
        _mint(msg.sender, TOTAL_SUPPLY);
    }
}
