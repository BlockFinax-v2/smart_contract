import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  const balance = await ethers.provider.getBalance(deployer.address);
  const network = await ethers.provider.getNetwork();
  
  console.log("\n╔════════════════════════════════════════════════════════════╗");
  console.log("║              Wallet Balance Check                         ║");
  console.log("╚════════════════════════════════════════════════════════════╝\n");
  
  console.log("📡 Network:", network.name);
  console.log("🔗 Chain ID:", network.chainId);
  console.log("👤 Deployer Address:", deployer.address);
  console.log("💰 Balance:", ethers.formatEther(balance), "ETH");
  
  if (balance === 0n) {
    console.log("\n⚠️  WARNING: You have 0 ETH!");
    console.log("🚰 Get Base Sepolia ETH from:");
    console.log("   • https://www.alchemy.com/faucets/base-sepolia");
    console.log("   • https://faucet.quicknode.com/base/sepolia");
    console.log("   • Bridge: https://bridge.base.org");
  } else {
    console.log("\n✅ You have sufficient balance to deploy!");
    const estimatedGas = ethers.parseEther("0.02"); // Rough estimate
    if (balance >= estimatedGas) {
      console.log("✅ Estimated deployment cost: ~0.01-0.02 ETH");
      console.log("✅ You're ready to deploy!");
    } else {
      console.log("⚠️  You may need more ETH. Recommended: at least 0.02 ETH");
    }
  }
  
  console.log("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
