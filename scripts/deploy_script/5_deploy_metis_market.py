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

    m_metis = deployer.deploy(MErc20)
    m_metis.initialize(
        tokens["METIS"],
        deployed_contracts_addresses["Controller"],
        deployed_contracts_addresses["MetisRateModel"],
        2e26,
        "Market Metis",
        "mMetis",
        8,
        {"from": deployer}
    )

    m_metis.setRestPeriod(4 * 3600, {"from": deployer})
    m_metis.setReserveFactor(0.2e18, {"from": deployer})

    print(f"Metis Market token deployed at {m_metis}")