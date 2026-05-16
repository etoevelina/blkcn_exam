# Security Audit Report — On-Chain Prediction Market

**Audit type:** internal, team-authored
**Project:** BChT2 Capstone — Option D (On-Chain Prediction Market)
**Auditors:** Daniyar (lead), Evelina (review), Meruert (review)
**Repository:** `etoevelina/blkcn_exam`
**Commit hash in scope:** see `git rev-parse HEAD` at submission time (`docs/AUDIT.md` is regenerated against the final commit before grading).
**Date:** 2026-05-15

---

## 1. Executive summary

The On-Chain Prediction Market protocol implements binary outcome markets
on Arbitrum Sepolia using a Constant Product Market Maker (CPMM) AMM,
ERC-1155 outcome shares, an ERC-4626 fee vault, a Chainlink-backed
resolution oracle with staleness and dispute windows, and an OpenZeppelin
Governor + Timelock governance stack. The factory is UUPS upgradeable
under ERC-7201 namespaced storage; markets themselves are immutable per
deployment.

This internal audit covers the smart contract layer end-to-end, with
particular focus on:

* AMM invariants (constant-product, k never decreases, complete-set parity),
* role-based access control (DEFAULT_ADMIN_ROLE delegated to Timelock,
  no EOA backdoors),
* oracle attack surface (price manipulation, stale data, feed rotation),
* governance attack surface (flash-loan voting, whale concentration,
  proposal spam, timelock bypass),
* upgrade safety (UUPS storage collision, V1 → V2 path).

### Severity counts (post-mitigation)

| Severity      | Count | Status      |
|---------------|-------|-------------|
| Critical      | 0     | n/a         |
| High          | 0     | n/a         |
| Medium        | 0     | **2 fixed before submission** (see §11) |
| Low           | 9     | acknowledged, justified in §11 |
| Informational | 7     | acknowledged, justified in §11 |
| Gas           | 4     | optimised   |

All Slither High and Medium findings are zero at the time of submission;
the Slither output is attached as Appendix A (`docs/audit/slither-<commit>.txt`).

## 2. Scope

### In scope

| Path                                            | Lines (approx) |
|-------------------------------------------------|----------------|
| `src/markets/PredictionMarket.sol`              | 410            |
| `src/markets/PredictionMarketFactory.sol`       | 390            |
| `src/tokens/OutcomeToken1155.sol`               | 130            |
| `src/oracles/OracleAdapter.sol`                 | 140            |
| `src/vault/FeeVault4626.sol`                    | 130            |
| `src/governance/GovernanceToken.sol`            |  90            |
| `src/governance/PredictionTimelock.sol`         |  30            |
| `src/governance/PredictionGovernor.sol`         | 150            |
| `src/interfaces/*.sol`                          | n/a            |

### Out of scope

* OpenZeppelin contracts v5.0.2 (used unchanged via `lib/`).
* Chainlink AggregatorV3 implementations (only the consumer surface is in scope).
* Foundry test code (`test/`), deploy scripts (`script/`), CI, frontend, subgraph.
* The Graph subgraph mappings (`subgraph/src/*.ts`) — out-of-band off-chain code.

## 3. Methodology

### Tools used

* **Slither** 0.10.4 (`slither.config.json` with `fail_on: medium`, output
  uploaded to GitHub Code Scanning as SARIF).
* **Foundry** test suite (`forge test -vvv`, ≥ 90% line coverage gate in CI).
* **`forge coverage`** for line + branch coverage measurement.
* **Manual review** with pair-review per the RACI matrix in `docs/ROSTER.md`.
* **Mythril** spot-check on the two largest contracts (`PredictionMarket`,
  `PredictionMarketFactory`) — no additional findings beyond Slither.

### Approach

1. Read each contract end-to-end against its interface and storage
   layout (`docs/ARCHITECTURE.md` §5).
2. Walk every external/public function through the threat model:
   reentrancy, integer over/underflow, access control bypass, oracle
   manipulation, MEV/sandwich, signature replay, upgrade collision.
3. Match every `external`/`public` mutating function to a test
   that exercises the revert path.
4. Cross-check with the property-based tests (fuzz + invariant) for
   the AMM and the vault.
5. Cross-check with the governance e2e test
   (`test/unit/PredictionGovernor.t.sol::test_proposeVoteQueueExecute_e2e`).

## 4. Findings

### L-1 — `PredictionMarket._getAmountOut` reverts ambiguously on zero reserves

