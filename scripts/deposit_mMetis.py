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

    # Set amount of Metis to deposit(currently 0.1 Metis)
    amount_to_deposit = 0.1e18

    # Approving Metis
    metis.approve(metis_market, amount_to_deposit, {"from": user})

    # Depositing Metis tokens to Metis Market Token
    print("Your balance of Metis before depositing: ", metis.balanceOf(user) / 1e18)
    print("Your balance of Metis Market Token before depositing:", metis_market.balanceOf(user) / 1e8)
    
    metis_market.mint(amount_to_deposit, {"from": user})

    print("Your balance of Metis after depositing: ", metis.balanceOf(user) / 1e18)
    print("Your balance of Metis Market Token after depositing:", metis_market.balanceOf(user) / 1e8)

    # Entering the market, marking that asset can be used as collateral
    controller.enterMarkets([metis_market], {"from": user})
