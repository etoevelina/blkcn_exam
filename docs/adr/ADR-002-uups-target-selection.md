# ADR-002 — UUPS upgradeability on the Factory, not on the Market

**Status:** Accepted (W6)
**Decision-makers:** Evelina (core)

## Context

§3.1 of the spec mandates "at least one upgradeable contract using UUPS
proxy pattern with a documented V1 → V2 upgrade path". We must decide
**which** contract is the upgrade target.

## Options considered

1. **Each `PredictionMarket` is its own UUPS proxy.**
   - Pros: per-market bugfixes; flexible.
   - Cons: traders lose the guarantee that market rules are immutable
     once they bought a YES/NO share. Every market becomes
     a trust assumption on the upgrade admin. Slither flags any per-market
     proxy whose admin can rewrite reserves as a centralisation risk.
2. **`PredictionMarketFactory` is UUPS; markets are immutable.**
   - Pros: trader rules are immutable; only *how new markets are created*
     is mutable. Storage namespace lives in one well-audited contract.
   - Cons: cannot retroactively fix a critical bug in an existing market —
     we'd need to redeploy and migrate liquidity manually.
3. **`FeeVault4626` is UUPS.**
   - Pros: vault accounting is a likely source of future tuning.
   - Cons: ERC-4626 invariants are mechanical; we don't anticipate a
     reason to upgrade them.

## Decision

**Option 2.** The factory is the UUPS proxy target. Markets are
fresh, immutable contracts.

The V1 → V2 migration path is:

1. Deploy `PredictionMarketFactoryV2` (new implementation).
2. Submit governance proposal `upgradeToAndCall(V2, abi.encodeCall(V2.initializeV2, (...)))`.
3. Wait voting delay (1 day) + voting period (1 week) + timelock (2 days).
4. Execute. Storage is preserved via ERC-7201 namespaced storage; any new
   state added in V2 lives in a **new** namespace
   (`erc7201:prediction.market.factory.v2`), making collisions impossible.
5. Post-upgrade verification script asserts:
   - storage slot 0–N of V1 is byte-identical to V2,
   - `getRoleAdmin(DEFAULT_ADMIN_ROLE) == TIMELOCK`,
   - `nextMarketId` did not regress.

## Consequences

- The factory **must** use ERC-7201 namespaced storage from V1 to avoid
  storage-collision proofs across every variable. This is the modern OZ-5
  way; we adopt it.
- `_authorizeUpgrade` is gated by `onlyRole(DEFAULT_ADMIN_ROLE)`, and
  `DEFAULT_ADMIN_ROLE` is held exclusively by the Timelock.
- We document the storage namespace slot constant in
  `docs/ARCHITECTURE.md` §5.2.
- Markets stay immutable. If a market bug is discovered post-deploy, the
  recovery procedure is: governance pauses the market, retires it via
  `setInvalid()`, refunds complete sets 1:1, and creates a replacement
  through the (possibly upgraded) factory.
