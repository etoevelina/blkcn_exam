// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

/// @title PredictionTimelock — 2-day delay TimelockController
/// @author Daniyar (governance)
/// @notice
/// Constructor wires the standard OZ TimelockController with:
///   * minDelay = 2 days (spec §3.1 Governance)
///   * proposers = [initialProposer]  (deployer briefly; Governor takes over)
///   * executors = [address(0)] (open execution after the delay)
///   * admin    = initialAdmin (deployer briefly; renounces post-wiring)
///
/// `Verify.s.sol` asserts that the deployer has renounced both PROPOSER
/// and DEFAULT_ADMIN at steady-state, so the Timelock has no EOA
/// backdoor in production. The temporary admin is required only to
/// grant the Governor `PROPOSER_ROLE` at deploy time.
contract PredictionTimelock is TimelockController {
    constructor(address initialProposer, address initialAdmin)
        TimelockController(
            2 days,
            _singleton(initialProposer),
            _openExecutors(),
            initialAdmin
        )
    {}

    function _singleton(address a) private pure returns (address[] memory arr) {
        arr = new address[](1);
        arr[0] = a;
    }

    function _openExecutors() private pure returns (address[] memory arr) {
        arr = new address[](1);
        arr[0] = address(0);
    }
}
