#!/usr/bin/env ts-node

/**
 * Special upgrade for reorganized facets
 * - Adds new token management functions to GovernanceFacet
 * - Replaces remaining LiquidityPoolFacet functions (removes old admin functions)
 */

const { ethers } = require("hardhat");
import * as fs from "fs";
import * as path from "path";

// Deployment paths
const DEPLOYMENTS_DIR = path.join(__dirname, "..", "deployments");
const DEPLOYMENT_FILE = path.join(DEPLOYMENTS_DIR, "deployments.json");

// FacetCutAction enum
enum FacetCutAction {
  Add = 0,
  Replace = 1,
  Remove = 2
}

interface FacetCut {
  facetAddress: string;
  action: number;
  functionSelectors: string[];
}

/**
 * Load deployment history
 */
function loadDeploymentHistory(): any {
  if (!fs.existsSync(DEPLOYMENT_FILE)) {
    throw new Error(`No deployment found at ${DEPLOYMENT_FILE}`);
  }
  return JSON.parse(fs.readFileSync(DEPLOYMENT_FILE, "utf8"));
}

/**
 * Get function selectors from a facet
 */
function getSelectors(contract: any): string[] {
  const selectors: string[] = [];
  
  for (const fragment of contract.interface.fragments) {
    if (fragment.type === 'function' && fragment.name !== 'init') {
      const selector = contract.interface.getFunction(fragment.name)!.selector;
      selectors.push(selector);
    }
  }
  
  return selectors;
}

/**
 * Get current facet addresses and their selectors from Diamond
 */
async function getCurrentFacets(diamondAddress: string): Promise<any[]> {
  const diamondLoupe = await ethers.getContractAt("IDiamondLoupe", diamondAddress);
  return await diamondLoupe.facets();
}

