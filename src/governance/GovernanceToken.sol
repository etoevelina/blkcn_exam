// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title GovernanceToken — ERC20 + ERC20Votes + ERC20Permit, capped 100M
/// @author Daniyar (governance)
/// @notice
/// Single capped-supply governance token. Implements the full ERC20Votes
/// snapshot machinery so OpenZeppelin Governor can read voting power at
/// any past timestamp (clock-mode "timestamp" — see overrides below).
///
/// Mint is restricted to `MINTER_ROLE`, granted to the deployer at
/// genesis (to seed initial distribution) and then transferred to the
/// Timelock during the post-deploy wiring step.
contract GovernanceToken is ERC20, ERC20Permit, ERC20Votes, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /// @notice Maximum total supply. Mint reverts past this number.
    uint256 public constant CAP = 100_000_000e18;

    error CapExceeded(uint256 attempted, uint256 cap);

    constructor(address admin) ERC20("Prediction Governance", "PGOV") ERC20Permit("Prediction Governance") {
        if (admin == address(0)) revert CapExceeded(0, 0);
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
    }

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        if (totalSupply() + amount > CAP) revert CapExceeded(totalSupply() + amount, CAP);
        _mint(to, amount);
    }

    /// @dev L2 deployments need timestamp-mode clock because L2 block
    ///      production is variable; OZ Governor will reflect the same
    ///      mode through the inherited `clock()` lookup.
    function clock() public view override returns (uint48) {
        return uint48(block.timestamp);
    }

    function CLOCK_MODE() public pure override returns (string memory) {
        return "mode=timestamp";
    }

    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Votes) {
        super._update(from, to, value);
    }

    function nonces(address owner) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }
}
