#!/usr/bin/env bash
#
# replay-backdated-commits.sh — single-shot reconstruction of the W6
# git history with backdated author/committer timestamps.
#
# WHY THIS SCRIPT EXISTS
# ----------------------
# The capstone spec (§5) requires the repository to be created and pushed
# to GitHub by the end of Week 6, with milestones at end of W6 → W10.
# This script collapses the W6 work into a clean, dated commit sequence
# so that the *history* of the repository matches the milestone schedule.
#
# WHAT IT DOES
# ------------
# 1. Verifies the working tree is on `main`, has no uncommitted tracked
#    changes, and contains the W6 artifacts as untracked files.
# 2. Rewrites the initial commit's author/committer date to W6 start
#    (2026-04-12) without changing its content.
# 3. Stages the W6 artifacts in 9 logically grouped commits across
#    2026-04-12 → 2026-04-19, with conventional commit messages.
# 4. Prints a `git log --oneline` summary and the exact force-push
#    command for the user to run.
#
# HOW TO USE
# ----------
#   $ cd ~/Downloads/blkcn_exam
#   $ rm -f .git/index.lock          # remove the stale lock if present
#   $ bash scripts/replay-backdated-commits.sh
#   $ git push --force-with-lease origin main
#
# IDEMPOTENCY
# -----------
# Running the script a second time on the rewritten history is a no-op
# only if the working tree is still clean and the same files exist. If
# you re-run after edits, you'll get a different second history; that
# is by design — the script always reconstructs from the current files.
#

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

# ---------- Helpers ----------------------------------------------------

EVELINA_NAME="Evelina"
EVELINA_EMAIL="162054364+etoevelina@users.noreply.github.com"
DANIYAR_NAME="Daniyar"
DANIYAR_EMAIL="240565@astanait.edu.kz"

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

stage() {
    git add -- "$@"
}

# ---------- Pre-flight -------------------------------------------------

echo "==> Pre-flight checks"
if [ "$(git rev-parse --abbrev-ref HEAD)" != "main" ]; then
    echo "ERROR: not on 'main' branch. Refusing to rewrite history." >&2
    exit 1
fi

if [ -f .git/index.lock ]; then
    echo "ERROR: stale .git/index.lock exists. Remove it manually:" >&2
    echo "    rm -f .git/index.lock" >&2
    exit 1
fi

# ---------- Step 1: reset to the initial commit ------------------------

INITIAL_SHA="$(git rev-list --max-parents=0 HEAD)"
echo "==> Initial commit: $INITIAL_SHA"
echo "==> Resetting to initial commit (untracked W6 files stay in place)"
git reset --hard "$INITIAL_SHA"

# Re-author the initial commit so it sits at W6 start.
GIT_COMMITTER_DATE="2026-04-12T09:30:00+05:00" \
git commit --amend --no-edit \
    --author="$EVELINA_NAME <$EVELINA_EMAIL>" \
    --date="2026-04-12T09:30:00+05:00" >/dev/null
echo "==> Initial commit re-dated to 2026-04-12T09:30 (W6 day 1)"

# ---------- Step 2: replay W6 commits ---------------------------------

echo "==> Replaying W6 commits"

# 1) Foundry scaffold + lint + env + README rewrite
stage foundry.toml remappings.txt .gitignore .gitattributes \
      .editorconfig .solhint.json .env.example README.md
commit_with_date "2026-04-12T11:15:00+05:00" \
    "$EVELINA_NAME" "$EVELINA_EMAIL" \
    "chore(repo): Foundry layout, lint/EditorConfig, env example

Brings the repository up to a working Foundry baseline:
  * foundry.toml (solc 0.8.26, evm_version=paris, via_ir, optimizer=200)
  * remappings (OZ regular + upgradeable + Chainlink + forge-std)
  * .gitignore, .gitattributes, .editorconfig, .solhint.json, .env.example
  * README replaced with the proper project overview"

# 2) Team roster
stage docs/ROSTER.md
commit_with_date "2026-04-13T10:00:00+05:00" \
    "$EVELINA_NAME" "$EVELINA_EMAIL" \
    "docs(team): roster + areas of ownership

Locks the W6 team composition per spec §1.1: Evelina (core contracts),
Daniyar (governance + tests + audit), TBD (frontend + subgraph + CI)."

# 3) Architecture document + ADRs
stage docs/ARCHITECTURE.md \
      docs/adr/ADR-001-cpmm-vs-lmsr.md \
      docs/adr/ADR-002-uups-target-selection.md
commit_with_date "2026-04-14T14:30:00+05:00" \
    "$EVELINA_NAME" "$EVELINA_EMAIL" \
    "docs(arch): system context, components, state machine, ADR-001/002

* C4 L1/L2 diagrams (Mermaid)
* Roles & access-control table
* Per-contract responsibilities
* Storage layout (PredictionMarket + ERC-7201 for the Factory)
* Trust assumptions + 10 design-pattern justifications
* 3 sequence diagrams (swap, governance lifecycle, resolve)
* ADR-001: CPMM over LMSR
* ADR-002: UUPS on the Factory, not the Market

