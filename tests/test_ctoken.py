import pytest
import brownie
from brownie import *
import os
from dotenv import load_dotenv, find_dotenv
from utils.deploy_helpers import deploy_proxy, deploy_admin


MAX_UINT = 115792089237316195423570985008687907853269984665640564039457584007913129639935
ONE_WEEK = 7 * 86400
TWO_WEEKS = 2 * 7 * 86400
ONE_MONTH = 4 * 7 * 86400
SECONDS_PER_BLOCK = 15


def mint_token(token, to, amount):
    token.mint(to, amount)

def test_deposit_redeem(user1, user2, usdc, wbtc, weth, cUsdc, cWeth, cWbtc, controller):
    # Part with USDC
    amount1 = 1e6
    amount2 = 5e6
    mint_token(usdc, user1, amount1)
    mint_token(usdc, user2, amount2)

    # Mint
    usdc.approve(cUsdc, amount1, {"from": user1})
    cUsdc.mint(amount1, {"from": user1})
    assert cUsdc.balanceOf(user1) == 50e8
    assert usdc.balanceOf(user1) == 0

    usdc.approve(cUsdc, amount2, {"from": user2})
    cUsdc.mint(amount2, {"from": user2})
    assert cUsdc.balanceOf(user2) == 250e8
    assert usdc.balanceOf(user2) == 0

    # Redeem
    balance1 = cUsdc.balanceOf(user1)
    balance2 = cUsdc.balanceOf(user2)

    controller.enterMarkets([cUsdc], {"from": user1})

    cUsdc.redeem(balance1, {"from": user1})
    assert cUsdc.balanceOf(user1) == 0
    assert usdc.balanceOf(user1) == amount1

    cUsdc.redeem(balance2, {"from": user2})
    assert cUsdc.balanceOf(user2) == 0
    assert usdc.balanceOf(user2) == amount2

    # Part with WBTC
    amount1 = 1e8
    amount2 = 5e8
    mint_token(wbtc, user1, amount1)
    mint_token(wbtc, user2, amount2)

    # Mint
    wbtc.approve(cWbtc, amount1, {"from": user1})
    cWbtc.mint(amount1, {"from": user1})
    assert cWbtc.balanceOf(user1) == 50e8
    assert wbtc.balanceOf(user1) == 0

    wbtc.approve(cWbtc, amount2, {"from": user2})
    cWbtc.mint(amount2, {"from": user2})
    assert cWbtc.balanceOf(user2) == 250e8
    assert wbtc.balanceOf(user2) == 0

    # Redeem
    balance1 = cWbtc.balanceOf(user1)
    balance2 = cWbtc.balanceOf(user2)

    cWbtc.redeem(balance1, {"from": user1})
    assert cWbtc.balanceOf(user1) == 0
    assert wbtc.balanceOf(user1) == amount1

    cWbtc.redeem(balance2, {"from": user2})
    assert cWbtc.balanceOf(user2) == 0
    assert wbtc.balanceOf(user2) == amount2

    # Part with WETH
    amount1 = 1e18
    amount2 = 5e18
    mint_token(weth, user1, amount1)
    mint_token(weth, user2, amount2)

    # Mint
    weth.approve(cWeth, amount1, {"from": user1})
    cWeth.mint(amount1, {"from": user1})
    assert cWeth.balanceOf(user1) == 50e8
    assert weth.balanceOf(user1) == 0

    weth.approve(cWeth, amount2, {"from": user2})
    cWeth.mint(amount2, {"from": user2})
    assert cWeth.balanceOf(user2) == 250e8
    assert weth.balanceOf(user2) == 0

    # Redeem
    balance1 = cWeth.balanceOf(user1)
    balance2 = cWeth.balanceOf(user2)

    cWeth.redeem(balance1, {"from": user1})
    assert cWeth.balanceOf(user1) == 0
    assert weth.balanceOf(user1) == amount1

    cWeth.redeem(balance2, {"from": user2})
    assert cWeth.balanceOf(user2) == 0
    assert weth.balanceOf(user2) == amount2


