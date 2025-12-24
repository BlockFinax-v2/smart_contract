/**
 * Upgrade Diamond contract with reorganized facets
 * - Updates GovernanceFacet with token management functions
 * - Updates LiquidityPoolFacet with staking functions only (admin functions removed)
 * 
 * Usage: npx hardhat run scripts/upgrade-facets.ts --network liskSepolia
 */

import { ethers } from "hardhat";

// Diamond contract address
const DIAMOND_ADDRESS = "0xE133CD2eE4d835AC202942Baff2B1D6d47862d34";

// Token addresses on Lisk Sepolia
const TOKENS = {
  USDC: "0x0E82fDDAd51cc3ac12b69761C45bBCB9A2Bf3C83",
  USDT: "0x7E2db2968f80E5cACFB0bd93C724d0447a6b6D8c",
  DAI: "0x4F96Fe3b7A6Cf9725f59d353F723c1bDb64CA6Aa",
};

// FacetCutAction enum
const FacetCutAction = {
  Add: 0,
  Replace: 1,
  Remove: 2
};

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("\n🚀 Upgrading Diamond with Reorganized Facets");
  console.log("Deployer:", deployer.address);
  console.log("Diamond:", DIAMOND_ADDRESS);
  console.log("Network:", (await ethers.provider.getNetwork()).name);

  // Get current facets
  console.log("\n📋 Current Diamond State:");
  const diamondLoupe = await ethers.getContractAt("IDiamondLoupe", DIAMOND_ADDRESS);
  const currentFacets = await diamondLoupe.facets();
  console.log(`   Total facets: ${currentFacets.length}`);
  for (const facet of currentFacets) {
    console.log(`   - ${facet.facetAddress}: ${facet.functionSelectors.length} functions`);
  }

  // Step 1: Deploy new GovernanceFacet with token management
  console.log("\n📦 Step 1: Deploying updated GovernanceFacet...");
  const GovernanceFacet = await ethers.getContractFactory("GovernanceFacet");
  const governanceFacet = await GovernanceFacet.deploy();
  await governanceFacet.waitForDeployment();
  const governanceAddress = await governanceFacet.getAddress();
  console.log("✅ GovernanceFacet deployed to:", governanceAddress);

  // Step 2: Deploy new LiquidityPoolFacet without admin functions
  console.log("\n📦 Step 2: Deploying updated LiquidityPoolFacet...");
  const LiquidityPoolFacet = await ethers.getContractFactory("LiquidityPoolFacet");
  const liquidityPoolFacet = await LiquidityPoolFacet.deploy();
  await liquidityPoolFacet.waitForDeployment();
  const liquidityPoolAddress = await liquidityPoolFacet.getAddress();
  console.log("✅ LiquidityPoolFacet deployed to:", liquidityPoolAddress);

  // Step 3: Get new GovernanceFacet selectors (token management functions)
  console.log("\n🔍 Step 3: Getting new GovernanceFacet selectors...");
  const newGovernanceSelectors = [
    governanceFacet.interface.getFunction("addSupportedStakingToken").selector,
    governanceFacet.interface.getFunction("removeSupportedStakingToken").selector,
    governanceFacet.interface.getFunction("getSupportedStakingTokens").selector,
    governanceFacet.interface.getFunction("isTokenSupported").selector,
    governanceFacet.interface.getFunction("getTotalStakedForToken").selector,
  ];
  console.log(`   Adding ${newGovernanceSelectors.length} new functions to GovernanceFacet:`);
  newGovernanceSelectors.forEach((sel, i) => console.log(`   ${i + 1}. ${sel}`));

  // Step 4: Get all LiquidityPoolFacet selectors to replace
  console.log("\n🔍 Step 4: Getting LiquidityPoolFacet selectors...");
  const liquidityPoolSelectors = Object.values(liquidityPoolFacet.interface.fragments)
    .filter((f: any) => f.type === "function")
    .map((f: any) => liquidityPoolFacet.interface.getFunction(f.name).selector);
  console.log(`   Replacing ${liquidityPoolSelectors.length} functions in LiquidityPoolFacet`);

  // Step 5: Prepare diamond cut
  console.log("\n💎 Step 5: Preparing diamond cut...");
  const cuts = [
    {
      facetAddress: governanceAddress,
      action: FacetCutAction.Add,
      functionSelectors: newGovernanceSelectors
    },
    {
      facetAddress: liquidityPoolAddress,
      action: FacetCutAction.Replace,
      functionSelectors: liquidityPoolSelectors
    }
  ];

  console.log("\nDiamond Cut Plan:");
  console.log(`   1. ADD ${newGovernanceSelectors.length} functions to GovernanceFacet`);
  console.log(`   2. REPLACE ${liquidityPoolSelectors.length} functions in LiquidityPoolFacet`);

  // Step 6: Execute diamond cut
  console.log("\n✂️ Step 6: Executing diamond cut...");
  const diamondCut = await ethers.getContractAt("IDiamondCut", DIAMOND_ADDRESS);
  const tx = await diamondCut.diamondCut(cuts, ethers.ZeroAddress, "0x");
  console.log("📤 Transaction sent:", tx.hash);
  
  const receipt = await tx.wait();
  console.log("✅ Diamond cut executed! (Block:", receipt?.blockNumber + ")");

  // Step 7: Verify upgrade
  console.log("\n🔍 Step 7: Verifying upgrade...");
  const updatedFacets = await diamondLoupe.facets();
  console.log(`   Total facets after upgrade: ${updatedFacets.length}`);
  for (const facet of updatedFacets) {
    console.log(`   - ${facet.facetAddress}: ${facet.functionSelectors.length} functions`);
  }

  // Step 8: Add supported tokens
  console.log("\n🪙 Step 8: Adding supported tokens...");
  const governance = await ethers.getContractAt("GovernanceFacet", DIAMOND_ADDRESS);
  
  for (const [symbol, address] of Object.entries(TOKENS)) {
    console.log(`\n   Checking ${symbol} (${address})...`);
    const isSupported = await governance.isTokenSupported(address);
    
    if (!isSupported) {
      console.log(`   Adding ${symbol}...`);
      const addTx = await governance.addSupportedStakingToken(address);
      await addTx.wait();
      console.log(`   ✅ ${symbol} added`);
    } else {
      console.log(`   ℹ️  ${symbol} already supported`);
    }
  }

  // Step 9: Final verification
  console.log("\n\n🎉 Final Verification:");
  const supportedTokens = await governance.getSupportedStakingTokens();
  console.log(`   Total supported tokens: ${supportedTokens.length}`);
  supportedTokens.forEach((addr, i) => {
    const symbol = Object.entries(TOKENS).find(([_, a]) => a.toLowerCase() === addr.toLowerCase())?.[0] || "Unknown";
    console.log(`   ${i + 1}. ${symbol}: ${addr}`);
  });

  // Test token support check
  console.log("\n📝 Testing token support checks:");
  for (const [symbol, address] of Object.entries(TOKENS)) {
    const isSupported = await governance.isTokenSupported(address);
    const totalStaked = await governance.getTotalStakedForToken(address);
    console.log(`   ${symbol}: Supported=${isSupported}, TotalStaked=${ethers.formatUnits(totalStaked, 18)} tokens`);
  }

  console.log("\n✅ Facet upgrade complete!");
  console.log("\n💡 Architecture Changes:");
  console.log("   - GovernanceFacet: Now has token management functions");
  console.log("   - LiquidityPoolFacet: Staking logic only (admin functions removed)");
  console.log("\n💡 Your mobile app will now support:");
  console.log("   - Staking USDC, USDT, and DAI");
  console.log("   - Cross-token voting power aggregation");
  console.log("   - Per-token rewards tracking");
  console.log("\n🔄 Refresh your app to see the changes!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("\n❌ Error:", error);
    process.exit(1);
  });
