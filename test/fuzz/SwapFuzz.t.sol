// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Fixture} from "../helpers/Fixture.sol";

contract SwapFuzz is Fixture {
    function setUp() public override {
        super.setUp();
        _approveAndAddLiquidity(alice, 1_000_000e6);
    }

    /// @dev k must never decrease over a swap.
    function testFuzz_swap_kNeverDecreases(uint96 amountIn) public {
        amountIn = uint96(bound(amountIn, 1, 100_000e6));

        vm.startPrank(bob);
        usdc.approve(address(market), uint256(amountIn));
        outcomeToken.setApprovalForAll(address(market), true);
        market.mintCompleteSets(amountIn);

        (uint128 ry0, uint128 rn0) = market.reserves();
        uint256 kBefore = uint256(ry0) * uint256(rn0);
        market.swap(market.yesId(), market.noId(), amountIn, 0, block.timestamp + 1 hours);
        (uint128 ry1, uint128 rn1) = market.reserves();
        uint256 kAfter = uint256(ry1) * uint256(rn1);
        vm.stopPrank();

        assertGe(kAfter, kBefore);
    }

    /// @dev getAmountOut is strictly less than amountIn * reserveOut / reserveIn.
    function testFuzz_getAmountOut_underNoFeeBound(uint96 amountIn, uint128 ri, uint128 ro) public view {
        amountIn = uint96(bound(amountIn, 1, type(uint96).max / 10_000));
        ri = uint128(bound(ri, 1, type(uint96).max));
        ro = uint128(bound(ro, 1, type(uint96).max));
        uint256 noFee = (uint256(amountIn) * uint256(ro)) / uint256(ri);
        uint256 out = market.getAmountOut(amountIn, ri, ro);
        assertLe(out, noFee, "fee path must not exceed zero-fee bound");
    }

    /// @dev A round-trip swap (yes→no→yes) ends with strictly less YES than started.
    function testFuzz_roundtrip_losesToFee(uint96 amountIn) public {
        amountIn = uint96(bound(amountIn, 1e6, 50_000e6));

        vm.startPrank(bob);
        usdc.approve(address(market), uint256(amountIn));
        outcomeToken.setApprovalForAll(address(market), true);
        market.mintCompleteSets(amountIn);
        uint256 yesStart = outcomeToken.balanceOf(bob, market.yesId());

        uint256 gotNo = market.swap(market.yesId(), market.noId(), amountIn, 0, block.timestamp + 1 hours);
        market.swap(market.noId(), market.yesId(), gotNo, 0, block.timestamp + 1 hours);
        uint256 yesEnd = outcomeToken.balanceOf(bob, market.yesId());
        vm.stopPrank();

        assertLt(yesEnd, yesStart, "round-trip must bleed fee");
    }
}