# def test_borrow_repay(user1, user2, user3, user4, usdc, wbtc, weth, cUsdc, cWeth, cWbtc, controller):
#     amount1 = 100000e6
#     amount2 = 500000e6
#     mint_token(usdc, user1, amount1)
#     mint_token(usdc, user2, amount2)

#     # Mint
#     usdc.approve(cUsdc, amount1, {"from": user1})
#     cUsdc.mint(amount1, {"from": user1})

#     usdc.approve(cUsdc, amount2, {"from": user2})
#     cUsdc.mint(amount2, {"from": user2})

#     # Mint collateral
#     amount3 = 100e18
#     mint_token(weth, user3, amount3)
#     controller.enterMarkets([cWeth], {"from": user3})

#     weth.approve(cWeth, amount3, {"from": user3})
#     cWeth.mint(amount3, {"from": user3})

#     # Borrow
#     borrow_amount = 300000e6
#     cUsdc.borrow(borrow_amount, {"from": user3})

#     assert usdc.balanceOf(user3) == borrow_amount

#     # Can't transfer collater
#     tx = cWeth.transfer(user1, cWeth.balanceOf(user3), {"from": user3})
#     assert tx.return_value is False

#     chain.sleep(86400)
#     chain.mine(1000)

#     mint_token(usdc, user3, 1000e6)

#     bal_before = usdc.balanceOf(user3)
#     usdc.approve(cUsdc, bal_before, {"from": user3})
#     cUsdc.repayBorrow(MAX_UINT, {"from": user3})

#     interest_accrued = bal_before - borrow_amount - usdc.balanceOf(user3)
#     print("Interest accrued: ", interest_accrued)

#     assert cUsdc.exchangeRateStored() > 2e14
#     assert cUsdc.totalReserves() > 0

#     # Redeem
#     balance1 = cUsdc.balanceOf(user1)
#     balance2 = cUsdc.balanceOf(user2)

#     cUsdc.redeem(balance1, {"from": user1})
#     assert cUsdc.balanceOf(user1) == 0
#     assert usdc.balanceOf(user1) > amount1

#     cUsdc.redeem(balance2, {"from": user2})
#     assert cUsdc.balanceOf(user2) == 0
#     assert usdc.balanceOf(user2) > amount2

#     assert usdc.balanceOf(cUsdc) == cUsdc.totalReserves()

#     print("Interest collected for user1: ", usdc.balanceOf(user1) - amount1)
#     print("Interest collected for user2: ", usdc.balanceOf(user2) - amount2)


# def test_borrow_liquidate(user1, user2, user3, user4, usdc, wbtc,
#                           weth, cUsdc, cWeth, cWbtc, controller, oracle_mock):
#     amount1 = 100000e6
#     amount2 = 500000e6
#     mint_token(usdc, user1, amount1)
#     mint_token(usdc, user2, amount2)

#     # Mint
#     usdc.approve(cUsdc, amount1, {"from": user1})
#     cUsdc.mint(amount1, {"from": user1})

#     usdc.approve(cUsdc, amount2, {"from": user2})
#     cUsdc.mint(amount2, {"from": user2})

#     # Mint collateral
#     amount3 = 100e18
#     mint_token(weth, user3, amount3)
#     controller.enterMarkets([cWeth], {"from": user3})

#     weth.approve(cWeth, amount3, {"from": user3})
#     cWeth.mint(amount3, {"from": user3})

#     c_weth_bal = cWeth.balanceOf(user3)
#     # Borrow
#     borrow_amount = 300000e6
#     cUsdc.borrow(borrow_amount, {"from": user3})

#     assert usdc.balanceOf(user3) == borrow_amount

#     chain.sleep(86400)
#     chain.mine(1000)

#     mint_token(usdc, user4, 310000e6)
#     oracle_mock.setUnderlyingPrice(cWeth, 2000e18)

