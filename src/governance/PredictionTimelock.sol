// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

/// @title PredictionTimelock — 2-day delay TimelockController
/// @author Daniyar (governance)
/// @notice
/// Constructor wires the standard OZ TimelockController with:
///   * minDelay = 2 days (spec §3.1 Governance)
///   * proposers = [governor]
///   * executors = [address(0)] (open execution after the delay)
///   * admin    = address(0) (no admin EOA — Timelock is its own admin
///                            via the role-grant logic the OZ contract
///                            performs internally)
///
/// We deliberately pass `address(0)` as the admin so there is no
/// `TIMELOCK_ADMIN_ROLE`-holder outside the Timelock itself. This
/// matches the spec's "no admin backdoor remains" guarantee.
contract PredictionTimelock is TimelockController {
    constructor(address governor)
        TimelockController(
            2 days,
            _singleton(governor),
            _openExecutors(),
            address(0)
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
