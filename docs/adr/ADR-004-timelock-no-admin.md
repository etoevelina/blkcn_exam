# ADR-004 — Timelock without `TIMELOCK_ADMIN_ROLE` holder at steady state

**Status:** Accepted (W9)
**Decision-makers:** Daniyar (governance)

## Context

`OpenZeppelin TimelockController` accepts a fourth constructor argument
`admin` that, when non-zero, gets `DEFAULT_ADMIN_ROLE`. Holding that
role lets the holder bypass the time-locked queue and directly grant /
revoke `PROPOSER_ROLE` / `EXECUTOR_ROLE`.

Two patterns:

1. **Admin = address(0) forever.** No-one outside the Timelock itself
   can rotate roles. To grant a new proposer, the existing Governor must
   pass a proposal that calls `timelock.grantRole(...)` → 2-day delay.
2. **Admin = deployer at construct time, deployer renounces after wiring.**
   The deployer briefly holds admin to grant Governor the proposer role,
   then renounces. Steady-state is identical to (1).

A naive "admin = address(0)" constructor would mean the deployer cannot
grant Governor the proposer role at all (no role-holder exists to grant
anything). The OZ docs solve this by passing a TempAdmin in the
constructor's `proposers[]` array and using the OZ-internal admin path.
That's confusing and error-prone.

## Decision

Adopt pattern (2). `PredictionTimelock` constructor takes
`(address initialProposer, address initialAdmin)`. The deploy script
passes `(deployer, deployer)`, wires up the Governor, then has the
deployer call `renounceRole(DEFAULT_ADMIN_ROLE, deployer)`.

The post-deploy `Verify.s.sol` asserts:

```solidity
require(!tl.hasRole(0x00, deployer), "VERIFY: deployer still has TIMELOCK admin");
```

## Consequences

- Steady-state security identical to "admin = address(0) forever".
- Test fixtures can pass `(admin, admin)` to keep admin available
  throughout test runs — explicitly documented in `test/helpers/Fixture.sol`.
- Adds one line to the deploy script (the renounce). Tradeoff is worth
  the clarity.
