// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

import {IOracleAdapter} from "../interfaces/IOracleAdapter.sol";

/// @dev Minimal local view of the Chainlink AggregatorV3Interface we
///      depend on. Kept inline (instead of importing the full chainlink
///      repository) so the adapter has no transitive surface area to audit.
interface IAggregatorV3 {
    function decimals() external view returns (uint8);
    function description() external view returns (string memory);
    function version() external view returns (uint256);
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

/// @title OracleAdapter — Chainlink wrapper with staleness + dispute window
/// @author Evelina (core)
/// @notice
/// Maps `questionId` → (Chainlink feed, staleness threshold, dispute window).
/// Used by every `PredictionMarket` for outcome resolution. Reverts on:
///   * unknown questionId,
///   * non-positive price,
///   * round still incomplete (`answeredInRound < roundId`),
///   * `updatedAt + staleness < block.timestamp`.
///
/// Registration is admin-gated (Timelock). Once a feed is registered the
/// admin can `updateFeed` to point at a new Chainlink address (e.g. after
/// Chainlink rotates the proxy), but cannot retroactively change a
/// previously-reported outcome — that flows through the market's own
/// dispute window.
contract OracleAdapter is AccessControl, IOracleAdapter {
    struct FeedConfig {
        address feed;
        uint32 staleness;       // seconds
        uint32 disputeWindow;   // seconds
        bool registered;
    }

    mapping(bytes32 questionId => FeedConfig) private _feeds;

    constructor(address admin) {
        if (admin == address(0)) revert UnknownFeed(bytes32(0));
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /*//////////////////////////////////////////////////////////////
                          ADMIN — FEED REGISTRATION
    //////////////////////////////////////////////////////////////*/

    function registerFeed(
        bytes32 questionId,
        address feed,
        uint32 staleness,
        uint32 disputeWindow_
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_feeds[questionId].registered) revert FeedAlreadyRegistered(questionId);
        if (feed == address(0) || staleness == 0 || disputeWindow_ == 0) revert UnknownFeed(questionId);

        _feeds[questionId] = FeedConfig({
            feed: feed,
            staleness: staleness,
            disputeWindow: disputeWindow_,
            registered: true
        });
        emit FeedRegistered(questionId, feed, staleness, disputeWindow_);
    }

    function updateFeed(
        bytes32 questionId,
        address feed,
        uint32 staleness,
        uint32 disputeWindow_
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        FeedConfig storage cfg = _feeds[questionId];
        if (!cfg.registered) revert UnknownFeed(questionId);
        if (feed == address(0) || staleness == 0 || disputeWindow_ == 0) revert UnknownFeed(questionId);

        cfg.feed = feed;
        cfg.staleness = staleness;
        cfg.disputeWindow = disputeWindow_;
        emit FeedUpdated(questionId, feed, staleness, disputeWindow_);
    }

    /*//////////////////////////////////////////////////////////////
                               READ-ONLY API
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IOracleAdapter
    function latestSafePrice(bytes32 questionId)
        public
        view
        returns (int256 price, uint256 updatedAt)
    {
        FeedConfig memory cfg = _feeds[questionId];
        if (!cfg.registered) revert UnknownFeed(questionId);

        // We deliberately ignore `startedAt` — staleness is enforced via
        // `updatedAt` + the configured threshold, and `answeredInRound`
        // already guards against in-progress / pending rounds.
        // slither-disable-next-line unused-return
        (uint80 roundId, int256 answer, , uint256 ts, uint80 answeredInRound) =
            IAggregatorV3(cfg.feed).latestRoundData();

        if (answer <= 0) revert InvalidPrice(answer);
        if (answeredInRound < roundId) revert StalePrice(ts, cfg.staleness);
        if (ts == 0) revert StalePrice(0, cfg.staleness);

        // Strict-less-than: a feed updated exactly `staleness` seconds ago
        // is still considered fresh; one second later it isn't.
        if (block.timestamp > ts + cfg.staleness) revert StalePrice(ts, cfg.staleness);

        return (answer, ts);
    }

    /// @inheritdoc IOracleAdapter
    function resolveBinary(bytes32 questionId, int256 threshold) external view returns (uint8 outcome) {
        (int256 price, ) = latestSafePrice(questionId);
        // outcome = 0 (YES) iff price >= threshold; else 1 (NO).
        outcome = price >= threshold ? 0 : 1;
    }

    /// @inheritdoc IOracleAdapter
    function disputeWindow(bytes32 questionId) external view returns (uint256) {
        FeedConfig memory cfg = _feeds[questionId];
        if (!cfg.registered) revert UnknownFeed(questionId);
        return cfg.disputeWindow;
    }

    /// @inheritdoc IOracleAdapter
    function stalenessOf(bytes32 questionId) external view returns (uint256) {
        FeedConfig memory cfg = _feeds[questionId];
        if (!cfg.registered) revert UnknownFeed(questionId);
        return cfg.staleness;
    }

    function feedOf(bytes32 questionId) external view returns (address) {
        return _feeds[questionId].feed;
    }
}
