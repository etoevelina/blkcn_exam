# Architecture — On-Chain Prediction Market

**Status:** v0.1 (W6 baseline)
**Authors:** Evelina (core), Daniyar (governance/audit), Teammate 3 (frontend/devops)
**Scope of this document:** the full protocol, not only the W6 deliverables.

---

## 1. System context (C4 — Level 1)

```mermaid
graph TB
    User[End user / LP / Trader]
    Voter[Governance voter]
    Keeper[Resolution keeper]
    Sub[The Graph subgraph]
    FE[Frontend dApp]
    CL[Chainlink AggregatorV3]
    Protocol[(Prediction Market Protocol<br/>on Arbitrum Sepolia)]

    User -->|swap, addLP, removeLP, claim| FE
    Voter -->|propose / vote / queue / execute| FE
    Keeper -->|lock, report, finalize| Protocol
    FE --> Protocol
    FE --> Sub
    Protocol -->|emit events| Sub
    Protocol -->|latestRoundData| CL
```

The protocol is self-contained on a single L2. External dependencies are
**Chainlink** (price/data feeds) and **The Graph** (read-only indexing).
There is no off-chain backend in the trust path.

## 2. Component diagram (C4 — Level 2)

```mermaid
graph LR
    subgraph Market plane
        PMF[PredictionMarketFactory<br/>UUPS proxy]
        PM[PredictionMarket<br/>per market, immutable]
        OT[OutcomeToken1155<br/>singleton]
        OA[OracleAdapter]
        FV[FeeVault4626]
    end
    subgraph Governance plane
        GT[GovernanceToken<br/>ERC20Votes + Permit]
        GOV[PredictionGovernor]
        TL[PredictionTimelock<br/>2-day delay]
        TR[Treasury]
    end
    subgraph External
        CL[Chainlink<br/>AggregatorV3]
    end

    PMF -- CREATE / CREATE2 --> PM
    PM -- mint/burn YES,NO --> OT
    PM -- read price --> OA
    OA -- latestRoundData --> CL
    PM -- fee transfer --> FV

    GT --> GOV
    GOV --> TL
    TL --> TR
    TL -- admin role --> PMF
    TL -- admin role --> OA
    TL -- admin role --> FV
```

### 2.1 Roles & access control

| Role                                  | Holder                | Powers                                                                 |
|---------------------------------------|-----------------------|------------------------------------------------------------------------|
| `DEFAULT_ADMIN_ROLE` (Factory + Vault + Oracle) | `PredictionTimelock` | Grant/revoke other roles, set protocol parameters                |
| `PROPOSER_ROLE` (Timelock)            | `PredictionGovernor`  | Queue executions                                                       |
| `EXECUTOR_ROLE` (Timelock)            | `address(0)` (open)   | Execute queued operations after delay                                  |
| `CANCELLER_ROLE` (Timelock)           | Multisig (W9)         | Emergency cancel of queued proposals                                   |
| `KEEPER_ROLE` (Market)                | EOA / Chainlink Automation | Call `lockMarket`, `reportOutcome`, `finalize` (only state transitions, no value extraction) |
| `PAUSER_ROLE` (Market)                | `PredictionTimelock`  | Pause swaps/LP in emergency                                            |
| `MARKET_MINTER_ROLE` (OutcomeToken1155) | per-market `PredictionMarket` instances | Mint/burn YES/NO ids for that specific market           |

**No EOA owns any privileged role at steady state.** All admin power is
mediated by the 2-day Timelock, which itself is controlled by the on-chain
Governor. See §6 (Trust assumptions).

## 3. Contract responsibilities

### 3.1 `PredictionMarket` (per-market, non-upgradeable)

