// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./IController.sol";
import "./ICToken.sol";
import "./IInterestRateModel.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ICErc20 {
    /*** User Interface ***/
    function underlying() external view returns (address);

    function mint(uint mintAmount) external returns (uint);
    function redeem(uint redeemTokens) external returns (uint);
    function redeemUnderlying(uint redeemAmount) external returns (uint);
    function borrow(uint borrowAmount) external returns (uint);
    function repayBorrow(uint repayAmount) external returns (uint);
    function repayBorrowBehalf(address borrower, uint repayAmount) external returns (uint);
    function liquidateBorrow(address borrower, uint repayAmount, ICToken cTokenCollateral) external returns (uint);
    function sweepToken(IERC20 token) external;


    /*** Admin Functions ***/

    function addReserves(uint addAmount) external;
}