// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";

import {Fixture} from "../helpers/Fixture.sol";
import {PredictionMarketFactory} from "../../src/markets/PredictionMarketFactory.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @title Case Study #2 — Unprotected `initialize` on the UUPS factory
/// @notice Documented in `docs/AUDIT.md §8.2`.
///
///   BEFORE — an early draft of `PredictionMarketFactory` exposed
///            `initialize` without the OZ `initializer` modifier *and*
///            without `_disableInitializers()` on the implementation
///            constructor. An attacker could front-run the legitimate
///            initialise call, set themselves as DEFAULT_ADMIN_ROLE, and
///            then `upgradeToAndCall` to malicious code.
///
///   AFTER  — production version uses `initializer` (one-shot) and
///            `_disableInitializers()` in the constructor. We assert
///            both: a) the implementation itself cannot be initialised,
///            and b) the proxy cannot be re-initialised after the
///            legitimate setup.
contract AccessControlCaseStudy is Fixture {
    function test_afterFix_implementationCannotBeInitialized() public {
        PredictionMarketFactory impl = new PredictionMarketFactory();

        vm.expectRevert();
        impl.initialize(
            admin, admin,
            address(usdc), address(outcomeToken),
            address(oracle), address(vault),
            30, 1 days
        );
    }

    function test_afterFix_proxyCannotBeReinitialized() public {
        vm.expectRevert();
        factory.initialize(
            alice, alice,
            address(usdc), address(outcomeToken),
            address(oracle), address(vault),
            30, 1 days
        );
    }

    function test_afterFix_upgradeRestrictedToDefaultAdmin() public {
        PredictionMarketFactory newImpl = new PredictionMarketFactory();

        vm.prank(alice);
        vm.expectRevert();
        factory.upgradeToAndCall(address(newImpl), "");

        vm.prank(admin);
        factory.upgradeToAndCall(address(newImpl), "");
    }

    function test_afterFix_factoryAdminIsNeverDeployer() public view {
        assertFalse(
            factory.hasRole(0x00, address(this)),
            "test contract should not be a factory admin"
        );
    }
}