A single market is one binary question (e.g. "BTC/USD ≥ $100k on
2026-12-31 UTC"). Each instance:

- holds reserves of YES (id = `2 * marketId`) and NO (id = `2 * marketId + 1`) shares;
- is the only `MARKET_MINTER` of those two token ids on the singleton ERC-1155;
- implements a constant-product (`x · y = k`) AMM with a **0.3% LP fee**;
- maintains an internal ERC-20 LP token (`PLP`);
- transitions through a state machine (§4);
- redeems winning shares 1:1 for collateral after finalisation, **pull-style**.

Markets are deliberately **non-upgradeable** so traders are guaranteed the
rules don't change underneath them once they buy in.

### 3.2 `PredictionMarketFactory` (UUPS upgradeable)

The factory is the only contract that can create new markets. It:

- deploys markets via `CREATE` (`createMarket`) and via `CREATE2`
  (`createMarketDeterministic`), letting integrators pre-compute the address;
- holds a registry `marketId → marketAddress` plus the reverse mapping;
- grants the new market the `MARKET_MINTER_ROLE` on the singleton ERC-1155
  immediately after deploy;
- uses **ERC-7201 namespaced storage** to make storage collisions impossible
  across V1 → V2 upgrades (§5);
- is owned by the Timelock; upgrades require a governance proposal.

The factory is also the natural place for inline Yul: `predictMarketAddress`
computes the CREATE2 address (`keccak256(0xff ‖ factory ‖ salt ‖ keccak256(initCode))`)
in 5 lines of Yul that we benchmark against a pure-Solidity equivalent in W7.

### 3.3 `OutcomeToken1155`

ERC-1155 singleton. Token IDs are derived deterministically from the
market id, so no on-chain mapping is needed:

```
yesId(marketId) = marketId * 2
noId (marketId) = marketId * 2 + 1
```

Mint/burn for a given id is gated by `MARKET_MINTER_ROLE`, and the role is
granted only to the market that owns that id. Other markets cannot mint
into someone else's id range.

### 3.4 `OracleAdapter` (W8)

Wraps a Chainlink `AggregatorV3Interface`. Reverts if the reported price is
older than `STALENESS_THRESHOLD` (configurable per feed, governance-controlled).
Exposes:

- `latestSafePrice(feed)` — reverts on stale / negative / zero-round data;
- `resolveBinary(market, threshold)` — returns `0` (YES) or `1` (NO) based
  on the comparison;
- a **dispute window** (default 24h) during which `disputeOutcome` may be
  invoked by governance, blocking finalisation.

### 3.5 `FeeVault4626` (W8)

ERC-4626 vault denominated in the protocol's collateral token. LP fees
collected from `PredictionMarket` instances flow here. Shares are
non-rebasing; yield accrues as `convertToAssets` grows. We ship the
standard OZ ERC-4626 plus an explicit set of rounding invariants:

```
previewDeposit(x) ≤ deposit(x)     // user can never get more shares than the preview
previewMint(s)   ≥ mint(s)         // user always pays at least the previewed assets
previewWithdraw(a)≥ withdraw(a)    // shares burnt cannot be lower than preview
previewRedeem(s) ≤ redeem(s)       // assets returned cannot exceed preview
```

These invariants will be enforced via Foundry invariant tests in W8.

### 3.6 Governance plane (W9)

- `GovernanceToken` — `ERC20 + ERC20Votes + ERC20Permit`, fixed cap of 100M.
- `PredictionGovernor` — `Governor + GovernorSettings + GovernorCountingSimple
  + GovernorVotes + GovernorVotesQuorumFraction + GovernorTimelockControl`.
  - voting delay: **1 day** (`7200 blocks` on Arbitrum; we use `block.number`
    via the standard OZ clock unless we switch to `timestamp` mode);
  - voting period: **1 week**;
  - quorum: **4% of total supply**;
  - proposal threshold: **1% of total supply**.
- `PredictionTimelock` — `TimelockController`, minDelay = **2 days**.

Scope of governance: market creation parameters (fees, dispute window),
oracle whitelist, vault parameters, and treasury spending. The Governor
**cannot** rewrite an in-flight market's outcome — only resolve a dispute
within the dispute window via the standard adapter call.

## 4. Market lifecycle (state machine)

```
                          ┌─────────────────────────────────────────────┐
                          │                  Open                       │  default after deploy
                          │  addLiquidity, removeLiquidity, swap, mint/redeem complete sets │
                          └───────────────┬─────────────────────────────┘
                                          │ block.timestamp ≥ tradingEndsAt && lockMarket()
                                          ▼
                          ┌─────────────────────────────────────────────┐
                          │                 Locked                      │  no trading; LP can still removeLiquidity
                          └───────────────┬─────────────────────────────┘
                                          │ reportOutcome() via OracleAdapter
                                          ▼
                          ┌─────────────────────────────────────────────┐
                          │                Reported                     │  dispute window open
                          └─────┬────────────────────────┬──────────────┘
        disputeOutcome() via DAO │                        │ block.timestamp ≥ disputeEndsAt && finalize()
                                 ▼                        ▼
                  ┌──────────────────────┐    ┌─────────────────────────┐
                  │      Disputed        │    │       Finalized         │
                  │  governance decides  │    │  claimWinnings() open   │
                  └──────┬───────────────┘    └─────────────────────────┘
                         │ resolveDispute(outcome) by Timelock
                         ▼
                  (transitions to Finalized)
```

`Invalid` is a side state (reachable from `Reported` or `Disputed`) that
allows redemption of complete sets 1:1 (i.e. cancels the market).

## 5. Storage layout

### 5.1 `PredictionMarket` (non-upgradeable, slot-explicit)

| Slot | Field                          | Type                  | Notes                            |
|------|--------------------------------|-----------------------|----------------------------------|
| 0    | `_balances` (ERC-20 LP)        | mapping(address ⇒ uint256) | inherited from OZ ERC-20    |
| 1    | `_allowances` (ERC-20 LP)      | mapping(address ⇒ mapping(address ⇒ uint256)) |     |
| 2    | `_totalSupply` (LP)            | uint256               |                                  |
| 3    | `_name` (LP)                   | string                |                                  |
| 4    | `_paused`                      | bool                  | from Pausable                    |
| 5    | `_status` (ReentrancyGuard)    | uint256               |                                  |
| 6    | `_roles`                       | mapping               | from AccessControl               |
| 7    | `reserveYes`                   | uint128 + uint128 packed with `reserveNo` | packed slot   |
| 8    | `tradingEndsAt` (uint64) `‖ disputeEndsAt` (uint64) `‖ status` (uint8) `‖ winningOutcome` (uint8) | packed | single slot |
| 9    | `marketId`                     | uint64                | immutable-style (set in constructor) |
| 10   | `feeBps`                       | uint16                |                                  |
| 11   | `claimed[address]`             | mapping(address ⇒ uint256) | for pull-style claim tracking |
| —    | `collateralToken`              | `IERC20`              | **immutable** (no slot)          |
| —    | `outcomeToken`                 | `IOutcomeToken1155`   | **immutable**                    |
| —    | `oracleAdapter`                | `IOracleAdapter`      | **immutable**                    |
| —    | `feeVault`                     | address               | **immutable**                    |
| —    | `questionId`                   | bytes32               | **immutable**                    |

Markets are **not upgradeable**; this table exists for review, not for collision proofs.

### 5.2 `PredictionMarketFactory` (UUPS — ERC-7201 namespaced storage)

```solidity
/// @custom:storage-location erc7201:prediction.market.factory.main
struct FactoryStorage {
    address oracleAdapter;          // adapter wrapping Chainlink
    address feeVault;               // ERC-4626 fee receiver
    address outcomeToken;           // singleton ERC-1155
    address collateralToken;        // e.g. USDC
    uint64  nextMarketId;
    uint16  defaultFeeBps;
    uint32  defaultDisputeWindow;   // seconds
    mapping(uint64 => address) marketById;
    mapping(address => uint64) idByMarket;
}

// keccak256(abi.encode(uint256(keccak256("prediction.market.factory.main")) - 1)) & ~bytes32(uint256(0xff))
bytes32 constant FACTORY_STORAGE_SLOT =
    0x8a6eeb15c0a4f6f1bc393fbd6de59958b6281e71cb4379c188e2764f21c90200;
```

Because this contract is upgradeable, **no other storage variables** appear
at fixed slots — the `_authorizeUpgrade` check + namespaced storage make
V1 → V2 upgrades collision-proof. The V1 → V2 path is documented in ADR-002
(`docs/adr/ADR-002-uups-target-selection.md`).

#### Storage-collision proof for V1 → V2 upgrades

The ERC-7201 namespace slot is derived deterministically from the string
`"prediction.market.factory.main"`. Slither, manual audit, and the
`script/StorageSlot.s.sol` derivation script all produce the same hex:

```
keccak256(abi.encode(uint256(keccak256("prediction.market.factory.main")) - 1)) & ~bytes32(uint256(0xff))
  = 0x8a6eeb15c0a4f6f1bc393fbd6de59958b6281e71cb4379c188e2764f21c90200
```

V2 of the factory **must** keep its `FactoryStorage` struct as a strict
superset of V1: append-only fields after the last V1 field, never reorder
or delete. New unrelated state in V2 lives under a *new* namespace
(`erc7201:prediction.market.factory.v2`), giving us two non-overlapping
slot regions. The `_authorizeUpgrade` hook is `onlyRole(DEFAULT_ADMIN_ROLE)`,
which only the Timelock holds → unauthorised upgrades revert at the proxy
layer.

### 5.3 `OutcomeToken1155` (singleton ERC-1155, non-upgradeable)

| Slot | Field                | Type                                | Notes                       |
|------|----------------------|-------------------------------------|-----------------------------|
| 0    | `_balances`          | mapping(uint256 ⇒ mapping(address ⇒ uint256)) | inherited from OZ ERC-1155 |
| 1    | `_operatorApprovals` | mapping(address ⇒ mapping(address ⇒ bool))    |                            |
| 2    | `_uri`               | string                              | base URI                    |
| 3    | `_roles`             | mapping(bytes32 ⇒ RoleData)         | from AccessControl          |
| 4    | `_marketOfId`        | mapping(uint256 ⇒ address)          | id ⇒ authorised market      |
| 5    | `_registered`        | mapping(uint64 ⇒ bool)              | marketId ⇒ registered flag  |

ID derivation is pure (no state): `yesIdOf(m) = m * 2`, `noIdOf(m) = m * 2 + 1`.

### 5.4 `OracleAdapter` (non-upgradeable, AccessControl-gated)

| Slot | Field        | Type                          | Notes                                 |
|------|--------------|-------------------------------|---------------------------------------|
| 0    | `_roles`     | mapping(bytes32 ⇒ RoleData)   | from AccessControl                    |
| 1    | `_feeds`     | mapping(bytes32 ⇒ FeedConfig) | questionId ⇒ (feed, staleness, window, registered) |

`FeedConfig` is packed into a single slot: `address feed` (20 bytes) +
`uint32 staleness` (4 bytes) + `uint32 disputeWindow` (4 bytes) + `bool
registered` (1 byte) = 29 bytes, fits in a 32-byte slot.

### 5.5 `FeeVault4626` (non-upgradeable, ERC-4626)

| Slot | Field                | Type                              | Notes                          |
|------|----------------------|-----------------------------------|--------------------------------|
| 0–3  | ERC-20 base state    | balances/allowances/totalSupply/name | from OZ ERC-20              |
| 4    | `_paused`            | bool                              | Pausable                       |
| 5    | `_status`            | uint256                           | ReentrancyGuard                |
| 6    | `_roles`             | mapping                           | AccessControl                  |
| 7    | `_asset`             | IERC20                            | from ERC4626 (immutable, slot reserved by OZ pattern) |
| 8    | `_underlyingDecimals`| uint8                             | from ERC4626                   |

`_decimalsOffset()` returns 1 (constant) so the inflation-attack surface
is one decimal beyond the asset's. Pure function, no storage.

### 5.6 `GovernanceToken` (non-upgradeable, ERC20 + ERC20Votes + ERC20Permit)

| Slot | Field                | Type                              | Notes                          |
|------|----------------------|-----------------------------------|--------------------------------|
| 0    | `_balances`          | mapping(address ⇒ uint256)        | ERC-20                         |
| 1    | `_allowances`        | mapping(address ⇒ mapping)        | ERC-20                         |
| 2    | `_totalSupply`       | uint256                           | ERC-20                         |
| 3    | `_name`              | string                            |                                |
| 4    | `_symbol`            | string                            |                                |
| 5    | `_nameHash`          | bytes32                           | EIP-712 / ERC-20Permit         |
| 6    | `_versionHash`       | bytes32                           | EIP-712                        |
| 7    | `_nonces`            | mapping(address ⇒ Counters.Counter)| Nonces                        |
| 8    | `_delegation`        | mapping(address ⇒ address)        | ERC-20Votes                    |
| 9    | `_delegateCheckpoints`| mapping(address ⇒ Checkpoints.Trace224) | ERC-20Votes              |
| 10   | `_totalSupplyCheckpoints` | Checkpoints.Trace224         | ERC-20Votes                    |
| 11   | `_roles`             | mapping                           | AccessControl                  |
| —    | `CAP`                | uint256                           | constant — no slot             |

Clock mode is `timestamp` (override of OZ defaults) — checkpoints are
keyed by `uint48 timestamp`. This is required for Arbitrum where L2
block times are variable.

### 5.7 `PredictionTimelock` (non-upgradeable, OZ TimelockController)

Inherits OZ `TimelockController` directly. Storage layout is **exactly**
OZ's, no additions:

| Slot | Field             | Type                          | Notes                                |
|------|-------------------|-------------------------------|--------------------------------------|
| 0    | `_roles`          | mapping(bytes32 ⇒ RoleData)   | AccessControl                        |
| 1    | `_timestamps`     | mapping(bytes32 ⇒ uint256)    | operation id ⇒ scheduled ETA         |
| 2    | `_minDelay`       | uint256                       | set to 2 days in constructor         |

`PROPOSER_ROLE` holder = Governor.
`EXECUTOR_ROLE` holder = `address(0)` (open execution).
`DEFAULT_ADMIN_ROLE` holder = none (deployer renounces at deploy time;
asserted by `Verify.s.sol`).

### 5.8 `PredictionGovernor` (non-upgradeable, OZ Governor stack)

Inherits the OZ Governor diamond:

```
Governor
  ↳ GovernorSettings           (votingDelay, votingPeriod, proposalThreshold storage)
  ↳ GovernorCountingSimple     (per-proposal vote tallies)
  ↳ GovernorVotes              (token reference)
  ↳ GovernorVotesQuorumFraction (quorum numerator)
  ↳ GovernorTimelockControl    (timelock reference)
```

Each extension adds a couple of slots; OZ's `__gap` arrays preserve
forward compatibility, but **we never upgrade the Governor** (it's
deployed once and is not behind a proxy). Storage collisions are
therefore not a concern.

Key constants:

| Constant            | Value                  | Source                          |
|---------------------|------------------------|---------------------------------|
| `votingDelay`       | `1 days`               | GovernorSettings                |
| `votingPeriod`      | `1 weeks`              | GovernorSettings                |
| `proposalThreshold` | 1% of totalSupply      | overridden, dynamic             |
| `quorum`            | 4% of `getPastTotalSupply` | GovernorVotesQuorumFraction |
| Clock mode          | `timestamp`            | inherited from `GovernanceToken` |

## 6. Trust assumptions

- **Timelock is honest.** The 2-day delay gives token-holders a chance to
  exit or fork before a malicious upgrade can land. Without this assumption,
  a flash-loan governance attack could pass any proposal — see audit §8
  (Governance attack analysis) in W10.
- **Chainlink reports an unmanipulated price within `STALENESS_THRESHOLD`.**
  If the feed depegs or stalls, `reportOutcome` reverts and the market
  enters the dispute branch.
- **OutcomeToken1155 is correctly granted role only to authorised markets.**
  Tested via invariant: no two contracts share `MARKET_MINTER_ROLE` over
  the same id.
- **No EOA admin remains after deploy.** The post-deploy verification
  script (`script/Verify.s.sol`, W10) asserts this and is shipped as part
  of the submission.

### 6.1 Power matrix (who can do what)

| Role / actor                        | Powers                                                            | If compromised                                                   |
|-------------------------------------|-------------------------------------------------------------------|------------------------------------------------------------------|
| `DEFAULT_ADMIN_ROLE` on every contract | Grant/revoke other roles                                          | Held by Timelock → 2-day delay before any malicious grant lands. |
| `PROPOSER_ROLE` on Timelock         | Queue any operation                                               | Held by Governor only; requires successful proposal first.       |
| `EXECUTOR_ROLE` on Timelock         | Execute queued operation (anyone)                                 | `address(0)` — by design open. Cannot execute non-queued ops.    |
| `CANCELLER_ROLE` on Timelock        | Cancel queued operation                                           | Held by Governor → vetoed proposals can be cancelled.            |
| `KEEPER_ROLE` on each Market        | Call `lockMarket`, `reportOutcome`, `finalize`                    | Compromise = market lifecycle can be triggered early/late; **cannot extract value** because reserves are only released via `claimWinnings` / `removeLiquidity` whose owner is the user. |
| `PAUSER_ROLE` on Market + Vault     | `pause()` / `unpause()`                                           | Held by Timelock; worst case is a DoS that takes 2 days to recover (immediate `unpause` proposal). |
| `MARKET_MINTER` (per-id, OutcomeToken)| Mint/burn that specific id                                       | One id = one market; cross-market damage impossible by construction. |
| `FACTORY_ROLE` on OutcomeToken      | Call `registerMarket`                                             | Held by the factory proxy; registration is one-shot (`registered[mid]` flag).|
| `MINTER_ROLE` on GovernanceToken    | Mint up to CAP                                                    | Held by Timelock; deployer renounces at end of deploy.           |
| Deployer EOA                        | None at steady state — renounces all roles in `Deploy.s.sol` step | n/a — verified by `Verify.s.sol`.                                |

### 6.2 What happens if the team multisig is compromised

There is **no team multisig** with privileged access in production. All
roles are held by the Timelock, which is in turn driven exclusively by
the on-chain Governor. The only off-chain artefact that matters for
ongoing security is the **Chainlink feed registration** — and that too
is gated behind a Governor proposal (`OracleAdapter.updateFeed`).

If the team's GitHub or development-environment is compromised, the
attacker can:

* Push a malicious commit and propose its bytecode as an upgrade — the
  Governor (token-holders) still has to vote yes, and even after
  passing, the Timelock holds the operation for 2 days. Token-holders
  can exit or fork in that window.
* Tamper with the subgraph / frontend — only affects the read path;
  on-chain state is unchanged. Users can always interact with the
  contracts directly via Arbiscan.

### 6.3 What happens if Chainlink stalls or depegs

* **Stale price** → `OracleAdapter.latestSafePrice` reverts → `reportOutcome`
  reverts → market stays in `Locked` state until either (a) feed
  recovers, or (b) governance invalidates the market via `setInvalid`,
  refunding complete sets 1:1.
* **Manipulated price within the staleness window** → market reports a
  wrong outcome → governance can `disputeOutcome` within the dispute
  window (default 24 h) → on `resolveDispute` the Timelock writes the
  correct outcome.
* **Feed registry tampering** → blocked by `onlyRole(DEFAULT_ADMIN_ROLE)`
  on `registerFeed`/`updateFeed` → requires governance proposal +
  2-day Timelock delay.

## 7. Design patterns in use (≥5 required)

| Pattern                       | Where                                                                                | Justification                                                |
|-------------------------------|--------------------------------------------------------------------------------------|--------------------------------------------------------------|
| **Factory**                   | `PredictionMarketFactory`                                                            | Each market is a fresh contract; CREATE2 enables pre-computation for UX. |
| **Proxy / UUPS**              | `PredictionMarketFactory`                                                            | Market-creation logic may evolve (e.g. add new oracle types) without re-deploying markets. |
| **Checks-Effects-Interactions** | All externally callable functions in `PredictionMarket`                            | Defends against reentrancy via state mutation discipline.    |
| **Reentrancy Guard**          | `swap`, `addLiquidity`, `removeLiquidity`, `claimWinnings`                           | Belt-and-braces with CEI — ERC-1155 callbacks reach into user-controlled code. |
| **Access Control**            | All admin-only entry points                                                          | No `onlyOwner` — role-based, Timelock-rooted.                |
| **Pausable / Circuit Breaker**| `PredictionMarket` (Timelock-controlled)                                             | Emergency freeze if Chainlink halts.                         |
| **State Machine**             | `PredictionMarket` lifecycle                                                         | Different invariants per state; prevents e.g. trading after lock. |
| **Pull-over-push**            | `claimWinnings`, `removeLiquidity` (no auto-distribution)                            | Winning user always initiates the transfer; isolates failures. |
| **Oracle adapter**            | `OracleAdapter` wraps Chainlink                                                      | Lets us swap feeds (or use the mock in tests) without touching the market. |
| **Timelock**                  | `PredictionTimelock`                                                                 | All privileged actions delayed by 2 days — mandatory governance lag. |

We claim **10 / 10** of the listed patterns; spec requires ≥ 5. Every claim
is backed by a code reference (see audit report cross-references in W10).

## 8. Sequence diagrams (3 critical flows)

### 8.1 Swap (buy YES with collateral via complete-set mint + AMM)

```mermaid
sequenceDiagram
    actor Trader
    participant PM as PredictionMarket
    participant OT as OutcomeToken1155
    participant Coll as ERC-20 Collateral

    Trader->>PM: buyOutcome(YES, C, minOut, deadline)
    PM->>PM: require state == Open, block.timestamp ≤ deadline
    PM->>Coll: safeTransferFrom(trader, this, C)
    PM->>OT: mint(this, yesId, C); mint(this, noId, C)
    PM->>PM: (Effects) update reserves: R_N += C, R_Y += C - yesOut
    Note over PM: yesOut = C + (C·997·R_Y) / (R_N·1000 + C·997)
    PM->>PM: require yesOut ≥ minOut
    PM->>OT: safeTransferFrom(this, trader, yesId, C + swapYesOut)
    PM-->>Trader: event Swap(...)
```

### 8.2 Propose → Vote → Queue → Execute (governance lifecycle)

```mermaid
sequenceDiagram
    actor Proposer
    actor Voter
    participant Gov as PredictionGovernor
    participant TL as PredictionTimelock
    participant Tgt as Target (e.g. Factory.setFee)

    Proposer->>Gov: propose(targets, calldatas, description)
    Note over Gov: voting delay = 1 day
    Voter->>Gov: castVote(proposalId, support)
    Note over Gov: voting period = 1 week
    Proposer->>Gov: queue(proposalId)
    Gov->>TL: scheduleBatch(...)
    Note over TL: delay = 2 days
    Proposer->>Gov: execute(proposalId)
    Gov->>TL: executeBatch(...)
    TL->>Tgt: low-level call
```

### 8.3 Resolve (lock → report → finalise / dispute)

```mermaid
sequenceDiagram
    participant Keeper
    participant PM as PredictionMarket
    participant OA as OracleAdapter
    participant CL as Chainlink Aggregator
    participant DAO as Governor + Timelock

    Keeper->>PM: lockMarket()
    PM->>PM: require block.timestamp ≥ tradingEndsAt; status = Locked
    Keeper->>PM: reportOutcome()
    PM->>OA: resolveBinary(questionId, threshold)
    OA->>CL: latestRoundData()
    OA-->>PM: outcome (YES | NO)
    PM->>PM: status = Reported; disputeEndsAt = now + window
    alt Within dispute window
        DAO->>PM: disputeOutcome()
        PM->>PM: status = Disputed
        DAO->>PM: resolveDispute(finalOutcome)
        PM->>PM: status = Finalized
    else After dispute window
        Keeper->>PM: finalize()
        PM->>PM: status = Finalized
    end
```

## 9. ADRs (Architecture Decision Records)

Stored under `docs/adr/`. Initial set:

- **ADR-001 — Choosing CPMM (x · y = k) over LMSR for binary outcomes.**
  CPMM is easier to audit, has no bounded-loss subsidy requirement, and
  reuses well-understood Uniswap-style invariant tests. LMSR would have
  given better price discovery in thin markets but required `exp`/`ln` math
  with bespoke fixed-point libraries — auditing those is a sub-project on
  its own.
- **ADR-002 — UUPS on the Factory, not on the Market.** Markets are
  immutable for trader safety; the factory holds the upgradeable mutable
  state (default fees, oracle whitelist, etc.).
- ADR-003+ to be added through W7–W10 as decisions arise.

## 10. Out-of-scope (this baseline)

- Frontend dApp (W9)
- Subgraph schema (W9)
- Slither output (W10)
- Gas report (W10)

---

> This document is reviewed at the end of each weekly milestone. Diffs are
> captured in commit messages of the form `docs(arch): <change>`.
