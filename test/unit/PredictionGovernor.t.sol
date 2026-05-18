// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Fixture} from "../helpers/Fixture.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";

contract PredictionGovernorTest is Fixture {
    function test_parametersMatchSpec() public view {
        assertEq(governor.votingDelay(), 1 days);
        assertEq(governor.votingPeriod(), 1 weeks);
        assertEq(governor.quorumNumerator(), 4);
    }

    function test_timelockDelay_isTwoDays() public view {
        assertEq(timelock.getMinDelay(), 2 days);
    }

    function test_timelock_executorIsAddressZero() public view {
        assertTrue(timelock.hasRole(timelock.EXECUTOR_ROLE(), address(0)));
    }

    function test_proposalThreshold_isOnePercent() public {
        vm.prank(admin);
        gov.mint(alice, 10_000e18);
        vm.prank(alice);
        gov.delegate(alice);
        vm.warp(block.timestamp + 1);
        assertEq(governor.proposalThreshold(), 10_000e18 / 100);
    }

    function test_proposeVoteQueueExecute_e2e() public {
        vm.prank(admin);
        gov.mint(alice, 10_000_000e18);
        vm.prank(alice);
        gov.delegate(alice);
        vm.warp(block.timestamp + 1);

        address[] memory targets   = new address[](1);
        uint256[] memory values    = new uint256[](1);
        bytes[]   memory calldatas = new bytes[](1);
        targets[0]   = address(factory);
        values[0]    = 0;
        calldatas[0] = abi.encodeWithSignature("setDefaults(uint16,uint32)", 50, 2 days);
        string memory description = "bump default fee to 0.5% and dispute window to 2d";

        vm.prank(admin);
        factory.grantRole(0x00, address(timelock));

        vm.prank(alice);
        uint256 id = governor.propose(targets, values, calldatas, description);
        assertEq(uint8(governor.state(id)), uint8(IGovernor.ProposalState.Pending));

        vm.warp(block.timestamp + 1 days + 1);
        assertEq(uint8(governor.state(id)), uint8(IGovernor.ProposalState.Active));

        vm.prank(alice);
        governor.castVote(id, 1);

        vm.warp(block.timestamp + 1 weeks + 1);
        assertEq(uint8(governor.state(id)), uint8(IGovernor.ProposalState.Succeeded));

        governor.queue(targets, values, calldatas, keccak256(bytes(description)));
        assertEq(uint8(governor.state(id)), uint8(IGovernor.ProposalState.Queued));

        vm.warp(block.timestamp + 2 days + 1);
        governor.execute(targets, values, calldatas, keccak256(bytes(description)));
        assertEq(uint8(governor.state(id)), uint8(IGovernor.ProposalState.Executed));

        assertEq(factory.defaultFeeBps(), 50);
        assertEq(factory.defaultDisputeWindow(), 2 days);
    }
}
