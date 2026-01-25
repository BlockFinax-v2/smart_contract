#!/usr/bin/env ts-node

const { ethers } = require("hardhat");
const fs = require("fs");
const path = require("path");

const DEPLOYMENTS_FILE = path.join(__dirname, "..", "deployments", "deployments.json");

async function main() {
  const network = await ethers.provider.getNetwork();
  const networkName = network.name === "unknown" ? "localhost" : network.name;
  
  console.log(`\n🔧 Recalculating stablecoin USD values on ${networkName}...`);
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

  console.log("📊 State before recalculation:");
  
  try {
    // Get total staked before
    const poolStats = await diamond.getPoolStats();
    console.log(`   Total Staked: ${poolStats.totalStaked.toString()}`);
    console.log(`   Total Staked (USD): ${ethers.formatUnits(poolStats.totalStaked, 6)} USD`);
    console.log(`   Total LPs: ${poolStats.totalLiquidityProviders.toString()}\n`);

    // Run recalculation
    console.log("🚀 Executing recalculateStablecoinUsdValues()...");
    const tx = await diamond.recalculateStablecoinUsdValues();
    console.log(`   Transaction sent: ${tx.hash}`);
    
    const receipt = await tx.wait();
    console.log(`   ✅ Recalculation successful! Gas used: ${receipt.gasUsed.toString()}\n`);

    // Get total staked after
    const poolStatsAfter = await diamond.getPoolStats();
    console.log("📊 State after recalculation:");
    console.log(`   Total Staked: ${poolStatsAfter.totalStaked.toString()}`);
    console.log(`   Total Staked (USD): ${ethers.formatUnits(poolStatsAfter.totalStaked, 6)} USD`);
    console.log(`   Total LPs: ${poolStatsAfter.totalLiquidityProviders.toString()}\n`);
    
    // Show change
    const before = BigInt(poolStats.totalStaked.toString());
    const after = BigInt(poolStatsAfter.totalStaked.toString());
    const change = after - before;
    console.log(`   Change: ${change > 0 ? '+' : ''}${change.toString()} (${ethers.formatUnits(change, 6)} USD)`);

    console.log("\n✅ Recalculation completed successfully!");
    console.log("   All stablecoin stakes now have USD equivalent = token amount.\n");

  } catch (error: any) {
    console.error("❌ Recalculation failed:", error.message);
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
