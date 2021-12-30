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
    metis = ERC20PresetMinterPauserMock.at(tokens["METIS"])
    metis_market = MErc20.at(deployed_contracts_addresses["MetisMarketToken"])

    # !!! NOTE !!! You need to have enough Metis tokens in order to repay your borrow
    borrow_amount_fixed = (metis_market.getAccountSnapshot(user)[3] - metis_market.borrowBalanceStored(user)) / 1e18

    print(f"You have borrow with fixed rate in quantity {borrow_amount_fixed} Metis tokens")

    # Repaing the first one of borrows
    print("Your Metis balance before repaying borrow: ", metis.balanceOf(user) / 1e18)

    print("Your amount of borrows with fixed rate before repaying: ", metis_market.fixedBorrowsAmount(user))
    metis.approve(metis_market, metis.balanceOf(user), {"from": user})
    metis_market.repayBorrowFixedRate([0], {"from": user})

    print("Your Metis balance after repaying borrow: ", metis.balanceOf(user) / 1e18)
    print("You debt with fixed rate after repaying borrow: ", (metis_market.getAccountSnapshot(user)[3] - metis_market.borrowBalanceStored(user)) / 1e18)
    print("Your amount of borrows with fixed rate after repaying: ", metis_market.fixedBorrowsAmount(user))