#     print("Value: ", oracle_mock.getUnderlyingPrice(cUsdc) * 300000000000 // 10**usdc.decimals())
#     print("Cweth exchange rate: ", cWeth.exchangeRateStored())
#     print("Cusdc exchange rate: ", cUsdc.exchangeRateStored())
#     amount_liquidate = controller.getAccountLiquidity(user3)[1] / (10**(18 - usdc.decimals()))
#     print(cUsdc.getAccountSnapshot(user3))
#     print(cWeth.getAccountSnapshot(user3))

#     bal_before = usdc.balanceOf(user4)
#     usdc.approve(cUsdc, bal_before, {"from": user4})

#     print("Liquidate amount: ", amount_liquidate)
#     print("Seize tokens: ", controller.liquidateCalculateSeizeTokens(cUsdc, cWeth, amount_liquidate))
#     cUsdc.liquidateBorrow(user3, 150000e6, cWeth, {"from": user4})

#     interest_accrued = bal_before - borrow_amount - usdc.balanceOf(user4)
#     print("Interest accrued: ", interest_accrued)

#     assert cUsdc.exchangeRateStored() > 2e14
#     assert cUsdc.totalReserves() > 0

#     assert cWeth.balanceOf(user3) < c_weth_bal
#     assert cWeth.balanceOf(user4) > 0
#     assert cWeth.totalReserves() > 0
#     print("cWeth user3 bal after liq: ", cWeth.balanceOf(user3))
#     print("cWeth user4 bal after liq: ", cWeth.balanceOf(user4))

#     # Redeem
#     balance1 = cUsdc.balanceOf(user1)

#     cUsdc.redeem(balance1, {"from": user1})
#     assert cUsdc.balanceOf(user1) == 0
#     assert usdc.balanceOf(user1) > amount1

#     print("Interest collected for user1: ", usdc.balanceOf(user1) - amount1)


# def test_fixed_borrow_repay_after_maturity(user1, user2, user3, user4, usdc, wbtc,
#                             weth, cUsdc, cWeth, cWbtc, controller, oracle_mock):
#     amount1 = 100000e6
#     amount2 = 500000e6
#     mint_token(usdc, user1, amount1)
#     mint_token(usdc, user2, amount2)

#     # Mint
#     usdc.approve(cUsdc, amount1, {"from": user1})
#     cUsdc.mint(amount1, {"from": user1})

#     usdc.approve(cUsdc, amount2, {"from": user2})
#     cUsdc.mint(amount2, {"from": user2})

#     # Mint collateral
#     amount3 = 100e18
#     mint_token(weth, user3, amount3)
#     controller.enterMarkets([cWeth], {"from": user3})

#     weth.approve(cWeth, amount3, {"from": user3})
#     cWeth.mint(amount3, {"from": user3})

#     # Borrow with stable rate
#     borrow_amount = 300000e6

#     current_rate = cUsdc.borrowRatePerBlock() * TWO_WEEKS // SECONDS_PER_BLOCK
#     exchange_rate_before = cUsdc.exchangeRateStored()
#     current_timestamp = chain.time()
#     cUsdc.borrowFixedRate(borrow_amount, TWO_WEEKS, {"from": user3})

#     interested_accumulated = borrow_amount * current_rate // 1e18
#     print("Borrow rate: ", current_rate)
#     print("Interest: ", int(interested_accumulated))
#     assert usdc.balanceOf(user3) == borrow_amount
#     assert cUsdc.totalBorrowsFixed() == borrow_amount + interested_accumulated
#     assert cUsdc.totalReserves() == interested_accumulated * cUsdc.reserveFactorMantissa() // 1e18

#     assert cUsdc.exchangeRateStored() > exchange_rate_before
#     assert cUsdc.fixedBorrowsAmount(user3) == 1

#     borrow_info = cUsdc.accountFixedRateBorrows(user3, 0)
#     assert borrow_info[0] == borrow_amount
#     assert borrow_info[1] == current_rate
#     assert abs(borrow_info[2] - current_timestamp) <= 1
#     assert borrow_info[3] == TWO_WEEKS
#     print("Interest: ", interested_accumulated)

