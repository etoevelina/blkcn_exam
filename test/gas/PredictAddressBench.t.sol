// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, console2} from "forge-std/Test.sol";
import {Fixture} from "../helpers/Fixture.sol";

/// @notice Side-by-side gas benchmark for the Yul implementation of
///         `predictMarketAddress` vs the Solidity baseline. Used to
///         populate `docs/GAS.md §1`.
///
/// Run with:
///   forge test --match-path test/gas/PredictAddressBench.t.sol -vvv --gas-report
contract PredictAddressBench is Fixture {
    bytes32 internal constant SAMPLE_SALT = bytes32(uint256(0xC0FFEE));
    bytes32 internal constant SAMPLE_HASH = keccak256("benchmark-init-code");

    function test_bench_yulPredict() public view {
        uint256 g0 = gasleft();
        factory.predictMarketAddress(SAMPLE_SALT, SAMPLE_HASH);
        uint256 used = g0 - gasleft();
        console2.log("Yul predictMarketAddress gas (incl. call):", used);
    }

    function test_bench_solidityPredict() public view {
        uint256 g0 = gasleft();
        factory.predictMarketAddressSolidity(SAMPLE_SALT, SAMPLE_HASH);
        uint256 used = g0 - gasleft();
        console2.log("Solidity predictMarketAddressSolidity gas (incl. call):", used);
    }

    function test_bench_savings_comparison() public view {
        uint256 g0 = gasleft();
        factory.predictMarketAddress(SAMPLE_SALT, SAMPLE_HASH);
        uint256 yul = g0 - gasleft();

        uint256 g1 = gasleft();
        factory.predictMarketAddressSolidity(SAMPLE_SALT, SAMPLE_HASH);
        uint256 sol = g1 - gasleft();

        console2.log("Yul gas:     ", yul);
        console2.log("Solidity gas:", sol);
    }
}
