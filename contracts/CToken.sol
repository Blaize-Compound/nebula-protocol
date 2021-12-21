// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./interfaces/IController.sol";
import "./interfaces/ICToken.sol";
import "./interfaces/IInterestRateModel.sol";
import "./CTokenStorage.sol";
import "./interfaces/ICTokenEvents.sol";

/**
 * @title Compound's CToken Contract
 * @notice Abstract base for CTokens
 * @author Compound
 */
abstract contract CToken is CTokenStorage, ICTokenEvents {
    modifier onlyAdmin(address _caller) {
        require(_caller == admin, "Caller is not an admin");
        _;
    }

    modifier marketFresh() {
        /* Verify market's block number equals current block number */
        require(accrualBlockNumber == getBlockNumber(), "Market is not fresh");
        _;
    }

    /**
     * @notice Initialize the money market
     * @param comptroller_ The address of the Comptroller
     * @param interestRateModel_ The address of the interest rate model
     * @param initialExchangeRateMantissa_ The initial exchange rate, scaled by 1e18
     * @param name_ EIP-20 name of this token
     * @param symbol_ EIP-20 symbol of this token
     * @param decimals_ EIP-20 decimal precision of this token
     */
    function initialize(
        IController comptroller_,
        IInterestRateModel interestRateModel_,
        uint256 initialExchangeRateMantissa_,
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    ) public {
        require(msg.sender == admin, "only admin may initialize the market");
        require(
            accrualBlockNumber == 0 && borrowIndex == 0,
            "market may only be initialized once"
        );

        // Set initial exchange rate
        initialExchangeRateMantissa = initialExchangeRateMantissa_;
        require(
            initialExchangeRateMantissa > 0,
            "initial exchange rate must be greater than zero."
        );

        // Set the comptroller
        setController(comptroller_);

        // Initialize block number and borrow index (block number mocks depend on comptroller being set)
        accrualBlockNumber = getBlockNumber();
        borrowIndex = 1e18;
        restPeriod = 4 hours;

        // Set the interest rate model (depends on block number / borrow index)
        _setInterestRateModelFresh(interestRateModel_);

        name = name_;
        symbol = symbol_;
        decimals = decimals_;

        // The counter starts true to prevent changing it from zero to non-zero (i.e. smaller cost/refund)
        _notEntered = true;
    }

    /**
     * @notice Transfer tokens tokens from src to dst by spender
     * @dev Called by both transfer and transferFrom internally
     * @param spender The address of the account performing the transfer
     * @param src The address of the source account
     * @param dst The address of the destination account
     * @param tokens The number of tokens to transfer
     * @return Whether or not the transfer succeeded
     */
    function transferTokens(
        address spender,
        address src,
        address dst,
        uint256 tokens
    ) internal returns (bool) {
        /* Fail if transfer not allowed */
        if (!comptroller.transferAllowed(address(this), src, dst, tokens)) {
            return false;
        }

        /* Do not allow self-transfers */
        if (src == dst) {
            return false;
        }

        /* Get the allowance, infinite for the account owner */
        uint256 startingAllowance = 0;
        if (spender == src) {
            startingAllowance = type(uint256).max;
        } else {
            startingAllowance = transferAllowances[src][spender];
        }

        /* Do the calculations, checking for {under,over}flow */
        uint256 allowanceNew = startingAllowance - tokens;

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        accountTokens[src] -= tokens;
        accountTokens[dst] += tokens;

        /* Eat some of the allowance (if necessary) */
        if (startingAllowance != type(uint256).max) {
            transferAllowances[src][spender] = allowanceNew;
        }

        /* We emit a Transfer event */
        emit Transfer(src, dst, tokens);

        return true;
    }

    /**
     * @notice Transfer amount tokens from msg.sender to dst
     * @param dst The address of the destination account
     * @param amount The number of tokens to transfer
     * @return Whether or not the transfer succeeded
     */
    function transfer(address dst, uint256 amount)
        external
        nonReentrant
        returns (bool)
    {
        return transferTokens(msg.sender, msg.sender, dst, amount);
    }

    /**
     * @notice Transfer amount tokens from src to dst
     * @param src The address of the source account
     * @param dst The address of the destination account
     * @param amount The number of tokens to transfer
     * @return Whether or not the transfer succeeded
     */
    function transferFrom(
        address src,
        address dst,
        uint256 amount
    ) external nonReentrant returns (bool) {
        return transferTokens(msg.sender, src, dst, amount);
    }

    /**
     * @notice Approve spender to transfer up to amount from src
     * @dev This will overwrite the approval amount for spender
     *  and is subject to issues noted [here](https://eips.ethereum.org/EIPS/eip-20#approve)
     * @param spender The address of the account which may transfer tokens
     * @param amount The number of tokens that are approved (-1 means infinite)
     * @return Whether or not the approval succeeded
     */
    function approve(address spender, uint256 amount) external returns (bool) {
        address src = msg.sender;
        transferAllowances[src][spender] = amount;
        emit Approval(src, spender, amount);
        return true;
    }

    /**
     * @notice Get the current allowance from owner for spender
     * @param owner The address of the account which owns the tokens to be spent
     * @param spender The address of the account which may transfer tokens
     * @return The number of tokens allowed to be spent (-1 means infinite)
     */
    function allowance(address owner, address spender)
        external
        view
        returns (uint256)
    {
        return transferAllowances[owner][spender];
    }

    /**
     * @notice Get the token balance of the owner
     * @param owner The address of the account to query
     * @return The number of tokens owned by owner
     */
    function balanceOf(address owner) external view returns (uint256) {
        return accountTokens[owner];
    }

    /**
     * @notice Get the underlying balance of the owner
     * @dev This also accrues interest in a transaction
     * @param owner The address of the account to query
     * @return The amount of underlying owned by owner
     */
    function balanceOfUnderlying(address owner) external returns (uint256) {
        uint256 exchangeRate = exchangeRateCurrent();
        uint256 balance = (exchangeRate * accountTokens[owner]) / 1e18;
        return balance;
    }

    /**
     * @notice Get a snapshot of the account's balances, and the cached exchange rate
     * @dev This is used by comptroller to more efficiently perform liquidity checks.
     * @param account Address of the account to snapshot
     * @return (token balance, borrow balance, exchange rate mantissa)
     */
    function getAccountSnapshot(address account)
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        uint256 cTokenBalance = accountTokens[account];
        uint256 borrowBalance = borrowBalanceStoredInternal(account);
        uint256 borrowBalanceTotal = borrowBalance +
            borrowBalanceFixedStored(account);
        uint256 exchangeRateMantissa = exchangeRateStoredInternal();

        return (
            cTokenBalance,
            borrowBalance,
            exchangeRateMantissa,
            borrowBalanceTotal
        );
    }

    /**
     * @dev Function to simply retrieve block number
     *  This exists mainly for inheriting test contracts to stub this result.
     */
    function getBlockNumber() internal view returns (uint256) {
        return block.number;
    }

    function getTotalBorrows() external view returns (uint256) {
        return totalBorrows + totalBorrowsFixed;
    }

    /**
     * @dev Function to simply retrieve accrual block number.
     */
    function getAccrualBlockNumber() external view returns (uint256) {
        return accrualBlockNumber;
    }

    /**
     * @notice Returns the current per-block borrow interest rate for this cToken
     * @return The borrow interest rate per block, scaled by 1e18
     */
    function borrowRatePerBlock() external view returns (uint256) {
        return
            interestRateModel.getBorrowRate(
                getCashPrior(),
                totalBorrows,
                totalReserves
            );
    }

    /**
     * @notice Returns the current per-block supply interest rate for this cToken
     * @return The supply interest rate per block, scaled by 1e18
     */
    function supplyRatePerBlock() external view returns (uint256) {
        return
            interestRateModel.getSupplyRate(
                getCashPrior(),
                totalBorrows,
                totalReserves,
                reserveFactorMantissa
            );
    }

    /**
     * @notice Returns the current total borrows plus accrued interest
     * @return The total borrows with interest
     */
    function totalBorrowsCurrent() external nonReentrant returns (uint256) {
        accrueInterest();
        return totalBorrows;
    }

    /**
     * @notice Accrue interest to updated borrowIndex and then calculate account's borrow balance using the updated borrowIndex
     * @param account The address whose balance should be calculated after updating borrowIndex
     * @return The calculated balance
     */
    function borrowBalanceCurrent(address account)
        external
        nonReentrant
        returns (uint256)
    {
        accrueInterest();
        return borrowBalanceStored(account);
    }

    function expiredBorrows(address account)
        external
        view
        returns (uint256[] memory indexes, uint256[] memory repayAmounts)
    {
        FixedRateBorrow[] memory borrows = accountFixedRateBorrows[account];
        uint256 count;
        for (uint256 i = 0; i < borrows.length; i++) {
            if (
                block.timestamp >
                borrows[i].openedAt + borrows[i].duration + restPeriod
            ) {
                indexes[count] = i;
                repayAmounts[count] =
                    borrows[i].amount +
                    ((borrows[i].amount * borrows[i].rate) / 1e18);
                count++;
            }
        }
    }

    /**
     * @notice Return the borrow balance of account based on stored data
     * @param account The address whose balance should be calculated
     * @return The calculated balance
     */
    function borrowBalanceStored(address account)
        public
        view
        returns (uint256)
    {
        uint256 result = borrowBalanceStoredInternal(account);
        return result;
    }

    /**
     * @notice Return the borrow balance of account based on stored data
     * @param account The address whose balance should be calculated
     * @return (error code, the calculated balance or 0 if error code is non-zero)
     */
    function borrowBalanceStoredInternal(address account)
        internal
        view
        returns (uint256)
    {
        /* Note: we do not assert that the market is up to date */
        uint256 principalTimesIndex;
        uint256 result;

        /* Get borrowBalance and borrowIndex */
        BorrowSnapshot storage borrowSnapshot = accountBorrows[account];

        /* If borrowBalance = 0 then borrowIndex is likely also 0.
         * Rather than failing the calculation with a division by 0, we immediately return 0 in this case.
         */
        if (borrowSnapshot.principal == 0) {
            return 0;
        }

        /* Calculate new borrow balance using the interest index:
         *  recentBorrowBalance = borrower.borrowBalance * market.borrowIndex / borrower.borrowIndex
         */
        principalTimesIndex = borrowSnapshot.principal * borrowIndex;

        result = principalTimesIndex / borrowSnapshot.interestIndex;

        return result;
    }

    function borrowBalanceFixedStored(address account)
        internal
        view
        returns (uint256)
    {
        FixedRateBorrow[] memory borrows = accountFixedRateBorrows[account];
        uint256 accountTotalFixedBorrow;
        for (uint256 i = 0; i < borrows.length; i++) {
            accountTotalFixedBorrow += borrows[i].amount;
        }
        return accountTotalFixedBorrow;
    }

    /**
     * @notice Accrue interest then return the up-to-date exchange rate
     * @return Calculated exchange rate scaled by 1e18
     */
    function exchangeRateCurrent() public nonReentrant returns (uint256) {
        accrueInterest();
        return exchangeRateStored();
    }

    /**
     * @notice Calculates the exchange rate from the underlying to the CToken
     * @dev This function does not accrue interest before calculating the exchange rate
     * @return Calculated exchange rate scaled by 1e18
     */
    function exchangeRateStored() public view returns (uint256) {
        return exchangeRateStoredInternal();
    }

    /**
     * @notice Calculates the exchange rate from the underlying to the CToken
     * @dev This function does not accrue interest before calculating the exchange rate
     * @return (error code, calculated exchange rate scaled by 1e18)
     */
    function exchangeRateStoredInternal() internal view returns (uint256) {
        uint256 _totalSupply = totalSupply;
        if (_totalSupply == 0) {
            /*
             * If there are no tokens minted:
             *  exchangeRate = initialExchangeRate
             */
            return initialExchangeRateMantissa;
        }

        /*
         * Otherwise:
         *  exchangeRate = (totalCash + totalBorrows - totalReserves) / totalSupply
         */
        uint256 totalCash = getCashPrior();
        uint256 cashPlusBorrowsMinusReserves;
        uint256 exchangeRate;

        cashPlusBorrowsMinusReserves = totalCash + totalBorrows - totalReserves;

        exchangeRate = (cashPlusBorrowsMinusReserves * 1e18) / _totalSupply;

        return exchangeRate;
    }

    /**
     * @notice Get cash balance of this cToken in the underlying asset
     * @return The quantity of underlying asset owned by this contract
     */
    function getCash() external view returns (uint256) {
        return getCashPrior();
    }

    /**
     * @notice Applies accrued interest to total borrows and reserves
     * @dev This calculates interest accrued from the last checkpointed block
     *   up to the current block and writes new checkpoint to storage.
     */
    function accrueInterest() public {
        /* Remember the initial block number */
        uint256 currentBlockNumber = getBlockNumber();
        uint256 accrualBlockNumberPrior = accrualBlockNumber;

        /* Short-circuit accumulating 0 interest */
        if (accrualBlockNumberPrior == currentBlockNumber) {
            return;
        }

        /* Read the previous values out of storage */
        uint256 cashPrior = getCashPrior();
        uint256 borrowsPrior = totalBorrows + totalBorrowsFixed;
        uint256 reservesPrior = totalReserves;
        uint256 borrowIndexPrior = borrowIndex;

        /* Calculate the current borrow interest rate */
        uint256 borrowRateMantissa = interestRateModel.getBorrowRate(
            cashPrior,
            borrowsPrior,
            reservesPrior
        );
        require(
            borrowRateMantissa <= borrowRateMaxMantissa,
            "borrow rate is absurdly high"
        );

        /* Calculate the number of blocks elapsed since the last accrual */
        uint256 blockDelta = currentBlockNumber - accrualBlockNumberPrior;

        /*
         * Calculate the interest accumulated into borrows and reserves and the new index:
         *  simpleInterestFactor = borrowRate * blockDelta
         *  interestAccumulated = simpleInterestFactor * totalBorrows
         *  totalBorrowsNew = interestAccumulated + totalBorrows
         *  totalReservesNew = interestAccumulated * reserveFactor + totalReserves
         *  borrowIndexNew = simpleInterestFactor * borrowIndex + borrowIndex
         */

        uint256 simpleInterestFactor;
        uint256 interestAccumulated;
        uint256 totalBorrowsNew;
        uint256 totalReservesNew;
        uint256 borrowIndexNew;

        simpleInterestFactor = borrowRateMantissa * blockDelta;

        interestAccumulated = (simpleInterestFactor * borrowsPrior) / 1e18;

        totalBorrowsNew = interestAccumulated + borrowsPrior;

        totalReservesNew =
            ((reserveFactorMantissa * interestAccumulated) / 1e18) +
            reservesPrior;

        borrowIndexNew =
            ((simpleInterestFactor * borrowIndexPrior) / 1e18) +
            borrowIndexPrior;

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        /* We write the previously calculated values into storage */
        accrualBlockNumber = currentBlockNumber;
        borrowIndex = borrowIndexNew;
        totalBorrows = totalBorrowsNew;
        totalReserves = totalReservesNew;

        /* We emit an AccrueInterest event */
        emit AccrueInterest(
            cashPrior,
            interestAccumulated,
            borrowIndexNew,
            totalBorrowsNew
        );
    }

    /**
     * @notice Sender supplies assets into the market and receives cTokens in exchange
     * @dev Accrues interest whether or not the operation succeeds, unless reverted
     * @param mintAmount The amount of the underlying asset to supply
     * @return the actual mint amount.
     */
    function mintInternal(uint256 mintAmount)
        internal
        nonReentrant
        returns (uint256)
    {
        accrueInterest();
        // mintFresh emits the actual Mint event if successful and logs on errors, so we don't need to
        return mintFresh(msg.sender, mintAmount);
    }

    /**
     * @notice User supplies assets into the market and receives cTokens in exchange
     * @dev Assumes interest has already been accrued up to the current block
     * @param minter The address of the account which is supplying the assets
     * @param mintAmount The amount of the underlying asset to supply
     * @return the actual mint amount.
     */
    function mintFresh(address minter, uint256 mintAmount)
        internal
        marketFresh
        returns (uint256)
    {
        /* Fail if mint not allowed */
        require(
            comptroller.mintAllowed(address(this), minter, mintAmount),
            "Mint is not allowed"
        );

        uint256 exchangeRateMantissa = exchangeRateStoredInternal();

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        /*
         *  We call doTransferIn for the minter and the mintAmount.
         *  Note: The cToken must handle variations between ERC-20 and ETH underlying.
         *  doTransferIn reverts if anything goes wrong, since we can't be sure if
         *  side-effects occurred. The function returns the amount actually transferred,
         *  in case of a fee. On success, the cToken holds an additional actualMintAmount
         *  of cash.
         */
        uint256 actualMintAmount = doTransferIn(minter, mintAmount);

        /*
         * We get the current exchange rate and calculate the number of cTokens to be minted:
         *  mintTokens = actualMintAmount / exchangeRate
         */

        uint256 mintTokens = (((actualMintAmount * 1e18) * 1e18) /
            exchangeRateMantissa) / 1e18;

        /* We write previously calculated values into storage */
        totalSupply += mintTokens;
        accountTokens[minter] += mintTokens;

        /* We emit a Mint event, and a Transfer event */
        emit Mint(minter, actualMintAmount, mintTokens);
        emit Transfer(address(this), minter, mintTokens);

        return actualMintAmount;
    }

    /**
     * @notice Sender redeems cTokens in exchange for the underlying asset
     * @dev Accrues interest whether or not the operation succeeds, unless reverted
     * @param redeemTokens The number of cTokens to redeem into underlying
     */
    function redeemInternal(uint256 redeemTokens) internal nonReentrant {
        accrueInterest();
        // redeemFresh emits redeem-specific logs on errors, so we don't need to
        redeemFresh(payable(msg.sender), redeemTokens, 0);
    }

    /**
     * @notice Sender redeems cTokens in exchange for a specified amount of underlying asset
     * @dev Accrues interest whether or not the operation succeeds, unless reverted
     * @param redeemAmount The amount of underlying to receive from redeeming cTokens
     */
    function redeemUnderlyingInternal(uint256 redeemAmount)
        internal
        nonReentrant
    {
        accrueInterest();
        // redeemFresh emits redeem-specific logs on errors, so we don't need to
        redeemFresh(payable(msg.sender), 0, redeemAmount);
    }

    /**
     * @notice User redeems cTokens in exchange for the underlying asset
     * @dev Assumes interest has already been accrued up to the current block
     * @param redeemer The address of the account which is redeeming the tokens
     * @param redeemTokensIn The number of cTokens to redeem into underlying (only one of redeemTokensIn or redeemAmountIn may be non-zero)
     * @param redeemAmountIn The number of underlying tokens to receive from redeeming cTokens (only one of redeemTokensIn or redeemAmountIn may be non-zero)
     */
    function redeemFresh(
        address payable redeemer,
        uint256 redeemTokensIn,
        uint256 redeemAmountIn
    ) internal marketFresh {
        require(
            redeemTokensIn == 0 || redeemAmountIn == 0,
            "one of redeemTokensIn or redeemAmountIn must be zero"
        );

        /* exchangeRate = invoke Exchange Rate Stored() */
        uint256 exchangeRateMantissa = exchangeRateStoredInternal();
        uint256 redeemTokens;
        uint256 redeemAmount;

        /* If redeemTokensIn > 0: */
        if (redeemTokensIn > 0) {
            /*
             * We calculate the exchange rate and the amount of underlying to be redeemed:
             *  redeemTokens = redeemTokensIn
             *  redeemAmount = redeemTokensIn x exchangeRateCurrent
             */
            redeemTokens = redeemTokensIn;
            redeemAmount = (exchangeRateMantissa * redeemTokensIn) / 1e18;
        } else {
            /*
             * We get the current exchange rate and calculate the amount to be redeemed:
             *  redeemTokens = redeemAmountIn / exchangeRate
             *  redeemAmount = redeemAmountIn
             */

            redeemTokens =
                (((redeemAmountIn * 1e18) * 1e18) / exchangeRateMantissa) /
                1e18;
            redeemAmount = redeemAmountIn;
        }

        /* Fail if redeem not allowed */
        require(
            comptroller.redeemAllowed(address(this), redeemer, redeemTokens),
            "Redeem is not allowed"
        );

        /* Fail gracefully if protocol has insufficient cash */
        require(redeemAmount < getCashPrior(), "Insufficient amount of cash");

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        /*
         * We invoke doTransferOut for the redeemer and the redeemAmount.
         *  Note: The cToken must handle variations between ERC-20 and ETH underlying.
         *  On success, the cToken has redeemAmount less of cash.
         *  doTransferOut reverts if anything goes wrong, since we can't be sure if side effects occurred.
         */
        doTransferOut(redeemer, redeemAmount);

        /* We write previously calculated values into storage */
        totalSupply -= redeemTokens;
        accountTokens[redeemer] -= redeemTokens;

        /* We emit a Transfer event, and a Redeem event */
        emit Transfer(redeemer, address(this), redeemTokens);
        emit Redeem(redeemer, redeemAmount, redeemTokens);

        /* We call the defense hook */
        comptroller.redeemVerify(
            address(this),
            redeemer,
            redeemAmount,
            redeemTokens
        );
    }

    function borrowFixedRate(uint256 borrowAmount, uint256 maturity)
        internal
        nonReentrant
    {
        require(borrowAmount != 0, "Wrong borrow amount");
        require(
            maturity == 1 weeks || maturity == 2 weeks || maturity == 4 weeks,
            "Wrong maturity provided"
        );
        accrueInterest();
        borrowFixedRateFresh(payable(msg.sender), borrowAmount, maturity);
    }

    function borrowFixedRateFresh(
        address payable borrower,
        uint256 borrowAmount,
        uint256 maturity
    ) internal marketFresh {
        /* Fail if borrow not allowed */
        require(
            comptroller.borrowAllowed(address(this), borrower, borrowAmount),
            "Borrow is not allowed"
        );

        uint256 cashPrior = getCashPrior();
        /* Fail gracefully if protocol has insufficient underlying cash */
        require(borrowAmount < cashPrior, "Insufficient cash");
        doTransferOut(borrower, borrowAmount);

        /* Calculate the current borrow interest rate */
        uint256 borrowRateMantissa = interestRateModel.getBorrowRate(
            cashPrior,
            totalBorrows + totalBorrowsFixed,
            totalReserves
        );

        accountFixedRateBorrows[borrower].push(
            FixedRateBorrow({
                amount: borrowAmount,
                rate: borrowRateMantissa,
                openedAt: block.timestamp,
                duration: maturity
            })
        );

        uint256 interestedAccumulated = (borrowAmount * borrowRateMantissa) /
            1e18;
        totalBorrowsFixed += borrowAmount + interestedAccumulated;
        totalReserves += (interestedAccumulated * reserveFactorMantissa) / 1e18;

        emit BorrowFixedRate(borrower, borrowAmount, block.timestamp, maturity);
    }

    /**
     * @notice Sender borrows assets from the protocol to their own address
     * @param borrowAmount The amount of the underlying asset to borrow
     */
    function borrowInternal(uint256 borrowAmount) internal nonReentrant {
        accrueInterest();
        borrowFresh(payable(msg.sender), borrowAmount);
    }

    /**
     * @notice Users borrow assets from the protocol to their own address
     * @param borrowAmount The amount of the underlying asset to borrow
     */
    function borrowFresh(address payable borrower, uint256 borrowAmount)
        internal
        marketFresh
    {
        /* Fail if borrow not allowed */
        require(
            comptroller.borrowAllowed(address(this), borrower, borrowAmount),
            "Borrow is not allowed"
        );

        /* Fail gracefully if protocol has insufficient underlying cash */
        require(borrowAmount < getCashPrior(), "Insufficient cash");

        uint256 accountBorrowsStored = borrowBalanceStoredInternal(borrower);
        uint256 accountBorrowsNew = accountBorrowsStored + borrowAmount;

        doTransferOut(borrower, borrowAmount);

        /* We write the previously calculated values into storage */
        accountBorrows[borrower].principal = accountBorrowsNew;
        accountBorrows[borrower].interestIndex = borrowIndex;
        totalBorrows += borrowAmount;

        /* We emit a Borrow event */
        emit Borrow(borrower, borrowAmount, accountBorrowsNew, totalBorrows);
    }

    function repayBorrowFixedRate(uint256[] memory borrowsIndexes)
        internal
        nonReentrant
    {
        accrueInterest();
        repayBorrowFixedRateFresh(msg.sender, msg.sender, borrowsIndexes);
    }

    function repayBorrowFixedRateOnBehalf(
        address borrower,
        uint256[] memory borrowsIndexes
    ) internal nonReentrant {
        accrueInterest();
        repayBorrowFixedRateFresh(msg.sender, borrower, borrowsIndexes);
    }

    function repayBorrowFixedRateFresh(
        address payer,
        address borrower,
        uint256[] memory borrowsIndexes
    ) internal marketFresh returns (uint256[] memory actualRepayAmounts) {
        FixedRateBorrow[] storage borrows = accountFixedRateBorrows[borrower];
        uint256 totalRepayAmount;
        uint256 borrowsFixedToSub;
        actualRepayAmounts = new uint256[](borrowsIndexes.length);

        // Calculate how much to pay for borrows
        uint256 repaid;
        for (uint256 i = 0; i < borrowsIndexes.length; i++) {
            uint256 interestAccumulated = (borrows[borrowsIndexes[i]].amount *
                borrows[borrowsIndexes[i]].rate) / 1e18;
            if (
                block.timestamp >=
                borrows[borrowsIndexes[i]].openedAt +
                    borrows[borrowsIndexes[i]].duration
            ) {
                repaid = borrows[borrowsIndexes[i]].amount +
                    interestAccumulated;
                totalRepayAmount += repaid;
                borrowsFixedToSub += repaid;
            } else {
                borrowsFixedToSub +=
                    borrows[borrowsIndexes[i]].amount +
                    interestAccumulated;

                uint256 timeDelta = block.timestamp -
                    borrows[borrowsIndexes[i]].openedAt;
                // TODO extra coefficient for repaying before maturity is reached
                repaid = borrows[borrowsIndexes[i]].amount +
                    ((interestAccumulated * timeDelta) /
                        borrows[borrowsIndexes[i]].duration);

                totalRepayAmount += repaid;
            }
            borrows[borrowsIndexes[i]].amount = 0;
            actualRepayAmounts[i] = repaid;
        }

        /* Fail if repayBorrow not allowed */
        require(
            comptroller.repayBorrowAllowed(
                address(this),
                payer,
                borrower,
                totalRepayAmount
            ),
            "Repay is not allowed"
        );

        doTransferIn(payer, totalRepayAmount);
        totalBorrowsFixed -= borrowsFixedToSub;

        // Remove repaid borrows
        for (uint256 i = 0; i < borrows.length; i++) {
            if (borrows[i].amount == 0) {
                borrows[i] = borrows[borrows.length - 1];
                borrows.pop();
                i--;
            }
        }

        emit RepayBorrowFixedRate(
            payer,
            borrower,
            totalRepayAmount,
            totalBorrowsFixed,
            actualRepayAmounts
        );

        return actualRepayAmounts;
    }

    /**
     * @notice Sender repays their own borrow
     * @param repayAmount The amount to repay
     * @return the actual repayment amount.
     */
    function repayBorrowInternal(uint256 repayAmount)
        internal
        nonReentrant
        returns (uint256)
    {
        accrueInterest();
        // repayBorrowFresh emits repay-borrow-specific logs on errors, so we don't need to
        return repayBorrowFresh(msg.sender, msg.sender, repayAmount);
    }

    /**
     * @notice Sender repays a borrow belonging to borrower
     * @param borrower the account with the debt being payed off
     * @param repayAmount The amount to repay
     * @return the actual repayment amount.
     */
    function repayBorrowBehalfInternal(address borrower, uint256 repayAmount)
        internal
        nonReentrant
        returns (uint256)
    {
        accrueInterest();
        // repayBorrowFresh emits repay-borrow-specific logs on errors, so we don't need to
        return repayBorrowFresh(msg.sender, borrower, repayAmount);
    }

    /**
     * @notice Borrows are repaid by another user (possibly the borrower).
     * @param payer the account paying off the borrow
     * @param borrower the account with the debt being payed off
     * @param repayAmount the amount of undelrying tokens being returned
     * @return the actual repayment amount.
     */
    function repayBorrowFresh(
        address payer,
        address borrower,
        uint256 repayAmount
    ) internal marketFresh returns (uint256) {
        /* Fail if repayBorrow not allowed */
        require(
            comptroller.repayBorrowAllowed(
                address(this),
                payer,
                borrower,
                repayAmount
            ),
            "Repay is not allowed"
        );

        /* We fetch the amount the borrower owes, with accumulated interest */
        uint256 accountBorrowsStored = borrowBalanceStoredInternal(borrower);

        /* If repayAmount == -1, repayAmount = accountBorrows */
        if (repayAmount == type(uint256).max) {
            repayAmount = accountBorrowsStored;
        }

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        /*
         * We call doTransferIn for the payer and the repayAmount
         *  Note: The cToken must handle variations between ERC-20 and ETH underlying.
         *  On success, the cToken holds an additional repayAmount of cash.
         *  doTransferIn reverts if anything goes wrong, since we can't be sure if side effects occurred.
         *   it returns the amount actually transferred, in case of a fee.
         */
        uint256 actualRepayAmount = doTransferIn(payer, repayAmount);
        uint256 accountBorrowsNew = accountBorrowsStored - actualRepayAmount;

        /* We write the previously calculated values into storage */
        accountBorrows[borrower].principal = accountBorrowsNew;
        accountBorrows[borrower].interestIndex = borrowIndex;
        totalBorrows -= actualRepayAmount;

        /* We emit a RepayBorrow event */
        emit RepayBorrow(
            payer,
            borrower,
            actualRepayAmount,
            accountBorrowsNew,
            totalBorrows
        );
        return actualRepayAmount;
    }

    function liquidateBorrowFixedRate(address borrower, uint256[] memory borrowsIndexes, ICToken[] memory cTokenCollaterals) internal nonReentrant {
        accrueInterest();
        liquidateBorrowFixedRate(msg.sender, borrower, borrowsIndexes, cTokenCollaterals);
    }

    function liquidateBorrowFixedRate(address liquidator, address borrower, uint256[] memory borrowsIndexes, ICToken[] memory cTokenCollaterals) internal marketFresh {
        /* Fail if borrower = liquidator */
        require(borrower != liquidator, "Can't liquidate your own position");

        // Verify that all the borrows can be liquidated
        _liquidateFixedBorrowsAllowed(borrower, borrowsIndexes);

        uint256[] memory actualRepayAmounts = repayBorrowFixedRateFresh(
            liquidator,
            borrower,
            borrowsIndexes
        );

        // Calculate seize tokens
        for (uint256 i = 0; i < actualRepayAmounts.length; i++) {
            /* We calculate the number of collateral tokens that will be seized */
            uint256 seizeTokens = comptroller.liquidateCalculateSeizeTokens(
                address(this),
                address(cTokenCollaterals[i]),
                actualRepayAmounts[i]
            );

            /* Revert if borrower collateral token balance < seizeTokens */
            require(
                cTokenCollaterals[i].balanceOf(borrower) >= seizeTokens,
                "LIQUIDATE_SEIZE_TOO_MUCH"
            );

            // If this is also the collateral, run seizeInternal to avoid re-entrancy, otherwise make an external call
            if (address(cTokenCollaterals[i]) == address(this)) {
                seizeInternal(address(this), liquidator, borrower, seizeTokens);
            } else {
                cTokenCollaterals[i].seize(liquidator, borrower, seizeTokens);
            }
        }

        emit LiquidateBorrowFixedRate(
            liquidator,
            borrower,
            actualRepayAmounts,
            cTokenCollaterals
        );
    }

    function _liquidateFixedBorrowsAllowed(address borrower, uint256[] memory borrowsIndexes) internal {
        FixedRateBorrow[] storage borrows = accountFixedRateBorrows[borrower];
        for (uint256 i = 0; i < borrowsIndexes.length; i++) {
            require(block.timestamp > borrows[borrowsIndexes[i]].openedAt + borrows[borrowsIndexes[i]].duration + restPeriod, "Cannot liquidate fixed rate borrow");
        }
    }

    /**
     * @notice The sender liquidates the borrowers collateral.
     *  The collateral seized is transferred to the liquidator.
     * @param borrower The borrower of this cToken to be liquidated
     * @param cTokenCollateral The market in which to seize collateral from the borrower
     * @param repayAmount The amount of the underlying borrowed asset to repay
     * @return the actual repayment amount.
     */
    function liquidateBorrowInternal(
        address borrower,
        uint256 repayAmount,
        ICToken cTokenCollateral
    ) internal nonReentrant returns (uint256) {
        accrueInterest();
        cTokenCollateral.accrueInterest();
        // liquidateBorrowFresh emits borrow-specific logs on errors, so we don't need to
        return
            liquidateBorrowFresh(
                msg.sender,
                borrower,
                repayAmount,
                cTokenCollateral
            );
    }

    /**
     * @notice The liquidator liquidates the borrowers collateral.
     *  The collateral seized is transferred to the liquidator.
     * @param borrower The borrower of this cToken to be liquidated
     * @param liquidator The address repaying the borrow and seizing collateral
     * @param cTokenCollateral The market in which to seize collateral from the borrower
     * @param repayAmount The amount of the underlying borrowed asset to repay
     * @return the actual repayment amount.
     */
    function liquidateBorrowFresh(
        address liquidator,
        address borrower,
        uint256 repayAmount,
        ICToken cTokenCollateral
    ) internal returns (uint256) {
        /* Fail if liquidate not allowed */
        require(
            comptroller.liquidateBorrowAllowed(
                address(this),
                address(cTokenCollateral),
                liquidator,
                borrower,
                repayAmount
            ),
            "Liquidate is not allowed"
        );

        /* Verify market's block number equals current block number */
        require(
            accrualBlockNumber == getBlockNumber() &&
                cTokenCollateral.getAccrualBlockNumber() == getBlockNumber(),
            "Market is not fresh"
        );

        /* Fail if borrower = liquidator */
        require(borrower != liquidator, "Can't liquidate your own position");

        /* Fail if repayAmount = 0 */
        require(
            repayAmount != 0 && repayAmount != type(uint256).max,
            "Invalid repay amount"
        );

        /* Fail if repayBorrow fails */
        uint256 actualRepayAmount = repayBorrowFresh(
            liquidator,
            borrower,
            repayAmount
        );

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        /* We calculate the number of collateral tokens that will be seized */
        uint256 seizeTokens = comptroller.liquidateCalculateSeizeTokens(
            address(this),
            address(cTokenCollateral),
            actualRepayAmount
        );

        /* Revert if borrower collateral token balance < seizeTokens */
        require(
            cTokenCollateral.balanceOf(borrower) >= seizeTokens,
            "LIQUIDATE_SEIZE_TOO_MUCH"
        );

        // If this is also the collateral, run seizeInternal to avoid re-entrancy, otherwise make an external call
        if (address(cTokenCollateral) == address(this)) {
            seizeInternal(address(this), liquidator, borrower, seizeTokens);
        } else {
            cTokenCollateral.seize(liquidator, borrower, seizeTokens);
        }

        /* We emit a LiquidateBorrow event */
        emit LiquidateBorrow(
            liquidator,
            borrower,
            actualRepayAmount,
            address(cTokenCollateral),
            seizeTokens
        );
        return actualRepayAmount;
    }

    /**
     * @notice Transfers collateral tokens (this market) to the liquidator.
     * @dev Will fail unless called by another cToken during the process of liquidation.
     *  Its absolutely critical to use msg.sender as the borrowed cToken and not a parameter.
     * @param liquidator The account receiving seized collateral
     * @param borrower The account having collateral seized
     * @param seizeTokens The number of cTokens to seize
     */
    function seize(
        address liquidator,
        address borrower,
        uint256 seizeTokens
    ) external nonReentrant {
        return seizeInternal(msg.sender, liquidator, borrower, seizeTokens);
    }

    /**
     * @notice Transfers collateral tokens (this market) to the liquidator.
     * @dev Called only during an in-kind liquidation, or by liquidateBorrow during the liquidation of another CToken.
     *  Its absolutely critical to use msg.sender as the seizer cToken and not a parameter.
     * @param seizerToken The contract seizing the collateral (i.e. borrowed cToken)
     * @param liquidator The account receiving seized collateral
     * @param borrower The account having collateral seized
     * @param seizeTokens The number of cTokens to seize
     */
    function seizeInternal(
        address seizerToken,
        address liquidator,
        address borrower,
        uint256 seizeTokens
    ) internal {
        /* Fail if seize not allowed */
        require(
            comptroller.seizeAllowed(
                address(this),
                seizerToken,
                liquidator,
                borrower,
                seizeTokens
            ),
            "Seize is not allowed"
        );

        /* Fail if borrower = liquidator */
        require(liquidator != borrower, "Can't liquidate your own position");

        /*
         * We calculate the new borrower and liquidator token balances, failing on underflow/overflow:
         *  borrowerTokensNew = accountTokens[borrower] - seizeTokens
         *  liquidatorTokensNew = accountTokens[liquidator] + seizeTokens
         */
        uint256 protocolSeizeTokens = (seizeTokens *
            protocolSeizeShareMantissa) / 1e18;
        uint256 liquidatorSeizeTokens = seizeTokens - protocolSeizeTokens;
        uint256 exchangeRateMantissa = exchangeRateStoredInternal();
        uint256 protocolSeizeAmount = (exchangeRateMantissa *
            protocolSeizeTokens) / 1e18;

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        /* We write the previously calculated values into storage */
        totalReserves += protocolSeizeAmount;
        totalSupply -= protocolSeizeAmount;
        accountTokens[borrower] -= seizeTokens;
        accountTokens[liquidator] += liquidatorSeizeTokens;

        /* Emit a Transfer event */
        emit Transfer(borrower, liquidator, liquidatorSeizeTokens);
        emit Transfer(borrower, address(this), protocolSeizeTokens);
        emit ReservesAdded(address(this), protocolSeizeAmount, totalReserves);
    }

    /*** Admin Functions ***/

    /**
     * @notice Begins transfer of admin rights. The newPendingAdmin must call _acceptAdmin to finalize the transfer.
     * @dev Admin function to begin change of admin. The newPendingAdmin must call _acceptAdmin to finalize the transfer.
     * @param newPendingAdmin New pending admin.
     */
    function setPendingAdmin(address payable newPendingAdmin)
        external
        onlyAdmin(msg.sender)
    {
        require(newPendingAdmin != address(0), "Zero address");
        address oldPendingAdmin = pendingAdmin;
        pendingAdmin = newPendingAdmin;
        emit NewPendingAdmin(oldPendingAdmin, newPendingAdmin);
    }

    /**
     * @notice Accepts transfer of admin rights. msg.sender must be pendingAdmin
     * @dev Admin function for pending admin to accept role and update admin
     */
    function acceptAdmin() external {
        // Check caller is pendingAdmin and pendingAdmin != address(0)
        require(msg.sender == pendingAdmin, "Caller is not a pending admin");

        address oldAdmin = admin;
        address oldPendingAdmin = pendingAdmin;

        // Store admin with value pendingAdmin
        admin = pendingAdmin;

        // Clear the pending value
        pendingAdmin = payable(address(0));

        emit NewAdmin(oldAdmin, admin);
        emit NewPendingAdmin(oldPendingAdmin, pendingAdmin);
    }

    /**
     * @notice Sets a new comptroller for the market
     * @dev Admin function to set a new comptroller
     */
    function setController(IController newComptroller)
        public
        onlyAdmin(msg.sender)
    {
        IController oldComptroller = comptroller;
        // Ensure invoke comptroller.isComptroller() returns true
        require(newComptroller.isController(), "marker method returned false");

        comptroller = newComptroller;
        emit NewComptroller(oldComptroller, newComptroller);
    }

    /**
     * @notice accrues interest and sets a new reserve factor for the protocol using _setReserveFactorFresh
     * @dev Admin function to accrue interest and set a new reserve factor
     */
    function setReserveFactor(uint256 newReserveFactorMantissa)
        external
        nonReentrant
        onlyAdmin(msg.sender)
    {
        accrueInterest();
        // _setReserveFactorFresh emits reserve-factor-specific logs on errors, so we don't need to.
        return _setReserveFactorFresh(newReserveFactorMantissa);
    }

    function setRestPeriod(uint256 newRestPeriod)
        external
        onlyAdmin(msg.sender)
    {
        restPeriod = newRestPeriod;
    }

    /**
     * @notice Sets a new reserve factor for the protocol (*requires fresh interest accrual)
     * @dev Admin function to set a new reserve factor
     */
    function _setReserveFactorFresh(uint256 newReserveFactorMantissa)
        internal
        marketFresh
    {
        // Check newReserveFactor <= maxReserveFactor
        require(
            newReserveFactorMantissa <= reserveFactorMaxMantissa,
            "Wrong reserve factor"
        );

        uint256 oldReserveFactorMantissa = reserveFactorMantissa;
        reserveFactorMantissa = newReserveFactorMantissa;
        emit NewReserveFactor(
            oldReserveFactorMantissa,
            newReserveFactorMantissa
        );
    }

    /**
     * @notice Accrues interest and reduces reserves by transferring from msg.sender
     * @param addAmount Amount of addition to reserves
     */
    function _addReservesInternal(uint256 addAmount) internal nonReentrant {
        accrueInterest();

        // _addReservesFresh emits reserve-addition-specific logs on errors, so we don't need to.
        _addReservesFresh(addAmount);
    }

    /**
     * @notice Add reserves by transferring from caller
     * @dev Requires fresh interest accrual
     * @param addAmount Amount of addition to reserves
     * @return the actual amount added, net token fees
     */
    function _addReservesFresh(uint256 addAmount)
        internal
        marketFresh
        returns (uint256)
    {
        // totalReserves + actualAddAmount
        uint256 actualAddAmount;

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        /*
         * We call doTransferIn for the caller and the addAmount
         *  Note: The cToken must handle variations between ERC-20 and ETH underlying.
         *  On success, the cToken holds an additional addAmount of cash.
         *  doTransferIn reverts if anything goes wrong, since we can't be sure if side effects occurred.
         *  it returns the amount actually transferred, in case of a fee.
         */

        actualAddAmount = doTransferIn(msg.sender, addAmount);

        // Store reserves[n+1] = reserves[n] + actualAddAmount
        totalReserves += actualAddAmount;

        /* Emit NewReserves(admin, actualAddAmount, reserves[n+1]) */
        emit ReservesAdded(msg.sender, actualAddAmount, totalReserves);

        return actualAddAmount;
    }

    /**
     * @notice Accrues interest and reduces reserves by transferring to admin
     * @param reduceAmount Amount of reduction to reserves
     */
    function reduceReserves(uint256 reduceAmount)
        external
        nonReentrant
        onlyAdmin(msg.sender)
    {
        accrueInterest();
        // _reduceReservesFresh emits reserve-reduction-specific logs on errors, so we don't need to.
        return _reduceReservesFresh(reduceAmount);
    }

    /**
     * @notice Reduces reserves by transferring to admin
     * @dev Requires fresh interest accrual
     * @param reduceAmount Amount of reduction to reserves)
     */
    function _reduceReservesFresh(uint256 reduceAmount) internal marketFresh {
        // Fail gracefully if protocol has insufficient underlying cash
        require(reduceAmount <= getCashPrior(), "Insufficient cash");
        require(reduceAmount <= totalReserves, "Insufficient reserves");

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        // Store reserves[n+1] = reserves[n] - reduceAmount
        totalReserves -= reduceAmount;

        // doTransferOut reverts if anything goes wrong, since we can't be sure if side effects occurred.
        doTransferOut(admin, reduceAmount);

        emit ReservesReduced(admin, reduceAmount, totalReserves);
    }

    /**
     * @notice accrues interest and updates the interest rate model using _setInterestRateModelFresh
     * @dev Admin function to accrue interest and update the interest rate model
     * @param newInterestRateModel the new interest rate model to use
     */
    function setInterestRateModel(IInterestRateModel newInterestRateModel)
        public
        onlyAdmin(msg.sender)
    {
        accrueInterest();
        // _setInterestRateModelFresh emits interest-rate-model-update-specific logs on errors, so we don't need to.
        _setInterestRateModelFresh(newInterestRateModel);
    }

    /**
     * @notice updates the interest rate model (*requires fresh interest accrual)
     * @dev Admin function to update the interest rate model
     * @param newInterestRateModel the new interest rate model to use
     */
    function _setInterestRateModelFresh(IInterestRateModel newInterestRateModel)
        internal
        marketFresh
    {
        // Used to store old model for use in the event that is emitted on success
        IInterestRateModel oldInterestRateModel;

        // Track the market's current interest rate model
        oldInterestRateModel = interestRateModel;

        // Ensure invoke newInterestRateModel.isInterestRateModel() returns true
        require(
            newInterestRateModel.isInterestRateModel(),
            "marker method returned false"
        );

        // Set the interest rate model to newInterestRateModel
        interestRateModel = newInterestRateModel;

        // Emit NewMarketInterestRateModel(oldInterestRateModel, newInterestRateModel)
        emit NewMarketInterestRateModel(
            oldInterestRateModel,
            newInterestRateModel
        );
    }

    /*** Safe Token ***/

    /**
     * @notice Gets balance of this contract in terms of the underlying
     * @dev This excludes the value of the current message, if any
     * @return The quantity of underlying owned by this contract
     */
    function getCashPrior() internal view virtual returns (uint256);

    /**
     * @dev Performs a transfer in, reverting upon failure. Returns the amount actually transferred to the protocol, in case of a fee.
     *  This may revert due to insufficient balance or insufficient allowance.
     */
    function doTransferIn(address from, uint256 amount)
        internal
        virtual
        returns (uint256);

    /**
     * @dev Performs a transfer out, ideally returning an explanatory error code upon failure tather than reverting.
     *  If caller has not called checked protocol's balance, may revert due to insufficient cash held in the contract.
     *  If caller has checked protocol's balance, and verified it is >= amount, this should not revert in normal conditions.
     */
    function doTransferOut(address payable to, uint256 amount) internal virtual;

    /*** Reentrancy Guard ***/

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     */
    modifier nonReentrant() {
        require(_notEntered, "re-entered");
        _notEntered = false;
        _;
        _notEntered = true; // get a gas-refund post-Istanbul
    }
}
