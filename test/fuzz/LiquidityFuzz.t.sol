// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Fixture} from "../helpers/Fixture.sol";

contract LiquidityFuzz is Fixture {
    /// @dev Initial deposit minus MIN_LIQUIDITY equals lpMinted (matches OZ Uniswap-V2 pattern).
    function testFuzz_initialDeposit_lpEqualsAmountMinusMin(uint96 amount) public {
        amount = uint96(bound(amount, market.MIN_LIQUIDITY() + 1, 1_000_000e6));
        uint256 lp = _approveAndAddLiquidity(alice, amount);
        assertEq(lp, uint256(amount) - market.MIN_LIQUIDITY());
    }

    /// @dev addLiquidity then removeLiquidity returns ≤ the original YES+NO.
    function testFuzz_addThenRemove_roundtrip(uint96 amount) public {
        amount = uint96(bound(amount, market.MIN_LIQUIDITY() + 1, 1_000_000e6));
        uint256 lp = _approveAndAddLiquidity(alice, amount);

        vm.prank(alice);
        (uint256 yesOut, uint256 noOut) =
            market.removeLiquidity(lp, 0, 0, block.timestamp + 1 hours);

        // We can never get more YES+NO than we put in (some is forever locked
        // in MIN_LIQUIDITY tokens held by the burn address).
        assertLe(yesOut, uint256(amount));
        assertLe(noOut, uint256(amount));
    }
}
