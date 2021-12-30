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
    price_oracle = SimplePriceOracle.at(deployed_contracts_addresses["PriceOracle"])

    # !!! NOTE !!! You need to have enough collateral in order to borrow
    current_liquidity = controller.getAccountLiquidity(user)[0]
    metis_allowed_to_borrow = current_liquidity / price_oracle.assetPrices(metis)

    print(f"Your are currently allowed to borrow {metis_allowed_to_borrow} METIS tokens")

    # Borrow Metis for 1$ worth(Current price is 200$)
    metis_borrow_amount = 0.005e18

    print("Your Metis balance before borrowing: ", metis.balanceOf(user) / 1e18)
    print("Your Metis Market Token Borrow balance before borrowing", metis_market.borrowBalanceStored(user) / 1e18)

    metis_market.borrow(metis_borrow_amount, {"from": user})

    print("Your Metis balance after borrowing: ", metis.balanceOf(user) / 1e18)
    print("Your Metis Market Token Borrow balance after borrowing", metis_market.borrowBalanceStored(user) / 1e18)
