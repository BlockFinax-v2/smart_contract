const { ethers } = require("hardhat");

const FacetCutAction = { Add: 0, Replace: 1, Remove: 2 };

function getSelectors(contract) {
  const selectors = [];
  for (const fragment of contract.interface.fragments) {
    if (fragment.type === "function") {
      try {
        const funcFragment = contract.interface.getFunction(fragment.name);
        if (funcFragment && funcFragment.selector) {
          selectors.push(funcFragment.selector);
        }
      } catch (e) {
        // Skip functions that can't be processed
        continue;
      }
    }
  }
  return selectors;
}

async function deployDiamond() {
  const [owner, addr1, addr2] = await ethers.getSigners();

  // Deploy DiamondCutFacet
  const DiamondCutFacet = await ethers.getContractFactory("DiamondCutFacet");
  const diamondCutFacet = await DiamondCutFacet.deploy();
  await diamondCutFacet.waitForDeployment();

  // Deploy Diamond
  const Diamond = await ethers.getContractFactory("Diamond");
  const diamond = await Diamond.deploy(
    await owner.getAddress(),
    await diamondCutFacet.getAddress()
  );
  await diamond.waitForDeployment();

  // Deploy DiamondInit for initialization
  const DiamondInit = await ethers.getContractFactory("DiamondInit");
  const diamondInit = await DiamondInit.deploy();
  await diamondInit.waitForDeployment();

  // Deploy other facets
  const DiamondLoupeFacet = await ethers.getContractFactory("DiamondLoupeFacet");
  const diamondLoupeFacet = await DiamondLoupeFacet.deploy();
  await diamondLoupeFacet.waitForDeployment();

  const OwnershipFacet = await ethers.getContractFactory("OwnershipFacet");
  const ownershipFacet = await OwnershipFacet.deploy();
  await ownershipFacet.waitForDeployment();

  const GovernanceFacet = await ethers.getContractFactory("GovernanceFacet");
  const governanceFacet = await GovernanceFacet.deploy();
  await governanceFacet.waitForDeployment();

  const LiquidityPoolFacet = await ethers.getContractFactory("LiquidityPoolFacet");
  const liquidityPoolFacet = await LiquidityPoolFacet.deploy();
  await liquidityPoolFacet.waitForDeployment();

  const AddressLinkingFacet = await ethers.getContractFactory("AddressLinkingFacet");
  const addressLinkingFacet = await AddressLinkingFacet.deploy();
  await addressLinkingFacet.waitForDeployment();

  // Deploy MockERC20 for testing
  const MockERC20 = await ethers.getContractFactory("MockERC20");
  const mockUSDC = await MockERC20.deploy(
    "Mock USDC",
    "USDC",
    18
  );
  await mockUSDC.waitForDeployment();

  // Mint tokens to test accounts
  await mockUSDC.mint(await owner.getAddress(), ethers.parseUnits("100000", 18));
  await mockUSDC.mint(await addr1.getAddress(), ethers.parseUnits("100000", 18));
  await mockUSDC.mint(await addr2.getAddress(), ethers.parseUnits("100000", 18));

  // Get the diamondCut function
  const diamondCut = await ethers.getContractAt('IDiamondCut', await diamond.getAddress());

  // Add facets to diamond
  const cut = [
    {
      facetAddress: await diamondLoupeFacet.getAddress(),
      action: FacetCutAction.Add,
      functionSelectors: getSelectors(diamondLoupeFacet)
    },
    {
      facetAddress: await ownershipFacet.getAddress(),
      action: FacetCutAction.Add,
      functionSelectors: getSelectors(ownershipFacet)
    },
    {
      facetAddress: await governanceFacet.getAddress(),
      action: FacetCutAction.Add,
      functionSelectors: getSelectors(governanceFacet)
    },
    {
      facetAddress: await liquidityPoolFacet.getAddress(),
      action: FacetCutAction.Add,
      functionSelectors: getSelectors(liquidityPoolFacet)
    },
    {
      facetAddress: await addressLinkingFacet.getAddress(),
      action: FacetCutAction.Add,
      functionSelectors: getSelectors(addressLinkingFacet)
    }
  ];

  // Initialize diamond with initial values
  const initCalldata = diamondInit.interface.encodeFunctionData('init', [
    await mockUSDC.getAddress(),
    ethers.parseUnits("100", 18), // minimumStake
    1200, // 12% initial APR (in basis points)
    7 * 24 * 60 * 60, // 7 days lock duration
    50, // APR reduction per thousand (0.5%)
    10 // 10% emergency withdraw penalty
  ]);

  const tx = await diamondCut.diamondCut(cut, await diamondInit.getAddress(), initCalldata);
  await tx.wait();

  return {
    diamond,
    diamondCutFacet,
    diamondLoupeFacet,
    ownershipFacet,
    governanceFacet,
    liquidityPoolFacet,
    addressLinkingFacet,
    mockUSDC,
    owner,
    addr1,
    addr2
  };
}

async function setupFinancier(diamond, mockUSDC, signer) {
  const liquidityPoolFacet = await ethers.getContractAt("LiquidityPoolFacet", await diamond.getAddress());
  
  // Mint tokens for the financier
  await mockUSDC.mint(await signer.getAddress(), ethers.parseUnits("100000", 18));
  
  // Approve and stake enough to become a financier
  const stakeAmount = ethers.parseUnits("10000", 18); // Well above minimum
  await mockUSDC.connect(signer).approve(await diamond.getAddress(), stakeAmount);
  
  // Stake with long deadline (1 year)
  const deadline = Math.floor(Date.now() / 1000) + (365 * 24 * 60 * 60);
  await liquidityPoolFacet.connect(signer).stake(stakeAmount, deadline);
  
  // Apply as financier
  await liquidityPoolFacet.connect(signer).applyAsFinancier();
  
  return signer;
}

module.exports = {
  deployDiamond,
  getSelectors,
  FacetCutAction,
  setupFinancier
};