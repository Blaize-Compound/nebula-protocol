// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "./CToken.sol";
import "./interfaces/IController.sol";
import "./interfaces/IControllerEvents.sol";
import "./ControllerStorage.sol";
import "./Unitroller.sol";
import "./Governance/Neb.sol";

/**
 * @title Compounds Comptroller Contract
 * @author Compound
 */
contract Controller is ControllerV7Storage, IController, IControllerEvents {
    /// @notice Indicator that this is a Controller contract (for inspection)
    bool public constant isController = true;
    /// @notice The initial COMP index for a market
    uint224 public constant compInitialIndex = 1e36;
    // closeFactorMantissa must be strictly greater than this value
    uint internal constant closeFactorMinMantissa = 0.05e18; // 0.05
    // closeFactorMantissa must not exceed this value
    uint internal constant closeFactorMaxMantissa = 0.9e18; // 0.9
    // No collateralFactorMantissa may exceed this value
    uint internal constant collateralFactorMaxMantissa = 0.9e18; // 0.9

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
    function getAssetsIn(address account) external view returns (ICToken[] memory) {
        ICToken[] memory assetsIn = accountAssets[account];

        return assetsIn;
    }

    /**
     * @notice Returns whether the given account is entered in the given asset
     * @param account The address of the account to check
     * @param cToken The cToken to check
     * @return True if the account is in the asset, otherwise false.
     */
    function checkMembership(address account, ICToken cToken) external view returns (bool) {
        return accountMembership[address(cToken)][account];
    }

    /**
     * @notice Add assets to be included in account liquidity calculation
     * @param cTokens The list of addresses of the cToken markets to be enabled
     */
    function enterMarkets(address[] memory cTokens) public {
        for (uint i = 0; i < cTokens.length; i++) {
            ICToken cToken = ICToken(cTokens[i]);

            addToMarketInternal(cToken, msg.sender);
        }
    }

    /**
     * @notice Add the market to the borrowers "assets in" for liquidity calculations
     * @param cToken The market to enter
     * @param borrower The address of the account to modify
     */
    function addToMarketInternal(ICToken cToken, address borrower) internal {
        Market storage marketToJoin = markets[address(cToken)];

        require(marketToJoin.isListed, "Market is not listed");

        if (accountMembership[address(cToken)][borrower]) {
            // already joined
            return;
        }

        // survived the gauntlet, add to list
        // NOTE: we store these somewhat redundantly as a significant optimization
        //  this avoids having to iterate through the list for the most common use cases
        //  that is, only when we need to perform liquidity checks
        //  and not whenever we want to check if an account is in a particular market
        accountMembership[address(cToken)][borrower] = true;
        accountAssets[borrower].push(cToken);

        emit MarketEntered(cToken, borrower);
    }

    /**
     * @notice Removes asset from senders account liquidity calculation
     * @dev Sender must not have an outstanding borrow balance in the asset,
     *  or be providing necessary collateral for an outstanding borrow.
     * @param cTokenAddress The address of the asset to be removed
     */
    function exitMarket(address cTokenAddress) external {
        ICToken cToken = CToken(cTokenAddress);
        /* Get sender tokensHeld and amountOwed underlying from the cToken */
        (uint tokensHeld, uint amountOwed, ) = cToken.getAccountSnapshot(msg.sender);

        /* Fail if the sender has a borrow balance */
        require(amountOwed == 0, "User has a borrow balance");

        /* Fail if the sender is not permitted to redeem all of their tokens */
        require(redeemAllowedInternal(cTokenAddress, msg.sender, tokensHeld), "User is not allowed to redeem");

        Market storage marketToExit = markets[address(cToken)];

        /* Return true if the sender is not already in  the market */
        require(accountMembership[address(cToken)][msg.sender], "User is not in market");

        /* Set cToken account membership to false */
        accountMembership[address(cToken)][msg.sender] = false;

        /* Delete cToken from the account s list of assets */
        // load into memory for faster iteration
        ICToken[] memory userAssetList = accountAssets[msg.sender];
        uint len = userAssetList.length;
        uint assetIndex = len;
        for (uint i = 0; i < len; i++) {
            if (userAssetList[i] == cToken) {
                assetIndex = i;
                break;
            }
        }

        // We *must* have found the asset in the list or our redundant data structure is broken
        assert(assetIndex < len);

        // copy last item in list to location of item to be removed, reduce length by 1
        ICToken[] storage storedList = accountAssets[msg.sender];
        storedList[assetIndex] = storedList[storedList.length - 1];
        storedList.pop();

        emit MarketExited(cToken, msg.sender);
    }

    /*** Policy Hooks ***/

    /**
     * @notice Checks if the account should be allowed to mint tokens in the given market
     * @param cToken The market to verify the mint against
     * @param minter The account which would get the minted tokens
     * @param mintAmount The amount of underlying being supplied to the market in exchange for tokens
     */
    function mintAllowed(address cToken, address minter, uint mintAmount) external returns (bool){
        // Pausing is a very serious situation - we revert to sound the alarms
        require(!mintGuardianPaused[cToken], "mint is paused");

        // Shh - currently unused
        minter;
        mintAmount;

        require(markets[cToken].isListed, "Market is not listed");

        // Keep the flywheel moving
        updateCompSupplyIndex(cToken);
        distributeSupplierComp(cToken, minter);

        return true;
    }

    /**
     * @notice Validates mint and reverts on rejection. May emit logs.
     * @param cToken Asset being minted
     * @param minter The address minting the tokens
     * @param actualMintAmount The amount of the underlying asset being minted
     * @param mintTokens The number of tokens being minted
     */
    function mintVerify(address cToken, address minter, uint actualMintAmount, uint mintTokens) external {
        // Shh - currently unused
        cToken;
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
     * @param cToken The market to verify the redeem against
     * @param redeemer The account which would redeem the tokens
     * @param redeemTokens The number of cTokens to exchange for the underlying asset in the market
     */
    function redeemAllowed(address cToken, address redeemer, uint redeemTokens) external returns (bool) {
        require(redeemAllowedInternal(cToken, redeemer, redeemTokens), "Redeem is not allowed");

        // Keep the flywheel moving
        updateCompSupplyIndex(cToken);
        distributeSupplierComp(cToken, redeemer);

        return true;
    }

    function redeemAllowedInternal(address cToken, address redeemer, uint redeemTokens) internal view returns (bool) {
        if (!markets[cToken].isListed) {
            return false;
        }

        /* If the redeemer is not in the market, then we can bypass the liquidity check */
        if (accountMembership[address(cToken)][redeemer]) {
            return false;
        }

        /* Otherwise, perform a hypothetical liquidity check to guard against shortfall */
        (, uint shortfall) = getHypotheticalAccountLiquidityInternal(redeemer, ICToken(cToken), redeemTokens, 0);
        if (shortfall > 0) {
            return false;
        }

        return true;
    }

    /**
     * @notice Validates redeem and reverts on rejection. May emit logs.
     * @param cToken Asset being redeemed
     * @param redeemer The address redeeming the tokens
     * @param redeemAmount The amount of the underlying asset being redeemed
     * @param redeemTokens The number of tokens being redeemed
     */
    function redeemVerify(address cToken, address redeemer, uint redeemAmount, uint redeemTokens) external {
        // Shh - currently unused
        cToken;
        redeemer;

        // Require tokens is zero or amount is also zero
        if (redeemTokens == 0 && redeemAmount > 0) {
            revert("redeemTokens zero");
        }
    }

    /**
     * @notice Checks if the account should be allowed to borrow the underlying asset of the given market
     * @param cToken The market to verify the borrow against
     * @param borrower The account which would borrow the asset
     * @param borrowAmount The amount of underlying the account would borrow
     */
    function borrowAllowed(address cToken, address borrower, uint borrowAmount) external returns (bool) {
        // Pausing is a very serious situation - we revert to sound the alarms
        require(!borrowGuardianPaused[cToken], "borrow is paused");
        require(markets[cToken].isListed, "Market is not listed");

        if (!accountMembership[address(cToken)][borrower]) {
            // only cTokens may call borrowAllowed if borrower not in market
            require(msg.sender == cToken, "sender must be cToken");

            // attempt to add borrower to the market
            addToMarketInternal(CToken(msg.sender), borrower);

            // it should be impossible to break the important invariant
            assert(accountMembership[address(cToken)][borrower]);
        }

        require(oracle.getUnderlyingPrice(ICToken(cToken)) != 0, "Failed to get underlying price");

        uint borrowCap = borrowCaps[cToken];
        // Borrow cap of 0 corresponds to unlimited borrowing
        if (borrowCap != 0) {
            uint totalBorrows = ICToken(cToken).totalBorrows();
            uint nextTotalBorrows = totalBorrows + borrowAmount;
            require(nextTotalBorrows < borrowCap, "market borrow cap reached");
        }

        (, uint shortfall) = getHypotheticalAccountLiquidityInternal(borrower, ICToken(cToken), 0, borrowAmount);
        require(shortfall == 0, "Insufficient liquidity");

        // Keep the flywheel moving
        uint borrowIndex = ICToken(cToken).borrowIndex();
        updateCompBorrowIndex(cToken, borrowIndex);
        distributeBorrowerComp(cToken, borrower, borrowIndex);

        return true;
    }

    /**
     * @notice Validates borrow and reverts on rejection. May emit logs.
     * @param cToken Asset whose underlying is being borrowed
     * @param borrower The address borrowing the underlying
     * @param borrowAmount The amount of the underlying asset requested to borrow
     */
    function borrowVerify(address cToken, address borrower, uint borrowAmount) external {
        // Shh - currently unused
        cToken;
        borrower;
        borrowAmount;

        // Shh - we dont ever want this hook to be marked pure
        if (false) {
            maxAssets = maxAssets;
        }
    }

    /**
     * @notice Checks if the account should be allowed to repay a borrow in the given market
     * @param cToken The market to verify the repay against
     * @param payer The account which would repay the asset
     * @param borrower The account which would borrowed the asset
     * @param repayAmount The amount of the underlying asset the account would repay
     */
    function repayBorrowAllowed(
        address cToken,
        address payer,
        address borrower,
        uint repayAmount) external returns (bool) {
        // Shh - currently unused
        payer;
        borrower;
        repayAmount;

        require(markets[cToken].isListed, "Market is not listed");

        // Keep the flywheel moving
        uint borrowIndex = ICToken(cToken).borrowIndex();
        updateCompBorrowIndex(cToken, borrowIndex);
        distributeBorrowerComp(cToken, borrower, borrowIndex);

        return true;
    }

    /**
     * @notice Validates repayBorrow and reverts on rejection. May emit logs.
     * @param cToken Asset being repaid
     * @param payer The address repaying the borrow
     * @param borrower The address of the borrower
     * @param actualRepayAmount The amount of underlying being repaid
     */
    function repayBorrowVerify(
        address cToken,
        address payer,
        address borrower,
        uint actualRepayAmount,
        uint borrowerIndex) external {
        // Shh - currently unused
        cToken;
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
     * @param cTokenBorrowed Asset which was borrowed by the borrower
     * @param cTokenCollateral Asset which was used as collateral and will be seized
     * @param liquidator The address repaying the borrow and seizing the collateral
     * @param borrower The address of the borrower
     * @param repayAmount The amount of underlying being repaid
     */
    function liquidateBorrowAllowed(
        address cTokenBorrowed,
        address cTokenCollateral,
        address liquidator,
        address borrower,
        uint repayAmount) external returns (bool) {
        // Shh - currently unused
        liquidator;

        require(markets[cTokenBorrowed].isListed && markets[cTokenCollateral].isListed, "Market is not listed");

        uint borrowBalance = ICToken(cTokenBorrowed).borrowBalanceStored(borrower);

        /* allow accounts to be liquidated if the market is deprecated */
        if (isDeprecated(ICToken(cTokenBorrowed))) {
            require(borrowBalance >= repayAmount, "Can not repay more than the total borrow");
        } else {
            /* The borrower must have shortfall in order to be liquidatable */
            ( , uint shortfall) = getAccountLiquidityInternal(borrower);

            require(shortfall != 0, "Insufficient shortfall");

            /* The liquidator may not repay more than what is allowed by the closeFactor */
            uint maxClose = (closeFactorMantissa * borrowBalance) / 1e18;
            require(repayAmount <= maxClose, "Too much repay");
        }

        return true;
    }

    /**
     * @notice Validates liquidateBorrow and reverts on rejection. May emit logs.
     * @param cTokenBorrowed Asset which was borrowed by the borrower
     * @param cTokenCollateral Asset which was used as collateral and will be seized
     * @param liquidator The address repaying the borrow and seizing the collateral
     * @param borrower The address of the borrower
     * @param actualRepayAmount The amount of underlying being repaid
     */
    function liquidateBorrowVerify(
        address cTokenBorrowed,
        address cTokenCollateral,
        address liquidator,
        address borrower,
        uint actualRepayAmount,
        uint seizeTokens) external {
        // Shh - currently unused
        cTokenBorrowed;
        cTokenCollateral;
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
     * @param cTokenCollateral Asset which was used as collateral and will be seized
     * @param cTokenBorrowed Asset which was borrowed by the borrower
     * @param liquidator The address repaying the borrow and seizing the collateral
     * @param borrower The address of the borrower
     * @param seizeTokens The number of collateral tokens to seize
     */
    function seizeAllowed(
        address cTokenCollateral,
        address cTokenBorrowed,
        address liquidator,
        address borrower,
        uint seizeTokens) external returns (bool) {
        // Pausing is a very serious situation - we revert to sound the alarms
        require(!seizeGuardianPaused, "seize is paused");

        // Shh - currently unused
        seizeTokens;
        require(markets[cTokenCollateral].isListed && markets[cTokenBorrowed].isListed, "Market is not listed");
        require(ICToken(cTokenCollateral).comptroller() == ICToken(cTokenBorrowed).comptroller(), "Controller mismatch");

        // Keep the flywheel moving
        updateCompSupplyIndex(cTokenCollateral);
        distributeSupplierComp(cTokenCollateral, borrower);
        distributeSupplierComp(cTokenCollateral, liquidator);

        return true;
    }

    /**
     * @notice Validates seize and reverts on rejection. May emit logs.
     * @param cTokenCollateral Asset which was used as collateral and will be seized
     * @param cTokenBorrowed Asset which was borrowed by the borrower
     * @param liquidator The address repaying the borrow and seizing the collateral
     * @param borrower The address of the borrower
     * @param seizeTokens The number of collateral tokens to seize
     */
    function seizeVerify(
        address cTokenCollateral,
        address cTokenBorrowed,
        address liquidator,
        address borrower,
        uint seizeTokens) external {
        // Shh - currently unused
        cTokenCollateral;
        cTokenBorrowed;
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
     * @param cToken The market to verify the transfer against
     * @param src The account which sources the tokens
     * @param dst The account which receives the tokens
     * @param transferTokens The number of cTokens to transfer
     * @return true if the transfer is allowed, false otherwise
     */
    function transferAllowed(address cToken, address src, address dst, uint transferTokens) external returns (bool) {
        // Pausing is a very serious situation - we revert to sound the alarms
        require(!transferGuardianPaused, "transfer is paused");

        // Currently the only consideration is whether or not
        //  the src is allowed to redeem this many tokens
        bool allowed = redeemAllowedInternal(cToken, src, transferTokens);
        if (allowed) {
            // Keep the flywheel moving
            updateCompSupplyIndex(cToken);
            distributeSupplierComp(cToken, src);
            distributeSupplierComp(cToken, dst);
        }

        return allowed;
    }

    /**
     * @notice Validates transfer and reverts on rejection. May emit logs.
     * @param cToken Asset being transferred
     * @param src The account which sources the tokens
     * @param dst The account which receives the tokens
     * @param transferTokens The number of cTokens to transfer
     */
    function transferVerify(address cToken, address src, address dst, uint transferTokens) external {
        // Shh - currently unused
        cToken;
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
    function getAccountLiquidity(address account) public view returns (uint, uint) {
        (uint liquidity, uint shortfall) = getHypotheticalAccountLiquidityInternal(account, CToken(address(0)), 0, 0);

        return (liquidity, shortfall);
    }

    /**
     * @notice Determine the current account liquidity wrt collateral requirements
     * @return (
                account liquidity in excess of collateral requirements,
     *          account shortfall below collateral requirements)
     */
    function getAccountLiquidityInternal(address account) internal view returns (uint, uint) {
        return getHypotheticalAccountLiquidityInternal(account, ICToken(address(0)), 0, 0);
    }

    /**
     * @notice Determine what the account liquidity would be if the given amounts were redeemed/borrowed
     * @param cTokenModify The market to hypothetically redeem/borrow in
     * @param account The account to determine liquidity for
     * @param redeemTokens The number of tokens to hypothetically redeem
     * @param borrowAmount The amount of underlying to hypothetically borrow
     * @return 
                hypothetical account liquidity in excess of collateral requirements,
     *          hypothetical account shortfall below collateral requirements)
     */
    function getHypotheticalAccountLiquidity(
        address account,
        address cTokenModify,
        uint redeemTokens,
        uint borrowAmount) public view returns (uint, uint) {
        (uint liquidity, uint shortfall) = getHypotheticalAccountLiquidityInternal(account, ICToken(cTokenModify), redeemTokens, borrowAmount);
        return (liquidity, shortfall);
    }

    /**
     * @notice Determine what the account liquidity would be if the given amounts were redeemed/borrowed
     * @param cTokenModify The market to hypothetically redeem/borrow in
     * @param account The account to determine liquidity for
     * @param redeemTokens The number of tokens to hypothetically redeem
     * @param borrowAmount The amount of underlying to hypothetically borrow
     * @dev Note that we calculate the exchangeRateStored for each collateral cToken using stored data,
     *  without calculating accumulated interest.
     * @return (possible error code,
                hypothetical account liquidity in excess of collateral requirements,
     *          hypothetical account shortfall below collateral requirements)
     */
    function getHypotheticalAccountLiquidityInternal(
        address account,
        ICToken cTokenModify,
        uint redeemTokens,
        uint borrowAmount) internal view returns (uint, uint) {

        uint sumCollateral;
        uint sumBorrowPlusEffects;

        // For each asset the account is in
        ICToken[] memory assets = accountAssets[account];
        for (uint i = 0; i < assets.length; i++) {
            ICToken asset = assets[i];

            // Read the balances and exchange rate from the cToken
            (uint cTokenBalance, uint borrowBalance, uint exchangeRateMantissa) = asset.getAccountSnapshot(account);

            // Get the normalized price of the asset
            uint oraclePrice = oracle.getUnderlyingPrice(asset);
            require(oraclePrice != 0, "Failed to get price");

            // Pre-compute a conversion factor from tokens -> ether (normalized price value)
            uint tokensToDenom = (((markets[address(asset)].collateralFactorMantissa * exchangeRateMantissa) / 1e18) * oraclePrice) / 1e18;

            // sumCollateral += tokensToDenom * cTokenBalance
            sumCollateral += (tokensToDenom * cTokenBalance) / 1e18;
            // sumBorrowPlusEffects += oraclePrice * borrowBalance
            sumBorrowPlusEffects += (oraclePrice * borrowBalance) / 1e18;

            // Calculate effects of interacting with cTokenModify
            if (asset == cTokenModify) {
                // redeem effect
                // sumBorrowPlusEffects += tokensToDenom * redeemTokens
                sumBorrowPlusEffects += (tokensToDenom * redeemTokens) / 1e18;

                // borrow effect
                // sumBorrowPlusEffects += oraclePrice * borrowAmount
                sumBorrowPlusEffects += (oraclePrice * borrowAmount) / 1e18;
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
     * @dev Used in liquidation (called in cToken.liquidateBorrowFresh)
     * @param cTokenBorrowed The address of the borrowed cToken
     * @param cTokenCollateral The address of the collateral cToken
     * @param actualRepayAmount The amount of cTokenBorrowed underlying to convert into cTokenCollateral tokens
     * @return (number of cTokenCollateral tokens to be seized in a liquidation)
     */
    function liquidateCalculateSeizeTokens(address cTokenBorrowed, address cTokenCollateral, uint actualRepayAmount) external view returns (uint) {
        /* Read oracle prices for borrowed and collateral markets */
        uint priceBorrowedMantissa = oracle.getUnderlyingPrice(CToken(cTokenBorrowed));
        uint priceCollateralMantissa = oracle.getUnderlyingPrice(CToken(cTokenCollateral));
        require(priceBorrowedMantissa != 0 && priceCollateralMantissa != 0, "Failed to get price");

        /*
         * Get the exchange rate and calculate the number of collateral tokens to seize:
         *  seizeAmount = actualRepayAmount * liquidationIncentive * priceBorrowed / priceCollateral
         *  seizeTokens = seizeAmount / exchangeRate
         *   = actualRepayAmount * (liquidationIncentive * priceBorrowed) / (priceCollateral * exchangeRate)
         */
        uint exchangeRateMantissa = ICToken(cTokenCollateral).exchangeRateStored(); // Note: reverts on error
        uint seizeTokens;
        uint numerator;
        uint denominator;
        uint ratio;

        numerator = (liquidationIncentiveMantissa * priceBorrowedMantissa) / 1e18;
        denominator = (priceCollateralMantissa * exchangeRateMantissa) / 1e18;
        ratio = (numerator * 1e18) / denominator;

        seizeTokens = (ratio * actualRepayAmount) / 1e18;

        return seizeTokens;
    }

    /*** Admin Functions ***/

    /**
      * @notice Sets a new price oracle for the comptroller
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
    function setCloseFactor(uint newCloseFactorMantissa) external onlyAdmin(msg.sender) {
        uint oldCloseFactorMantissa = closeFactorMantissa;
        closeFactorMantissa = newCloseFactorMantissa;
        emit NewCloseFactor(oldCloseFactorMantissa, closeFactorMantissa);
    }

    /**
      * @notice Sets the collateralFactor for a market
      * @dev Admin function to set per-market collateralFactor
      * @param cToken The market to set the factor on
      * @param newCollateralFactorMantissa The new collateral factor, scaled by 1e18
      */
    function setCollateralFactor(ICToken cToken, uint newCollateralFactorMantissa) external onlyAdmin(msg.sender) {
        // Verify market is listed
        Market storage market = markets[address(cToken)];
        require(market.isListed, "Market is not listed");

        // Check collateral factor <= 0.9
        require(newCollateralFactorMantissa <= collateralFactorMaxMantissa, "Collateral factor exceeds maximum");

        // If collateral factor != 0, fail if price == 0
        require(newCollateralFactorMantissa == 0 || oracle.getUnderlyingPrice(cToken) != 0, "Failed to get price");

        // Set markets collateral factor to new collateral factor, remember old value
        uint oldCollateralFactorMantissa = market.collateralFactorMantissa;
        market.collateralFactorMantissa = newCollateralFactorMantissa;

        // Emit event with asset, old collateral factor, and new collateral factor
        emit NewCollateralFactor(cToken, oldCollateralFactorMantissa, newCollateralFactorMantissa);
    }

    /**
      * @notice Sets liquidationIncentive
      * @dev Admin function to set liquidationIncentive
      * @param newLiquidationIncentiveMantissa New liquidationIncentive scaled by 1e18
      */
    function _setLiquidationIncentive(uint newLiquidationIncentiveMantissa) external onlyAdmin(msg.sender) {
        uint oldLiquidationIncentiveMantissa = liquidationIncentiveMantissa;
        liquidationIncentiveMantissa = newLiquidationIncentiveMantissa;
        emit NewLiquidationIncentive(oldLiquidationIncentiveMantissa, newLiquidationIncentiveMantissa);
    }

    /**
      * @notice Add the market to the markets mapping and set it as listed
      * @dev Admin function to set isListed and add support for the market
      * @param cToken The address of the market (token) to list
      */
    function supportMarket(ICToken cToken) external onlyAdmin(msg.sender) {
        require(!markets[address(cToken)].isListed, "Market is already listed");

        cToken.isCToken(); // Sanity check to make sure its really a CToken

        // Note that isComped is not in active use anymore
        markets[address(cToken)] = Market({isListed: true, isComped: false, collateralFactorMantissa: 0});

        _addMarketInternal(address(cToken));
        _initializeMarket(address(cToken));

        emit MarketListed(cToken);
    }

    function _addMarketInternal(address cToken) internal {
        for (uint i = 0; i < allMarkets.length; i ++) {
            require(allMarkets[i] != ICToken(cToken), "market already added");
        }
        allMarkets.push(ICToken(cToken));
    }

    function _initializeMarket(address cToken) internal {

        CompMarketState storage supplyState = compSupplyState[cToken];
        CompMarketState storage borrowState = compBorrowState[cToken];

        /*
         * Update market state indices
         */
        if (supplyState.index == 0) {
            // Initialize supply state index with default value
            supplyState.index = compInitialIndex;
        }

        if (borrowState.index == 0) {
            // Initialize borrow state index with default value
            borrowState.index = compInitialIndex;
        }

        /*
         * Update market state block numbers
         */
         supplyState.block = borrowState.block = getBlockNumber();
    }


    /**
      * @notice Set the given borrow caps for the given cToken markets. Borrowing that brings total borrows to or above borrow cap will revert.
      * @dev Admin or borrowCapGuardian function to set the borrow caps. A borrow cap of 0 corresponds to unlimited borrowing.
      * @param cTokens The addresses of the markets (tokens) to change the borrow caps for
      * @param newBorrowCaps The new borrow cap values in underlying to be set. A value of 0 corresponds to unlimited borrowing.
      */
    function setMarketBorrowCaps(CToken[] calldata cTokens, uint[] calldata newBorrowCaps) external {
    	require(msg.sender == admin || msg.sender == borrowCapGuardian, "only admin or borrow cap guardian can set borrow caps"); 

        uint numMarkets = cTokens.length;
        uint numBorrowCaps = newBorrowCaps.length;

        require(numMarkets != 0 && numMarkets == numBorrowCaps, "invalid input");

        for(uint i = 0; i < numMarkets; i++) {
            borrowCaps[address(cTokens[i])] = newBorrowCaps[i];
            emit NewBorrowCap(cTokens[i], newBorrowCaps[i]);
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

    function setMintPaused(CToken cToken, bool state) public returns (bool) {
        require(markets[address(cToken)].isListed, "cannot pause a market that is not listed");
        require(msg.sender == pauseGuardian || msg.sender == admin, "only pause guardian and admin can pause");
        require(msg.sender == admin || state == true, "only admin can unpause");

        mintGuardianPaused[address(cToken)] = state;
        emit ActionPaused(cToken, "Mint", state);
        return state;
    }

    function setBorrowPaused(ICToken cToken, bool state) public returns (bool) {
        require(markets[address(cToken)].isListed, "cannot pause a market that is not listed");
        require(msg.sender == pauseGuardian || msg.sender == admin, "only pause guardian and admin can pause");
        require(msg.sender == admin || state == true, "only admin can unpause");

        borrowGuardianPaused[address(cToken)] = state;
        emit ActionPaused(cToken, "Borrow", state);
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
        return msg.sender == admin || msg.sender == comptrollerImplementation;
    }

    /*** Comp Distribution ***/

    /**
     * @notice Set COMP speed for a single market
     * @param cToken The market whose COMP speed to update
     * @param supplySpeed New supply-side COMP speed for market
     * @param borrowSpeed New borrow-side COMP speed for market
     */
    function setCompSpeedInternal(ICToken cToken, uint supplySpeed, uint borrowSpeed) internal {
        Market storage market = markets[address(cToken)];
        require(market.isListed, "comp market is not listed");

        if (compSupplySpeeds[address(cToken)] != supplySpeed) {
            // Supply speed updated so lets update supply state to ensure that
            //  1. COMP accrued properly for the old speed, and
            //  2. COMP accrued at the new speed starts after this block.
            updateCompSupplyIndex(address(cToken));

            // Update speed and emit event
            compSupplySpeeds[address(cToken)] = supplySpeed;
            emit CompSupplySpeedUpdated(cToken, supplySpeed);
        }

        if (compBorrowSpeeds[address(cToken)] != borrowSpeed) {
            // Borrow speed updated so lets update borrow state to ensure that
            //  1. COMP accrued properly for the old speed, and
            //  2. COMP accrued at the new speed starts after this block.
            updateCompBorrowIndex(address(cToken), cToken.borrowIndex());

            // Update speed and emit event
            compBorrowSpeeds[address(cToken)] = borrowSpeed;
            emit CompBorrowSpeedUpdated(cToken, borrowSpeed);
        }
    }

    /**
     * @notice Accrue COMP to the market by updating the supply index
     * @param cToken The market whose supply index to update
     * @dev Index is a cumulative sum of the COMP per cToken accrued.
     */
    function updateCompSupplyIndex(address cToken) internal {
        CompMarketState storage supplyState = compSupplyState[cToken];
        uint supplySpeed = compSupplySpeeds[cToken];
        uint blockNumber = getBlockNumber();
        uint deltaBlocks = blockNumber - supplyState.block;
        if (deltaBlocks > 0 && supplySpeed > 0) {
            uint supplyTokens = ICToken(cToken).totalSupply();
            uint compAccrued = deltaBlocks * supplySpeed;
            uint ratio = supplyTokens > 0 ? (compAccrued * 1e18) / supplyTokens : 0;
            supplyState.index += ratio;
            supplyState.block = blockNumber;
        } else if (deltaBlocks > 0) {
            supplyState.block = blockNumber;
        }
    }

    /**
     * @notice Accrue COMP to the market by updating the borrow index
     * @param cToken The market whose borrow index to update
     * @dev Index is a cumulative sum of the COMP per cToken accrued.
     */
    function updateCompBorrowIndex(address cToken, uint marketBorrowIndex) internal {
        CompMarketState storage borrowState = compBorrowState[cToken];
        uint borrowSpeed = compBorrowSpeeds[cToken];
        uint blockNumber = getBlockNumber();
        uint deltaBlocks = blockNumber - borrowState.block;
        if (deltaBlocks > 0 && borrowSpeed > 0) {
            uint borrowAmount = ICToken(cToken).totalBorrows() / marketBorrowIndex;
            uint compAccrued = deltaBlocks * borrowSpeed;
            uint ratio = borrowAmount > 0 ? (compAccrued * 1e18) / borrowAmount : 0;
            borrowState.index += ratio;
            borrowState.block = blockNumber;
        } else if (deltaBlocks > 0) {
            borrowState.block = blockNumber;
        }
    }

    /**
     * @notice Calculate COMP accrued by a supplier and possibly transfer it to them
     * @param cToken The market in which the supplier is interacting
     * @param supplier The address of the supplier to distribute COMP to
     */
    function distributeSupplierComp(address cToken, address supplier) internal {
        // TODO: Dont distribute supplier COMP if the user is not in the supplier market.
        // This check should be as gas efficient as possible as distributeSupplierComp is called in many places.
        // - We really dont want to call an external contract as thats quite expensive.

        CompMarketState storage supplyState = compSupplyState[cToken];
        uint supplyIndex = supplyState.index;
        uint supplierIndex = compSupplierIndex[cToken][supplier];

        // Update suppliers index to the current index since we are distributing accrued COMP
        compSupplierIndex[cToken][supplier] = supplyIndex;

        if (supplierIndex == 0 && supplyIndex >= compInitialIndex) {
            // Covers the case where users supplied tokens before the markets supply state index was set.
            // Rewards the user with COMP accrued from the start of when supplier rewards were first
            // set for the market.
            supplierIndex = compInitialIndex;
        }

        // Calculate change in the cumulative sum of the COMP per cToken accrued
        uint deltaIndex = supplyIndex - supplierIndex;

        uint supplierTokens = ICToken(cToken).balanceOf(supplier);

        // Calculate COMP accrued: cTokenAmount * accruedPerCToken
        uint supplierDelta = supplierTokens * deltaIndex;
        compAccrued[supplier] += supplierDelta;

        emit DistributedSupplierComp(ICToken(cToken), supplier, supplierDelta, supplyIndex);
    }

    /**
     * @notice Calculate COMP accrued by a borrower and possibly transfer it to them
     * @dev Borrowers will not begin to accrue until after the first interaction with the protocol.
     * @param cToken The market in which the borrower is interacting
     * @param borrower The address of the borrower to distribute COMP to
     */
    function distributeBorrowerComp(address cToken, address borrower, uint marketBorrowIndex) internal {
        // TODO: Dont distribute supplier COMP if the user is not in the borrower market.
        // This check should be as gas efficient as possible as distributeBorrowerComp is called in many places.
        // - We really dont want to call an external contract as thats quite expensive.

        CompMarketState storage borrowState = compBorrowState[cToken];
        uint borrowIndex = borrowState.index;
        uint borrowerIndex = compBorrowerIndex[cToken][borrower];

        // Update borrowerss index to the current index since we are distributing accrued COMP
        compBorrowerIndex[cToken][borrower] = borrowIndex;

        if (borrowerIndex == 0 && borrowIndex >= compInitialIndex) {
            // Covers the case where users borrowed tokens before the markets borrow state index was set.
            // Rewards the user with COMP accrued from the start of when borrower rewards were first
            // set for the market.
            borrowerIndex = compInitialIndex;
        }

        // Calculate change in the cumulative sum of the COMP per borrowed unit accrued
        uint deltaIndex = borrowIndex - borrowerIndex;

        uint borrowerAmount = ICToken(cToken).borrowBalanceStored(borrower) / marketBorrowIndex;
        
        // Calculate COMP accrued: cTokenAmount * accruedPerBorrowedUnit
        uint borrowerDelta = borrowerAmount * deltaIndex;
        compAccrued[borrower] += borrowerDelta;

        emit DistributedBorrowerComp(ICToken(cToken), borrower, borrowerDelta, borrowIndex);
    }

    /**
     * @notice Calculate additional accrued COMP for a contributor since last accrual
     * @param contributor The address to calculate contributor rewards for
     */
    function updateContributorRewards(address contributor) public {
        uint compSpeed = compContributorSpeeds[contributor];
        uint blockNumber = getBlockNumber();
        uint deltaBlocks = blockNumber - lastContributorBlock[contributor];
        if (deltaBlocks > 0 && compSpeed > 0) {
            uint newAccrued = deltaBlocks * compSpeed;
            compAccrued[contributor] += newAccrued;
            lastContributorBlock[contributor] = blockNumber;
        }
    }

    /**
     * @notice Claim all the comp accrued by holder in all markets
     * @param holder The address to claim COMP for
     */
    function claimComp(address holder) public {
        claimComp(holder, allMarkets);
    }

    /**
     * @notice Claim all the comp accrued by holder in the specified markets
     * @param holder The address to claim COMP for
     * @param cTokens The list of markets to claim COMP in
     */
    function claimComp(address holder, ICToken[] memory cTokens) public {
        address[] memory holders = new address[](1);
        holders[0] = holder;
        claimComp(holders, cTokens, true, true);
    }

    /**
     * @notice Claim all comp accrued by the holders
     * @param holders The addresses to claim COMP for
     * @param cTokens The list of markets to claim COMP in
     * @param borrowers Whether or not to claim COMP earned by borrowing
     * @param suppliers Whether or not to claim COMP earned by supplying
     */
    function claimComp(address[] memory holders, ICToken[] memory cTokens, bool borrowers, bool suppliers) public {
        for (uint i = 0; i < cTokens.length; i++) {
            ICToken cToken = cTokens[i];
            require(markets[address(cToken)].isListed, "market must be listed");
            if (borrowers) {
                uint borrowIndex = cToken.borrowIndex();
                updateCompBorrowIndex(address(cToken), borrowIndex);
                for (uint j = 0; j < holders.length; j++) {
                    distributeBorrowerComp(address(cToken), holders[j], borrowIndex);
                }
            }
            if (suppliers) {
                updateCompSupplyIndex(address(cToken));
                for (uint j = 0; j < holders.length; j++) {
                    distributeSupplierComp(address(cToken), holders[j]);
                }
            }
        }
        for (uint j = 0; j < holders.length; j++) {
            compAccrued[holders[j]] = grantCompInternal(holders[j], compAccrued[holders[j]]);
        }
    }

    /**
     * @notice Transfer COMP to the user
     * @dev Note: If there is not enough COMP, we do not perform the transfer all.
     * @param user The address of the user to transfer COMP to
     * @param amount The amount of COMP to (possibly) transfer
     * @return The amount of COMP which was NOT transferred to the user
     */
    function grantCompInternal(address user, uint amount) internal returns (uint) {
        Neb comp = Neb(getCompAddress());
        uint compRemaining = comp.balanceOf(address(this));
        if (amount > 0 && amount <= compRemaining) {
            comp.transfer(user, amount);
            return 0;
        }
        return amount;
    }

    /*** Comp Distribution Admin ***/

    /**
     * @notice Transfer COMP to the recipient
     * @dev Note: If there is not enough COMP, we do not perform the transfer all.
     * @param recipient The address of the recipient to transfer COMP to
     * @param amount The amount of COMP to (possibly) transfer
     */
    function grantComp(address recipient, uint amount) public {
        require(adminOrInitializing(), "only admin can grant comp");
        uint amountLeft = grantCompInternal(recipient, amount);
        require(amountLeft == 0, "insufficient comp for grant");
        emit CompGranted(recipient, amount);
    }

    /**
     * @notice Set COMP borrow and supply speeds for the specified markets.
     * @param cTokens The markets whose COMP speed to update.
     * @param supplySpeeds New supply-side COMP speed for the corresponding market.
     * @param borrowSpeeds New borrow-side COMP speed for the corresponding market.
     */
    function setCompSpeeds(CToken[] memory cTokens, uint[] memory supplySpeeds, uint[] memory borrowSpeeds) public {
        require(adminOrInitializing(), "only admin can set comp speed");

        uint numTokens = cTokens.length;
        require(numTokens == supplySpeeds.length && numTokens == borrowSpeeds.length, "Comptroller::_setCompSpeeds invalid input");

        for (uint i = 0; i < numTokens; ++i) {
            setCompSpeedInternal(cTokens[i], supplySpeeds[i], borrowSpeeds[i]);
        }
    }

    /**
     * @notice Set COMP speed for a single contributor
     * @param contributor The contributor whose COMP speed to update
     * @param compSpeed New COMP speed for contributor
     */
    function _setContributorCompSpeed(address contributor, uint compSpeed) public {
        require(adminOrInitializing(), "only admin can set comp speed");

        // note that COMP speed could be set to 0 to halt liquidity rewards for a contributor
        updateContributorRewards(contributor);
        if (compSpeed == 0) {
            // release storage
            delete lastContributorBlock[contributor];
        } else {
            lastContributorBlock[contributor] = getBlockNumber();
        }
        compContributorSpeeds[contributor] = compSpeed;

        emit ContributorCompSpeedUpdated(contributor, compSpeed);
    }

    /**
     * @notice Return all of the markets
     * @dev The automatic getter may be used to access an individual market.
     * @return The list of market addresses
     */
    function getAllMarkets() public view returns (ICToken[] memory) {
        return allMarkets;
    }

    /**
     * @notice Returns true if the given cToken market has been deprecated
     * @dev All borrows in a deprecated cToken market can be immediately liquidated
     * @param cToken The market to check if deprecated
     */
    function isDeprecated(ICToken cToken) public view returns (bool) {
        return
            markets[address(cToken)].collateralFactorMantissa == 0 && 
            borrowGuardianPaused[address(cToken)] == true && 
            cToken.reserveFactorMantissa() == 1e18
        ;
    }

    function getBlockNumber() public view returns (uint) {
        return block.number;
    }

    /**
     * @notice Return the address of the COMP token
     * @return The address of COMP
     */
    function getCompAddress() public view returns (address) {
        return 0xc00e94Cb662C3520282E6f5717214004A7f26888;
    }
}
