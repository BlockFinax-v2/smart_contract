#!/usr/bin/env ts-node

const { ethers } = require("hardhat");
import * as fs from "fs";
import * as path from "path";

// Diamond addresses
const DIAMOND_ADDRESSES: Record<string, string> = {
  sepolia: "0xA4d19a7b133d2A9fAce5b1ad407cA7b9D4Ee9284",
  liskSepolia: "0xE133CD2eE4d835AC202942Baff2B1D6d47862d34",
  baseSepolia: "0xb899A968e785dD721dbc40e71e2FAEd7B2d84711",
};

// Token addresses per network
const TOKEN_ADDRESSES: Record<string, { USDC: string; USDT: string }> = {
  sepolia: {
    USDC: "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238",
    USDT: "0x523C8591Fbe215B5aF0bEad65e65dF783A37BCBC",
  },
  liskSepolia: {
    USDC: "0x17b3531549F842552911CB287CCf7a5F328ff7d1",
    USDT: "0xa3f3aA5B62237961AF222B211477e572149EBFAe",
  },
  baseSepolia: {
    USDC: "0x036CbD53842c5426634e7929541eC2318f3dCF7e",
    USDT: "0x0000000000000000000000000000000000000000", // Not deployed
  },
};

async function main() {
  const networkName = process.env.HARDHAT_NETWORK || "hardhat";
  console.log(`\n🔍 Checking Diamond Token Configuration on ${networkName}\n`);

  const diamondAddress = DIAMOND_ADDRESSES[networkName];
  if (!diamondAddress) {
    console.error(`❌ No Diamond address found for network: ${networkName}`);
    process.exit(1);
  }

  console.log(`Diamond Address: ${diamondAddress}\n`);

  // Get governance contract
  const governance = await ethers.getContractAt("GovernanceFacet", diamondAddress);

  // Check current supported tokens
  console.log("📋 Current Supported Tokens:");
  try {
    const supportedTokens = await governance.getSupportedStakingTokens();
    if (supportedTokens.length === 0) {
      console.log("  ⚠️  No tokens configured!");
    } else {
      for (const token of supportedTokens) {
        console.log(`  ✓ ${token}`);
        
        // Check if it's USDC or USDT
        const tokens = TOKEN_ADDRESSES[networkName];
        if (tokens) {
          if (token.toLowerCase() === tokens.USDC.toLowerCase()) {
            console.log(`    → USDC`);
          } else if (token.toLowerCase() === tokens.USDT.toLowerCase()) {
            console.log(`    → USDT`);
          }
        }
        
        // Get total staked for this token
        try {
          const totalStaked = await governance.getTotalStakedForToken(token);
          console.log(`    Total Staked: ${ethers.utils.formatUnits(totalStaked, 6)}`);
        } catch (e) {
          console.log(`    Total Staked: Unable to fetch`);
        }
      }
    }
  } catch (error: any) {
    console.log(`  ❌ Error: ${error.message}`);
  }

  // Check getTotalStakedUSD
  console.log("\n💰 Total Staked USD (from getTotalStakedUSD):");
  try {
    const totalUSD = await governance.getTotalStakedUSD();
    console.log(`  ${ethers.utils.formatEther(totalUSD)} USD`);
  } catch (error: any) {
    console.log(`  ❌ Error: ${error.message}`);
  }

  // Check what tokens should be configured
  console.log("\n📝 Expected Token Configuration:");
  const tokens = TOKEN_ADDRESSES[networkName];
  if (tokens) {
    console.log(`  USDC: ${tokens.USDC}`);
    console.log(`  USDT: ${tokens.USDT}`);
    
    // Check if each token is supported
    const usdcSupported = await governance.isTokenSupported(tokens.USDC);
    const usdtSupported = tokens.USDT !== "0x0000000000000000000000000000000000000000" 
      ? await governance.isTokenSupported(tokens.USDT) 
      : false;
    
    console.log(`\n✓ USDC Supported: ${usdcSupported ? '✅ Yes' : '❌ No'}`);
    if (tokens.USDT !== "0x0000000000000000000000000000000000000000") {
      console.log(`✓ USDT Supported: ${usdtSupported ? '✅ Yes' : '❌ No'}`);
    }
    
    // Show what needs to be done
    console.log("\n🔧 Action Required:");
    if (!usdcSupported) {
      console.log(`  → Add USDC: npx hardhat run scripts/add-tokens.ts --network ${networkName}`);
    }
    if (tokens.USDT !== "0x0000000000000000000000000000000000000000" && !usdtSupported) {
      console.log(`  → Add USDT: npx hardhat run scripts/add-tokens.ts --network ${networkName}`);
    }
    if (usdcSupported && (tokens.USDT === "0x0000000000000000000000000000000000000000" || usdtSupported)) {
      console.log(`  ✅ All tokens are configured correctly!`);
    }
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
