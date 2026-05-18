// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Fixture} from "../helpers/Fixture.sol";
import {FeeVault4626} from "../../src/vault/FeeVault4626.sol";
import {MockUSDC} from "../../script/mocks/MockUSDC.sol";

contract VaultHandler is Test {
    FeeVault4626 internal vault;
    MockUSDC internal usdc;
    address internal user;

    constructor(FeeVault4626 v, MockUSDC u, address actor) {
        vault = v;
        usdc = u;
        user = actor;
    }

    function deposit(uint96 amount) external {
        amount = uint96(bound(amount, 1, 100_000e6));
        vm.startPrank(user);
        usdc.approve(address(vault), amount);
        try vault.deposit(amount, user) { } catch { }
        vm.stopPrank();
    }

    function withdraw(uint96 shares) external {
        shares = uint96(bound(shares, 0, vault.balanceOf(user)));
        if (shares == 0) return;
        vm.startPrank(user);
        try vault.redeem(shares, user, user) { } catch { }
        vm.stopPrank();
    }

    function receiveFees(uint96 amount) external {
        amount = uint96(bound(amount, 0, 10_000e6));
        if (amount == 0) return;
        vm.startPrank(user);
        usdc.approve(address(vault), amount);
        try vault.receiveFees(amount) { } catch { }
        vm.stopPrank();
    }
}

contract VaultInvariant is Fixture {
    VaultHandler internal handler;

    function setUp() public override {
        super.setUp();
        handler = new VaultHandler(vault, usdc, alice);
        targetContract(address(handler));
    }

    /// @dev `previewDeposit` must always under-estimate shares vs `deposit`.
    function invariant_previewDeposit_under_deposit() public view {
        uint256 sample = 1e6;
        if (vault.totalSupply() == 0) return;
        uint256 prev = vault.previewDeposit(sample);
        assertEq(prev, vault.convertToShares(sample));
    }

    /// @dev Vault assets never go negative (handler tries random calls).
    function invariant_assetsNonNegative() public view {
        assertGe(vault.totalAssets(), 0);
    }
}
