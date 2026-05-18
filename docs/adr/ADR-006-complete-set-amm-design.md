# ADR-006 — "Mint complete sets, then swap" pricing pattern

**Status:** Accepted (W6)
**Decision-makers:** Evelina (core)

## Context

CPMM on two outcome tokens (YES, NO) needs a way to fund initial
reserves and price trades against collateral (USDC). Three patterns:

1. **Complete-set model** (Augur, Polymarket, Gnosis). A trader can
   always exchange 1 collateral for 1 YES + 1 NO (and vice versa). The
   AMM swaps between YES and NO; collateral is acquired/spent via the
   complete-set side path.
2. **Direct AMM in collateral** (Uniswap V2 with a virtual second
   asset). The pool holds collateral on one side, YES on the other.
   Requires NO to be priced separately or treated as 1 - YES.
3. **LMSR with subsidy.** Requires `exp` / `ln` on-chain (bespoke
   fixed-point math).

## Decision

Adopt pattern (1) — complete sets. The AMM reserves are YES and NO, not
collateral. Buying YES with collateral is a two-step path:

1. `mintCompleteSets(C)` — pull C collateral, mint C YES + C NO into the buyer's wallet.
2. `swap(NO → YES, C, minOut)` — buyer trades the C NO they don't want for additional YES.

Result: trader holds `C + getAmountOut(C, R_N, R_Y)` of YES. Collateral
sits inside the market backing the outcome supply.

## Consequences

- The CPMM invariant is the simplest possible (Uniswap V2 with 0.3%
  fee). Easy to audit, easy to invariant-test.
- Two-step UX. The frontend hides this — users see "buy YES with $C"
  as one action. The frontend simulates both steps off-chain to compute
  the final YES amount and slippage.
- The market always has exact 1-to-1 backing: `collateralBalance ==
  totalYesSupply == totalNoSupply` is an invariant. Tested in
  `test/invariant/PredictionMarketInvariant.t.sol::invariant_supplyParity`.
- "Sell YES for collateral" is also two-step (`swap YES → NO`, then
  `redeemCompleteSets`). The high-level `buyOutcome`/`sellOutcome`
  wrappers (W7+) compose the two steps atomically.
