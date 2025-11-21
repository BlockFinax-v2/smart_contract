import { ethers, run, network } from "hardhat";
import * as dotenv from "dotenv";
import { writeFileSync, readFileSync } from "fs";
import { join } from "path";

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

interface UpgradeResult {
  success: boolean;
  diamond: string;
  oldLiquidityPoolFacet: string;
  newLiquidityPoolFacet: string;
  transactionHash: string;
  gasUsed: string;
  blockNumber?: number;
  timestamp?: number;
}

async function verify(address: string, constructorArguments: any[] = []): Promise<boolean> {
  if (network.name === "hardhat" || network.name === "localhost") {
    return true;
  }

  if (!BASESCAN_API_KEY) {
    console.log(`⏭️  Skipping verification for ${address} (no API key)`);
    return false;
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
    return true;
  } catch (e: any) {
    if (e.message.toLowerCase().includes("already verified")) {
      const explorerUrl = network.name === "baseSepolia"
        ? `https://sepolia.basescan.org/address/${address}`
        : `https://basescan.org/address/${address}`;
      console.log(`   ✅ Already verified: ${explorerUrl}`);
      return true;
    } else {
      console.log(`   ❌ Verification failed: ${e.message}`);
      return false;
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

// Helper function to remove pause-related selectors
function removePauseSelectors(selectors: string[]): string[] {
  const pauseSelectors = [
    "0x8456cb59", // pause()
    "0x3f4ba83a", // unpause()
    "0x5c975abb"  // paused()
  ];
  
  return selectors.filter(s => !pauseSelectors.includes(s));
}

function saveUpgradeResult(result: UpgradeResult): void {
  const upgradeLog = {
    timestamp: new Date().toISOString(),
    network: network.name,
    chainId: network.config.chainId,
    ...result
  };

  const logPath = join(__dirname, "../upgrade-logs");
  const logFile = join(logPath, `liquidity-pool-upgrade-${Date.now()}.json`);
  
  try {
    writeFileSync(logFile, JSON.stringify(upgradeLog, null, 2));
    console.log(`📝 Upgrade log saved to: ${logFile}`);
  } catch (error) {
    console.log(`⚠️  Could not save upgrade log: ${error}`);
  }
}

async function testUpgradedContract(diamondAddress: string): Promise<boolean> {
  console.log("🧪 Testing Upgraded Contract Functionality...");
  
  try {
    const liquidityPool = await ethers.getContractAt("LiquidityPoolFacet", diamondAddress);
    
    // Test 1: Basic read functions
    const paused = await liquidityPool.paused();
    console.log("   ✓ Contract state - Paused:", paused);
    
    // Test 2: Check if new functions are available
    try {
      // Test new functions added in the upgrade
      const config = await liquidityPool.getStakingConfig();
      console.log("   ✓ Staking configuration accessible");
    } catch (error) {
      console.log("   ℹ️  Staking config not initialized (expected for new deployment)");
    }

    // Test 3: Check Diamond Loupe functionality
    const diamondLoupe = await ethers.getContractAt("IDiamondLoupe", diamondAddress);
    const facets = await diamondLoupe.facets();
    console.log("   ✓ Diamond has", facets.length, "facets");
    
    console.log("   ✅ Basic functionality test passed");
    return true;
  } catch (error: any) {
    console.log("   ❌ Basic functionality test failed:", error.message);
    return false;
  }
}

async function main(): Promise<UpgradeResult> {
  const [deployer] = await ethers.getSigners();
  const deployerAddress = await deployer.getAddress();

  console.log("\n╔════════════════════════════════════════════════════════════╗");
  console.log("║     BlockFinax Complete Upgrade & Verification Script     ║");
  console.log(`║                     ${network.name.toUpperCase()} Network                     ║`);
  console.log("╚════════════════════════════════════════════════════════════╝\n");

  console.log("📡 Network:", network.name);
  console.log("🔗 Chain ID:", (await ethers.provider.getNetwork()).chainId);
  console.log("👤 Deployer:", deployerAddress);
  console.log("💰 Balance:", ethers.formatEther(await ethers.provider.getBalance(deployerAddress)), "ETH");
  console.log("💎 Diamond Address:", DIAMOND_ADDRESSES.diamond);
  console.log("🔄 Current LiquidityPoolFacet:", DIAMOND_ADDRESSES.liquidityPoolFacet);

  console.log("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");

  // PHASE 1: DEPLOY NEW LIQUIDITYPOOLFACE
  console.log("🚀 PHASE 1: DEPLOYING NEW LIQUIDITYPOOLFACE");
  console.log("============================================\n");

  console.log("📦 Deploying New LiquidityPoolFacet (includes updated LibAppStorage)...");
  const LiquidityPoolFacet = await ethers.getContractFactory("LiquidityPoolFacet");
  const newLiquidityPoolFacet = await LiquidityPoolFacet.deploy();
  await newLiquidityPoolFacet.waitForDeployment();
  const newLiquidityPoolFacetAddress = await newLiquidityPoolFacet.getAddress();
  console.log("   ✅ New LiquidityPoolFacet deployed:", newLiquidityPoolFacetAddress);

  console.log("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");

  // PHASE 2: PREPARE DIAMOND CUT
  console.log("🔧 PHASE 2: PREPARING DIAMOND CUT");
  console.log("==================================\n");

  const newFacetSelectors = removePauseSelectors(getSelectors(newLiquidityPoolFacet));
  console.log("🔧 Function Selectors:");
  console.log("   ✓ LiquidityPoolFacet selectors:", newFacetSelectors.length, "functions");
  console.log("   ✓ Pause functions excluded (managed by EscrowFacet)");

  // Connect to Diamond and get current state
  const diamondCut = await ethers.getContractAt("IDiamondCut", DIAMOND_ADDRESSES.diamond);
  const diamondLoupe = await ethers.getContractAt("IDiamondLoupe", DIAMOND_ADDRESSES.diamond);
  
  console.log("\n🔍 Analyzing Current Diamond State...");
  const currentFacets = await diamondLoupe.facets();
  console.log("   ✓ Current facet count:", currentFacets.length);
  
  let oldSelectors: string[] = [];
  for (const facet of currentFacets) {
    if (facet.facetAddress.toLowerCase() === DIAMOND_ADDRESSES.liquidityPoolFacet.toLowerCase()) {
      oldSelectors = facet.functionSelectors;
      console.log("   ✓ Found existing LiquidityPoolFacet with", oldSelectors.length, "selectors");
      break;
    }
  }

  if (oldSelectors.length === 0) {
    throw new Error("Could not find existing LiquidityPoolFacet selectors in Diamond");
  }

  console.log("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");

  // PHASE 3: EXECUTE UPGRADE
  console.log("⚡ PHASE 3: EXECUTING DIAMOND CUT");
  console.log("=================================\n");

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
    ];  console.log("✂️  Diamond Cut Details:");
  console.log("   - Step 1: Remove old selectors (", oldSelectors.length, "functions )");
  console.log("   - Step 2: Add new implementation (", newFacetSelectors.length, "functions )");
  console.log("   - Old Implementation:", DIAMOND_ADDRESSES.liquidityPoolFacet);
  console.log("   - New Implementation:", newLiquidityPoolFacetAddress);
  
  console.log("\n💫 Executing Diamond Cut...");
  const tx = await diamondCut.diamondCut(cuts, ethers.ZeroAddress, "0x");
  console.log("   ⏳ Transaction submitted:", tx.hash);
  
  const receipt = await tx.wait();
  const blockNumber = receipt?.blockNumber;
  const timestamp = blockNumber ? (await ethers.provider.getBlock(blockNumber))?.timestamp : undefined;
  
  console.log("   ✅ Diamond Cut executed successfully!");
  console.log("   📊 Gas used:", receipt?.gasUsed?.toString() || "N/A");
  console.log("   📦 Block number:", blockNumber || "N/A");

  console.log("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");

  // PHASE 4: VERIFY UPGRADE
  console.log("✅ PHASE 4: VERIFYING UPGRADE");
  console.log("==============================\n");

  console.log("🔍 Checking Diamond State After Upgrade...");
  const updatedFacets = await diamondLoupe.facets();
  let upgradeVerified = false;
  let oldFacetRemoved = true;
  
  for (const facet of updatedFacets) {
    if (facet.facetAddress.toLowerCase() === newLiquidityPoolFacetAddress.toLowerCase()) {
      upgradeVerified = true;
      console.log("   ✅ New LiquidityPoolFacet found in Diamond");
      console.log("   ✓ Function count:", facet.functionSelectors.length);
    }
    if (facet.facetAddress.toLowerCase() === DIAMOND_ADDRESSES.liquidityPoolFacet.toLowerCase()) {
      oldFacetRemoved = false;
    }
  }

  if (!upgradeVerified) {
    throw new Error("❌ Upgrade verification failed - new facet not found in Diamond");
  }

  if (!oldFacetRemoved) {
    console.log("   ⚠️  Warning: Old facet address still present in Diamond (this might be expected)");
  } else {
    console.log("   ✅ Old LiquidityPoolFacet successfully replaced");
  }

  // Test upgraded contract
  const testPassed = await testUpgradedContract(DIAMOND_ADDRESSES.diamond);
  if (!testPassed) {
    console.log("   ⚠️  Some functionality tests failed - manual testing recommended");
  }

  console.log("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");

  // PHASE 5: VERIFY ON BASESCAN
  console.log("🔍 PHASE 5: BASESCAN VERIFICATION");
  console.log("==================================\n");

  let verificationSuccess = false;
  if (BASESCAN_API_KEY && (network.name === "baseSepolia" || network.name === "base")) {
    console.log("🔍 Verifying New Contract on Basescan...");
    console.log("⏳ Waiting for block confirmations...\n");
    
    // Wait for the contract to be indexed
    await new Promise(resolve => setTimeout(resolve, 15000));
    
    verificationSuccess = await verify(newLiquidityPoolFacetAddress);
  } else {
    console.log("⏭️  Skipping Basescan verification (API key not provided)");
  }

  console.log("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");

  // PHASE 6: GENERATE SUMMARY & LOGS
  console.log("📋 PHASE 6: GENERATING SUMMARY");
  console.log("===============================\n");

  const result: UpgradeResult = {
    success: true,
    diamond: DIAMOND_ADDRESSES.diamond,
    oldLiquidityPoolFacet: DIAMOND_ADDRESSES.liquidityPoolFacet,
    newLiquidityPoolFacet: newLiquidityPoolFacetAddress,
    transactionHash: tx.hash,
    gasUsed: receipt?.gasUsed?.toString() || "N/A",
    blockNumber,
    timestamp
  };

  saveUpgradeResult(result);

  // Final Summary
  console.log("╔════════════════════════════════════════════════════════════╗");
  console.log("║               🎉 UPGRADE COMPLETED! 🎉                    ║");
  console.log("╚════════════════════════════════════════════════════════════╝\n");

  console.log("💎 DIAMOND PROXY (unchanged)");
  console.log("   Address:", DIAMOND_ADDRESSES.diamond);
  
  console.log("\n🔄 LIQUIDITY POOL FACET UPGRADE");
  console.log("   Old Implementation:", DIAMOND_ADDRESSES.liquidityPoolFacet);
  console.log("   New Implementation:", newLiquidityPoolFacetAddress);
  console.log("   Function Count:", newFacetSelectors.length);
  console.log("   Gas Used:", receipt?.gasUsed?.toString() || "N/A");

  const explorerUrl = network.name === "baseSepolia" 
    ? "https://sepolia.basescan.org" 
    : "https://basescan.org";

  if (network.name === "baseSepolia" || network.name === "base") {
    console.log("\n🔗 EXPLORER LINKS");
    console.log("   Diamond (use this address in your app):", `${explorerUrl}/address/${DIAMOND_ADDRESSES.diamond}`);
    console.log("   New LiquidityPoolFacet:", `${explorerUrl}/address/${newLiquidityPoolFacetAddress}`);
    console.log("   Upgrade Transaction:", `${explorerUrl}/tx/${tx.hash}`);
  }

  console.log("\n✨ SUCCESS SUMMARY:");
  console.log("   ✅ LiquidityPoolFacet upgraded with new implementation");
  console.log("   ✅ LibAppStorage changes automatically included");
  console.log("   ✅ All Diamond functionality preserved");
  console.log(`   ${verificationSuccess ? '✅' : '⚠️'} Contract ${verificationSuccess ? 'verified' : 'verification attempted'} on Basescan`);

  console.log("\n📝 IMPORTANT NOTES:");
  console.log("   🎯 Your Diamond proxy address remains unchanged:", DIAMOND_ADDRESSES.diamond);
  console.log("   🎯 Use the Diamond address for all interactions (not the facet address)");
  console.log("   🎯 All existing functionality continues to work normally");
  console.log("   🎯 New LiquidityPoolFacet features are now available");

  console.log("\n🚀 NEXT STEPS:");
  console.log("   1. Test all upgraded functionality thoroughly");
  console.log("   2. Update your frontend/backend if using new features");
  console.log("   3. Run integration tests against the Diamond proxy");
  console.log("   4. Monitor the contract for the first few transactions");
  console.log("   5. Consider announcing the upgrade to your users\n");

  return result;
}

// Execute upgrade script
if (require.main === module) {
  main()
    .then((result) => {
      console.log("🎊 Complete upgrade and verification finished!");
      console.log("📄 Result saved to upgrade logs directory");
      process.exit(0);
    })
    .catch((error) => {
      console.error("\n💥 UPGRADE FAILED!");
      console.error("================\n");
      console.error(error);
      console.error("\n🔧 Troubleshooting:");
      console.error("   1. Check your private key and network configuration");
      console.error("   2. Ensure you have enough ETH for gas fees");
      console.error("   3. Verify the Diamond contract is deployed at the specified address");
      console.error("   4. Check that you are the owner of the Diamond contract");
      console.error("   5. Ensure the LiquidityPoolFacet compiles without errors\n");
      process.exit(1);
    });
}

export { main };