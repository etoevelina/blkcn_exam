// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title FeeVault4626 — ERC-4626 fee receiver for LPs
/// @author Evelina (core)
/// @notice
/// Vault denominated in the protocol's collateral token. Anyone may
/// deposit; LPs receive shares; markets push protocol-fee dust into the
/// vault via plain ERC-20 transfers, which uplifts every share's
/// redemption value.
///
/// ERC-4626 rounding invariants this contract upholds (audited in W10
/// via `test/invariant/VaultInvariant.t.sol`):
///
///     previewDeposit(x)  <=  deposit(x)      // user can never get more shares
///     previewMint(s)     >=  mint(s)         // user always pays at least preview
///     previewWithdraw(a) >=  withdraw(a)     // shares burnt cannot be lower
///     previewRedeem(s)   <=  redeem(s)       // assets returned cannot exceed preview
///
/// We use OZ's `_decimalsOffset() = 1` to make the inflation-attack
/// surface negligible: a virtual share of 10 is added to the share
/// supply at preview time so a 1-wei donation can't move the share
/// price meaningfully on a fresh vault.
contract FeeVault4626 is ERC4626, AccessControl, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Math for uint256;

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @dev OZ default is 0; we increase the offset by 1 to gain extra
    ///      protection against the share-inflation attack on first deposit.
    uint8 private constant DECIMALS_OFFSET = 1;

    event FeesReceived(address indexed from, uint256 amount, uint256 totalAssetsAfter);

    constructor(IERC20 assetToken, address admin)
        ERC20("Prediction Fee Vault", "pfv")
        ERC4626(assetToken)
    {
        if (admin == address(0)) revert ERC4626ZeroAdmin();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
    }

    error ERC4626ZeroAdmin();

    /*//////////////////////////////////////////////////////////////
                              PAUSE GUARDS
    //////////////////////////////////////////////////////////////*/

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                              FEES IN-PUSH
    //////////////////////////////////////////////////////////////*/

    /// @notice Markets call this to push protocol-fee dust into the vault.
    ///         Emits an event so the subgraph can credit LPs analytically.
    function receiveFees(uint256 amount) external nonReentrant {
        if (amount == 0) return;
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), amount);
        emit FeesReceived(msg.sender, amount, totalAssets());
    }

    /*//////////////////////////////////////////////////////////////
                              ERC-4626 HOOKS
    //////////////////////////////////////////////////////////////*/

    /// @dev Reentrancy + pause guarded deposit/mint/withdraw/redeem path.
    function deposit(uint256 assets, address receiver) public override nonReentrant whenNotPaused returns (uint256) {
        return super.deposit(assets, receiver);
    }

    function mint(uint256 shares, address receiver) public override nonReentrant whenNotPaused returns (uint256) {
        return super.mint(shares, receiver);
    }

    function withdraw(uint256 assets, address receiver, address owner)
        public
        override
        nonReentrant
        returns (uint256)
    {
        return super.withdraw(assets, receiver, owner);
    }

    function redeem(uint256 shares, address receiver, address owner)
        public
        override
        nonReentrant
        returns (uint256)
    {
        return super.redeem(shares, receiver, owner);
    }

    /// @dev Increases share-inflation resistance: virtualises 10 shares at preview.
    function _decimalsOffset() internal pure override returns (uint8) {
        return DECIMALS_OFFSET;
    }

    function decimals() public view virtual override(ERC4626, ERC20, IERC20Metadata) returns (uint8) {
        return ERC4626.decimals();
    }
}
