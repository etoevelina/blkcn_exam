// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Fixture} from "../helpers/Fixture.sol";
import {IOutcomeToken1155} from "../../src/interfaces/IOutcomeToken1155.sol";

contract OutcomeToken1155Test is Fixture {
    function test_idDerivation_isDeterministic() public view {
        assertEq(outcomeToken.yesIdOf(0), 0);
        assertEq(outcomeToken.noIdOf(0), 1);
        assertEq(outcomeToken.yesIdOf(7), 14);
        assertEq(outcomeToken.noIdOf(7), 15);
    }

    function test_marketOf_reflectsRegistration() public view {
        assertEq(outcomeToken.marketOf(outcomeToken.yesIdOf(1)), address(market));
        assertEq(outcomeToken.marketOf(outcomeToken.noIdOf(1)), address(market));
        assertEq(outcomeToken.marketOf(999), address(0));
    }

    function test_mint_revertsForNonMinter() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IOutcomeToken1155.NotMarketMinter.selector, alice, outcomeToken.yesIdOf(1)
            )
        );
        vm.prank(alice);
        outcomeToken.mint(alice, outcomeToken.yesIdOf(1), 1);
    }

    function test_burn_revertsForNonMinter() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IOutcomeToken1155.NotMarketMinter.selector, alice, outcomeToken.yesIdOf(1)
            )
        );
        vm.prank(alice);
        outcomeToken.burn(alice, outcomeToken.yesIdOf(1), 1);
    }

    function test_registerMarket_revertsOnDoubleRegister() public {
        vm.prank(address(factory));
        vm.expectRevert(
            abi.encodeWithSelector(IOutcomeToken1155.MarketAlreadyRegistered.selector, uint64(1))
        );
        outcomeToken.registerMarket(1, address(0xBEEF));
    }

    function test_registerMarket_revertsForNonFactoryRole() public {
        vm.expectRevert();
        vm.prank(alice);
        outcomeToken.registerMarket(42, address(0xBEEF));
    }

    function test_registerMarket_revertsOnZeroAddress() public {
        vm.prank(address(factory));
        vm.expectRevert(
            abi.encodeWithSelector(IOutcomeToken1155.InvalidMarket.selector, address(0))
        );
        outcomeToken.registerMarket(42, address(0));
    }

    function test_supportsInterface_acceptsERC1155AndAccessControl() public view {
        // ERC-165 itself
        assertTrue(outcomeToken.supportsInterface(0x01ffc9a7));
        // ERC-1155
        assertTrue(outcomeToken.supportsInterface(0xd9b67a26));
        // AccessControl
        assertTrue(outcomeToken.supportsInterface(0x7965db0b));
    }
}
