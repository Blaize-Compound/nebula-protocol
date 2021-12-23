import pytest
from brownie import *
import os
from dotenv import load_dotenv, find_dotenv
from utils.deploy_helpers import deploy_proxy, deploy_admin


@pytest.fixture(scope="module")
def env_settings():
    yield load_dotenv(find_dotenv())


@pytest.fixture(scope="module")
def deployer(accounts):
    yield accounts[0]


@pytest.fixture(scope="module")
def user1(accounts):
    yield accounts[1]


@pytest.fixture(scope="module")
def user2(accounts):
    yield accounts[2]


@pytest.fixture(scope="module")
def user3(accounts):
    yield accounts[3]


@pytest.fixture(scope="module")
def user4(accounts):
    yield accounts[4]


@pytest.fixture(scope="module")
def usdc(deployer, ERC20PresetMinterPauserMock):
    yield deployer.deploy(
        ERC20PresetMinterPauserMock,
        "USD Coin",
        "USDC",
        6
    )


@pytest.fixture(scope="module")
def wbtc(deployer, ERC20PresetMinterPauserMock):
    yield deployer.deploy(
        ERC20PresetMinterPauserMock,
        "Wrapped BTC",
        "WBTC",
        8
    )


@pytest.fixture(scope="module")
def weth(deployer, ERC20PresetMinterPauserMock):
    yield deployer.deploy(
        ERC20PresetMinterPauserMock,
        "Wrapped ETH",
        "WETH",
        18
    )


@pytest.fixture(scope="module")
def usdc_rate_model(deployer, BaseJumpRateModelV2):
    yield deployer.deploy(
        BaseJumpRateModelV2,
        0.57e18,
        39222804184156400,
        3272914755156920000,
        800000000000000000,
        deployer
    )


@pytest.fixture(scope="module")
def wbtc_rate_model(deployer, BaseJumpRateModelV2):
    yield deployer.deploy(
        BaseJumpRateModelV2,
        0.57e18,
        262458573636948000,
        370843987858870000,
        800000000000000000,
        deployer
    )


@pytest.fixture(scope="module")
def weth_rate_model(deployer, BaseJumpRateModelV2):
    yield deployer.deploy(
        BaseJumpRateModelV2,
        0.57e18,
        95322621997923200,
        222330528872230000,
        800000000000000000,
        deployer
    )


@pytest.fixture(scope="module")
def controller(deployer, Controller):
    yield deployer.deploy(Controller)


@pytest.fixture(scope="module")
def cUsdc(deployer, usdc, usdc_rate_model, controller, CErc20):
    ctoken = deployer.deploy(CErc20)
    ctoken.initialize(
        usdc,
        controller,
        usdc_rate_model,
        2e14,
        "cUSDC",
        "CUSDC",
        6
    )
    ctoken.setRestPeriod(4 * 3600)
    ctoken.setReserveFactor(0.1e18)
    yield ctoken


@pytest.fixture(scope="module")
def cWbtc(deployer, wbtc, wbtc_rate_model, controller, CErc20):
    ctoken = deployer.deploy(CErc20)
    ctoken.initialize(
        wbtc,
        controller,
        wbtc_rate_model,
        2e16,
        "cWBTC",
        "CWBTC",
        8
    )
    ctoken.setRestPeriod(4 * 3600)
    ctoken.setReserveFactor(0.2e18)
    yield ctoken


@pytest.fixture(scope="module")
def cWeth(deployer, weth, weth_rate_model, controller, CErc20):
    ctoken = deployer.deploy(CErc20)
    ctoken.initialize(
        weth,
        controller,
        weth_rate_model,
        2e26,
        "cWETH",
        "CWETH",
        18
    )
    ctoken.setRestPeriod(4 * 3600)
    ctoken.setReserveFactor(0.25e18)
    yield ctoken


@pytest.fixture(scope="module")
def oracle_mock(deployer, cUsdc, cWeth, cWbtc, SimplePriceOracle):
    oracle = deployer.deploy(SimplePriceOracle)
    oracle.setUnderlyingPrice(cUsdc, 1e18)
    oracle.setUnderlyingPrice(cWbtc, 50e18)
    oracle.setUnderlyingPrice(cWeth, 4000e18)
    yield oracle


@pytest.fixture(scope="module", autouse=True)
def setup_controller(controller, oracle_mock, cUsdc, cWbtc, cWeth):
    controller.setPriceOracle(oracle_mock)
    controller.setCloseFactor(0.5e18)
    controller.setLiquidationIncentive(1.1e18)

    controller.supportMarket(cUsdc)
    controller.supportMarket(cWbtc)
    controller.supportMarket(cWeth)

    controller.setCollateralFactor(cUsdc, 0.85e18)
    controller.setCollateralFactor(cWbtc, 0.75e18)
    controller.setCollateralFactor(cWeth, 0.75e18)


@pytest.fixture(autouse=True)
def isolation(fn_isolation):
    pass
