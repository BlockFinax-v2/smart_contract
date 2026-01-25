#!/usr/bin/env ts-node

const { ethers } = require("hardhat");
const fs = require("fs");
const path = require("path");

const DEPLOYMENTS_FILE = path.join(__dirname, "..", "deployments", "deployments.json");

async function main() {
  const network = await ethers.provider.getNetwork();
  const networkName = network.name === "unknown" ? "localhost" : network.name;
  
  console.log(`\n🔍 Checking stake data on ${networkName}...`);
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

  // Get Diamond contract with LiquidityPoolFacet interface
  const LiquidityPoolFacet = await ethers.getContractFactory("LiquidityPoolFacet");
  const diamond = LiquidityPoolFacet.attach(diamondAddress);

  console.log("📊 Pool Statistics:");
  const poolStats = await diamond.getPoolStats();
  console.log(`   Total Staked: ${poolStats.totalStaked.toString()}`);
  console.log(`   Total LPs: ${poolStats.totalLiquidityProviders.toString()}`);
  console.log(`   Total Rewards: ${poolStats.totalRewardsDistributed.toString()}\n`);

  // Get all stakers
  const stakers = await diamond.getStakers();
  console.log(`📋 Total Stakers: ${stakers.length}\n`);

  if (stakers.length > 0) {
    console.log("🔍 Checking first 3 stakers for usdEquivalent values...\n");
    
    for (let i = 0; i < Math.min(3, stakers.length); i++) {
      const stakerAddress = stakers[i];
      console.log(`Staker ${i + 1}: ${stakerAddress}`);
      
      try {
        const stakes = await diamond.getAllStakesForUser(stakerAddress);
        
        for (const stake of stakes) {
          console.log(`  Token: ${stake.tokenAddress}`);
          console.log(`  Amount: ${stake.amount.toString()}`);
          console.log(`  USD Equivalent: ${stake.usdEquivalent.toString()}`);
          
          // Check if it looks like 18 decimals (value > 1e12)
          const usdEq = BigInt(stake.usdEquivalent.toString());
          if (usdEq > BigInt(1e12)) {
            console.log(`  ⚠️  WARNING: This looks like 18-decimal precision (needs migration)`);
          } else if (usdEq > 0) {
            console.log(`  ✅ Looks like 6-decimal precision (already migrated or new stake)`);
          }
          console.log();
        }
      } catch (error: any) {
        console.log(`  ❌ Error fetching stakes: ${error.message}\n`);
      }
    }
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
