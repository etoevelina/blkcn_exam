// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Fixture} from "../helpers/Fixture.sol";
import {IOracleAdapter} from "../../src/interfaces/IOracleAdapter.sol";

contract OracleAdapterTest is Fixture {
    bytes32 constant Q = keccak256("oracle-test");

    function test_register_setsFields() public {
        vm.prank(admin);
        oracle.registerFeed(Q, address(feed), 1800, 1 days);
        assertEq(oracle.feedOf(Q), address(feed));
        assertEq(oracle.stalenessOf(Q), 1800);
        assertEq(oracle.disputeWindow(Q), 1 days);
    }

    function test_register_revertsOnDouble() public {
        vm.startPrank(admin);
        oracle.registerFeed(Q, address(feed), 1800, 1 days);
        vm.expectRevert(
            abi.encodeWithSelector(IOracleAdapter.FeedAlreadyRegistered.selector, Q)
        );
        oracle.registerFeed(Q, address(feed), 1800, 1 days);
        vm.stopPrank();
    }

    function test_register_revertsForNonAdmin() public {
        vm.prank(alice);
        vm.expectRevert();
        oracle.registerFeed(Q, address(feed), 1800, 1 days);
    }

    function test_latestSafePrice_returnsAnswer() public {
        vm.prank(admin);
        oracle.registerFeed(Q, address(feed), 1 hours, 1 days);
        (int256 p, uint256 ts) = oracle.latestSafePrice(Q);
        assertEq(p, 95_000e8);
        assertEq(ts, block.timestamp);
    }

    function test_latestSafePrice_revertsOnStale() public {
        vm.prank(admin);
        oracle.registerFeed(Q, address(feed), 30, 1 days);

        vm.warp(block.timestamp + 31);
        vm.expectRevert();
        oracle.latestSafePrice(Q);
    }

    function test_latestSafePrice_revertsOnNonPositiveAnswer() public {
        vm.prank(admin);
        oracle.registerFeed(Q, address(feed), 1 hours, 1 days);

        feed.setPrice(-1);
        vm.expectRevert(
            abi.encodeWithSelector(IOracleAdapter.InvalidPrice.selector, int256(-1))
        );
        oracle.latestSafePrice(Q);
    }

    function test_resolveBinary_returnsZeroWhenPriceAboveThreshold() public {
        vm.prank(admin);
        oracle.registerFeed(Q, address(feed), 1 hours, 1 days);
        feed.setPrice(101_000e8);
        assertEq(oracle.resolveBinary(Q, 100_000e8), 0);
    }

    function test_resolveBinary_returnsOneWhenPriceBelowThreshold() public {
        vm.prank(admin);
        oracle.registerFeed(Q, address(feed), 1 hours, 1 days);
        feed.setPrice(99_000e8);
        assertEq(oracle.resolveBinary(Q, 100_000e8), 1);
    }

    function test_updateFeed_changesParameters() public {
        vm.startPrank(admin);
        oracle.registerFeed(Q, address(feed), 1 hours, 1 days);
        oracle.updateFeed(Q, address(feed), 30 minutes, 12 hours);
        vm.stopPrank();
        assertEq(oracle.stalenessOf(Q), 30 minutes);
        assertEq(oracle.disputeWindow(Q), 12 hours);
    }

    function test_updateFeed_revertsForNonAdmin() public {
        vm.prank(admin);
        oracle.registerFeed(Q, address(feed), 1 hours, 1 days);
        vm.prank(alice);
        vm.expectRevert();
        oracle.updateFeed(Q, address(feed), 30 minutes, 1 days);
    }

    function test_updateFeed_revertsOnZeroValues() public {
        vm.startPrank(admin);
        oracle.registerFeed(Q, address(feed), 1 hours, 1 days);
        vm.expectRevert();
        oracle.updateFeed(Q, address(0), 1 hours, 1 days);
        vm.expectRevert();
        oracle.updateFeed(Q, address(feed), 0, 1 days);
        vm.expectRevert();
        oracle.updateFeed(Q, address(feed), 1 hours, 0);
        vm.stopPrank();
    }

    function test_updateFeed_revertsForUnknownQuestion() public {
        vm.prank(admin);
        vm.expectRevert();
        oracle.updateFeed(bytes32("never-registered"), address(feed), 1 hours, 1 days);
    }

    function test_views_revertOnUnknown() public {
        vm.expectRevert(
            abi.encodeWithSelector(IOracleAdapter.UnknownFeed.selector, bytes32("unknown"))
        );
        oracle.stalenessOf(bytes32("unknown"));
    }
}
