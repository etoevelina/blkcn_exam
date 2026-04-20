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