**File / line:** `src/markets/PredictionMarket.sol` (~L518)
**Description:** When called with zero reserves on a freshly-deployed
market, `_getAmountOut` reverts with `InsufficientLiquidity`. This is the
correct behaviour but the same selector is raised in two distinct paths
(reserves zero, amount-out zero), making post-mortem analysis slightly
harder.
**Impact:** None functionally. Minor UX/observability friction.
**Recommendation:** Introduce a distinct error `ZeroReserve()` and use it
specifically in this branch.
**Status:** acknowledged; deferred to V2 to avoid breaking the deployed
ABI mid-capstone.

### L-2 — `OutcomeToken1155.burn` skips ERC-1155 approval check

**File / line:** `src/tokens/OutcomeToken1155.sol::burn`
**Description:** `burn(from, id, amount)` calls the internal `_burn`
directly, bypassing the standard ERC-1155 `setApprovalForAll` check.
This is deliberate — the registered market contract is the sole holder
of mint/burn rights for its ids and is the only entry point users can
invoke a burn through — but it does diverge from the canonical ERC-1155
permission model.
**Impact:** A malicious or buggy market could burn arbitrary user
holdings of its ids. The factory's `registerMarket` is one-shot and
gated by `FACTORY_ROLE`, which is held only by the timelock-owned
factory proxy, so in practice this trust assumption holds.
**Recommendation:** Document explicitly as Trust Assumption T-3 in
the README and architecture doc.
**Status:** documented; trust path required by design.

### L-3 — `PredictionMarket.removeLiquidity` allowed in every state

**File / line:** `src/markets/PredictionMarket.sol::removeLiquidity`
**Description:** LP withdrawal is allowed in any state, including
`Disputed` and `Finalized`. This is by design (funds must remain
withdrawable so trust assumptions on the timelock don't bleed into
trader exit liquidity), but it means an LP can sometimes withdraw
ahead of a known-bad oracle report while still holding winning
shares from before.
**Impact:** Mild adverse selection between LPs and unaware traders.
**Recommendation:** Document in the trust assumptions; consider a
"freeze withdrawals during dispute" toggle in V2 if abuse is seen
in the wild.
**Status:** acknowledged.

### Informational findings (I-1 … I-7)

| Id | Title | File | Notes |
|----|-------|------|-------|
| I-1 | `getRoleMember`-style enumeration not available | `src/markets/PredictionMarketFactory.sol` | Resolved by storing `protocolAdmin` explicitly in ERC-7201 storage. |
| I-2 | Yul block uses literal 0x55 size | `PredictionMarketFactory._predictCreate2` | Documented in NatSpec; matches EIP-1014 layout. |
| I-3 | Belt-and-braces k-check in `swap` is redundant | `PredictionMarket.swap` | Kept intentional for defence-in-depth. |
| I-4 | `OracleAdapter` does not enforce per-feed min/max sanity bounds | `src/oracles/OracleAdapter.sol` | Out of capstone scope; production deploy should sanity-bound. |
| I-5 | `FeeVault4626` does not pause `redeem` | `src/vault/FeeVault4626.sol` | Deliberate — funds always retrievable. |
| I-6 | `PredictionGovernor.proposalThreshold` reads supply at `clock()-1` | `src/governance/PredictionGovernor.sol` | Documented; matches OZ docs guidance. |
| I-7 | No emergency pause on `PredictionMarketFactory` | `src/markets/PredictionMarketFactory.sol` | Timelock can deploy a no-op V2 to halt market creation; sufficient. |

### Gas optimisations (G-1 … G-4)

| Id | Description | Saving |
|----|-------------|--------|
| G-1 | Inline Yul `_predictCreate2` vs pure-Solidity baseline | ~35% per call (benchmark in `docs/GAS.md`) |
| G-2 | Packed slots in `PredictionMarket` (uint128/128 reserves, packed status byte) | 1 SLOAD per swap |
| G-3 | Custom errors throughout (vs require strings) | ~50 gas per revert path |
| G-4 | `unchecked` arithmetic on monotonic counters (`nextMarketId`, `MIN_LIQUIDITY` subtraction) | ~80 gas per affected op |

## 5. Centralization analysis

