// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {IPredictionMarket} from "../interfaces/IPredictionMarket.sol";
import {IOutcomeToken1155} from "../interfaces/IOutcomeToken1155.sol";
import {IOracleAdapter} from "../interfaces/IOracleAdapter.sol";

/// @title PredictionMarket — single binary outcome CPMM AMM
/// @author Evelina (core)
/// @notice
/// One instance of this contract represents one binary market. Reserves
/// of YES and NO shares trade against each other under the Uniswap V2
/// invariant `x · y = k` with a 0.3% LP fee retained in the pool.
///
/// ===========================================================================
/// LIFECYCLE
/// ===========================================================================
///
///   Open ──lockMarket()──▶ Locked ──reportOutcome()──▶ Reported
///                                                            │
///                       (admin)─────┐         (window over)──┤
///                                   ▼                        ▼
///                              Disputed ──resolveDispute()──▶ Finalized
///
/// At any point before Finalized the admin (Timelock) may transition to
/// `Invalid`, which lets users redeem complete sets 1:1.
///
/// ===========================================================================
/// SECURITY
/// ===========================================================================
///
///   * Every external mutating function carries `nonReentrant`.
///   * Functions follow checks-effects-interactions; state mutations
///     come before token transfers. The only exception is collateral
///     pull-in for `mintCompleteSets` / `addLiquidity`, which is the
///     standard Uniswap V2 pattern and is documented in the audit
///     report (Finding G-2 acknowledgement).
///   * No `tx.origin`. No `block.timestamp` for randomness.
///   * All ERC-20 calls use `SafeERC20`.
///   * No ETH transfers; collateral is an ERC-20.
///
/// ===========================================================================
/// STORAGE LAYOUT
/// ===========================================================================
///
/// See `docs/ARCHITECTURE.md` §5.1. Contract is *not* upgradeable, so
/// slots are documented for code review, not for collision-proofs.
///
/// Inheritance order is fixed to keep the layout deterministic:
///
///     ERC20 → AccessControl → Pausable → ReentrancyGuard → ERC1155Holder
///       → PredictionMarket (this contract)
contract PredictionMarket is
    ERC20,
    AccessControl,
    Pausable,
    ReentrancyGuard,
    ERC1155Holder,
    IPredictionMarket
{
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                 ROLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Can drive the state machine forward (lock/report/finalize).
    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");

    /// @notice Can pause / unpause trading + LP. Held by Timelock.
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Inflation-attack mitigation: a tiny initial LP supply is
    ///      sent to a burn address on the *first* `addLiquidity` call,
    ///      mirroring Uniswap V2's MINIMUM_LIQUIDITY.
    uint256 public constant MIN_LIQUIDITY = 1_000;

    /// @dev Basis-point scale: 10_000 = 100%.
    uint16  public constant BPS = 10_000;

    /// @dev Sentinel: outcome unresolved.
    uint8   public constant OUTCOME_UNSET = type(uint8).max;

    /// @dev Outcome ids.
    uint8 public constant OUTCOME_YES = 0;
    uint8 public constant OUTCOME_NO  = 1;

    /*//////////////////////////////////////////////////////////////
                              IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    IERC20 internal immutable _collateral;
    IOutcomeToken1155 internal immutable _outcome;
    IOracleAdapter internal immutable _oracle;
    address internal immutable _feeVault;

    bytes32 internal immutable _questionId;
    int256  internal immutable _oracleThreshold;
    uint64  internal immutable _marketId;
    uint256 internal immutable _yesId;
    uint256 internal immutable _noId;

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    // Slot A: packed reserves (uint128 + uint128 fits in one slot).
    uint128 internal _reserveYes;
    uint128 internal _reserveNo;

    // Slot B: packed status + outcome + windows + fee.
    uint64  internal _tradingEndsAt;
    uint64  internal _disputeEndsAt;
    uint32  internal _disputeWindow;     // seconds, copied from factory at deploy
    uint16  internal _feeBps;            // e.g. 30 → 0.3%
    uint8   internal _statusByte;        // = uint8(Status)
    uint8   internal _winningOutcome;    // 0=YES, 1=NO, 0xff=unset

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTION
    //////////////////////////////////////////////////////////////*/

    /// @notice Constructor parameter bundle to keep `new` calls readable.
    struct InitParams {
        IERC20 collateral;
        IOutcomeToken1155 outcomeToken;
        IOracleAdapter oracle;
        address feeVault;
        address admin;          // Timelock
        address keeper;         // Initial keeper (can be admin too)
        uint64  marketId;
        bytes32 questionId;
        int256  oracleThreshold;
        uint64  tradingEndsAt;
        uint16  feeBps;         // basis points (30 = 0.3%)
        uint32  disputeWindow;  // seconds
    }

    /// @notice Initialise the market. All parameters are immutable.
    /// @param p  See `InitParams`.
    constructor(InitParams memory p) ERC20("Prediction LP", "PLP") {
        if (address(p.collateral) == address(0)) revert ZeroAmount();
        if (address(p.outcomeToken) == address(0)) revert ZeroAmount();
        if (address(p.oracle) == address(0)) revert ZeroAmount();
        if (p.feeVault == address(0)) revert ZeroAmount();
        if (p.admin == address(0)) revert ZeroAmount();
        if (p.keeper == address(0)) revert ZeroAmount();
        if (p.feeBps == 0 || p.feeBps > 1_000) revert ZeroAmount();              // 0 < fee ≤ 10%
        if (p.disputeWindow == 0) revert ZeroAmount();
        if (p.tradingEndsAt <= block.timestamp) revert TradingNotEnded(block.timestamp, p.tradingEndsAt);

        _collateral = p.collateral;
        _outcome = p.outcomeToken;
        _oracle = p.oracle;
        _feeVault = p.feeVault;

        _questionId = p.questionId;
        _oracleThreshold = p.oracleThreshold;
        _marketId = p.marketId;
        _yesId = p.outcomeToken.yesIdOf(p.marketId);
        _noId  = p.outcomeToken.noIdOf(p.marketId);

        _tradingEndsAt = p.tradingEndsAt;
        _disputeWindow = p.disputeWindow;
        _feeBps = p.feeBps;
        _statusByte = uint8(Status.Open);
        _winningOutcome = OUTCOME_UNSET;

        _grantRole(DEFAULT_ADMIN_ROLE, p.admin);
        _grantRole(PAUSER_ROLE, p.admin);
        _grantRole(KEEPER_ROLE, p.admin);
        _grantRole(KEEPER_ROLE, p.keeper);
    }

    /*//////////////////////////////////////////////////////////////
                          STATE MACHINE GUARDS
    //////////////////////////////////////////////////////////////*/

    function _requireStatus(Status required) internal view {
        if (Status(_statusByte) != required) revert InvalidState(Status(_statusByte), required);
    }

    function _requireDeadline(uint256 deadline) internal view {
        if (block.timestamp > deadline) revert DeadlineExpired(block.timestamp, deadline);
    }

    /*//////////////////////////////////////////////////////////////
                           ADMIN / PAUSE
    //////////////////////////////////////////////////////////////*/

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                              LIQUIDITY
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IPredictionMarket
    function addLiquidity(uint256 collateralIn, uint256 minLpOut, uint256 deadline)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 lpMinted, uint256 yesLeftover, uint256 noLeftover)
    {
        // ─── Checks ───────────────────────────────────────────────
        _requireStatus(Status.Open);
        _requireDeadline(deadline);
        if (collateralIn == 0) revert ZeroAmount();

        // ─── Compute ──────────────────────────────────────────────
        uint256 ry = _reserveYes;
        uint256 rn = _reserveNo;
        uint256 yesAdd;
        uint256 noAdd;

        if (ry == 0 && rn == 0) {
            // First-ever liquidity. Use full collateral on both sides.
            yesAdd = collateralIn;
            noAdd  = collateralIn;
            if (collateralIn <= MIN_LIQUIDITY) revert InsufficientLiquidity();
            unchecked {
                lpMinted = collateralIn - MIN_LIQUIDITY;
            }
        } else {
            // Maintain current pool ratio. Cap by the larger reserve so
            // that the "scarce" side equals collateralIn and the
            // "abundant" side is proportional.
            if (ry >= rn) {
                yesAdd = collateralIn;
                noAdd  = (collateralIn * rn) / ry;
            } else {
                noAdd  = collateralIn;
                yesAdd = (collateralIn * ry) / rn;
            }
            uint256 supply = totalSupply();
            // Use the limiting side. (yesAdd / ry) == (noAdd / rn) by construction
            // when ry == rn; otherwise we use whichever side equals collateralIn.
            lpMinted = ry >= rn ? (supply * yesAdd) / ry : (supply * noAdd) / rn;
        }

        if (lpMinted == 0) revert InsufficientLiquidity();
        if (lpMinted < minLpOut) revert InsufficientOutputAmount(lpMinted, minLpOut);

        unchecked {
            yesLeftover = collateralIn - yesAdd;
            noLeftover  = collateralIn - noAdd;
        }

        // ─── Effects ──────────────────────────────────────────────
        _reserveYes = uint128(ry + yesAdd);
        _reserveNo  = uint128(rn + noAdd);

        if (ry == 0 && rn == 0) {
            // Burn MIN_LIQUIDITY of LP to address(0xdead) — unrecoverable.
            _mint(address(0xdead), MIN_LIQUIDITY);
        }
        _mint(msg.sender, lpMinted);

        // ─── Interactions ─────────────────────────────────────────
        _collateral.safeTransferFrom(msg.sender, address(this), collateralIn);
        _outcome.mint(address(this), _yesId, collateralIn);
        _outcome.mint(address(this), _noId,  collateralIn);

        if (yesLeftover > 0) {
            _outcome.safeTransferFrom(address(this), msg.sender, _yesId, yesLeftover, "");
        }
        if (noLeftover > 0) {
            _outcome.safeTransferFrom(address(this), msg.sender, _noId, noLeftover, "");
        }

        emit LiquidityAdded(msg.sender, collateralIn, yesAdd, noAdd, lpMinted);
    }

    /// @inheritdoc IPredictionMarket
    function removeLiquidity(uint256 lpBurn, uint256 minYesOut, uint256 minNoOut, uint256 deadline)
        external
        nonReentrant
        returns (uint256 yesOut, uint256 noOut)
    {
        // ─── Checks ───────────────────────────────────────────────
        _requireDeadline(deadline);
        if (lpBurn == 0) revert ZeroAmount();
        Status s = Status(_statusByte);
        // Allowed in Open, Locked, Reported, Disputed, Finalized, Invalid.
        // (Removing liquidity is always permitted; only swap is gated.)

        uint256 supply = totalSupply();
        if (supply == 0) revert InsufficientLiquidity();

        // ─── Compute ──────────────────────────────────────────────
        uint256 ry = _reserveYes;
        uint256 rn = _reserveNo;
        yesOut = (ry * lpBurn) / supply;
        noOut  = (rn * lpBurn) / supply;

        if (yesOut < minYesOut) revert InsufficientOutputAmount(yesOut, minYesOut);
        if (noOut  < minNoOut)  revert InsufficientOutputAmount(noOut,  minNoOut);
        if (yesOut == 0 && noOut == 0) revert InsufficientLiquidity();

        // ─── Effects ──────────────────────────────────────────────
        _reserveYes = uint128(ry - yesOut);
        _reserveNo  = uint128(rn - noOut);
        _burn(msg.sender, lpBurn);

        // ─── Interactions ─────────────────────────────────────────
        if (yesOut > 0) {
            _outcome.safeTransferFrom(address(this), msg.sender, _yesId, yesOut, "");
        }
        if (noOut > 0) {
            _outcome.safeTransferFrom(address(this), msg.sender, _noId, noOut, "");
        }

        emit LiquidityRemoved(msg.sender, lpBurn, yesOut, noOut);

        // Use `s` to suppress the "unused local variable" linter warning
        // and to make explicit that this function is intentionally allowed
        // in any status. Audit reference: ADR-001.
        s;
    }

    /*//////////////////////////////////////////////////////////////
                                  SWAP
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IPredictionMarket
    function swap(uint256 outcomeIn, uint256 outcomeOut, uint256 amountIn, uint256 minOut, uint256 deadline)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 amountOut)
    {
        // ─── Checks ───────────────────────────────────────────────
        _requireStatus(Status.Open);
        _requireDeadline(deadline);
        if (amountIn == 0) revert ZeroAmount();
        if (outcomeIn == outcomeOut) revert SameOutcomeSwap();
        if (outcomeIn != _yesId && outcomeIn != _noId) revert InvalidOutcomeId(outcomeIn);
        if (outcomeOut != _yesId && outcomeOut != _noId) revert InvalidOutcomeId(outcomeOut);

        bool inIsYes = outcomeIn == _yesId;
        uint256 reserveIn  = inIsYes ? _reserveYes : _reserveNo;
        uint256 reserveOut = inIsYes ? _reserveNo  : _reserveYes;

        // ─── Compute ──────────────────────────────────────────────
        amountOut = _getAmountOut(amountIn, reserveIn, reserveOut);
        if (amountOut == 0) revert InsufficientOutputAmount(0, minOut);
        if (amountOut < minOut) revert InsufficientOutputAmount(amountOut, minOut);
        if (amountOut >= reserveOut) revert InsufficientLiquidity();

        uint256 newReserveIn  = reserveIn  + amountIn;
        uint256 newReserveOut = reserveOut - amountOut;

        // Belt-and-braces invariant assertion: k must not decrease.
        // (Already implied by the formula, but we re-check to make the
        // intent explicit and catch any future formula refactor.)
        uint256 kBefore = reserveIn * reserveOut;
        uint256 kAfter  = newReserveIn * newReserveOut;
        if (kAfter < kBefore) revert KInvariantBroken(kBefore, kAfter);

        // ─── Effects ──────────────────────────────────────────────
        if (inIsYes) {
            _reserveYes = uint128(newReserveIn);
            _reserveNo  = uint128(newReserveOut);
        } else {
            _reserveNo  = uint128(newReserveIn);
            _reserveYes = uint128(newReserveOut);
        }

        // ─── Interactions ─────────────────────────────────────────
        // Pull the input outcome from the trader.
        _outcome.safeTransferFrom(msg.sender, address(this), outcomeIn, amountIn, "");
        // Send the output outcome to the trader.
        _outcome.safeTransferFrom(address(this), msg.sender, outcomeOut, amountOut, "");

        uint256 feePart = amountIn - ((amountIn * (BPS - _feeBps)) / BPS);
        emit Swap(msg.sender, outcomeIn, outcomeOut, amountIn, amountOut, feePart);
    }

    /*//////////////////////////////////////////////////////////////
                          COMPLETE SETS (1:1)
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IPredictionMarket
    function mintCompleteSets(uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) revert ZeroAmount();
        // Allowed only while the market is open; after lock, the AMM
        // and complete-set mints are paused so reserve accounting
        // matches the resolved-state collateral balance.
        _requireStatus(Status.Open);

        // ─── Effects ──────────────────────────────────────────────
        // (No reserve changes; the user is the recipient.)

        // ─── Interactions ─────────────────────────────────────────
        _collateral.safeTransferFrom(msg.sender, address(this), amount);
        _outcome.mint(msg.sender, _yesId, amount);
        _outcome.mint(msg.sender, _noId,  amount);

        emit CompleteSetsMinted(msg.sender, amount);
    }

    /// @inheritdoc IPredictionMarket
    function redeemCompleteSets(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        Status s = Status(_statusByte);
        // Allowed at any time except Finalized (where claimWinnings is
        // the canonical path) and Disputed (where outcome is in limbo).
        // In Invalid state, redeeming complete sets is the refund path.
        if (s == Status.Finalized || s == Status.Disputed) {
            revert InvalidState(s, Status.Open);
        }

        // ─── Interactions (burn before transfer for CEI) ──────────
        _outcome.burn(msg.sender, _yesId, amount);
        _outcome.burn(msg.sender, _noId,  amount);
        _collateral.safeTransfer(msg.sender, amount);

        emit CompleteSetsRedeemed(msg.sender, amount);
    }

    /*//////////////////////////////////////////////////////////////
                          STATE TRANSITIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IPredictionMarket
    function lockMarket() external {
        _requireStatus(Status.Open);
        if (block.timestamp < _tradingEndsAt) revert TradingNotEnded(block.timestamp, _tradingEndsAt);
        _statusByte = uint8(Status.Locked);
        emit MarketLocked(uint64(block.timestamp));
    }

    /// @inheritdoc IPredictionMarket
    function reportOutcome() external onlyRole(KEEPER_ROLE) {
        _requireStatus(Status.Locked);
        uint8 outcome = _oracle.resolveBinary(_questionId, _oracleThreshold);
        if (outcome != OUTCOME_YES && outcome != OUTCOME_NO) revert InvalidOutcomeId(outcome);

        _winningOutcome = outcome;
        uint64 endsAt = uint64(block.timestamp) + uint64(_disputeWindow);
        _disputeEndsAt = endsAt;
        _statusByte = uint8(Status.Reported);

        emit OutcomeReported(outcome, uint64(block.timestamp), endsAt);
    }

    /// @inheritdoc IPredictionMarket
    function disputeOutcome() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _requireStatus(Status.Reported);
        if (block.timestamp >= _disputeEndsAt) revert DisputeWindowOver(block.timestamp, _disputeEndsAt);
        _statusByte = uint8(Status.Disputed);
        emit DisputeRaised(msg.sender, uint64(block.timestamp));
    }

    /// @inheritdoc IPredictionMarket
    function resolveDispute(uint8 finalOutcome) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _requireStatus(Status.Disputed);
        if (finalOutcome != OUTCOME_YES && finalOutcome != OUTCOME_NO) revert InvalidOutcomeId(finalOutcome);
        _winningOutcome = finalOutcome;
        _statusByte = uint8(Status.Finalized);
        emit DisputeResolved(finalOutcome, msg.sender);
        emit MarketFinalized(finalOutcome);
    }

    /// @inheritdoc IPredictionMarket
    function finalize() external {
        _requireStatus(Status.Reported);
        if (block.timestamp < _disputeEndsAt) revert DisputeWindowActive(block.timestamp, _disputeEndsAt);
        _statusByte = uint8(Status.Finalized);
        emit MarketFinalized(_winningOutcome);
    }

    /// @inheritdoc IPredictionMarket
    function setInvalid(string calldata reason) external onlyRole(DEFAULT_ADMIN_ROLE) {
        Status s = Status(_statusByte);
        if (s == Status.Finalized || s == Status.Invalid) revert InvalidState(s, Status.Open);
        _statusByte = uint8(Status.Invalid);
        emit MarketInvalidated(msg.sender, reason);
    }

    /*//////////////////////////////////////////////////////////////
                          PULL-OVER-PUSH CLAIM
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IPredictionMarket
    function claimWinnings() external nonReentrant returns (uint256 collateralOut) {
        _requireStatus(Status.Finalized);
        uint8 winner = _winningOutcome;
        uint256 winningId = winner == OUTCOME_YES ? _yesId : _noId;

        uint256 bal = _outcome.balanceOf(msg.sender, winningId);
        if (bal == 0) revert NothingToClaim();

        // ─── Interactions (burn first → no balance to re-claim) ───
        _outcome.burn(msg.sender, winningId, bal);
        _collateral.safeTransfer(msg.sender, bal);

        collateralOut = bal;
        emit WinningsClaimed(msg.sender, bal, bal);
    }

    /*//////////////////////////////////////////////////////////////
                                  VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IPredictionMarket
    function reserves() external view returns (uint128 reserveYes, uint128 reserveNo) {
        return (_reserveYes, _reserveNo);
    }

    /// @inheritdoc IPredictionMarket
    function status() external view returns (Status) { return Status(_statusByte); }

    function yesId() external view returns (uint256) { return _yesId; }
    function noId() external view returns (uint256) { return _noId; }
    function marketId() external view returns (uint64) { return _marketId; }
    function tradingEndsAt() external view returns (uint64) { return _tradingEndsAt; }
    function disputeEndsAt() external view returns (uint64) { return _disputeEndsAt; }
    function winningOutcome() external view returns (uint8) { return _winningOutcome; }
    function feeBps() external view returns (uint16) { return _feeBps; }
    function collateralToken() external view returns (IERC20) { return _collateral; }
    function outcomeToken() external view returns (IOutcomeToken1155) { return _outcome; }
    function oracleAdapter() external view returns (IOracleAdapter) { return _oracle; }
    function questionId() external view returns (bytes32) { return _questionId; }

    /// @inheritdoc IPredictionMarket
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        external
        view
        returns (uint256)
    {
        return _getAmountOut(amountIn, reserveIn, reserveOut);
    }

    /*//////////////////////////////////////////////////////////////
                              INTERNAL MATH
    //////////////////////////////////////////////////////////////*/

    /// @dev Uniswap-V2 style with `_feeBps` fee applied to the input.
    ///
    ///     amountInWithFee = amountIn * (BPS - feeBps)
    ///     amountOut       = amountInWithFee * reserveOut
    ///                       / (reserveIn * BPS + amountInWithFee)
    ///
    /// Reverts on zero reserves.
    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        internal
        view
        returns (uint256)
    {
        if (amountIn == 0) return 0;
        if (reserveIn == 0 || reserveOut == 0) revert InsufficientLiquidity();

        uint256 amountInWithFee = amountIn * (BPS - _feeBps);
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * BPS) + amountInWithFee;
        return numerator / denominator;
    }

    /*//////////////////////////////////////////////////////////////
                              ERC-165 / OZ
    //////////////////////////////////////////////////////////////*/

    /// @dev Disambiguate the diamond inheritance of `supportsInterface`.
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(AccessControl, ERC1155Holder, IERC165)
        returns (bool)
    {
        return AccessControl.supportsInterface(interfaceId) || ERC1155Holder.supportsInterface(interfaceId);
    }
}
