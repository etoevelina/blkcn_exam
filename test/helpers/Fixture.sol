// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {OutcomeToken1155} from "../../src/tokens/OutcomeToken1155.sol";
import {PredictionMarket} from "../../src/markets/PredictionMarket.sol";
import {PredictionMarketFactory} from "../../src/markets/PredictionMarketFactory.sol";
import {OracleAdapter} from "../../src/oracles/OracleAdapter.sol";
import {FeeVault4626} from "../../src/vault/FeeVault4626.sol";
import {GovernanceToken} from "../../src/governance/GovernanceToken.sol";
import {PredictionTimelock} from "../../src/governance/PredictionTimelock.sol";
import {PredictionGovernor} from "../../src/governance/PredictionGovernor.sol";

import {MockUSDC} from "../../script/mocks/MockUSDC.sol";
import {MockAggregatorV3} from "../mocks/MockAggregatorV3.sol";

/// @title Fixture — deploys the full protocol for tests
/// @notice Inherit from this in every unit/fuzz/invariant test.
abstract contract Fixture is Test {
    address internal admin     = makeAddr("admin");
    address internal keeper    = makeAddr("keeper");
    address internal alice     = makeAddr("alice");
    address internal bob       = makeAddr("bob");
    address internal carol     = makeAddr("carol");

    MockUSDC               internal usdc;
    OutcomeToken1155       internal outcomeToken;
    OracleAdapter          internal oracle;
    MockAggregatorV3       internal feed;
    FeeVault4626           internal vault;
    GovernanceToken        internal gov;
    PredictionTimelock     internal timelock;
    PredictionGovernor     internal governor;
    PredictionMarketFactory internal factory;
    PredictionMarket       internal market;

    bytes32  internal constant QUESTION = keccak256("BTC>=100k @ 2026-12-31");
    int256   internal constant THRESHOLD = 100_000e8;
    uint64   internal tradingEndsAt;

    function setUp() public virtual {
        vm.warp(1_726_000_000);
        tradingEndsAt = uint64(block.timestamp) + 30 days;

        usdc = new MockUSDC(admin);
        outcomeToken = new OutcomeToken1155(admin, "");

        oracle = new OracleAdapter(admin);
        feed = new MockAggregatorV3(8, 95_000e8);
        vm.startPrank(admin);
        oracle.registerFeed(QUESTION, address(feed), 3600, 1 days);
        vm.stopPrank();

        vault = new FeeVault4626(IERC20(address(usdc)), admin);

        gov = new GovernanceToken(admin);
        timelock = new PredictionTimelock(admin, admin);
        governor = new PredictionGovernor(gov, timelock);
        vm.startPrank(admin);
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));
        timelock.revokeRole(timelock.PROPOSER_ROLE(), admin);
        vm.stopPrank();

        PredictionMarketFactory impl = new PredictionMarketFactory();
        bytes memory initData = abi.encodeCall(
            PredictionMarketFactory.initialize,
            (
                admin, admin,
                address(usdc), address(outcomeToken),
                address(oracle), address(vault),
                30,
                1 days
            )
        );
        factory = PredictionMarketFactory(address(new ERC1967Proxy(address(impl), initData)));

        vm.startPrank(admin);
        outcomeToken.grantRole(outcomeToken.FACTORY_ROLE(), address(factory));
        vm.stopPrank();

        vm.prank(admin);
        (, address mkt) = factory.createMarket(QUESTION, THRESHOLD, tradingEndsAt, 0);
        market = PredictionMarket(mkt);

        vm.startPrank(admin);
        usdc.mint(alice, 1_000_000e6);
        usdc.mint(bob,   1_000_000e6);
        usdc.mint(carol, 1_000_000e6);
        vm.stopPrank();
    }

    function _approveAndAddLiquidity(address lp, uint256 amount) internal returns (uint256 lpMinted) {
        vm.startPrank(lp);
        usdc.approve(address(market), amount);
        outcomeToken.setApprovalForAll(address(market), true);
        (lpMinted, , ) = market.addLiquidity(amount, 0, block.timestamp + 1 hours);
        vm.stopPrank();
    }
}
