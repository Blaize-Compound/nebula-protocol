from brownie import *
from dotenv import load_dotenv, find_dotenv
from brownie.convert.normalize import format_input
from brownie.convert import to_bytes
from utils.deploy_helpers import deploy_proxy, deploy_admin
import os
import json


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

    print(f"User is currently allowed to borrow {usdc_allowed_to_borrow} USDC tokens")

    # Borrow USDC for 1$ worth
    usdc_borrow_amount = 1e6

    print("User's USDC balance before borrowing: ", usdc.balanceOf(user) / 1e6)
    print("User's USDC Market Token Borrow balance before borrowing", usdc_market.borrowBalanceStored(user) / 1e6)

    usdc_market.borrow(usdc_borrow_amount, {"from": user})

    print("User's USDC balance after borrowing: ", usdc.balanceOf(user) / 1e6)
    print("User's USDC Market Token Borrow balance after borrowing", usdc_market.borrowBalanceStored(user) / 1e6)
