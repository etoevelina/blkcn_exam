# ADR-003 — ERC-7201 namespaced storage for the UUPS factory

**Status:** Accepted (W6)
**Decision-makers:** Evelina (core)

## Context

`PredictionMarketFactory` is upgradeable (UUPS). Spec §3.1 requires a
"documented V1 → V2 upgrade path"; OZ requires that storage layout be
preserved across upgrades, or new state added via well-defined slots.

Three patterns were available in May 2026:

1. **Implicit layout + `__gap` padding** — pre-OZ-5 idiom. Reserve `uint256[N] __gap` after every batch of state to absorb future fields.
2. **ERC-7201 namespaced storage** — store the entire state of a logical "module" in a deterministic slot (`keccak256(abi.encode(uint256(keccak256(name)) - 1)) & ~0xff`). Each upgrade can introduce a new namespace.
3. **Diamond / proxy-pattern multi-facet storage** — overkill for one upgradeable contract.

## Decision

Use ERC-7201 — single namespace `erc7201:prediction.market.factory.main`
for V1, with the convention that V2/V3 add new namespaces, never reorder
existing ones.

Concretely:

```solidity
/// @custom:storage-location erc7201:prediction.market.factory.main
struct FactoryStorage {
    address protocolAdmin;
    address oracleAdapter;
    address feeVault;
    address outcomeToken;
    address collateralToken;
    uint64  nextMarketId;
    uint16  defaultFeeBps;
    uint32  defaultDisputeWindow;
    mapping(uint64 => address) marketById;
    mapping(address => uint64) idByMarket;
}

bytes32 private constant _FACTORY_STORAGE_SLOT =
    0x8a6eeb15c0a4f6f1bc393fbd6de59958b6281e71cb4379c188e2764f21c90200;

function _factoryStorage() private pure returns (FactoryStorage storage $) {
    assembly { $.slot := _FACTORY_STORAGE_SLOT }
}
```

## Consequences

- **Zero risk of slot collision** across V1 → V2 → … if we follow the
  append-only rule for `FactoryStorage` and put unrelated V2 state in a
  new namespace.
- **Slot derivation verifiable**: `script/StorageSlot.s.sol` (or `cast
  keccak`) reproduces the constant; any audit can verify it offline.
- **One extra assembly block per accessor** — small cost, paid only at
  read/write time, ~7 gas per call.
- Slither flags the assembly as Informational; documented in audit §11.
