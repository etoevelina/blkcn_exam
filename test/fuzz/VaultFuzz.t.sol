// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Fixture} from "../helpers/Fixture.sol";

contract VaultFuzz is Fixture {
    function testFuzz_depositRedeem_returnsAtMostAssets(uint96 amount) public {
        amount = uint96(bound(amount, 1, 1_000_000e6));

        vm.startPrank(alice);
        usdc.approve(address(vault), uint256(amount));
        uint256 shares = vault.deposit(amount, alice);
        uint256 out = vault.redeem(shares, alice, alice);
        vm.stopPrank();

        // Vault must never pay back more than deposited (rounding favours vault).
        assertLe(out, uint256(amount));
    }

    function testFuzz_previewDeposit_underActual(uint96 amount) public {
        amount = uint96(bound(amount, 1, 1_000_000e6));

        // Seed the vault first so the offset is non-trivial.
        vm.startPrank(alice);
        usdc.approve(address(vault), 1_000e6);
        vault.deposit(1_000e6, alice);

        uint256 prev = vault.previewDeposit(amount);
        usdc.approve(address(vault), uint256(amount));
        uint256 minted = vault.deposit(amount, alice);
        vm.stopPrank();

        assertLe(prev, minted, "previewDeposit must not over-estimate shares");
    }

    function testFuzz_previewRedeem_overActual(uint96 amount) public {
        amount = uint96(bound(amount, 1, 1_000_000e6));

        vm.startPrank(alice);
        usdc.approve(address(vault), uint256(amount));
        uint256 shares = vault.deposit(amount, alice);

        uint256 prev = vault.previewRedeem(shares);
        uint256 actual = vault.redeem(shares, alice, alice);
        vm.stopPrank();

        assertGe(prev, actual, "previewRedeem must not under-estimate assets");
    }
}
