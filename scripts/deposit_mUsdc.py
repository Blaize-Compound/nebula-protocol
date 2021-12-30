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

    # Set amount of USDC to deposit(currently 5 USDC)
    amount_to_deposit = 5e6

    # Approving USDC
    usdc.approve(usdc_market, amount_to_deposit, {"from": user})

    # Depositing USDC tokens to USDC Market Token
    print("Your balance of USDC before depositing: ", usdc.balanceOf(user) / 1e6)
    print("Your balance of USDC Market Token before depositing:", usdc_market.balanceOf(user) / 1e8)
    
    usdc_market.mint(amount_to_deposit, {"from": user})

    print("Your balance of USDC after depositing: ", usdc.balanceOf(user) / 1e6)
    print("Your balance of USDC Market Token after depositing:", usdc_market.balanceOf(user) / 1e8)

    # Entering the market, marking that asset can be used as collateral
    controller.enterMarkets([usdc_market], {"from": user})