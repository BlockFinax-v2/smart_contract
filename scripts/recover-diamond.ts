#!/usr/bin/env ts-node

const { ethers } = require("hardhat");
const fs = require("fs");
const path = require("path");

const DEPLOYMENTS_FILE = path.join(__dirname, "..", "deployments", "deployments.json");

// FacetCutAction: Add=0, Replace=1, Remove=2
const FacetCutAction = { Add: 0, Replace: 1, Remove: 2 };

async function main() {
  const network = await ethers.provider.getNetwork();
  const networkName = network.name === "unknown" ? "localhost" : network.name;
  
  console.log(`\n🔧 EMERGENCY: Recovering Diamond facets on ${networkName}...`);
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

  const [signer] = await ethers.getSigners();
  console.log(`   Signer: ${signer.address}\n`);

  // Deploy all facets fresh
  console.log("📦 Deploying facets...\n");

  const facets = [
    "DiamondLoupeFacet",
    "OwnershipFacet",
    "AddressLinkingFacet",
    "LiquidityPoolFacet",
    "GovernanceFacet"
  ];

  const facetCuts = [];

  for (const facetName of facets) {
    console.log(`   Deploying ${facetName}...`);
    const FacetFactory = await ethers.getContractFactory(facetName);
    const facet = await FacetFactory.deploy();
    await facet.waitForDeployment();
    
    const facetAddress = await facet.getAddress();
    console.log(`   ✅ ${facetName}: ${facetAddress}`);

    // Get function selectors
    const selectors = [];
    for (const fragment of Object.values(facet.interface.fragments)) {
      if (fragment.type === 'function') {
        selectors.push(facet.interface.getFunction(fragment.name).selector);
      }
    }

    facetCuts.push({
      facetAddress: facetAddress,
      action: FacetCutAction.Add,
      functionSelectors: selectors
    });

    console.log(`   Selectors: ${selectors.length} functions\n`);
  }

  // Execute diamond cut
  console.log("✂️  Executing Diamond Cut to add all facets...\n");
  
  const DiamondCutFacet = await ethers.getContractFactory("DiamondCutFacet");
  const diamondCut = DiamondCutFacet.attach(diamondAddress);

  const tx = await diamondCut.diamondCut(facetCuts, ethers.ZeroAddress, "0x");
  console.log(`   Transaction sent: ${tx.hash}`);
  
  const receipt = await tx.wait();
  console.log(`   ✅ Diamond recovered! Gas used: ${receipt.gasUsed.toString()}\n`);

  console.log("✅ All facets have been re-added to the Diamond!\n");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Recovery failed:", error);
    process.exit(1);
  });
