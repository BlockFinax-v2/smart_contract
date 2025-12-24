/**
 * Add supported staking tokens to Diamond contract
 * Usage: npx hardhat run scripts/add-staking-tokens.ts --network liskSepolia
 */

import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("\n🚀 Adding staking tokens with account:", deployer.address);

  // Diamond contract address on Lisk Sepolia
  const DIAMOND_ADDRESS = "0xE133CD2eE4d835AC202942Baff2B1D6d47862d34";

  // Token addresses on Lisk Sepolia (lowercase to avoid checksum issues)
  const TOKENS = {
    USDC: "0x0e82fddad51cc3ac12b69761c45bbcb9a2bf3c83",
    USDT: "0x7e2db2968f80e5cacfb0bd93c724d0447a6b6d8c",
    DAI: "0x4f96fe3b7a6cf9725f59d353f723c1bdb64ca6aa",
  };

  console.log("📍 Diamond Contract:", DIAMOND_ADDRESS);
  console.log("\n📝 Tokens to add:");
  console.log("   USDC:", TOKENS.USDC);
  console.log("   USDT:", TOKENS.USDT);
  console.log("   DAI:", TOKENS.DAI);

  // ABI for adding tokens
  const abi = [
    "function addSupportedStakingToken(address tokenAddress) external",
    "function isTokenSupported(address tokenAddress) external view returns (bool)",
    "function getSupportedStakingTokens() external view returns (address[])",
  ];

  const diamond = new ethers.Contract(DIAMOND_ADDRESS, abi, deployer);

  try {
    // Check current supported tokens
    console.log("\n🔍 Checking current supported tokens...");
    const currentTokens = await diamond.getSupportedStakingTokens();
    console.log(`   Currently ${currentTokens.length} token(s) supported`);

    // Add each token
    for (const [symbol, address] of Object.entries(TOKENS)) {
      console.log(`\n📌 Processing ${symbol} (${address})...`);
      
      // Check if already supported
      const isSupported = await diamond.isTokenSupported(address);
      
      if (isSupported) {
        console.log(`   ✅ ${symbol} is already supported`);
      } else {
        console.log(`   ➕ Adding ${symbol}...`);
        const tx = await diamond.addSupportedStakingToken(address);
        console.log(`   📤 Transaction sent: ${tx.hash}`);
        
        const receipt = await tx.wait();
        console.log(`   ✅ ${symbol} added successfully! (Block: ${receipt.blockNumber})`);
      }
    }

    // Verify all tokens were added
    console.log("\n\n🎉 Verification:");
    const finalTokens = await diamond.getSupportedStakingTokens();
    console.log(`   Total supported tokens: ${finalTokens.length}`);
    console.log("\n   Supported token addresses:");
    finalTokens.forEach((addr, i) => {
      const symbol = Object.entries(TOKENS).find(([_, a]) => a.toLowerCase() === addr.toLowerCase())?.[0] || "Unknown";
      console.log(`   ${i + 1}. ${symbol}: ${addr}`);
    });

    console.log("\n✅ All tokens configured successfully!");
    console.log("\n💡 Next steps:");
    console.log("   1. Your mobile app should now show multi-token staking options");
    console.log("   2. Users can stake USDC, USDT, or DAI");
    console.log("   3. All stakes are converted to USD for voting power");

  } catch (error: any) {
    console.error("\n❌ Error adding tokens:");
    if (error.message.includes("Function does not exist")) {
      console.error("   The contract doesn't have addSupportedStakingToken() function.");
      console.error("   Make sure MultiTokenStakingFacet is deployed and added to Diamond.");
    } else if (error.message.includes("Only admin")) {
      console.error("   You don't have admin permissions.");
      console.error("   Make sure you're using the contract owner account.");
    } else {
      console.error("   ", error.message);
    }
    throw error;
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