#     # Can't borrow more
#     with brownie.reverts("Insufficient liquidity"):
#         cUsdc.borrow(100000e6, {"from": user3})

#     # Repay after maturity is reached
#     chain.sleep(TWO_WEEKS + 1)
#     chain.mine(1)

#     mint_token(usdc, user3, interested_accumulated)

#     usdc.approve(cUsdc, borrow_amount + interested_accumulated, {"from": user3})
#     cUsdc.repayBorrowFixedRate([0], {"from": user3})

#     assert cUsdc.totalBorrowsFixed() == 0
#     assert cUsdc.fixedBorrowsAmount(user3) == 0

#     # Redeem
#     balance1 = cUsdc.balanceOf(user2)

#     cUsdc.redeem(balance1, {"from": user2})
#     assert cUsdc.balanceOf(user2) == 0
#     assert usdc.balanceOf(user2) > amount2

#     print(usdc.balanceOf(cUsdc))
#     print(cUsdc.totalReserves())
#     print(usdc.balanceOf(user2))
#     print("Interest collected for user2: ", usdc.balanceOf(user2) - amount2)


# def test_fixed_borrow_repay_before_maturity(user1, user2, user3, user4, usdc, wbtc,
#                             weth, cUsdc, cWeth, cWbtc, controller, oracle_mock):
#     amount1 = 100000e6
#     amount2 = 500000e6
#     mint_token(usdc, user1, amount1)
#     mint_token(usdc, user2, amount2)

#     # Mint
#     usdc.approve(cUsdc, amount1, {"from": user1})
#     cUsdc.mint(amount1, {"from": user1})

#     usdc.approve(cUsdc, amount2, {"from": user2})
#     cUsdc.mint(amount2, {"from": user2})

#     # Mint collateral
#     amount3 = 100e18
#     mint_token(weth, user3, amount3)
#     controller.enterMarkets([cWeth], {"from": user3})

#     weth.approve(cWeth, amount3, {"from": user3})
#     cWeth.mint(amount3, {"from": user3})

#     # Borrow with stable rate
#     borrow_amount = 300000e6

#     current_rate = cUsdc.borrowRatePerBlock() * TWO_WEEKS // SECONDS_PER_BLOCK
#     cUsdc.borrowFixedRate(borrow_amount, TWO_WEEKS, {"from": user3})

#     interested_accumulated = borrow_amount * current_rate // 1e18
#     print("Borrow rate: ", current_rate)
#     print("Interest: ", int(interested_accumulated))


#     # Can't borrow more
#     with brownie.reverts("Insufficient liquidity"):
#         cUsdc.borrow(100000e6, {"from": user3})

#     # Repay before maturity is reached
#     chain.sleep(ONE_WEEK)
#     chain.mine(1)

#     expected_interest = interested_accumulated * ONE_WEEK // TWO_WEEKS

#     mint_token(usdc, user3, 5000e6)

#     usdc.approve(cUsdc, borrow_amount + 5000e6, {"from": user3})
#     bal_before = usdc.balanceOf(user3)
#     cUsdc.repayBorrowFixedRate([0], {"from": user3})
#     print("Interest paid: ", bal_before - borrow_amount - usdc.balanceOf(user3))

#     assert cUsdc.totalBorrowsFixed() == 0
#     assert cUsdc.fixedBorrowsAmount(user3) == 0
#     # assert cUsdc.totalReserves() == int(expected_reserves_new)

#     assert usdc.balanceOf(cUsdc) > int(cUsdc.totalReserves() + amount1 + amount2)

#     # Redeem
#     balance1 = cUsdc.balanceOf(user2)

#     cUsdc.redeem(balance1, {"from": user2})
#     assert cUsdc.balanceOf(user2) == 0
#     assert usdc.balanceOf(user2) > amount2

#     print("Interest collected for user1: ", usdc.balanceOf(user2) - amount2)

#     balance1 = cUsdc.balanceOf(user1)

