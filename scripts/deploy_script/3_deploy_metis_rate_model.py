from brownie import *
from dotenv import load_dotenv, find_dotenv
from brownie.convert.normalize import format_input
from brownie.convert import to_bytes
from utils.deploy_helpers import deploy_proxy, deploy_admin
import os


def main():
    load_dotenv(dotenv_path="./.env", override=True)
    load_dotenv(find_dotenv())
    deployer = accounts.add(os.getenv("DEPLOYER_PRIVATE_KEY"))

    interest_model = deployer.deploy(
        BaseJumpRateModelV2,
        0.57e18,
        95322621997923200,
        222330528872230000,
        800000000000000000,
        deployer
    )

    print(f"Interest rate model for metis deployed at {interest_model}")
