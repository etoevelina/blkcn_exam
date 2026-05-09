// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Fixture} from "../helpers/Fixture.sol";
import {GovernanceToken} from "../../src/governance/GovernanceToken.sol";

/// @notice Random mint/transfer/delegate workload to stress total-supply
///         conservation and treasury (timelock) balance accounting.
///         Spec §3.3 — invariant suite must include total supply
///         conservation AND treasury accounting.
contract TreasuryHandler is Test {
    GovernanceToken internal gov;
    address internal admin;
    address[] internal userActors;   // can be `from` for transfers (EOAs)
    address[] internal allActors;    // can be `to` (includes the treasury)

    constructor(GovernanceToken g, address admin_, address[] memory users_, address treasury) {
        gov = g;
        admin = admin_;
        userActors = users_;
        for (uint256 i = 0; i < users_.length; i++) allActors.push(users_[i]);
        allActors.push(treasury);
    }

    function _userActor(uint256 seed) internal view returns (address) {
        return userActors[seed % userActors.length];
    }

    function _anyActor(uint256 seed) internal view returns (address) {
        return allActors[seed % allActors.length];
    }

    function mint(uint96 amount, uint256 seed) external {
        amount = uint96(bound(amount, 0, 1_000_000e18));
        if (amount == 0 || gov.totalSupply() + amount > gov.CAP()) return;
        vm.prank(admin);
        gov.mint(_anyActor(seed), amount);
    }

    function transfer(uint96 amount, uint256 fromSeed, uint256 toSeed) external {
        // The treasury only enters via `to`; it can never be the `from`
        // side under the handler (governance-mediated transfers out of
        // the treasury go through `execute`, not the handler).
        address from = _userActor(fromSeed);
        address to   = _anyActor(toSeed);
        uint256 bal  = gov.balanceOf(from);
        amount       = uint96(bound(amount, 0, bal == 0 ? 0 : bal));
        if (amount == 0) return;
        vm.prank(from);
        gov.transfer(to, amount);
    }

    function delegate(uint256 fromSeed, uint256 toSeed) external {
        address from = _userActor(fromSeed);
        address to   = _anyActor(toSeed);
        vm.prank(from);
        gov.delegate(to);
    }
}

contract TreasuryInvariant is Fixture {
    TreasuryHandler internal handler;
    address[] internal allActors;
    uint256 internal timelockStartBalance;

    function setUp() public override {
        super.setUp();

        address[] memory users = new address[](3);
        users[0] = alice;
        users[1] = bob;
        users[2] = carol;

        allActors.push(alice);
        allActors.push(bob);
        allActors.push(carol);
        allActors.push(address(timelock));

        // Seed treasury (timelock) with some governance tokens — simulates
        // a community-initiated transfer to the treasury.
        vm.prank(admin);
        gov.mint(address(timelock), 100_000e18);
        timelockStartBalance = gov.balanceOf(address(timelock));

        handler = new TreasuryHandler(gov, admin, users, address(timelock));
        targetContract(address(handler));
    }

    /* ──────────────────────────────────────────────────────────────────
     *  Invariant 1 — total-supply conservation.
     *  ERC-20 sum-of-balances must equal totalSupply at all times.
     * ──────────────────────────────────────────────────────────────── */
    function invariant_totalSupplyEqualsSumOfBalances() public view {
        uint256 sum;
        for (uint256 i = 0; i < allActors.length; i++) {
            sum += gov.balanceOf(allActors[i]);
        }
        assertEq(sum, gov.totalSupply(), "totalSupply != sum(balanceOf)");
    }

    /* ──────────────────────────────────────────────────────────────────
     *  Invariant 2 — treasury accounting.
     *  The Timelock balance can only decrease via an `execute` call,
     *  which the handler never makes. Therefore the timelock balance
     *  must be ≥ its starting balance at every snapshot.
     * ──────────────────────────────────────────────────────────────── */
    function invariant_treasuryBalanceMonotonicUnderHandler() public view {
        assertGe(
            gov.balanceOf(address(timelock)),
            timelockStartBalance,
            "treasury bled funds outside of governance"
        );
    }
}
