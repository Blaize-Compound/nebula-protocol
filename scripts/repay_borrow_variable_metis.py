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

    rate_model = BaseJumpRateModelV2.at(deployed_contracts_addresses["MetisRateModel"])

    print("Cash: ", metis.balanceOf(metis_market))
    print("Borrows: ",  metis_market.getTotalBorrows())
    print("reserves: ", metis_market.totalReserves())
    print(rate_model.utilizationRate(
        metis.balanceOf(metis_market),
        metis_market.getTotalBorrows(),
        metis_market.totalReserves()
    ))
    print(rate_model.getBorrowRate(
        metis.balanceOf(metis_market),
        metis_market.getTotalBorrows(),
        metis_market.totalReserves()
    ))
    # !!! NOTE !!! You need to have enough Metis tokens in order to repay your borrow
    borrow_amount = metis_market.borrowBalanceStored(user)

    print(f"You have borrow in quantity {borrow_amount / 1e18}")

    # Repay user's borrow
    print("Your Metis balance before repaying borrow: ", metis.balanceOf(user) / 1e18)

    print("Borrow balance: ", metis_market.borrowBalanceStored(user, {"from": user}) / 1e18)
    metis.approve(metis_market, borrow_amount, {"from": user})
    metis_market.repayBorrow(borrow_amount, {"from": user})

    print("Your Metis balance after repaying borrow: ", metis.balanceOf(user) / 1e18)
    print("You debt after repaying borrow: ", metis_market.borrowBalanceStored(user) / 1e18)
