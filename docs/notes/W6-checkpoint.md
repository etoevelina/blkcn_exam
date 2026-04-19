# W6 Checkpoint — Review Notes

**Author:** Daniyar
**Date:** 2026-04-19
**Scope reviewed:** W6 baseline scaffold (commits `chore(repo)` → `feat(factory)`).

## What I reviewed

* `docs/ARCHITECTURE.md` — system context, component diagram, state machine, storage layout, design-pattern justification.
* `docs/adr/ADR-001-cpmm-vs-lmsr.md` — pricing model decision.
* `docs/adr/ADR-002-uups-target-selection.md` — UUPS target decision.
* `src/interfaces/` — four interfaces.
* `src/tokens/OutcomeToken1155.sol` — singleton ERC-1155 implementation.
* `src/markets/PredictionMarket.sol` — CPMM AMM core.
* `src/markets/PredictionMarketFactory.sol` — UUPS factory with `CREATE` + `CREATE2`.

## Findings (Informational — to be addressed in W7+)

| Id | Severity | Location                                  | Note                                                                                   |
|----|----------|-------------------------------------------|----------------------------------------------------------------------------------------|
| W6-01 | Info | `PredictionMarket.addLiquidity`           | Excess-share leftover transfer to LP must be invariant-tested for both ratio branches. |
| W6-02 | Info | `PredictionMarket.swap`                   | Belt-and-braces `k`-invariant assertion is redundant with the formula; keep it anyway for defence-in-depth and write a fuzz test that it never trips. |
| W6-03 | Info | `PredictionMarketFactory._predictCreate2` | Yul branch must be benchmarked against `predictMarketAddressSolidity` in W7 — target ≥ 30% gas reduction to justify keeping the Yul path. |
| W6-04 | Info | `PredictionMarketFactory.initialize`      | Add a `reinitializer(2)` placeholder in V1 to keep the V2 storyline credible.          |
| W6-05 | Info | `OutcomeToken1155.burn`                   | "Trust the registered market" model must be explicit in the audit (Trust Assumption T-3). |

## Next milestones (W7)

* Add `src/oracles/OracleAdapter.sol` + `src/oracles/MockAggregatorV3.sol`.
* Add `src/vault/FeeVault4626.sol`.
* Begin Foundry test suite. Targets at end of W7:
  - ≥ 15 unit tests across `PredictionMarket`, `OutcomeToken1155`, `PredictionMarketFactory`.
  - 2 fuzz tests (swap monotonicity, addLiquidity ratio preservation).
  - 1 invariant test (`k_after ≥ k_before` after every swap).
* CI: GitHub Actions for `forge build` + `forge test` + `forge fmt --check`.

## Sign-off

Reviewed and approved for W6 milestone artifact.
