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
    deployed_contracts_addresses = data["deployedContracts"]

    oracle_mock = deployer.deploy(SimplePriceOracle)

    oracle_mock.setUnderlyingPrice(deployed_contracts_addresses["UsdcMarketToken"], 1e18, {"from": deployer})
    oracle_mock.setUnderlyingPrice(deployed_contracts_addresses["MetisMarketToken"], 80e18, {"from": deployer})