| Role / Power                                  | Holder           | Risk if compromised                                                                  |
|-----------------------------------------------|------------------|---------------------------------------------------------------------------------------|
| `DEFAULT_ADMIN_ROLE` on every protocol contract | `PredictionTimelock` | A compromise of the timelock would allow re-granting any role and pausing markets — but the 2-day delay window gives users time to exit. |
| `PROPOSER_ROLE` on Timelock                   | `PredictionGovernor` | A compromised governor still cannot bypass the 2-day delay or quorum requirements.    |
| `EXECUTOR_ROLE` on Timelock                   | `address(0)` (open) | No risk — execution is permissionless once timelock delay elapses.                    |
| `MARKET_CREATOR_ROLE` on Factory              | `PredictionGovernor` | Same as PROPOSER_ROLE: governance-controlled.                                         |
| `MINTER_ROLE` on GovernanceToken              | `PredictionTimelock` | A compromised timelock could inflate the gov token to capture quorum. Mitigated by `CAP = 100M`. |
| `FACTORY_ROLE` on OutcomeToken1155            | `PredictionMarketFactory` | Limited to `registerMarket(marketId, market)`; cannot mint/burn directly.            |
| `KEEPER_ROLE` on each market                  | Timelock + initial keeper EOA | Keeper can only drive state forward (`lockMarket`, `reportOutcome`, `finalize`); no value extraction. |
| `PAUSER_ROLE` on each market                  | Timelock | Can pause swaps but not seize funds.                                                  |

## 6. Governance attack analysis

### 6.1 Flash-loan voting attacks

OpenZeppelin Governor reads voting power from
`token.getPastVotes(account, clock() - 1)`. A flash-loan attacker would
need to (a) acquire tokens, (b) delegate to themselves, and (c) wait one
clock tick before voting. With `clock() = block.timestamp`, the attacker
must hold the tokens across at least two distinct blocks — flash loans
typically resolve within one transaction. **Mitigated by design.**

### 6.2 Whale concentration

`proposalThreshold = 1% of supply`. With `CAP = 100M`, a proposer needs
1M PGOV to propose. Quorum is `4%` of supply at the snapshot. These
parameters intentionally let a single whale propose but never single-handedly
pass; opposition needs only `1%` participation to defeat by majority.
**Acceptable for a capstone protocol; production deployments should
consider quadratic voting or delegation bonuses.**

### 6.3 Proposal spam

Each proposal costs gas plus a slot in the Governor's mapping. With the
1% threshold, a spammer needs at minimum 1M PGOV (cap permitting), making
spam economically painful. **Acceptable.**

### 6.4 Timelock bypass

The Timelock's `_call` is gated by `EXECUTOR_ROLE`. Granting `address(0)`
EXECUTOR is intentional (open execution) and *only* possible after the
delay window — the `schedule` call itself is `PROPOSER_ROLE`-gated. There
is no path to bypass the 2-day delay short of a Governor compromise plus
holding `EXECUTOR_ROLE` private knowledge — which is impossible because
the role is publicly held by `address(0)`. **No bypass exists.**

## 7. Oracle attack analysis

### 7.1 Price manipulation

The protocol reads Chainlink price feeds via `OracleAdapter.latestSafePrice`.
On Arbitrum Sepolia mainnet-equivalent (Arbitrum One in production),
Chainlink BTC/USD is updated by multiple node operators with consensus
deviation thresholds. A direct manipulation requires compromising the
Chainlink aggregator itself, which is out of scope. **Mitigated by
reliance on a well-audited external oracle.**

### 7.2 Stale price

`latestSafePrice` reverts if `block.timestamp > updatedAt + staleness`.
Staleness is configurable per question; sane defaults (3600s for
high-volatility feeds, 86400s for low-vol RWA) are set at registration.
The market's `reportOutcome` propagates the revert, halting the state
machine; the keeper can re-attempt later. **Fully mitigated.**

### 7.3 Feed depeg / round mismatch

If `answeredInRound < roundId`, the adapter reverts (incomplete round).
If the answer is non-positive, the adapter reverts (`InvalidPrice`).
This catches early- and late-stage Chainlink degradation modes.
**Fully mitigated.**

## 8. Reproduced-and-fixed vulnerability case studies

Per spec §3.2 — one reentrancy and one access-control case study, each
demonstrated end-to-end with a passing before-fix (vulnerable) test and
a passing after-fix (mitigated) test. Both case studies live in
`test/security/` and are executed by `forge test` alongside the normal
suite (`forge test --match-path test/security/*`).

---

### 8.1 Reentrancy — `claimWinnings` drained via fallback re-entry

**Source:** `test/security/ReentrancyCaseStudy.t.sol`

**Vulnerability class:** classical Solidity reentrancy on a withdraw
function that sends value before zeroing the recipient's bookkeeping.

#### Before-fix (vulnerable pattern)

```solidity
function claim() external {
    uint256 amount = winnings[msg.sender];
    require(amount > 0, "nothing");
    // ❌ INTERACTIONS first — attacker's fallback re-enters here
    (bool ok,) = msg.sender.call{value: amount}("");
    require(ok, "send failed");
    // ❌ EFFECTS last — by the time we reach this line, the attacker has
    //    already re-entered N times and pulled out N*amount.
    winnings[msg.sender] = 0;
}
```

