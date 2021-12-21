// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./interfaces/IController.sol";
import "./interfaces/IInterestRateModel.sol";
import "./interfaces/ICToken.sol";

abstract contract CTokenStorage is ICToken {
    /**
     * @notice Indicator that this is a CToken contract (for inspection)
     */
    bool public constant isCToken = true;

    /**
     * @dev Guard variable for re-entrancy checks
     */
    bool internal _notEntered;

    /**
     * @notice EIP-20 token name for this token
     */
    string public name;

    /**
     * @notice EIP-20 token symbol for this token
     */
    string public symbol;

    /**
     * @notice EIP-20 token decimals for this token
     */
    uint8 public decimals;

    /**
     * @notice Maximum borrow rate that can ever be applied (.0005% / block)
     */

    uint256 internal constant borrowRateMaxMantissa = 0.0005e16;

    /**
     * @notice Maximum fraction of interest that can be set aside for reserves
     */
    uint256 internal constant reserveFactorMaxMantissa = 1e18;

    /**
     * @notice Administrator for this contract
     */
    address payable public admin;

    /**
     * @notice Pending administrator for this contract
     */
    address payable public pendingAdmin;

    /**
     * @notice Contract which oversees inter-cToken operations
     */
    IController public comptroller;

    /**
     * @notice Model which tells what the current interest rate should be
     */
    IInterestRateModel public interestRateModel;

    /**
     * @notice Initial exchange rate used when minting the first CTokens (used when totalSupply = 0)
     */
    uint256 internal initialExchangeRateMantissa;

    /**
     * @notice Fraction of interest currently set aside for reserves
     */
    uint256 public reserveFactorMantissa;

    /**
     * @notice Block number that interest was last accrued at
     */
    uint256 public accrualBlockNumber;

    /**
     * @notice Accumulator of the total earned interest rate since the opening of the market
     */
    uint256 public borrowIndex;

    /**
     * @notice Total amount of outstanding borrows of the underlying in this market
     */
    uint256 public totalBorrows;

    /**
     * @notice Total amount of outstanding borrows of the underlying, borrowed with fixed rate
     */
    uint256 public totalBorrowsFixed;

    /**
     * @notice Total amount of reserves of the underlying held in this market
     */
    uint256 public totalReserves;

    /**
     * @notice Total number of tokens in circulation
     */
    uint256 public totalSupply;

    /**
     * @notice Amount of time, given for user in order to repay borrow after maturity is reached
     */
    uint256 public restPeriod;

    /**
     * @notice Official record of token balances for each account
     */
    mapping(address => uint256) internal accountTokens;

    /**
     * @notice Approved token transfer amounts on behalf of others
     */
    mapping(address => mapping(address => uint256)) internal transferAllowances;

    /**
     * @notice Container for borrow balance information
     * @member principal Total balance (with accrued interest), after applying the most recent balance-changing action
     * @member interestIndex Global borrowIndex as of the most recent balance-changing action
     */
    struct BorrowSnapshot {
        uint256 principal;
        uint256 interestIndex;
    }

    /**
     * @notice Mapping of account addresses to outstanding borrow balances
     */
    mapping(address => BorrowSnapshot) internal accountBorrows;

    /**
     * @notice Container for fixed borrow balance information
     * @member amount Amount of underlying borrowed with provided rate
     * @member rate Fixed rate with which a borrow was made
     * @member openedAt Timestamp, inidicating when a borrow was taken
     * @member duration Duration till maturity will be reached
     */
    struct FixedRateBorrow {
        uint256 amount;
        uint256 rate;
        uint256 openedAt;
        uint256 duration;
    }

    /**
     * @notice Mapping of account addresses to array of every fixed borrow
     */
    mapping(address => FixedRateBorrow[]) internal accountFixedRateBorrows;

    /**
     * @notice Share of seized collateral that is added to reserves
     */
    uint256 public constant protocolSeizeShareMantissa = 2.8e16; //2.8%
}
