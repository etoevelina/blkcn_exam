// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {OutcomeToken1155} from "../src/tokens/OutcomeToken1155.sol";
import {PredictionMarketFactory} from "../src/markets/PredictionMarketFactory.sol";
import {OracleAdapter} from "../src/oracles/OracleAdapter.sol";
import {FeeVault4626} from "../src/vault/FeeVault4626.sol";
import {GovernanceToken} from "../src/governance/GovernanceToken.sol";
import {PredictionTimelock} from "../src/governance/PredictionTimelock.sol";
import {PredictionGovernor} from "../src/governance/PredictionGovernor.sol";

/// @title Verify — full-stack post-deploy assertions
contract Verify is Script {
    using stdJson for string;

    function run() external view {
        string memory json = vm.readFile("deployments/arbitrum-sepolia.json");

        address outcomeToken = json.readAddress(".outcomeToken");
        address factory      = json.readAddress(".factoryProxy");
        address oracle       = json.readAddress(".oracleAdapter");
        address vault        = json.readAddress(".feeVault");
        address timelock     = json.readAddress(".timelock");
        address governor     = json.readAddress(".governor");
        address govToken     = json.readAddress(".governanceToken");
        address deployer     = json.readAddress(".deployer");

        require(outcomeToken != address(0), "outcomeToken not deployed");
        require(factory      != address(0), "factoryProxy not deployed");
        require(oracle       != address(0), "oracleAdapter not deployed");
        require(vault        != address(0), "feeVault not deployed");
        require(timelock     != address(0), "timelock not deployed");
        require(governor     != address(0), "governor not deployed");
        require(govToken     != address(0), "governanceToken not deployed");

        // ─── Access-control / ownership ──────────────────────────
        _checkAdmin(outcomeToken, timelock, deployer, "OutcomeToken1155");
        _checkAdmin(factory,      timelock, deployer, "PredictionMarketFactory");
        _checkAdmin(oracle,       timelock, deployer, "OracleAdapter");
        _checkAdmin(vault,        timelock, deployer, "FeeVault4626");
        _checkAdmin(govToken,     timelock, deployer, "GovernanceToken");

        // Factory ↔ OutcomeToken wiring
        require(
            IAccessControl(outcomeToken).hasRole(
                OutcomeToken1155(outcomeToken).FACTORY_ROLE(), factory
            ),
            "factory lacks FACTORY_ROLE on OutcomeToken1155"
        );
        console2.log("OK   OutcomeToken1155 -> factory wiring");

        // ─── Timelock parameters ─────────────────────────────────
        PredictionTimelock tl = PredictionTimelock(payable(timelock));
        require(tl.getMinDelay() == 2 days, "timelock delay != 2 days");
        console2.log("OK   Timelock delay == 2 days");

        require(tl.hasRole(tl.PROPOSER_ROLE(), governor), "Governor not proposer");
        require(!tl.hasRole(tl.PROPOSER_ROLE(), deployer), "deployer still proposer");
        console2.log("OK   Timelock PROPOSER_ROLE wiring");

        require(tl.hasRole(tl.EXECUTOR_ROLE(), address(0)), "executor != address(0)");
        console2.log("OK   Timelock open execution (executor == address(0))");

        // ─── Governor parameters ─────────────────────────────────
        PredictionGovernor gv = PredictionGovernor(payable(governor));
        require(gv.votingDelay()  == 1 days,  "votingDelay != 1 day");
        require(gv.votingPeriod() == 1 weeks, "votingPeriod != 1 week");
        require(gv.quorumNumerator() == 4,    "quorum fraction != 4%");
        console2.log("OK   Governor 1d / 1w / 4% quorum");

        // proposalThreshold = 1% of supply (snapshot at clock()-1).
        uint256 supply = GovernanceToken(govToken).totalSupply();
        require(gv.proposalThreshold() == supply / 100, "proposalThreshold != 1% of supply");
        console2.log("OK   Governor proposalThreshold == 1%% of supply");

        // ─── No backdoor ─────────────────────────────────────────
        require(!tl.hasRole(0x00, deployer), "deployer still has TIMELOCK admin");
        console2.log("OK   No EOA backdoor on Timelock");

        console2.log("== All post-deploy invariants OK ==");
    }

    function _checkAdmin(address target, address timelock, address deployer, string memory label) internal view {
        IAccessControl ac = IAccessControl(target);
        require(ac.hasRole(0x00, timelock), string.concat(label, ": timelock not admin"));
        require(!ac.hasRole(0x00, deployer), string.concat(label, ": deployer still admin"));
        console2.log(string.concat("OK   ", label, " admin -> Timelock"));
    }
}
