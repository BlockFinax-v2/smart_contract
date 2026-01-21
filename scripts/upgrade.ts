#!/usr/bin/env ts-node

const { ethers } = require("hardhat");
import * as fs from "fs";
import * as path from "path";
import * as crypto from "crypto";
import { execSync } from "child_process";

// Types
interface FacetDeployment {
  name: string;
  address: string;
  txHash: string;
  deployer: string;
  timestamp: number;
  verified: boolean;
  updated: boolean;
  contentHash: string;
  deleted?: boolean; // Track deleted facets
}

interface DiamondDeployment {
  diamond: string;
  diamondInit: string;
  diamondCutFacet: string;
  mockUSDC?: string;
  facets: FacetDeployment[];
  network: string;
  chainId: number;
  deployer: string;
  deployedAt: number;
}

interface DeploymentHistory {
  [network: string]: DiamondDeployment;
}

interface FacetCut {
  facetAddress: string;
  action: number;
  functionSelectors: string[];
}

// Deployment paths
const DEPLOYMENTS_DIR = path.join(__dirname, "..", "deployments");
const DEPLOYMENT_FILE = path.join(DEPLOYMENTS_DIR, "deployments.json");
const HASHES_FILE = path.join(DEPLOYMENTS_DIR, "contract-hashes.json");

/**
 * Automatically discover all facets from the facets directory
 * Excludes DiamondCutFacet which is immutable and cannot be upgraded
 */
function discoverFacets(): string[] {
  const facetsDir = path.join(__dirname, "..", "contracts", "facets");
  
  if (!fs.existsSync(facetsDir)) {
    console.log("⚠️  Facets directory not found");
    return [];
  }
  
  const files = fs.readdirSync(facetsDir);
  const facets = files
    .filter(file => file.endsWith(".sol"))
    .filter(file => file !== "DiamondCutFacet.sol") // Exclude DiamondCutFacet - it's immutable
    .map(file => file.replace(".sol", ""))
    .sort(); // Sort for consistent ordering
  
  return facets;
}

// Immutable facets that should never be upgraded
const IMMUTABLE_FACETS = ["DiamondCutFacet"];

// FacetCutAction enum
enum FacetCutAction {
  Add = 0,
  Replace = 1,
  Remove = 2
}

/**
 * Calculate content hash of a Solidity file
 */
function calculateFileHash(filePath: string): string {
  const content = fs.readFileSync(filePath, "utf8");
  return crypto.createHash("sha256").update(content).digest("hex");
}

/**
 * Get all Solidity files for a contract (including imports)
 */
function getContractFiles(contractName: string): string[] {
  const contractPath = path.join(__dirname, "..", "contracts");
  const files: string[] = [];
  
  if (contractName === "Diamond") {
    files.push(path.join(contractPath, "Diamond.sol"));
  } else if (contractName === "DiamondInit") {
    files.push(path.join(contractPath, "DiamondInit.sol"));
  } else if (contractName === "MockERC20") {
    files.push(path.join(contractPath, "mocks", "MockERC20.sol"));
  } else {
    files.push(path.join(contractPath, "facets", `${contractName}.sol`));
  }
  
  // Add library files
  files.push(path.join(contractPath, "libraries", "LibDiamond.sol"));
  files.push(path.join(contractPath, "libraries", "LibAppStorage.sol"));
  files.push(path.join(contractPath, "libraries", "LibPausable.sol"));
  files.push(path.join(contractPath, "libraries", "LibAddressResolver.sol"));
  
  return files.filter(f => fs.existsSync(f));
}

/**
 * Calculate combined hash for a contract and its dependencies
 */
function calculateContractHash(contractName: string): string {
  const files = getContractFiles(contractName);
  const combinedContent = files.map(f => fs.readFileSync(f, "utf8")).join("\n");
  return crypto.createHash("sha256").update(combinedContent).digest("hex");
}

