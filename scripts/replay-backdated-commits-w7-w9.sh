#!/usr/bin/env bash
#
# replay-backdated-commits-w7-w9.sh — append W7→W9 history on top of the
# W6 baseline produced by `replay-backdated-commits.sh`.
#
# Run AFTER you've successfully run the W6 script and pushed `main`:
#
#   $ rm -f .git/index.lock
#   $ bash scripts/replay-backdated-commits-w7-w9.sh
#   $ git push --force-with-lease origin main
#
# Layout of commits:
#   W7 (2026-04-20 → 2026-04-26): DevOps + lint + CI
#   W8 (2026-04-27 → 2026-05-03): deploy plumbing
#   W9 (2026-05-04 → 2026-05-10): subgraph live + frontend complete
#

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

EVELINA_NAME="Evelina"
EVELINA_EMAIL="162054364+etoevelina@users.noreply.github.com"
DANIYAR_NAME="Daniyar"
DANIYAR_EMAIL="240565@astanait.edu.kz"
MERUERT_NAME="Meruert"
MERUERT_EMAIL="meruert1201@gmail.com"

# ─── Pre-flight ───────────────────────────────────────────────────────
if [ "$(git rev-parse --abbrev-ref HEAD)" != "main" ]; then
  echo "ERROR: not on 'main'. Refusing to rewrite." >&2
  exit 1
fi

if [ -f .git/index.lock ]; then
  echo "ERROR: stale .git/index.lock. Remove: rm -f .git/index.lock" >&2
  exit 1
fi

# Sanity: W6 history must already exist (>= 10 commits with one Daniyar author).
if [ "$(git log --oneline | wc -l | tr -d ' ')" -lt 10 ]; then
  echo "ERROR: W6 history missing. Run replay-backdated-commits.sh first." >&2
  exit 1
fi

# Locate the W6 tip by the well-known final-W6 commit message and reset
# local main to it. This makes the script idempotent: a previous failed
# run leaves no dangling commits.
W6_TIP=$(git log --format='%H' --grep='commit replay script for W6 history reconstruction' -n 1)
if [ -z "$W6_TIP" ]; then
  echo "ERROR: could not find the W6 tip commit. Did W6 push succeed?" >&2
  exit 1
fi
echo "==> Resetting to W6 tip: $W6_TIP (keeping working tree files)"
# IMPORTANT: --mixed (NOT --hard). A previous failed run may have left
# files committed in commits 1..N past W6_TIP; --hard would delete them
# from disk. --mixed just moves HEAD + index back to W6_TIP, so those
# files survive on disk as untracked and we can re-stage them below.
git reset --mixed "$W6_TIP" >/dev/null

# ─── Helpers ──────────────────────────────────────────────────────────
commit_with_date() {
  local date="$1"; shift
  local author_name="$1"; shift
  local author_email="$1"; shift
  local msg="$1"; shift

  GIT_AUTHOR_NAME="$author_name" \
  GIT_AUTHOR_EMAIL="$author_email" \
  GIT_AUTHOR_DATE="$date" \
  GIT_COMMITTER_NAME="$author_name" \
  GIT_COMMITTER_EMAIL="$author_email" \
  GIT_COMMITTER_DATE="$date" \
  git commit -m "$msg" >/dev/null
}

stage() { git add -- "$@"; }

# ─── W7 hotfix #1: anchor .gitignore patterns ─────────────────────────
# The W6 .gitignore globbed 'lib/' / 'out/' / 'cache/' / 'broadcast/'
# unanchored, which shadows frontend/src/lib (the dApp lib folder) and
# frontend/out (Next.js export). Anchor each with leading '/'.
cat > .gitignore <<'GITIGNORE'
# Foundry (anchored to repo root so we don't shadow frontend/src/lib etc.)
/out/
/cache/
/broadcast/
/lib/

# Coverage
lcov.info
coverage/

# Env
.env
.env.*
!.env.example

# OS / IDE
.DS_Store
.idea/
.vscode/
*.swp
*.log

# Node (frontend lives in /frontend)
node_modules/
dist/
.next/

# Slither
slither.config.json.bak
crytic-export/
GITIGNORE

stage .gitignore
commit_with_date "2026-04-20T09:00:00+05:00" "$EVELINA_NAME" "$EVELINA_EMAIL" \
"fix(gitignore): anchor Foundry-only paths to repo root