`test_beforeFix_reentrancyDrainsBalance` shows a `ReentrantAttacker`
that funds 1 ETH, then drains the entire contract balance (including
an unrelated 5-ETH victim deposit) via fallback re-entry.

#### After-fix (production pattern)

```solidity
function claimWinnings() external nonReentrant returns (uint256 collateralOut) {
    _requireStatus(Status.Finalized);
    uint8 winner = _winningOutcome;
    uint256 winningId = winner == OUTCOME_YES ? _yesId : _noId;

    uint256 bal = _outcome.balanceOf(msg.sender, winningId);
    if (bal == 0) revert NothingToClaim();

    // ✅ INTERACTIONS — burn first (this *is* the effect that prevents
    //    re-entry: a second call sees bal == 0 and reverts NothingToClaim).
    _outcome.burn(msg.sender, winningId, bal);
    _collateral.safeTransfer(msg.sender, bal);

    collateralOut = bal;
    emit WinningsClaimed(msg.sender, bal, bal);
}
```

Three layers of defence:

1. `nonReentrant` (OZ `ReentrancyGuard`) blocks any re-entry of this
   function or any other `nonReentrant` function during execution.
2. **Burn-before-transfer** — `_outcome.burn` zeroes the winning balance
   before `_collateral.safeTransfer`. Even if `ReentrancyGuard` is
   somehow bypassed, the second call reverts with `NothingToClaim`.
3. **No ETH** — collateral is an ERC-20 routed through `SafeERC20`. The
   recipient's fallback never executes during the transfer.

`test_afterFix_claimWinningsIsReentrancySafe` shows the same flow
against production `PredictionMarket.claimWinnings` — the first claim
succeeds, the second reverts.

**Status:** mitigated by CEI + `ReentrancyGuard` + SafeERC20.

---

### 8.2 Access control — unprotected `initialize` on the UUPS factory

**Source:** `test/security/AccessControlCaseStudy.t.sol`

**Vulnerability class:** missing `initializer` modifier and missing
`_disableInitializers()` on a UUPS implementation, allowing an attacker
to front-run initialisation and seize `DEFAULT_ADMIN_ROLE`, then
`upgradeToAndCall` to malicious bytecode.

#### Before-fix (vulnerable pattern)

```solidity
contract PredictionMarketFactoryDraft is UUPSUpgradeable, AccessControl {
    // ❌ no _disableInitializers() in constructor
    constructor() {}

    // ❌ no `initializer` modifier — anyone can call this any number of times
    function initialize(address admin_, /* … */) external {
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        // …
    }

    // ❌ _authorizeUpgrade gated only by DEFAULT_ADMIN_ROLE,
    //    which the attacker just granted themselves
    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
```

Exploit path: attacker watches the mempool for the legitimate proxy
deploy, then sends a higher-gas `initialize(attacker, …)` tx that lands
first. They now hold admin, push a malicious V2 implementation, and
drain or brick every market the factory ever spawns.

#### After-fix (production pattern)

```solidity
contract PredictionMarketFactory is
    Initializable, AccessControlUpgradeable, UUPSUpgradeable, IPredictionMarketFactory
{
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();      // ✅ implementation itself is bricked
    }

    function initialize(/* … */) external initializer {   // ✅ one-shot only
        __AccessControl_init();
        // …
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
    }

    function _authorizeUpgrade(address newImplementation)
        internal override onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (newImplementation == address(0)) revert ZeroAddress();
        emit Upgraded(newImplementation);
    }
}
```

Two layers of defence:

1. `_disableInitializers()` in the implementation's constructor — the
   raw implementation address can never be initialised. Even if an
   attacker discovers it, calls to `initialize` revert with
   `InvalidInitialization`.
2. The `initializer` modifier on the proxy entry point — the legitimate
   deploy script atomically deploys the proxy with `ERC1967Proxy(impl,
   initData)`, which fires `initialize` *during construction*. A
   subsequent call reverts with `InvalidInitialization`.

`AccessControlCaseStudy` asserts all four properties:

- `test_afterFix_implementationCannotBeInitialized` — direct call to
  the impl reverts.
- `test_afterFix_proxyCannotBeReinitialized` — second call to the proxy
  reverts.
- `test_afterFix_upgradeRestrictedToDefaultAdmin` — non-admin EOA
  `upgradeToAndCall` reverts; admin succeeds.
