// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./IController.sol";
import "./ICToken.sol";
import "./IInterestRateModel.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ICErc20 {
    /*** User Interface ***/
    function underlying() external view returns (address);

    function mint(uint256 mintAmount) external returns (uint256);

    function redeem(uint256 redeemTokens) external returns (uint256);

    function redeemUnderlying(uint256 redeemAmount) external returns (uint256);

    function borrow(uint256 borrowAmount) external returns (uint256);

    function borrowFixedRate(uint256 borrowAmount, uint256 maturity) external;

    function repayBorrowFixedRate(uint256[] memory borrowsIndexes) external;

    function repayBorrowFixedRateOnBehalf(address borrower, uint256[] memory borrowsIndexes) external;

    function repayBorrow(uint256 repayAmount) external returns (uint256);

    function repayBorrowBehalf(address borrower, uint256 repayAmount) external returns (uint256);

    function liquidateBorrowFixedRate(
        address borrower,
        uint256[] memory borrowsIndexes,
        ICToken[] memory cTokenCollaterals
    ) external;

    function liquidateBorrow(
        address borrower,
        uint256 repayAmount,
        ICToken cTokenCollateral
    ) external returns (uint256);

    function sweepToken(IERC20 token) external;

    /*** Admin Functions ***/

    function addReserves(uint256 addAmount) external;
}
