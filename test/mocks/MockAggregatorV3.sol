// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title MockAggregatorV3 — test double for Chainlink AggregatorV3Interface
/// @notice
/// Lets tests advance the round, set arbitrary prices, simulate stale
/// data (by *not* updating `_updatedAt` when calling `setPrice`), and
/// simulate "answered-in-round mismatch" via `setRoundData`.
contract MockAggregatorV3 {
    uint8 public immutable decimals;
    string public constant description = "Mock Chainlink";
    uint256 public constant version = 1;

    uint80 private _roundId;
    int256 private _answer;
    uint256 private _startedAt;
    uint256 private _updatedAt;
    uint80 private _answeredInRound;

    constructor(uint8 decimals_, int256 initialAnswer) {
        decimals = decimals_;
        _roundId = 1;
        _answer = initialAnswer;
        _startedAt = block.timestamp;
        _updatedAt = block.timestamp;
        _answeredInRound = 1;
    }

    /// @notice Set a fresh price (auto-advances round and updates timestamps).
    function setPrice(int256 newAnswer) external {
        _roundId += 1;
        _answeredInRound = _roundId;
        _answer = newAnswer;
        _startedAt = block.timestamp;
        _updatedAt = block.timestamp;
    }

    /// @notice Power-user variant for simulating stale / pending data.
    function setRoundData(
        uint80 roundId_,
        int256 answer_,
        uint256 startedAt_,
        uint256 updatedAt_,
        uint80 answeredInRound_
    ) external {
        _roundId = roundId_;
        _answer = answer_;
        _startedAt = startedAt_;
        _updatedAt = updatedAt_;
        _answeredInRound = answeredInRound_;
    }

    function latestRoundData()
        external
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return (_roundId, _answer, _startedAt, _updatedAt, _answeredInRound);
    }
}
