// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title MockUSDC — testnet collateral with public faucet
/// @notice 6-decimal ERC-20 used as the protocol's collateral on
///         Arbitrum Sepolia. Anyone can mint up to `FAUCET_PER_CALL`
///         once per call (no rate limit on testnet — we keep it
///         simple). Admin can mint arbitrary amounts for fixture setup.
contract MockUSDC is ERC20, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    uint256 public constant FAUCET_PER_CALL = 10_000e6;

    constructor(address admin) ERC20("Mock USD Coin", "USDC") {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    /// @notice Anyone can call to top up their own balance on testnet.
    function faucet() external {
        _mint(msg.sender, FAUCET_PER_CALL);
    }
}
