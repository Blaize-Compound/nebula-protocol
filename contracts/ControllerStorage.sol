// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "./interfaces/IMToken.sol";
import "./interfaces/IPriceOracle.sol";

contract UnitrollerAdminStorage {
    /**
     * @notice Administrator for this contract
     */
    address public admin;

    /**
     * @notice Pending administrator for this contract
     */
    address public pendingAdmin;

    /**
     * @notice Active brains of Unitroller
     */
    address public controllerImplementation;

    /**
     * @notice Pending brains of Unitroller
     */
    address public pendingControllerImplementation;
}

contract ControllerV1Storage is UnitrollerAdminStorage {
    /**
     * @notice Oracle which gives the price of any given asset
     */
    IPriceOracle public oracle;

    /**
     * @notice Multiplier used to calculate the maximum repayAmount when liquidating a borrow
     */
    uint256 public closeFactorMantissa;

    /**
     * @notice Multiplier representing the discount on collateral that a liquidator receives
     */
    uint256 public liquidationIncentiveMantissa;

    /**
     * @notice Max number of assets a single account can participate in (borrow or use as collateral)
     */
    uint256 public maxAssets;

    /**
     * @notice Per-account mapping of "assets you are in", capped by maxAssets
     */
    mapping(address => IMToken[]) public accountAssets;
}

contract ControllerV2Storage is ControllerV1Storage {
    struct Market {
        /// @notice Whether or not this market is listed
        bool isListed;
        /**
         * @notice Multiplier representing the most one can borrow against their collateral in this market.
         *  For instance, 0.9 to allow borrowing 90% of collateral value.
         *  Must be between 0 and 1, and stored as a mantissa.
         */
        uint256 collateralFactorMantissa;
        /// @notice Whether or not this market receives NEB
        bool isComped;
    }

    /// @notice Per-market mapping of "accounts in this asset"
    /// Token => user => indicator
    mapping(address => mapping(address => bool)) public accountMembership;

    /**
     * @notice Official mapping of cTokens -> Market metadata
     * @dev Used e.g. to determine if a market is supported
     */
    mapping(address => Market) public markets;

    /**
     * @notice The Pause Guardian can pause certain actions as a safety mechanism.
     *  Actions which allow users to remove their own assets cannot be paused.
     *  Liquidation / seizing / transfer can only be paused globally, not by market.
     */
    address public pauseGuardian;
    bool public _mintGuardianPaused;
    bool public _borrowGuardianPaused;
    bool public transferGuardianPaused;
    bool public seizeGuardianPaused;
    mapping(address => bool) public mintGuardianPaused;
    mapping(address => bool) public borrowGuardianPaused;
}

contract ControllerV3Storage is ControllerV2Storage {
    struct NebMarketState {
        /// @notice The market's last updated compBorrowIndex or compSupplyIndex
        uint256 index;
        /// @notice The block number the index was last updated at
        uint256 block;
    }

    /// @notice A list of all markets
    IMToken[] public allMarkets;

    /// @notice The rate at which the flywheel distributes NEB, per block
    uint256 public nebRate;

    /// @notice The portion of nebRate that each market currently receives
    mapping(address => uint256) public nebSpeeds;

    /// @notice The NEB market supply state for each market
    mapping(address => NebMarketState) public nebSupplyState;

    /// @notice The NEB market borrow state for each market
    mapping(address => NebMarketState) public nebBorrowState;

    /// @notice The NEB borrow index for each market for each supplier as of the last time they accrued NEB
    mapping(address => mapping(address => uint256)) public nebSupplierIndex;

    /// @notice The NEB borrow index for each market for each borrower as of the last time they accrued NEB
    mapping(address => mapping(address => uint256)) public nebBorrowerIndex;

    /// @notice The NEB accrued but not yet transferred to each user
    mapping(address => uint256) public nebAccrued;
}

contract ControllerV4Storage is ControllerV3Storage {
    // @notice The borrowCapGuardian can set borrowCaps to any number for any market. Lowering the borrow cap could disable borrowing on the given market.
    address public borrowCapGuardian;

    // @notice Borrow caps enforced by borrowAllowed for each cToken address. Defaults to zero which corresponds to unlimited borrowing.
    mapping(address => uint256) public borrowCaps;
}

contract ControllerV5Storage is ControllerV4Storage {
    /// @notice The portion of NEB that each contributor receives per block
    mapping(address => uint256) public nebContributorSpeeds;

    /// @notice Last block at which a contributor's NEB rewards have been allocated
    mapping(address => uint256) public lastContributorBlock;
}

contract ControllerV6Storage is ControllerV5Storage {
    /// @notice The rate at which comp is distributed to the corresponding borrow market (per block)
    mapping(address => uint256) public nebBorrowSpeeds;

    /// @notice The rate at which comp is distributed to the corresponding supply market (per block)
    mapping(address => uint256) public nebSupplySpeeds;
}

contract ControllerV7Storage is ControllerV6Storage {
    /// @notice Accounting storage mapping account addresses to how much NEB they owe the protocol.
    mapping(address => uint256) public nebReceivable;
}
