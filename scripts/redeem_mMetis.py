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
    controller = Controller.at(deployed_contracts_addresses["Controller"])

    # Redeeming all the balance of Metis Market Token and receiving Metic tokens
    redeem_balance = metis_market.balanceOf(user)

    print("Your Metis Market Token balance before redeeming: ", redeem_balance / 1e8)
    print("Your Metis balance before redeeming: ", metis.balanceOf(user) / 1e18)

    # Redeem mMetis and receiving Metis in exchange
    metis_market.redeem(redeem_balance, {"from": user})

    print("Your Metis Market Token balance before redeeming: ", metis_market.balanceOf(user) / 1e8)
    print("Your Metis balance after redeeming: ", metis.balanceOf(user) / 1e18)
