// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "./interfaces/IMToken.sol";
import "./interfaces/IController.sol";
import "./interfaces/IMErc20.sol";
import "./interfaces/IControllerEvents.sol";
import "./ControllerStorage.sol";
import "./Unitroller.sol";
import "./Governance/Neb.sol";

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/**
 * @title Nebula Lending Controller Contract
 * @author Blaize.tech
 */
contract Controller is ControllerV7Storage, IController, IControllerEvents {
    /// @notice Indicator that this is a Controller contract (for inspection)
    bool public constant isController = true;
    /// @notice The initial NEB index for a market
    uint224 public constant nebInitialIndex = 1e36;
    // closeFactorMantissa must be strictly greater than this value
    uint256 internal constant closeFactorMinMantissa = 0.05e18; // 0.05
    // closeFactorMantissa must not exceed this value
    uint256 internal constant closeFactorMaxMantissa = 0.9e18; // 0.9
    // No collateralFactorMantissa may exceed this value
    uint256 internal constant collateralFactorMaxMantissa = 0.9e18; // 0.9

    modifier onlyAdmin(address _caller) {
        require(_caller == admin, "Caller is not an admin");
        _;
    }

    constructor() {
        admin = msg.sender;
    }

    /*** Assets You Are In ***/

    /**
     * @notice Returns the assets an account has entered
     * @param account The address of the account to pull assets for
     * @return A dynamic list with the assets the account has entered
     */
    function getAssetsIn(address account) external view returns (IMToken[] memory) {
        IMToken[] memory assetsIn = accountAssets[account];

        return assetsIn;
    }

    /**
     * @notice Returns whether the given account is entered in the given asset
     * @param account The address of the account to check
     * @param mToken The mToken to check
     * @return True if the account is in the asset, otherwise false.
     */
    function checkMembership(address account, IMToken mToken) external view returns (bool) {
        return accountMembership[address(mToken)][account];
    }

    /**
     * @notice Add assets to be included in account liquidity calculation
     * @param mTokens The list of addresses of the mToken markets to be enabled
     */
    function enterMarkets(address[] memory mTokens) public {
        for (uint256 i = 0; i < mTokens.length; i++) {
            IMToken mToken = IMToken(mTokens[i]);

            addToMarketInternal(mToken, msg.sender);
        }
    }

    /**
     * @notice Add the market to the borrowers "assets in" for liquidity calculations
     * @param mToken The market to enter
     * @param borrower The address of the account to modify
     */
    function addToMarketInternal(IMToken mToken, address borrower) internal {
        Market storage marketToJoin = markets[address(mToken)];

        require(marketToJoin.isListed, "Market is not listed");

        if (accountMembership[address(mToken)][borrower]) {
            // already joined
            return;
        }

        // survived the gauntlet, add to list
        // NOTE: we store these somewhat redundantly as a significant optimization
        //  this avoids having to iterate through the list for the most common use cases
        //  that is, only when we need to perform liquidity checks
        //  and not whenever we want to check if an account is in a particular market
        accountMembership[address(mToken)][borrower] = true;
        accountAssets[borrower].push(mToken);

        emit MarketEntered(mToken, borrower);
    }

    /**
     * @notice Removes asset from senders account liquidity calculation
     * @dev Sender must not have an outstanding borrow balance in the asset,
     *  or be providing necessary collateral for an outstanding borrow.
     * @param mTokenAddress The address of the asset to be removed
     */
    function exitMarket(address mTokenAddress) external {
        IMToken mToken = IMToken(mTokenAddress);
        /* Get sender tokensHeld and amountOwed underlying from the mToken */
        (uint256 tokensHeld, uint256 amountOwed, , ) = mToken.getAccountSnapshot(msg.sender);

        /* Fail if the sender has a borrow balance */
        require(amountOwed == 0, "User has a borrow balance");

        /* Fail if the sender is not permitted to redeem all of their tokens */
        require(redeemAllowedInternal(mTokenAddress, msg.sender, tokensHeld), "User is not allowed to redeem");

        Market storage marketToExit = markets[address(mToken)];

        /* Return true if the sender is not already in  the market */
        require(accountMembership[address(mToken)][msg.sender], "User is not in market");

        /* Set mToken account membership to false */
        accountMembership[address(mToken)][msg.sender] = false;

        /* Delete mToken from the account s list of assets */
        // load into memory for faster iteration
        IMToken[] memory userAssetList = accountAssets[msg.sender];
        uint256 len = userAssetList.length;
        uint256 assetIndex = len;
        for (uint256 i = 0; i < len; i++) {
            if (userAssetList[i] == mToken) {
                assetIndex = i;
                break;
            }
        }

        // We *must* have found the asset in the list or our redundant data structure is broken
        assert(assetIndex < len);

        // copy last item in list to location of item to be removed, reduce length by 1
        IMToken[] storage storedList = accountAssets[msg.sender];
        storedList[assetIndex] = storedList[storedList.length - 1];
        storedList.pop();

        emit MarketExited(mToken, msg.sender);
    }

    /*** Policy Hooks ***/

    /**
     * @notice Checks if the account should be allowed to mint tokens in the given market
     * @param mToken The market to verify the mint against
     * @param minter The account which would get the minted tokens
     * @param mintAmount The amount of underlying being supplied to the market in exchange for tokens
     */
    function mintAllowed(
        address mToken,
        address minter,
        uint256 mintAmount
    ) external returns (bool) {
        // Pausing is a very serious situation - we revert to sound the alarms
        require(!mintGuardianPaused[mToken], "mint is paused");

        // Shh - currently unused
        minter;
        mintAmount;

        require(markets[mToken].isListed, "Market is not listed");

        // Keep the flywheel moving
        updateNebSupplyIndex(mToken);
        distributeSupplierNeb(mToken, minter);

        return true;
    }

    /**
     * @notice Validates mint and reverts on rejection. May emit logs.
     * @param mToken Asset being minted
     * @param minter The address minting the tokens
     * @param actualMintAmount The amount of the underlying asset being minted
     * @param mintTokens The number of tokens being minted
     */
    function mintVerify(
        address mToken,
        address minter,
        uint256 actualMintAmount,
        uint256 mintTokens
    ) external {
        // Shh - currently unused
        mToken;
        minter;
        actualMintAmount;
        mintTokens;

        // Shh - we dont ever want this hook to be marked pure
        if (false) {
            maxAssets = maxAssets;
        }
    }

    /**
     * @notice Checks if the account should be allowed to redeem tokens in the given market
     * @param mToken The market to verify the redeem against
     * @param redeemer The account which would redeem the tokens
     * @param redeemTokens The number of mTokens to exchange for the underlying asset in the market
     */
    function redeemAllowed(
        address mToken,
        address redeemer,
        uint256 redeemTokens
    ) external returns (bool) {
        require(redeemAllowedInternal(mToken, redeemer, redeemTokens), "Redeem is not allowed");

        // Keep the flywheel moving
        updateNebSupplyIndex(mToken);
        distributeSupplierNeb(mToken, redeemer);

        return true;
    }

    function redeemAllowedInternal(
        address mToken,
        address redeemer,
        uint256 redeemTokens
    ) internal view returns (bool) {
        if (!markets[mToken].isListed) {
            return false;
        }

        /* If the redeemer is not in the market, then we can bypass the liquidity check */
        if (!accountMembership[address(mToken)][redeemer]) {
            return true;
        }

        /* Otherwise, perform a hypothetical liquidity check to guard against shortfall */
        (, uint256 shortfall) = getHypotheticalAccountLiquidityInternal(
            redeemer,
            IMToken(mToken),
            redeemTokens,
            0,
            true
        );
        if (shortfall > 0) {
            return false;
        }

        return true;
    }

    /**
     * @notice Validates redeem and reverts on rejection. May emit logs.
     * @param mToken Asset being redeemed
     * @param redeemer The address redeeming the tokens
     * @param redeemAmount The amount of the underlying asset being redeemed
     * @param redeemTokens The number of tokens being redeemed
     */
    function redeemVerify(
        address mToken,
        address redeemer,
        uint256 redeemAmount,
        uint256 redeemTokens
    ) external {
        // Shh - currently unused
        mToken;
        redeemer;

        // Require tokens is zero or amount is also zero
        if (redeemTokens == 0 && redeemAmount > 0) {
            revert("redeemTokens zero");
        }
    }

    /**
     * @notice Checks if the account should be allowed to borrow the underlying asset of the given market
     * @param mToken The market to verify the borrow against
     * @param borrower The account which would borrow the asset
     * @param borrowAmount The amount of underlying the account would borrow
     */
    function borrowAllowed(
        address mToken,
        address borrower,
        uint256 borrowAmount
    ) external returns (bool) {
        // Pausing is a very serious situation - we revert to sound the alarms
        require(!borrowGuardianPaused[mToken], "borrow is paused");
        require(markets[mToken].isListed, "Market is not listed");

        if (!accountMembership[address(mToken)][borrower]) {
            // only mTokens may call borrowAllowed if borrower not in market
            require(msg.sender == mToken, "sender must be mToken");

            // attempt to add borrower to the market
            addToMarketInternal(IMToken(msg.sender), borrower);

            // it should be impossible to break the important invariant
            assert(accountMembership[address(mToken)][borrower]);
        }

        require(oracle.getUnderlyingPrice(IMToken(mToken)) != 0, "Failed to get underlying price");

        uint256 borrowCap = borrowCaps[mToken];
        // Borrow cap of 0 corresponds to unlimited borrowing
        if (borrowCap != 0) {
            uint256 totalBorrows = IMToken(mToken).getTotalBorrows();
            uint256 nextTotalBorrows = totalBorrows + borrowAmount;
            require(nextTotalBorrows < borrowCap, "market borrow cap reached");
        }

        (, uint256 shortfall) = getHypotheticalAccountLiquidityInternal(
            borrower,
            IMToken(mToken),
            0,
            borrowAmount,
            true
        );
        require(shortfall == 0, "Insufficient liquidity");

        // Keep the flywheel moving
        uint256 borrowIndex = IMToken(mToken).borrowIndex();
        updateNebBorrowIndex(mToken, borrowIndex);
        distributeBorrowerNeb(mToken, borrower, borrowIndex);

        return true;
    }

    /**
     * @notice Validates borrow and reverts on rejection. May emit logs.
     * @param mToken Asset whose underlying is being borrowed
     * @param borrower The address borrowing the underlying
     * @param borrowAmount The amount of the underlying asset requested to borrow
     */
    function borrowVerify(
        address mToken,
        address borrower,
        uint256 borrowAmount
    ) external {
        // Shh - currently unused
        mToken;
        borrower;
        borrowAmount;

        // Shh - we dont ever want this hook to be marked pure
        if (false) {
            maxAssets = maxAssets;
        }
    }

    /**
     * @notice Checks if the account should be allowed to repay a borrow in the given market
     * @param mToken The market to verify the repay against
     * @param payer The account which would repay the asset
     * @param borrower The account which would borrowed the asset
     * @param repayAmount The amount of the underlying asset the account would repay
     */
    function repayBorrowAllowed(
        address mToken,
        address payer,
        address borrower,
        uint256 repayAmount
    ) external returns (bool) {
        // Shh - currently unused
        payer;
        borrower;
        repayAmount;

        require(markets[mToken].isListed, "Market is not listed");

        // Keep the flywheel moving
        uint256 borrowIndex = IMToken(mToken).borrowIndex();
        updateNebBorrowIndex(mToken, borrowIndex);
        distributeBorrowerNeb(mToken, borrower, borrowIndex);

        return true;
    }

    /**
     * @notice Validates repayBorrow and reverts on rejection. May emit logs.
     * @param mToken Asset being repaid
     * @param payer The address repaying the borrow
     * @param borrower The address of the borrower
     * @param actualRepayAmount The amount of underlying being repaid
     */
    function repayBorrowVerify(
        address mToken,
        address payer,
        address borrower,
        uint256 actualRepayAmount,
        uint256 borrowerIndex
    ) external {
        // Shh - currently unused
        mToken;
        payer;
        borrower;
        actualRepayAmount;
        borrowerIndex;

        // Shh - we dont ever want this hook to be marked pure
        if (false) {
            maxAssets = maxAssets;
        }
    }

    /**
     * @notice Checks if the liquidation should be allowed to occur
     * @param mTokenBorrowed Asset which was borrowed by the borrower
     * @param mTokenCollateral Asset which was used as collateral and will be seized
     * @param liquidator The address repaying the borrow and seizing the collateral
     * @param borrower The address of the borrower
     * @param repayAmount The amount of underlying being repaid
     */
    function liquidateBorrowAllowed(
        address mTokenBorrowed,
        address mTokenCollateral,
        address liquidator,
        address borrower,
        uint256 repayAmount
    ) external returns (bool) {
        // Shh - currently unused
        liquidator;

        require(markets[mTokenBorrowed].isListed && markets[mTokenCollateral].isListed, "Market is not listed");

        uint256 borrowBalance = IMToken(mTokenBorrowed).borrowBalanceStored(borrower);

        /* allow accounts to be liquidated if the market is deprecated */
        if (isDeprecated(IMToken(mTokenBorrowed))) {
            require(borrowBalance >= repayAmount, "Can not repay more than the total borrow");
        } else {
            /* The borrower must have shortfall in order to be liquidatable */
            (, uint256 shortfall) = getAccountLiquidityInternalLiquidation(borrower);

            require(shortfall != 0, "Insufficient shortfall");

            /* The liquidator may not repay more than what is allowed by the closeFactor */
            uint256 maxClose = (closeFactorMantissa * borrowBalance) / 1e18;
            require(repayAmount <= maxClose, "Too much repay");
        }

        return true;
    }

    /**
     * @notice Validates liquidateBorrow and reverts on rejection. May emit logs.
     * @param mTokenBorrowed Asset which was borrowed by the borrower
     * @param mTokenCollateral Asset which was used as collateral and will be seized
     * @param liquidator The address repaying the borrow and seizing the collateral
     * @param borrower The address of the borrower
     * @param actualRepayAmount The amount of underlying being repaid
     */
    function liquidateBorrowVerify(
        address mTokenBorrowed,
        address mTokenCollateral,
        address liquidator,
        address borrower,
        uint256 actualRepayAmount,
        uint256 seizeTokens
    ) external {
        // Shh - currently unused
        mTokenBorrowed;
        mTokenCollateral;
        liquidator;
        borrower;
        actualRepayAmount;
        seizeTokens;

        // Shh - we dont ever want this hook to be marked pure
        if (false) {
            maxAssets = maxAssets;
        }
    }

    /**
     * @notice Checks if the seizing of assets should be allowed to occur
     * @param mTokenCollateral Asset which was used as collateral and will be seized
     * @param mTokenBorrowed Asset which was borrowed by the borrower
     * @param liquidator The address repaying the borrow and seizing the collateral
     * @param borrower The address of the borrower
     * @param seizeTokens The number of collateral tokens to seize
     */
    function seizeAllowed(
        address mTokenCollateral,
        address mTokenBorrowed,
        address liquidator,
        address borrower,
        uint256 seizeTokens
    ) external returns (bool) {
        // Pausing is a very serious situation - we revert to sound the alarms
        require(!seizeGuardianPaused, "seize is paused");

        // Shh - currently unused
        seizeTokens;
        require(markets[mTokenCollateral].isListed && markets[mTokenBorrowed].isListed, "Market is not listed");
        require(IMToken(mTokenCollateral).controller() == IMToken(mTokenBorrowed).controller(), "Controller mismatch");

        // Keep the flywheel moving
        updateNebSupplyIndex(mTokenCollateral);
        distributeSupplierNeb(mTokenCollateral, borrower);
        distributeSupplierNeb(mTokenCollateral, liquidator);

        return true;
    }

    /**
     * @notice Validates seize and reverts on rejection. May emit logs.
     * @param mTokenCollateral Asset which was used as collateral and will be seized
     * @param mTokenBorrowed Asset which was borrowed by the borrower
     * @param liquidator The address repaying the borrow and seizing the collateral
     * @param borrower The address of the borrower
     * @param seizeTokens The number of collateral tokens to seize
     */
    function seizeVerify(
        address mTokenCollateral,
        address mTokenBorrowed,
        address liquidator,
        address borrower,
        uint256 seizeTokens
    ) external {
        // Shh - currently unused
        mTokenCollateral;
        mTokenBorrowed;
        liquidator;
        borrower;
        seizeTokens;

        // Shh - we dont ever want this hook to be marked pure
        if (false) {
            maxAssets = maxAssets;
        }
    }

    /**
     * @notice Checks if the account should be allowed to transfer tokens in the given market
     * @param mToken The market to verify the transfer against
     * @param src The account which sources the tokens
     * @param dst The account which receives the tokens
     * @param transferTokens The number of mTokens to transfer
     * @return true if the transfer is allowed, false otherwise
     */
    function transferAllowed(
        address mToken,
        address src,
        address dst,
        uint256 transferTokens
    ) external returns (bool) {
        // Pausing is a very serious situation - we revert to sound the alarms
        require(!transferGuardianPaused, "transfer is paused");

        // Currently the only consideration is whether or not
        //  the src is allowed to redeem this many tokens
        bool allowed = redeemAllowedInternal(mToken, src, transferTokens);
        if (allowed) {
            // Keep the flywheel moving
            updateNebSupplyIndex(mToken);
            distributeSupplierNeb(mToken, src);
            distributeSupplierNeb(mToken, dst);
        }

        return allowed;
    }

    /**
     * @notice Validates transfer and reverts on rejection. May emit logs.
     * @param mToken Asset being transferred
     * @param src The account which sources the tokens
     * @param dst The account which receives the tokens
     * @param transferTokens The number of mTokens to transfer
     */
    function transferVerify(
        address mToken,
        address src,
        address dst,
        uint256 transferTokens
    ) external {
        // Shh - currently unused
        mToken;
        src;
        dst;
        transferTokens;

        // Shh - we dont ever want this hook to be marked pure
        if (false) {
            maxAssets = maxAssets;
        }
    }

    /*** Liquidity/Liquidation Calculations ***/

    /**
     * @notice Determine the current account liquidity wrt collateral requirements
     * @return (
                account liquidity in excess of collateral requirements,
     *          account shortfall below collateral requirements)
     */
    function getAccountLiquidity(address account) public view returns (uint256, uint256) {
        (uint256 liquidity, uint256 shortfall) = getHypotheticalAccountLiquidityInternal(
            account,
            IMToken(address(0)),
            0,
            0,
            true
        );

        return (liquidity, shortfall);
    }

    /**
     * @notice Determine the current account liquidity wrt collateral requirements
     * @return (
                account liquidity in excess of collateral requirements,
     *          account shortfall below collateral requirements)
     */
    function getAccountLiquidityInternalLiquidation(address account) internal view returns (uint256, uint256) {
        return getHypotheticalAccountLiquidityInternal(account, IMToken(address(0)), 0, 0, false);
    }

    /**
     * @notice Determine what the account liquidity would be if the given amounts were redeemed/borrowed
     * @param mTokenModify The market to hypothetically redeem/borrow in
     * @param account The account to determine liquidity for
     * @param redeemTokens The number of tokens to hypothetically redeem
     * @param borrowAmount The amount of underlying to hypothetically borrow
     * @return 
                hypothetical account liquidity in excess of collateral requirements,
     *          hypothetical account shortfall below collateral requirements)
     */
    function getHypotheticalAccountLiquidity(
        address account,
        address mTokenModify,
        uint256 redeemTokens,
        uint256 borrowAmount
    ) public view returns (uint256, uint256) {
        (uint256 liquidity, uint256 shortfall) = getHypotheticalAccountLiquidityInternal(
            account,
            IMToken(mTokenModify),
            redeemTokens,
            borrowAmount,
            true
        );
        return (liquidity, shortfall);
    }

    struct AccountLiquidityInfo {
        uint256 mTokenBalance;
        uint256 exchangeRateMantissa;
        uint256 borrowBalance;
    }

    /**
     * @notice Determine what the account liquidity would be if the given amounts were redeemed/borrowed
     * @param mTokenModify The market to hypothetically redeem/borrow in
     * @param account The account to determine liquidity for
     * @param redeemTokens The number of tokens to hypothetically redeem
     * @param borrowAmount The amount of underlying to hypothetically borrow
     * @param withFixed flag to indicate whether to count or not account's fixed rate borrows
     * @dev Note that we calculate the exchangeRateStored for each collateral mToken using stored data,
     *  without calculating accumulated interest.
     * @return (possible error code,
                hypothetical account liquidity in excess of collateral requirements,
     *          hypothetical account shortfall below collateral requirements)
     */
    function getHypotheticalAccountLiquidityInternal(
        address account,
        IMToken mTokenModify,
        uint256 redeemTokens,
        uint256 borrowAmount,
        bool withFixed
    ) internal view returns (uint256, uint256) {
        uint256 sumCollateral;
        uint256 sumBorrowPlusEffects;

        // For each asset the account is in
        IMToken[] memory assets = accountAssets[account];
        AccountLiquidityInfo memory accountInfo;
        for (uint256 i = 0; i < assets.length; i++) {
            IMToken asset = assets[i];

            // Read the balances and exchange rate from the mToken
            if (withFixed) {
                (accountInfo.mTokenBalance, , accountInfo.exchangeRateMantissa, accountInfo.borrowBalance) = asset
                    .getAccountSnapshot(account);
            } else {
                (accountInfo.mTokenBalance, accountInfo.borrowBalance, accountInfo.exchangeRateMantissa, ) = asset
                    .getAccountSnapshot(account);
            }

            // Get the normalized price of the asset
            uint256 oraclePrice = oracle.getUnderlyingPrice(asset);
            require(oraclePrice != 0, "Failed to get price");

            // Pre-Compute a conversion factor from tokens -> ether (normalized price value)
            uint256 tokensToDenom = (((markets[address(asset)].collateralFactorMantissa *
                accountInfo.exchangeRateMantissa) / 1e18) * oraclePrice) / 1e18;

            // sumCollateral += tokensToDenom * mTokenBalance
            sumCollateral +=
                (tokensToDenom * accountInfo.mTokenBalance) /
                10**(IERC20Metadata(IMErc20(address(asset)).underlying()).decimals());
            // sumBorrowPlusEffects += oraclePrice * borrowBalance
            sumBorrowPlusEffects +=
                (oraclePrice * accountInfo.borrowBalance) /
                10**(IERC20Metadata(IMErc20(address(asset)).underlying()).decimals());

            // Calculate effects of interacting with mTokenModify
            if (asset == mTokenModify) {
                // redeem effect
                // sumBorrowPlusEffects += tokensToDenom * redeemTokens
                sumBorrowPlusEffects +=
                    (tokensToDenom * redeemTokens) /
                    10**(IERC20Metadata(IMErc20(address(asset)).underlying()).decimals());

                // borrow effect
                // sumBorrowPlusEffects += oraclePrice * borrowAmount
                sumBorrowPlusEffects +=
                    (oraclePrice * borrowAmount) /
                    10**(IERC20Metadata(IMErc20(address(asset)).underlying()).decimals());
            }
        }

        // These are safe, as the underflow condition is checked first
        if (sumCollateral > sumBorrowPlusEffects) {
            return (sumCollateral - sumBorrowPlusEffects, 0);
        } else {
            return (0, sumBorrowPlusEffects - sumCollateral);
        }
    }

    /**
     * @notice Calculate number of tokens of collateral asset to seize given an underlying amount
     * @dev Used in liquidation (called in mToken.liquidateBorrowFresh)
     * @param mTokenBorrowed The address of the borrowed mToken
     * @param mTokenCollateral The address of the collateral mToken
     * @param actualRepayAmount The amount of mTokenBorrowed underlying to convert into mTokenCollateral tokens
     * @return (number of mTokenCollateral tokens to be seized in a liquidation)
     */
    function liquidateCalculateSeizeTokens(
        address mTokenBorrowed,
        address mTokenCollateral,
        uint256 actualRepayAmount
    ) external view returns (uint256) {
        /* Read oracle prices for borrowed and collateral markets */
        uint256 priceBorrowedMantissa = oracle.getUnderlyingPrice(IMToken(mTokenBorrowed));
        uint256 priceCollateralMantissa = oracle.getUnderlyingPrice(IMToken(mTokenCollateral));
        require(priceBorrowedMantissa != 0 && priceCollateralMantissa != 0, "Failed to get price");

        /*
         * Get the exchange rate and calculate the number of collateral tokens to seize:
         *  seizeAmount = actualRepayAmount * liquidationIncentive * priceBorrowed / priceCollateral
         *  seizeTokens = seizeAmount / exchangeRate
         *   = actualRepayAmount * (liquidationIncentive * priceBorrowed) / (priceCollateral * exchangeRate)
         */
        uint256 exchangeRateMantissa = IMToken(mTokenCollateral).exchangeRateStored(); // Note: reverts on error
        uint256 seizeTokens;
        uint256 numerator;
        uint256 denominator;
        uint256 ratio;

        numerator = (liquidationIncentiveMantissa * priceBorrowedMantissa) / 1e18;
        denominator = (priceCollateralMantissa * exchangeRateMantissa) / 1e18;
        ratio = (numerator * 1e18) / denominator;

        seizeTokens =
            (ratio * (actualRepayAmount * 10**(18 - IERC20Metadata(IMErc20(mTokenBorrowed).underlying()).decimals()))) /
            1e18;

        return seizeTokens;
    }

    /*** Admin Functions ***/

    /**
     * @notice Sets a new price oracle for the Nebtroller
     * @dev Admin function to set a new price oracle
     */
    function setPriceOracle(IPriceOracle newOracle) public onlyAdmin(msg.sender) {
        IPriceOracle oldOracle = oracle;
        oracle = newOracle;
        emit NewPriceOracle(oldOracle, newOracle);
    }

    /**
     * @notice Sets the closeFactor used when liquidating borrows
     * @dev Admin function to set closeFactor
     * @param newCloseFactorMantissa New close factor, scaled by 1e18
     */
    function setCloseFactor(uint256 newCloseFactorMantissa) external onlyAdmin(msg.sender) {
        uint256 oldCloseFactorMantissa = closeFactorMantissa;
        closeFactorMantissa = newCloseFactorMantissa;
        emit NewCloseFactor(oldCloseFactorMantissa, closeFactorMantissa);
    }

    /**
     * @notice Sets the collateralFactor for a market
     * @dev Admin function to set per-market collateralFactor
     * @param mToken The market to set the factor on
     * @param newCollateralFactorMantissa The new collateral factor, scaled by 1e18
     */
    function setCollateralFactor(IMToken mToken, uint256 newCollateralFactorMantissa) external onlyAdmin(msg.sender) {
        // Verify market is listed
        Market storage market = markets[address(mToken)];
        require(market.isListed, "Market is not listed");

        // Check collateral factor <= 0.9
        require(newCollateralFactorMantissa <= collateralFactorMaxMantissa, "Collateral factor exceeds maximum");

        // If collateral factor != 0, fail if price == 0
        require(newCollateralFactorMantissa == 0 || oracle.getUnderlyingPrice(mToken) != 0, "Failed to get price");

        // Set markets collateral factor to new collateral factor, remember old value
        uint256 oldCollateralFactorMantissa = market.collateralFactorMantissa;
        market.collateralFactorMantissa = newCollateralFactorMantissa;

        // Emit event with asset, old collateral factor, and new collateral factor
        emit NewCollateralFactor(mToken, oldCollateralFactorMantissa, newCollateralFactorMantissa);
    }

    /**
     * @notice Sets liquidationIncentive
     * @dev Admin function to set liquidationIncentive
     * @param newLiquidationIncentiveMantissa New liquidationIncentive scaled by 1e18
     */
    function setLiquidationIncentive(uint256 newLiquidationIncentiveMantissa) external onlyAdmin(msg.sender) {
        uint256 oldLiquidationIncentiveMantissa = liquidationIncentiveMantissa;
        liquidationIncentiveMantissa = newLiquidationIncentiveMantissa;
        emit NewLiquidationIncentive(oldLiquidationIncentiveMantissa, newLiquidationIncentiveMantissa);
    }

    /**
     * @notice Add the market to the markets mapping and set it as listed
     * @dev Admin function to set isListed and add support for the market
     * @param mToken The address of the market (token) to list
     */
    function supportMarket(IMToken mToken) external onlyAdmin(msg.sender) {
        require(!markets[address(mToken)].isListed, "Market is already listed");

        mToken.isMToken(); // Sanity check to make sure its really a IMToken

        // Note that isNebed is not in active use anymore
        markets[address(mToken)] = Market({isListed: true, isComped: false, collateralFactorMantissa: 0});

        _addMarketInternal(address(mToken));
        _initializeMarket(address(mToken));

        emit MarketListed(mToken);
    }

    function _addMarketInternal(address mToken) internal {
        for (uint256 i = 0; i < allMarkets.length; i++) {
            require(allMarkets[i] != IMToken(mToken), "market already added");
        }
        allMarkets.push(IMToken(mToken));
    }

    function _initializeMarket(address mToken) internal {
        NebMarketState storage supplyState = nebSupplyState[mToken];
        NebMarketState storage borrowState = nebBorrowState[mToken];

        /*
         * Update market state indices
         */
        if (supplyState.index == 0) {
            // Initialize supply state index with default value
            supplyState.index = nebInitialIndex;
        }

        if (borrowState.index == 0) {
            // Initialize borrow state index with default value
            borrowState.index = nebInitialIndex;
        }

        /*
         * Update market state block numbers
         */
        supplyState.block = borrowState.block = getBlockNumber();
    }

    /**
     * @notice Set the given borrow caps for the given mToken markets. Borrowing that brings total borrows to or above borrow cap will revert.
     * @dev Admin or borrowCapGuardian function to set the borrow caps. A borrow cap of 0 corresponds to unlimited borrowing.
     * @param mTokens The addresses of the markets (tokens) to change the borrow caps for
     * @param newBorrowCaps The new borrow cap values in underlying to be set. A value of 0 corresponds to unlimited borrowing.
     */
    function setMarketBorrowCaps(IMToken[] calldata mTokens, uint256[] calldata newBorrowCaps) external {
        require(
            msg.sender == admin || msg.sender == borrowCapGuardian,
            "only admin or borrow cap guardian can set borrow caps"
        );

        uint256 numMarkets = mTokens.length;
        uint256 numBorrowCaps = newBorrowCaps.length;

        require(numMarkets != 0 && numMarkets == numBorrowCaps, "invalid input");

        for (uint256 i = 0; i < numMarkets; i++) {
            borrowCaps[address(mTokens[i])] = newBorrowCaps[i];
            emit NewBorrowCap(mTokens[i], newBorrowCaps[i]);
        }
    }

    /**
     * @notice Admin function to change the Borrow Cap Guardian
     * @param newBorrowCapGuardian The address of the new Borrow Cap Guardian
     */
    function setBorrowCapGuardian(address newBorrowCapGuardian) external onlyAdmin(msg.sender) {
        address oldBorrowCapGuardian = borrowCapGuardian;
        borrowCapGuardian = newBorrowCapGuardian;
        emit NewBorrowCapGuardian(oldBorrowCapGuardian, newBorrowCapGuardian);
    }

    /**
     * @notice Admin function to change the Pause Guardian
     * @param newPauseGuardian The address of the new Pause Guardian
     */
    function setPauseGuardian(address newPauseGuardian) external onlyAdmin(msg.sender) {
        address oldPauseGuardian = pauseGuardian;
        pauseGuardian = newPauseGuardian;
        emit NewPauseGuardian(oldPauseGuardian, pauseGuardian);
    }

    function setMintPaused(IMToken mToken, bool state) public returns (bool) {
        require(markets[address(mToken)].isListed, "cannot pause a market that is not listed");
        require(msg.sender == pauseGuardian || msg.sender == admin, "only pause guardian and admin can pause");
        require(msg.sender == admin || state == true, "only admin can unpause");

        mintGuardianPaused[address(mToken)] = state;
        emit ActionPaused(mToken, "Mint", state);
        return state;
    }

    function setBorrowPaused(IMToken mToken, bool state) public returns (bool) {
        require(markets[address(mToken)].isListed, "cannot pause a market that is not listed");
        require(msg.sender == pauseGuardian || msg.sender == admin, "only pause guardian and admin can pause");
        require(msg.sender == admin || state == true, "only admin can unpause");

        borrowGuardianPaused[address(mToken)] = state;
        emit ActionPaused(mToken, "Borrow", state);
        return state;
    }

    function setTransferPaused(bool state) public returns (bool) {
        require(msg.sender == pauseGuardian || msg.sender == admin, "only pause guardian and admin can pause");
        require(msg.sender == admin || state == true, "only admin can unpause");

        transferGuardianPaused = state;
        emit ActionPaused("Transfer", state);
        return state;
    }

    function setSeizePaused(bool state) public returns (bool) {
        require(msg.sender == pauseGuardian || msg.sender == admin, "only pause guardian and admin can pause");
        require(msg.sender == admin || state == true, "only admin can unpause");

        seizeGuardianPaused = state;
        emit ActionPaused("Seize", state);
        return state;
    }

    function _become(Unitroller unitroller) public {
        require(msg.sender == unitroller.admin(), "only unitroller admin can change brains");
        require(unitroller.acceptImplementation(), "change not authorized");
    }

    /**
     * @notice Checks caller is admin, or this contract is becoming the new implementation
     */
    function adminOrInitializing() internal view returns (bool) {
        return msg.sender == admin || msg.sender == controllerImplementation;
    }

    /*** Neb Distribution ***/

    /**
     * @notice Set NEB speed for a single market
     * @param mToken The market whose NEB speed to update
     * @param supplySpeed New supply-side NEB speed for market
     * @param borrowSpeed New borrow-side NEB speed for market
     */
    function setNebSpeedInternal(
        IMToken mToken,
        uint256 supplySpeed,
        uint256 borrowSpeed
    ) internal {
        Market storage market = markets[address(mToken)];
        require(market.isListed, "neb market is not listed");

        if (nebSupplySpeeds[address(mToken)] != supplySpeed) {
            // Supply speed updated so lets update supply state to ensure that
            //  1. NEB accrued properly for the old speed, and
            //  2. NEB accrued at the new speed starts after this block.
            updateNebSupplyIndex(address(mToken));

            // Update speed and emit event
            nebSupplySpeeds[address(mToken)] = supplySpeed;
            emit NebSupplySpeedUpdated(mToken, supplySpeed);
        }

        if (nebBorrowSpeeds[address(mToken)] != borrowSpeed) {
            // Borrow speed updated so lets update borrow state to ensure that
            //  1. NEB accrued properly for the old speed, and
            //  2. NEB accrued at the new speed starts after this block.
            updateNebBorrowIndex(address(mToken), mToken.borrowIndex());

            // Update speed and emit event
            nebBorrowSpeeds[address(mToken)] = borrowSpeed;
            emit NebBorrowSpeedUpdated(mToken, borrowSpeed);
        }
    }

    /**
     * @notice Accrue NEB to the market by updating the supply index
     * @param mToken The market whose supply index to update
     * @dev Index is a cumulative sum of the NEB per mToken accrued.
     */
    function updateNebSupplyIndex(address mToken) internal {
        NebMarketState storage supplyState = nebSupplyState[mToken];
        uint256 supplySpeed = nebSupplySpeeds[mToken];
        uint256 blockNumber = getBlockNumber();
        uint256 deltaBlocks = blockNumber - supplyState.block;
        if (deltaBlocks > 0 && supplySpeed > 0) {
            uint256 supplyTokens = IMToken(mToken).totalSupply();
            uint256 nebAccrued = deltaBlocks * supplySpeed;
            uint256 ratio = supplyTokens > 0 ? (nebAccrued * 1e18) / supplyTokens : 0;
            supplyState.index += ratio;
            supplyState.block = blockNumber;
        } else if (deltaBlocks > 0) {
            supplyState.block = blockNumber;
        }
    }

    /**
     * @notice Accrue NEB to the market by updating the borrow index
     * @param mToken The market whose borrow index to update
     * @dev Index is a cumulative sum of the NEB per mToken accrued.
     */
    function updateNebBorrowIndex(address mToken, uint256 marketBorrowIndex) internal {
        NebMarketState storage borrowState = nebBorrowState[mToken];
        uint256 borrowSpeed = nebBorrowSpeeds[mToken];
        uint256 blockNumber = getBlockNumber();
        uint256 deltaBlocks = blockNumber - borrowState.block;
        if (deltaBlocks > 0 && borrowSpeed > 0) {
            uint256 borrowAmount = IMToken(mToken).getTotalBorrows() / marketBorrowIndex;
            uint256 nebAccrued = deltaBlocks * borrowSpeed;
            uint256 ratio = borrowAmount > 0 ? (nebAccrued * 1e18) / borrowAmount : 0;
            borrowState.index += ratio;
            borrowState.block = blockNumber;
        } else if (deltaBlocks > 0) {
            borrowState.block = blockNumber;
        }
    }

    /**
     * @notice Calculate NEB accrued by a supplier and possibly transfer it to them
     * @param mToken The market in which the supplier is interacting
     * @param supplier The address of the supplier to distribute NEB to
     */
    function distributeSupplierNeb(address mToken, address supplier) internal {
        // TODO: Dont distribute supplier NEB if the user is not in the supplier market.
        // This check should be as gas efficient as possible as distributeSupplierNeb is called in many places.
        // - We really dont want to call an external contract as thats quite expensive.

        NebMarketState storage supplyState = nebSupplyState[mToken];
        uint256 supplyIndex = supplyState.index;
        uint256 supplierIndex = nebSupplierIndex[mToken][supplier];

        // Update suppliers index to the current index since we are distributing accrued NEB
        nebSupplierIndex[mToken][supplier] = supplyIndex;

        if (supplierIndex == 0 && supplyIndex >= nebInitialIndex) {
            // Covers the case where users supplied tokens before the markets supply state index was set.
            // Rewards the user with NEB accrued from the start of when supplier rewards were first
            // set for the market.
            supplierIndex = nebInitialIndex;
        }

        // Calculate change in the cumulative sum of the NEB per mToken accrued
        uint256 deltaIndex = supplyIndex - supplierIndex;

        uint256 supplierTokens = IMToken(mToken).balanceOf(supplier);

        // Calculate NEB accrued: IMTokenAmount * accruedPerIMToken
        uint256 supplierDelta = supplierTokens * deltaIndex;
        nebAccrued[supplier] += supplierDelta;

        emit DistributedSupplierNeb(IMToken(mToken), supplier, supplierDelta, supplyIndex);
    }

    /**
     * @notice Calculate NEB accrued by a borrower and possibly transfer it to them
     * @dev Borrowers will not begin to accrue until after the first interaction with the protocol.
     * @param mToken The market in which the borrower is interacting
     * @param borrower The address of the borrower to distribute NEB to
     */
    function distributeBorrowerNeb(
        address mToken,
        address borrower,
        uint256 marketBorrowIndex
    ) internal {
        // TODO: Dont distribute supplier NEB if the user is not in the borrower market.
        // This check should be as gas efficient as possible as distributeBorrowerNeb is called in many places.
        // - We really dont want to call an external contract as thats quite expensive.

        NebMarketState storage borrowState = nebBorrowState[mToken];
        uint256 borrowIndex = borrowState.index;
        uint256 borrowerIndex = nebBorrowerIndex[mToken][borrower];

        // Update borrowerss index to the current index since we are distributing accrued NEB
        nebBorrowerIndex[mToken][borrower] = borrowIndex;

        if (borrowerIndex == 0 && borrowIndex >= nebInitialIndex) {
            // Covers the case where users borrowed tokens before the markets borrow state index was set.
            // Rewards the user with NEB accrued from the start of when borrower rewards were first
            // set for the market.
            borrowerIndex = nebInitialIndex;
        }

        // Calculate change in the cumulative sum of the NEB per borrowed unit accrued
        uint256 deltaIndex = borrowIndex - borrowerIndex;

        uint256 borrowerAmount = IMToken(mToken).borrowBalanceStored(borrower) / marketBorrowIndex;

        // Calculate NEB accrued: IMTokenAmount * accruedPerBorrowedUnit
        uint256 borrowerDelta = borrowerAmount * deltaIndex;
        nebAccrued[borrower] += borrowerDelta;

        emit DistributedBorrowerNeb(IMToken(mToken), borrower, borrowerDelta, borrowIndex);
    }

    /**
     * @notice Calculate additional accrued NEB for a contributor since last accrual
     * @param contributor The address to calculate contributor rewards for
     */
    function updateContributorRewards(address contributor) public {
        uint256 nebSpeed = nebContributorSpeeds[contributor];
        uint256 blockNumber = getBlockNumber();
        uint256 deltaBlocks = blockNumber - lastContributorBlock[contributor];
        if (deltaBlocks > 0 && nebSpeed > 0) {
            uint256 newAccrued = deltaBlocks * nebSpeed;
            nebAccrued[contributor] += newAccrued;
            lastContributorBlock[contributor] = blockNumber;
        }
    }

    /**
     * @notice Claim all the neb accrued by holder in all markets
     * @param holder The address to claim NEB for
     */
    function claimNeb(address holder) public {
        claimNeb(holder, allMarkets);
    }

    /**
     * @notice Claim all the neb accrued by holder in the specified markets
     * @param holder The address to claim NEB for
     * @param mTokens The list of markets to claim NEB in
     */
    function claimNeb(address holder, IMToken[] memory mTokens) public {
        address[] memory holders = new address[](1);
        holders[0] = holder;
        claimNeb(holders, mTokens, true, true);
    }

    /**
     * @notice Claim all neb accrued by the holders
     * @param holders The addresses to claim NEB for
     * @param mTokens The list of markets to claim NEB in
     * @param borrowers Whether or not to claim NEB earned by borrowing
     * @param suppliers Whether or not to claim NEB earned by supplying
     */
    function claimNeb(
        address[] memory holders,
        IMToken[] memory mTokens,
        bool borrowers,
        bool suppliers
    ) public {
        for (uint256 i = 0; i < mTokens.length; i++) {
            IMToken mToken = mTokens[i];
            require(markets[address(mToken)].isListed, "market must be listed");
            if (borrowers) {
                uint256 borrowIndex = mToken.borrowIndex();
                updateNebBorrowIndex(address(mToken), borrowIndex);
                for (uint256 j = 0; j < holders.length; j++) {
                    distributeBorrowerNeb(address(mToken), holders[j], borrowIndex);
                }
            }
            if (suppliers) {
                updateNebSupplyIndex(address(mToken));
                for (uint256 j = 0; j < holders.length; j++) {
                    distributeSupplierNeb(address(mToken), holders[j]);
                }
            }
        }
        for (uint256 j = 0; j < holders.length; j++) {
            nebAccrued[holders[j]] = grantNebInternal(holders[j], nebAccrued[holders[j]]);
        }
    }

    /**
     * @notice Transfer NEB to the user
     * @dev Note: If there is not enough NEB, we do not perform the transfer all.
     * @param user The address of the user to transfer NEB to
     * @param amount The amount of NEB to (possibly) transfer
     * @return The amount of NEB which was NOT transferred to the user
     */
    function grantNebInternal(address user, uint256 amount) internal returns (uint256) {
        Neb neb = Neb(getNebAddress());
        uint256 nebRemaining = neb.balanceOf(address(this));
        if (amount > 0 && amount <= nebRemaining) {
            neb.transfer(user, amount);
            return 0;
        }
        return amount;
    }

    /*** Neb Distribution Admin ***/

    /**
     * @notice Transfer NEB to the recipient
     * @dev Note: If there is not enough NEB, we do not perform the transfer all.
     * @param recipient The address of the recipient to transfer NEB to
     * @param amount The amount of NEB to (possibly) transfer
     */
    function grantNeb(address recipient, uint256 amount) public {
        require(adminOrInitializing(), "only admin can grant neb");
        uint256 amountLeft = grantNebInternal(recipient, amount);
        require(amountLeft == 0, "insufficient neb for grant");
        emit NebGranted(recipient, amount);
    }

    /**
     * @notice Set NEB borrow and supply speeds for the specified markets.
     * @param mTokens The markets whose NEB speed to update.
     * @param supplySpeeds New supply-side NEB speed for the corresponding market.
     * @param borrowSpeeds New borrow-side NEB speed for the corresponding market.
     */
    function setNebSpeeds(
        IMToken[] memory mTokens,
        uint256[] memory supplySpeeds,
        uint256[] memory borrowSpeeds
    ) public {
        require(adminOrInitializing(), "only admin can set neb speed");

        uint256 numTokens = mTokens.length;
        require(
            numTokens == supplySpeeds.length && numTokens == borrowSpeeds.length,
            "Controller::_setNebSpeeds invalid input"
        );

        for (uint256 i = 0; i < numTokens; ++i) {
            setNebSpeedInternal(mTokens[i], supplySpeeds[i], borrowSpeeds[i]);
        }
    }

    /**
     * @notice Set NEB speed for a single contributor
     * @param contributor The contributor whose NEB speed to update
     * @param nebSpeed New NEB speed for contributor
     */
    function _setContributorNebSpeed(address contributor, uint256 nebSpeed) public {
        require(adminOrInitializing(), "only admin can set neb speed");

        // note that NEB speed could be set to 0 to halt liquidity rewards for a contributor
        updateContributorRewards(contributor);
        if (nebSpeed == 0) {
            // release storage
            delete lastContributorBlock[contributor];
        } else {
            lastContributorBlock[contributor] = getBlockNumber();
        }
        nebContributorSpeeds[contributor] = nebSpeed;

        emit ContributorNebSpeedUpdated(contributor, nebSpeed);
    }

    /**
     * @notice Return all of the markets
     * @dev The automatic getter may be used to access an individual market.
     * @return The list of market addresses
     */
    function getAllMarkets() public view returns (IMToken[] memory) {
        return allMarkets;
    }

    /**
     * @notice Returns true if the given mToken market has been deprecated
     * @dev All borrows in a deprecated mToken market can be immediately liquidated
     * @param mToken The market to check if deprecated
     */
    function isDeprecated(IMToken mToken) public view returns (bool) {
        return
            markets[address(mToken)].collateralFactorMantissa == 0 &&
            borrowGuardianPaused[address(mToken)] == true &&
            mToken.reserveFactorMantissa() == 1e18;
    }

    function getBlockNumber() public view returns (uint256) {
        return block.number;
    }

    /**
     * @notice Return the address of the NEB token
     * @return The address of NEB
     */
    function getNebAddress() public view returns (address) {
        return 0xc00e94Cb662C3520282E6f5717214004A7f26888;
    }
}
