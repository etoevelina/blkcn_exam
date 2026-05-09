// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Fixture} from "../helpers/Fixture.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";

contract PredictionGovernorTest is Fixture {
    function test_parametersMatchSpec() public view {
        assertEq(governor.votingDelay(), 1 days);
        assertEq(governor.votingPeriod(), 1 weeks);
        // quorum fraction is fixed (4%) but quorum(timepoint) returns supply * 4 / 100
        // and supply is 0 in the unit fixture; just sanity-check the divisor.
        assertEq(governor.quorumNumerator(), 4);
    }

    function test_timelockDelay_isTwoDays() public view {
        assertEq(timelock.getMinDelay(), 2 days);
    }

    function test_timelock_executorIsAddressZero() public view {
        // address(0) holding EXECUTOR_ROLE means "anyone may execute".
        assertTrue(timelock.hasRole(timelock.EXECUTOR_ROLE(), address(0)));
    }

    function test_proposalThreshold_isOnePercent() public {
        // Mint a known supply, delegate, advance, then verify threshold == 1%.
        vm.prank(admin);
        gov.mint(alice, 10_000e18);
        vm.prank(alice);
        gov.delegate(alice);
        vm.warp(block.timestamp + 1);
        assertEq(governor.proposalThreshold(), 10_000e18 / 100);
    }

    function test_proposeVoteQueueExecute_e2e() public {
        // Mint, delegate, advance the snapshot.
        vm.prank(admin);
        gov.mint(alice, 10_000_000e18);
        vm.prank(alice);
        gov.delegate(alice);
        vm.warp(block.timestamp + 1);

        // Build a proposal: have the Timelock call factory.setDefaults(50, 2 days).
        address[] memory targets   = new address[](1);
        uint256[] memory values    = new uint256[](1);
        bytes[]   memory calldatas = new bytes[](1);
        targets[0]   = address(factory);
        values[0]    = 0;
        calldatas[0] = abi.encodeWithSignature("setDefaults(uint16,uint32)", 50, 2 days);
        string memory description = "bump default fee to 0.5% and dispute window to 2d";

        // Hand the Timelock the right role on the factory first (in W10 deploy
        // this is wired by the deploy script; here we do it inline).
        vm.prank(admin);
        factory.grantRole(0x00, address(timelock));

        // Propose.
        vm.prank(alice);
        uint256 id = governor.propose(targets, values, calldatas, description);
        assertEq(uint8(governor.state(id)), uint8(IGovernor.ProposalState.Pending));

        // After votingDelay → Active.
        vm.warp(block.timestamp + 1 days + 1);
        assertEq(uint8(governor.state(id)), uint8(IGovernor.ProposalState.Active));

        // Cast vote.
        vm.prank(alice);
        governor.castVote(id, 1);

        // After votingPeriod → Succeeded.
        vm.warp(block.timestamp + 1 weeks + 1);
        assertEq(uint8(governor.state(id)), uint8(IGovernor.ProposalState.Succeeded));

        // Queue → Queued.
        governor.queue(targets, values, calldatas, keccak256(bytes(description)));
        assertEq(uint8(governor.state(id)), uint8(IGovernor.ProposalState.Queued));

        // After timelock delay → Execute.
        vm.warp(block.timestamp + 2 days + 1);
        governor.execute(targets, values, calldatas, keccak256(bytes(description)));
        assertEq(uint8(governor.state(id)), uint8(IGovernor.ProposalState.Executed));

        // Effect reflected on-chain.
        assertEq(factory.defaultFeeBps(), 50);
        assertEq(factory.defaultDisputeWindow(), 2 days);
    }
}
