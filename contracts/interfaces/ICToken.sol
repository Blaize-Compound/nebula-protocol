// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./IController.sol";
import "./IInterestRateModel.sol";

interface ICToken {
    /*** User Interface ***/

    function transfer(address dst, uint256 amount) external returns (bool);

    function transferFrom(
        address src,
        address dst,
        uint256 amount
    ) external returns (bool);

    function approve(address spender, uint256 amount) external returns (bool);

    function allowance(address owner, address spender) external view returns (uint256);

    function balanceOf(address owner) external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function balanceOfUnderlying(address owner) external returns (uint256);

    function getTotalBorrows() external view returns (uint256);

    function getAccountSnapshot(address account)
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256
        );

    function borrowRatePerBlock() external view returns (uint256);
    
    function borrowRatePerTime(uint256 time) external view returns (uint256);

    function fixedBorrowsAmount(address account) external view returns (uint256);

    function expiredBorrows(address account)
        external
        view
        returns (uint256[] memory indexes, uint256[] memory repayAmounts);

    function supplyRatePerBlock() external view returns (uint256);

    function totalBorrowsCurrent() external returns (uint256);

    function borrowBalanceCurrent(address account) external returns (uint256);

    function borrowBalanceStored(address account) external view returns (uint256);

    function exchangeRateCurrent() external returns (uint256);

    function exchangeRateStored() external view returns (uint256);

    function getCash() external view returns (uint256);

    function getAccrualBlockNumber() external view returns (uint256);

    function accrueInterest() external;

    function seize(
        address liquidator,
        address borrower,
        uint256 seizeTokens
    ) external;

    function totalBorrows() external view returns (uint256);

    function borrowIndex() external view returns (uint256);

    function comptroller() external view returns (IController);

    function isCToken() external view returns (bool);

    function reserveFactorMantissa() external view returns (uint256);

    /*** Admin Functions ***/

    function setPendingAdmin(address payable newPendingAdmin) external;

    function acceptAdmin() external;

    function setController(IController newComptroller) external;

    function setReserveFactor(uint256 newReserveFactorMantissa) external;

    function reduceReserves(uint256 reduceAmount) external;

    function setInterestRateModel(IInterestRateModel newInterestRateModel) external;
}
