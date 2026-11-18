# Geode

A mining game on BNB Chain. Players mint rock NFTs and mine GEO tokens from the browser. Agent ID holders get their first mint free, and rarer minerals earn more mining power.

- Website: https://www.geodehash.xyz
- X: https://x.com/geodehash
- Chain: BNB Chain (chainId 56)

## How Agent ID is used

Agent ID is the access gate of the whole game, enforced on-chain in the mint contract, not by a server. `Geode.sol` calls `balanceOf` on the official Agent ID registry (`0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F`) and gives every Agent ID holder their first mint free. Non-holders pay 0.0006 BNB per mint. Supply is 50,000, max 5 per wallet.

## Contracts

All contracts are verified and open-sourced on BscScan.

| Contract | Address | BscScan |
|---|---|---|
| Geode NFT (ERC721) | `0x8aB5Ddc1c73e353DC81bfCfAA368c5BD32bA9698` | https://bscscan.com/address/0x8aB5Ddc1c73e353DC81bfCfAA368c5BD32bA9698 |
| GEO token (ERC20) | `0x36B72b40BdC8Ff5cbaC54cB3f5516cD066265426` | https://bscscan.com/address/0x36B72b40BdC8Ff5cbaC54cB3f5516cD066265426 |
| GeodeMarketplace | `0x5724f92c636b47bA7255A5E447D4B76BE2273009` | https://bscscan.com/address/0x5724f92c636b47bA7255A5E447D4B76BE2273009 |

- `Geode` — ERC721 + ERC2981 (5% royalty). Rarity is decided from `keccak(minter + tokenId)`: Common Iron 55% (power 1), Uncommon Quartz 22% (power 2), Rare Copper 13% (power 3), Epic Gold 7% (power 5), Legendary Diamond 3% (power 10).
- `GEO` — ERC20 mining reward token, fixed supply of 1,000,000,000, minted once to the owner at deploy. No further minting, no taxes, no pausing, no blacklist.
- `GeodeMarketplace` — fixed-price marketplace for Geode NFTs. 2.5% fee (250 bps) to the fee recipient on every sale. The contract never holds user funds: no deposit, no escrow, no withdraw. See `contracts/GeodeMarketplace-DEPLOY.md` for the full deployment guide and audit notes.

## Build (marketplace)

```bash
cd contracts
forge install OpenZeppelin/openzeppelin-contracts
forge install foundry-rs/forge-std
forge test
```

`Geode.sol` (solc 0.8.24) and `GEO.sol` (solc 0.8.28) use OpenZeppelin 5.x. `GeodeMarketplace.sol` uses solc 0.8.24, optimizer on, 200 runs.

## License

MIT
