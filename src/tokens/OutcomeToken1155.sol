// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {IOutcomeToken1155} from "../interfaces/IOutcomeToken1155.sol";

/// @title OutcomeToken1155 — singleton ERC-1155 for binary-market YES/NO shares
/// @author Evelina (core)
/// @notice
/// One contract holds the outcome shares of every market deployed by the
/// `PredictionMarketFactory`. Token ids encode the market id:
///
///     yesId(marketId) = marketId * 2
///     noId (marketId) = marketId * 2 + 1
///
/// Mint and burn for a given id are restricted to the `PredictionMarket`
/// instance that owns the corresponding marketId (recorded once on
/// `registerMarket`). The factory holds `FACTORY_ROLE` and is the only
/// caller permitted to register new markets.
///
/// SECURITY MODEL — Slither / audit notes:
///   * `mint` / `burn` are sender-gated by an O(1) mapping lookup; no
///     looped iteration; gas is constant per id.
///   * `burn` deliberately does *not* check ERC-1155 approval, because
///     the registered market is a contract that itself reverts unless
///     the share holder explicitly called into it. This is documented
///     in the audit report (Trust Assumption T-3).
///   * No `tx.origin`, no `block.timestamp` in authorisation logic.
contract OutcomeToken1155 is ERC1155, AccessControl, IOutcomeToken1155 {

    /// @notice Granted to the `PredictionMarketFactory` (proxy address).
    ///         The factory is the only contract permitted to register
    ///         new markets.
    bytes32 public constant FACTORY_ROLE = keccak256("FACTORY_ROLE");

    /// @dev token id => market address authorised to mint/burn it.
    mapping(uint256 id => address market) private _marketOfId;
    /// @dev marketId => registered (true once and only once).
    mapping(uint64 marketId => bool registered) private _registered;

    /// @param admin    Timelock / DAO that owns role administration.
    /// @param baseUri  ERC-1155 base URI (e.g. "ipfs://.../{id}.json").
    constructor(address admin, string memory baseUri) ERC1155(baseUri) {
        if (admin == address(0)) revert InvalidMarket(address(0));
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /// @inheritdoc IOutcomeToken1155
    /// @dev Called by the factory once per market, atomically with the
    ///      market's deployment. Reverts on re-registration to make
    ///      "id squatting" impossible.
    function registerMarket(uint64 marketId_, address market) external onlyRole(FACTORY_ROLE) {
        if (market == address(0)) revert InvalidMarket(market);
        if (_registered[marketId_]) revert MarketAlreadyRegistered(marketId_);

        _registered[marketId_] = true;
        uint256 yId = yesIdOf(marketId_);
        uint256 nId = noIdOf(marketId_);
        _marketOfId[yId] = market;
        _marketOfId[nId] = market;

        emit MarketRegistered(marketId_, market);
    }

    /// @inheritdoc IOutcomeToken1155
    function mint(address to, uint256 id, uint256 amount) external {
        address market = _marketOfId[id];
        if (market != msg.sender) revert NotMarketMinter(msg.sender, id);

        _mint(to, id, amount, "");
        emit OutcomeMinted(uint64(id >> 1), id, to, amount);
    }

    /// @inheritdoc IOutcomeToken1155
    function burn(address from, uint256 id, uint256 amount) external {
        address market = _marketOfId[id];
        if (market != msg.sender) revert NotMarketMinter(msg.sender, id);

        _burn(from, id, amount);
        emit OutcomeBurned(uint64(id >> 1), id, from, amount);
    }

    /// @inheritdoc IOutcomeToken1155
    function yesIdOf(uint64 marketId_) public pure returns (uint256) {
        return uint256(marketId_) << 1;
    }

    /// @inheritdoc IOutcomeToken1155
    function noIdOf(uint64 marketId_) public pure returns (uint256) {
        return (uint256(marketId_) << 1) | 1;
    }

    /// @inheritdoc IOutcomeToken1155
    function marketOf(uint256 id) external view returns (address) {
        return _marketOfId[id];
    }

    /// @dev Multiple inheritance disambiguation for `supportsInterface`.
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC1155, AccessControl, IERC165)
        returns (bool)
    {
        return ERC1155.supportsInterface(interfaceId) || AccessControl.supportsInterface(interfaceId);
    }
}
