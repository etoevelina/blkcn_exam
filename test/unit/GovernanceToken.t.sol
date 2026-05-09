// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Fixture} from "../helpers/Fixture.sol";
import {GovernanceToken} from "../../src/governance/GovernanceToken.sol";

contract GovernanceTokenTest is Fixture {
    function test_capAndDecimals() public view {
        assertEq(gov.CAP(), 100_000_000e18);
        assertEq(gov.decimals(), 18);
    }

    function test_constructor_revertsOnZeroAdmin() public {
        vm.expectRevert();
        new GovernanceToken(address(0));
    }

    function test_mint_revertsAboveCap() public {
        vm.prank(admin);
        vm.expectRevert();
        gov.mint(alice, gov.CAP() + 1);
    }

    function test_mint_byNonMinter_reverts() public {
        vm.prank(alice);
        vm.expectRevert();
        gov.mint(alice, 1e18);
    }

    function test_delegate_addsVotingPower() public {
        vm.prank(admin);
        gov.mint(alice, 1_000e18);

        vm.prank(alice);
        gov.delegate(alice);

        // Voting power is recorded post-delegation; warp +1 so checkpoint sticks.
        vm.warp(block.timestamp + 1);
        assertEq(gov.getVotes(alice), 1_000e18);
    }

    function test_clockMode_isTimestamp() public view {
        assertEq(gov.CLOCK_MODE(), "mode=timestamp");
        assertEq(uint256(gov.clock()), block.timestamp);
    }

    function test_permit_signsAndSpends() public {
        uint256 privKey = 0xA11CE;
        address owner = vm.addr(privKey);
        vm.prank(admin);
        gov.mint(owner, 1_000e18);

        uint256 deadline = block.timestamp + 1 hours;
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                gov.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                        owner,
                        bob,
                        100e18,
                        gov.nonces(owner),
                        deadline
                    )
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privKey, digest);
        gov.permit(owner, bob, 100e18, deadline, v, r, s);

        assertEq(gov.allowance(owner, bob), 100e18);
    }
}
