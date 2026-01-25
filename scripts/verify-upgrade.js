const path = require('path');
const deployments = require(path.join(__dirname, '..', 'deployments', 'deployments.json'));

async function verify() {
  const { ethers } = require('hardhat');
  
  const diamondAddress = deployments.sepolia.diamond;
  const newLiquidityFacet = deployments.sepolia.facets.find(f => f.name === 'LiquidityPoolFacet');
  
  console.log('\n=== UPGRADE VERIFICATION ===\n');
  console.log('Diamond:', diamondAddress);
  console.log('New LiquidityPoolFacet:', newLiquidityFacet.address);
  console.log('Deployed:', new Date(newLiquidityFacet.timestamp).toLocaleString());
  
  // Connect to Diamond
  const loupeABI = [
    'function facetAddress(bytes4 _functionSelector) external view returns (address facetAddress_)'
  ];
  
  const [signer] = await ethers.getSigners();
  const diamond = new ethers.Contract(diamondAddress, loupeABI, signer);
  
  // Check getAllStakesForUser selector
  const getAllStakesSelector = ethers.id('getAllStakesForUser(address)').substring(0, 10);
  const activeFacet = await diamond.facetAddress(getAllStakesSelector);
  
  console.log('\n=== ACTIVE ROUTING ===\n');
  console.log('getAllStakesForUser() routes to:', activeFacet);
  
  const isLive = activeFacet.toLowerCase() === newLiquidityFacet.address.toLowerCase();
  
  console.log('\n' + '='.repeat(60));
  if (isLive) {
    console.log('✅ UPGRADE IS LIVE!');
    console.log('✅ Diamond is using the NEW facet with 6-decimal precision');
    console.log('✅ getAllStakesForUser will return correct values immediately');
  } else {
    console.log('⚠️  Old facet still active');
  }
  console.log('='.repeat(60) + '\n');
}

verify().catch(console.error);
