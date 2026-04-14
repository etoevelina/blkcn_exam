# ADR-001 — Choosing CPMM (x · y = k) over LMSR for binary outcome pricing

**Status:** Accepted (W6)
**Decision-makers:** Evelina (core), Daniyar (governance/audit)

## Context

The spec for Option D (§1.2) allows either **LMSR** (Logarithmic Market
Scoring Rule) or **CPMM** (Constant Product Market Maker) as the pricing
mechanism for our binary outcome markets. We must pick one and justify it
in the architecture document.

## Options considered

1. **LMSR** — Hanson's market scoring rule.
   - Pros: well-defined bounded loss to the subsidiser; clean price = `e^q_i / Σ e^q_j`; continuous liquidity even at price extremes.
   - Cons: requires `exp` / `ln` on-chain → bespoke fixed-point math; harder to audit; needs a subsidy parameter `b` that must be governance-tuned per market; gas-heavier per trade.
2. **CPMM `x · y = k`** — Uniswap V2 style on the two outcome reserves.
   - Pros: trivial invariant to test (`k_new ≥ k_old`); ubiquitous prior art for both implementation and auditing; uses only `mul/div/add/sub` — no fixed-point library; LPs intuitively understand "concentration" via reserves.
   - Cons: zero liquidity at price extremes (close to 0 or 1) without infinite reserves; LPs bear inventory risk on the side the market trends toward.
3. **Hybrid** (CPMM + LMSR subsidy mode below a threshold) — too much surface area for a 5-week capstone.

## Decision

**CPMM.** Specifically: a two-token Uniswap-V2-style invariant with a
**0.3% LP fee** retained in the pool (boosting `k`), and a separate
ERC-4626 fee vault into which a portion of the fees (governance-controlled,
initially 0%) can be routed.

## Consequences

- The constant-product invariant `R_Y · R_N ≥ k_old` becomes a Foundry
  invariant test (one of the required ≥ 5 invariant tests).
- "Buy YES with collateral" is implemented as **mint complete sets +
  swap NO → YES**, mirroring the Augur / Polymarket pattern. This keeps
  the AMM math identical to plain Uniswap and lets us reuse known-good
  reasoning around overflow and price impact.
- Liquidity providers receive an ERC-20 LP token (`PLP`) representing
  their pro-rata share of the pool. On `removeLiquidity` they receive
  proportional YES + NO shares (which they can redeem 1:1 after
  finalisation, or sell on a secondary market).
- We accept the "no liquidity at extremes" trade-off: traders cannot
  push the price to literally 0 or 1, but in practice the market's
  utility is bounded well before that.

## Cross-references

- `src/markets/PredictionMarket.sol` — `_getAmountOut`, invariant assertion.
- `test/invariant/PredictionMarketInvariant.t.sol` — `invariant_kNeverDecreases` (W7).
- Audit report §3.2 (W10).