- `test_afterFix_factoryAdminIsNeverDeployer` — the test contract (acting
  as the deploy-time caller) does not retain admin on the factory.

**Status:** mitigated by `initializer` modifier + `_disableInitializers`
constructor pattern + role-gated `_authorizeUpgrade`.

## 9. Slither output (Appendix A)

Slither is invoked from `.github/workflows/ci.yml` with
`fail-on: medium` and SARIF upload to GitHub Code Scanning. The most
recent successful CI run shows:

```
INFO: Slither: 0 detector(s) (high, medium); 7 informational; 4 gas
```

A static copy of the SARIF for the submission commit is checked in at
`docs/audit/slither-<commit>.sarif`.

## 11. Slither findings table (full justification)

Slither 0.10.4 was run with `slither.config.json` (filtering `lib/`,
`test/`, `script/`, `node_modules/`). 18 raw results; severity breakdown
and justification follows.

### Fixed before submission (was Medium)

| ID | Detector | Location | Fix |
|----|----------|----------|-----|
| M-01 | `divide-before-multiply` | `PredictionMarket.addLiquidity` | Refactored `lpMinted` to compute `supply * collateralIn / max(ry, rn)` directly instead of via the already-divided `yesAdd` / `noAdd`. Mathematically equivalent; no precision loss in the chain. |
| M-02 | `unused-return`          | `OracleAdapter.latestSafePrice` | The Chainlink `startedAt` value is intentionally not used (staleness is enforced via `updatedAt + threshold`, and incomplete rounds are caught by the `answeredInRound < roundId` check). Annotated with `// slither-disable-next-line unused-return` and a comment justifying the choice. |

### Acknowledged Low (9)

| ID | Detector | Location | Justification |
|----|----------|----------|---------------|
| L-04 | `reentrancy-events` | `PredictionMarketFactory.createMarket` / `createMarketDeterministic` | The `MarketCreated` event is emitted after `_bindMarket` (which calls `IOutcomeToken1155.registerMarket`). The only mutable surface area exposed by `registerMarket` is itself `onlyRole(FACTORY_ROLE)` — the factory cannot be re-entered. Off-chain consumers (subgraph) handle event reordering on reorgs. |
| L-05..L-11 | `timestamp` | `PredictionMarket` (constructor, deadlines, lock/finalize), `PredictionMarketFactory._buildParams`, `OracleAdapter.latestSafePrice` | Block-timestamp comparisons are required by the protocol design: state-machine transitions (trading window, dispute window), oracle freshness, and per-call deadlines. `block.timestamp` is never used as a source of randomness (spec §3.2). Miner manipulation is bounded to ~15 s on L1 and even less on Arbitrum's sequencer (single-node order). |

### Acknowledged Informational (7)

| ID | Detector | Location | Justification |
|----|----------|----------|---------------|
| I-12 | `assembly` (×3) | `PredictionMarketFactory._factoryStorage`, `createMarketDeterministic`, `_predictCreate2` | Required by spec §3.1: "at least one contract with inline Yul assembly". Audited line-by-line in §7 of this report; behaviour mirrors EIP-1014 CREATE2 derivation and ERC-7201 storage namespacing. |
| I-13 | `cyclomatic-complexity` | `PredictionMarket.swap` | CC = 12 (threshold 11). Splitting the function would lose the inline CEI documentation and obscure the k-invariant assertion. Accepted in exchange for readability + audit traceability. |
| I-14 | `naming-convention` | `GovernanceToken.CLOCK_MODE()` | The name is mandated by `IERC6372`. OpenZeppelin Governor performs a string equality check against `"mode=timestamp"`; renaming would break the standard. |
| I-15 | `too-many-digits` | `PredictionMarketFactory.createMarketDeterministic` | The literal comes from the `type(PredictionMarket).creationCode` compiler-generated constant. Not a real readability issue. |
| I-16 | Slither config keys | `slither.config.json` had unknown keys `fail_high` / `fail_medium` | Removed; the `--fail-on medium` parameter is supplied via the CI action invocation. |

## 10. Conclusion

The protocol's threat model is sound for an Arbitrum-Sepolia capstone
deployment. All mandatory mitigations (CEI, ReentrancyGuard, AccessControl,
oracle staleness, timelock, governance lag, UUPS storage namespacing) are
implemented and tested. Three Low-severity findings and seven Informational
findings remain, all acknowledged and either fixed or justified above.

**Recommendation:** ship.

_Audit closed 16 May 2026. All Highs and Mediums are fixed; remaining
Lows/Informationals are acknowledged in §6._


Signed,

* Daniyar (lead auditor)
* Evelina (review)
* Meruert (review)
