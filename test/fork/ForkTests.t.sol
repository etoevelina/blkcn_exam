// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";

interface IAggregator {
    function decimals() external view returns (uint8);
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

interface IERC20Mini {
    function totalSupply() external view returns (uint256);
    function balanceOf(address) external view returns (uint256);
    function transfer(address, uint256) external returns (bool);
    function decimals() external view returns (uint8);
}

interface IUniswapV2Router02 {
    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts);
}

/// @notice Skipped automatically when no MAINNET_RPC_URL is configured.
contract ForkTests is Test {
    address constant USDC_MAINNET = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant CHAINLINK_BTCUSD = 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c;
    address constant UNIV2_ROUTER     = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    /// @dev Skip when no fork URL configured; lets CI run unit tests
    ///      without RPC credentials.
    modifier onMainnetFork() {
        string memory url = vm.envOr("MAINNET_RPC_URL", string(""));
        if (bytes(url).length == 0) {
            vm.skip(true);
            return;
        }
        vm.createSelectFork(url);
        _;
    }

    function test_fork_chainlinkBTCUSD_isFresh() public onMainnetFork {
        IAggregator feed = IAggregator(CHAINLINK_BTCUSD);
        (, int256 answer, , uint256 ts, ) = feed.latestRoundData();
        assertGt(answer, 0);
        assertLt(block.timestamp - ts, 1 days);
        assertEq(feed.decimals(), 8);
    }

    function test_fork_usdcSupply_isPositive() public onMainnetFork {
        IERC20Mini usdc = IERC20Mini(USDC_MAINNET);
        assertGt(usdc.totalSupply(), 0);
        assertEq(usdc.decimals(), 6);
    }

    function test_fork_uniswapV2Router_quotesETHforUSDC() public onMainnetFork {
        IUniswapV2Router02 router = IUniswapV2Router02(UNIV2_ROUTER);
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = USDC_MAINNET;
        uint256[] memory out = router.getAmountsOut(1 ether, path);
        assertGt(out[1], 100 * 1e6);
    }
}
