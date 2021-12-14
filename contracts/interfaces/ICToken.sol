// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./IController.sol";
import "./IInterestRateModel.sol";

interface ICToken {
    /*** User Interface ***/

    function transfer(address dst, uint amount) external returns (bool);
    function transferFrom(address src, address dst, uint amount) external returns (bool);
    function approve(address spender, uint amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint);
    function balanceOf(address owner) external view returns (uint);
    function totalSupply() external view returns (uint);
    function balanceOfUnderlying(address owner) external returns (uint);
    function getAccountSnapshot(address account) external view returns (uint, uint, uint);
    function borrowRatePerBlock() external view returns (uint);
    function supplyRatePerBlock() external view returns (uint);
    function totalBorrowsCurrent() external returns (uint);
    function borrowBalanceCurrent(address account) external returns (uint);
    function borrowBalanceStored(address account) external view returns (uint);
    function exchangeRateCurrent() external returns (uint);
    function exchangeRateStored() external view returns (uint);
    function getCash() external view returns (uint);
    function getAccrualBlockNumber() external view returns (uint);
    function accrueInterest() external;
    function seize(address liquidator, address borrower, uint seizeTokens) external;
    function totalBorrows() external view returns (uint);
    function borrowIndex() external view returns (uint);
    function comptroller() external view returns (IController);
    function isCToken() external view returns (bool);
    function reserveFactorMantissa() external view returns (uint);


    /*** Admin Functions ***/

    function setPendingAdmin(address payable newPendingAdmin) external;
    function acceptAdmin() external;
    function setController(IController newComptroller) external;
    function setReserveFactor(uint newReserveFactorMantissa) external;
    function reduceReserves(uint reduceAmount) external;
    function setInterestRateModel(IInterestRateModel newInterestRateModel) external;
}