#     cUsdc.redeem(balance1, {"from": user1})
#     assert cUsdc.balanceOf(user1) == 0
#     assert usdc.balanceOf(user1) > amount1

#     print("Interest collected for user1: ", usdc.balanceOf(user1) - amount1)

#     assert usdc.balanceOf(cUsdc) == cUsdc.totalReserves()


# def test_cant_take_fixed_if_taken_enough_borrow(user1, user2, user3, user4, usdc, wbtc,
#                             weth, cUsdc, cWeth, cWbtc, controller, oracle_mock):
#     amount1 = 100000e6
#     amount2 = 500000e6
#     mint_token(usdc, user1, amount1)
#     mint_token(usdc, user2, amount2)

#     # Mint
#     usdc.approve(cUsdc, amount1, {"from": user1})
#     cUsdc.mint(amount1, {"from": user1})

#     usdc.approve(cUsdc, amount2, {"from": user2})
#     cUsdc.mint(amount2, {"from": user2})

#     # Mint collateral
#     amount3 = 100e18
#     mint_token(weth, user3, amount3)
#     controller.enterMarkets([cWeth], {"from": user3})

#     weth.approve(cWeth, amount3, {"from": user3})
#     cWeth.mint(amount3, {"from": user3})

#     # Borrow
#     borrow_amount = 250000e6
#     cUsdc.borrow(borrow_amount, {"from": user3})

#     # Try to borrow with fixed rate

#     with brownie.reverts("Insufficient liquidity"):
#         cUsdc.borrowFixedRate(100000e6, TWO_WEEKS, {"from": user3})

#     with brownie.reverts("Insufficient liquidity"):
#         cUsdc.borrow(100000e6, {"from": user3})


# def test_cant_liquidate_fixed_using_repay_borrow(user1, user2, user3, user4, usdc, wbtc,
#                             weth, cUsdc, cWeth, cWbtc, controller, oracle_mock):
#     amount1 = 100000e6
#     amount2 = 500000e6
#     mint_token(usdc, user1, amount1)
#     mint_token(usdc, user2, amount2)

#     # Mint
#     usdc.approve(cUsdc, amount1, {"from": user1})
#     cUsdc.mint(amount1, {"from": user1})

#     usdc.approve(cUsdc, amount2, {"from": user2})
#     cUsdc.mint(amount2, {"from": user2})

#     # Mint collateral
#     amount3 = 100e18
#     mint_token(weth, user3, amount3)
#     controller.enterMarkets([cWeth], {"from": user3})

#     weth.approve(cWeth, amount3, {"from": user3})
#     cWeth.mint(amount3, {"from": user3})

#     cUsdc.borrowFixedRate(100000e6, TWO_WEEKS, {"from": user3})

#     cUsdc.borrow(200000e6, {"from": user3})

#     # Lower price of collateral
#     oracle_mock.setUnderlyingPrice(cWeth, 3000e18)

#     # Try to liquidate
#     mint_token(usdc, user4, 160000e6)

#     usdc.approve(cUsdc, 160000e6, {"from": user4})
#     with brownie.reverts("Insufficient shortfall"):
#         cUsdc.liquidateBorrow(user3, 150000e6, cWeth, {"from": user4})


# def test_cant_liquidate_fixed_using_repay_borrow_case_2(user1, user2, user3, user4, usdc, wbtc,
#                             weth, cUsdc, cWeth, cWbtc, controller, oracle_mock):
#     amount1 = 100000e6
#     amount2 = 500000e6
#     mint_token(usdc, user1, amount1)
#     mint_token(usdc, user2, amount2)

#     # Mint
#     usdc.approve(cUsdc, amount1, {"from": user1})
#     cUsdc.mint(amount1, {"from": user1})

#     usdc.approve(cUsdc, amount2, {"from": user2})
#     cUsdc.mint(amount2, {"from": user2})

#     # Mint collateral
#     amount3 = 100e18
#     mint_token(weth, user3, amount3)
#     controller.enterMarkets([cWeth], {"from": user3})

