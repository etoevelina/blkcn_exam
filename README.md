# On-Chain Prediction Market — BChT2 Capstone

Binary-outcome prediction markets with a CPMM AMM, Chainlink oracle resolution,
ERC-1155 outcome shares, ERC-4626 LP fee vault, and a full OpenZeppelin
Governor + Timelock DAO. Target L2: **Arbitrum Sepolia**.

> Course: Blockchain Technologies 2, Final Project (Option D).
> Team: see [`docs/ROSTER.md`](docs/ROSTER.md). Architecture: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md). Audit: [`docs/AUDIT.md`](docs/AUDIT.md). Gas: [`docs/GAS.md`](docs/GAS.md). Final deliverables: [`docs/FinalReport.pdf`](docs/FinalReport.pdf), [`docs/Slides.pdf`](docs/Slides.pdf).

## What it does

Anyone can create a binary YES/NO market on a real-world question, seed it with
USDC liquidity, trade outcome shares against a 0.3 %-fee CPMM, and — after the
question resolves via a Chainlink price feed — redeem winning shares 1-to-1 for
collateral. LPs earn fees through an ERC-4626 vault. All protocol parameters
(fee, dispute window, supported collateral, contract upgrades) are controlled
by a Governor + 2-day Timelock DAO with an ERC20Votes governance token.

## Architecture at a glance

```
                                                     ┌─────────────────────┐
              ┌────────────────────────────┐         │   Governor          │
              │ PredictionMarketFactory    │◀── upg ─│   (1d / 1w / 4% / 1%)│
              │  (UUPS, CREATE + CREATE2)  │         └──────────┬──────────┘
              └─────────────┬──────────────┘                    │ queue
                            │ deploys                           ▼
                            ▼                          ┌─────────────────┐
              ┌────────────────────────────┐           │ Timelock (2 day)│
              │ PredictionMarket           │── admin ──┴────────┬────────┘
              │  (CPMM, 0.3% fee, CEI)     │                    │ execute
              └─┬─────────────┬────────┬───┘                    │
                │ mints       │ reads  │ payouts                │
                ▼             ▼        ▼                        │
        ┌──────────────┐ ┌──────────┐ ┌──────────────┐          │
        │OutcomeToken  │ │ Oracle   │ │ FeeVault4626 │◀─────────┘
        │ 1155 (YES/NO)│ │ Adapter  │ │ (LP yield)   │
        └──────────────┘ └──────────┘ └──────────────┘
                              │
                              ▼
                         Chainlink
                       (stale-price + dispute window)
```

A full C4 + threat model + ADR set lives in [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Repository layout

```
src/
  interfaces/      Solidity interfaces (no storage, no logic)
  markets/         PredictionMarket + PredictionMarketFactory (UUPS)
  tokens/          OutcomeToken1155 (singleton ERC-1155 for YES/NO)
  oracles/         Chainlink OracleAdapter + MockAggregatorV3
  vault/           FeeVault4626 (ERC-4626 LP fee vault)
  governance/      GovernanceToken, PredictionTimelock, PredictionGovernor
test/
  unit/            50 unit tests
  fuzz/            11 fuzz tests
  invariant/        6 invariant tests
  fork/             3 fork tests (Arbitrum Sepolia)
  gas/             Yul vs Solidity benchmarks
  security/        Reentrancy + access-control case studies
script/            Deploy.s.sol + Verify.s.sol
subgraph/          The Graph: 7 entities, 3 mappings, 5 documented queries
frontend/          Next.js 14 (App Router) + wagmi v2 + viem + urql
docs/              Architecture, audit, ADRs, gas report, final PDF + slides
.github/workflows/ CI (build / test / coverage / slither / lint / subgraph / frontend)
```

## Toolchain

- Solidity `0.8.26`, `evm_version = cancun`, `via_ir = true`
- Foundry (`forge` / `cast` / `anvil`)
- OpenZeppelin Contracts 5.0.2 + Upgradeable 5.0.2
- Chainlink `AggregatorV3Interface` (brownie-contracts v1.2.0)
- Slither — CI gate: **0 High, 0 Medium**
- Next.js 14 (App Router) + Tailwind, wagmi v2 + viem, urql
- The Graph (hosted on The Graph Studio)

## Quickstart

```bash
# Contracts
forge install
forge build
forge test -vv
forge coverage --ir-minimum   # ≥ 90 % line coverage

# Subgraph
cd subgraph && yarn && yarn codegen && yarn build

# Frontend
cd frontend && pnpm install && pnpm dev
```

## Deliverables

| Track            | Artefact                                                                 |
|------------------|--------------------------------------------------------------------------|
| Architecture     | [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — 560+ lines, C4 + threat model + 7 ADRs |
| Security audit   | [`docs/AUDIT.md`](docs/AUDIT.md) — 10+ pages, 2 case studies, Slither findings table |
| Gas report       | [`docs/GAS.md`](docs/GAS.md) — Yul vs Solidity (~35 % savings), L1 vs L2 table |
| Tests            | 70 tests total — 50 unit / 11 fuzz / 6 invariant / 3 fork, **≥ 90 % coverage** |
| Static analysis  | [`docs/audit/slither-report.json`](docs/audit/slither-report.json) — 0 High, 0 Medium |
| Deploy           | `script/Deploy.s.sol` + `script/Verify.s.sol`, deployed on Arbitrum Sepolia |
| Subgraph         | `subgraph/` — 7 entities, deployed on The Graph Studio                   |
| Frontend         | `frontend/` — Next.js App Router, hosted on Vercel                       |
| Final report     | [`docs/FinalReport.pdf`](docs/FinalReport.pdf)                           |
| Presentation     | [`docs/Slides.pdf`](docs/Slides.pdf)                                     |

## Status — all weeks complete

| Week  | Scope                                                                              | Status |
|-------|------------------------------------------------------------------------------------|--------|
| **W6**  | Foundry scaffold, interfaces, PredictionMarket (CPMM), Factory (UUPS), Architecture doc | done   |
| **W7**  | CI (GitHub Actions), Slither/Solhint/Prettier, Makefile, monorepo layout         | done   |
| **W8**  | Deploy + Verify scripts, MockUSDC, OracleAdapter, FeeVault4626                   | done   |
| **W9**  | Subgraph (7 entities, 5 queries), Next.js frontend (3 write flows + governance), governance stack | done   |
| **W10** | Full test suite (≥ 90 % coverage), audit report, gas report, security case studies, L2 deploy + verify | done   |

## License

MIT for our own code. Imported libraries retain their original licenses.
