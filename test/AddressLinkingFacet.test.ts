const { expect } = require("chai");
const { ethers } = require("hardhat");
const { deployDiamond } = require("./helpers/diamondHelper");

describe("AddressLinkingFacet Tests", function () {

  describe("Address Linking Tests", function () {
    it("Should link smart account to EOA successfully", async function () {
      const deployment = await deployDiamond();
      const addressLinking = await ethers.getContractAt("AddressLinkingFacet", await deployment.diamond.getAddress());

      const eoaAddress = await deployment.addr1.getAddress();
      const smartAccountAddress = await deployment.addr2.getAddress(); // Simulating smart account

      // Link smart account to EOA
      await addressLinking.connect(deployment.addr1).linkSmartAccount(smartAccountAddress);

      // Verify link was created
      const linkedSA = await addressLinking.getLinkedSmartAccount(eoaAddress);
      expect(linkedSA).to.equal(smartAccountAddress);

      const linkedEOA = await addressLinking.getLinkedEOA(smartAccountAddress);
      expect(linkedEOA).to.equal(eoaAddress);

      const isLinked = await addressLinking.isLinkedSmartAccount(smartAccountAddress);
      expect(isLinked).to.be.true;
    });

    it("Should resolve smart account to EOA", async function () {
      const deployment = await deployDiamond();
      const addressLinking = await ethers.getContractAt("AddressLinkingFacet", await deployment.diamond.getAddress());

      const eoaAddress = await deployment.addr1.getAddress();
      const smartAccountAddress = await deployment.addr2.getAddress();

      // Link addresses
      await addressLinking.connect(deployment.addr1).linkSmartAccount(smartAccountAddress);

      // Resolve smart account to primary identity
      const resolved = await addressLinking.resolveToPrimaryIdentity(smartAccountAddress);
      expect(resolved).to.equal(eoaAddress);
    });

    it("Should resolve EOA to itself when not linked", async function () {
      const deployment = await deployDiamond();
      const addressLinking = await ethers.getContractAt("AddressLinkingFacet", await deployment.diamond.getAddress());

      const eoaAddress = await deployment.addr1.getAddress();

      // Resolve unlinked EOA
      const resolved = await addressLinking.resolveToPrimaryIdentity(eoaAddress);
      expect(resolved).to.equal(eoaAddress);
    });

    it("Should unlink smart account successfully", async function () {
      const deployment = await deployDiamond();
      const addressLinking = await ethers.getContractAt("AddressLinkingFacet", await deployment.diamond.getAddress());

      const eoaAddress = await deployment.addr1.getAddress();
      const smartAccountAddress = await deployment.addr2.getAddress();

      // Link addresses
      await addressLinking.connect(deployment.addr1).linkSmartAccount(smartAccountAddress);

      // Verify link exists
      let linkedSA = await addressLinking.getLinkedSmartAccount(eoaAddress);
      expect(linkedSA).to.equal(smartAccountAddress);

      // Unlink
      await addressLinking.connect(deployment.addr1).unlinkSmartAccount();

      // Verify link was removed
      linkedSA = await addressLinking.getLinkedSmartAccount(eoaAddress);
      expect(linkedSA).to.equal(ethers.ZeroAddress);

      const isLinked = await addressLinking.isLinkedSmartAccount(smartAccountAddress);
      expect(isLinked).to.be.false;
    });

    it("Should get comprehensive link info", async function () {
      const deployment = await deployDiamond();
      const addressLinking = await ethers.getContractAt("AddressLinkingFacet", await deployment.diamond.getAddress());

      const eoaAddress = await deployment.addr1.getAddress();
      const smartAccountAddress = await deployment.addr2.getAddress();

      // Link addresses
      await addressLinking.connect(deployment.addr1).linkSmartAccount(smartAccountAddress);

      // Get link info for smart account
      const [isLinked, linkedAddress, primaryIdentity] = await addressLinking.getLinkInfo(smartAccountAddress);
      expect(isLinked).to.be.true;
      expect(linkedAddress).to.equal(eoaAddress);
      expect(primaryIdentity).to.equal(eoaAddress);

      // Get link info for EOA
      const [isLinkedEOA, linkedAddressEOA, primaryIdentityEOA] = await addressLinking.getLinkInfo(eoaAddress);
      expect(isLinkedEOA).to.be.true;
      expect(linkedAddressEOA).to.equal(smartAccountAddress);
      expect(primaryIdentityEOA).to.equal(eoaAddress);
    });
  });

  describe("Error Handling Tests", function () {
    it("Should revert when linking zero address", async function () {
      const deployment = await deployDiamond();
      const addressLinking = await ethers.getContractAt("AddressLinkingFacet", await deployment.diamond.getAddress());

      await expect(
        addressLinking.connect(deployment.addr1).linkSmartAccount(ethers.ZeroAddress)
      ).to.be.revertedWithCustomError(addressLinking, "InvalidAddress");
    });

    it("Should revert when linking to self", async function () {
      const deployment = await deployDiamond();
      const addressLinking = await ethers.getContractAt("AddressLinkingFacet", await deployment.diamond.getAddress());

      const eoaAddress = await deployment.addr1.getAddress();

      await expect(
        addressLinking.connect(deployment.addr1).linkSmartAccount(eoaAddress)
      ).to.be.revertedWithCustomError(addressLinking, "InvalidAddress");
    });

    it("Should revert when smart account already linked", async function () {
      const deployment = await deployDiamond();
      const addressLinking = await ethers.getContractAt("AddressLinkingFacet", await deployment.diamond.getAddress());

      const smartAccountAddress = await deployment.addr2.getAddress();

      // Link to addr1
      await addressLinking.connect(deployment.addr1).linkSmartAccount(smartAccountAddress);

      // Try to link same smart account to owner
      await expect(
        addressLinking.connect(deployment.owner).linkSmartAccount(smartAccountAddress)
      ).to.be.revertedWithCustomError(addressLinking, "AlreadyLinked");
    });

    it("Should revert when EOA already has linked smart account", async function () {
      const deployment = await deployDiamond();
      const addressLinking = await ethers.getContractAt("AddressLinkingFacet", await deployment.diamond.getAddress());

      const smartAccount1 = await deployment.addr2.getAddress();
      const [, , addr3] = await ethers.getSigners();
      const smartAccount2 = await addr3.getAddress();

      // Link first smart account
      await addressLinking.connect(deployment.addr1).linkSmartAccount(smartAccount1);

      // Try to link second smart account
      await expect(
        addressLinking.connect(deployment.addr1).linkSmartAccount(smartAccount2)
      ).to.be.revertedWithCustomError(addressLinking, "AlreadyLinked");
    });

    it("Should revert when unlinking non-existent link", async function () {
      const deployment = await deployDiamond();
      const addressLinking = await ethers.getContractAt("AddressLinkingFacet", await deployment.diamond.getAddress());

      await expect(
        addressLinking.connect(deployment.addr1).unlinkSmartAccount()
      ).to.be.revertedWithCustomError(addressLinking, "NotLinked");
    });
  });

  describe("Integration with Staking Tests", function () {
    it("Should stake via EOA and query from smart account with same result", async function () {
      const deployment = await deployDiamond();
      const addressLinking = await ethers.getContractAt("AddressLinkingFacet", await deployment.diamond.getAddress());
      const liquidityPool = await ethers.getContractAt("LiquidityPoolFacet", await deployment.diamond.getAddress());

      const eoaAddress = await deployment.addr1.getAddress();
      const smartAccountAddress = await deployment.addr2.getAddress();

      // Link smart account to EOA
      await addressLinking.connect(deployment.addr1).linkSmartAccount(smartAccountAddress);

      // Stake via EOA
      const stakeAmount = ethers.parseEther("1000");
      const stakingDeadline = Math.floor(Date.now() / 1000) + (30 * 24 * 60 * 60);

      const mockUSDCAddress = await deployment.mockUSDC.getAddress();
      await deployment.mockUSDC.connect(deployment.addr1).approve(await deployment.diamond.getAddress(), stakeAmount);
      await liquidityPool.connect(deployment.addr1).stakeToken(mockUSDCAddress, stakeAmount, stakingDeadline, stakeAmount);

      // Query from EOA
      const stakeInfoEOA = await liquidityPool.getStake(eoaAddress);
      expect(stakeInfoEOA.amount).to.equal(stakeAmount);

      // Query from smart account - should resolve to EOA and return same data
      const stakeInfoSA = await liquidityPool.getStake(smartAccountAddress);
      expect(stakeInfoSA.amount).to.equal(stakeAmount);
      expect(stakeInfoSA.amount).to.equal(stakeInfoEOA.amount);
    });

    it("Should stake via linked smart account and record under EOA", async function () {
      const deployment = await deployDiamond();
      const addressLinking = await ethers.getContractAt("AddressLinkingFacet", await deployment.diamond.getAddress());
      const liquidityPool = await ethers.getContractAt("LiquidityPoolFacet", await deployment.diamond.getAddress());

      const eoaAddress = await deployment.addr1.getAddress();
      const smartAccountAddress = await deployment.addr2.getAddress();

      // Link smart account to EOA
      await addressLinking.connect(deployment.addr1).linkSmartAccount(smartAccountAddress);

      // Give smart account signer some tokens and approve
      const stakeAmount = ethers.parseEther("1000");
      const stakingDeadline = Math.floor(Date.now() / 1000) + (30 * 24 * 60 * 60);

      const mockUSDCAddress = await deployment.mockUSDC.getAddress();
      // Ensure EOA has allowance since funds come from EOA
      await deployment.mockUSDC.connect(deployment.addr1).approve(await deployment.diamond.getAddress(), stakeAmount);

      // Stake via smart account (addr2 simulating smart account)
      await liquidityPool.connect(deployment.addr2).stakeToken(mockUSDCAddress, stakeAmount, stakingDeadline, stakeAmount);

      // Query from EOA - should show the stake
      const stakeInfo = await liquidityPool.getStake(eoaAddress);
      expect(stakeInfo.amount).to.equal(stakeAmount);
      expect(stakeInfo.active).to.be.true;
    });

    it("Should accumulate stakes from both EOA and smart account under single identity", async function () {
      const deployment = await deployDiamond();
      const addressLinking = await ethers.getContractAt("AddressLinkingFacet", await deployment.diamond.getAddress());
      const liquidityPool = await ethers.getContractAt("LiquidityPoolFacet", await deployment.diamond.getAddress());

      const eoaAddress = await deployment.addr1.getAddress();
      const smartAccountAddress = await deployment.addr2.getAddress();

      // Link smart account to EOA
      await addressLinking.connect(deployment.addr1).linkSmartAccount(smartAccountAddress);

      const stakeAmount1 = ethers.parseEther("1000");
      const stakeAmount2 = ethers.parseEther("500");
      const stakingDeadline = Math.floor(Date.now() / 1000) + (30 * 24 * 60 * 60);

      const mockUSDCAddress = await deployment.mockUSDC.getAddress();
      // First stake via EOA
      await deployment.mockUSDC.connect(deployment.addr1).approve(await deployment.diamond.getAddress(), stakeAmount1);
      await liquidityPool.connect(deployment.addr1).stakeToken(mockUSDCAddress, stakeAmount1, stakingDeadline, stakeAmount1);

      // Second stake via smart account - triggers fund transfer from EOA
      // So EOA must approve the amount
      await deployment.mockUSDC.connect(deployment.addr1).approve(await deployment.diamond.getAddress(), stakeAmount2);
      await liquidityPool.connect(deployment.addr2).stakeToken(mockUSDCAddress, stakeAmount2, stakingDeadline, stakeAmount2);

      // Total should be sum of both stakes
      const stakeInfo = await liquidityPool.getStake(eoaAddress);
      expect(stakeInfo.amount).to.equal(stakeAmount1 + stakeAmount2);
    });

    it("Should check financier eligibility with both EOA and smart account", async function () {
      const deployment = await deployDiamond();
      const addressLinking = await ethers.getContractAt("AddressLinkingFacet", await deployment.diamond.getAddress());
      const liquidityPool = await ethers.getContractAt("LiquidityPoolFacet", await deployment.diamond.getAddress());

      const eoaAddress = await deployment.addr1.getAddress();
      const smartAccountAddress = await deployment.addr2.getAddress();

      // Link smart account to EOA
      await addressLinking.connect(deployment.addr1).linkSmartAccount(smartAccountAddress);

      // Stake as financier via EOA
      const stakeAmount = ethers.parseEther("10000");
      const stakingDeadline = Math.floor(Date.now() / 1000) + (365 * 24 * 60 * 60);

      const mockUSDCAddress = await deployment.mockUSDC.getAddress();
      await deployment.mockUSDC.connect(deployment.addr1).approve(await deployment.diamond.getAddress(), stakeAmount);
      await liquidityPool.connect(deployment.addr1).stakeTokenAsFinancier(mockUSDCAddress, stakeAmount, stakingDeadline, stakeAmount);

      // Check eligibility from both addresses
      const isEligibleEOA = await liquidityPool.isFinancier(eoaAddress);
      const isEligibleSA = await liquidityPool.isFinancier(smartAccountAddress);

      expect(isEligibleEOA).to.be.true;
      expect(isEligibleSA).to.be.true; // Should resolve to EOA
    });
  });

  describe("View Functions Edge Cases", function () {
    it("Should return zero address for unlinked EOA", async function () {
      const deployment = await deployDiamond();
      const addressLinking = await ethers.getContractAt("AddressLinkingFacet", await deployment.diamond.getAddress());

      const eoaAddress = await deployment.addr1.getAddress();
      const linkedSA = await addressLinking.getLinkedSmartAccount(eoaAddress);
      expect(linkedSA).to.equal(ethers.ZeroAddress);
    });

    it("Should return zero address for unlinked smart account", async function () {
      const deployment = await deployDiamond();
      const addressLinking = await ethers.getContractAt("AddressLinkingFacet", await deployment.diamond.getAddress());

      const smartAccountAddress = await deployment.addr2.getAddress();
      const linkedEOA = await addressLinking.getLinkedEOA(smartAccountAddress);
      expect(linkedEOA).to.equal(ethers.ZeroAddress);
    });

    it("Should return false for unlinked address", async function () {
      const deployment = await deployDiamond();
      const addressLinking = await ethers.getContractAt("AddressLinkingFacet", await deployment.diamond.getAddress());

      const address = await deployment.addr1.getAddress();
      const isLinked = await addressLinking.isLinkedSmartAccount(address);
      expect(isLinked).to.be.false;
    });

    it("Should return unlinked info for address without links", async function () {
      const deployment = await deployDiamond();
      const addressLinking = await ethers.getContractAt("AddressLinkingFacet", await deployment.diamond.getAddress());

      const address = await deployment.addr1.getAddress();
      const [isLinked, linkedAddress, primaryIdentity] = await addressLinking.getLinkInfo(address);

      expect(isLinked).to.be.false;
      expect(linkedAddress).to.equal(ethers.ZeroAddress);
      expect(primaryIdentity).to.equal(address);
    });
  });
});