#     weth.approve(cWeth, amount3, {"from": user3})
#     cWeth.mint(amount3, {"from": user3})

#     cUsdc.borrowFixedRate(50000e6, TWO_WEEKS, {"from": user3})
#     oracle_mock.setUnderlyingPrice(cWeth, 666e18)

#     # Cant liquidate fixed rate borrow
#     mint_token(usdc, user4, 160000e6)
#     usdc.approve(cUsdc, 160000e6, {"from": user4})
#     with brownie.reverts("Insufficient shortfall"):
#         cUsdc.liquidateBorrow(user3, 25000e6, cWeth, {"from": user4})

#     oracle_mock.setUnderlyingPrice(cWeth, 4000e18)
#     cUsdc.borrow(150000e6, {"from": user3})

#     # Lower price of collateral
#     oracle_mock.setUnderlyingPrice(cWeth, 2000e18)

#     # Cant also liquidated fixed while liquidating variable(close factor = 0.5)
#     with brownie.reverts("Too much repay"):
#         cUsdc.liquidateBorrow(user3, 100000e6, cWeth, {"from": user4})


# def test_cant_liquidate_fixed_using_repay_borrow_case_3(user1, user2, user3, user4, usdc, wbtc,
#                             weth, cUsdc, cWeth, cWbtc, controller, oracle_mock):
#     amount1 = 100000e6
#     amount2 = 500000e6
#     mint_token(usdc, user1, amount1)
#     mint_token(usdc, user2, amount2)

#     # Mint
#     usdc.approve(cUsdc, amount1, {"from": user1})
#     cUsdc.mint(amount1, {"from": user1})

#     usdc.approve(cUsdc, amount2, {"from": user2})
#     cUsdc.mint(amount2, {"from": user2})

#     # Mint collateral
#     amount3 = 100e18
#     mint_token(weth, user3, amount3)
#     controller.enterMarkets([cWeth], {"from": user3})

#     weth.approve(cWeth, amount3, {"from": user3})
#     cWeth.mint(amount3, {"from": user3})

#     cUsdc.borrowFixedRate(300000e6, TWO_WEEKS, {"from": user3})

#     chain.sleep(TWO_WEEKS + cUsdc.restPeriod() + 1)
#     chain.mine(1)

#     # Lower price of collateral
#     oracle_mock.setUnderlyingPrice(cWeth, 2000e18)

#     mint_token(usdc, user4, 150000e6)
#     usdc.approve(cUsdc, 150000e6, {"from": user4})
#     with brownie.reverts("Insufficient shortfall"):
#         cUsdc.liquidateBorrow(user3, 150000e6, cWeth, {"from": user4})


# def test_should_liquidate_one_fixed_rate(user1, user2, user3, user4, usdc, wbtc,
#                             weth, cUsdc, cWeth, cWbtc, controller, oracle_mock):
#     amount1 = 100000e6
#     amount2 = 500000e6
#     mint_token(usdc, user1, amount1)
#     mint_token(usdc, user2, amount2)

#     # Mint
#     usdc.approve(cUsdc, amount1, {"from": user1})
#     cUsdc.mint(amount1, {"from": user1})

#     usdc.approve(cUsdc, amount2, {"from": user2})
#     cUsdc.mint(amount2, {"from": user2})

#     # Mint collateral
#     amount3 = 100e18
#     mint_token(weth, user3, amount3)
#     controller.enterMarkets([cWeth], {"from": user3})

#     weth.approve(cWeth, amount3, {"from": user3})
#     cWeth.mint(amount3, {"from": user3})

#     cUsdc.borrowFixedRate(300000e6, TWO_WEEKS, {"from": user3})
#     # Can't borrow more
#     with brownie.reverts("Insufficient liquidity"):
#         cUsdc.borrowFixedRate(10000e6, TWO_WEEKS, {"from": user3})

#     # User doesn't repay, we can liquidate
#     chain.sleep(TWO_WEEKS + cUsdc.restPeriod() + 1)
#     chain.mine(1)

