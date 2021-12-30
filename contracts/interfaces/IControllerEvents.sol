// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./IMToken.sol";
import "./IPriceOracle.sol";

interface IControllerEvents {
    /// @notice Emitted when an admin supports a market
    event MarketListed(IMToken mToken);

    /// @notice Emitted when an account enters a market
    event MarketEntered(IMToken mToken, address account);

    /// @notice Emitted when an account exits a market
    event MarketExited(IMToken mToken, address account);

    /// @notice Emitted when close factor is changed by admin
    event NewCloseFactor(uint256 oldCloseFactorMantissa, uint256 newCloseFactorMantissa);

    /// @notice Emitted when a collateral factor is changed by admin
    event NewCollateralFactor(IMToken mToken, uint256 oldCollateralFactorMantissa, uint256 newCollateralFactorMantissa);

    /// @notice Emitted when liquidation incentive is changed by admin
    event NewLiquidationIncentive(uint256 oldLiquidationIncentiveMantissa, uint256 newLiquidationIncentiveMantissa);

    /// @notice Emitted when price oracle is changed
    event NewPriceOracle(IPriceOracle oldPriceOracle, IPriceOracle newPriceOracle);

    /// @notice Emitted when pause guardian is changed
    event NewPauseGuardian(address oldPauseGuardian, address newPauseGuardian);

    /// @notice Emitted when an action is paused globally
    event ActionPaused(string action, bool pauseState);

    /// @notice Emitted when an action is paused on a market
    event ActionPaused(IMToken mToken, string action, bool pauseState);

    /// @notice Emitted when a new borrow-side NEB speed is calculated for a market
    event NebBorrowSpeedUpdated(IMToken indexed mToken, uint256 newSpeed);

    /// @notice Emitted when a new supply-side NEB speed is calculated for a market
    event NebSupplySpeedUpdated(IMToken indexed mToken, uint256 newSpeed);

    /// @notice Emitted when a new NEB speed is set for a contributor
    event ContributorNebSpeedUpdated(address indexed contributor, uint256 newSpeed);

    /// @notice Emitted when NEB is distributed to a supplier
    event DistributedSupplierNeb(
        IMToken indexed mToken,
        address indexed supplier,
        uint256 NebDelta,
        uint256 NebSupplyIndex
    );

    /// @notice Emitted when NEB is distributed to a borrower
    event DistributedBorrowerNeb(
        IMToken indexed mToken,
        address indexed borrower,
        uint256 NebDelta,
        uint256 NebBorrowIndex
    );

    /// @notice Emitted when borrow cap for a mToken is changed
    event NewBorrowCap(IMToken indexed mToken, uint256 newBorrowCap);

    /// @notice Emitted when borrow cap guardian is changed
    event NewBorrowCapGuardian(address oldBorrowCapGuardian, address newBorrowCapGuardian);

    /// @notice Emitted when NEB is granted by admin
    event NebGranted(address recipient, uint256 amount);

    /// @notice Emitted when NEB accrued for a user has been manually adjusted.
    event NebAccruedAdjusted(address indexed user, uint256 oldNebAccrued, uint256 newNebAccrued);

    /// @notice Emitted when NEB receivable for a user has been updated.
    event NebReceivableUpdated(address indexed user, uint256 oldNebReceivable, uint256 newNebReceivable);
}
