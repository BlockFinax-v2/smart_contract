/**
 * Smart upgrade for Base Sepolia - handles different old versions
 */

import { ethers } from "hardhat";
import * as fs from "fs";
import * as path from "path";

const DEPLOYMENTS_DIR = path.join(__dirname, "..", "deployments");
const DEPLOYMENT_FILE = path.join(DEPLOYMENTS_DIR, "deployments.json");

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

function loadDeploymentHistory(): any {
  return JSON.parse(fs.readFileSync(DEPLOYMENT_FILE, "utf8"));
}

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

async function getCurrentFacets(diamondAddress: string): Promise<any[]> {
  const diamondLoupe = await ethers.getContractAt("IDiamondLoupe", diamondAddress);
  return await diamondLoupe.facets();
}

async function main() {
  const hre = require("hardhat");
  const network = hre.network.name;
  
  console.log(`\n🔄 Smart Upgrade for ${network}...`);
  
  const [deployer] = await ethers.getSigners();
  const history = loadDeploymentHistory();
  const deployment = history[network];
  
  if (!deployment) {
    throw new Error(`No deployment found for network: ${network}`);
  }
  
  const diamondAddress = deployment.diamond;
  console.log(`   Diamond: ${diamondAddress}\n`);
  
  // Get current Diamond state
  const currentFacets = await getCurrentFacets(diamondAddress);
  
  // Get new facets
  const governanceFacet = deployment.facets.find((f: any) => f.name === "GovernanceFacet");
  const liquidityPoolFacet = deployment.facets.find((f: any) => f.name === "LiquidityPoolFacet");
  
  const governanceContract = await ethers.getContractAt("GovernanceFacet", governanceFacet.address);
  const liquidityPoolContract = await ethers.getContractAt("LiquidityPoolFacet", liquidityPoolFacet.address);
  
  const newGovernanceSelectors = getSelectors(governanceContract);
  const newLiquidityPoolSelectors = getSelectors(liquidityPoolContract);
  
  console.log(`📦 New Facets:`);
  console.log(`   GovernanceFacet: ${governanceFacet.address} (${newGovernanceSelectors.length} functions)`);
  console.log(`   LiquidityPoolFacet: ${liquidityPoolFacet.address} (${newLiquidityPoolSelectors.length} functions)\n`);
  
  // Get all current function selectors in Diamond
  const allCurrentSelectors = new Set<string>();
  for (const facet of currentFacets) {
    for (const sel of facet.functionSelectors) {
      allCurrentSelectors.add(sel.toLowerCase());
    }
  }
  
  console.log(`📋 Current Diamond has ${allCurrentSelectors.size} total function selectors\n`);
  
  // Categorize GovernanceFacet selectors
  const governanceToAdd: string[] = [];
  const governanceToReplace: string[] = [];
  
  for (const sel of newGovernanceSelectors) {
    if (allCurrentSelectors.has(sel.toLowerCase())) {
      governanceToReplace.push(sel);
    } else {
      governanceToAdd.push(sel);
    }
  }
  
  // Categorize LiquidityPoolFacet selectors
  const liquidityPoolToAdd: string[] = [];
  const liquidityPoolToReplace: string[] = [];
  
  for (const sel of newLiquidityPoolSelectors) {
    if (allCurrentSelectors.has(sel.toLowerCase())) {
      liquidityPoolToReplace.push(sel);
    } else {
      liquidityPoolToAdd.push(sel);
    }
  }
  
  console.log(`🔍 GovernanceFacet:`);
  console.log(`   ${governanceToAdd.length} new functions to ADD`);
  console.log(`   ${governanceToReplace.length} existing functions to REPLACE`);
  
  console.log(`\n🔍 LiquidityPoolFacet:`);
  console.log(`   ${liquidityPoolToAdd.length} new functions to ADD`);
  console.log(`   ${liquidityPoolToReplace.length} existing functions to REPLACE\n`);
  
  // Build diamond cuts
  const cuts: FacetCut[] = [];
  
  if (governanceToAdd.length > 0) {
    cuts.push({
      facetAddress: governanceFacet.address,
      action: FacetCutAction.Add,
      functionSelectors: governanceToAdd
    });
    console.log(`1️⃣  ADD ${governanceToAdd.length} new GovernanceFacet functions`);
  }
  
  if (governanceToReplace.length > 0) {
    cuts.push({
      facetAddress: governanceFacet.address,
      action: FacetCutAction.Replace,
      functionSelectors: governanceToReplace
    });
    console.log(`2️⃣  REPLACE ${governanceToReplace.length} existing GovernanceFacet functions`);
  }
  
  if (liquidityPoolToAdd.length > 0) {
    cuts.push({
      facetAddress: liquidityPoolFacet.address,
      action: FacetCutAction.Add,
      functionSelectors: liquidityPoolToAdd
    });
    console.log(`3️⃣  ADD ${liquidityPoolToAdd.length} new LiquidityPoolFacet functions`);
  }
  
  if (liquidityPoolToReplace.length > 0) {
    cuts.push({
      facetAddress: liquidityPoolFacet.address,
      action: FacetCutAction.Replace,
      functionSelectors: liquidityPoolToReplace
    });
    console.log(`4️⃣  REPLACE ${liquidityPoolToReplace.length} existing LiquidityPoolFacet functions`);
  }
  
  // Execute upgrade
  console.log(`\n⚙️  Executing Diamond Cut with ${cuts.length} operations...\n`);
  
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
  
  // Verify
  console.log(`\n🎉 Final State:`);
  const finalFacets = await getCurrentFacets(diamondAddress);
  for (const facet of finalFacets) {
    const facetData = deployment.facets.find((f: any) => 
      f.address.toLowerCase() === facet.facetAddress.toLowerCase()
    );
    const name = facetData?.name || "DiamondCutFacet";
    console.log(`   ${name}: ${facet.facetAddress} (${facet.functionSelectors.length} functions)`);
  }
  
  // Test token management
  console.log(`\n🧪 Testing Token Management:`);
  const governance = await ethers.getContractAt("GovernanceFacet", diamondAddress);
  const supportedTokens = await governance.getSupportedStakingTokens();
  console.log(`   ✅ getSupportedStakingTokens() works - ${supportedTokens.length} tokens`);
  
  console.log(`\n✅ Upgrade Complete!`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
