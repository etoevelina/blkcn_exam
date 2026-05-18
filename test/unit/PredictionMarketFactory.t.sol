// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Fixture} from "../helpers/Fixture.sol";
import {PredictionMarket} from "../../src/markets/PredictionMarket.sol";
import {PredictionMarketFactory} from "../../src/markets/PredictionMarketFactory.sol";
import {IPredictionMarketFactory} from "../../src/interfaces/IPredictionMarketFactory.sol";

contract PredictionMarketFactoryTest is Fixture {
    bytes32 constant Q2 = keccak256("ETH>=5k @ 2026-06-30");

    function test_initialState() public view {
        assertEq(factory.defaultFeeBps(), 30);
        assertEq(factory.defaultDisputeWindow(), 1 days);
        assertEq(factory.nextMarketId(), 2);
        assertEq(factory.idByMarket(address(market)), 1);
    }

    function test_createMarket_incrementsId_andRegistersOnOutcomeToken() public {
        vm.prank(admin);
        (uint64 id, address mkt) = factory.createMarket(Q2, 5_000e8, tradingEndsAt, 0);
        assertEq(id, 2);
        assertEq(factory.marketById(2), mkt);
        assertEq(outcomeToken.marketOf(PredictionMarket(mkt).yesId()), mkt);
        assertEq(outcomeToken.marketOf(PredictionMarket(mkt).noId()), mkt);
    }

    function test_createMarket_revertsOnZeroQuestion() public {
        vm.prank(admin);
        vm.expectRevert(IPredictionMarketFactory.InvalidQuestion.selector);
        factory.createMarket(bytes32(0), 5_000e8, tradingEndsAt, 0);
    }

    function test_createMarket_revertsOnPastTradingEnd() public {
        vm.prank(admin);
        vm.expectRevert(IPredictionMarketFactory.InvalidWindow.selector);
        factory.createMarket(Q2, 5_000e8, uint64(block.timestamp - 1), 0);
    }

    function test_createMarket_revertsForNonRole() public {
        vm.prank(alice);
        vm.expectRevert();
        factory.createMarket(Q2, 5_000e8, tradingEndsAt, 0);
    }

    function test_createMarketDeterministic_addressMatchesPrediction() public {
        bytes32 salt = bytes32(uint256(0xCAFE));

        PredictionMarket.InitParams memory params = PredictionMarket.InitParams({
            collateral:      usdc,
            outcomeToken:    outcomeToken,
            oracle:          oracle,
            feeVault:        address(vault),
            admin:           admin,
            keeper:          admin,
            marketId:        2,
            questionId:      Q2,
            oracleThreshold: 5_000e8,
            tradingEndsAt:   tradingEndsAt,
            feeBps:          30,
            disputeWindow:   1 days
        });
        bytes memory initCode = abi.encodePacked(
            type(PredictionMarket).creationCode, abi.encode(params)
        );
        bytes32 initCodeHash = keccak256(initCode);
        address predicted = factory.predictMarketAddress(salt, initCodeHash);

        vm.prank(admin);
        (, address mkt) = factory.createMarketDeterministic(Q2, 5_000e8, tradingEndsAt, 0, salt);
        assertEq(mkt, predicted, "predicted != deployed");
    }

    function test_predictMarketAddress_matchesSolidityBaseline() public view {
        bytes32 salt = bytes32(uint256(1));
        bytes32 initCodeHash = keccak256("dummy initcode");
        assertEq(
            factory.predictMarketAddress(salt, initCodeHash),
            factory.predictMarketAddressSolidity(salt, initCodeHash),
            "Yul and Solidity must agree"
        );
    }

    function test_setDefaults_updatesFeeAndWindow() public {
        vm.prank(admin);
        factory.setDefaults(50, 2 days);
        assertEq(factory.defaultFeeBps(), 50);
        assertEq(factory.defaultDisputeWindow(), 2 days);
    }

    function test_setDefaults_revertsOnInvalidFee() public {
        vm.prank(admin);
        vm.expectRevert(IPredictionMarketFactory.InvalidFee.selector);
        factory.setDefaults(0, 1 days);
        vm.prank(admin);
        vm.expectRevert(IPredictionMarketFactory.InvalidFee.selector);
        factory.setDefaults(1_001, 1 days);
    }

    function test_protocolAdmin_view_returnsTimelockEquivalent() public view {
        assertEq(factory.protocolAdmin(), admin);
    }

    function test_setProtocolAdmin_updatesStorage() public {
        address newAdmin = makeAddr("newAdmin");
        vm.prank(admin);
        factory.setProtocolAdmin(newAdmin);
        assertEq(factory.protocolAdmin(), newAdmin);
    }

    function test_setProtocolAdmin_revertsOnZero() public {
        vm.prank(admin);
        vm.expectRevert();
        factory.setProtocolAdmin(address(0));
    }

    function test_setProtocolAdmin_revertsForNonAdmin() public {
        vm.prank(alice);
        vm.expectRevert();
        factory.setProtocolAdmin(alice);
    }

    function test_setDefaults_revertsOnInvalidWindow() public {
        vm.prank(admin);
        vm.expectRevert();
        factory.setDefaults(30, 0);
    }

    function test_predictMarketAddressSolidity_branchCovered() public view {
        bytes32 salt = bytes32(uint256(42));
        bytes32 hash = keccak256("benchmark");
        assertEq(
            factory.predictMarketAddress(salt, hash),
            factory.predictMarketAddressSolidity(salt, hash)
        );
    }

    function test_authorizeUpgrade_onlyAdmin() public {
        PredictionMarketFactory newImpl = new PredictionMarketFactory();
        vm.prank(alice);
        vm.expectRevert();
        factory.upgradeToAndCall(address(newImpl), "");
    }

    function test_createMarket_withCustomFeeBpsOverride() public {
        vm.prank(admin);
        (, address mkt) = factory.createMarket(Q2, 5_000e8, tradingEndsAt, 50);
        assertEq(PredictionMarket(mkt).feeBps(), 50);
    }

    function test_createMarket_revertsOnFeeBpsOverrideAboveMax() public {
        vm.prank(admin);
        vm.expectRevert();
        factory.createMarket(Q2, 5_000e8, tradingEndsAt, 1_001);
    }
}
