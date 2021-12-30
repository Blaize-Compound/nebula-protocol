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

    # Redeeming all the balance of USDC Market Token and receiving USDC tokens
    redeem_balance = usdc_market.balanceOf(user)

    print("Your USDC Market Token balance before redeeming: ", redeem_balance / 1e8)
    print("Your USDC balance before redeeming: ", usdc.balanceOf(user) / 1e6)

    # Redeem mUSDC and receiving USDC in exchange
    usdc_market.redeem(redeem_balance, {"from": user})

    print("Your USDC Market Token balance after redeeming: ", usdc_market.balanceOf(user) / 1e8)
    print("Your USDC balance after redeeming: ", usdc.balanceOf(user) / 1e6)
