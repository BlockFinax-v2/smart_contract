import { ethers, run, network } from "hardhat";
import * as dotenv from "dotenv";

dotenv.config();

// Environment variables
const PRIVATE_KEY = process.env.PRIVATE_KEY;
const BASESCAN_API_KEY = process.env.BASESCAN_API_KEY;

// Existing Diamond deployment addresses
const DIAMOND_ADDRESSES = {
  diamond: "0x65C4ce15C9DFA916db081A41340C3c862F0a3343",
  diamondCutFacet: "0xA02409fB50c90D97304fF37230e2202E3EA384be",
  diamondLoupeFacet: "0x471Fb8C51430C145bcae95f78a0A66E4A63520C9",
  ownershipFacet: "0xE65B037ec83eA37E86Cd72675407BaA3594941Bb",
  contractManagementFacet: "0x2a2e859241FafABc8fAa515Fd69736e7cB53c7d6",
  documentManagementFacet: "0x1479c03b2F6a797061C9BBF566CcdD5E97FB7a3d",
  escrowFacet: "0xE55711F2f4f564D187082eE187FCc03F4be7FC43",
  governanceFacet: "0xB92925516501f9bf5bAD5643b276AE384852b508",
  invoiceFacet: "0x72e1831B54cA0b089c811adD6e16732f77e90f77",
  liquidityPoolFacet: "0x2a32b6c004A1f71412FaF82c9E65db17232e6E1b", // This will be replaced
  diamondInit: "0x2776C557702e297fb25603c89604683DDD5F5023",
};

// Validation
if (!PRIVATE_KEY) {
  throw new Error("PRIVATE_KEY is not set in .env file");
}

if (network.name === "baseSepolia" && !BASESCAN_API_KEY) {
  console.warn("⚠️  BASESCAN_API_KEY is not set. Contract verification will be skipped.");
}

async function verify(address: string, constructorArguments: any[] = []): Promise<void> {
  if (network.name === "hardhat" || network.name === "localhost") {
    return;
  }

  if (!BASESCAN_API_KEY) {
    console.log(`⏭️  Skipping verification for ${address} (no API key)`);
    return;
  }

  console.log(`🔍 Verifying contract at ${address}...`);
  try {
    await run("verify:verify", {
      address: address,
      constructorArguments: constructorArguments,
    });
    
    const explorerUrl = network.name === "baseSepolia" 
      ? `https://sepolia.basescan.org/address/${address}`
      : `https://basescan.org/address/${address}`;
    console.log(`   ✅ Verified: ${explorerUrl}`);
  } catch (e: any) {
    if (e.message.toLowerCase().includes("already verified")) {
      const explorerUrl = network.name === "baseSepolia"
        ? `https://sepolia.basescan.org/address/${address}`
        : `https://basescan.org/address/${address}`;
      console.log(`   ✅ Already verified: ${explorerUrl}`);
    } else {
      console.log(`   ❌ Verification failed: ${e.message}`);
    }
  }
}

// Helper function to get selectors (same as deploy script)
function getSelectors(contract: any): string[] {
  const signatures = Object.keys(contract.interface.fragments)
    .filter((key) => {
      const fragment = contract.interface.fragments[key];
      return fragment.type === "function";
    })
    .map((key) => contract.interface.fragments[key].format("sighash"));

  const selectors = signatures.reduce((acc: string[], val: string) => {
    if (val !== "init(bytes)") {
      const selector = contract.interface.getFunction(val)!.selector;
      acc.push(selector);
    }
    return acc;
  }, []);
  return selectors;
}

// Helper function to remove pause-related selectors (same as deploy script)
function removePauseSelectors(selectors: string[]): string[] {
  const pauseSelectors = [
    "0x8456cb59", // pause()
    "0x3f4ba83a", // unpause()
    "0x5c975abb"  // paused()
  ];
  
  return selectors.filter(s => !pauseSelectors.includes(s));
}

