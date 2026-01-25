#!/usr/bin/env ts-node

const { ethers } = require("hardhat");
const fs = require("fs");
const path = require("path");

const DEPLOYMENTS_FILE = path.join(__dirname, "..", "deployments", "deployments.json");

// Your address from the screenshot
const USER_ADDRESS = "0xf070F568c125b2740391136662Fc600A2A29D2A6";

async function main() {
  const network = await ethers.provider.getNetwork();
  const networkName = network.name === "unknown" ? "localhost" : network.name;
  
  console.log(`\n🔍 Detailed stake analysis for ${USER_ADDRESS}`);
  console.log(`   Network: ${networkName} (Chain ID: ${network.chainId})\n`);

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

  // Get pool stats first
  console.log("📊 Pool Statistics:");
  const poolStats = await diamond.getPoolStats();
  console.log(`   Total Staked (USD): ${poolStats.totalStaked.toString()}`);
  console.log(`   In 6 decimals: ${ethers.formatUnits(poolStats.totalStaked, 6)} USD`);
  console.log(`   Total LPs: ${poolStats.totalLiquidityProviders.toString()}\n`);

  // Get all stakes for user
  console.log("💰 All Stakes for User:");
  const stakes = await diamond.getAllStakesForUser(USER_ADDRESS);
  
  console.log(`   Total USD Value: ${stakes.totalUsdValue.toString()}`);
  console.log(`   In 6 decimals: ${ethers.formatUnits(stakes.totalUsdValue, 6)} USD\n`);

  console.log("   Individual Token Stakes:");
  for (let i = 0; i < stakes.tokens.length; i++) {
    const amount = stakes.amounts[i];
    const usdEq = stakes.usdEquivalents[i];
    
    if (amount.toString() !== "0" || usdEq.toString() !== "0") {
      console.log(`\n   Token ${i + 1}: ${stakes.tokens[i]}`);
      console.log(`   ├─ Amount: ${amount.toString()}`);
      console.log(`   ├─ Amount (formatted): ${ethers.formatUnits(amount, 6)}`);
      console.log(`   ├─ USD Equivalent: ${usdEq.toString()}`);
      console.log(`   ├─ USD Equivalent (formatted): ${ethers.formatUnits(usdEq, 6)} USD`);
      console.log(`   ├─ Is Financier: ${stakes.isFinancierFlags[i]}`);
      console.log(`   ├─ Deadline: ${stakes.deadlines[i].toString()}`);
      console.log(`   └─ Pending Rewards: ${stakes.pendingRewards[i].toString()}`);
      
      // Analysis
      if (amount > 0) {
        const ratio = Number(usdEq) / Number(amount);
        console.log(`\n   📊 Analysis:`);
        console.log(`   ├─ USD/Amount ratio: ${ratio.toFixed(6)}`);
        if (ratio < 0.5 || ratio > 2) {
          console.log(`   └─ ⚠️  WARNING: Ratio seems off! Expected ~1.0 for stablecoins`);
        } else {
          console.log(`   └─ ✅ Ratio looks correct for stablecoins`);
        }
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
