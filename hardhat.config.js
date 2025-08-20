require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

module.exports = {
  solidity: "0.8.20",
  networks: {
    zetatestnet: {
      url: process.env.ZETA_TESTNET_RPC,
      accounts: [process.env.PRIVATE_KEY].filter(Boolean)
    },
    zetamainnet: {
      url: process.env.ZETA_MAINNET_RPC,
      accounts: [process.env.PRIVATE_KEY].filter(Boolean)
    }
  }
};
