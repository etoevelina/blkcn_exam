# Team Roster — locked at end of W6

> Spec reference: §1.1. Team size 2–3. Each member must have a documented area
> of ownership. Composition is locked at end of Week 6.

| Member             | Primary area of ownership                                              | Backup area                  |
|--------------------|------------------------------------------------------------------------|------------------------------|
| **Evelina Penkova** `<162054364+etoevelina@users.noreply.github.com>` | Core protocol contracts: `PredictionMarket`, `PredictionMarketFactory`, `OutcomeToken1155`, `FeeVault4626`, `OracleAdapter` | Deploy scripts, gas report   |
| **Daniyar** `<240565@astanait.edu.kz>` | Governance stack: `GovernanceToken`, `PredictionGovernor`, `PredictionTimelock`, end-to-end propose→vote→queue→execute tests, security audit report | Unit/fuzz/invariant tests    |
| Teammate 3 (TBD)    | Frontend dApp (React + wagmi + viem), The Graph subgraph, GitHub Actions CI, Slither integration | Documentation + slide deck   |

## Replace placeholders

Once names are provided, update the table above **and** rewrite the git author
metadata for previously-committed work using `git filter-repo`:

```bash
git filter-repo --mailmap docs/.mailmap
```

A template `docs/.mailmap` will be added when names are known.

## Responsibility matrix (RACI-lite)

| Component                          | Owner       | Reviewer    |
|------------------------------------|-------------|-------------|
| `PredictionMarket` (AMM core)      | Evelina     | Daniyar  |
| `PredictionMarketFactory` (UUPS)   | Evelina     | Daniyar  |
| `OutcomeToken1155`                 | Evelina     | Teammate 3  |
| `OracleAdapter` + `MockAggregator` | Evelina     | Daniyar  |
| `FeeVault4626` (ERC-4626)          | Evelina     | Daniyar  |
| Governance (Governor/Timelock/Token)| Daniyar | Evelina     |
| Test suite (unit/fuzz/invariant)   | Daniyar  | Evelina     |
| Fork tests                         | Daniyar  | Teammate 3  |
| Audit report (`docs/AUDIT.md`)     | Daniyar  | Evelina     |
| Frontend dApp                      | Teammate 3  | Daniyar  |
| Subgraph                           | Teammate 3  | Daniyar  |
| CI / Slither / lint                | Teammate 3  | Evelina     |
| Deploy scripts (`script/`)         | Evelina     | Teammate 3  |
| Architecture doc                   | Evelina     | Daniyar  |
| Gas report                         | Evelina     | Teammate 3  |

Every member is responsible for understanding the whole system at the
architectural level (spec §7, Final Presentation).
