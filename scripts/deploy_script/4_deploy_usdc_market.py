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

    # usdc_token = deployer.deploy(
    #     ERC20PresetMinterPauserMock,
    #     "USD Coin",
    #     "USDC",
    #     6
    # )

    # m_usdc = deployer.deploy(MErc20)
    m_usdc = MErc20.at(deployed_contracts_addresses["UsdcMarketToken"])
    m_usdc.initialize(
        tokens["USDC"],
        deployed_contracts_addresses["Controller"],
        deployed_contracts_addresses["UsdcRateModel"],
        2e14,
        "Market USD Coin",
        "mUSDC",
        8,
        {"from": deployer}
    )

    m_usdc.setRestPeriod(4 * 3600, {"from": deployer})
    m_usdc.setReserveFactor(0.1e18, {"from": deployer})

    print(f"Usdc token deployed at {usdc_token}")
    print(f"USDC Market token deployed at {m_usdc}")
