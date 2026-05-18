// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

/// @title IOutcomeToken1155 — ERC-1155 outcome share token
/// @notice
/// One singleton ERC-1155 holds *all* outcome shares for *all* markets.
/// IDs are derived deterministically from the market id so no on-chain
/// mapping is required:
///
///     yesId(marketId) = marketId * 2
///     noId (marketId) = marketId * 2 + 1
///
/// Mint and burn of a given id are restricted to the holder of
/// `MARKET_MINTER_ROLE` for that id — which, by construction, is the
/// `PredictionMarket` instance that owns the corresponding marketId.
///
/// The interface deliberately does *not* expose any role-management
/// functions; those live on the concrete implementation under
/// AccessControl, gated by the factory.
interface IOutcomeToken1155 is IERC1155 {

    error NotMarketMinter(address caller, uint256 id);
    error MarketAlreadyRegistered(uint64 marketId);
    error InvalidMarket(address market);

    /// @notice Emitted when a new market is registered and granted
    ///         mint/burn authority over its YES/NO ids.
    event MarketRegistered(uint64 indexed marketId, address indexed market);

    /// @notice Emitted on `mint` (mirrors the ERC-1155 TransferSingle but
    ///         exposes the market id explicitly for indexers).
    event OutcomeMinted(uint64 indexed marketId, uint256 indexed id, address indexed to, uint256 amount);

    /// @notice Emitted on `burn`.
    event OutcomeBurned(uint64 indexed marketId, uint256 indexed id, address indexed from, uint256 amount);

    /// @notice Mint `amount` units of token `id` to `to`.
    /// @dev Reverts unless `msg.sender` holds the per-id `MARKET_MINTER_ROLE`.
    function mint(address to, uint256 id, uint256 amount) external;

    /// @notice Burn `amount` units of token `id` from `from`.
    /// @dev `from` must either be `msg.sender` or have approved
    ///      `msg.sender` via `setApprovalForAll`. Additionally the caller
    ///      must hold the per-id `MARKET_MINTER_ROLE`.
    function burn(address from, uint256 id, uint256 amount) external;

    /// @notice Bind a freshly deployed market to its YES/NO ids.
    /// @dev Callable only by `FACTORY_ROLE` (the `PredictionMarketFactory`
    ///      proxy). Reverts if the market id is already registered.
    function registerMarket(uint64 marketId, address market) external;

    /// @notice Derive the YES token id for a market.
    function yesIdOf(uint64 marketId) external pure returns (uint256);

    /// @notice Derive the NO token id for a market.
    function noIdOf(uint64 marketId) external pure returns (uint256);

    /// @notice Address of the market that owns a given token id, or
    ///         `address(0)` if the id is not registered yet.
    function marketOf(uint256 id) external view returns (address);
}