#     expired_borrows = cUsdc.expiredBorrows(user3)
#     mint_token(usdc, user4, expired_borrows[1][0])

#     c_token_weth_before = cWeth.balanceOf(user3)
#     usdc.approve(cUsdc, expired_borrows[1][0], {"from": user4})
#     cUsdc.liquidateBorrowFixedRate(user3, expired_borrows[0], [cWeth], {"from": user4})

#     assert cUsdc.fixedBorrowsAmount(user3) == 0
#     assert cWeth.balanceOf(user3) < c_token_weth_before
#     assert cWeth.balanceOf(user4) > 0
#     assert cUsdc.totalReserves() > 0

#     print("User3 cWeth bal after: ", cWeth.balanceOf(user3))
#     print("User4 cWeth bal after: ", cWeth.balanceOf(user4))
#     print("cWeth total reserves after: ", cWeth.totalReserves())
#     print("cUsdc total reserves after: ", cUsdc.totalReserves())

#     assert cUsdc.totalReserves() > 0
#     assert cWeth.totalReserves() > 0
#     assert cUsdc.totalBorrowsFixed() == 0
#     assert usdc.balanceOf(user4) == 0

#     # Redeem
#     balance1 = cUsdc.balanceOf(user2)

#     cUsdc.redeem(balance1, {"from": user2})
#     assert cUsdc.balanceOf(user2) == 0
#     assert usdc.balanceOf(user2) > amount2

#     print("Interest collected for user1: ", usdc.balanceOf(user2) - amount2)


# def test_should_liquidate_only_matured_fixed_rate(user1, user2, user3, user4, usdc, wbtc,
#                             weth, cUsdc, cWeth, cWbtc, controller, oracle_mock):
#     amount1 = 100000e6
#     amount2 = 500000e6
#     mint_token(usdc, user1, amount1)
#     mint_token(usdc, user2, amount2)

#     # Mint
#     usdc.approve(cUsdc, amount1, {"from": user1})
#     cUsdc.mint(amount1, {"from": user1})

#     usdc.approve(cUsdc, amount2, {"from": user2})
#     cUsdc.mint(amount2, {"from": user2})

#     # Mint collateral
#     amount3 = 100e18
#     mint_token(weth, user3, amount3)
#     controller.enterMarkets([cWeth], {"from": user3})

#     weth.approve(cWeth, amount3, {"from": user3})
#     cWeth.mint(amount3, {"from": user3})

#     cUsdc.borrowFixedRate(100000e6, TWO_WEEKS, {"from": user3})

#     print("Interest for 2nd borrow: ", 100000e6 * cUsdc.borrowRatePerTime(ONE_MONTH) // 1e18)
#     cUsdc.borrowFixedRate(100000e6, ONE_MONTH, {"from": user3})
#     cUsdc.borrowFixedRate(100000e6, TWO_WEEKS, {"from": user3})

#     assert cUsdc.fixedBorrowsAmount(user3) == 3

#     # Liquidate only matured borrows
#     chain.sleep(TWO_WEEKS + cUsdc.restPeriod() + 1)
#     chain.mine(1)

#     expired_borrows = cUsdc.expiredBorrows(user3)
#     total_repay = 0
#     for i in expired_borrows[1]:
#         mint_token(usdc, user4, i)
#         total_repay += i

#     c_token_weth_before = cWeth.balanceOf(user3)
#     usdc.approve(cUsdc, total_repay, {"from": user4})
#     cUsdc.liquidateBorrowFixedRate(user3, expired_borrows[0], [cWeth, cWeth], {"from": user4})

#     assert cUsdc.fixedBorrowsAmount(user3) == 1
#     assert cUsdc.accountFixedRateBorrows(user3, 0)[3] == ONE_MONTH

#     assert cWeth.balanceOf(user3) < c_token_weth_before
#     assert cWeth.balanceOf(user4) > 0
#     assert cUsdc.totalReserves() > 0

