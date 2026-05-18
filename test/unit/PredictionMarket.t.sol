// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Fixture} from "../helpers/Fixture.sol";
import {IPredictionMarket} from "../../src/interfaces/IPredictionMarket.sol";

contract PredictionMarketTest is Fixture {
    function test_initialState() public view {
        (uint128 ry, uint128 rn) = market.reserves();
        assertEq(ry, 0);
        assertEq(rn, 0);
        assertEq(uint8(market.status()), uint8(IPredictionMarket.Status.Open));
        assertEq(market.feeBps(), 30);
        assertEq(market.winningOutcome(), type(uint8).max);
    }

    function test_addLiquidity_initialDeposit_mintsLpMinusMinLiquidity() public {
        uint256 amount = 100_000e6;
        uint256 lpMinted = _approveAndAddLiquidity(alice, amount);
        assertEq(lpMinted, amount - market.MIN_LIQUIDITY());
        assertEq(market.balanceOf(alice), lpMinted);
        (uint128 ry, uint128 rn) = market.reserves();
        assertEq(uint256(ry), amount);
        assertEq(uint256(rn), amount);
    }

    function test_addLiquidity_revertsBelowMinLiquidity() public {
        uint256 minLiq = market.MIN_LIQUIDITY();
        uint256 deadline = block.timestamp + 1 hours;
        vm.startPrank(alice);
        usdc.approve(address(market), minLiq);
        vm.expectRevert(IPredictionMarket.InsufficientLiquidity.selector);
        market.addLiquidity(minLiq, 0, deadline);
        vm.stopPrank();
    }

    function test_addLiquidity_revertsOnDeadline() public {
        vm.startPrank(alice);
        usdc.approve(address(market), 10_000e6);
        vm.warp(block.timestamp + 2);
        uint256 deadline = block.timestamp - 1;
        vm.expectRevert(
            abi.encodeWithSelector(IPredictionMarket.DeadlineExpired.selector, block.timestamp, deadline)
        );
        market.addLiquidity(10_000e6, 0, deadline);
        vm.stopPrank();
    }

    function test_addLiquidity_revertsOnZero() public {
        vm.startPrank(alice);
        usdc.approve(address(market), 100);
        vm.expectRevert(IPredictionMarket.ZeroAmount.selector);
        market.addLiquidity(0, 0, block.timestamp + 1 hours);
        vm.stopPrank();
    }

    function test_swap_revertsBeforeLiquidity() public {
        uint256 yId = market.yesId();
        uint256 nId = market.noId();
        uint256 deadline = block.timestamp + 1 hours;
        vm.startPrank(alice);
        outcomeToken.setApprovalForAll(address(market), true);
        vm.expectRevert(IPredictionMarket.InsufficientLiquidity.selector);
        market.swap(yId, nId, 1e6, 0, deadline);
        vm.stopPrank();
    }

    function test_swap_yesToNo_reducesReserveOut() public {
        _approveAndAddLiquidity(alice, 100_000e6);

        vm.startPrank(alice);
        usdc.approve(address(market), 10_000e6);
        market.mintCompleteSets(10_000e6);
        uint256 yesBefore = outcomeToken.balanceOf(alice, market.yesId());
        uint256 noBefore = outcomeToken.balanceOf(alice, market.noId());

        uint256 amountIn = 1_000e6;
        uint256 expected = market.getAmountOut(amountIn, 100_000e6, 100_000e6);
        market.swap(market.yesId(), market.noId(), amountIn, 0, block.timestamp + 1 hours);
        vm.stopPrank();

        assertEq(outcomeToken.balanceOf(alice, market.yesId()), yesBefore - amountIn);
        assertEq(outcomeToken.balanceOf(alice, market.noId()), noBefore + expected);
    }

    function test_swap_revertsOnSameOutcome() public {
        _approveAndAddLiquidity(alice, 100_000e6);
        uint256 yId = market.yesId();
        uint256 deadline = block.timestamp + 1 hours;
        vm.prank(alice);
        vm.expectRevert(IPredictionMarket.SameOutcomeSwap.selector);
        market.swap(yId, yId, 1e6, 0, deadline);
    }

    function test_swap_revertsOnSlippage() public {
        _approveAndAddLiquidity(alice, 100_000e6);
        uint256 yId = market.yesId();
        uint256 nId = market.noId();
        uint256 expected = market.getAmountOut(1_000e6, 100_000e6, 100_000e6);
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory expectedRevert = abi.encodeWithSelector(
            IPredictionMarket.InsufficientOutputAmount.selector, expected, expected + 1
        );

        vm.startPrank(alice);
        usdc.approve(address(market), 10_000e6);
        market.mintCompleteSets(10_000e6);
        vm.expectRevert(expectedRevert);
        market.swap(yId, nId, 1_000e6, expected + 1, deadline);
        vm.stopPrank();
    }

    function test_swap_kInvariantHolds() public {
        _approveAndAddLiquidity(alice, 100_000e6);

        vm.startPrank(alice);
        usdc.approve(address(market), 10_000e6);
        market.mintCompleteSets(10_000e6);

        (uint128 ry0, uint128 rn0) = market.reserves();
        uint256 kBefore = uint256(ry0) * uint256(rn0);
        market.swap(market.yesId(), market.noId(), 1_000e6, 0, block.timestamp + 1 hours);
        (uint128 ry1, uint128 rn1) = market.reserves();
        uint256 kAfter = uint256(ry1) * uint256(rn1);
        assertGe(kAfter, kBefore, "k must not decrease");
        vm.stopPrank();
    }

    function test_mintAndRedeemCompleteSets() public {
        uint256 amount = 5_000e6;
        vm.startPrank(alice);
        usdc.approve(address(market), amount);
        market.mintCompleteSets(amount);
        assertEq(outcomeToken.balanceOf(alice, market.yesId()), amount);
        assertEq(outcomeToken.balanceOf(alice, market.noId()), amount);

        market.redeemCompleteSets(amount);
        assertEq(outcomeToken.balanceOf(alice, market.yesId()), 0);
        assertEq(outcomeToken.balanceOf(alice, market.noId()), 0);
        vm.stopPrank();
    }

    function test_lockMarket_revertsBeforeWindow() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IPredictionMarket.TradingNotEnded.selector, block.timestamp, tradingEndsAt
            )
        );
        market.lockMarket();
    }

    function test_lockReportFinalize_happyPath() public {
        _approveAndAddLiquidity(alice, 100_000e6);

        vm.warp(tradingEndsAt + 1);
        market.lockMarket();
        assertEq(uint8(market.status()), uint8(IPredictionMarket.Status.Locked));

        feed.setPrice(110_000e8);
        vm.prank(admin);
        market.reportOutcome();
        assertEq(uint8(market.status()), uint8(IPredictionMarket.Status.Reported));
        assertEq(market.winningOutcome(), 0);

        vm.warp(market.disputeEndsAt() + 1);
        market.finalize();
        assertEq(uint8(market.status()), uint8(IPredictionMarket.Status.Finalized));
    }

    function test_claimWinnings_pullsCollateralOneToOne() public {
        _approveAndAddLiquidity(alice, 100_000e6);

        vm.startPrank(bob);
        usdc.approve(address(market), 5_000e6);
        outcomeToken.setApprovalForAll(address(market), true);
        market.mintCompleteSets(5_000e6);
        market.swap(market.noId(), market.yesId(), 5_000e6, 0, block.timestamp + 1 hours);
        uint256 yesBal = outcomeToken.balanceOf(bob, market.yesId());
        vm.stopPrank();

        vm.warp(tradingEndsAt + 1);
        market.lockMarket();
        feed.setPrice(110_000e8);
        vm.prank(admin);
        market.reportOutcome();
        vm.warp(market.disputeEndsAt() + 1);
        market.finalize();

        uint256 usdcBefore = usdc.balanceOf(bob);
        vm.prank(bob);
        uint256 paid = market.claimWinnings();
        assertEq(paid, yesBal);
        assertEq(usdc.balanceOf(bob), usdcBefore + yesBal);
    }

    function test_claimWinnings_revertsBeforeFinalize() public {
        vm.expectRevert();
        vm.prank(alice);
        market.claimWinnings();
    }

    function test_disputeOutcome_happyPath() public {
        _approveAndAddLiquidity(alice, 100_000e6);
        vm.warp(tradingEndsAt + 1);
        market.lockMarket();
        feed.setPrice(110_000e8);
        vm.prank(admin);
        market.reportOutcome();

        vm.prank(admin);
        market.disputeOutcome();
        assertEq(uint8(market.status()), uint8(IPredictionMarket.Status.Disputed));
    }

    function test_disputeOutcome_revertsAfterWindow() public {
        _approveAndAddLiquidity(alice, 100_000e6);
        vm.warp(tradingEndsAt + 1);
        market.lockMarket();
        feed.setPrice(110_000e8);
        vm.prank(admin);
        market.reportOutcome();

        vm.warp(market.disputeEndsAt() + 1);
        vm.prank(admin);
        vm.expectRevert();
        market.disputeOutcome();
    }

    function test_resolveDispute_happyPath_flipsOutcome() public {
        _approveAndAddLiquidity(alice, 100_000e6);
        vm.warp(tradingEndsAt + 1);
        market.lockMarket();
        feed.setPrice(110_000e8);
        vm.prank(admin);
        market.reportOutcome();
        vm.prank(admin);
        market.disputeOutcome();

        vm.prank(admin);
        market.resolveDispute(1);
        assertEq(uint8(market.status()), uint8(IPredictionMarket.Status.Finalized));
        assertEq(market.winningOutcome(), 1);
    }

    function test_resolveDispute_revertsOnInvalidOutcome() public {
        _approveAndAddLiquidity(alice, 100_000e6);
        vm.warp(tradingEndsAt + 1);
        market.lockMarket();
        feed.setPrice(110_000e8);
        vm.prank(admin);
        market.reportOutcome();
        vm.prank(admin);
        market.disputeOutcome();

        vm.prank(admin);
        vm.expectRevert();
        market.resolveDispute(2);
    }

    function test_setInvalid_voidsMarketAndRefunds() public {
        _approveAndAddLiquidity(alice, 100_000e6);

        vm.startPrank(bob);
        usdc.approve(address(market), 5_000e6);
        outcomeToken.setApprovalForAll(address(market), true);
        market.mintCompleteSets(5_000e6);
        vm.stopPrank();

        vm.prank(admin);
        market.setInvalid("oracle compromise");
        assertEq(uint8(market.status()), uint8(IPredictionMarket.Status.Invalid));

        uint256 usdcBefore = usdc.balanceOf(bob);
        vm.prank(bob);
        market.redeemCompleteSets(5_000e6);
        assertEq(usdc.balanceOf(bob), usdcBefore + 5_000e6);
    }

    function test_setInvalid_revertsAfterFinalize() public {
        _approveAndAddLiquidity(alice, 100_000e6);
        vm.warp(tradingEndsAt + 1);
        market.lockMarket();
        feed.setPrice(110_000e8);
        vm.prank(admin);
        market.reportOutcome();
        vm.warp(market.disputeEndsAt() + 1);
        market.finalize();

        vm.prank(admin);
        vm.expectRevert();
        market.setInvalid("too late");
    }

    function test_finalize_revertsBeforeWindow() public {
        _approveAndAddLiquidity(alice, 100_000e6);
        vm.warp(tradingEndsAt + 1);
        market.lockMarket();
        feed.setPrice(110_000e8);
        vm.prank(admin);
        market.reportOutcome();
        vm.expectRevert();
        market.finalize();
    }

    function test_reportOutcome_revertsForNonKeeper() public {
        _approveAndAddLiquidity(alice, 100_000e6);
        vm.warp(tradingEndsAt + 1);
        market.lockMarket();
        feed.setPrice(110_000e8);

        vm.prank(alice);
        vm.expectRevert();
        market.reportOutcome();
    }

    function test_unpause_restoresSwap() public {
        _approveAndAddLiquidity(alice, 100_000e6);
        vm.prank(admin);
        market.pause();
        vm.prank(admin);
        market.unpause();

        uint256 yId = market.yesId();
        uint256 nId = market.noId();
        uint256 deadline = block.timestamp + 1 hours;
        vm.startPrank(alice);
        usdc.approve(address(market), 1_000e6);
        market.mintCompleteSets(1_000e6);
        market.swap(yId, nId, 100e6, 0, deadline);
        vm.stopPrank();
    }

    function test_swap_revertsOnInvalidOutcomeId() public {
        _approveAndAddLiquidity(alice, 100_000e6);
        uint256 yId = market.yesId();
        uint256 bogus = 9999;
        uint256 deadline = block.timestamp + 1 hours;
        vm.startPrank(alice);
        usdc.approve(address(market), 1_000e6);
        market.mintCompleteSets(1_000e6);
        vm.expectRevert();
        market.swap(yId, bogus, 1e6, 0, deadline);
        vm.stopPrank();
    }

    function test_addLiquidity_revertsWhenPaused() public {
        vm.prank(admin);
        market.pause();

        uint256 deadline = block.timestamp + 1 hours;
        vm.startPrank(alice);
        usdc.approve(address(market), 100e6);
        vm.expectRevert();
        market.addLiquidity(100e6, 0, deadline);
        vm.stopPrank();
    }

    function test_mintCompleteSets_revertsWhenLocked() public {
        _approveAndAddLiquidity(alice, 100_000e6);
        vm.warp(tradingEndsAt + 1);
        market.lockMarket();

        vm.startPrank(alice);
        usdc.approve(address(market), 100e6);
        vm.expectRevert();
        market.mintCompleteSets(100e6);
        vm.stopPrank();
    }

    function test_redeemCompleteSets_revertsWhenFinalized() public {
        _approveAndAddLiquidity(alice, 100_000e6);

        vm.startPrank(bob);
        usdc.approve(address(market), 1_000e6);
        outcomeToken.setApprovalForAll(address(market), true);
        market.mintCompleteSets(1_000e6);
        vm.stopPrank();

        vm.warp(tradingEndsAt + 1);
        market.lockMarket();
        feed.setPrice(110_000e8);
        vm.prank(admin);
        market.reportOutcome();
        vm.warp(market.disputeEndsAt() + 1);
        market.finalize();

        vm.prank(bob);
        vm.expectRevert();
        market.redeemCompleteSets(1_000e6);
    }

    function test_pauseBlocksSwap() public {
        _approveAndAddLiquidity(alice, 100_000e6);
        uint256 yId = market.yesId();
        uint256 nId = market.noId();
        uint256 deadline = block.timestamp + 1 hours;

        vm.prank(admin);
        market.pause();

        vm.startPrank(alice);
        vm.expectRevert();
        market.swap(yId, nId, 1_000e6, 0, deadline);
        vm.stopPrank();
    }
}
