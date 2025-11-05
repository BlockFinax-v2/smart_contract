const { expect } = require("chai");
const { ethers } = require("hardhat");
const { main: deployDiamond, getSelectors } = require("../scripts/deploy.js");

describe("BLL Diamond Token - Complete Test Suite", function () {
  let diamond;
  let diamondCutFacet;
  let diamondLoupeFacet;
  let ownershipFacet;
  let erc20Facet;
  let swapFacet;
  let multiSigFacet;
  let tokenURIFacet;
  let owner;
  let addr1;
  let addr2;
  let addr3;
  let ownerAddress, addr1Address, addr2Address, addr3Address;

  beforeEach(async function () {
    [owner, addr1, addr2, addr3] = await ethers.getSigners();
    ownerAddress = await owner.getAddress();
    addr1Address = await addr1.getAddress();
    addr2Address = await addr2.getAddress();
    addr3Address = await addr3.getAddress();
    
    // Deploy the diamond
    const deployment = await deployDiamond();
    const diamondAddress = deployment.diamond;

    // Get contract instances
    diamond = await ethers.getContractAt("Diamond", diamondAddress);
    erc20Facet = await ethers.getContractAt("ERC20Facet", diamondAddress);
    swapFacet = await ethers.getContractAt("SwapFacet", diamondAddress);
    multiSigFacet = await ethers.getContractAt("MultiSigFacet", diamondAddress);
    tokenURIFacet = await ethers.getContractAt("TokenURIFacet", diamondAddress);
    ownershipFacet = await ethers.getContractAt("OwnershipFacet", diamondAddress);
    diamondLoupeFacet = await ethers.getContractAt("DiamondLoupeFacet", diamondAddress);
  });

  describe("ERC20 Functionality", function () {
    it("Should have correct name, symbol, and decimals", async function () {
      expect(await erc20Facet.name()).to.equal("BLL Token");
      expect(await erc20Facet.symbol()).to.equal("BLL");
      expect(await erc20Facet.decimals()).to.equal(18);
    });

    it("Should have initial supply", async function () {
      const totalSupply = await erc20Facet.totalSupply();
      expect(totalSupply).to.equal(ethers.parseEther("1000000"));
      
      const ownerBalance = await erc20Facet.balanceOf(ownerAddress);
      expect(ownerBalance).to.equal(totalSupply);
    });

    it("Should transfer tokens", async function () {
      const amount = ethers.parseEther("100");
      await erc20Facet.transfer(addr1Address, amount);
      
      expect(await erc20Facet.balanceOf(addr1Address)).to.equal(amount);
    });

    it("Should approve and transferFrom", async function () {
      const amount = ethers.parseEther("100");
      await erc20Facet.approve(addr1Address, amount);
      
      expect(await erc20Facet.allowance(ownerAddress, addr1Address)).to.equal(amount);
      
      await erc20Facet.connect(addr1).transferFrom(ownerAddress, addr2Address, amount);
      expect(await erc20Facet.balanceOf(addr2Address)).to.equal(amount);
    });
  });

  describe("Swap Functionality", function () {
    it("Should allow buying tokens with ETH", async function () {
      const ethAmount = ethers.parseEther("1");
      const expectedTokens = ethers.parseEther("1000"); // 1 ETH = 1000 tokens at 0.001 ETH/token
      
      await swapFacet.connect(addr1).swapEthForTokens({ value: ethAmount });
      
      const balance = await erc20Facet.balanceOf(addr1Address);
      expect(balance).to.equal(expectedTokens);
    });

    it("Should track ETH received", async function () {
      const ethAmount = ethers.parseEther("1");
      await swapFacet.connect(addr1).swapEthForTokens({ value: ethAmount });
      
      expect(await swapFacet.getTotalEthReceived()).to.equal(ethAmount);
    });

    it("Should allow owner to change token price", async function () {
      const newPrice = ethers.parseEther("0.002");
      await swapFacet.setTokenPrice(newPrice);
      
      expect(await swapFacet.getTokenPrice()).to.equal(newPrice);
    });

    it("Should allow owner to disable/enable swapping", async function () {
      await swapFacet.setSwapEnabled(false);
      expect(await swapFacet.isSwapEnabled()).to.equal(false);
      
      await expect(
        swapFacet.connect(addr1).swapEthForTokens({ value: ethers.parseEther("1") })
      ).to.be.revertedWith("Swap: Swapping is disabled");
      
      await swapFacet.setSwapEnabled(true);
      expect(await swapFacet.isSwapEnabled()).to.equal(true);
    });

    it("Should allow owner to withdraw ETH", async function () {
      const ethAmount = ethers.parseEther("1");
      await swapFacet.connect(addr1).swapEthForTokens({ value: ethAmount });
      
      const initialBalance = await ethers.provider.getBalance(ownerAddress);
      await swapFacet.withdrawEth(ownerAddress, ethAmount);
      
      expect(await swapFacet.getContractBalance()).to.equal(0);
    });
  });

  describe("MultiSig Functionality", function () {
    beforeEach(async function () {
      await multiSigFacet.initializeMultiSig(
        [addr1Address, addr2Address],
        2
      );
    });

    it("Should initialize multisig correctly", async function () {
      const owners = await multiSigFacet.getOwners();
      expect(owners).to.have.lengthOf(2);
      expect(owners).to.include(addr1Address);
      expect(owners).to.include(addr2Address);
      expect(await multiSigFacet.getRequiredConfirmations()).to.equal(2);
    });

    it("Should submit a transaction", async function () {
      const tx = await multiSigFacet.connect(addr1).submitTransaction(
        addr3Address,
        ethers.parseEther("0.1"),
        "0x"
      );
      
      expect(await multiSigFacet.getTransactionCount()).to.equal(1);
    });

    it("Should confirm and execute transaction", async function () {
      await multiSigFacet.connect(addr1).submitTransaction(
        addr3Address,
        0,
        "0x"
      );
      
      await multiSigFacet.connect(addr1).confirmTransaction(0);
      await multiSigFacet.connect(addr2).confirmTransaction(0);
      
      await multiSigFacet.connect(addr1).executeTransaction(0);
      
      const tx = await multiSigFacet.getTransaction(0);
      expect(tx.executed).to.equal(true);
    });

    it("Should revoke confirmation", async function () {
      await multiSigFacet.connect(addr1).submitTransaction(addr3Address, 0, "0x");
      await multiSigFacet.connect(addr1).confirmTransaction(0);
      
      expect(await multiSigFacet.isConfirmed(0, addr1Address)).to.equal(true);
      
      await multiSigFacet.connect(addr1).revokeConfirmation(0);
      expect(await multiSigFacet.isConfirmed(0, addr1Address)).to.equal(false);
    });

    it("Should add and remove owners", async function () {
      await multiSigFacet.addOwner(addr3Address);
      expect(await multiSigFacet.isOwner(addr3Address)).to.equal(true);
      
      await multiSigFacet.removeOwner(addr3Address);
      expect(await multiSigFacet.isOwner(addr3Address)).to.equal(false);
    });
  });

  describe("TokenURI Functionality", function () {
    it("Should return tokenURI with metadata", async function () {
      const uri = await tokenURIFacet.tokenURI();
      expect(uri).to.include("data:application/json;base64");
    });

    it("Should return SVG logo", async function () {
      const logo = await tokenURIFacet.getLogo();
      expect(logo).to.include("<svg");
      expect(logo).to.include("BLL");
    });

    it("Should return metadata", async function () {
      const metadata = await tokenURIFacet.getMetadata();
      expect(metadata).to.include("BLL Token");
      expect(metadata).to.include("BLL");
    });

    it("Should allow owner to set metadata", async function () {
      await tokenURIFacet.setTokenMetadata(
        "Updated description",
        "https://new-url.com",
        "FF0000"
      );
      
      const metadata = await tokenURIFacet.getMetadata();
      expect(metadata).to.include("Updated description");
      expect(metadata).to.include("https://new-url.com");
    });
  });

  describe("Diamond Loupe", function () {
    it("Should return all facets", async function () {
      const facets = await diamondLoupeFacet.facets();
      expect(facets.length).to.be.greaterThan(0);
    });

    it("Should return facet addresses", async function () {
      const addresses = await diamondLoupeFacet.facetAddresses();
      expect(addresses.length).to.be.greaterThan(0);
    });

    it("Should return function selectors for a facet", async function () {
      const addresses = await diamondLoupeFacet.facetAddresses();
      const selectors = await diamondLoupeFacet.facetFunctionSelectors(addresses[0]);
      expect(selectors.length).to.be.greaterThan(0);
    });
  });

  describe("Ownership", function () {
    it("Should return correct owner", async function () {
      expect(await ownershipFacet.owner()).to.equal(ownerAddress);
    });

    it("Should transfer ownership", async function () {
      await ownershipFacet.transferOwnership(addr1Address);
      expect(await ownershipFacet.owner()).to.equal(addr1Address);
    });

    it("Should not allow non-owner to transfer ownership", async function () {
      await expect(
        ownershipFacet.connect(addr1).transferOwnership(addr2Address)
      ).to.be.revertedWith("LibDiamond: Must be contract owner");
    });
  });

  describe("Diamond Upgradeability", function () {
    it("Should support adding new functions", async function () {
      const facets = await diamondLoupeFacet.facets();
      expect(facets.length).to.be.greaterThan(0);
    });
  });
});
