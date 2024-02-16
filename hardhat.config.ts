import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox-viem";

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.23",

  },

  networks: {
    "blast-mainnet": {
      url: "coming end of February",
      accounts: [],
      gasPrice: 1000000000,
    },
    "blast-sepolia": {
      url: "https://testnet.blast.io",
      accounts: [],
      gasPrice: 1000000000,
    },
    "blast-local": {
      url: "http://localhost:8545",
      accounts: "remote",
      gasPrice: 1000000000,
    },
  },
  defaultNetwork: "hardhat",
};

export default config;
