// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title IPredictionMarketFactory
/// @notice Creates new `PredictionMarket` contracts. Supports both
///         `CREATE` (auto-incrementing market id, address unknown until
///         deploy) and `CREATE2` (deterministic address from
///         `(salt, initCodeHash)`).
///
/// The factory itself is UUPS-upgradeable and uses ERC-7201 namespaced
/// storage to make V1 → V2 upgrades collision-proof. See
/// `docs/adr/ADR-002-uups-target-selection.md`.
interface IPredictionMarketFactory {

    error AlreadyInitialized();
    error ZeroAddress();
    error InvalidWindow();
    error InvalidFee();
    error MarketAlreadyDeployed(address predicted);
    error UnknownMarket(address market);
    error InvalidQuestion();

    event MarketCreated(
        uint64 indexed marketId,
        address indexed market,
        bytes32 indexed questionId,
        uint64 tradingEndsAt,
        uint16 feeBps,
        bool deterministic
    );

    event DefaultsUpdated(uint16 defaultFeeBps, uint32 defaultDisputeWindow);
    event Upgraded(address indexed newImplementation);

    /// @notice Deploy a new market via `CREATE`. The address is
    ///         determined by `(factoryAddress, factoryNonce)` and is
    ///         returned alongside the auto-incremented `marketId`.
    function createMarket(
        bytes32 questionId,
        int256 oracleThreshold,
        uint64 tradingEndsAt,
        uint16 feeBpsOverride
    ) external returns (uint64 marketId, address market);

    /// @notice Deploy a new market via `CREATE2` at a deterministic
    ///         address derived from `(factoryAddress, salt, initCodeHash)`.
    function createMarketDeterministic(
        bytes32 questionId,
        int256 oracleThreshold,
        uint64 tradingEndsAt,
        uint16 feeBpsOverride,
        bytes32 salt
    ) external returns (uint64 marketId, address market);

    /// @notice Pure: predict the CREATE2 address for a given salt and
    ///         initialisation parameters. Implemented in inline Yul.
    function predictMarketAddress(bytes32 salt, bytes32 initCodeHash) external view returns (address predicted);

    function marketById(uint64 id) external view returns (address);
    function idByMarket(address market) external view returns (uint64);
    function nextMarketId() external view returns (uint64);
    function defaultFeeBps() external view returns (uint16);
    function defaultDisputeWindow() external view returns (uint32);
    function collateralToken() external view returns (address);
    function outcomeToken() external view returns (address);
    function oracleAdapter() external view returns (address);
    function feeVault() external view returns (address);

    function setDefaults(uint16 newDefaultFeeBps, uint32 newDisputeWindow) external;
}
