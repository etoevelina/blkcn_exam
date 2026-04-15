// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title IOracleAdapter — Chainlink-backed resolution oracle
/// @notice
/// Wraps a Chainlink `AggregatorV3Interface` per question. Adds:
///   * staleness check (reverts if `updatedAt + staleness < block.timestamp`),
///   * dispute window (configurable per question),
///   * deterministic binary outcome derivation: `latestPrice >= threshold`.
///
/// Implementations may be backed by mocks in test environments. The
/// concrete adapter contract is itself `AccessControl`-gated; the
/// interface only exposes the read/resolution path that callers (markets,
/// frontends) need.
///
/// SECURITY: callers MUST treat `resolveBinary` as a state-change in the
/// sense that the *first* successful call locks in the reported outcome
/// for the dispute window. Re-querying mid-window may return a different
/// answer if the underlying feed updated; the market is responsible for
/// snapshotting the result the first time it's read.
interface IOracleAdapter {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error StalePrice(uint256 updatedAt, uint256 staleness);
    error InvalidPrice(int256 price);
    error UnknownFeed(bytes32 questionId);
    error FeedAlreadyRegistered(bytes32 questionId);

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event FeedRegistered(bytes32 indexed questionId, address feed, uint256 staleness, uint256 disputeWindow);
    event FeedUpdated(bytes32 indexed questionId, address feed, uint256 staleness, uint256 disputeWindow);

    /*//////////////////////////////////////////////////////////////
                                  VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @notice Return the latest non-stale signed price for `questionId`.
    /// @dev Reverts on stale / negative / zero price.
    function latestSafePrice(bytes32 questionId) external view returns (int256 price, uint256 updatedAt);

    /// @notice Resolve a binary question: returns 0 (YES) if
    ///         `latestSafePrice >= threshold`, else 1 (NO).
    /// @dev Convention: outcome ids match the ERC-1155 token id parity
    ///      (`marketId * 2 + outcome`).
    function resolveBinary(bytes32 questionId, int256 threshold) external view returns (uint8 outcome);

    /// @notice Length of the dispute window (in seconds) configured for
    ///         a given question.
    function disputeWindow(bytes32 questionId) external view returns (uint256);

    /// @notice Length of the staleness threshold (in seconds).
    function stalenessOf(bytes32 questionId) external view returns (uint256);
}
