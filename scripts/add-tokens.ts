#!/usr/bin/env ts-node

/**
 * Add Supported Tokens to Diamond Contract
 * 
 * This script adds USDC and USDT to the GovernanceFacet's supported tokens list
 * Run: npx hardhat run scripts/add-tokens.ts --network sepolia
 */

const { ethers } = require("hardhat");
import * as fs from "fs";
import * as path from "path";

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
    USDT: "0x0000000000000000000000000000000000000000", // Not deployed on Base Sepolia
  },
};

// GovernanceFacet ABI (minimal - only what we need)
const GOVERNANCE_FACET_ABI = [
  "function addSupportedStakingToken(address token) external",
  "function getSupportedStakingTokens() external view returns (address[] memory)",
  "function isTokenSupported(address token) external view returns (bool)",
];

async function main() {
  console.log("\n═══════════════════════════════════════════════");
  console.log("🔧 Adding Supported Tokens to Diamond Contract");
  console.log("═══════════════════════════════════════════════\n");

  // Get network name
  const networkName = process.env.HARDHAT_NETWORK || "hardhat";
  console.log(`📡 Network: ${networkName}`);

  // Load deployment data
  const deploymentsPath = path.join(__dirname, "..", "deployments", "deployments.json");
  const deployments = JSON.parse(fs.readFileSync(deploymentsPath, "utf8"));

  // Get Diamond address for this network
  let diamondAddress: string;
  let tokens: { USDC: string; USDT: string };

  if (networkName === "sepolia") {
    diamondAddress = deployments.sepolia?.diamond;
    tokens = TOKEN_ADDRESSES.sepolia;
  } else if (networkName === "liskSepolia") {
    diamondAddress = deployments.liskSepolia?.diamond;
    tokens = TOKEN_ADDRESSES.liskSepolia;
  } else if (networkName === "baseSepolia") {
    diamondAddress = deployments.baseSepolia?.diamond;
    tokens = TOKEN_ADDRESSES.baseSepolia;
  } else {
    throw new Error(`Unsupported network: ${networkName}`);
  }

  if (!diamondAddress) {
    throw new Error(`Diamond not deployed on ${networkName}`);
  }

  console.log(`💎 Diamond Address: ${diamondAddress}`);
  console.log(`📍 USDC Address: ${tokens.USDC}`);
  console.log(`📍 USDT Address: ${tokens.USDT}\n`);

  // Get signer
  const [deployer] = await ethers.getSigners();
  console.log(`👤 Deployer: ${deployer.address}`);
  const balance = await deployer.provider.getBalance(deployer.address);
  console.log(`💰 Balance: ${ethers.formatEther(balance)} ETH\n`);

  // Connect to GovernanceFacet
  const governanceFacet = await ethers.getContractAt(
    GOVERNANCE_FACET_ABI,
    diamondAddress,
    deployer
  );

  console.log("═══════════════════════════════════════════════");
  console.log("📋 Checking Current Supported Tokens");
  console.log("═══════════════════════════════════════════════\n");

  try {
    const currentTokens = await governanceFacet.getSupportedStakingTokens();
    console.log(`✅ Current supported tokens count: ${currentTokens.length}`);
    if (currentTokens.length > 0) {
      currentTokens.forEach((token: string, index: number) => {
        console.log(`   ${index + 1}. ${token}`);
      });
    } else {
      console.log("   ⚠️  No tokens currently supported");
    }
  } catch (error) {
    console.log("⚠️  Could not fetch current tokens (function may not exist yet)");
  }

  console.log("\n═══════════════════════════════════════════════");
  console.log("➕ Adding Tokens");
  console.log("═══════════════════════════════════════════════\n");

  // Add USDC
  if (tokens.USDC !== "0x0000000000000000000000000000000000000000") {
    try {
      console.log("📤 Checking USDC support status...");
      const isUsdcSupported = await governanceFacet.isTokenSupported(tokens.USDC);
      
      if (isUsdcSupported) {
        console.log("✅ USDC is already supported!");
      } else {
        console.log("➕ Adding USDC...");
        const tx1 = await governanceFacet.addSupportedStakingToken(tokens.USDC);
        console.log(`   Transaction sent: ${tx1.hash}`);
        console.log("   ⏳ Waiting for confirmation...");
        await tx1.wait();
        console.log("   ✅ USDC added successfully!");
      }
    } catch (error: any) {
      console.error(`   ❌ Failed to add USDC: ${error.message}`);
    }
  }

  console.log();

  // Add USDT
  if (tokens.USDT !== "0x0000000000000000000000000000000000000000") {
    try {
      console.log("📤 Checking USDT support status...");
      const isUsdtSupported = await governanceFacet.isTokenSupported(tokens.USDT);
      
      if (isUsdtSupported) {
        console.log("✅ USDT is already supported!");
      } else {
        console.log("➕ Adding USDT...");
        const tx2 = await governanceFacet.addSupportedStakingToken(tokens.USDT);
        console.log(`   Transaction sent: ${tx2.hash}`);
        console.log("   ⏳ Waiting for confirmation...");
        await tx2.wait();
        console.log("   ✅ USDT added successfully!");
      }
    } catch (error: any) {
      console.error(`   ❌ Failed to add USDT: ${error.message}`);
    }
  }

  console.log("\n═══════════════════════════════════════════════");
  console.log("✅ Token Addition Complete!");
  console.log("═══════════════════════════════════════════════\n");

  // Verify final state
  try {
    const finalTokens = await governanceFacet.getSupportedStakingTokens();
    console.log(`📊 Final supported tokens count: ${finalTokens.length}`);
    finalTokens.forEach((token: string, index: number) => {
      const tokenName = 
        token.toLowerCase() === tokens.USDC.toLowerCase() ? "USDC" :
        token.toLowerCase() === tokens.USDT.toLowerCase() ? "USDT" :
        "Unknown";
      console.log(`   ${index + 1}. ${token} (${tokenName})`);
    });
  } catch (error) {
    console.log("⚠️  Could not verify final state");
  }

  console.log("\n✅ Done! You can now stake tokens on this network.\n");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("\n❌ Error:", error);
    process.exit(1);
  });
