#!/usr/bin/env ts-node

const { ethers } = require("hardhat");
const fs = require("fs");
const path = require("path");

const DEPLOYMENTS_FILE = path.join(__dirname, "..", "deployments", "deployments.json");

async function main() {
  const network = await ethers.provider.getNetwork();
  const networkName = network.name === "unknown" ? "localhost" : network.name;
  
  console.log(`\n🧹 Cleaning up orphaned facet functions on ${networkName}...`);
  console.log(`   Chain ID: ${network.chainId}`);

  // Load deployment info
  const deployments = JSON.parse(fs.readFileSync(DEPLOYMENTS_FILE, "utf8"));
  const deployment = deployments[networkName];

  if (!deployment) {
    console.error(`❌ No deployment found for network: ${networkName}`);
    process.exit(1);
  }

  const diamondAddress = deployment.diamond;
  console.log(`   Diamond: ${diamondAddress}\n`);

  // Get signer
  const [signer] = await ethers.getSigners();
  console.log(`   Signer: ${signer.address}\n`);

  // Get DiamondCut and Loupe facets
  const DiamondCutFacet = await ethers.getContractFactory("DiamondCutFacet");
  const DiamondLoupeFacet = await ethers.getContractFactory("DiamondLoupeFacet");
  
  const diamondCut = DiamondCutFacet.attach(diamondAddress);
  const loupe = DiamondLoupeFacet.attach(diamondAddress);

  // Get all facets
  const facets = await loupe.facets();
  
  console.log("📋 Current facets:");
  for (const facet of facets) {
    console.log(`   ${facet.facetAddress}: ${facet.functionSelectors.length} functions`);
  }
  console.log();

  // Find orphaned facets (not in deployment.json)
  const expectedAddresses = new Set();
  if (deployment.facets) {
    for (const facetName in deployment.facets) {
      const addr = deployment.facets[facetName];
      if (typeof addr === 'string') {
        expectedAddresses.add(addr.toLowerCase());
      }
    }
  }
  
  const orphanedSelectors = [];
  
  for (const facet of facets) {
    const addr = facet.facetAddress.toLowerCase();
    // Skip DiamondCutFacet (always needed)
    if (facet.functionSelectors.some((sel: string) => sel === "0x1f931c1c")) {
      continue;
    }
    
    if (!expectedAddresses.has(addr)) {
      console.log(`⚠️  Found orphaned facet: ${facet.facetAddress}`);
      console.log(`   Functions to remove: ${facet.functionSelectors.length}`);
      orphanedSelectors.push(...facet.functionSelectors);
    }
  }

  if (orphanedSelectors.length === 0) {
    console.log("✅ No orphaned functions found!\n");
    return;
  }

  console.log(`\n🔧 Removing ${orphanedSelectors.length} orphaned function(s)...`);
  
  // FacetCutAction: Add=0, Replace=1, Remove=2
  const FacetCutAction = { Add: 0, Replace: 1, Remove: 2 };

  const cut = [{
    facetAddress: ethers.ZeroAddress,
    action: FacetCutAction.Remove,
    functionSelectors: orphanedSelectors
  }];

  console.log("Selectors to remove:");
  for (const selector of orphanedSelectors) {
    console.log(`   ${selector}`);
  }
  console.log();

  const tx = await diamondCut.diamondCut(cut, ethers.ZeroAddress, "0x");
  console.log(`   Transaction sent: ${tx.hash}`);
  
  const receipt = await tx.wait();
  console.log(`   ✅ Cleanup successful! Gas used: ${receipt.gasUsed.toString()}\n`);

  // Verify
  const facetsAfter = await loupe.facets();
  console.log("📋 Facets after cleanup:");
  for (const facet of facetsAfter) {
    console.log(`   ${facet.facetAddress}: ${facet.functionSelectors.length} functions`);
  }
  
  console.log("\n✅ Diamond is now clean!\n");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