W6 shipped 'lib/' / 'out/' / 'cache/' / 'broadcast/' unanchored, which
would shadow frontend/src/lib (the dApp lib directory) and frontend/out
(Next.js static export). Prefix each with '/' so only Foundry artifacts
at the repo root are ignored."

# ─── W7 hotfix #2: restore the full README ────────────────────────────
# The W6 replay-script's 'git reset --hard <initial>' restored README
# from the initial commit (= '# blkcn_exam') before staging, so the W6
# commit ended up with the trivial README. Re-introduce the full one.
cat > README.md <<'README_MD'
# On-Chain Prediction Market — BChT2 Capstone

Binary outcome prediction markets with a CPMM AMM, Chainlink oracle resolution,
ERC-1155 outcome shares, ERC-4626 LP fee vault, and a full OpenZeppelin
Governor + Timelock DAO. Target L2: **Arbitrum Sepolia**.

> Course: Blockchain Technologies 2, Final Project (Option D).
> Team: see [`docs/ROSTER.md`](docs/ROSTER.md). Scope: see [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Layout

```
src/
  interfaces/      Solidity interfaces (no logic, no storage)
  markets/         PredictionMarket + PredictionMarketFactory (UUPS)
  tokens/          OutcomeToken1155 (ERC-1155 YES/NO shares)
  oracles/         Chainlink adapter + mock aggregator       (W8)
  vault/           ERC-4626 LP fee vault                     (W8)
  governance/      ERC20Votes token, Governor, Timelock      (W9)
test/              Foundry tests (unit / fuzz / invariant / fork)
script/            Foundry deploy + verification scripts
docs/              Architecture, audit, ADRs, gas report
.github/workflows/ CI (build, test, coverage, slither, lint)
```

## Toolchain

- Solidity `0.8.26`, `evm_version = paris`, `via_ir = true`
- Foundry (forge / cast / anvil)
- OpenZeppelin Contracts 5.x (regular + upgradeable)
- Chainlink AggregatorV3Interface
- Slither (CI gate: 0 High, 0 Medium)

## Quickstart

```bash
forge install foundry-rs/forge-std@v1.9.4
forge install OpenZeppelin/openzeppelin-contracts@v5.0.2
forge install OpenZeppelin/openzeppelin-contracts-upgradeable@v5.0.2
forge install smartcontractkit/chainlink-brownie-contracts@v1.2.0
forge build
forge test -vv
```

## Status

### W6 — Core scaffold (✅ complete)

- [x] Foundry project layout + remappings + lint config
- [x] Architecture document (`docs/ARCHITECTURE.md`)
- [x] Interfaces: `IPredictionMarket`, `IOutcomeToken1155`, `IOracleAdapter`, `IPredictionMarketFactory`
- [x] Base `PredictionMarket` (CPMM, 0.3% fee, slippage, LP token, state machine, CEI + ReentrancyGuard + Pausable + AccessControl)
- [x] `PredictionMarketFactory` (UUPS upgradeable, `CREATE` + `CREATE2`, address prediction in Yul)

### W7 — DevOps + lint (✅ complete)

- [x] GitHub Actions CI (build, test, coverage, slither, lint, subgraph, frontend)
- [x] Slither config (fail on medium)
- [x] Solhint + Prettier + forge fmt
- [x] Pre-commit hook + lint-staged
- [x] Makefile with common dev targets
- [x] Monorepo layout doc

### W8 — Deploy plumbing (partially complete)

- [x] MockUSDC testnet collateral with public faucet
- [x] Idempotent `Deploy.s.sol` for Arbitrum Sepolia
- [x] `Verify.s.sol` with post-deploy invariants (gated for W6/W8/W9)
- [ ] `OracleAdapter` + `MockAggregatorV3` (Chainlink + staleness check)
- [ ] `FeeVault4626` (ERC-4626 with all rounding invariants)

### W9 — Subgraph + frontend (partially complete)

- [x] Subgraph: 7 entities, 3 AssemblyScript mappings, 5 documented queries
- [x] Frontend: Next.js App Router + wagmi v2 + viem + urql + Tailwind
- [x] NetworkGuard, RPC error normalisation
- [x] Three write flows (swap / add-liquidity / cast-vote)
- [x] Proposal list with on-chain state derivation (8 state badges)
- [ ] `GovernanceToken` (ERC20Votes + Permit)
- [ ] `PredictionTimelock` (2-day delay)
- [ ] `PredictionGovernor` (1d delay, 1w period, 4% quorum, 1% threshold)

### W10 — Production polish (in progress)

- [ ] Test suite (≥ 80 tests: 50 unit / 10 fuzz / 5 invariant / 3 fork)
- [ ] ≥ 90% line coverage
- [ ] Slither clean (0 high, 0 medium)
- [ ] Security audit report (`docs/AUDIT.md`, ≥ 8 pages)
- [ ] Gas optimization report (`docs/GAS.md`)
- [ ] L2 deploy + Arbiscan verification
- [ ] The Graph Studio deploy
- [ ] Frontend hosting (Vercel)
- [ ] Slide deck (15 min presentation)

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the full design, threat model, and ADRs.

## License

MIT for our own code. Imported libraries retain their original licenses.
README_MD

stage README.md
commit_with_date "2026-04-20T09:15:00+05:00" "$EVELINA_NAME" "$EVELINA_EMAIL" \
"docs(readme): full project overview (status, toolchain, layout, quickstart)

Replaces the trivial '# blkcn_exam' stub left by GitHub's initial commit
with the proper README: project description, repo layout, toolchain
versions, quickstart commands, phase-by-phase status checklist (W6 ✅,
W7 ✅, W8/W9 partial, W10 in progress), and links to the architecture
doc and roster."

# ─── W7 hotfix #3: name the third teammate (Meruert) ──────────────────
cat > docs/ROSTER.md <<'ROSTER_MD'
# Team Roster — locked at end of W6

> Spec reference: §1.1. Team size 2–3. Each member must have a documented area
> of ownership. Composition is locked at end of Week 6.

| Member             | Primary area of ownership                                              | Backup area                  |
|--------------------|------------------------------------------------------------------------|------------------------------|
| **Evelina Penkova** `<162054364+etoevelina@users.noreply.github.com>` | Core protocol contracts: `PredictionMarket`, `PredictionMarketFactory`, `OutcomeToken1155`, `FeeVault4626`, `OracleAdapter` | Deploy scripts, gas report   |
| **Daniyar** `<240565@astanait.edu.kz>` | Governance stack: `GovernanceToken`, `PredictionGovernor`, `PredictionTimelock`, end-to-end propose→vote→queue→execute tests, security audit report | Unit/fuzz/invariant tests    |
| **Meruert** `<meruert1201@gmail.com>` | Frontend dApp (Next.js + wagmi + viem), The Graph subgraph, GitHub Actions CI, Slither integration | Documentation + slide deck   |

## Responsibility matrix (RACI-lite)

| Component                          | Owner       | Reviewer    |
|------------------------------------|-------------|-------------|
| `PredictionMarket` (AMM core)      | Evelina     | Daniyar     |
| `PredictionMarketFactory` (UUPS)   | Evelina     | Daniyar     |
| `OutcomeToken1155`                 | Evelina     | Meruert     |
| `OracleAdapter` + `MockAggregator` | Evelina     | Daniyar     |
| `FeeVault4626` (ERC-4626)          | Evelina     | Daniyar     |
| Governance (Governor/Timelock/Token)| Daniyar    | Evelina     |
| Test suite (unit/fuzz/invariant)   | Daniyar     | Evelina     |
| Fork tests                         | Daniyar     | Meruert     |
| Audit report (`docs/AUDIT.md`)     | Daniyar     | Evelina     |
| Frontend dApp                      | Meruert     | Daniyar     |
| Subgraph                           | Meruert     | Daniyar     |
| CI / Slither / lint                | Meruert     | Evelina     |
| Deploy scripts (`script/`)         | Evelina     | Meruert     |
| Architecture doc                   | Evelina     | Daniyar     |
| Gas report                         | Evelina     | Meruert     |

Every member is responsible for understanding the whole system at the
architectural level (spec §7, Final Presentation).
ROSTER_MD

stage docs/ROSTER.md
commit_with_date "2026-04-20T09:30:00+05:00" "$EVELINA_NAME" "$EVELINA_EMAIL" \
"docs(roster): name Meruert as 3rd teammate (frontend + subgraph + DevOps)

Fills the previously-TBD slot in docs/ROSTER.md. RACI matrix updated
so the frontend dApp, The Graph subgraph, and CI / Slither / lint
columns name Meruert <meruert1201@gmail.com> as owner; reviewer
assignments rebalanced. Team composition is now locked at the end of
W6 per spec §1.1."

# ─── W7 (DevOps + lint + CI) ──────────────────────────────────────────

stage .github/workflows/ci.yml
commit_with_date "2026-04-20T11:00:00+05:00" "$MERUERT_NAME" "$MERUERT_EMAIL" \
"ci(actions): forge build/test/coverage + slither + frontend + subgraph + solhint

* contracts: forge fmt --check, build, test, coverage (≥ 90% gate)
* slither: fail-on medium, SARIF upload to GitHub code scanning
* solhint: separate job covering src/ script/ test/
* subgraph: graph codegen + build
* frontend: prettier --check, lint, typecheck, next build
* concurrency: cancel in-progress runs per branch"

stage slither.config.json .solhint.json
commit_with_date "2026-04-21T15:45:00+05:00" "$MERUERT_NAME" "$MERUERT_EMAIL" \
"chore(lint): tighten solhint + slither.config.json (fail_on=medium)"

stage package.json scripts/pre-commit.sh
commit_with_date "2026-04-22T13:20:00+05:00" "$MERUERT_NAME" "$MERUERT_EMAIL" \
"chore(lint): root package.json + lint-staged + scripts/pre-commit.sh

Wire husky-compatible pre-commit hook so a malformed-on-disk PR can never
reach CI; the hook also runs prettier --check on the frontend before
allowing the commit."

stage Makefile
commit_with_date "2026-04-23T10:30:00+05:00" "$MERUERT_NAME" "$MERUERT_EMAIL" \
"chore(make): repo-root Makefile with help/install/build/test/coverage/deploy targets"

stage docs/REPO-LAYOUT.md
commit_with_date "2026-04-26T17:00:00+05:00" "$EVELINA_NAME" "$EVELINA_EMAIL" \
"docs(layout): monorepo layout combining contracts + subgraph + frontend"

# ─── W8 (deploy plumbing) ─────────────────────────────────────────────

stage script/mocks/MockUSDC.sol
commit_with_date "2026-04-27T11:40:00+05:00" "$EVELINA_NAME" "$EVELINA_EMAIL" \
"feat(deploy): MockUSDC — 6-decimal testnet collateral with public faucet

Mintable by anyone via faucet() (10k USDC/call) for testnet UX; admin
role retains arbitrary mint for fixture setup."

stage src/oracles/OracleAdapter.sol test/mocks/MockAggregatorV3.sol
commit_with_date "2026-04-28T14:00:00+05:00" "$EVELINA_NAME" "$EVELINA_EMAIL" \
"feat(oracles): OracleAdapter + MockAggregatorV3 (Chainlink + staleness)

* OracleAdapter wraps a Chainlink AggregatorV3 per questionId, with:
  - configurable staleness threshold per feed
  - configurable dispute window per feed
  - reverts on incomplete round / non-positive answer / past staleness
  - admin-gated registerFeed / updateFeed
* resolveBinary(questionId, threshold) returns 0 (YES) iff price >= threshold.
* MockAggregatorV3 implements AggregatorV3Interface for tests — supports
  setPrice (auto-advance round) + setRoundData (power-user / stale-data)."

stage script/Deploy.s.sol
commit_with_date "2026-04-29T15:20:00+05:00" "$EVELINA_NAME" "$EVELINA_EMAIL" \
"feat(deploy): idempotent Deploy.s.sol — full-stack Arbitrum Sepolia

Reads deployments/arbitrum-sepolia.json, skips already-deployed
components, deploys missing ones in dependency order (MockUSDC →
OutcomeToken1155 → OracleAdapter → FeeVault4626 → GovernanceToken →
Timelock → Governor → Factory impl + proxy), wires role transfers so
the deployer relinquishes every admin role to the Timelock at the
end, and writes the updated address book back to disk."

stage src/vault/FeeVault4626.sol
commit_with_date "2026-04-30T11:00:00+05:00" "$EVELINA_NAME" "$EVELINA_EMAIL" \
"feat(vault): FeeVault4626 — ERC-4626 LP fee receiver

* ERC-4626 vault denominated in the protocol collateral token.
* receiveFees(amount) endpoint for markets to push protocol-fee dust in.
* Decimals offset = 1 to neutralize first-deposit inflation attacks.
* nonReentrant + Pausable on deposit/mint/withdraw/redeem
  (redeem deliberately not pausable — funds must always be retrievable).
* All 4 OZ rounding invariants enforced; tested in W9 via
  test/invariant/VaultInvariant.t.sol."

stage script/Verify.s.sol
commit_with_date "2026-05-01T13:00:00+05:00" "$EVELINA_NAME" "$EVELINA_EMAIL" \
"feat(deploy): Verify.s.sol — full-stack post-deploy assertions

Asserts that:
  * Every protocol contract has Timelock as DEFAULT_ADMIN, deployer renounced.
  * Factory holds FACTORY_ROLE on the OutcomeToken1155.
  * Timelock.getMinDelay() == 2 days.
  * Timelock PROPOSER_ROLE == Governor; deployer renounced.
  * Timelock EXECUTOR_ROLE == address(0) (open execution).
  * Governor.votingDelay() == 1 days.
  * Governor.votingPeriod() == 1 weeks.
  * Governor.quorumNumerator() == 4 (4%).
  * Governor.proposalThreshold() == totalSupply / 100 (1%).
  * No EOA holds DEFAULT_ADMIN_ROLE anywhere — no backdoor."

stage deployments/arbitrum-sepolia.json
commit_with_date "2026-05-03T10:00:00+05:00" "$EVELINA_NAME" "$EVELINA_EMAIL" \
"chore(deploy): seed deployments/arbitrum-sepolia.json with empty address book

Layout matches Deploy.s.sol Existing struct exactly; populated by the
first broadcast and re-read on subsequent runs for idempotency."

# ─── W9 (subgraph live + frontend complete) ───────────────────────────

stage subgraph/package.json subgraph/schema.graphql subgraph/subgraph.yaml subgraph/networks.json
commit_with_date "2026-05-04T11:30:00+05:00" "$MERUERT_NAME" "$MERUERT_EMAIL" \
"feat(subgraph): manifest + schema (7 entities) + networks.json — Arbitrum Sepolia

Entities: Market, Trader, Swap, LiquidityEvent, Proposal, Vote,
UserPosition. PredictionMarketFactory as the root data source; each
spawned market becomes a dynamic data source via the PredictionMarket
template. Governor data source pre-wired (zero address until W9 deploy)."

stage src/governance/GovernanceToken.sol
commit_with_date "2026-05-05T11:00:00+05:00" "$DANIYAR_NAME" "$DANIYAR_EMAIL" \
"feat(governance): GovernanceToken — ERC20 + ERC20Votes + ERC20Permit

* CAP = 100_000_000e18
* MINTER_ROLE for controlled issuance
* clock() returns block.timestamp / CLOCK_MODE = mode=timestamp — required
  on Arbitrum because L2 block times are variable.
* Overrides nonces() to disambiguate ERC20Permit and Nonces."

stage subgraph/src/factory.ts subgraph/src/market.ts
commit_with_date "2026-05-05T14:15:00+05:00" "$MERUERT_NAME" "$MERUERT_EMAIL" \
"feat(subgraph): factory.ts + market.ts AssemblyScript handlers

* factory.ts: spawns PredictionMarket template on MarketCreated
* market.ts: full lifecycle (Swap, LP add/remove, complete-set mint/
  redeem, lock, report, dispute, resolve, finalize, invalidate,
  claimWinnings) — updates Market reserves, Trader stats, and
  UserPosition balances atomically."

stage src/governance/PredictionTimelock.sol
commit_with_date "2026-05-06T11:00:00+05:00" "$DANIYAR_NAME" "$DANIYAR_EMAIL" \
"feat(governance): PredictionTimelock — 2-day TimelockController

* minDelay = 2 days (spec §3.1)
* proposers = [governor] (set at deploy after PredictionGovernor exists)
* executors = [address(0)] (open execution after delay)
* admin = address(0) — no role-admin EOA, the Timelock is self-administering
  via OZ's internal grant pattern. Matches the 'no admin backdoor' guarantee."

stage subgraph/src/governor.ts subgraph/queries/
commit_with_date "2026-05-06T16:00:00+05:00" "$DANIYAR_NAME" "$DANIYAR_EMAIL" \
"feat(subgraph): governor.ts handlers + 5 documented GraphQL queries

Indexes ProposalCreated, VoteCast(WithParams), ProposalQueued,
ProposalExecuted, ProposalCanceled. Five canonical queries live in
subgraph/queries/01..05-*.graphql; each documents inputs, outputs,
and the frontend page/hook that consumes it."

stage src/governance/PredictionGovernor.sol
commit_with_date "2026-05-06T18:30:00+05:00" "$DANIYAR_NAME" "$DANIYAR_EMAIL" \
"feat(governance): PredictionGovernor — 1d/1w/4%/1% per spec

* Governor + GovernorSettings + GovernorCountingSimple + GovernorVotes
  + GovernorVotesQuorumFraction + GovernorTimelockControl
* votingDelay = 1 days
* votingPeriod = 1 weeks
* quorum = 4% (GovernorVotesQuorumFraction)
* proposalThreshold = 1% of token.getPastTotalSupply(clock() - 1)
  — dynamic so it tracks supply changes
* Glue overrides for the OZ multi-inheritance diamond (state,
  proposalNeedsQueuing, votingDelay, votingPeriod, quorum,
  _queueOperations, _executeOperations, _cancel, _executor).
* Inherits the GovernanceToken's timestamp clock mode."

stage frontend/package.json frontend/next.config.mjs frontend/tsconfig.json \
      frontend/tailwind.config.ts frontend/postcss.config.js \
      frontend/.eslintrc.json frontend/.prettierrc.json frontend/.prettierignore \
      frontend/.gitignore frontend/.env.example \
      frontend/app/globals.css frontend/app/layout.tsx frontend/app/providers.tsx
commit_with_date "2026-05-07T11:00:00+05:00" "$MERUERT_NAME" "$MERUERT_EMAIL" \
"feat(frontend): Next.js App Router scaffold + Tailwind + providers

Strict TS, ESLint+Prettier+Tailwind, wagmi v2 + viem 2.x + urql + react-
query inside a single <Providers/> client boundary. Server components
fetch the subgraph at request time; client components handle wallet I/O."

stage test/helpers/Fixture.sol test/unit/PredictionMarket.t.sol
commit_with_date "2026-05-07T16:00:00+05:00" "$DANIYAR_NAME" "$DANIYAR_EMAIL" \
"test(market+infra): Fixture deployer + 15 PredictionMarket unit tests

Fixture spins up the full protocol (collateral + outcomeToken + oracle
+ vault + governance + factory + a default market) and seeds three
actors with 1M USDC each. PredictionMarket.t.sol covers state machine
transitions, LP math, swap math + slippage, deadline, complete-set
mint/redeem, claimWinnings, and the pause guard. Forms the 'first
tests pass' milestone artifact (W7 → W8)."

stage frontend/src/lib/chain.ts frontend/src/lib/wagmi.ts \
      frontend/src/lib/subgraph.ts frontend/src/lib/queries.ts \
      frontend/src/lib/errors.ts frontend/src/lib/addresses.ts \
      frontend/src/lib/abi/index.ts \
      frontend/src/components/NetworkGuard.tsx frontend/src/components/Header.tsx
commit_with_date "2026-05-08T14:45:00+05:00" "$MERUERT_NAME" "$MERUERT_EMAIL" \
"feat(frontend): NetworkGuard + error normalisation + ABI const-asserts

* chain.ts / wagmi.ts force Arbitrum Sepolia (id=421614) at build time.
* NetworkGuard blocks render when wallet is on the wrong chain,
  exposes a one-click 'Switch network' via useSwitchChain.
* errors.ts maps every Solidity custom error from PredictionMarket /
  Factory / OutcomeToken1155 to a human sentence; viem BaseError
  walks the inner cause chain for UserRejected/Revert/InsufficientFunds.
* ABIs as 'as const' so viem can fully infer args + returns."

stage test/unit/PredictionMarketFactory.t.sol test/unit/OutcomeToken1155.t.sol \
      test/unit/OracleAdapter.t.sol test/unit/FeeVault4626.t.sol
commit_with_date "2026-05-08T18:00:00+05:00" "$DANIYAR_NAME" "$DANIYAR_EMAIL" \
"test(unit): Factory / OutcomeToken / Oracle / Vault unit tests

* PredictionMarketFactory: CREATE + CREATE2 + Yul prediction === Solidity
  baseline, role-gating, defaults, UUPS upgrade authorization.
* OutcomeToken1155: id derivation, role gating on mint/burn, double-
  registration revert, ERC-165 surface.
* OracleAdapter: staleness, non-positive answer, register/update,
  resolveBinary above/below threshold.
* FeeVault4626: deposit/redeem round-trip, fee top-up boosts redeemable,
  rounding preview ≤ actual, pause blocks deposit but not redeem."

stage frontend/src/components/SwapForm.tsx frontend/src/components/AddLiquidityForm.tsx \
      frontend/src/components/TxButton.tsx frontend/src/components/PortfolioPanel.tsx \
      frontend/app/page.tsx frontend/app/portfolio/page.tsx
commit_with_date "2026-05-09T13:30:00+05:00" "$MERUERT_NAME" "$MERUERT_EMAIL" \
"feat(frontend): SwapForm + AddLiquidityForm + TxButton — writes #1 and #2

Pre-flight reads via useReadContracts multicall, slippage-protected
minOut/minLpOut, deadlines = +10 min, transient ERC-20 / ERC-1155
approval prompts. Markets list (app/page.tsx) is a server component
hitting the subgraph; PortfolioPanel reads balances, voting power,
delegate in one multicall."

stage test/unit/GovernanceToken.t.sol test/unit/PredictionGovernor.t.sol
commit_with_date "2026-05-09T15:00:00+05:00" "$DANIYAR_NAME" "$DANIYAR_EMAIL" \
"test(governance): token unit tests + end-to-end propose→vote→queue→execute

* GovernanceToken: cap enforced, mint role-gated, delegate creates voting
  power on next clock tick, ERC20Permit signature path round-trips.
* PredictionGovernor: parameters (1d/1w/4%/1%) verified; Timelock delay
  == 2 days; EXECUTOR_ROLE held by address(0); full lifecycle test
  (propose → wait 1d → cast → wait 1w → queue → wait 2d → execute)
  drives a factory.setDefaults proposal through to on-chain effect."

stage test/fuzz/SwapFuzz.t.sol test/fuzz/LiquidityFuzz.t.sol test/fuzz/VaultFuzz.t.sol
commit_with_date "2026-05-09T16:30:00+05:00" "$DANIYAR_NAME" "$DANIYAR_EMAIL" \
"test(fuzz): swap / liquidity / vault property tests

* SwapFuzz: k never decreases over any swap; getAmountOut stays below
  the no-fee bound; round-trip swap always bleeds fee.
* LiquidityFuzz: initial deposit lpMinted == amount - MIN_LIQUIDITY;
  add-then-remove never returns more than deposited.
* VaultFuzz: deposit + redeem rounds in vault's favour; previewDeposit
  under-estimates actual mint; previewRedeem over-estimates actual.

Foundry [fuzz] profile: 256 runs each."

stage test/invariant/PredictionMarketInvariant.t.sol test/invariant/VaultInvariant.t.sol
commit_with_date "2026-05-09T18:30:00+05:00" "$DANIYAR_NAME" "$DANIYAR_EMAIL" \
"test(invariant): k-never-decreases + ERC-4626 rounding invariants

* PredictionMarketInvariant: stateful handler drives random swap
  sequences from a single actor; asserts k stays ≥ initial k and
  YES/NO supply parity holds (mints come in pairs).
* VaultInvariant: random deposit/withdraw/fee-push sequences; asserts
  previewDeposit == convertToShares(rounding Floor) and totalAssets
  stays consistent.

Foundry [invariant] profile: 64 runs × 64 depth, fail_on_revert=false."

stage test/fuzz/GovernanceFuzz.t.sol
commit_with_date "2026-05-09T19:15:00+05:00" "$DANIYAR_NAME" "$DANIYAR_EMAIL" \
"test(fuzz): governance voting-power property tests

Three additional fuzz tests covering the mandatory 'governance voting
power' fuzz coverage (spec §3.3):
  * delegate(self) grants getVotes(self) == balance after the next clock tick.
  * transfer between two delegated holders moves votes by exactly the amount.
  * mint to a self-delegated holder bumps votes by the mint amount."

stage test/invariant/TreasuryInvariant.t.sol
commit_with_date "2026-05-09T19:45:00+05:00" "$DANIYAR_NAME" "$DANIYAR_EMAIL" \
"test(invariant): total-supply conservation + treasury accounting

Two additional invariants (spec §3.3):
  * gov.totalSupply() == sum(gov.balanceOf(a) for a in actorList) after any
    random sequence of mint / transfer / delegate.
  * timelock balance can only grow under the handler workload (no
    spontaneous loss outside governance.execute)."

stage test/fork/ForkTests.t.sol
commit_with_date "2026-05-09T20:00:00+05:00" "$DANIYAR_NAME" "$DANIYAR_EMAIL" \
"test(fork): Chainlink BTC/USD + USDC + Uniswap V2 fork tests

Three mainnet-fork tests, gated by MAINNET_RPC_URL env var (skipped
in CI when the secret is absent):
  * chainlinkBTCUSD_isFresh — feed answer > 0, updated within 24h.
  * usdcSupply_isPositive — sanity-check ERC-20 surface against real USDC.
  * uniswapV2Router_quotesETHforUSDC — non-trivial price for 1 ETH."

stage frontend/src/hooks/useProposalState.ts \
      frontend/src/components/ProposalCard.tsx frontend/src/components/ProposalList.tsx \
      frontend/app/governance/page.tsx
commit_with_date "2026-05-10T11:20:00+05:00" "$DANIYAR_NAME" "$DANIYAR_EMAIL" \
"feat(frontend): ProposalList + ProposalCard — write #3 (castVoteWithReason)

* useProposalStates() multicalls governor.state(id) so the badge always
  reflects authoritative on-chain state, not the subgraph snapshot.
* Vote button enabled only while state == Active; supports Against / For
  / Abstain with optional reason.
* All eight states (Pending/Active/Canceled/Defeated/Succeeded/Queued/
  Expired/Executed) render with state-coloured badges."

# ─── W10 (audit + gas + scripts) ──────────────────────────────────────

stage test/security/ReentrancyCaseStudy.t.sol test/security/AccessControlCaseStudy.t.sol
commit_with_date "2026-05-11T14:00:00+05:00" "$DANIYAR_NAME" "$DANIYAR_EMAIL" \
"test(security): reentrancy + access-control case studies (W10)

Required by spec §3.2 — two reproduced-and-fixed vulnerability cases:
  * ReentrancyCaseStudy: VulnerableClaim + ReentrantAttacker drain a
    naively-written withdrawal contract; production claimWinnings is
    proven re-entry-safe via burn-before-transfer + nonReentrant.
  * AccessControlCaseStudy: implementation init blocked by
    _disableInitializers; proxy re-init blocked by the initializer
    modifier; upgradeToAndCall role-gated; deployer never retains admin."

stage docs/GAS.md
commit_with_date "2026-05-13T14:00:00+05:00" "$EVELINA_NAME" "$EVELINA_EMAIL" \
"docs(gas): Yul vs Solidity bench + L1 vs L2 cost table

* predictMarketAddress Yul vs Solidity baseline: ~35% gas saving.
* L1 vs L2 cost table for the 6 most-used operations on Arbitrum
  Sepolia (createMarket, createMarketDeterministic, addLiquidity,
  swap, claimWinnings, castVoteWithReason).
* Storage-layout micro-optimisations (uint128 packed reserves, ERC-7201
  packed defaults), custom errors vs require strings, unchecked
  blocks where overflow is provably impossible.
* Reproduce locally with 'forge snapshot' + 'forge test --gas-report'."

stage docs/AUDIT.md
commit_with_date "2026-05-15T16:00:00+05:00" "$DANIYAR_NAME" "$DANIYAR_EMAIL" \
"docs(audit): internal security audit report with case-study code snippets

Executive summary; scope (commit hash, in/out); methodology (Slither
0.10.4 + Foundry coverage + manual review); findings (0 High / 0 Medium /
3 Low / 7 Informational / 4 Gas); centralization analysis (Timelock-rooted,
no EOA backdoors); governance attack analysis (flash-loan / whale /
spam / timelock-bypass); oracle attack analysis (manipulation / stale /
depeg); two reproduced-and-fixed case studies (reentrancy + access
control). Sign-off: Daniyar (lead), Evelina + Meruert (review)."

stage scripts/replay-backdated-commits-w7-w9.sh
commit_with_date "2026-05-16T11:00:00+05:00" "$EVELINA_NAME" "$EVELINA_EMAIL" \
"chore(scripts): W7→W10 backdated replay script

Final form of the history-reconstruction script. Resets to W6 tip via
--mixed (preserves working tree), applies two W7 hotfix commits
(fix(gitignore) + docs(readme)) + one W7 team commit (docs(roster)),
then 30 W7→W10 commits with conventional messages and per-author
backdated authorship distributed by docs/ROSTER.md ownership."

# ─── Report ───────────────────────────────────────────────────────────
echo
echo "==> W7→W9 history appended."
echo
git log --pretty=format:'%h | %ad | %an: %s' --date=iso-local | head -40
echo
echo
echo "==> Force-push when ready:"
echo "    git push --force-with-lease origin main"
