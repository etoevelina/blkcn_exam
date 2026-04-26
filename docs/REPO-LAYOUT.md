# Repository layout

Single git repository, three deployable units:

```
blkcn_exam/                       # ← Foundry root lives here
├── foundry.toml                  # solc 0.8.26, via_ir, evm_version=paris
├── remappings.txt
├── .gitignore  .gitattributes  .editorconfig  .solhint.json  .env.example
├── README.md
├── Makefile                      # one-shot dev targets (build, test, lint, deploy, etc.)
│
├── src/                          # ── Solidity sources (Foundry) ───────────
│   ├── interfaces/               IPredictionMarket, IPredictionMarketFactory,
│   │                             IOutcomeToken1155, IOracleAdapter
│   ├── markets/                  PredictionMarket, PredictionMarketFactory (UUPS)
│   ├── tokens/                   OutcomeToken1155 (W6)
│   ├── oracles/                  OracleAdapter, MockAggregatorV3              (W8)
│   ├── vault/                    FeeVault4626                                 (W8)
│   └── governance/               GovernanceToken, PredictionGovernor,
│                                 PredictionTimelock                            (W9)
│
├── test/                         # ── Foundry tests ────────────────────────
│   ├── unit/                     PredictionMarket.t.sol, Factory.t.sol, ...
│   ├── fuzz/                     SwapFuzz.t.sol, LiquidityFuzz.t.sol, ...
│   ├── invariant/                PredictionMarketInvariant.t.sol  (k never decreases)
│   ├── fork/                     ChainlinkFork.t.sol, USDCFork.t.sol
│   └── helpers/                  Deployers, mock tokens, oracle harness
│
├── script/                       # ── Deploy + verify ─────────────────────
│   ├── Deploy.s.sol              idempotent: reads/writes deployments/*.json
│   ├── Verify.s.sol              post-deploy invariants (Timelock owns X, …)
│   └── StorageSlot.s.sol         derives + asserts ERC-7201 slot for Factory
│
├── deployments/                  # ── Authoritative addresses per chain ───
│   ├── arbitrum-sepolia.json     written by Deploy.s.sol; verified by CI
│   └── anvil.json                local
│
├── docs/                         # ── Long-form docs ──────────────────────
│   ├── ARCHITECTURE.md           system context, state machine, threat model
│   ├── ROSTER.md                 team + areas of ownership
│   ├── AUDIT.md                  internal security audit                (W10)
│   ├── GAS.md                    gas report                              (W10)
│   ├── REPO-LAYOUT.md            this file
│   ├── notes/                    weekly checkpoints
│   └── adr/                      ADR-001, ADR-002, …
│
├── subgraph/                     # ── The Graph indexer ───────────────────
│   ├── package.json              graph-cli, typescript
│   ├── subgraph.yaml             manifest (arbitrum-sepolia)
│   ├── schema.graphql            7 entities
│   ├── networks.json             addresses + start blocks per chain
│   ├── abis/                     symlinked ABIs from forge out/
│   │   ├── PredictionMarketFactory.json
│   │   ├── PredictionMarket.json
│   │   └── PredictionGovernor.json
│   ├── src/
│   │   ├── factory.ts            handlers for PredictionMarketFactory events
│   │   ├── market.ts             handlers for PredictionMarket events (template)
│   │   └── governor.ts           handlers for Governor events
│   └── queries/                  5 documented GraphQL queries (.graphql)
│
├── frontend/                     # ── Next.js App Router (TS + Tailwind) ──
│   ├── package.json              next 14, wagmi v2, viem 2.x, urql, react-query
│   ├── next.config.mjs
│   ├── tsconfig.json
│   ├── tailwind.config.ts        postcss.config.js
│   ├── .eslintrc.json  .prettierrc.json  .prettierignore
│   ├── public/                   favicon, …
│   ├── app/                      App Router (file-system routing)
│   │   ├── layout.tsx            root layout — wraps every page in <Providers>
│   │   ├── page.tsx              "/"           — Markets list (subgraph-fed)
│   │   ├── markets/[id]/page.tsx market detail + swap + add LP
│   │   ├── governance/page.tsx   proposal list with state + vote
│   │   ├── portfolio/page.tsx    user balances, voting power, claims
│   │   └── providers.tsx         "use client" — wagmi + react-query + urql
│   └── src/
│       ├── components/           NetworkGuard, ProposalCard, MarketCard, TxButton,
│       │                         SwapForm, AddLiquidityForm, WalletButton, …
│       ├── hooks/                useMarkets, useProposals, useProposalState,
│       │                         useUserPortfolio, useTxNotifier
│       ├── lib/
│       │   ├── wagmi.ts          chains + connectors + transports
│       │   ├── chain.ts          Arbitrum Sepolia chain literal (forced)
│       │   ├── subgraph.ts       urql client
│       │   ├── queries.ts        5 GraphQL queries as `gql` constants
│       │   ├── errors.ts         viem/wagmi error → user-facing message map
│       │   ├── addresses.ts      reads deployments/arbitrum-sepolia.json
│       │   └── abi/              const-asserted ABIs (Factory, Market, Token,
│       │                         OutcomeToken1155, Governor, Timelock, ERC20)
│       └── types/                shared TS types (Proposal, Market, …)
│
└── .github/
    ├── workflows/
    │   ├── ci.yml                build + test + coverage + slither + lint
    │   ├── frontend.yml          frontend typecheck + build
    │   └── subgraph.yml          graph-cli codegen + build
    └── ISSUE_TEMPLATE/  PULL_REQUEST_TEMPLATE.md
```

## How the three units talk to each other

1. **Contracts → ABIs**
   Foundry compiles to `out/<Name>.sol/<Name>.json`. A `make abi-sync` step copies the relevant JSONs into both `subgraph/abis/` and `frontend/src/lib/abi/`.
2. **Contracts → Subgraph**
   `subgraph/networks.json` maps each chain to the factory address + start block. `subgraph.yaml` uses a template so each new market spawns a dynamic data source.
3. **Subgraph → Frontend**
   `frontend/src/lib/subgraph.ts` wires an `urql` client at the Studio URL. Five typed queries live in `frontend/src/lib/queries.ts`. Reads of slow-changing protocol-wide state go through The Graph; reads of "is this proposal Active right now?" go through wagmi `useReadContract` against `governor.state(proposalId)` because indexer lag would break the UX.
4. **Deploy/Verify ↔ Frontend**
   `script/Deploy.s.sol` writes addresses to `deployments/arbitrum-sepolia.json`. The frontend imports that JSON at build time (`frontend/src/lib/addresses.ts`). One source of truth, no hand-typed addresses.
5. **CI gate**
   `.github/workflows/ci.yml` runs **all three** units on every push and PR. Slither runs with `--fail-pedantic` for High/Medium; PR cannot merge if any of `forge fmt --check`, `forge test`, `forge coverage --report lcov` (≥90%), `slither`, `pnpm lint`, `pnpm tsc --noEmit`, `graph build` fails.
