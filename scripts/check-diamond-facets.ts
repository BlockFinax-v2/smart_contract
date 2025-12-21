/**
 * Check which facet addresses are actually in the Diamond
 * This will show you if the upgrade worked correctly
 */

import { ethers } from "hardhat";
import * as fs from "fs";
import * as path from "path";

const DEPLOYMENTS_DIR = path.join(__dirname, "..", "deployments");
const DEPLOYMENT_FILE = path.join(DEPLOYMENTS_DIR, "deployments.json");

async function main() {
  const hre = require("hardhat");
  const network = hre.network.name;
  
  console.log(`\n🔍 Checking Diamond Facets on ${network}...`);
  
  // Load deployment
  const history = JSON.parse(fs.readFileSync(DEPLOYMENT_FILE, "utf8"));
  const deployment = history[network];
  
  if (!deployment) {
    throw new Error(`No deployment found for network: ${network}`);
  }
  
  const diamondAddress = deployment.diamond;
  console.log(`\n💎 Diamond: ${diamondAddress}`);
  
  // Get facets from Diamond using DiamondLoupe
  const diamondLoupe = await ethers.getContractAt("IDiamondLoupe", diamondAddress);
  const facets = await diamondLoupe.facets();
  
  console.log(`\n📋 Facets in Diamond (${facets.length} total):\n`);
  
  for (const facet of facets) {
    // Find which facet this is from deployment history
    const deployed = deployment.facets.find((f: any) => 
      f.address.toLowerCase() === facet.facetAddress.toLowerCase()
    );
    
    let name = "Unknown";
    let status = "";
    
    if (deployed) {
      name = deployed.name;
      status = " ✅ (from deployment.json)";
    } else if (facet.facetAddress === deployment.diamondCutFacet) {
      name = "DiamondCutFacet";
      status = " ✅ (DiamondCutFacet)";
    } else {
      // Check if it matches any of the old addresses
      const allDeployed = deployment.facets;
      for (const d of allDeployed) {
        if (d.address.toLowerCase() === facet.facetAddress.toLowerCase()) {
          name = d.name + " (OLD)";
          status = " ⚠️  OLD VERSION";
          break;
        }
      }
    }
    
    console.log(`   ${name}:`);
    console.log(`   Address: ${facet.facetAddress}${status}`);
    console.log(`   Functions: ${facet.functionSelectors.length}`);
    console.log(`   Selectors: ${facet.functionSelectors.slice(0, 3).join(", ")}...`);
    console.log();
  }
  
  // Compare with expected deployment
  console.log(`\n📝 Expected Facets from deployment.json:\n`);
  
  for (const facet of deployment.facets) {
    const inDiamond = facets.find((f: any) => 
      f.facetAddress.toLowerCase() === facet.address.toLowerCase()
    );
    
    const status = inDiamond ? "✅ ACTIVE in Diamond" : "❌ NOT in Diamond";
    console.log(`   ${facet.name}: ${facet.address}`);
    console.log(`   ${status}`);
    console.log();
  }
  
  // Show discrepancies
  console.log(`\n🔍 Analysis:\n`);
  
  const expectedAddresses = deployment.facets.map((f: any) => f.address.toLowerCase());
  const actualAddresses = facets
    .filter((f: any) => f.facetAddress !== deployment.diamondCutFacet)
    .map((f: any) => f.facetAddress.toLowerCase());
  
  const missingInDiamond = expectedAddresses.filter(addr => !actualAddresses.includes(addr));
  const unexpectedInDiamond = actualAddresses.filter(addr => !expectedAddresses.includes(addr));
  
  if (missingInDiamond.length > 0) {
    console.log(`   ⚠️  Facets in deployment.json but NOT in Diamond:`);
    for (const addr of missingInDiamond) {
      const facet = deployment.facets.find((f: any) => f.address.toLowerCase() === addr);
      console.log(`      - ${facet.name}: ${facet.address}`);
    }
    console.log();
  }
  
  if (unexpectedInDiamond.length > 0) {
    console.log(`   ⚠️  Facets in Diamond but NOT in deployment.json (OLD versions?):`);
    for (const addr of unexpectedInDiamond) {
      console.log(`      - ${addr}`);
    }
    console.log();
  }
  
  if (missingInDiamond.length === 0 && unexpectedInDiamond.length === 0) {
    console.log(`   ✅ All facets match! Diamond is correctly upgraded.`);
  } else {
    console.log(`   ❌ Mismatch detected! The upgrade.ts script may not have worked.`);
    console.log(`\n💡 Solution: Run the upgrade-reorganized-facets.ts script instead.`);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
