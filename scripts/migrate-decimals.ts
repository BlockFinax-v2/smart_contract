#!/usr/bin/env ts-node

const { ethers } = require("hardhat");
const fs = require("fs");
const path = require("path");

const DEPLOYMENTS_FILE = path.join(__dirname, "..", "deployments", "deployments.json");

async function main() {
  const network = await ethers.provider.getNetwork();
  const networkName = network.name === "unknown" ? "localhost" : network.name;
  
  console.log(`\n🔧 Running decimal precision migration on ${networkName}...`);
  console.log(`   Chain ID: ${network.chainId}`);

  // Load deployment info
  const deployments = JSON.parse(fs.readFileSync(DEPLOYMENTS_FILE, "utf8"));
  const deployment = deployments[networkName];

  if (!deployment) {
    console.error(`❌ No deployment found for network: ${networkName}`);
    process.exit(1);
  }

  const diamondAddress = deployment.diamond;
  console.log(`   Diamond: ${diamondAddress}\n`);

  // Get signer
  const [signer] = await ethers.getSigners();
  console.log(`   Signer: ${signer.address}`);
  console.log(`   Balance: ${ethers.formatEther(await signer.provider.getBalance(signer.address))} ETH\n`);

  // Get Diamond contract with LiquidityPoolFacet interface
  const LiquidityPoolFacet = await ethers.getContractFactory("LiquidityPoolFacet");
  const diamond = LiquidityPoolFacet.attach(diamondAddress);

  console.log("📊 Checking current state before migration...");
  
  try {
    // Get total staked before migration
    const poolStats = await diamond.getPoolStats();
    console.log(`   Total Staked (before): ${poolStats.totalStaked.toString()}`);
    console.log(`   Total LPs: ${poolStats.totalLiquidityProviders.toString()}\n`);

    // Run migration
    console.log("🚀 Executing migrateDecimalPrecision()...");
    const tx = await diamond.migrateDecimalPrecision();
    console.log(`   Transaction sent: ${tx.hash}`);
    
    const receipt = await tx.wait();
    console.log(`   ✅ Migration successful! Gas used: ${receipt.gasUsed.toString()}\n`);

    // Get total staked after migration
    const poolStatsAfter = await diamond.getPoolStats();
    console.log("📊 State after migration:");
    console.log(`   Total Staked (after): ${poolStatsAfter.totalStaked.toString()}`);
    console.log(`   Total LPs: ${poolStatsAfter.totalLiquidityProviders.toString()}`);
    
    // Calculate reduction
    const before = BigInt(poolStats.totalStaked.toString());
    const after = BigInt(poolStatsAfter.totalStaked.toString());
    const reduction = before / after;
    console.log(`   Reduction factor: ~${reduction.toString()}x (should be ~1e12)\n`);

    console.log("✅ Migration completed successfully!");
    console.log("   All USD equivalent values have been converted from 18 to 6 decimals.\n");

  } catch (error: any) {
    console.error("❌ Migration failed:", error.message);
    if (error.reason) {
      console.error("   Reason:", error.reason);
    }
    process.exit(1);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
