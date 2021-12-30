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

    controller = Controller.at(deployed_contracts_addresses["Controller"])

    controller.setPriceOracle(deployed_contracts_addresses["PriceOracle"], {"from": deployer})
    controller.setCloseFactor(0.5e18, {"from": deployer})
    controller.setLiquidationIncentive(1.1e18, {"from": deployer})

    controller.supportMarket(deployed_contracts_addresses["UsdcMarketToken"], {"from": deployer})
    controller.setCollateralFactor(deployed_contracts_addresses["UsdcMarketToken"], 0.85e18, {"from": deployer})

    controller.supportMarket(deployed_contracts_addresses["MetisMarketToken"], {"from": deployer})
    controller.setCollateralFactor(deployed_contracts_addresses["MetisMarketToken"], 0.75e18, {"from": deployer})