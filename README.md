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