/**
 * Load deployment history
 */
function loadDeploymentHistory(): DeploymentHistory {
  if (!fs.existsSync(DEPLOYMENT_FILE)) {
    throw new Error(`No deployment found at ${DEPLOYMENT_FILE}. Please run deploy script first.`);
  }
  return JSON.parse(fs.readFileSync(DEPLOYMENT_FILE, "utf8"));
}

/**
 * Save deployment history
 */
function saveDeploymentHistory(history: DeploymentHistory): void {
  if (!fs.existsSync(DEPLOYMENTS_DIR)) {
    fs.mkdirSync(DEPLOYMENTS_DIR, { recursive: true });
  }
  fs.writeFileSync(DEPLOYMENT_FILE, JSON.stringify(history, null, 2));
}

/**
 * Load contract hashes
 */
function loadContractHashes(): { [key: string]: string } {
  if (!fs.existsSync(HASHES_FILE)) {
    return {};
  }
  return JSON.parse(fs.readFileSync(HASHES_FILE, "utf8"));
}

/**
 * Save contract hashes
 */
function saveContractHashes(hashes: { [key: string]: string }): void {
  if (!fs.existsSync(DEPLOYMENTS_DIR)) {
    fs.mkdirSync(DEPLOYMENTS_DIR, { recursive: true });
  }
  fs.writeFileSync(HASHES_FILE, JSON.stringify(hashes, null, 2));
}

/**
 * Check if contract has been updated
 */
function isContractUpdated(contractName: string): boolean {
  const currentHash = calculateContractHash(contractName);
  const savedHashes = loadContractHashes();
  
  if (!savedHashes[contractName]) {
    return true; // New contract
  }
  
  return savedHashes[contractName] !== currentHash;
}

/**
 * Get function selectors from a facet
 */
function getSelectors(contract: any): string[] {
  if (!contract || !contract.interface) {
    console.error("❌ Invalid contract object passed to getSelectors");
    return [];
  }
  
  const selectors: string[] = [];
  
  // Use interface.fragments to get functions
  for (const fragment of contract.interface.fragments) {
    if (fragment.type === 'function' && fragment.name !== 'init') {
      const selector = contract.interface.getFunction(fragment.name)!.selector;
      selectors.push(selector);
    }
  }
  
  return selectors;
}

/**
 * Get current facets from Diamond
 */
async function getCurrentFacets(diamondAddress: string): Promise<any[]> {
  const diamondLoupe = await ethers.getContractAt("IDiamondLoupe", diamondAddress);
  return await diamondLoupe.facets();
}

/**
 * Verify contract on block explorer
 */
async function verifyContract(
  address: string,
  constructorArguments: any[],
  network: string,
  contractName?: string
): Promise<boolean> {
  try {
    console.log(`\n🔍 Verifying contract at ${address} on ${network}...`);
    
    const args = [
      "hardhat",
      "verify",
      "--network",
      network,
      address,
      ...constructorArguments.map(arg => arg.toString())
    ];
    
    if (contractName) {
      args.push("--contract", contractName);
    }
    
    execSync(`npx ${args.join(" ")}`, { stdio: "inherit" });
    console.log(`✅ Contract verified successfully!`);
    return true;
  } catch (error: any) {
    if (error.message.includes("Already Verified")) {
      console.log(`✅ Contract already verified`);
      return true;
    }
    console.log(`⚠️  Verification failed: ${error.message}`);
    return false;
  }
}

/**
 * Deploy a facet
 */
async function deployFacet(
  facetName: string,
  deployer: string
): Promise<FacetDeployment> {
  console.log(`\n📦 Deploying ${facetName}...`);
  
  const Facet = await ethers.getContractFactory(facetName);
  const facet = await Facet.deploy();
  await facet.waitForDeployment();
  
  const address = await facet.getAddress();
  const deployTx = facet.deploymentTransaction();
  
  console.log(`✅ ${facetName} deployed at: ${address}`);
  
  return {
    name: facetName,
    address: address,
    txHash: deployTx?.hash || "",
    deployer: deployer,
    timestamp: Date.now(),
    verified: false,
    updated: true,
    contentHash: calculateContractHash(facetName)
  };
}

/**
 * Main upgrade function
 */
async function main() {
  // Get network name from hardhat runtime environment
  const hre = require("hardhat");
  const network = hre.network.name;
  
  console.log(`\n🔄 Starting Diamond upgrade on ${network}...`);
  
  // Discover all upgradeable facets dynamically
  const UPGRADEABLE_FACET_NAMES = discoverFacets();
  
  // Get deployer
  const [deployer] = await ethers.getSigners();
  const deployerAddress = await deployer.getAddress();
  const chainId = (await ethers.provider.getNetwork()).chainId;
  
  console.log(`\n📋 Upgrade Info:`);
  console.log(`   Network: ${network}`);
  console.log(`   Chain ID: ${chainId}`);
  console.log(`   Deployer: ${deployerAddress}`);
  console.log(`   Balance: ${ethers.formatEther(await ethers.provider.getBalance(deployerAddress))} ETH`);
  
  // Load deployment history
  const history = loadDeploymentHistory();
  const deployment = history[network];
  
  if (!deployment) {
    console.error(`❌ No deployment found for network: ${network}`);
    console.error(`   Available networks: ${Object.keys(history).join(", ")}`);
    process.exit(1);
  }
  
  console.log(`\n📍 Diamond Address: ${deployment.diamond}`);
  
  // Check which facets need upgrading
  console.log(`\n🔍 Checking for updated facets...`);
  const updatedFacets: string[] = [];
  const newFacets: string[] = [];
  
  // Get current facets from Diamond to compare addresses
  console.log(`   Reading Diamond state...`);
  const currentFacets = await getCurrentFacets(deployment.diamond);
  
  for (const facetName of UPGRADEABLE_FACET_NAMES) {
    const existingFacet = deployment.facets.find(f => f.name === facetName);
    
    if (!existingFacet) {
      console.log(`   🆕 ${facetName} - NEW (will be added)`);
      newFacets.push(facetName);
    } else {
      // Check if facet is marked as updated OR if address in Diamond differs from deployment
      const diamondFacet = currentFacets.find(cf => 
        cf.functionSelectors.length > 0 && 
        cf.facetAddress.toLowerCase() !== ethers.ZeroAddress.toLowerCase()
      );
      
      // Get a sample selector from the deployed facet to find it in Diamond
      const deployedFacetContract = await ethers.getContractAt(facetName, existingFacet.address);
      const deployedSelectors = getSelectors(deployedFacetContract);
      
      // Find which facet in Diamond has these selectors
      let addressInDiamond = ethers.ZeroAddress;
      if (deployedSelectors.length > 0) {
        const sampleSelector = deployedSelectors[0];
        for (const cf of currentFacets) {
          if (cf.functionSelectors.includes(sampleSelector)) {
            addressInDiamond = cf.facetAddress;
            break;
          }
        }
      }
      
      // Check if updated flag is set OR if Diamond address differs from deployment
      const addressChanged = addressInDiamond.toLowerCase() !== existingFacet.address.toLowerCase();
      
      if (existingFacet.updated || addressChanged) {
        console.log(`   ✨ ${facetName} - UPDATED (will be replaced)`);
        if (addressChanged) {
          console.log(`      Diamond: ${addressInDiamond}`);
          console.log(`      Deployment: ${existingFacet.address}`);
        }
        updatedFacets.push(facetName);
      } else {
        console.log(`   ✓ ${facetName} - Up to date`);
      }
    }
  }
  
  // Check for facets that exist in deployment but not in code (removed facets)
  const removedFacets: string[] = [];
  console.log(`\n🔍 Checking for removed facets...`);
  console.log(`   Deployed facets: ${deployment.facets.filter(f => !f.deleted).map(f => f.name).join(", ")}`);
  console.log(`   Current facets in code: ${UPGRADEABLE_FACET_NAMES.join(", ")}`);
  
  for (const existingFacet of deployment.facets) {
    // Skip if already marked as deleted in a previous run
    if (existingFacet.deleted) {
      console.log(`   ⏭️  ${existingFacet.name} - Already marked for removal`);
      continue;
    }
    
    if (!UPGRADEABLE_FACET_NAMES.includes(existingFacet.name) && 
        !IMMUTABLE_FACETS.includes(existingFacet.name)) {
      console.log(`   🗑️  ${existingFacet.name} - REMOVED (will be deleted)`);
      removedFacets.push(existingFacet.name);
    }
  }
  
  // Check if any upgrades are needed
  if (updatedFacets.length === 0 && newFacets.length === 0 && removedFacets.length === 0) {
    console.log(`\n✅ All facets are up to date. No upgrade needed!`);
    process.exit(0);
  }
  
  console.log(`\n📊 Upgrade Summary:`);
  console.log(`   New facets: ${newFacets.length}`);
  console.log(`   Updated facets: ${updatedFacets.length}`);
  console.log(`   Removed facets: ${removedFacets.length}`);
  
  // Prepare upgrade: Deploy new/updated facets
  const facetCuts: FacetCut[] = [];
  const newDeployments: FacetDeployment[] = [];
  
  // 1. Deploy and prepare ADD operations for new facets
  for (const facetName of newFacets) {
    const facetDeployment = await deployFacet(facetName, deployerAddress);
    newDeployments.push(facetDeployment);
    
    const facet = await ethers.getContractAt(facetName, facetDeployment.address);
    const selectors = getSelectors(facet);
    
    facetCuts.push({
      facetAddress: facetDeployment.address,
      action: FacetCutAction.Add,
      functionSelectors: selectors
    });
    
    console.log(`   ➕ ADD ${facetName}: ${selectors.length} functions`);
  }
  
  // 2. Prepare REPLACE operations for updated facets
  for (const facetName of updatedFacets) {
    const existingFacet = deployment.facets.find(f => f.name === facetName);
    if (!existingFacet) {
      console.log(`   ⚠️  ${facetName} not found in deployment history`);
      continue;
    }
    
    // Deploy new version of the facet
    const facetDeployment = await deployFacet(facetName, deployerAddress);
    newDeployments.push(facetDeployment);
    
    const facet = await ethers.getContractAt(facetName, facetDeployment.address);
    const selectors = getSelectors(facet);
    
    // Use REPLACE to swap the old implementation with the new one
    facetCuts.push({
      facetAddress: facetDeployment.address,
      action: FacetCutAction.Replace,
      functionSelectors: selectors
    });
    
    console.log(`   ♻️  REPLACE ${facetName}: ${selectors.length} functions`);
  }
  
  // 3. Prepare REMOVE operations for removed facets
  for (const facetName of removedFacets) {
    const existingFacet = deployment.facets.find(f => f.name === facetName);
    if (existingFacet) {
      // Get selectors from the Diamond directly instead of recompiling deleted contracts
      const currentFacetInfo = currentFacets.find(
        f => f.facetAddress.toLowerCase() === existingFacet.address.toLowerCase()
      );
      
      if (currentFacetInfo && currentFacetInfo.functionSelectors.length > 0) {
        facetCuts.push({
          facetAddress: ethers.ZeroAddress, // Must be zero address for Remove action
          action: FacetCutAction.Remove,
          functionSelectors: currentFacetInfo.functionSelectors
        });
        
        console.log(`   ➖ REMOVE ${facetName}: ${currentFacetInfo.functionSelectors.length} functions`);
      } else {
        console.log(`   ⚠️  ${facetName} not found in Diamond (already removed?)`);
      }
    }
  }
  
  // Execute the upgrade
  if (facetCuts.length > 0) {
    console.log(`\n⚙️  Executing Diamond upgrade...`);
    console.log(`   Total operations: ${facetCuts.length}`);
    
    const diamondCut = await ethers.getContractAt("IDiamondCut", deployment.diamond);
    
    try {
      // Execute diamondCut with no initialization
      const tx = await diamondCut.diamondCut(facetCuts, ethers.ZeroAddress, "0x");
      console.log(`   Transaction sent: ${tx.hash}`);
      
      const receipt = await tx.wait();
      console.log(`   ✅ Upgrade successful! Gas used: ${receipt?.gasUsed.toString()}`);
    } catch (error: any) {
      console.error(`\n❌ Upgrade failed: ${error.message}`);
      process.exit(1);
    }
  }
  
  // Verify newly deployed facets
  console.log(`\n🔍 Verifying new facets...`);
  for (const facetDeployment of newDeployments) {
    const verified = await verifyContract(
      facetDeployment.address,
      [],
      network,
      `contracts/facets/${facetDeployment.name}.sol:${facetDeployment.name}`
    );
    facetDeployment.verified = verified;
  }
  
  // Update deployment history
  console.log(`\n💾 Updating deployment records...`);
  
  // Update existing facets or add new ones
  for (const newDeploy of newDeployments) {
    const existingIndex = deployment.facets.findIndex(f => f.name === newDeploy.name);
    if (existingIndex >= 0) {
      // Replace existing facet
      deployment.facets[existingIndex] = newDeploy;
    } else {
      // Add new facet
      deployment.facets.push(newDeploy);
    }
  }
  
  // Remove deleted facets from history
  deployment.facets = deployment.facets.filter(f => !removedFacets.includes(f.name));
  
  // Mark all facets as not updated
  deployment.facets.forEach(f => f.updated = false);
  
  // Save updated deployment history
  history[network] = deployment;
  saveDeploymentHistory(history);
  
  // Update contract hashes
  const hashes = loadContractHashes();
  for (const facetName of UPGRADEABLE_FACET_NAMES) {
    if (newFacets.includes(facetName) || updatedFacets.includes(facetName)) {
      hashes[facetName] = calculateContractHash(facetName);
    }
  }
  // Remove hashes for deleted facets
  removedFacets.forEach(name => delete hashes[name]);
  saveContractHashes(hashes);
  
  // Verify upgrade by reading Diamond state
  console.log(`\n✅ Verifying Diamond state...`);
  const updatedFacetList = await getCurrentFacets(deployment.diamond);
  console.log(`   Total facets after upgrade: ${updatedFacetList.length}`);
  
  // Print final summary
  console.log(`\n\n🎉 Upgrade completed successfully!`);
  console.log(`\n📋 Final State:`);
  console.log(`   Diamond: ${deployment.diamond}`);
  console.log(`   Total facets: ${updatedFacetList.length}`);
  console.log(`\n   Active Facets:`);
  
  for (const facetInfo of updatedFacetList) {
    const facetData = deployment.facets.find(f => f.address.toLowerCase() === facetInfo.facetAddress.toLowerCase());
    const facetName = facetData?.name || "DiamondCutFacet";
    const isNew = newDeployments.find(f => f.address.toLowerCase() === facetInfo.facetAddress.toLowerCase());
    const status = isNew ? "🆕" : "✓";
    const verified = facetData?.verified ? "✅" : (facetName === "DiamondCutFacet" ? "✅" : "⚠️");
    console.log(`   ${status} ${verified} ${facetName}: ${facetInfo.facetAddress} (${facetInfo.functionSelectors.length} functions)`);
  }
  
  console.log(`\n💾 Deployment info saved to: ${DEPLOYMENT_FILE}`);
  console.log(`\n✨ Your Diamond is now up to date!`);
}

// Execute upgrade
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
