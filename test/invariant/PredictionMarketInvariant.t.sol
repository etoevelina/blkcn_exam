// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Fixture} from "../helpers/Fixture.sol";
import {PredictionMarket} from "../../src/markets/PredictionMarket.sol";
import {OutcomeToken1155} from "../../src/tokens/OutcomeToken1155.sol";
import {MockUSDC} from "../../script/mocks/MockUSDC.sol";

/// @dev Stateful handler that the foundry invariant fuzzer drives.
contract MarketHandler is Test {
    PredictionMarket internal market;
    OutcomeToken1155 internal outcomeToken;
    MockUSDC internal usdc;
    address internal user;

    constructor(PredictionMarket m, OutcomeToken1155 ot, MockUSDC u, address actor) {
        market = m;
        outcomeToken = ot;
        usdc = u;
        user = actor;
        vm.prank(user);
        outcomeToken.setApprovalForAll(address(market), true);
    }

    function swapYesForNo(uint96 amount) external {
        amount = uint96(bound(amount, 1, 50_000e6));
        vm.startPrank(user);
        usdc.approve(address(market), amount);
        try market.mintCompleteSets(amount) { } catch { vm.stopPrank(); return; }
        try market.swap(market.yesId(), market.noId(), amount, 0, block.timestamp + 1 hours) { } catch { }
        vm.stopPrank();
    }

    function swapNoForYes(uint96 amount) external {
        amount = uint96(bound(amount, 1, 50_000e6));
        vm.startPrank(user);
        usdc.approve(address(market), amount);
        try market.mintCompleteSets(amount) { } catch { vm.stopPrank(); return; }
        try market.swap(market.noId(), market.yesId(), amount, 0, block.timestamp + 1 hours) { } catch { }
        vm.stopPrank();
    }
}

contract PredictionMarketInvariant is Fixture {
    MarketHandler internal handler;
    uint256 internal kAtStart;

    function setUp() public override {
        super.setUp();
        _approveAndAddLiquidity(alice, 500_000e6);

        (uint128 ry, uint128 rn) = market.reserves();
        kAtStart = uint256(ry) * uint256(rn);

        handler = new MarketHandler(market, outcomeToken, usdc, bob);
        targetContract(address(handler));
    }

    /// @dev k must never decrease over any sequence of swaps.
    function invariant_kNeverDecreases() public view {
        (uint128 ry, uint128 rn) = market.reserves();
        assertGe(uint256(ry) * uint256(rn), kAtStart);
    }

    /// @dev YES supply equals NO supply at all times (complete-set invariant).
    function invariant_supplyParity() public view {
        uint256 yesBob = outcomeToken.balanceOf(bob, market.yesId());
        uint256 noBob  = outcomeToken.balanceOf(bob, market.noId());
        (uint128 ry, uint128 rn) = market.reserves();
        assertEq(uint256(ry) + yesBob, uint256(rn) + noBob);
    }
}
