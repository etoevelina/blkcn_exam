// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Governor, IGovernor} from "@openzeppelin/contracts/governance/Governor.sol";
import {GovernorSettings} from "@openzeppelin/contracts/governance/extensions/GovernorSettings.sol";
import {GovernorCountingSimple} from "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import {GovernorVotes} from "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import {GovernorVotesQuorumFraction} from
    "@openzeppelin/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";
import {GovernorTimelockControl} from
    "@openzeppelin/contracts/governance/extensions/GovernorTimelockControl.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

/// @title PredictionGovernor — OZ Governor with capstone-mandated params
/// @author Daniyar (governance)
/// @notice
///   voting delay     = 1 day
///   voting period    = 1 week
///   proposal threshold = 1% of supply (handled via GovernorSettings: 1e18)
///   quorum           = 4% (GovernorVotesQuorumFraction)
///   clock mode       = timestamp (inherited from the GovernanceToken)
///
/// Timestamp-mode is critical for L2: Arbitrum's per-block time is
/// variable, so any block-number-counted delay would be wildly
/// inconsistent in practice.
contract PredictionGovernor is
    Governor,
    GovernorSettings,
    GovernorCountingSimple,
    GovernorVotes,
    GovernorVotesQuorumFraction,
    GovernorTimelockControl
{
    constructor(IVotes token_, TimelockController timelock_)
        Governor("PredictionGovernor")
        GovernorSettings(
            1 days,                  // voting delay
            1 weeks,                 // voting period
            0                        // proposalThreshold: computed dynamically below
        )
        GovernorVotes(token_)
        GovernorVotesQuorumFraction(4)   // quorum = 4%
        GovernorTimelockControl(timelock_)
    {}

    /*//////////////////////////////////////////////////////////////
                          PROPOSAL THRESHOLD = 1%
    //////////////////////////////////////////////////////////////*/

    /// @dev Returns 1% of the token's current total supply. Implemented as
    ///      a dynamic readout (rather than a fixed constant in
    ///      GovernorSettings) so that minting more tokens later
    ///      automatically raises the bar.
    function proposalThreshold()
        public
        view
        override(Governor, GovernorSettings)
        returns (uint256)
    {
        // 1% of total voting supply.
        return token().getPastTotalSupply(clock() - 1) / 100;
    }

    /*//////////////////////////////////////////////////////////////
                          MULTIPLE-INHERITANCE GLUE
    //////////////////////////////////////////////////////////////*/

    function state(uint256 proposalId)
        public
        view
        override(Governor, GovernorTimelockControl)
        returns (ProposalState)
    {
        return super.state(proposalId);
    }

    function proposalNeedsQueuing(uint256 proposalId)
        public
        view
        override(Governor, GovernorTimelockControl)
        returns (bool)
    {
        return super.proposalNeedsQueuing(proposalId);
    }

    function votingDelay() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.votingDelay();
    }

    function votingPeriod() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.votingPeriod();
    }

    function quorum(uint256 timepoint)
        public
        view
        override(Governor, GovernorVotesQuorumFraction)
        returns (uint256)
    {
        return super.quorum(timepoint);
    }

    function _queueOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint48) {
        return super._queueOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _executeOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) {
        super._executeOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint256) {
        return super._cancel(targets, values, calldatas, descriptionHash);
    }

    function _executor() internal view override(Governor, GovernorTimelockControl) returns (address) {
        return super._executor();
    }
}
