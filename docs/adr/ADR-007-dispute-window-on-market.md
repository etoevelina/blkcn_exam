# ADR-007 — Per-market dispute window between report and finalisation

**Status:** Accepted (W6)
**Decision-makers:** Evelina (core), Daniyar (governance/audit)

## Context

Chainlink can return a wrong price during the rare window where its
aggregator hasn't yet absorbed an outlier-removal round, or during a
deliberate attack on the underlying feeds. The spec requires both a
staleness check AND a dispute window (§3.1 Oracles).

Design space:

1. **Instant finalisation.** Reported outcome locks immediately; no
   dispute. Maximum simplicity, zero protection against feed manipulation.
2. **Per-market dispute window** (chosen). Between `reportOutcome` and
   `finalize`, the Timelock can `disputeOutcome` and then
   `resolveDispute(finalOutcome)` to override.
3. **UMA-style optimistic oracle.** Anyone can dispute by posting a
   bond; jurors resolve. Vastly more complex; out of scope for a 5-week
   capstone.

## Decision

Adopt (2). Each market has a `disputeWindow` (default 24 h, configurable
via governance) that starts the moment `reportOutcome` succeeds.

States:

```
Reported ──(within window, admin)──▶ Disputed ──(admin resolves)──▶ Finalized
   │
   └───(window elapses, anyone)─────────────────────────────────▶ Finalized
```

## Consequences

- 24 h is enough for the off-chain monitoring crew to flag a bad report
  and queue a `disputeOutcome` call. Not enough that legitimate users
  are kept waiting forever before they can claim.
- The `disputeOutcome` call is gated by `DEFAULT_ADMIN_ROLE` (Timelock).
  In practice, an emergency multisig with `CANCELLER_ROLE` on the
  Timelock could also trigger via a fast-queue proposal — but the
  baseline path is the standard Governor flow.
- `claimWinnings` can only run in `Finalized` state, so disputed
  markets correctly hold winnings hostage until governance decides.
- Per-market window (not protocol-wide) lets fast-resolving markets
  (sports betting) coexist with slow-resolving ones (year-end
  prediction).
