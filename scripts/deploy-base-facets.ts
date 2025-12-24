/**
 * Deploy updated facets on Base Sepolia
 */

import { ethers } from "hardhat";
import * as fs from "fs";
import * as path from "path";

const DEPLOYMENTS_DIR = path.join(__dirname, "..", "deployments");
const DEPLOYMENT_FILE = path.join(DEPLOYMENTS_DIR, "deployments.json");

async function main() {
  const hre = require("hardhat");
  const network = hre.network.name;
  
  console.log(`\n🚀 Deploying Updated Facets on ${network}...`);
  
  const [deployer] = await ethers.getSigners();
  const deployerAddress = await deployer.getAddress();
  const balance = await ethers.provider.getBalance(deployerAddress);
  
  console.log(`   Deployer: ${deployerAddress}`);
  console.log(`   Balance: ${ethers.formatEther(balance)} ETH\n`);
  
  // Load deployment history
  const history = JSON.parse(fs.readFileSync(DEPLOYMENT_FILE, "utf8"));
  const deployment = history[network];
  
  if (!deployment) {
    throw new Error(`No deployment found for network: ${network}`);
  }
  
  console.log(`   Diamond: ${deployment.diamond}\n`);
  
  // Deploy GovernanceFacet
  console.log(`📦 Deploying GovernanceFacet...`);
  const GovernanceFacet = await ethers.getContractFactory("GovernanceFacet");
  const governanceFacet = await GovernanceFacet.deploy();
  await governanceFacet.waitForDeployment();
  const governanceAddress = await governanceFacet.getAddress();
  const governanceTx = governanceFacet.deploymentTransaction();
  console.log(`✅ GovernanceFacet deployed: ${governanceAddress}`);
  
  // Deploy LiquidityPoolFacet
  console.log(`\n📦 Deploying LiquidityPoolFacet...`);
  const LiquidityPoolFacet = await ethers.getContractFactory("LiquidityPoolFacet");
  const liquidityPoolFacet = await LiquidityPoolFacet.deploy();
  await liquidityPoolFacet.waitForDeployment();
  const liquidityPoolAddress = await liquidityPoolFacet.getAddress();
  const liquidityPoolTx = liquidityPoolFacet.deploymentTransaction();
  console.log(`✅ LiquidityPoolFacet deployed: ${liquidityPoolAddress}`);
  
  // Update deployment history
  const facetIndex1 = deployment.facets.findIndex((f: any) => f.name === "GovernanceFacet");
  const facetIndex2 = deployment.facets.findIndex((f: any) => f.name === "LiquidityPoolFacet");
  
  if (facetIndex1 >= 0) {
    deployment.facets[facetIndex1] = {
      name: "GovernanceFacet",
      address: governanceAddress,
      txHash: governanceTx?.hash || "",
      deployer: deployerAddress,
      timestamp: Date.now(),
      verified: false,
      updated: true,
      contentHash: "new_deployment_base_sepolia"
    };
  }
  
  if (facetIndex2 >= 0) {
    deployment.facets[facetIndex2] = {
      name: "LiquidityPoolFacet",
      address: liquidityPoolAddress,
      txHash: liquidityPoolTx?.hash || "",
      deployer: deployerAddress,
      timestamp: Date.now(),
      verified: false,
      updated: true,
      contentHash: "new_deployment_base_sepolia"
    };
  }
  
  // Save deployment
  history[network] = deployment;
  fs.writeFileSync(DEPLOYMENT_FILE, JSON.stringify(history, null, 2));
  
  console.log(`\n✅ Facets deployed and saved to deployment history!`);
  console.log(`\n📋 Summary:`);
  console.log(`   GovernanceFacet: ${governanceAddress}`);
  console.log(`   LiquidityPoolFacet: ${liquidityPoolAddress}`);
  console.log(`\n🔄 Next: Run upgrade-reorganized-facets.ts on ${network}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
