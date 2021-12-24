// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

interface IController {
    /*** Assets You Are In ***/

    function enterMarkets(address[] calldata mTokens) external;

    function exitMarket(address mToken) external;

    /*** Policy Hooks ***/

    function mintAllowed(
        address mToken,
        address minter,
        uint256 mintAmount
    ) external returns (bool);

    function mintVerify(
        address mToken,
        address minter,
        uint256 mintAmount,
        uint256 mintTokens
    ) external;

    function redeemAllowed(
        address mToken,
        address redeemer,
        uint256 redeemTokens
    ) external returns (bool);

    function redeemVerify(
        address mToken,
        address redeemer,
        uint256 redeemAmount,
        uint256 redeemTokens
    ) external;

    function borrowAllowed(
        address mToken,
        address borrower,
        uint256 borrowAmount
    ) external returns (bool);

    function borrowVerify(
        address mToken,
        address borrower,
        uint256 borrowAmount
    ) external;

    function repayBorrowAllowed(
        address mToken,
        address payer,
        address borrower,
        uint256 repayAmount
    ) external returns (bool);

    function repayBorrowVerify(
        address mToken,
        address payer,
        address borrower,
        uint256 repayAmount,
        uint256 borrowerIndex
    ) external;

    function liquidateBorrowAllowed(
        address mTokenBorrowed,
        address mTokenCollateral,
        address liquidator,
        address borrower,
        uint256 repayAmount
    ) external returns (bool);

    function liquidateBorrowVerify(
        address mTokenBorrowed,
        address mTokenCollateral,
        address liquidator,
        address borrower,
        uint256 repayAmount,
        uint256 seizeTokens
    ) external;

    function seizeAllowed(
        address mTokenCollateral,
        address mTokenBorrowed,
        address liquidator,
        address borrower,
        uint256 seizeTokens
    ) external returns (bool);

    function seizeVerify(
        address mTokenCollateral,
        address mTokenBorrowed,
        address liquidator,
        address borrower,
        uint256 seizeTokens
    ) external;

    function transferAllowed(
        address mToken,
        address src,
        address dst,
        uint256 transferTokens
    ) external returns (bool);

    function transferVerify(
        address mToken,
        address src,
        address dst,
        uint256 transferTokens
    ) external;

    /*** Liquidity/Liquidation Calculations ***/

    function liquidateCalculateSeizeTokens(
        address mTokenBorrowed,
        address mTokenCollateral,
        uint256 repayAmount
    ) external view returns (uint256);

    function isController() external view returns (bool);
}
