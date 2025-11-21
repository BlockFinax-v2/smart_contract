import { ethers } from "hardhat";

async function main() {
  const diamondAddress = "0x65C4ce15C9DFA916db081A41340C3c862F0a3343";
  
  console.log("🔍 Analyzing Current Diamond State...\n");
  
  // Connect to Diamond Loupe
  const diamondLoupe = await ethers.getContractAt("IDiamondLoupe", diamondAddress);
  
  // Get all facets
  const facets = await diamondLoupe.facets();
  
  console.log(`💎 Diamond has ${facets.length} facets:\n`);
  
  for (let i = 0; i < facets.length; i++) {
    const facet = facets[i];
    console.log(`📋 Facet ${i + 1}:`);
    console.log(`   Address: ${facet.facetAddress}`);
    console.log(`   Selectors: ${facet.functionSelectors.length}`);
    
    // Check if this is the LiquidityPoolFacet
    if (facet.facetAddress.toLowerCase() === "0x2a32b6c004A1f71412FaF82c9E65db17232e6E1b".toLowerCase()) {
      console.log("   🎯 This is the current LiquidityPoolFacet");
      console.log("   Selectors:", facet.functionSelectors);
      
      // Try to decode the selectors
      console.log("   Function signatures:");
      for (const selector of facet.functionSelectors) {
        try {
          // We'll just show the selectors as we can't decode them without the ABI
          console.log(`     - ${selector}`);
        } catch (error) {
          console.log(`     - ${selector} (could not decode)`);
        }
      }
    }
    console.log("");
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });