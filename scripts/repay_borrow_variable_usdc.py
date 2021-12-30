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

    # !!! NOTE !!! You need to have enough USDC tokens in order to repay your borrow
    borrow_amount = usdc_market.borrowBalanceStored(user)

    print(f"You have borrow in quantity {borrow_amount / 1e6}")

    # Repay user's borrow
    print("Your USDC balance before borrowing: ", usdc.balanceOf(user) / 1e6)

    usdc.approve(usdc_market, borrow_amount, {"from": user})
    usdc_market.repayBorrow(borrow_amount, {"from": user})

    print("Your Metis balance after borrowing: ", usdc.balanceOf(user) / 1e6)
    print("You debt after repaying borrow: ", usdc_market.borrowBalanceStored(user) / 1e6)
