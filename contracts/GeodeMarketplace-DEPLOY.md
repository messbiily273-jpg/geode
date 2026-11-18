# GeodeMarketplace — Deployment Guide

> STATUS: **DEPLOYED 2026-11-13 ~10:05 WIB.** Deployer: Geode owner wallet
> `0x7bD068B471E60c24F6F544F77E500A4D8D4F4Ee9`. Contract address:
> `0x5724f92c636b47bA7255A5E447D4B76BE2273009`. Tx hash:
> `0x064df0bb9d04d77a3b50ce6123ea3bb9e07f74ba2b4033960cd0e97a96a22bae`.
> Block 133276713, status success, gas used 739,158 (exactly as estimated),
> actual cost ~0.000037 BNB (gas price 0.05 gwei at deploy time, well under
> the 1 gwei estimate). Owner wallet balance after deploy: 0.001222 BNB.
> On-chain verification: `nftContract()` = Geode NFT, `feeRecipient()` =
> owner wallet, `getFeeBps()` = 250, `owner()` = deployer. All match.
> Frontend: `MARKETPLACE_CONTRACT_ADDRESS` set in `marketplace.html` and
> `holder.html`; trading is live on https://www.geodehash.xyz/marketplace.
> `activity.json` (indexer) is still blocked by BSC RPC rate limits and is
> NOT required for trading; pages degrade gracefully without it.

## Contract

- Source: `src/GeodeMarketplace.sol`
- Compiler: Solidity 0.8.24, OpenZeppelin 5.4.0 (`ReentrancyGuard`, `Ownable`)
- Target chain: BNB Chain mainnet (chainId 56)
- Bytecode size: 3,507 bytes (well under the 24,576-byte limit)

## Constructor arguments

| # | Name | Type | Value |
|---|------|------|-------|
| 1 | `_nftContract` | address | `0x8aB5Ddc1c73e353DC81bfCfAA368c5BD32bA9698` (Geode NFT) |
| 2 | `_feeRecipient` | address | `0x7bD068B471E60c24F6F544F77E500A4D8D4F4Ee9` (Geode owner wallet) |
| 3 | `_feeBps` | uint256 | `250` (= 2.5%) |

## Deploy command

Run from this directory (`contract/`). The deployer wallet needs BNB for gas
(see below). Never paste a real private key into a shared terminal or file;
use an environment variable.

```bash
export BNB_RPC_URL="https://bsc-dataseed.binance.org/"
export PRIVATE_KEY="<deployer private key>"

FOUNDRY_VIA_IR=false forge create \
  --rpc-url "$BNB_RPC_URL" \
  --private-key "$PRIVATE_KEY" \
  --broadcast \
  src/GeodeMarketplace.sol:GeodeMarketplace \
  --constructor-args \
    0x8aB5Ddc1c73e353DC81bfCfAA368c5BD32bA9698 \
    0x7bD068B471E60c24F6F544F77E500A4D8D4F4Ee9 \
    250
```

Notes:

- The deployer becomes the contract `owner` (`Ownable(msg.sender)`). Only the
  owner can cancel other sellers' listings (`cancelListing`) and transfer
  ownership. There is no fee-change function: the 2.5% fee and the fee
  recipient are immutable and can only change by deploying a new contract.
- `FOUNDRY_VIA_IR=false` is mandatory on this VM: via-IR compilation
  OOM-kills on 6 GB RAM.
- Do NOT use `--verify` unless a BscScan API key is available. If it is,
  add: `--verify --verifier etherscan --verifier-url https://api.bscscan.com/api
  --etherscan-api-key "$BSCSCAN_API_KEY"`.

## Estimated gas

Measured 2026-11-13 on this VM (Foundry, solc 0.8.24, optimizer on, 200 runs):

| Item | Gas | How measured |
|------|-----|--------------|
| Contract deployment | **739,158** | `forge build --sizes` (deployment cost) |
| Deployment, second measurement | 777,341 | Foundry test deploying the contract (`test_DeploymentGas`, includes test-harness overhead; the 739,158 figure is the cleaner estimate) |
| `buy` (successful sale) | ~129,257 median (max 167,493 in tests) | `forge test --gas-report` |
| `list` | ~85,000–110,000 | `forge test --gas-report` (included in test totals) |

Cost in BNB depends on the gas price at deploy time. At 1 gwei, deployment
costs about 0.00074 BNB; at 5 gwei, about 0.0037 BNB. Check the live gas
price before deploying and fund the deployer wallet with a margin above it.
The deployer wallet must hold BNB on BNB Chain mainnet; the contract itself
never needs funding.

## Post-deploy checklist (for the deployer / frontend agent)

1. Record the deployed contract address and verify it on BscScan.
2. Sanity-check on-chain: `nftContract()` =
   `0x8aB5Ddc1c73e353DC81bfCfAA368c5BD32bA9698`, `feeRecipient()` =
   `0x7bD068B471E60c24F6F544F77E500A4D8D4F4Ee9`, `getFeeBps()` = `250`,
   `owner()` = deployer address.
3. Frontend: use `abi.json` in this directory (31 ABI entries). Listing flow
   is: seller approves the marketplace for the token (`approve` or
   `setApprovalForAll` on the Geode NFT contract), then calls
   `list(tokenId, price)`; buyer calls `buy(tokenId)` with `msg.value`
   exactly equal to the price. No funds are ever deposited into the
   marketplace contract; payment happens inside the `buy` transaction.

## Verification done (Phase 1)

- Foundry tests: **23 passed, 0 failed** (`FOUNDRY_VIA_IR=false forge test`).
  Covers: list/buy happy path with exact payouts, cancel then buy reverts,
  buy with too-low and too-high price reverts, buy own listing reverts,
  double-buy reverts, non-owner list reverts, price-0 list reverts, list
  without approval reverts, fee math at 1 ether (fee 0.025, seller 0.975),
  at 0.0006 BNB (fee 0.000015, seller 0.000585), at 101 wei (fee 2 wei,
  seller 99 wei), and reentrancy attempts via both `onERC721Received` and a
  seller `receive()` callback (both blocked, outer sale still completes,
  no second NFT and no extra funds move).
- Slither 0.11.6: **0 High, 0 Medium**. Two Informational findings left
  intentionally (see below).
- `forge build` linter warnings about reentrancy on the ETH payouts and the
  `Sold` event are false positives here: `buy()` is `nonReentrant` and the
  listing is deactivated before any external call (checks-effects-
  interactions), proven by the two reentrancy tests above.

### Slither Informational findings left intentionally

1. `pragma` (different-pragma-directives): OpenZeppelin 5.4.0 libraries use
   `^0.8.20` / `>=0.6.2` pragmas while this contract pins `0.8.24`. This is
   the vendored library's own versioning and cannot be changed without
   forking OpenZeppelin. Harmless.
2. `low-level-calls`: the two `.call{value:}()` payouts in `buy()` (seller
   and fee recipient). Intentional: `.call` is the recommended ETH transfer
   pattern (`.transfer` / `.send` break on gas-cost changes); both return
   values are checked and revert on failure; both run under
   `nonReentrant` after the listing is deactivated. No withdraw pattern
   exists, so the contract never holds user funds between calls.

## Files in this directory

- `src/GeodeMarketplace.sol` — the marketplace contract
- `test/GeodeMarketplace.t.sol` — 23 Foundry tests (incl. mock ERC721 and two
  attacker contracts)
- `abi.json` — full contract ABI for the frontend agent
- `foundry.toml` — solc 0.8.24, optimizer on, OpenZeppelin + forge-std remappings
- `DEPLOY.md` — this file