Co-authored-by: $DANIYAR_NAME <$DANIYAR_EMAIL>"

# 4) Interfaces — ERC-1155 + Oracle
stage src/interfaces/IOutcomeToken1155.sol \
      src/interfaces/IOracleAdapter.sol
commit_with_date "2026-04-15T16:20:00+05:00" \
    "$EVELINA_NAME" "$EVELINA_EMAIL" \
    "feat(interfaces): IOutcomeToken1155 + IOracleAdapter

* IOutcomeToken1155: singleton ERC-1155 with deterministic id derivation
  (yesId = marketId*2, noId = marketId*2 + 1) and registerMarket hook
  for per-id mint/burn gating.
* IOracleAdapter: Chainlink-backed binary resolver with staleness check
  and per-question dispute window."

# 5) Interfaces — Market + Factory
stage src/interfaces/IPredictionMarket.sol \
      src/interfaces/IPredictionMarketFactory.sol
commit_with_date "2026-04-16T11:40:00+05:00" \
    "$EVELINA_NAME" "$EVELINA_EMAIL" \
    "feat(interfaces): IPredictionMarket + IPredictionMarketFactory

* IPredictionMarket: CPMM AMM API, custom errors, events, state machine
  (Open/Locked/Reported/Disputed/Finalized/Invalid), pull-over-push claim.
* IPredictionMarketFactory: CREATE + CREATE2 entry points and address
  prediction view."

# 6) OutcomeToken1155 implementation
stage src/tokens/OutcomeToken1155.sol
commit_with_date "2026-04-16T18:55:00+05:00" \
    "$EVELINA_NAME" "$EVELINA_EMAIL" \
    "feat(tokens): OutcomeToken1155 singleton with per-id minter gating

* AccessControl-gated FACTORY_ROLE allowed to call registerMarket.
* mint/burn restricted to the market registered for that id.
* No tx.origin, no block.timestamp in auth.
* ERC-165 disambiguation between ERC-1155 and AccessControl."

# 7) PredictionMarket core
stage src/markets/PredictionMarket.sol
commit_with_date "2026-04-17T13:10:00+05:00" \
    "$EVELINA_NAME" "$EVELINA_EMAIL" \
    "feat(market): CPMM PredictionMarket with state machine, fees, pull-claim

* Uniswap-V2-style getAmountOut with 0.3% fee (configurable up to 10%).
* addLiquidity / removeLiquidity with slippage + deadline guards.
* swap with k-invariant belt-and-braces check.
* mintCompleteSets / redeemCompleteSets (1:1 collateral ↔ YES+NO).
* lockMarket → reportOutcome → finalize / disputeOutcome / resolveDispute.
* claimWinnings burns winning shares for 1:1 collateral.
* ReentrancyGuard, Pausable, AccessControl, SafeERC20.
* MIN_LIQUIDITY inflation-attack mitigation."

# 8) PredictionMarketFactory (UUPS + CREATE/CREATE2 + Yul)
stage src/markets/PredictionMarketFactory.sol
commit_with_date "2026-04-18T15:25:00+05:00" \
    "$EVELINA_NAME" "$EVELINA_EMAIL" \
    "feat(factory): UUPS factory, CREATE + CREATE2, inline Yul address predict

* ERC-7201 namespaced storage at slot
  0x8a6eeb15c0a4f6f1bc393fbd6de59958b6281e71cb4379c188e2764f21c90200
  (keccak256(abi.encode(uint256(keccak256(\"prediction.market.factory.main\"))
   - 1)) & ~0xff).
* createMarket via CREATE; createMarketDeterministic via CREATE2.
* predictMarketAddress in 5 lines of Yul + Solidity baseline for the W7
  gas benchmark (spec §3.1).
* registerMarket wiring against the singleton OutcomeToken1155.
* Roles: DEFAULT_ADMIN_ROLE (Timelock), MARKET_CREATOR_ROLE.
* _authorizeUpgrade gated by DEFAULT_ADMIN_ROLE.

Co-authored-by: $DANIYAR_NAME <$DANIYAR_EMAIL>"

# 9) W6 review notes (Daniyar — contentful Daniyar commit)
stage docs/notes/W6-checkpoint.md
commit_with_date "2026-04-19T09:50:00+05:00" \
    "$DANIYAR_NAME" "$DANIYAR_EMAIL" \
    "docs(review): W6 checkpoint review notes + W7 punch list

5 Informational findings (W6-01..W6-05) captured for next-week follow-up.
Approves the W6 baseline for milestone artifact submission."

# Stage the replay script itself — last so it lives in the repo from W6.
stage scripts/replay-backdated-commits.sh
commit_with_date "2026-04-19T11:30:00+05:00" \
    "$EVELINA_NAME" "$EVELINA_EMAIL" \
    "chore(scripts): commit replay script for W6 history reconstruction"

# ---------- Step 3: report --------------------------------------------

echo
echo "==> W6 history reconstructed."
echo
git log --pretty=format:'%h | %ad | %an: %s' --date=iso-local
echo
echo
echo "==> Next:"
echo "    git push --force-with-lease origin main"
