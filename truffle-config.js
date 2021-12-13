require("dotenv").config();

module.exports = {
    /**
     * Networks define how you connect to your ethereum client and let you set the
     * defaults web3 uses to send transactions. If you don't specify one truffle
     * will spin up a development blockchain for you on port 9545 when you
     * run `develop` or `test`. You can ask a truffle command to use a specific
     * network from the command line, e.g
     *
     * $ truffle test --network <network-name>
     */

    contracts_directory: "./contracts/",
    networks: {
        // Useful for testing. The `development` name is special - truffle uses it by default
        // if it's defined here and no other network is specified at the command line.
        // You should run a client (like ganache-cli, geth or parity) in a separate terminal
        // tab if you use this network and you must also set the `host`, `port` and `network_id`
        // options below to some value.
        //
        development: {
            host: "127.0.0.1", // Localhost (default: none)
            port: process.env.GANACHE_PORT || 8545, // Standard Ethereum port (default: 7545)
            network_id: "*", // Any network (default: none)
            accounts: 20,
            gas: 0x6691b7,
        },
    },

    plugins: ["truffle-contract-size"],

    // Set default mocha options here, use special reporters etc.
    mocha: {
        timeout: 250000,
    },

    // Configure your compilers
    compilers: {
        solc: {
            version: "0.8.10", // Fetch exact version from solc-bin (default: truffle's version)
            // docker: true,        // Use "0.5.1" you've installed locally with docker (default: false)
            settings: {
                // See the solidity docs for advice about optimization and evmVersion
                optimizer: {
                    enabled: true,
                    runs: 200,
                },
                //  evmVersion: "byzantium"
            },
        },
    },
};
