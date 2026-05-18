// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {OutcomeToken1155} from "../src/tokens/OutcomeToken1155.sol";
import {PredictionMarketFactory} from "../src/markets/PredictionMarketFactory.sol";
import {OracleAdapter} from "../src/oracles/OracleAdapter.sol";
import {FeeVault4626} from "../src/vault/FeeVault4626.sol";
import {GovernanceToken} from "../src/governance/GovernanceToken.sol";
import {PredictionTimelock} from "../src/governance/PredictionTimelock.sol";
import {PredictionGovernor} from "../src/governance/PredictionGovernor.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";

/// @title Deploy — idempotent full-stack deployment
contract Deploy is Script {
    using stdJson for string;

    string internal constant DEPLOYMENTS_PATH = "deployments/arbitrum-sepolia.json";

    struct Existing {
        address collateralToken;
        address outcomeToken;
        address oracleAdapter;
        address feeVault;
        address governanceToken;
        address timelock;
        address governor;
        address factoryProxy;
        address factoryImpl;
    }

    function run() external {
        Existing memory ex = _loadExisting();
        address deployer = msg.sender;
        console2.log("Deployer:", deployer);

        vm.startBroadcast();

        if (ex.collateralToken == address(0)) {
            ex.collateralToken = address(new MockUSDC(deployer));
            console2.log("MockUSDC deployed:", ex.collateralToken);
        }

        if (ex.outcomeToken == address(0)) {
            ex.outcomeToken = address(new OutcomeToken1155(deployer, ""));
            console2.log("OutcomeToken1155 deployed:", ex.outcomeToken);
        }

        if (ex.oracleAdapter == address(0)) {
            ex.oracleAdapter = address(new OracleAdapter(deployer));
            console2.log("OracleAdapter deployed:", ex.oracleAdapter);
        }

        if (ex.feeVault == address(0)) {
            ex.feeVault = address(new FeeVault4626(IERC20(ex.collateralToken), deployer));
            console2.log("FeeVault4626 deployed:", ex.feeVault);
        }

        if (ex.governanceToken == address(0)) {
            ex.governanceToken = address(new GovernanceToken(deployer));
            console2.log("GovernanceToken deployed:", ex.governanceToken);
        }

        if (ex.timelock == address(0) && ex.governor == address(0)) {
            ex.timelock = address(new PredictionTimelock(deployer, deployer));
            console2.log("PredictionTimelock deployed:", ex.timelock);

            ex.governor = address(
                new PredictionGovernor(
                    GovernanceToken(ex.governanceToken),
                    PredictionTimelock(payable(ex.timelock))
                )
            );
            console2.log("PredictionGovernor deployed:", ex.governor);

            PredictionTimelock tl = PredictionTimelock(payable(ex.timelock));
            tl.grantRole(tl.PROPOSER_ROLE(), ex.governor);
            tl.grantRole(tl.CANCELLER_ROLE(), ex.governor);
            tl.revokeRole(tl.PROPOSER_ROLE(), deployer);
            tl.renounceRole(0x00, deployer);
        }

        if (ex.factoryImpl == address(0)) {
            ex.factoryImpl = address(new PredictionMarketFactory());
            console2.log("Factory impl deployed:", ex.factoryImpl);
        }

        if (ex.factoryProxy == address(0)) {
            bytes memory initData = abi.encodeCall(
                PredictionMarketFactory.initialize,
                (
                    ex.timelock,
                    ex.governor,
                    ex.collateralToken,
                    ex.outcomeToken,
                    ex.oracleAdapter,
                    ex.feeVault,
                    30,
                    24 hours
                )
            );
            ex.factoryProxy = address(new ERC1967Proxy(ex.factoryImpl, initData));
            console2.log("Factory proxy deployed:", ex.factoryProxy);
        }

        OutcomeToken1155 ot = OutcomeToken1155(ex.outcomeToken);
        if (!ot.hasRole(ot.FACTORY_ROLE(), ex.factoryProxy)) {
            ot.grantRole(ot.FACTORY_ROLE(), ex.factoryProxy);
        }
        if (!ot.hasRole(0x00, ex.timelock)) {
            ot.grantRole(0x00, ex.timelock);
        }
        if (ot.hasRole(0x00, deployer) && ex.timelock != deployer) {
            ot.renounceRole(0x00, deployer);
        }

        OracleAdapter or_ = OracleAdapter(ex.oracleAdapter);
        if (!or_.hasRole(0x00, ex.timelock)) or_.grantRole(0x00, ex.timelock);
        if (or_.hasRole(0x00, deployer) && ex.timelock != deployer) or_.renounceRole(0x00, deployer);

        FeeVault4626 fv = FeeVault4626(ex.feeVault);
        if (!fv.hasRole(0x00, ex.timelock)) fv.grantRole(0x00, ex.timelock);
        if (fv.hasRole(0x00, deployer) && ex.timelock != deployer) fv.renounceRole(0x00, deployer);

        GovernanceToken gt = GovernanceToken(ex.governanceToken);
        if (!gt.hasRole(0x00, ex.timelock)) gt.grantRole(0x00, ex.timelock);
        if (!gt.hasRole(gt.MINTER_ROLE(), ex.timelock)) gt.grantRole(gt.MINTER_ROLE(), ex.timelock);
        if (gt.hasRole(gt.MINTER_ROLE(), deployer) && ex.timelock != deployer) gt.renounceRole(gt.MINTER_ROLE(), deployer);
        if (gt.hasRole(0x00, deployer) && ex.timelock != deployer) gt.renounceRole(0x00, deployer);

        vm.stopBroadcast();

        _writeAddresses(ex);
    }

    function _loadExisting() internal view returns (Existing memory ex) {
        string memory json = vm.readFile(DEPLOYMENTS_PATH);
        ex.collateralToken = json.readAddress(".collateralToken");
        ex.outcomeToken    = json.readAddress(".outcomeToken");
        ex.oracleAdapter   = json.readAddress(".oracleAdapter");
        ex.feeVault        = json.readAddress(".feeVault");
        ex.governanceToken = json.readAddress(".governanceToken");
        ex.timelock        = json.readAddress(".timelock");
        ex.governor        = json.readAddress(".governor");
        ex.factoryProxy    = json.readAddress(".factoryProxy");
        ex.factoryImpl     = json.readAddress(".factoryImpl");
    }

    function _writeAddresses(Existing memory ex) internal {
        string memory k = "deployment";
        vm.serializeUint   (k, "chainId",         block.chainid);
        vm.serializeString (k, "chainName",       "Arbitrum Sepolia");
        vm.serializeAddress(k, "deployer",        msg.sender);
        vm.serializeUint   (k, "deployedAt",      block.timestamp);
        vm.serializeAddress(k, "collateralToken", ex.collateralToken);
        vm.serializeAddress(k, "outcomeToken",    ex.outcomeToken);
        vm.serializeAddress(k, "oracleAdapter",   ex.oracleAdapter);
        vm.serializeAddress(k, "feeVault",        ex.feeVault);
        vm.serializeAddress(k, "governanceToken", ex.governanceToken);
        vm.serializeAddress(k, "timelock",        ex.timelock);
        vm.serializeAddress(k, "governor",        ex.governor);
        vm.serializeAddress(k, "factoryImpl",     ex.factoryImpl);
        string memory json = vm.serializeAddress(k, "factoryProxy", ex.factoryProxy);
        vm.writeJson(json, DEPLOYMENTS_PATH);
        console2.log("Wrote", DEPLOYMENTS_PATH);
    }
}
