// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Fixture} from "../helpers/Fixture.sol";

contract FeeVault4626Test is Fixture {
    function test_initialState() public view {
        assertEq(vault.totalAssets(), 0);
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.asset(), address(usdc));
    }

    function test_deposit_mintsSharesProportionally() public {
        vm.startPrank(alice);
        usdc.approve(address(vault), 1_000e6);
        uint256 minted = vault.deposit(1_000e6, alice);
        vm.stopPrank();
        assertGt(minted, 0);
        assertEq(vault.balanceOf(alice), minted);
        assertEq(vault.totalAssets(), 1_000e6);
    }

    function test_redeem_returnsAssetsCloseToDeposit() public {
        vm.startPrank(alice);
        usdc.approve(address(vault), 1_000e6);
        uint256 shares = vault.deposit(1_000e6, alice);
        uint256 out = vault.redeem(shares, alice, alice);
        vm.stopPrank();
        assertApproxEqAbs(out, 1_000e6, 1);
    }

    function test_receiveFees_boostsAssets() public {
        vm.startPrank(alice);
        usdc.approve(address(vault), 1_000e6);
        vault.deposit(1_000e6, alice);
        vm.stopPrank();

        vm.startPrank(bob);
        usdc.approve(address(vault), 100e6);
        vault.receiveFees(100e6);
        vm.stopPrank();

        assertEq(vault.totalAssets(), 1_100e6);

        uint256 redeemable = vault.previewRedeem(vault.balanceOf(alice));
        assertGt(redeemable, 1_000e6);
    }

    function test_preview_invariants_hold() public {
        vm.startPrank(alice);
        usdc.approve(address(vault), 10_000e6);
        vault.deposit(5_000e6, alice);
        vm.stopPrank();

        uint256 assets = 1_000e6;
        uint256 sharesPrev = vault.previewDeposit(assets);
        vm.prank(alice);
        uint256 minted = vault.deposit(assets, alice);
        assertLe(sharesPrev, minted);
    }

    function test_pause_blocksDeposit() public {
        vm.prank(admin);
        vault.pause();

        vm.startPrank(alice);
        usdc.approve(address(vault), 1e6);
        vm.expectRevert();
        vault.deposit(1e6, alice);
        vm.stopPrank();
    }

    function test_mint_burnsExactSharesAndPullsAssets() public {
        uint256 sharesWanted = 1_000e6;
        uint256 expectedAssets = vault.previewMint(sharesWanted);

        vm.startPrank(alice);
        usdc.approve(address(vault), expectedAssets);
        uint256 paid = vault.mint(sharesWanted, alice);
        vm.stopPrank();

        assertEq(paid, expectedAssets);
        assertEq(vault.balanceOf(alice), sharesWanted);
    }

    function test_withdraw_burnsExactShares() public {
        vm.startPrank(alice);
        usdc.approve(address(vault), 1_000e6);
        vault.deposit(1_000e6, alice);

        uint256 sharesBefore = vault.balanceOf(alice);
        uint256 burned = vault.withdraw(500e6, alice, alice);
        vm.stopPrank();

        assertGt(burned, 0);
        assertEq(vault.balanceOf(alice), sharesBefore - burned);
    }

    function test_unpause_restoresDeposit() public {
        vm.prank(admin);
        vault.pause();
        vm.prank(admin);
        vault.unpause();

        vm.startPrank(alice);
        usdc.approve(address(vault), 1e6);
        vault.deposit(1e6, alice);
        vm.stopPrank();
    }

    function test_pause_doesNotBlockRedeem() public {
        vm.startPrank(alice);
        usdc.approve(address(vault), 1_000e6);
        uint256 shares = vault.deposit(1_000e6, alice);
        vm.stopPrank();

        vm.prank(admin);
        vault.pause();

        vm.prank(alice);
        vault.redeem(shares, alice, alice);
    }
}