#     print("\nUser3 cWeth bal after 2: ", cWeth.balanceOf(user3))
#     print("User4 cWeth bal after 2: ", cWeth.balanceOf(user4))
#     print("cWeth total reserves after 2: ", cWeth.totalReserves())
#     print("cUsdc total reserves after 2: ", cUsdc.totalReserves())
#     print("cUsdc total borrows 2: ", cUsdc.totalBorrowsFixed())

#     assert cUsdc.totalReserves() > 0
#     assert cWeth.totalReserves() > 0
#     assert cUsdc.totalBorrowsFixed() > 100000e6
#     assert usdc.balanceOf(user4) == 0

#     # Liquidate 3rd borrow
#     chain.sleep(TWO_WEEKS + cUsdc.restPeriod() + 1)
#     chain.mine(1)

#     expired_borrows = cUsdc.expiredBorrows(user3)
#     mint_token(usdc, user4, expired_borrows[1][0])

#     usdc.approve(cUsdc, expired_borrows[1][0], {"from": user4})
#     cUsdc.liquidateBorrowFixedRate(user3, expired_borrows[0], [cWeth], {"from": user4})

#     print("\nUser3 cWeth bal after 2: ", cWeth.balanceOf(user3))
#     print("User4 cWeth bal after 2: ", cWeth.balanceOf(user4))
#     print("cWeth total reserves after 2: ", cWeth.totalReserves())
#     print("cUsdc total reserves after 2: ", cUsdc.totalReserves())
#     print("cUsdc total borrows 2: ", cUsdc.totalBorrowsFixed())

#     # Redeem
#     balance1 = cUsdc.balanceOf(user2)

#     cUsdc.redeem(balance1, {"from": user2})
#     assert cUsdc.balanceOf(user2) == 0
#     assert usdc.balanceOf(user2) > amount2

#     print("\nInterest collected for user1: ", usdc.balanceOf(user2) - amount2)


# def test_cant_liquidate_prematured_borrow(user1, user2, user3, user4, usdc, wbtc,
#                             weth, cUsdc, cWeth, cWbtc, controller, oracle_mock):
#     amount1 = 100000e6
#     amount2 = 500000e6
#     mint_token(usdc, user1, amount1)
#     mint_token(usdc, user2, amount2)

#     # Mint
#     usdc.approve(cUsdc, amount1, {"from": user1})
#     cUsdc.mint(amount1, {"from": user1})

#     usdc.approve(cUsdc, amount2, {"from": user2})
#     cUsdc.mint(amount2, {"from": user2})

#     # Mint collateral
#     amount3 = 100e18
#     mint_token(weth, user3, amount3)
#     controller.enterMarkets([cWeth], {"from": user3})

#     weth.approve(cWeth, amount3, {"from": user3})
#     cWeth.mint(amount3, {"from": user3})

#     cUsdc.borrowFixedRate(100000e6, TWO_WEEKS, {"from": user3})
#     cUsdc.borrowFixedRate(100000e6, ONE_MONTH, {"from": user3})
#     cUsdc.borrowFixedRate(100000e6, TWO_WEEKS, {"from": user3})

#     mint_token(usdc, user4, 320000e6)
#     usdc.approve(cUsdc, 320000e6, {"from": user4})

#     # Cant liquidate before rest period passes
#     chain.sleep(TWO_WEEKS + 1)
#     chain.mine(1)

#     with brownie.reverts("Cannot liquidate fixed rate borrow"):
#         cUsdc.liquidateBorrowFixedRate(user3, [0, 2], [cWeth, cWeth], {"from": user4})

#     # Cant liquidated prematured borrow
#     chain.sleep(cUsdc.restPeriod() + 1)

#     with brownie.reverts("Cannot liquidate fixed rate borrow"):
#         cUsdc.liquidateBorrowFixedRate(user3, [0, 1, 2], [cWeth, cWeth, cWeth], {"from": user4})

#     # Can liquidate matured borrows
#     cUsdc.liquidateBorrowFixedRate(user3, [0, 2], [cWeth, cWeth], {"from": user4})

#     assert cWeth.balanceOf(user4) > 0