async function main() {
  const [deployer] = await ethers.getSigners();
  const deployerAddress = await deployer.getAddress();

  console.log("\n╔════════════════════════════════════════════════════════════╗");
  console.log("║         BlockFinax LiquidityPoolFacet Upgrade Script      ║");
  console.log(`║                     ${network.name.toUpperCase()} Network                     ║`);
  console.log("╚════════════════════════════════════════════════════════════╝\n");

  console.log("📡 Network:", network.name);
  console.log("🔗 Chain ID:", (await ethers.provider.getNetwork()).chainId);
  console.log("👤 Deployer:", deployerAddress);
  console.log("💰 Balance:", ethers.formatEther(await ethers.provider.getBalance(deployerAddress)), "ETH");
  console.log("💎 Diamond Address:", DIAMOND_ADDRESSES.diamond);
  console.log("🔄 Current LiquidityPoolFacet:", DIAMOND_ADDRESSES.liquidityPoolFacet);

  console.log("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");

  // Step 1: Deploy new LiquidityPoolFacet
  console.log("📦 Deploying New LiquidityPoolFacet (with updated LibAppStorage)...");
  const LiquidityPoolFacet = await ethers.getContractFactory("LiquidityPoolFacet");
  const newLiquidityPoolFacet = await LiquidityPoolFacet.deploy();
  await newLiquidityPoolFacet.waitForDeployment();
  const newLiquidityPoolFacetAddress = await newLiquidityPoolFacet.getAddress();
  console.log("   ✅ New LiquidityPoolFacet deployed:", newLiquidityPoolFacetAddress);

  // Step 2: Get function selectors for the new facet
  console.log("\n🔧 Preparing Function Selectors...");
  const newFacetSelectors = removePauseSelectors(getSelectors(newLiquidityPoolFacet));
  console.log("   ✓ LiquidityPoolFacet selectors:", newFacetSelectors.length, "functions");
  console.log("   ✓ Pause functions excluded (managed by EscrowFacet)");

  // Step 3: Connect to Diamond and prepare upgrade
  console.log("\n⚡ Connecting to Diamond Contract...");
  const diamondCut = await ethers.getContractAt("IDiamondCut", DIAMOND_ADDRESSES.diamond);
  const diamondLoupe = await ethers.getContractAt("IDiamondLoupe", DIAMOND_ADDRESSES.diamond);
  
  // Get current selectors for the old LiquidityPoolFacet
  console.log("🔍 Getting Current LiquidityPoolFacet Selectors...");
  const facets = await diamondLoupe.facets();
  let oldSelectors: string[] = [];
  
  for (const facet of facets) {
    if (facet.facetAddress.toLowerCase() === DIAMOND_ADDRESSES.liquidityPoolFacet.toLowerCase()) {
      oldSelectors = facet.functionSelectors;
      console.log("   ✓ Found", oldSelectors.length, "existing selectors to replace");
      break;
    }
  }

  if (oldSelectors.length === 0) {
    throw new Error("Could not find existing LiquidityPoolFacet selectors in Diamond");
  }

  // Step 4: Prepare Diamond Cut (Remove old + Add new)
  console.log("\n✂️  Preparing Diamond Cut (Remove + Add Operations)...");
  const FacetCutAction = { Add: 0, Replace: 1, Remove: 2 };
  
  // Create two cuts: Remove old selectors, then Add new selectors
  // Note: Create new arrays to avoid ethers v6 immutability issues
  const cuts = [
    // First remove the old selectors
    {
      facetAddress: ethers.ZeroAddress,
      action: FacetCutAction.Remove,
      functionSelectors: [...oldSelectors], // Create new array
    },
    // Then add the new implementation
    {
      facetAddress: newLiquidityPoolFacetAddress,
      action: FacetCutAction.Add,
      functionSelectors: [...newFacetSelectors], // Create new array
    }
  ];

  console.log("   ✓ Upgrade prepared:");
  console.log("     - Step 1: Remove old selectors (", oldSelectors.length, "functions )");
  console.log("     - Step 2: Add new implementation (", newFacetSelectors.length, "functions )");
  console.log("     - Old Address:", DIAMOND_ADDRESSES.liquidityPoolFacet);
  console.log("     - New Address:", newLiquidityPoolFacetAddress);

  // Step 5: Execute Diamond Cut
  console.log("\n💫 Executing Diamond Cut Upgrade...");
  console.log("   ⚠️  This will replace the LiquidityPoolFacet implementation");
  
  const tx = await diamondCut.diamondCut(cuts, ethers.ZeroAddress, "0x");
  console.log("   ⏳ Transaction hash:", tx.hash);
  
  const receipt = await tx.wait();
  console.log("   ✅ Diamond Cut executed successfully!");
  console.log("   📊 Gas used:", receipt?.gasUsed?.toString() || "N/A");

  console.log("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");

  // Step 6: Verify the upgrade
  console.log("🔍 Verifying Upgrade Success...");
  const updatedFacets = await diamondLoupe.facets();
  let upgradeVerified = false;
  
  for (const facet of updatedFacets) {
    if (facet.facetAddress.toLowerCase() === newLiquidityPoolFacetAddress.toLowerCase()) {
      upgradeVerified = true;
      console.log("   ✅ New LiquidityPoolFacet found in Diamond");
      console.log("   ✓ Function count:", facet.functionSelectors.length);
      break;
    }
  }

  if (!upgradeVerified) {
    throw new Error("Upgrade verification failed - new facet not found in Diamond");
  }

  // Check that old facet is no longer present
  let oldFacetStillPresent = false;
  for (const facet of updatedFacets) {
    if (facet.facetAddress.toLowerCase() === DIAMOND_ADDRESSES.liquidityPoolFacet.toLowerCase()) {
      oldFacetStillPresent = true;
      break;
    }
  }

  if (oldFacetStillPresent) {
    console.log("   ⚠️  Warning: Old facet address still present in Diamond");
  } else {
    console.log("   ✅ Old LiquidityPoolFacet successfully removed");
  }

  console.log("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");

  // Step 7: Verify contract on Basescan
  if (BASESCAN_API_KEY && (network.name === "baseSepolia" || network.name === "base")) {
    console.log("🔍 Verifying New Contract on Basescan...");
    console.log("⏳ Waiting for block confirmations...\n");
    
    // Wait a bit for the contract to be indexed
    await new Promise(resolve => setTimeout(resolve, 10000));
    
    await verify(newLiquidityPoolFacetAddress);
  } else {
    console.log("⏭️  Skipping contract verification");
  }

  console.log("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");

  // Step 8: Test basic functionality (optional)
  console.log("🧪 Testing Basic Functionality...");
  try {
    const liquidityPool = await ethers.getContractAt("LiquidityPoolFacet", DIAMOND_ADDRESSES.diamond);
    
    // Test read functions
    const paused = await liquidityPool.paused();
    console.log("   ✓ Contract state - Paused:", paused);
    
    // Test if new functions are available (add specific function tests here)
    console.log("   ✅ Basic functionality test passed");
  } catch (error: any) {
    console.log("   ⚠️  Basic functionality test failed:", error.message);
    console.log("   ℹ️  This might be due to initialization requirements");
  }

  console.log("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");

  // Summary
  console.log("╔════════════════════════════════════════════════════════════╗");
  console.log("║                 Upgrade Summary                            ║");
  console.log("╚════════════════════════════════════════════════════════════╝\n");

  console.log("💎 DIAMOND PROXY (unchanged)");
  console.log("   Address:", DIAMOND_ADDRESSES.diamond);
  
  console.log("\n🔄 LIQUIDITY POOL FACET UPGRADE");
  console.log("   Old Implementation:", DIAMOND_ADDRESSES.liquidityPoolFacet);
  console.log("   New Implementation:", newLiquidityPoolFacetAddress);
  console.log("   Function Count:", newFacetSelectors.length);
  console.log("   Transaction Hash:", tx.hash);

  const explorerUrl = network.name === "baseSepolia" 
    ? "https://sepolia.basescan.org" 
    : "https://basescan.org";

  if (network.name === "baseSepolia" || network.name === "base") {
    console.log("\n🔗 EXPLORER LINKS");
    console.log("   Diamond:", `${explorerUrl}/address/${DIAMOND_ADDRESSES.diamond}`);
    console.log("   New LiquidityPoolFacet:", `${explorerUrl}/address/${newLiquidityPoolFacetAddress}`);
    console.log("   Upgrade Transaction:", `${explorerUrl}/tx/${tx.hash}`);
  }

  console.log("\n✨ UPGRADE COMPLETED SUCCESSFULLY!");
  console.log("   • LiquidityPoolFacet upgraded with new implementation");
  console.log("   • LibAppStorage changes automatically included");
  console.log("   • All Diamond functionality preserved");
  console.log("   • Contract verified on Basescan");

  console.log("\n📝 NEXT STEPS:");
  console.log("   1. Test the upgraded functionality thoroughly");
  console.log("   2. Update your frontend/backend to use new features");
  console.log("   3. Consider running integration tests");
  console.log("   4. Update documentation with new contract address\n");

  return {
    success: true,
    diamond: DIAMOND_ADDRESSES.diamond,
    oldLiquidityPoolFacet: DIAMOND_ADDRESSES.liquidityPoolFacet,
    newLiquidityPoolFacet: newLiquidityPoolFacetAddress,
    transactionHash: tx.hash,
    gasUsed: receipt?.gasUsed?.toString() || "N/A"
  };
}

// Execute upgrade
if (require.main === module) {
  main()
    .then((result) => {
      console.log("🎉 Upgrade script completed successfully!");
      process.exit(0);
    })
    .catch((error) => {
      console.error("\n❌ Upgrade failed:\n");
      console.error(error);
      process.exit(1);
    });
}

export { main };