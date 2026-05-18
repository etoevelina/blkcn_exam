# ADR-005 — `clock() = block.timestamp` for the Governor stack

**Status:** Accepted (W9)
**Decision-makers:** Daniyar (governance), Evelina (core)

## Context

OZ Governor v5 supports two clock modes:

* **`block.number`** (default, IERC6372 "mode=blocknumber") — voting delay
  and period are counted in L1 blocks.
* **`block.timestamp`** (IERC6372 "mode=timestamp") — counted in seconds.

On Ethereum mainnet, block time is ~12s. On Arbitrum, block time is
~250 ms but varies (Sequencer can batch). On other L2s it's variable
again. A 1-day voting delay specified as blocks ends up wildly
inconsistent.

The spec mandates `voting delay = 1 day` and `voting period = 1 week`
as durations, not block counts.

## Decision

Use `mode=timestamp`. The `GovernanceToken` overrides:

```solidity
function clock() public view override returns (uint48) {
    return uint48(block.timestamp);
}

function CLOCK_MODE() public pure override returns (string memory) {
    return "mode=timestamp";
}
```

`PredictionGovernor` inherits this clock via `GovernorVotes(token)`. All
`votingDelay()` / `votingPeriod()` / proposal timestamps are seconds.

## Consequences

- Deterministic 1-day / 1-week durations regardless of L2 block-time
  variability.
- IERC6372 mandates `CLOCK_MODE()` returning the string literal
  `"mode=timestamp"`. The function name violates Solidity mixedCase
  convention; Slither flags it as Informational. Cannot rename —
  documented in audit §11 I-14.
- `block.timestamp` is manipulable by miners on L1 by ~15s, by Arbitrum
  Sequencer by similar margin. Acceptable for governance durations
  measured in days; not acceptable as a source of randomness (we never
  use it that way — spec §3.2).
