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
    deployer = accounts.add(os.getenv("DEPLOYER_PRIVATE_KEY"))

    f = open('./scripts/deploy_script/deploy_info.json')
    data = json.load(f)
    tokens = data["tokens"]
    deployed_contracts_addresses = data["deployedContracts"]

    # Getting instances of contracts
    metis = ERC20PresetMinterPauserMock.at(tokens["METIS"])
    metis_market = MErc20.at(deployed_contracts_addresses["MetisMarketToken"])
    usdc = ERC20PresetMinterPauserMock.at(tokens["USDC"])
    usdc_market = MErc20.at(deployed_contracts_addresses["UsdcMarketToken"])

    # Add usdc to reserves
    amount = 200e6
    usdc.mint(deployer, amount, {"from": deployer})

    usdc.approve(usdc_market, amount, {"from": deployer})
    usdc_market.addReserves(amount, {"from": deployer})