/**
 * Upgrade Diamond contract with reorganized facets
 * - Updates GovernanceFacet with token management functions
 * - Updates LiquidityPoolFacet with staking functions only (admin functions removed)
 * 
 * Usage: npx hardhat run scripts/upgrade-facets.ts --network liskSepolia
 */

import { ethers } from "hardhat";

// Diamond contract address
const DIAMOND_ADDRESS = "0xE133CD2eE4d835AC202942Baff2B1D6d47862d34";

// Token addresses on Lisk Sepolia
const TOKENS = {
  USDC: "0x0E82fDDAd51cc3ac12b69761C45bBCB9A2Bf3C83",
  USDT: "0x7E2db2968f80E5cACFB0bd93C724d0447a6b6D8c",
  DAI: "0x4F96Fe3b7A6Cf9725f59d353F723c1bDb64CA6Aa",
};

// FacetCutAction enum
const FacetCutAction = {
  Add: 0,
  Replace: 1,
  Remove: 2
};

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("\n🚀 Upgrading Diamond with Reorganized Facets");
  console.log("Deployer:", deployer.address);
  console.log("Diamond:", DIAMOND_ADDRESS);
  console.log("Network:", (await ethers.provider.getNetwork()).name);

  // Get current facets
  console.log("\n📋 Current Diamond State:");
  const diamondLoupe = await ethers.getContractAt("IDiamondLoupe", DIAMOND_ADDRESS);
  const currentFacets = await diamondLoupe.facets();
  console.log(`   Total facets: ${currentFacets.length}`);
  for (const facet of currentFacets) {
    console.log(`   - ${facet.facetAddress}: ${facet.functionSelectors.length} functions`);
  }

  // Step 1: Deploy new GovernanceFacet with token management
  console.log("\n📦 Step 1: Deploying updated GovernanceFacet...");
  const GovernanceFacet = await ethers.getContractFactory("GovernanceFacet");
  const governanceFacet = await GovernanceFacet.deploy();
  await governanceFacet.waitForDeployment();
  const governanceAddress = await governanceFacet.getAddress();
  console.log("✅ GovernanceFacet deployed to:", governanceAddress);

  // Step 2: Deploy new LiquidityPoolFacet without admin functions
  console.log("\n📦 Step 2: Deploying updated LiquidityPoolFacet...");
  const LiquidityPoolFacet = await ethers.getContractFactory("LiquidityPoolFacet");
  const liquidityPoolFacet = await LiquidityPoolFacet.deploy();
  await liquidityPoolFacet.waitForDeployment();
  const liquidityPoolAddress = await liquidityPoolFacet.getAddress();
  console.log("✅ LiquidityPoolFacet deployed to:", liquidityPoolAddress);

  // Step 3: Get new GovernanceFacet selectors (token management functions)
  console.log("\n🔍 Step 3: Getting new GovernanceFacet selectors...");
  const newGovernanceSelectors = [
    governanceFacet.interface.getFunction("addSupportedStakingToken").selector,
    governanceFacet.interface.getFunction("removeSupportedStakingToken").selector,
    governanceFacet.interface.getFunction("getSupportedStakingTokens").selector,
    governanceFacet.interface.getFunction("isTokenSupported").selector,
    governanceFacet.interface.getFunction("getTotalStakedForToken").selector,
  ];
  console.log(`   Adding ${newGovernanceSelectors.length} new functions to GovernanceFacet:`);
  newGovernanceSelectors.forEach((sel, i) => console.log(`   ${i + 1}. ${sel}`));

  // Step 4: Get all LiquidityPoolFacet selectors to replace
  console.log("\n🔍 Step 4: Getting LiquidityPoolFacet selectors...");
  const liquidityPoolSelectors = Object.values(liquidityPoolFacet.interface.fragments)
    .filter((f: any) => f.type === "function")
    .map((f: any) => liquidityPoolFacet.interface.getFunction(f.name).selector);
  console.log(`   Replacing ${liquidityPoolSelectors.length} functions in LiquidityPoolFacet`);

  // Step 5: Prepare diamond cut
  console.log("\n💎 Step 5: Preparing diamond cut...");
  const cuts = [
    {
      facetAddress: governanceAddress,
      action: FacetCutAction.Add,
      functionSelectors: newGovernanceSelectors
    },
    {
      facetAddress: liquidityPoolAddress,
      action: FacetCutAction.Replace,
      functionSelectors: liquidityPoolSelectors
    }
  ];

  console.log("\nDiamond Cut Plan:");
  console.log(`   1. ADD ${newGovernanceSelectors.length} functions to GovernanceFacet`);
  console.log(`   2. REPLACE ${liquidityPoolSelectors.length} functions in LiquidityPoolFacet`);

  // Step 6: Execute diamond cut
  console.log("\n✂️ Step 6: Executing diamond cut...");
  const diamondCut = await ethers.getContractAt("IDiamondCut", DIAMOND_ADDRESS);
  const tx = await diamondCut.diamondCut(cuts, ethers.ZeroAddress, "0x");
  console.log("📤 Transaction sent:", tx.hash);
  
  const receipt = await tx.wait();
  console.log("✅ Diamond cut executed! (Block:", receipt?.blockNumber + ")");

  // Step 7: Verify upgrade
  console.log("\n🔍 Step 7: Verifying upgrade...");
  const updatedFacets = await diamondLoupe.facets();
  console.log(`   Total facets after upgrade: ${updatedFacets.length}`);
  for (const facet of updatedFacets) {
    console.log(`   - ${facet.facetAddress}: ${facet.functionSelectors.length} functions`);
  }

  // Step 8: Add supported tokens
  console.log("\n🪙 Step 8: Adding supported tokens...");
  const governance = await ethers.getContractAt("GovernanceFacet", DIAMOND_ADDRESS);
  
  for (const [symbol, address] of Object.entries(TOKENS)) {
    console.log(`\n   Checking ${symbol} (${address})...`);
    const isSupported = await governance.isTokenSupported(address);
    
    if (!isSupported) {
      console.log(`   Adding ${symbol}...`);
      const addTx = await governance.addSupportedStakingToken(address);
      await addTx.wait();
      console.log(`   ✅ ${symbol} added`);
    } else {
      console.log(`   ℹ️  ${symbol} already supported`);
    }
  }

  // Step 9: Final verification
  console.log("\n\n🎉 Final Verification:");
  const supportedTokens = await governance.getSupportedStakingTokens();
  console.log(`   Total supported tokens: ${supportedTokens.length}`);
  supportedTokens.forEach((addr, i) => {
    const symbol = Object.entries(TOKENS).find(([_, a]) => a.toLowerCase() === addr.toLowerCase())?.[0] || "Unknown";
    console.log(`   ${i + 1}. ${symbol}: ${addr}`);
  });

  // Test token support check
  console.log("\n📝 Testing token support checks:");
  for (const [symbol, address] of Object.entries(TOKENS)) {
    const isSupported = await governance.isTokenSupported(address);
    const totalStaked = await governance.getTotalStakedForToken(address);
    console.log(`   ${symbol}: Supported=${isSupported}, TotalStaked=${ethers.formatUnits(totalStaked, 18)} tokens`);
  }

  console.log("\n✅ Facet upgrade complete!");
  console.log("\n💡 Architecture Changes:");
  console.log("   - GovernanceFacet: Now has token management functions");
  console.log("   - LiquidityPoolFacet: Staking logic only (admin functions removed)");
  console.log("\n💡 Your mobile app will now support:");
  console.log("   - Staking USDC, USDT, and DAI");
  console.log("   - Cross-token voting power aggregation");
  console.log("   - Per-token rewards tracking");
  console.log("\n🔄 Refresh your app to see the changes!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("\n❌ Error:", error);
    process.exit(1);
  });
