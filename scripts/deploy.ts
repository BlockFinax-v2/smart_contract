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

// FacetCutAction enum
enum FacetCutAction {
  Add = 0,
  Replace = 1,
  Remove = 2
}

// Deployment paths
const DEPLOYMENTS_DIR = path.join(__dirname, "..", "deployments");
const DEPLOYMENT_FILE = path.join(DEPLOYMENTS_DIR, "deployments.json");
const HASHES_FILE = path.join(DEPLOYMENTS_DIR, "contract-hashes.json");

/**
 * Automatically discover all facets from the facets directory
 * Excludes DiamondCutFacet which is handled separately
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
    .filter(file => file !== "DiamondCutFacet.sol") // Exclude DiamondCutFacet
    .map(file => file.replace(".sol", ""))
    .sort(); // Sort for consistent ordering
  
  return facets;
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
    return {};
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
 * Main deployment function
 */
async function main() {
  // Get network name from hardhat runtime environment
  const hre = require("hardhat");
  const network = hre.network.name;
  
  console.log(`\n🚀 Starting Diamond deployment on ${network}...`);
  
  // Discover all facets dynamically
  const FACET_NAMES = discoverFacets();
  
  // Get deployer
  const [deployer] = await ethers.getSigners();
  const deployerAddress = await deployer.getAddress();
  const chainId = (await ethers.provider.getNetwork()).chainId;
  
  console.log(`\n📋 Deployment Info:`);
  console.log(`   Network: ${network}`);
  console.log(`   Chain ID: ${chainId}`);
  console.log(`   Deployer: ${deployerAddress}`);
  console.log(`   Balance: ${ethers.formatEther(await ethers.provider.getBalance(deployerAddress))} ETH`);
  
  // Load deployment history
  const history = loadDeploymentHistory();
  const previousDeployment = history[network];
  
  // Check which contracts need deployment
  console.log(`\n🔍 Checking for updated contracts...`);
  const updatedFacets: string[] = [];
  
  // Check DiamondCutFacet
  const diamondCutFacetUpdated = isContractUpdated("DiamondCutFacet");
  if (diamondCutFacetUpdated) {
    console.log(`   ✨ DiamondCutFacet - UPDATED`);
    updatedFacets.push("DiamondCutFacet");
  } else {
    console.log(`   ✓ DiamondCutFacet - Up to date`);
  }
  
  // Log discovered facets
  console.log(`\n📂 Discovered ${FACET_NAMES.length} facets: ${FACET_NAMES.join(", ")}`);
  
  // Check for deleted facets
  if (previousDeployment) {
    const deletedFacets = previousDeployment.facets
      .filter(f => !FACET_NAMES.includes(f.name))
      .map(f => f.name);
    
    if (deletedFacets.length > 0) {
      console.log(`\n🗑️  Deleted facets detected: ${deletedFacets.join(", ")}`);
      console.log(`   These will be removed from the Diamond via upgrade script`);
    }
  }
  
  for (const facetName of FACET_NAMES) {
    const isUpdated = isContractUpdated(facetName);
    if (isUpdated) {
      console.log(`   ✨ ${facetName} - UPDATED`);
      updatedFacets.push(facetName);
    } else {
      console.log(`   ✓ ${facetName} - Up to date`);
    }
  }
  
  const diamondUpdated = isContractUpdated("Diamond");
  const diamondInitUpdated = isContractUpdated("DiamondInit");
  
  if (diamondUpdated) console.log(`   ✨ Diamond - UPDATED`);
  if (diamondInitUpdated) console.log(`   ✨ DiamondInit - UPDATED`);
  
  // Deploy or reuse MockUSDC (only for testnet)
  let mockUSDC: any;
  let mockUSDCAddress = "";
  
  if (network.includes("Sepolia") || network.includes("testnet")) {
    if (previousDeployment?.mockUSDC && !isContractUpdated("MockERC20")) {
      mockUSDCAddress = previousDeployment.mockUSDC;
      console.log(`\n♻️  Reusing MockUSDC at: ${mockUSDCAddress}`);
    } else {
      console.log(`\n📦 Deploying MockUSDC...`);
      const MockERC20 = await ethers.getContractFactory("MockERC20");
      mockUSDC = await MockERC20.deploy("Mock USDC", "USDC", 18);
      await mockUSDC.waitForDeployment();
      mockUSDCAddress = await mockUSDC.getAddress();
      console.log(`✅ MockUSDC deployed at: ${mockUSDCAddress}`);
    }
  } else {
    // For mainnet, you should use actual USDC address
    console.log(`\n⚠️  MAINNET: Please set the actual USDC token address in the code!`);
    process.exit(1);
  }
  
  // Deploy DiamondCutFacet first (needed for Diamond constructor)
  let diamondCutFacetAddress = "";
  
  if (diamondCutFacetUpdated || !previousDeployment) {
    const deployment = await deployFacet("DiamondCutFacet", deployerAddress);
    diamondCutFacetAddress = deployment.address;
  } else {
    diamondCutFacetAddress = previousDeployment.diamondCutFacet;
    console.log(`\n♻️  Reusing DiamondCutFacet at: ${diamondCutFacetAddress}`);
  }
  
  // Deploy remaining facets
  const facetDeployments: FacetDeployment[] = [];
  
  // Use the same discovered facets
  for (const facetName of FACET_NAMES) {
    if (updatedFacets.includes(facetName) || !previousDeployment) {
      // Deploy new facet
      const deployment = await deployFacet(facetName, deployerAddress);
      facetDeployments.push(deployment);
    } else {
      // Reuse existing facet
      const existing = previousDeployment.facets.find(f => f.name === facetName);
      if (existing) {
        console.log(`\n♻️  Reusing ${facetName} at: ${existing.address}`);
        facetDeployments.push({
          ...existing,
          updated: false
        });
      } else {
        // Fallback: deploy if not found in history
        const deployment = await deployFacet(facetName, deployerAddress);
        facetDeployments.push(deployment);
      }
    }
  }
  
  // Deploy Diamond (if new deployment or Diamond contract updated)
  let diamondAddress = "";
  
  if (!previousDeployment || diamondUpdated) {
    console.log(`\n📦 Deploying Diamond...`);
    const Diamond = await ethers.getContractFactory("Diamond");
    const diamond = await Diamond.deploy(deployerAddress, diamondCutFacetAddress);
    await diamond.waitForDeployment();
    diamondAddress = await diamond.getAddress();
    console.log(`✅ Diamond deployed at: ${diamondAddress}`);
  } else {
    diamondAddress = previousDeployment.diamond;
    console.log(`\n♻️  Reusing Diamond at: ${diamondAddress}`);
  }
  
  // Deploy DiamondInit (if new deployment or DiamondInit updated)
  let diamondInitAddress = "";
  
  if (!previousDeployment || diamondInitUpdated || diamondUpdated) {
    console.log(`\n📦 Deploying DiamondInit...`);
    const DiamondInit = await ethers.getContractFactory("DiamondInit");
    const diamondInit = await DiamondInit.deploy();
    await diamondInit.waitForDeployment();
    diamondInitAddress = await diamondInit.getAddress();
    console.log(`✅ DiamondInit deployed at: ${diamondInitAddress}`);
  } else {
    diamondInitAddress = previousDeployment.diamondInit;
    console.log(`\n♻️  Reusing DiamondInit at: ${diamondInitAddress}`);
  }
  
  // Only initialize if new deployment
  if (!previousDeployment || diamondUpdated) {
    console.log(`\n⚙️  Initializing Diamond...`);
    
    // Prepare diamond cut (DiamondCutFacet already added in constructor)
    const cut = [];
    
    for (const deployment of facetDeployments) {
      console.log(`   Getting selectors for ${deployment.name}...`);
      const FacetFactory = await ethers.getContractFactory(deployment.name);
      const facet = FacetFactory.attach(deployment.address);
      
      console.log(`   - Contract attached: ${facet.target}`);
      console.log(`   - Has interface: ${!!facet.interface}`);
      console.log(`   - Interface fragments: ${facet.interface ? facet.interface.fragments.length : 0}`);
      console.log(`   - Interface format: ${facet.interface ? facet.interface.format() : 'N/A'}`);
      
      const selectors = getSelectors(facet);
      
      console.log(`   - Selectors count: ${selectors.length}`);
      
      cut.push({
        facetAddress: deployment.address,
        action: FacetCutAction.Add,
        functionSelectors: selectors
      });
    }
    
    // Prepare init data
    const DiamondInitFactory = await ethers.getContractFactory("DiamondInit");
    const diamondInit = DiamondInitFactory.attach(diamondInitAddress);
    const initData = diamondInit.interface.encodeFunctionData("init", [
      mockUSDCAddress,
      ethers.parseEther("100"), // minimumStake
      1200, // initialApr: 12%
      7 * 24 * 60 * 60, // minLockDuration: 7 days
      50, // aprReductionPerThousand: 0.5%
      10 // emergencyWithdrawPenalty: 10%
    ]);
    
    // Execute diamond cut
    const diamondCut = await ethers.getContractAt("IDiamondCut", diamondAddress);
    const tx = await diamondCut.diamondCut(cut, diamondInitAddress, initData);
    await tx.wait();
    
    console.log(`✅ Diamond initialized successfully!`);
  }
  
  // Verify contracts
  console.log(`\n🔍 Starting contract verification...`);
  
  // Verify DiamondCutFacet
  if (diamondCutFacetUpdated) {
    await verifyContract(
      diamondCutFacetAddress,
      [],
      network,
      "contracts/facets/DiamondCutFacet.sol:DiamondCutFacet"
    );
  }
  
  // Verify other facets
  for (const deployment of facetDeployments) {
    if (deployment.updated) {
      const verified = await verifyContract(
        deployment.address,
        [],
        network,
        `contracts/facets/${deployment.name}.sol:${deployment.name}`
      );
      deployment.verified = verified;
    }
  }
  
  // Verify Diamond
  if (!previousDeployment || diamondUpdated) {
    await verifyContract(
      diamondAddress,
      [deployerAddress, diamondCutFacetAddress],
      network,
      "contracts/Diamond.sol:Diamond"
    );
  }
  
  // Verify DiamondInit
  if (!previousDeployment || diamondInitUpdated) {
    await verifyContract(
      diamondInitAddress,
      [],
      network,
      "contracts/DiamondInit.sol:DiamondInit"
    );
  }
  
  // Verify MockUSDC (if newly deployed)
  if (mockUSDC) {
    await verifyContract(
      mockUSDCAddress,
      ["Mock USDC", "USDC", 18],
      network,
      "contracts/mocks/MockERC20.sol:MockERC20"
    );
  }
  
  // Save deployment info
  // Include deleted facets (marked for removal in upgrade script)
  const allFacets = [...facetDeployments];
  
  if (previousDeployment) {
    const deletedFacets = previousDeployment.facets
      .filter(f => !FACET_NAMES.includes(f.name))
      .map(f => ({ ...f, deleted: true }));
    
    allFacets.push(...deletedFacets);
  }
  
  const deployment: DiamondDeployment = {
    diamond: diamondAddress,
    diamondInit: diamondInitAddress,
    diamondCutFacet: diamondCutFacetAddress,
    mockUSDC: mockUSDCAddress || undefined,
    facets: allFacets,
    network: network,
    chainId: Number(chainId),
    deployer: deployerAddress,
    deployedAt: Date.now()
  };
  
  history[network] = deployment;
  saveDeploymentHistory(history);
  
  // Update contract hashes
  const hashes = loadContractHashes();
  hashes["DiamondCutFacet"] = calculateContractHash("DiamondCutFacet");
  // Use the same discovered facets
  for (const facetName of FACET_NAMES) {
    hashes[facetName] = calculateContractHash(facetName);
  }
  hashes["Diamond"] = calculateContractHash("Diamond");
  hashes["DiamondInit"] = calculateContractHash("DiamondInit");
  hashes["MockERC20"] = calculateContractHash("MockERC20");
  saveContractHashes(hashes);
  
  // Print summary
  console.log(`\n\n✅ Deployment completed successfully!`);
  console.log(`\n📋 Deployment Summary:`);
  console.log(`   Diamond: ${diamondAddress}`);
  console.log(`   DiamondCutFacet: ${diamondCutFacetAddress}`);
  console.log(`   DiamondInit: ${diamondInitAddress}`);
  if (mockUSDCAddress) {
    console.log(`   MockUSDC: ${mockUSDCAddress}`);
  }
  console.log(`\n   Facets:`);
  for (const facet of facetDeployments) {
    const status = facet.updated ? "🆕 NEW" : "♻️  REUSED";
    const verified = facet.verified ? "✅" : "⚠️";
    console.log(`   ${status} ${verified} ${facet.name}: ${facet.address}`);
  }
  
  console.log(`\n💾 Deployment info saved to: ${DEPLOYMENT_FILE}`);
  console.log(`\n🎉 Ready for upgrade! Run 'npx ts-node scripts/upgrade.ts ${network}' to upgrade updated facets.`);
}

// Execute deployment
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