async function main() {
  const hre = require("hardhat");
  const network = hre.network.name;
  
  console.log(`\n🔄 Upgrading Diamond with Reorganized Facets on ${network}...`);
  
  const [deployer] = await ethers.getSigners();
  const deployerAddress = await deployer.getAddress();
  
  console.log(`   Deployer: ${deployerAddress}`);
  console.log(`   Balance: ${ethers.formatEther(await ethers.provider.getBalance(deployerAddress))} ETH`);
  
  // Load deployment
  const history = loadDeploymentHistory();
  const deployment = history[network];
  
  if (!deployment) {
    throw new Error(`No deployment found for network: ${network}`);
  }
  
  const diamondAddress = deployment.diamond;
  console.log(`   Diamond: ${diamondAddress}\n`);
  
  // Get current Diamond state
  console.log("📋 Current Diamond State:");
  const currentFacets = await getCurrentFacets(diamondAddress);
  for (const facet of currentFacets) {
    console.log(`   ${facet.facetAddress}: ${facet.functionSelectors.length} functions`);
  }
  
  // Get deployed facets
  const governanceFacet = deployment.facets.find((f: any) => f.name === "GovernanceFacet");
  const liquidityPoolFacet = deployment.facets.find((f: any) => f.name === "LiquidityPoolFacet");
  
  if (!governanceFacet || !liquidityPoolFacet) {
    throw new Error("GovernanceFacet or LiquidityPoolFacet not found in deployment");
  }
  
  console.log(`\n📦 Using Deployed Facets:`);
  console.log(`   GovernanceFacet: ${governanceFacet.address}`);
  console.log(`   LiquidityPoolFacet: ${liquidityPoolFacet.address}`);
  
  // Get selectors from new facets
  const governanceContract = await ethers.getContractAt("GovernanceFacet", governanceFacet.address);
  const liquidityPoolContract = await ethers.getContractAt("LiquidityPoolFacet", liquidityPoolFacet.address);
  
  const newGovernanceSelectors = getSelectors(governanceContract);
  const newLiquidityPoolSelectors = getSelectors(liquidityPoolContract);
  
  console.log(`\n   GovernanceFacet functions: ${newGovernanceSelectors.length}`);
  console.log(`   LiquidityPoolFacet functions: ${newLiquidityPoolSelectors.length}`);
  
  // Find OLD GovernanceFacet and LiquidityPoolFacet selectors in Diamond
  const oldGovernanceInDiamond = currentFacets.find(f => 
    f.functionSelectors.some((sel: string) => 
      governanceContract.interface.getFunction("pause")?.selector === sel
    )
  );
  
  const oldLiquidityPoolInDiamond = currentFacets.find(f =>
    f.functionSelectors.some((sel: string) =>
      liquidityPoolContract.interface.getFunction("stake")?.selector === sel
    )
  );
  
  console.log(`\n🔍 Old Facets in Diamond:`);
  console.log(`   Old GovernanceFacet: ${oldGovernanceInDiamond?.facetAddress} (${oldGovernanceInDiamond?.functionSelectors.length} functions)`);
  console.log(`   Old LiquidityPoolFacet: ${oldLiquidityPoolInDiamond?.facetAddress} (${oldLiquidityPoolInDiamond?.functionSelectors.length} functions)`);
  
  // OLD admin functions that were in LiquidityPoolFacet (now need to be removed and added to Governance)
  const tokenManagementSelectorsToMove = [
    governanceContract.interface.getFunction("addSupportedStakingToken").selector, // 0xf3594258
    governanceContract.interface.getFunction("removeSupportedStakingToken").selector, // 0x063fbefa
    governanceContract.interface.getFunction("getSupportedStakingTokens").selector, // 0xfc54bbd1
    governanceContract.interface.getFunction("isTokenSupported").selector, // 0x75151b63
    governanceContract.interface.getFunction("getTotalStakedForToken").selector, // 0x1e145cc7
  ];
  
  console.log(`\n🔄 Token Management Functions to Move (${tokenManagementSelectorsToMove.length}):`);
  tokenManagementSelectorsToMove.forEach(sel => {
    const fragment = governanceContract.interface.getFunction(sel);
    console.log(`   ${sel} - ${fragment?.name}`);
  });
  
  // Check which of these exist in old LiquidityPoolFacet
  const existingInLiquidityPool = tokenManagementSelectorsToMove.filter(sel =>
    oldLiquidityPoolInDiamond?.functionSelectors.includes(sel)
  );
  
  console.log(`\n   ${existingInLiquidityPool.length} functions currently in old LiquidityPoolFacet`);
  console.log(`   ${tokenManagementSelectorsToMove.length - existingInLiquidityPool.length} functions are new`);
  
  // Prepare diamond cuts
  const cuts: FacetCut[] = [];
  
  // 1. REMOVE token management functions from old LiquidityPoolFacet (ONLY if they exist there)
  if (existingInLiquidityPool.length > 0) {
    cuts.push({
      facetAddress: ethers.ZeroAddress,
      action: FacetCutAction.Remove,
      functionSelectors: existingInLiquidityPool
    });
    console.log(`\n1️⃣  REMOVE ${existingInLiquidityPool.length} token management functions from old LiquidityPoolFacet`);
  } else {
    console.log(`\n1️⃣  SKIP REMOVE - No token management functions in old LiquidityPoolFacet`);
  }
  
  // 2. ADD token management functions to NEW GovernanceFacet
  cuts.push({
    facetAddress: governanceFacet.address,
    action: FacetCutAction.Add,
    functionSelectors: tokenManagementSelectorsToMove
  });
  console.log(`2️⃣  ADD ${tokenManagementSelectorsToMove.length} token management functions to GovernanceFacet`);
  
  // 3. REPLACE other GovernanceFacet functions (if any were in old GovernanceFacet)
  const otherGovernanceSelectors = newGovernanceSelectors.filter(
    sel => !tokenManagementSelectorsToMove.includes(sel)
  );
  
  if (otherGovernanceSelectors.length > 0) {
    cuts.push({
      facetAddress: governanceFacet.address,
      action: FacetCutAction.Replace,
      functionSelectors: otherGovernanceSelectors
    });
    console.log(`3️⃣  REPLACE ${otherGovernanceSelectors.length} existing GovernanceFacet functions`);
  }
  
  // 4. REPLACE LiquidityPoolFacet functions (staking functions only, admin already removed)
  cuts.push({
    facetAddress: liquidityPoolFacet.address,
    action: FacetCutAction.Replace,
    functionSelectors: newLiquidityPoolSelectors
  });
  console.log(`4️⃣  REPLACE ${newLiquidityPoolSelectors.length} LiquidityPoolFacet staking functions`);
  
  // Execute upgrade
  console.log(`\n⚙️  Executing Diamond Cut with ${cuts.length} operations...`);
  
  const diamondCut = await ethers.getContractAt("IDiamondCut", diamondAddress);
  
  try {
    const tx = await diamondCut.diamondCut(cuts, ethers.ZeroAddress, "0x");
    console.log(`   📤 Transaction sent: ${tx.hash}`);
    
    const receipt = await tx.wait();
    console.log(`   ✅ Upgrade successful! Gas used: ${receipt?.gasUsed.toString()}`);
  } catch (error: any) {
    console.error(`\n❌ Upgrade failed: ${error.message}`);
    throw error;
  }
  
  // Verify final state
  console.log(`\n🎉 Verifying Final State:`);
  const finalFacets = await getCurrentFacets(diamondAddress);
  let totalFunctions = 0;
  
  for (const facet of finalFacets) {
    const facetData = deployment.facets.find((f: any) => 
      f.address.toLowerCase() === facet.facetAddress.toLowerCase()
    );
    const name = facetData?.name || "DiamondCutFacet";
    console.log(`   ${name}: ${facet.facetAddress} (${facet.functionSelectors.length} functions)`);
    totalFunctions += facet.functionSelectors.length;
  }
  
  console.log(`\n   Total functions in Diamond: ${totalFunctions}`);
  
  // Test token management functions
  console.log(`\n🧪 Testing Token Management Functions:`);
  const governance = await ethers.getContractAt("GovernanceFacet", diamondAddress);
  
  try {
    const supportedTokens = await governance.getSupportedStakingTokens();
    console.log(`   ✅ getSupportedStakingTokens() works - ${supportedTokens.length} tokens`);
    
    const isSupported = await governance.isTokenSupported(ethers.ZeroAddress);
    console.log(`   ✅ isTokenSupported() works - result: ${isSupported}`);
    
    const totalStaked = await governance.getTotalStakedForToken(ethers.ZeroAddress);
    console.log(`   ✅ getTotalStakedForToken() works - result: ${totalStaked.toString()}`);
  } catch (error: any) {
    console.error(`   ❌ Function test failed: ${error.message}`);
  }
  
  console.log(`\n✅ Reorganization Complete!`);
  console.log(`\n💡 Changes:`);
  console.log(`   - Token management moved to GovernanceFacet`);
  console.log(`   - Admin functions removed from LiquidityPoolFacet`);
  console.log(`   - LiquidityPoolFacet now only has staking logic`);
  console.log(`\n🚀 Ready to add tokens! Run add-staking-tokens.ts next`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("\n❌ Error:", error);
    process.exit(1);
  });
