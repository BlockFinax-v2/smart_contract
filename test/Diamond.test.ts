const { expect } = require("chai");
const { ethers } = require("hardhat");
const { deployDiamond } = require("./helpers/diamondHelper.js");

describe("Diamond Core Tests", function () {
  let contracts;

  it("Should deploy Diamond with all facets", async function () {
    contracts = await deployDiamond();

    expect(await contracts.diamond.getAddress()).to.be.a("string");
    expect(await contracts.diamond.getAddress()).to.have.length(42);
  });

  describe("Diamond Deployment", function () {
    it("Should revert with zero address owner", async function () {
      const DiamondCutFacet = await ethers.getContractFactory("DiamondCutFacet");
      const diamondCutFacet = await DiamondCutFacet.deploy();
      await diamondCutFacet.waitForDeployment();

      const Diamond = await ethers.getContractFactory("Diamond");
      
      await expect(
        Diamond.deploy(
          ethers.ZeroAddress,
          await diamondCutFacet.getAddress()
        )
      ).to.be.revertedWith("LibDiamond: New owner cannot be the zero address");
    });

    it("Should have correct owner", async function () {
      const ownershipContract = await ethers.getContractAt("OwnershipFacet", await contracts.diamond.getAddress());
      const contractOwner = await ownershipContract.owner();
      
      expect(contractOwner).to.equal(await contracts.owner.getAddress());
    });
  });

  describe("Diamond Loupe Functions", function () {
    it("Should return facet addresses", async function () {
      const diamondLoupe = await ethers.getContractAt("DiamondLoupeFacet", await contracts.diamond.getAddress());
      const facetAddresses = await diamondLoupe.facetAddresses();
      
      expect(facetAddresses.length).to.be.greaterThan(0);
      expect(facetAddresses[0]).to.be.a("string");
      expect(facetAddresses[0]).to.have.length(42);
    });

    it("Should return facets with function selectors", async function () {
      const diamondLoupe = await ethers.getContractAt("DiamondLoupeFacet", await contracts.diamond.getAddress());
      const facets = await diamondLoupe.facets();
      
      expect(facets.length).to.be.greaterThan(0);
      expect(facets[0].facetAddress).to.be.a("string");
      expect(facets[0].functionSelectors.length).to.be.greaterThan(0);
    });

    it("Should return correct function selectors for given facet", async function () {
      const diamondLoupe = await ethers.getContractAt("DiamondLoupeFacet", await contracts.diamond.getAddress());
      const facetAddresses = await diamondLoupe.facetAddresses();
      
      expect(facetAddresses.length).to.be.greaterThan(0);
      
      for (const facetAddress of facetAddresses) {
        const selectors = await diamondLoupe.facetFunctionSelectors(facetAddress);
        expect(selectors.length).to.be.greaterThan(0);
      }
    });

    it("Should return empty selectors for non-existent facet", async function () {
      const diamondLoupe = await ethers.getContractAt("DiamondLoupeFacet", await contracts.diamond.getAddress());
      const nonExistentAddress = "0x1234567890123456789012345678901234567890";
      
      const selectors = await diamondLoupe.facetFunctionSelectors(nonExistentAddress);
      expect(selectors.length).to.equal(0);
    });

    it("Should return correct facet address for function selector", async function () {
      const diamondLoupe = await ethers.getContractAt("DiamondLoupeFacet", await contracts.diamond.getAddress());
      const facets = await diamondLoupe.facets();
      
      expect(facets.length).to.be.greaterThan(0);
      
      for (const facet of facets) {
        for (const selector of facet.functionSelectors) {
          const facetAddress = await diamondLoupe.facetAddress(selector);
          expect(facetAddress).to.equal(facet.facetAddress);
        }
      }
    });
  });

  describe("Ownership Functions", function () {
    it("Should allow owner to transfer ownership", async function () {
      const ownershipFacet = await ethers.getContractAt("OwnershipFacet", await contracts.diamond.getAddress());
      
      const newOwner = contracts.addr1;
      
      await expect(
        ownershipFacet.connect(contracts.owner).transferOwnership(await newOwner.getAddress())
      ).to.emit(ownershipFacet, "OwnershipTransferred")
        .withArgs(await contracts.owner.getAddress(), await newOwner.getAddress());
      
      expect(await ownershipFacet.owner()).to.equal(await newOwner.getAddress());
    });

    it("Should not allow transfer to zero address", async function () {
      const ownershipFacet = await ethers.getContractAt("OwnershipFacet", await contracts.diamond.getAddress());
      
      await expect(
        ownershipFacet.connect(contracts.addr1).transferOwnership(ethers.ZeroAddress)
      ).to.be.revertedWith("LibDiamond: New owner cannot be the zero address");
    });

    it("Should not allow non-owner to transfer ownership", async function () {
      const ownershipFacet = await ethers.getContractAt("OwnershipFacet", await contracts.diamond.getAddress());
      
      await expect(
        ownershipFacet.connect(contracts.addr2).transferOwnership(await contracts.addr2.getAddress())
      ).to.be.revertedWith("LibDiamond: Must be contract owner");
    });

    it("Should not allow transfer to same address", async function () {
      const ownershipFacet = await ethers.getContractAt("OwnershipFacet", await contracts.diamond.getAddress());
      const currentOwner = await ownershipFacet.owner();
      
      // Use addr1 as the signer since ownership was transferred in previous test
      await expect(
        ownershipFacet.connect(contracts.addr1).transferOwnership(currentOwner)
      ).to.be.revertedWith("LibDiamond: New owner is same as current owner");
    });
  });

  describe("ERC165 Support", function () {
    it("Should support required interfaces", async function () {
      const erc165 = await ethers.getContractAt(
        "@openzeppelin/contracts/utils/introspection/IERC165.sol:IERC165",
        await contracts.diamond.getAddress()
      );
      
      // ERC165 interface ID
      const erc165InterfaceId = "0x01ffc9a7";
      expect(await erc165.supportsInterface(erc165InterfaceId)).to.be.true;
      
      // DiamondLoupe interface ID
      const diamondLoupeInterfaceId = "0x48e2b093";
      expect(await erc165.supportsInterface(diamondLoupeInterfaceId)).to.be.true;
    });

    it("Should not support invalid interface", async function () {
      const erc165 = await ethers.getContractAt(
        "@openzeppelin/contracts/utils/introspection/IERC165.sol:IERC165",
        await contracts.diamond.getAddress()
      );
      
      const invalidInterfaceId = "0xffffffff";
      expect(await erc165.supportsInterface(invalidInterfaceId)).to.be.false;
    });
  });

  describe("Fuzz Tests", function () {
    it("Should handle random valid addresses for ownership transfer", async function () {
      const ownershipFacet = await ethers.getContractAt("OwnershipFacet", await contracts.diamond.getAddress());
      
      // Generate random addresses and test transfer
      for (let i = 0; i < 5; i++) {
        const randomWallet = ethers.Wallet.createRandom();
        const randomAddress = randomWallet.address;
        
        // Get current owner
        const currentOwner = await ownershipFacet.owner();
        const ownerSigner = currentOwner === await contracts.owner.getAddress() ? contracts.owner : contracts.addr1;
        
        await expect(
          ownershipFacet.connect(ownerSigner).transferOwnership(randomAddress)
        ).to.emit(ownershipFacet, "OwnershipTransferred");
        
        expect(await ownershipFacet.owner()).to.equal(randomAddress);
        
        // Transfer to addr1 for next iteration (since we can't use random wallet)
        // We need to impersonate the random address and fund it
        await ethers.provider.send("hardhat_impersonateAccount", [randomAddress]);
        const randomSigner = await ethers.getSigner(randomAddress);
        
        // Fund the impersonated account
        await contracts.owner.sendTransaction({
          to: randomAddress,
          value: ethers.parseEther("1.0")
        });
        
        await ownershipFacet.connect(randomSigner).transferOwnership(await contracts.addr1.getAddress());
        await ethers.provider.send("hardhat_stopImpersonatingAccount", [randomAddress]);
      }
      
      // Transfer back to original owner
      await ownershipFacet.connect(contracts.addr1).transferOwnership(await contracts.owner.getAddress());
    });

    it("Should handle multiple facet address queries", async function () {
      const diamondLoupe = await ethers.getContractAt("DiamondLoupeFacet", await contracts.diamond.getAddress());
      
      for (let i = 0; i < 10; i++) {
        const facetAddresses = await diamondLoupe.facetAddresses();
        expect(facetAddresses.length).to.be.greaterThan(0);
        
        for (const address of facetAddresses) {
          expect(address).to.be.a("string");
          expect(address).to.have.length(42);
        }
      }
    });

    it("Should handle rapid function selector queries", async function () {
      const diamondLoupe = await ethers.getContractAt("DiamondLoupeFacet", await contracts.diamond.getAddress());
      const facets = await diamondLoupe.facets();
      
      for (let i = 0; i < 5; i++) {
        for (const facet of facets) {
          for (const selector of facet.functionSelectors) {
            const facetAddress = await diamondLoupe.facetAddress(selector);
            expect(facetAddress).to.equal(facet.facetAddress);
          }
        }
      }
    });

    it("Should handle edge case function selector values", async function () {
      const diamondLoupe = await ethers.getContractAt("DiamondLoupeFacet", await contracts.diamond.getAddress());
      
      // Test with zero selector
      const zeroFacetAddress = await diamondLoupe.facetAddress("0x00000000");
      expect(zeroFacetAddress).to.equal(ethers.ZeroAddress);
      
      // Test with max selector
      const maxFacetAddress = await diamondLoupe.facetAddress("0xffffffff");
      expect(maxFacetAddress).to.equal(ethers.ZeroAddress);
    });
  });

  describe("Edge Cases", function () {
    it("Should handle contract deployment without errors", async function () {
      const deployment = await deployDiamond();
      
      expect(await deployment.diamond.getAddress()).to.be.a("string");
      expect(await deployment.mockUSDC.getAddress()).to.be.a("string");
      expect(await deployment.governanceFacet.getAddress()).to.be.a("string");
      expect(await deployment.liquidityPoolFacet.getAddress()).to.be.a("string");
    });

    it("Should maintain consistent facet configuration", async function () {
      const diamondLoupe = await ethers.getContractAt("DiamondLoupeFacet", await contracts.diamond.getAddress());
      
      const facets1 = await diamondLoupe.facets();
      const facets2 = await diamondLoupe.facets();
      
      expect(facets1.length).to.equal(facets2.length);
      
      for (let i = 0; i < facets1.length; i++) {
        expect(facets1[i].facetAddress).to.equal(facets2[i].facetAddress);
        expect(facets1[i].functionSelectors.length).to.equal(facets2[i].functionSelectors.length);
      }
    });

    it("Should handle multiple ownership queries", async function () {
      const ownershipFacet = await ethers.getContractAt("OwnershipFacet", await contracts.diamond.getAddress());
      
      for (let i = 0; i < 10; i++) {
        const owner1 = await ownershipFacet.owner();
        const owner2 = await ownershipFacet.owner();
        expect(owner1).to.equal(owner2);
      }
    });
  });
});
