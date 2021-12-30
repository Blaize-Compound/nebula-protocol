from brownie import *
from dotenv import load_dotenv, find_dotenv
from brownie.convert.normalize import format_input
from brownie.convert import to_bytes
from utils.deploy_helpers import deploy_proxy, deploy_admin
import os
import json

ONE_WEEK = 7 * 86400


def main():
    load_dotenv(dotenv_path="./.env", override=True)
    load_dotenv(find_dotenv())
    user = accounts.add(os.getenv("USER_PRIVATE_KEY"))

    f = open('./scripts/deploy_script/deploy_info.json')
    data = json.load(f)
    tokens = data["tokens"]
    deployed_contracts_addresses = data["deployedContracts"]

    # Getting instances of contracts
    usdc = ERC20PresetMinterPauserMock.at(tokens["USDC"])
    usdc_market = MErc20.at(deployed_contracts_addresses["UsdcMarketToken"])
    controller = Controller.at(deployed_contracts_addresses["Controller"])
    price_oracle = SimplePriceOracle.at(deployed_contracts_addresses["PriceOracle"])

    
    # !!! NOTE !!! You need to have enough collateral in order to borrow
    current_liquidity = controller.getAccountLiquidity(user)[0]
    usdc_allowed_to_borrow = current_liquidity / price_oracle.assetPrices(usdc)

    print(f"Your are currently allowed to borrow {usdc_allowed_to_borrow} USDC tokens")

    # Borrow 1 USDC with fixed rate for one week long
    usdc_borrow_amount = 1e6

    print("Your USDC balance before borrowing: ", usdc.balanceOf(user) / 1e6)
    print("Your USDC Market Token Borrow balance with fixed rate before borrowing", (usdc_market.getAccountSnapshot(user)[3] - usdc_market.borrowBalanceStored(user)) / 1e6)
    borrows_amount_before = usdc_market.fixedBorrowsAmount(user)
    print("Amount of your loans, taken with fixed rate before borrowing: ", borrows_amount_before)

    usdc_market.borrowFixedRate(usdc_borrow_amount, ONE_WEEK, {"from": user})

    print("Your USDC balance after borrowing: ", usdc.balanceOf(user) / 1e6)
    print("Your USDC Market Token Borrow balance with fixed rate after borrowing", (usdc_market.getAccountSnapshot(user)[3] - usdc_market.borrowBalanceStored(user)) / 1e6)
    print("Amount of your loans, taken with fixed rate after borrowing: ", usdc_market.fixedBorrowsAmount(user))

    # You have borrowed some tokens with fixed rate for one week. After this period,
    # you have 4 hours to repay this borrow, otherwise your position might be liquidated
    # !!! NOTE !!! You are allowed to repay before one week passes, paying for the period
    # you had a loan, but you will also have to pay extra comission for repaying before
    # maturity is reached
