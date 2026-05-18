// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";

import {Fixture} from "../helpers/Fixture.sol";

/// @title  Case Study #1 — Reentrancy on `claimWinnings`
/// @notice Documented in `docs/AUDIT.md §8.1`.
///         Demonstrates both the VULNERABLE pattern (interactions before
///         effects + ERC-1155 callback) and the SECURE pattern (CEI +
///         `nonReentrant` + state burn-before-pay).
///
/// Production `PredictionMarket.claimWinnings` is the secure form. We
/// mirror it here in a stub `VulnerableClaim` for didactic comparison.
contract VulnerableClaim {
    mapping(address => uint256) public winnings;

    function fund(address user, uint256 amount) external payable {
        require(msg.value == amount, "bad fund");
        winnings[user] += amount;
    }

    function claim() external {
        uint256 amount = winnings[msg.sender];
        require(amount > 0, "nothing");
        (bool ok,) = msg.sender.call{value: amount}("");
        require(ok, "send failed");
        winnings[msg.sender] = 0;
    }
}

/// @dev Reentrant attacker calls VulnerableClaim.claim() during the
///      `receive()` callback to drain the contract.
contract ReentrantAttacker {
    VulnerableClaim internal target;
    uint256 public hits;

    constructor(VulnerableClaim t) {
        target = t;
    }

    function attack() external payable {
        target.fund{value: msg.value}(address(this), msg.value);
        target.claim();
    }

    receive() external payable {
        if (hits < 3 && address(target).balance >= msg.value) {
            hits++;
            target.claim();
        }
    }
}

contract ReentrancyCaseStudy is Fixture {

    function test_beforeFix_reentrancyDrainsBalance() public {
        VulnerableClaim v = new VulnerableClaim();
        ReentrantAttacker att = new ReentrantAttacker(v);

        address victim = makeAddr("victim");
        vm.deal(victim, 5 ether);
        vm.prank(victim);
        v.fund{value: 5 ether}(victim, 5 ether);

        vm.deal(address(att), 2 ether);
        att.attack{value: 1 ether}();

        assertGt(address(att).balance, 1 ether, "expected drain to exceed seed");
        assertLt(address(v).balance, 6 ether, "victim's funds intact?");
    }

    function test_afterFix_claimWinningsIsReentrancySafe() public {
        _approveAndAddLiquidity(alice, 100_000e6);
        vm.startPrank(bob);
        usdc.approve(address(market), 5_000e6);
        outcomeToken.setApprovalForAll(address(market), true);
        market.mintCompleteSets(5_000e6);
        market.swap(market.noId(), market.yesId(), 5_000e6, 0, block.timestamp + 1 hours);
        vm.stopPrank();

        vm.warp(tradingEndsAt + 1);
        market.lockMarket();
        feed.setPrice(110_000e8);
        vm.prank(admin);
        market.reportOutcome();
        vm.warp(market.disputeEndsAt() + 1);
        market.finalize();

        vm.startPrank(bob);
        uint256 paid = market.claimWinnings();
        assertGt(paid, 0);
        vm.expectRevert();
        market.claimWinnings();
        vm.stopPrank();
    }
}
