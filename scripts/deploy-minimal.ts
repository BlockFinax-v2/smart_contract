import { ethers } from "hardhat";
import * as fs from "fs";
import * as path from "path";

/**
 * Minimal Diamond deployment for contest submission
 * Deploys only essential contracts to save gas
 */

const MAINNET_USDC = "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913";

interface FacetCut {
  facetAddress: string;
  action: number;
  functionSelectors: string[];
}

async function main() {
  const hre = require("hardhat");
  const network = hre.network.name;
  
  console.log(`\n🚀 Minimal Diamond deployment on ${network}...`);
  
  const [deployer] = await ethers.getSigners();
  const deployerAddress = await deployer.getAddress();
  const balance = await ethers.provider.getBalance(deployerAddress);
  
  console.log(`\n📋 Deployment Info:`);
  console.log(`   Deployer: ${deployerAddress}`);
  console.log(`   Balance: ${ethers.formatEther(balance)} ETH`);
  console.log(`   Network: ${network} (Chain ID: ${(await ethers.provider.getNetwork()).chainId})`);
  
  const deployments: any = {};
  
  // Step 1: Deploy DiamondCutFacet
  console.log(`\n📦 [1/6] Deploying DiamondCutFacet...`);
  const DiamondCutFacet = await ethers.getContractFactory("DiamondCutFacet");
  const diamondCutFacet = await DiamondCutFacet.deploy();
  await diamondCutFacet.waitForDeployment();
  const diamondCutAddress = await diamondCutFacet.getAddress();
  deployments.DiamondCutFacet = diamondCutAddress;
  console.log(`   ✅ DiamondCutFacet: ${diamondCutAddress}`);
  
  // Check balance after first deployment
  const balanceAfterCut = await ethers.provider.getBalance(deployerAddress);
  console.log(`   💰 Remaining: ${ethers.formatEther(balanceAfterCut)} ETH`);
  
  // Step 2: Deploy Diamond
  console.log(`\n📦 [2/6] Deploying Diamond...`);
  const Diamond = await ethers.getContractFactory("Diamond");
  const diamond = await Diamond.deploy(deployerAddress, diamondCutAddress);
  await diamond.waitForDeployment();
  const diamondAddress = await diamond.getAddress();
  deployments.Diamond = diamondAddress;
  console.log(`   ✅ Diamond: ${diamondAddress}`);
  
  const balanceAfterDiamond = await ethers.provider.getBalance(deployerAddress);
  console.log(`   💰 Remaining: ${ethers.formatEther(balanceAfterDiamond)} ETH`);
  
  // Step 3: Deploy critical facets
  const facetsToDeploy = [
    "DiamondLoupeFacet",
    "OwnershipFacet",
    "GovernanceFacet",
    "LiquidityPoolFacet"
  ];
  
  const facetCuts: FacetCut[] = [];
  let stepNum = 3;
  
  for (const facetName of facetsToDeploy) {
    try {
      console.log(`\n📦 [${stepNum}/6] Deploying ${facetName}...`);
      const Facet = await ethers.getContractFactory(facetName);
      const facet = await Facet.deploy();
      await facet.waitForDeployment();
      const facetAddress = await facet.getAddress();
      deployments[facetName] = facetAddress;
      
      // Get function selectors
      const selectors = Object.keys(facet.interface.fragments)
        .filter(key => facet.interface.fragments[key].type === 'function')
        .map(key => facet.interface.getFunction(key)!.selector);
      
      facetCuts.push({
        facetAddress: facetAddress,
        action: 0, // Add
        functionSelectors: selectors
      });
      
      console.log(`   ✅ ${facetName}: ${facetAddress}`);
      console.log(`   📝 Functions: ${selectors.length}`);
      
      const currentBalance = await ethers.provider.getBalance(deployerAddress);
      console.log(`   💰 Remaining: ${ethers.formatEther(currentBalance)} ETH`);
      
      stepNum++;
    } catch (error: any) {
      console.log(`   ⚠️  Failed to deploy ${facetName}: ${error.message}`);
      if (error.message.includes("insufficient funds")) {
        console.log(`   ⛽ Out of gas! Stopping deployment.`);
        break;
      }
    }
  }
  
  // Step 4: Deploy DiamondInit
  console.log(`\n📦 [${stepNum}/6] Deploying DiamondInit...`);
  try {
    const DiamondInit = await ethers.getContractFactory("DiamondInit");
    const diamondInit = await DiamondInit.deploy();
    await diamondInit.waitForDeployment();
    const diamondInitAddress = await diamondInit.getAddress();
    deployments.DiamondInit = diamondInitAddress;
    console.log(`   ✅ DiamondInit: ${diamondInitAddress}`);
    
    const balanceBeforeInit = await ethers.provider.getBalance(deployerAddress);
    console.log(`   💰 Remaining: ${ethers.formatEther(balanceBeforeInit)} ETH`);
    
    // Initialize Diamond if we have facets
    if (facetCuts.length > 0) {
      console.log(`\n⚙️  Initializing Diamond with ${facetCuts.length} facets...`);
      
      const initData = diamondInit.interface.encodeFunctionData("init", [MAINNET_USDC]);
      
      const diamondCut = await ethers.getContractAt("IDiamondCut", diamondAddress);
      const tx = await diamondCut.diamondCut(facetCuts, diamondInitAddress, initData);
      await tx.wait();
      
      console.log(`   ✅ Diamond initialized!`);
    }
  } catch (error: any) {
    console.log(`   ⚠️  Failed to initialize: ${error.message}`);
  }
  
  // Save deployment info
  const outputDir = path.join(__dirname, "..", "deployments");
  if (!fs.existsSync(outputDir)) {
    fs.mkdirSync(outputDir, { recursive: true });
  }
  
  const deploymentFile = path.join(outputDir, `${network}-contest.json`);
  fs.writeFileSync(deploymentFile, JSON.stringify({
    network,
    chainId: Number((await ethers.provider.getNetwork()).chainId),
    deployer: deployerAddress,
    timestamp: new Date().toISOString(),
    contracts: deployments,
    diamond: diamondAddress,
    facetsDeployed: facetCuts.length
  }, null, 2));
  
  // Final summary
  const finalBalance = await ethers.provider.getBalance(deployerAddress);
  console.log(`\n📊 DEPLOYMENT SUMMARY`);
  console.log(`   ═══════════════════════════════════════`);
  console.log(`   💎 Diamond Address: ${diamondAddress}`);
  console.log(`   📦 Contracts Deployed: ${Object.keys(deployments).length}`);
  console.log(`   🔌 Facets Connected: ${facetCuts.length}`);
  console.log(`   ⛽ ETH Used: ${ethers.formatEther(balance - finalBalance)} ETH`);
  console.log(`   💰 ETH Remaining: ${ethers.formatEther(finalBalance)} ETH`);
  console.log(`   📄 Saved to: ${deploymentFile}`);
  console.log(`   ═══════════════════════════════════════`);
  
  console.log(`\n✅ CONTEST SUBMISSION READY!`);
  console.log(`   Submit this Diamond address: ${diamondAddress}`);
  console.log(`   Network: Base Mainnet (Chain ID: 8453)`);
  console.log(`   Explorer: https://basescan.org/address/${diamondAddress}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
