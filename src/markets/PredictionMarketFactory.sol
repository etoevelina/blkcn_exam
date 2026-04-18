// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import {PredictionMarket} from "./PredictionMarket.sol";
import {IPredictionMarketFactory} from "../interfaces/IPredictionMarketFactory.sol";
import {IOutcomeToken1155} from "../interfaces/IOutcomeToken1155.sol";
import {IOracleAdapter} from "../interfaces/IOracleAdapter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title PredictionMarketFactory — UUPS proxy that mints new markets
/// @author Evelina (core)
/// @notice
/// Single source of new `PredictionMarket` contracts. Supports both
/// `CREATE` (auto-incrementing market id, address known only after
/// deploy) and `CREATE2` (caller-chosen salt → deterministic address).
///
/// The factory is itself upgradeable (UUPS). It uses ERC-7201
/// namespaced storage so that adding state in V2/V3/… cannot collide
/// with V1 layout.
///
/// ===========================================================================
/// INLINE YUL
/// ===========================================================================
///
/// `predictMarketAddress` is implemented in 5 lines of Yul. It computes
/// `address(uint160(uint256(keccak256(0xff ‖ factory ‖ salt ‖ initCodeHash))))`
/// without a Solidity `abi.encodePacked` call. A pure-Solidity baseline
/// is supplied (`predictMarketAddressSolidity`) for the W7 gas
/// benchmark required by the spec (§3.1).
///
/// ===========================================================================
/// ACCESS CONTROL
/// ===========================================================================
///
///   * `DEFAULT_ADMIN_ROLE` — Timelock. Grants/revokes roles, calls
///     `_authorizeUpgrade`, updates defaults.
///   * `MARKET_CREATOR_ROLE` — Governor (or, after W9, anyone if the DAO
///     votes to open up creation). Holds the right to call `createMarket`
///     and `createMarketDeterministic`.
contract PredictionMarketFactory is
    Initializable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    IPredictionMarketFactory
{
    /*//////////////////////////////////////////////////////////////
                                 ROLES
    //////////////////////////////////////////////////////////////*/

    /// @notice May spawn new markets. Initially granted to the Timelock
    ///         so only successful governance proposals create markets;
    ///         the DAO can grant this role more broadly later.
    bytes32 public constant MARKET_CREATOR_ROLE = keccak256("MARKET_CREATOR_ROLE");

    /*//////////////////////////////////////////////////////////////
                          ERC-7201 NAMESPACED STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @custom:storage-location erc7201:prediction.market.factory.main
    struct FactoryStorage {
        address protocolAdmin;     // Timelock — set as admin/keeper on every minted market
        address oracleAdapter;     // wraps Chainlink
        address feeVault;          // ERC-4626 fee receiver
        address outcomeToken;      // singleton ERC-1155
        address collateralToken;   // e.g. USDC
        uint64  nextMarketId;
        uint16  defaultFeeBps;
        uint32  defaultDisputeWindow; // seconds
        mapping(uint64 => address) marketById;
        mapping(address => uint64) idByMarket;
    }

    /// @dev Derivation (verified in `script/StorageSlot.s.sol`):
    ///      keccak256(abi.encode(uint256(keccak256("prediction.market.factory.main")) - 1)) & ~bytes32(uint256(0xff))
    ///      = 0x8a6eeb15c0a4f6f1bc393fbd6de59958b6281e71cb4379c188e2764f21c90200
    bytes32 private constant _FACTORY_STORAGE_SLOT =
        0x8a6eeb15c0a4f6f1bc393fbd6de59958b6281e71cb4379c188e2764f21c90200;

    function _factoryStorage() private pure returns (FactoryStorage storage $) {
        assembly {
            $.slot := _FACTORY_STORAGE_SLOT
        }
    }

    /*//////////////////////////////////////////////////////////////
                              INITIALIZER
    //////////////////////////////////////////////////////////////*/

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialise the proxy. Idempotent across upgrades via
    ///         OZ's `initializer` modifier on V1; V2 will use
    ///         `reinitializer(2)`.
    function initialize(
        address admin_,
        address marketCreator_,
        address collateralToken_,
        address outcomeToken_,
        address oracleAdapter_,
        address feeVault_,
        uint16 defaultFeeBps_,
        uint32 defaultDisputeWindow_
    ) external initializer {
        if (admin_ == address(0)) revert ZeroAddress();
        if (collateralToken_ == address(0)) revert ZeroAddress();
        if (outcomeToken_ == address(0)) revert ZeroAddress();
        if (oracleAdapter_ == address(0)) revert ZeroAddress();
        if (feeVault_ == address(0)) revert ZeroAddress();
        if (defaultFeeBps_ == 0 || defaultFeeBps_ > 1_000) revert InvalidFee();
        if (defaultDisputeWindow_ == 0) revert InvalidWindow();

        __AccessControl_init();
        __UUPSUpgradeable_init();

        FactoryStorage storage $ = _factoryStorage();
        $.protocolAdmin = admin_;
        $.oracleAdapter = oracleAdapter_;
        $.feeVault = feeVault_;
        $.outcomeToken = outcomeToken_;
        $.collateralToken = collateralToken_;
        $.defaultFeeBps = defaultFeeBps_;
        $.defaultDisputeWindow = defaultDisputeWindow_;
        $.nextMarketId = 1;     // marketId 0 is reserved (sentinel for "unknown")

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(MARKET_CREATOR_ROLE, marketCreator_ == address(0) ? admin_ : marketCreator_);

        emit DefaultsUpdated(defaultFeeBps_, defaultDisputeWindow_);
    }

    /*//////////////////////////////////////////////////////////////
                              UUPS UPGRADE
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc UUPSUpgradeable
    /// @dev Restricted to Timelock (`DEFAULT_ADMIN_ROLE`). V1 → V2 path
    ///      is documented in `docs/adr/ADR-002-uups-target-selection.md`.
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newImplementation == address(0)) revert ZeroAddress();
        emit Upgraded(newImplementation);
    }

    /*//////////////////////////////////////////////////////////////
                              ADMIN (TIMELOCK)
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IPredictionMarketFactory
    function setDefaults(uint16 newDefaultFeeBps, uint32 newDisputeWindow) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newDefaultFeeBps == 0 || newDefaultFeeBps > 1_000) revert InvalidFee();
        if (newDisputeWindow == 0) revert InvalidWindow();
        FactoryStorage storage $ = _factoryStorage();
        $.defaultFeeBps = newDefaultFeeBps;
        $.defaultDisputeWindow = newDisputeWindow;
        emit DefaultsUpdated(newDefaultFeeBps, newDisputeWindow);
    }

    /*//////////////////////////////////////////////////////////////
                              MARKET CREATION
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IPredictionMarketFactory
    function createMarket(
        bytes32 questionId,
        int256 oracleThreshold,
        uint64 tradingEndsAt,
        uint16 feeBpsOverride
    ) external onlyRole(MARKET_CREATOR_ROLE) returns (uint64 marketId, address market) {
        FactoryStorage storage $ = _factoryStorage();
        marketId = _nextId($);
        PredictionMarket.InitParams memory params = _buildParams($, marketId, questionId, oracleThreshold, tradingEndsAt, feeBpsOverride);

        // ─── Effects (id reservation) before external CREATE ──────
        _reserveId($, marketId);

        // ─── Interaction: CREATE the market ───────────────────────
        market = address(new PredictionMarket(params));
        _bindMarket($, marketId, market);

        emit MarketCreated(marketId, market, questionId, tradingEndsAt, params.feeBps, false);
    }

    /// @inheritdoc IPredictionMarketFactory
    function createMarketDeterministic(
        bytes32 questionId,
        int256 oracleThreshold,
        uint64 tradingEndsAt,
        uint16 feeBpsOverride,
        bytes32 salt
    ) external onlyRole(MARKET_CREATOR_ROLE) returns (uint64 marketId, address market) {
        FactoryStorage storage $ = _factoryStorage();
        marketId = _nextId($);
        PredictionMarket.InitParams memory params = _buildParams($, marketId, questionId, oracleThreshold, tradingEndsAt, feeBpsOverride);

        // ─── Pre-compute the address & assert there's no collision ─
        bytes memory initCode = abi.encodePacked(type(PredictionMarket).creationCode, abi.encode(params));
        bytes32 initCodeHash = keccak256(initCode);
        address predicted = _predictCreate2(salt, initCodeHash);
        if (predicted.code.length != 0) revert MarketAlreadyDeployed(predicted);

        // ─── Effects ──────────────────────────────────────────────
        _reserveId($, marketId);

        // ─── Interaction: CREATE2 via assembly ────────────────────
        address deployed;
        assembly {
            deployed := create2(0, add(initCode, 0x20), mload(initCode), salt)
        }
        if (deployed == address(0)) revert MarketAlreadyDeployed(predicted);
        if (deployed != predicted) revert MarketAlreadyDeployed(predicted);

        market = deployed;
        _bindMarket($, marketId, market);

        emit MarketCreated(marketId, market, questionId, tradingEndsAt, params.feeBps, true);
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HELPERS
    //////////////////////////////////////////////////////////////*/

    function _nextId(FactoryStorage storage $) internal view returns (uint64) {
        return $.nextMarketId;
    }

    function _reserveId(FactoryStorage storage $, uint64 marketId) internal {
        unchecked {
            $.nextMarketId = marketId + 1;
        }
    }

    function _bindMarket(FactoryStorage storage $, uint64 marketId, address market) internal {
        $.marketById[marketId] = market;
        $.idByMarket[market] = marketId;
        // Tell the singleton ERC-1155 that this address now owns the
        // YES/NO ids for this marketId. The factory must hold the
        // ERC-1155's `FACTORY_ROLE`; this is configured at deploy time.
        IOutcomeToken1155($.outcomeToken).registerMarket(marketId, market);
    }

    function _buildParams(
        FactoryStorage storage $,
        uint64 marketId,
        bytes32 questionId,
        int256 oracleThreshold,
        uint64 tradingEndsAt,
        uint16 feeBpsOverride
    ) internal view returns (PredictionMarket.InitParams memory params) {
        if (questionId == bytes32(0)) revert InvalidQuestion();
        if (tradingEndsAt <= block.timestamp) revert InvalidWindow();

        uint16 fee = feeBpsOverride == 0 ? $.defaultFeeBps : feeBpsOverride;
        if (fee == 0 || fee > 1_000) revert InvalidFee();

        params = PredictionMarket.InitParams({
            collateral: IERC20($.collateralToken),
            outcomeToken: IOutcomeToken1155($.outcomeToken),
            oracle: IOracleAdapter($.oracleAdapter),
            feeVault: $.feeVault,
            admin:  $.protocolAdmin,
            keeper: $.protocolAdmin,
            marketId: marketId,
            questionId: questionId,
            oracleThreshold: oracleThreshold,
            tradingEndsAt: tradingEndsAt,
            feeBps: fee,
            disputeWindow: $.defaultDisputeWindow
        });
    }

    /// @notice Update the protocol admin address recorded in storage.
    ///         The new admin is propagated to *future* markets only;
    ///         already-deployed markets keep their original admin.
    function setProtocolAdmin(address newAdmin) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newAdmin == address(0)) revert ZeroAddress();
        _factoryStorage().protocolAdmin = newAdmin;
    }

    /// @notice View the protocol admin used as `admin`/`keeper` on new markets.
    function protocolAdmin() external view returns (address) {
        return _factoryStorage().protocolAdmin;
    }

    /*//////////////////////////////////////////////////////////////
                          ADDRESS PREDICTION
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IPredictionMarketFactory
    /// @dev Inline Yul implementation. Benchmarked in
    ///      `test/gas/PredictMarketAddress.t.sol` (W7).
    function predictMarketAddress(bytes32 salt, bytes32 initCodeHash) external view returns (address predicted) {
        return _predictCreate2(salt, initCodeHash);
    }

    /// @dev Pure-Solidity baseline kept for the gas benchmark.
    function predictMarketAddressSolidity(bytes32 salt, bytes32 initCodeHash)
        external
        view
        returns (address)
    {
        return address(
            uint160(
                uint256(
                    keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, initCodeHash))
                )
            )
        );
    }

    /// @dev Optimised CREATE2 address derivation using inline Yul.
    ///
    ///      Layout written into memory starting at `p`:
    ///        offset 0x00 (1 byte)  : 0xff
    ///        offset 0x01 (20 bytes): factory address
    ///        offset 0x15 (32 bytes): salt
    ///        offset 0x35 (32 bytes): initCodeHash
    ///      Total: 1 + 20 + 32 + 32 = 85 bytes (0x55).
    ///
    ///      Hashing those 85 bytes and truncating to the low 160 bits
    ///      gives the CREATE2 address per EIP-1014. Slither audit ref:
    ///      Finding G-1 (Informational, acknowledged).
    function _predictCreate2(bytes32 salt, bytes32 initCodeHash) internal view returns (address predicted) {
        assembly {
            let p := mload(0x40)
            mstore8(p, 0xff)
            mstore(add(p, 0x01), shl(96, address()))    // factory address, left-aligned in a word
            mstore(add(p, 0x15), salt)
            mstore(add(p, 0x35), initCodeHash)
            let digest := keccak256(p, 0x55)
            predicted := and(digest, 0xffffffffffffffffffffffffffffffffffffffff)
            // Bump free memory pointer past the 96-byte scratch we wrote.
            mstore(0x40, add(p, 0x60))
        }
    }

    /*//////////////////////////////////////////////////////////////
                                  VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IPredictionMarketFactory
    function marketById(uint64 id) external view returns (address) {
        return _factoryStorage().marketById[id];
    }

    /// @inheritdoc IPredictionMarketFactory
    function idByMarket(address market) external view returns (uint64) {
        return _factoryStorage().idByMarket[market];
    }

    /// @inheritdoc IPredictionMarketFactory
    function nextMarketId() external view returns (uint64) {
        return _factoryStorage().nextMarketId;
    }

    /// @inheritdoc IPredictionMarketFactory
    function defaultFeeBps() external view returns (uint16) {
        return _factoryStorage().defaultFeeBps;
    }

    /// @inheritdoc IPredictionMarketFactory
    function defaultDisputeWindow() external view returns (uint32) {
        return _factoryStorage().defaultDisputeWindow;
    }

    /// @inheritdoc IPredictionMarketFactory
    function collateralToken() external view returns (address) {
        return _factoryStorage().collateralToken;
    }

    /// @inheritdoc IPredictionMarketFactory
    function outcomeToken() external view returns (address) {
        return _factoryStorage().outcomeToken;
    }

    /// @inheritdoc IPredictionMarketFactory
    function oracleAdapter() external view returns (address) {
        return _factoryStorage().oracleAdapter;
    }

    /// @inheritdoc IPredictionMarketFactory
    function feeVault() external view returns (address) {
        return _factoryStorage().feeVault;
    }
}
