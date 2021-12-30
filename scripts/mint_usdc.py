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
    owner = accounts.add(os.getenv("DEPLOYER_PRIVATE_KEY"))

    f = open('./scripts/deploy_script/deploy_info.json')
    data = json.load(f)
    tokens = data["tokens"]

    # Getting instance of USDC
    usdc = ERC20PresetMinterPauserMock.at(tokens["USDC"])

    # Minting 50 test USDC
    usdc.mint(os.getenv("USER_ADDRESS"), 50e6, {"from": owner})

    print(f"You are now having {usdc.balanceOf(os.getenv("USER_ADDRESS")) / 1e6} USDC")
