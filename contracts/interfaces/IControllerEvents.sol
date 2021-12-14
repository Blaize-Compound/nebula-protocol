// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./ICToken.sol";
import "./IPriceOracle.sol";

interface IControllerEvents {
    /// @notice Emitted when an admin supports a market
    event MarketListed(ICToken cToken);

    /// @notice Emitted when an account enters a market
    event MarketEntered(ICToken cToken, address account);

    /// @notice Emitted when an account exits a market
    event MarketExited(ICToken cToken, address account);

    /// @notice Emitted when close factor is changed by admin
    event NewCloseFactor(
        uint256 oldCloseFactorMantissa,
        uint256 newCloseFactorMantissa
    );

    /// @notice Emitted when a collateral factor is changed by admin
    event NewCollateralFactor(
        ICToken cToken,
        uint256 oldCollateralFactorMantissa,
        uint256 newCollateralFactorMantissa
    );

    /// @notice Emitted when liquidation incentive is changed by admin
    event NewLiquidationIncentive(
        uint256 oldLiquidationIncentiveMantissa,
        uint256 newLiquidationIncentiveMantissa
    );

    /// @notice Emitted when price oracle is changed
    event NewPriceOracle(
        IPriceOracle oldPriceOracle,
        IPriceOracle newPriceOracle
    );

    /// @notice Emitted when pause guardian is changed
    event NewPauseGuardian(address oldPauseGuardian, address newPauseGuardian);

    /// @notice Emitted when an action is paused globally
    event ActionPaused(string action, bool pauseState);

    /// @notice Emitted when an action is paused on a market
    event ActionPaused(ICToken cToken, string action, bool pauseState);

    /// @notice Emitted when a new borrow-side COMP speed is calculated for a market
    event CompBorrowSpeedUpdated(ICToken indexed cToken, uint256 newSpeed);

    /// @notice Emitted when a new supply-side COMP speed is calculated for a market
    event CompSupplySpeedUpdated(ICToken indexed cToken, uint256 newSpeed);

    /// @notice Emitted when a new COMP speed is set for a contributor
    event ContributorCompSpeedUpdated(
        address indexed contributor,
        uint256 newSpeed
    );

    /// @notice Emitted when COMP is distributed to a supplier
    event DistributedSupplierComp(
        ICToken indexed cToken,
        address indexed supplier,
        uint256 compDelta,
        uint256 compSupplyIndex
    );

    /// @notice Emitted when COMP is distributed to a borrower
    event DistributedBorrowerComp(
        ICToken indexed cToken,
        address indexed borrower,
        uint256 compDelta,
        uint256 compBorrowIndex
    );

    /// @notice Emitted when borrow cap for a cToken is changed
    event NewBorrowCap(ICToken indexed cToken, uint256 newBorrowCap);

    /// @notice Emitted when borrow cap guardian is changed
    event NewBorrowCapGuardian(
        address oldBorrowCapGuardian,
        address newBorrowCapGuardian
    );

    /// @notice Emitted when COMP is granted by admin
    event CompGranted(address recipient, uint256 amount);

    /// @notice Emitted when COMP accrued for a user has been manually adjusted.
    event CompAccruedAdjusted(
        address indexed user,
        uint256 oldCompAccrued,
        uint256 newCompAccrued
    );

    /// @notice Emitted when COMP receivable for a user has been updated.
    event CompReceivableUpdated(
        address indexed user,
        uint256 oldCompReceivable,
        uint256 newCompReceivable
    );
}
