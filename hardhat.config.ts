import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import dotenv from "dotenv";
dotenv.config();

const BASE_SEPOLIA_RPC = process.env.BASE_SEPOLIA_RPC || "https://sepolia.base.org";
const BASE_RPC = process.env.BASE_RPC || "https://mainnet.base.org";
const LISK_SEPOLIA_RPC = process.env.LISK_SEPOLIA_RPC || "https://rpc.sepolia-api.lisk.com";
const LISK_RPC = process.env.LISK_RPC || "https://rpc.api.lisk.com";
const PRIVATE_KEY = process.env.PRIVATE_KEY;
const BASESCAN_API_KEY = process.env.BASESCAN_API_KEY || "";
const LISK_EXPLORER_KEY = process.env.LISK_EXPLORER_KEY || "";

// Validate private key
if (!PRIVATE_KEY) {
  throw new Error("PRIVATE_KEY is not defined in .env file");
}

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.28",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      },
      viaIR: true,
      evmVersion: "cancun" // Latest EVM version supported by Base
    }
  },
  networks: {
    hardhat: {
      chainId: 1337
    },
    baseSepolia: {
      url: BASE_SEPOLIA_RPC,
      accounts: [PRIVATE_KEY.startsWith("0x") ? PRIVATE_KEY : `0x${PRIVATE_KEY}`],
      chainId: 84532,
      gasPrice: "auto",
      timeout: 60000,
      httpHeaders: {},
    },
    base: {
      url: BASE_RPC,
      accounts: [PRIVATE_KEY.startsWith("0x") ? PRIVATE_KEY : `0x${PRIVATE_KEY}`],
      chainId: 8453,
      gasPrice: "auto"
    },
    liskSepolia: {
      url: LISK_SEPOLIA_RPC,
      accounts: [PRIVATE_KEY.startsWith("0x") ? PRIVATE_KEY : `0x${PRIVATE_KEY}`],
      chainId: 4202,
      gasPrice: "auto",
      timeout: 60000,
    },
    lisk: {
      url: LISK_RPC,
      accounts: [PRIVATE_KEY.startsWith("0x") ? PRIVATE_KEY : `0x${PRIVATE_KEY}`],
      chainId: 1135,
      gasPrice: "auto"
    }
  },
  etherscan: {
    apiKey: {
      baseSepolia: BASESCAN_API_KEY,
      base: BASESCAN_API_KEY,
      liskSepolia: LISK_EXPLORER_KEY,
      lisk: LISK_EXPLORER_KEY
    },
    customChains: [
      {
        network: "baseSepolia",
        chainId: 84532,
        urls: {
          apiURL: "https://api-sepolia.basescan.org/api",
          browserURL: "https://sepolia.basescan.org"
        }
      },
      {
        network: "base",
        chainId: 8453,
        urls: {
          apiURL: "https://api.basescan.org/api",
          browserURL: "https://basescan.org"
        }
      },
      {
        network: "liskSepolia",
        chainId: 4202,
        urls: {
          apiURL: "https://sepolia-blockscout.lisk.com/api",
          browserURL: "https://sepolia-blockscout.lisk.com"
        }
      },
      {
        network: "lisk",
        chainId: 1135,
        urls: {
          apiURL: "https://blockscout.lisk.com/api",
          browserURL: "https://blockscout.lisk.com"
        }
      }
    ]
  },
  gasReporter: {
    enabled: process.env.REPORT_GAS === "true",
    currency: "USD"
  }
};

export default config;
