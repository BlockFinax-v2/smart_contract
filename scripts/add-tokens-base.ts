/**
 * Add supported staking tokens to Base Sepolia Diamond
 */

import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("\n🚀 Adding staking tokens on Base Sepolia");
  console.log("   Deployer:", deployer.address);

  const DIAMOND_ADDRESS = "0xb899A968e785dD721dbc40e71e2FAEd7B2d84711";

  // Token addresses from stablecoinPrices.ts
  const TOKENS = {
    USDC: "0x036cbd53842c5426634e7929541ec2318f3dcf7e",
    USDT: "0xf3e622265cad2c68330a46346d6e2c4bde19a251",
    DAI: "0x50c5725949a6f0c72e6c4a641f24049a917db0cb",
  };

  console.log("   Diamond:", DIAMOND_ADDRESS);
  console.log("\n📝 Tokens to add:");
  for (const [symbol, address] of Object.entries(TOKENS)) {
    console.log(`   ${symbol}: ${address}`);
  }

  const governance = await ethers.getContractAt("GovernanceFacet", DIAMOND_ADDRESS);

  // Check current tokens
  console.log(`\n🔍 Current state:`);
  const currentTokens = await governance.getSupportedStakingTokens();
  console.log(`   Supported tokens: ${currentTokens.length}`);

  // Add each token
  for (const [symbol, address] of Object.entries(TOKENS)) {
    console.log(`\n📌 Processing ${symbol}...`);
    
    const isSupported = await governance.isTokenSupported(address);
    
    if (!isSupported) {
      console.log(`   Adding ${symbol}...`);
      const tx = await governance.addSupportedStakingToken(address);
      const receipt = await tx.wait();
      console.log(`   ✅ ${symbol} added (Block: ${receipt?.blockNumber})`);
    } else {
      console.log(`   ℹ️  ${symbol} already supported`);
    }
  }

  // Verify
  console.log(`\n🎉 Final Verification:`);
  const finalTokens = await governance.getSupportedStakingTokens();
  console.log(`   Total tokens: ${finalTokens.length}\n`);
  
  for (let i = 0; i < finalTokens.length; i++) {
    const addr = finalTokens[i];
    const symbol = Object.entries(TOKENS).find(([_, a]) => 
      a.toLowerCase() === addr.toLowerCase()
    )?.[0] || "Unknown";
    console.log(`   ${i + 1}. ${symbol}: ${addr}`);
  }

  console.log(`\n✅ Base Sepolia is ready for multi-token staking!`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
