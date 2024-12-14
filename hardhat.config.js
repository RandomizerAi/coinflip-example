require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: "0.8.19",
};

module.exports = {
  solidity: {
    version: "0.8.19",
    settings: {
      optimizer: {
        enabled: true,
        runs: 9999,
      },
    },
  },
  networks: {
    hardhat: {
      chainId: 1337,
    },
    arbGoerli: {
      url: "https://goerli-rollup.arbitrum.io/rpc",
      accounts: [process.env.PRIVATE_KEY],
    },
    arbitrumMainnet: {
      url: process.env.PROVIDER_ARBITRUM || "https://arb1.arbitrum.io/rpc",
      accounts: [process.env.PRIVATE_KEY],
    },
    sanko: {
      url: process.env.SANKO_MAINNET_RPC,
      accounts: [process.env.PRIVATE_KEY],
      chainId: 1996,
      contracts: {
        randomizer: process.env.SANKO_MAINNET_RANDOMIZER,
      },
    },
  },
};
