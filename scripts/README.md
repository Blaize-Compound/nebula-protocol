## Before interacting with the protcol, make sure you have installed brownie framework
# Fill .env file where:
# `DEPLOYER_PRIVATE_KEY` is a key from .env.example
# `METIS_TESTNET_RPC` is RPC for Metis testnet
# `USER_ADDRESS` is address of user who is going to interact with protocol
# `USER_PRIVATE_KEY` is a private key of user who is going to interact with protocol
#
#
# Setup network with following commands:
## Run command `npm run "add:metis-testnet`
# Run `export METIS_TESTNET_RPC=https://stardust.metis.io/?owner=588`
#
#
# Before interacting with USDC Market, you need test usdc. Run command `npm run mint-test-usdc`
#
#
# Adding collaterals:
# In order to deposit Metis or Usdc and start earning interest run command `npm run deposit-usdc` or `npm run deposit-metis`
# !!! NOTE !!! You need to deposit collaterals in order to borrow assets
# Redeem assets:
# In order to redeem your deposits plus interest run command `npm run redeem-usdc` or `npm run redeem-metis`
#
#
# Borrowing with variable rate:
# In order to borrow assets run command `npm run borrow-usdc` or `npm run borrow-metis`
# In order to repay borrows run command `npm run repay-usdc` or `npm run repay-metis`
#
#
# Borrowing with fixed rate:
# In order to borrow assets with variable rate run command `npm run borrow-fixed-usdc` or `npm run borrow-fixed-metis`
# In order to repay fixed borrow run command `npm run repay-fixed-usdc` or `repay-fixed-metis`
