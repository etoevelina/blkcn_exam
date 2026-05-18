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

    /// @notice Can drive the state machine forward (lock/report/finalize).
    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");

    /// @notice Can pause / unpause trading + LP. Held by Timelock.
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

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

    IERC20 internal immutable _collateral;
    IOutcomeToken1155 internal immutable _outcome;
    IOracleAdapter internal immutable _oracle;
    address internal immutable _feeVault;

    bytes32 internal immutable _questionId;
    int256  internal immutable _oracleThreshold;
    uint64  internal immutable _marketId;
    uint256 internal immutable _yesId;
    uint256 internal immutable _noId;

    uint128 internal _reserveYes;
    uint128 internal _reserveNo;

    uint64  internal _tradingEndsAt;
    uint64  internal _disputeEndsAt;
    uint32  internal _disputeWindow;
    uint16  internal _feeBps;
    uint8   internal _statusByte;
    uint8   internal _winningOutcome;

    /// @notice Constructor parameter bundle to keep `new` calls readable.
    struct InitParams {
        IERC20 collateral;
        IOutcomeToken1155 outcomeToken;
        IOracleAdapter oracle;
        address feeVault;
        address admin;
        address keeper;
        uint64  marketId;
        bytes32 questionId;
        int256  oracleThreshold;
        uint64  tradingEndsAt;
        uint16  feeBps;
        uint32  disputeWindow;
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
        if (p.feeBps == 0 || p.feeBps > 1_000) revert ZeroAmount();
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

    function _requireStatus(Status required) internal view {
        if (Status(_statusByte) != required) revert InvalidState(Status(_statusByte), required);
    }

    function _requireDeadline(uint256 deadline) internal view {
        if (block.timestamp > deadline) revert DeadlineExpired(block.timestamp, deadline);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /// @inheritdoc IPredictionMarket
    function addLiquidity(uint256 collateralIn, uint256 minLpOut, uint256 deadline)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 lpMinted, uint256 yesLeftover, uint256 noLeftover)
    {
        _requireStatus(Status.Open);
        _requireDeadline(deadline);
        if (collateralIn == 0) revert ZeroAmount();

        uint256 ry = _reserveYes;
        uint256 rn = _reserveNo;
        uint256 yesAdd;
        uint256 noAdd;

        if (ry == 0 && rn == 0) {
            yesAdd = collateralIn;
            noAdd  = collateralIn;
            if (collateralIn <= MIN_LIQUIDITY) revert InsufficientLiquidity();
            unchecked {
                lpMinted = collateralIn - MIN_LIQUIDITY;
            }
        } else {
            if (ry >= rn) {
                yesAdd = collateralIn;
                noAdd  = (collateralIn * rn) / ry;
            } else {
                noAdd  = collateralIn;
                yesAdd = (collateralIn * ry) / rn;
            }
            uint256 supply = totalSupply();
            uint256 denom = ry >= rn ? ry : rn;
            lpMinted = (supply * collateralIn) / denom;
        }

        if (lpMinted == 0) revert InsufficientLiquidity();
        if (lpMinted < minLpOut) revert InsufficientOutputAmount(lpMinted, minLpOut);

        unchecked {
            yesLeftover = collateralIn - yesAdd;
            noLeftover  = collateralIn - noAdd;
        }

        _reserveYes = uint128(ry + yesAdd);
        _reserveNo  = uint128(rn + noAdd);

        if (ry == 0 && rn == 0) {
            _mint(address(0xdead), MIN_LIQUIDITY);
        }
        _mint(msg.sender, lpMinted);

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
        _requireDeadline(deadline);
        if (lpBurn == 0) revert ZeroAmount();

        uint256 supply = totalSupply();
        if (supply == 0) revert InsufficientLiquidity();

        uint256 ry = _reserveYes;
        uint256 rn = _reserveNo;
        yesOut = (ry * lpBurn) / supply;
        noOut  = (rn * lpBurn) / supply;

        if (yesOut < minYesOut) revert InsufficientOutputAmount(yesOut, minYesOut);
        if (noOut  < minNoOut)  revert InsufficientOutputAmount(noOut,  minNoOut);
        if (yesOut == 0 && noOut == 0) revert InsufficientLiquidity();

        _reserveYes = uint128(ry - yesOut);
        _reserveNo  = uint128(rn - noOut);
        _burn(msg.sender, lpBurn);

        if (yesOut > 0) {
            _outcome.safeTransferFrom(address(this), msg.sender, _yesId, yesOut, "");
        }
        if (noOut > 0) {
            _outcome.safeTransferFrom(address(this), msg.sender, _noId, noOut, "");
        }

        emit LiquidityRemoved(msg.sender, lpBurn, yesOut, noOut);
    }

    /// @inheritdoc IPredictionMarket
    function swap(uint256 outcomeIn, uint256 outcomeOut, uint256 amountIn, uint256 minOut, uint256 deadline)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 amountOut)
    {
        _requireStatus(Status.Open);
        _requireDeadline(deadline);
        if (amountIn == 0) revert ZeroAmount();
        if (outcomeIn == outcomeOut) revert SameOutcomeSwap();
        if (outcomeIn != _yesId && outcomeIn != _noId) revert InvalidOutcomeId(outcomeIn);
        if (outcomeOut != _yesId && outcomeOut != _noId) revert InvalidOutcomeId(outcomeOut);

        bool inIsYes = outcomeIn == _yesId;
        uint256 reserveIn  = inIsYes ? _reserveYes : _reserveNo;
        uint256 reserveOut = inIsYes ? _reserveNo  : _reserveYes;

        amountOut = _getAmountOut(amountIn, reserveIn, reserveOut);
        if (amountOut == 0) revert InsufficientOutputAmount(0, minOut);
        if (amountOut < minOut) revert InsufficientOutputAmount(amountOut, minOut);
        if (amountOut >= reserveOut) revert InsufficientLiquidity();

        uint256 newReserveIn  = reserveIn  + amountIn;
        uint256 newReserveOut = reserveOut - amountOut;

        uint256 kBefore = reserveIn * reserveOut;
        uint256 kAfter  = newReserveIn * newReserveOut;
        if (kAfter < kBefore) revert KInvariantBroken(kBefore, kAfter);

        if (inIsYes) {
            _reserveYes = uint128(newReserveIn);
            _reserveNo  = uint128(newReserveOut);
        } else {
            _reserveNo  = uint128(newReserveIn);
            _reserveYes = uint128(newReserveOut);
        }

        _outcome.safeTransferFrom(msg.sender, address(this), outcomeIn, amountIn, "");
        _outcome.safeTransferFrom(address(this), msg.sender, outcomeOut, amountOut, "");

        uint256 feePart = amountIn - ((amountIn * (BPS - _feeBps)) / BPS);
        emit Swap(msg.sender, outcomeIn, outcomeOut, amountIn, amountOut, feePart);
    }

    /// @inheritdoc IPredictionMarket
    function mintCompleteSets(uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) revert ZeroAmount();
        _requireStatus(Status.Open);

        _collateral.safeTransferFrom(msg.sender, address(this), amount);
        _outcome.mint(msg.sender, _yesId, amount);
        _outcome.mint(msg.sender, _noId,  amount);

        emit CompleteSetsMinted(msg.sender, amount);
    }

    /// @inheritdoc IPredictionMarket
    function redeemCompleteSets(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        Status s = Status(_statusByte);
        if (s == Status.Finalized || s == Status.Disputed) {
            revert InvalidState(s, Status.Open);
        }

        _outcome.burn(msg.sender, _yesId, amount);
        _outcome.burn(msg.sender, _noId,  amount);
        _collateral.safeTransfer(msg.sender, amount);

        emit CompleteSetsRedeemed(msg.sender, amount);
    }

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

    /// @inheritdoc IPredictionMarket
    function claimWinnings() external nonReentrant returns (uint256 collateralOut) {
        _requireStatus(Status.Finalized);
        uint8 winner = _winningOutcome;
        uint256 winningId = winner == OUTCOME_YES ? _yesId : _noId;

        uint256 bal = _outcome.balanceOf(msg.sender, winningId);
        if (bal == 0) revert NothingToClaim();

        _outcome.burn(msg.sender, winningId, bal);
        _collateral.safeTransfer(msg.sender, bal);

        collateralOut = bal;
        emit WinningsClaimed(msg.sender, bal, bal);
    }

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

    /// @dev Disambiguate the diamond inheritance of `supportsInterface`.
    ///      Solidity 0.8.20+ rejects interfaces in override lists, so we
    ///      enumerate only the concrete base contracts.
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(AccessControl, ERC1155Holder)
        returns (bool)
    {
        return AccessControl.supportsInterface(interfaceId) || ERC1155Holder.supportsInterface(interfaceId);
    }
}
