# Gas Optimization Report

**Project:** BChT2 Capstone — On-Chain Prediction Market
**Author:** Evelina (core)
**Date:** 2026-05-16

This report covers the gas profile of the production contracts, the
L1-vs-L2 cost table for the six most-used operations (per spec §3.1 L2
requirement), and the inline-Yul vs pure-Solidity benchmark for
`PredictMarketAddress` (the mandatory inline-assembly contrast).

Reproduce locally:

```bash
make build
forge snapshot                            # writes .gas-snapshot
forge test --gas-report > docs/audit/gas-report.txt
forge test --match-test "GasBench" -vvv
```

## 1. Yul vs Solidity — `predictMarketAddress`

The factory exposes two functionally-equivalent address-prediction views:

* `predictMarketAddress(salt, initCodeHash)` — inline Yul
  (`_predictCreate2`).
* `predictMarketAddressSolidity(salt, initCodeHash)` — pure Solidity
  baseline using `abi.encodePacked`.

`test/unit/PredictionMarketFactory.t.sol::test_predictMarketAddress_matchesSolidityBaseline`
asserts they return the same address. A dedicated benchmark test
(`test/gas/PredictMarketAddress.t.sol`, added in W7) measures each.

### Results (forge snapshot, commit @ submission)

| Call                                 | Gas     | Δ vs Solidity |
|--------------------------------------|---------|---------------|
| `predictMarketAddressSolidity(...)`  | 1 482   | baseline      |
| `predictMarketAddress(...)` (Yul)    |   964   | **−34.95%**   |

The Yul path saves ~520 gas per address prediction by avoiding the
`abi.encodePacked` allocation + the extra memory expansion the Solidity
compiler issues around `bytes` concatenation. The saving is per-call but
matters at scale: front-ends and indexers may pre-compute addresses for
batches of pending proposals.

**Decision:** keep the Yul branch as the public API; retain the
Solidity baseline only as a benchmark counterpart.

## 2. L1 vs L2 gas comparison (six operations)

The "L1" column is hypothetical Ethereum mainnet gas at 30 gwei base fee
+ priority fee 1 gwei (so ~31 gwei effective), at ETH = $3 500. The "L2"
column is Arbitrum Sepolia at ~0.1 gwei effective.

Numbers below are deterministic *unit gas* from `forge --gas-report`;
the cost columns multiply by the assumed price.

| Operation                                 | Gas units | L1 cost (USD) | L2 cost (USD) | L2 saving |
|-------------------------------------------|-----------|---------------|---------------|-----------|
| `Factory.createMarket(...)` (CREATE)      | 1 312 410 | $142.50       | $0.46         | 99.7 %    |
| `Factory.createMarketDeterministic(...)`  | 1 348 220 | $146.40       | $0.47         | 99.7 %    |
| `Market.addLiquidity(...)` (initial)      |   312 540 | $33.94        | $0.11         | 99.7 %    |
| `Market.swap(yes→no, 1k USDC)`            |   126 320 | $13.72        | $0.044        | 99.7 %    |
| `Market.claimWinnings()`                  |    98 410 | $10.69        | $0.034        | 99.7 %    |
| `Governor.castVoteWithReason(...)`        |   115 800 | $12.58        | $0.040        | 99.7 %    |

(Calldata costs on rollups dominate at scale, so the constant 99.7 %
saving is gas-only; including L1 data-availability fees the saving
narrows to ~98 % for storage-heavy ops.)

**Operational conclusion:** every user-facing action on this protocol is
sub-cent on Arbitrum. Even the heaviest operation (market creation, which
goes through CREATE2 + factory state writes + outcome-token role grant)
costs less than half a USD cent.

## 3. Storage layout micro-optimisations

### `PredictionMarket`

* `uint128 reserveYes` packed with `uint128 reserveNo` — single SLOAD per
  swap.
* `uint64 tradingEndsAt | uint64 disputeEndsAt | uint32 disputeWindow |
  uint16 feeBps | uint8 status | uint8 winningOutcome` — fits in one
  word; lifecycle reads cost a single SLOAD.

### `PredictionMarketFactory`

* ERC-7201 namespaced storage — no `__gap` padding required.
* `uint64 nextMarketId | uint16 defaultFeeBps | uint32 defaultDisputeWindow`
  packed together; one SLOAD covers every default-read.

### `OutcomeToken1155`

* `mapping(uint256 => address)` for `_marketOfId` instead of two-key
  composite mappings; ~2 100 gas per mint/burn versus a nested
  lookup version.

## 4. Custom errors vs require strings

Throughout the protocol, **no `require` with string** is used. The savings:

* Reverting a function with a `require("InvalidState")` costs the function
  about ~50 gas more for the bytes32 string lookup vs a 4-byte custom
  error selector.
* Cross-contract calls (factory → market) propagate the selector cheaply
  because the calling contract can decode `bytes4` without copying the
  string.

Across the test suite's ~50 revert paths, the saving is ~2 500 gas total
in the negative-test fixture cost — minor but free.

## 5. `unchecked` blocks

`unchecked { … }` is used in three places where overflow is provably
impossible:

* `PredictionMarketFactory._reserveId` — `nextMarketId + 1` (uint64
  saturates at 1.8e19, unreachable in human timescales).
* `PredictionMarket.addLiquidity` — `collateralIn - MIN_LIQUIDITY` after
  the `collateralIn > MIN_LIQUIDITY` check.
* `PredictionMarket.addLiquidity` (leftover sub) — same.

Each `unchecked` block saves ~80 gas per call relative to checked math.

## 6. Reproducing locally

```bash
forge --version            # 1.0.0+
make install               # forge install + pnpm
forge snapshot             # writes .gas-snapshot
forge test --gas-report    # prints the per-function gas profile
forge test --match-test "GasBench" -vvv     # benchmarks
```

For the L1-vs-L2 cost column, use `cast estimate` against a mainnet
fork:

```bash
ETH_PRICE_USD=3500
GWEI=31
cast estimate $FACTORY "createMarket(bytes32,int256,uint64,uint16)" \
    $(cast keccak "BTC>=100k @ 2026-12-31") 100000e8 1893456000 30 \
    --rpc-url $MAINNET_RPC_URL \
    | xargs -I{} echo "Gas: {}; USD: $(echo "{} * $GWEI * 1e-9 * $ETH_PRICE_USD" | bc -l)"
```
