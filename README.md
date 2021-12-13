# nebula-protocol

## Dependencies

For development purposes, you will need: 
- `Node.js` – v15.11.0
- `npm` – 7.14.0
- `python3` - version 3.8 or greater, python3-dev
- `brownie` - tested with version v1.14.6
- `ganache-cli` - tested with version 6.12.2

## Installation

To get started, first create and initialize a Python virtual environment. 
Run  the command:
```
npm run install
```
## Configuration

The project folder needs to be writable to perform logging.

#### `truffle-config.js`

The file contains configuration related to connection to the blockchain. For more information – read <a href="https://www.trufflesuite.com/docs/truffle/reference/configuration"  target="_blank">the Truffle docs</a>.
- `Networks`. Each of the networks subentry corresponds to the Truffle *--network* parameter.
- `Plugins`. The plugins subentry corresponds to the plugins to run using Truffle. Here *solidity-coverage* package is used as a plugin.
- `Compilers`. This section specifies versions of the compilers, and here is used to set the version of *solc* Solidity compiler to *0.8.10*.

#### `brownie-config.yaml`
The file contains:
- `Networks`. 
- `Dependecies`.
- `compiler`. This sections specifies versions of solidity and vyper compilers. Set *solc* Solidity compiler to *0.8.10*

#### `.env`
**!!! Needed to be created manually!!!**

For the deployment process to be successfully performed, the `.env` file with filled-in parameters should be present at the root of the project. In the same place, you should find a file `.env.example`. It contains all of the parameters that must be present in the `.env` file but without actual values (only parameter names). For now, these are the following:
- `GANACHE_PORT`. The port on which Ganache CLI will be running. If you did not change anything – use the default port number (which is `8545`)
- `ROPSTEN_PRIVATE_KEY`, `RINKEBY_PRIVATE_KEY`, `KOVAN_PRIVATE_KEY` and `MAINNET_PRIVATE_KEY`. Private keys for the networks. The contracts are deployed from an account (obtained from the private key that corresponds to the selected network) that should have **enough funds** to be able to deploy the contracts. You can set only those private keys that are planned to be used.
- `WEB3_INFURA_PROJECT_ID`. The project does not use an own ethereum node thus an external provider Infura is used. To obtain the key you shall visit their <a href="https://infura.io/"  target="_blank">website</a>.

## Running scripts

## *Development*

### Linters

`$ npm run dev:lint` to run Solidity and JavaScript linters and check the code for stylistic bugs.

### Tests coverage

`$ npm run dev:coverage` to examine how well developed tests cover the functionality of smart-contracts. The results can also be viewed in a web browser by opening a `coverage/` folder created by the script.

### Ganache test network

Use `$ npm run dev:ganache` to start a local Ethereum network. Here it is used for testing purposes but is not limited to this use case.

### Testing

You can perform tests with `$ npm test` to run all tests from the `tests/` directory.

## *Production*

### Build

Use `$ npm run compile` to compile the smart contracts code to use it in the production.
Use `$ npm run generate-abi` to get the artifacts over the compiled contracts.
Use `$ npm run dev:docgen` to get the up-to-date documentation.

### Deploy
