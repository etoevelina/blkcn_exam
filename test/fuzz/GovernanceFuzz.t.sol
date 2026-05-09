// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Fixture} from "../helpers/Fixture.sol";

/// @notice Property tests for GovernanceToken voting-power dynamics.
///         Spec §3.3 — fuzz tests must cover governance voting power.
contract GovernanceFuzz is Fixture {
    /// @dev After delegate(self), votingPower at the next timepoint
    ///      equals the holder's token balance.
    function testFuzz_delegate_grantsExactVotingPower(uint96 amount) public {
        amount = uint96(bound(amount, 1, uint96(gov.CAP())));
        vm.prank(admin);
        gov.mint(alice, amount);

        vm.prank(alice);
        gov.delegate(alice);

        // Snapshot only sticks at the next clock tick.
        vm.warp(block.timestamp + 1);
        assertEq(gov.getVotes(alice), amount, "votes != balance after self-delegate");
    }

    /// @dev Transferring tokens between delegated holders moves voting
    ///      power by exactly the transferred amount.
    function testFuzz_transfer_movesVotingPowerWhenBothDelegated(uint96 total, uint96 sendAmt) public {
        total = uint96(bound(total, 2, uint96(gov.CAP() / 2)));
        sendAmt = uint96(bound(sendAmt, 1, total));

        vm.prank(admin);
        gov.mint(alice, total);

        vm.startPrank(alice);
        gov.delegate(alice);
        vm.stopPrank();
        vm.prank(bob);
        gov.delegate(bob);

        vm.warp(block.timestamp + 1);
        uint256 aliceBefore = gov.getVotes(alice);
        uint256 bobBefore   = gov.getVotes(bob);

        vm.prank(alice);
        gov.transfer(bob, sendAmt);
        vm.warp(block.timestamp + 1);

        assertEq(gov.getVotes(alice), aliceBefore - sendAmt, "alice votes off");
        assertEq(gov.getVotes(bob),   bobBefore + sendAmt,   "bob votes off");
    }

    /// @dev Minting to a self-delegated holder bumps their votes by mint amount.
    function testFuzz_mint_bumpsVotesOfDelegatedHolder(uint96 seed, uint96 mintAmt) public {
        seed    = uint96(bound(seed,    1, uint96(gov.CAP() / 4)));
        mintAmt = uint96(bound(mintAmt, 1, uint96(gov.CAP() / 4)));

        vm.prank(admin);
        gov.mint(alice, seed);
        vm.prank(alice);
        gov.delegate(alice);
        vm.warp(block.timestamp + 1);

        uint256 before = gov.getVotes(alice);
        vm.prank(admin);
        gov.mint(alice, mintAmt);
        vm.warp(block.timestamp + 1);
        assertEq(gov.getVotes(alice), before + mintAmt, "votes did not match mint");
    }
}
