// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IOutcomeToken1155} from "./IOutcomeToken1155.sol";
import {IOracleAdapter} from "./IOracleAdapter.sol";

/// @title IPredictionMarket — binary outcome CPMM AMM
/// @notice
/// A single instance of this interface represents one binary market
/// (one question with two outcomes: YES and NO). Pricing is via a
/// constant-product AMM (`x · y = k`) on the two outcome reserves,
/// charging a 0.3% LP fee.
///
/// LPs deposit ERC-20 collateral. Internally the contract mints equal
/// amounts of YES + NO shares (a "complete set") into its own reserves
/// and issues a transferable ERC-20 LP token (`PLP`) to the depositor.
///
/// Outcomes are *not* upgradeable: each market is its own contract,
/// deployed by the `PredictionMarketFactory` (via `CREATE` or `CREATE2`),
/// and its parameters are immutable for the lifetime of the market.
///
/// STORAGE LAYOUT — see `docs/ARCHITECTURE.md` §5.1 for the exhaustive
/// slot-by-slot table. The relevant inheritance is:
///
///   ERC20 (LP token) → Pausable → AccessControl → ReentrancyGuard →
///   ERC1155Holder → PredictionMarket
///
/// All admin functions are protected by `DEFAULT_ADMIN_ROLE`, which is
/// held by the protocol Timelock. Keepers hold `KEEPER_ROLE` and can
/// only drive the state machine forward — they cannot withdraw value.
interface IPredictionMarket {

    /// @notice Lifecycle states. Transitions are strictly one-way except
    ///         `Reported → Disputed` and `Disputed → Reported` (during
    ///         governance review).
    enum Status {
        Open,
        Locked,
        Reported,
        Disputed,
        Finalized,
        Invalid
    }

    error InvalidState(Status current, Status required);
    error DeadlineExpired(uint256 nowTs, uint256 deadline);
    error ZeroAmount();
    error InsufficientLiquidity();
    error InsufficientOutputAmount(uint256 got, uint256 minOut);
    error ExcessiveInputAmount(uint256 paid, uint256 maxIn);
    error InvalidOutcomeId(uint256 id);
    error SameOutcomeSwap();
    error TradingNotEnded(uint256 nowTs, uint256 endsAt);
    error DisputeWindowActive(uint256 nowTs, uint256 endsAt);
    error DisputeWindowOver(uint256 nowTs, uint256 endsAt);
    error NothingToClaim();
    error KInvariantBroken(uint256 kBefore, uint256 kAfter);

    event LiquidityAdded(
        address indexed provider,
        uint256 collateralIn,
        uint256 yesAdded,
        uint256 noAdded,
        uint256 lpMinted
    );

    event LiquidityRemoved(
        address indexed provider,
        uint256 lpBurnt,
        uint256 yesOut,
        uint256 noOut
    );

    event Swap(
        address indexed trader,
        uint256 indexed outcomeIn,
        uint256 indexed outcomeOut,
        uint256 amountIn,
        uint256 amountOut,
        uint256 feeAccrued
    );

    event CompleteSetsMinted(address indexed user, uint256 amount);
    event CompleteSetsRedeemed(address indexed user, uint256 amount);

    event MarketLocked(uint64 lockedAt);
    event OutcomeReported(uint8 indexed outcome, uint64 reportedAt, uint64 disputeEndsAt);
    event DisputeRaised(address indexed by, uint64 raisedAt);
    event DisputeResolved(uint8 indexed finalOutcome, address indexed by);
    event MarketFinalized(uint8 indexed winningOutcome);
    event MarketInvalidated(address indexed by, string reason);
    event WinningsClaimed(address indexed user, uint256 sharesBurnt, uint256 collateralOut);

    /// @notice Deposit `collateralIn` collateral, mint equal YES + NO,
    ///         add them to reserves at the current pool ratio, mint LP
    ///         shares to `msg.sender`. Returns the imbalance shares
    ///         (YES or NO leftover) to `msg.sender`.
    /// @param collateralIn  Amount of ERC-20 collateral to deposit.
    /// @param minLpOut      Slippage protection. Reverts on `lpMinted < minLpOut`.
    /// @param deadline      `block.timestamp` upper bound.
    function addLiquidity(uint256 collateralIn, uint256 minLpOut, uint256 deadline)
        external
        returns (uint256 lpMinted, uint256 yesLeftover, uint256 noLeftover);

    /// @notice Burn LP shares, withdraw a proportional amount of the
    ///         YES + NO reserves.
    /// @param lpBurn      Amount of LP token to burn.
    /// @param minYesOut   Slippage protection.
    /// @param minNoOut    Slippage protection.
    /// @param deadline    `block.timestamp` upper bound.
    function removeLiquidity(uint256 lpBurn, uint256 minYesOut, uint256 minNoOut, uint256 deadline)
        external
        returns (uint256 yesOut, uint256 noOut);

    /// @notice Swap one outcome for the other through the CPMM.
    /// @param outcomeIn   Token id being sold.
    /// @param outcomeOut  Token id being bought.
    /// @param amountIn    Amount of `outcomeIn` sold.
    /// @param minOut      Slippage protection. Reverts on `out < minOut`.
    /// @param deadline    `block.timestamp` upper bound.
    function swap(uint256 outcomeIn, uint256 outcomeOut, uint256 amountIn, uint256 minOut, uint256 deadline)
        external
        returns (uint256 amountOut);

    /// @notice Mint a complete set: deposit `amount` collateral, receive
    ///         `amount` YES + `amount` NO. Does not interact with the AMM.
    function mintCompleteSets(uint256 amount) external;

    /// @notice Inverse of `mintCompleteSets`: burn equal YES + NO, get
    ///         back `amount` collateral.
    function redeemCompleteSets(uint256 amount) external;

    /// @notice Anyone may call after `tradingEndsAt`. Transitions Open → Locked.
    function lockMarket() external;

    /// @notice Trigger oracle resolution. Transitions Locked → Reported.
    function reportOutcome() external;

    /// @notice Open a dispute. Requires `DEFAULT_ADMIN_ROLE` (Timelock).
    function disputeOutcome() external;

    /// @notice Governance overrides the reported outcome. Disputed → Finalized.
    function resolveDispute(uint8 finalOutcome) external;

    /// @notice After dispute window elapses without dispute. Reported → Finalized.
    function finalize() external;

    /// @notice Void the market (refunds complete sets 1:1). Admin-gated.
    function setInvalid(string calldata reason) external;

    /// @notice Burn the caller's winning shares, send 1:1 collateral.
    ///         Available only in `Finalized` state. Each share of the
    ///         winning outcome redeems for 1 unit of collateral.
    function claimWinnings() external returns (uint256 collateralOut);

    function reserves() external view returns (uint128 reserveYes, uint128 reserveNo);
    function status() external view returns (Status);
    function yesId() external view returns (uint256);
    function noId() external view returns (uint256);
    function marketId() external view returns (uint64);
    function tradingEndsAt() external view returns (uint64);
    function disputeEndsAt() external view returns (uint64);
    function winningOutcome() external view returns (uint8);
    function feeBps() external view returns (uint16);
    function collateralToken() external view returns (IERC20);
    function outcomeToken() external view returns (IOutcomeToken1155);
    function oracleAdapter() external view returns (IOracleAdapter);
    function questionId() external view returns (bytes32);

    /// @notice Compute the CPMM output for a given input + reserves.
    ///         Pure helper used both internally and by the frontend.
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        external
        view
        returns (uint256 amountOut);
}
