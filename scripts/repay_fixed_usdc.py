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
    borrow_amount_fixed = (usdc_market.getAccountSnapshot(user)[3] - usdc_market.borrowBalanceStored(user)) / 1e6

    print(f"You have borrow with fixed rate in quantity {borrow_amount_fixed} USDC tokens")

    # Repaing the first one of borrows
    print("Your USDC balance before repaying borrow: ", usdc.balanceOf(user) / 1e6)

    print("Your amount of borrows with fixed rate before repaying: ", usdc_market.fixedBorrowsAmount(user))
    usdc.approve(usdc_market, usdc.balanceOf(user), {"from": user})
    usdc_market.repayBorrowFixedRate([0], {"from": user})

    print("Your USDC balance after repaying borrow: ", usdc.balanceOf(user) / 1e6)
    print("You debt with fixed rate after repaying borrow: ", (usdc_market.getAccountSnapshot(user)[3] - usdc_market.borrowBalanceStored(user)) / 1e6)
    print("Your amount of borrows with fixed rate after repaying: ", usdc_market.fixedBorrowsAmount(user))
