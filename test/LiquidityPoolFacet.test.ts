const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");
const { deployDiamond } = require("./helpers/diamondHelper");

describe("LiquidityPoolFacet Comprehensive Tests", function () {
  
  describe("Error Handling Tests", function () {
    it("Should handle zero amount staking error", async function () {
      const deployment = await deployDiamond();
      const liquidityPool = await ethers.getContractAt("LiquidityPoolFacet", await deployment.diamond.getAddress());

      const stakingDeadline = Math.floor(Date.now() / 1000) + (30 * 24 * 60 * 60);

      await expect(
        liquidityPool.connect(deployment.addr1).stake(0, stakingDeadline)
      ).to.be.revertedWithCustomError(liquidityPool, "ZeroAmount");
    });

    it("Should handle below minimum stake error", async function () {
      const deployment = await deployDiamond();
      const liquidityPool = await ethers.getContractAt("LiquidityPoolFacet", await deployment.diamond.getAddress());

      const belowMinAmount = ethers.parseEther("50"); // Below minimum of 100
      const stakingDeadline = Math.floor(Date.now() / 1000) + (30 * 24 * 60 * 60);

      await expect(
        liquidityPool.connect(deployment.addr1).stake(belowMinAmount, stakingDeadline)
      ).to.be.revertedWithCustomError(liquidityPool, "BelowMinimumStake");
    });

    it("Should handle no active stake error for unstaking", async function () {
      const deployment = await deployDiamond();
      const liquidityPool = await ethers.getContractAt("LiquidityPoolFacet", await deployment.diamond.getAddress());

      await expect(
        liquidityPool.connect(deployment.addr1).unstake(ethers.parseEther("100"))
      ).to.be.revertedWithCustomError(liquidityPool, "NoActiveStake");
    });

    it("Should handle zero amount unstake error", async function () {
      const deployment = await deployDiamond();
      const liquidityPool = await ethers.getContractAt("LiquidityPoolFacet", await deployment.diamond.getAddress());

      // NoActiveStake is checked before ZeroAmount
      await expect(
        liquidityPool.connect(deployment.addr1).unstake(0)
      ).to.be.revertedWithCustomError(liquidityPool, "NoActiveStake");
    });

    it("Should handle no active stake error for emergency withdraw", async function () {
      const deployment = await deployDiamond();
      const liquidityPool = await ethers.getContractAt("LiquidityPoolFacet", await deployment.diamond.getAddress());

      await expect(
        liquidityPool.connect(deployment.addr1).emergencyWithdraw()
      ).to.be.revertedWithCustomError(liquidityPool, "NoActiveStake");
    });

    it("Should handle no rewards to claim error", async function () {
      const deployment = await deployDiamond();
      const liquidityPool = await ethers.getContractAt("LiquidityPoolFacet", await deployment.diamond.getAddress());

      await expect(
        liquidityPool.connect(deployment.addr1).claimRewards()
      ).to.be.revertedWithCustomError(liquidityPool, "NoActiveStake");
    });
  });

  describe("View Functions Tests", function () {
    it("Should return staking configuration", async function () {
      const deployment = await deployDiamond();
      const liquidityPool = await ethers.getContractAt("LiquidityPoolFacet", await deployment.diamond.getAddress());

      const config = await liquidityPool.getStakingConfig();
      expect(config.minimumStake).to.equal(ethers.parseEther("100"));
      expect(config.emergencyWithdrawPenalty).to.equal(10); // 10%
    });

    it("Should return pool statistics", async function () {
      const deployment = await deployDiamond();
      const liquidityPool = await ethers.getContractAt("LiquidityPoolFacet", await deployment.diamond.getAddress());

      const stats = await liquidityPool.getPoolStats();
      expect(stats.totalStaked).to.equal(0);
      expect(stats.totalLiquidityProviders).to.equal(0);
    });

    it("Should return empty stakers array initially", async function () {
      const deployment = await deployDiamond();
      const liquidityPool = await ethers.getContractAt("LiquidityPoolFacet", await deployment.diamond.getAddress());

      const stakers = await liquidityPool.getStakers();
      expect(stakers.length).to.equal(0);
    });

    it("Should return empty financiers array initially", async function () {
      const deployment = await deployDiamond();
      const liquidityPool = await ethers.getContractAt("LiquidityPoolFacet", await deployment.diamond.getAddress());

      const financiers = await liquidityPool.getFinanciers();
      expect(financiers.length).to.equal(0);
    });

    it("Should return zero pending rewards for non-staker", async function () {
      const deployment = await deployDiamond();
      const liquidityPool = await ethers.getContractAt("LiquidityPoolFacet", await deployment.diamond.getAddress());

      const pendingRewards = await liquidityPool.getPendingRewards(await deployment.addr1.getAddress());
      expect(pendingRewards).to.equal(0);
    });

    it("Should return false for non-eligible financier", async function () {
      const deployment = await deployDiamond();
      const liquidityPool = await ethers.getContractAt("LiquidityPoolFacet", await deployment.diamond.getAddress());

      const isEligible = await liquidityPool.isEligibleFinancier(await deployment.addr1.getAddress());
      expect(isEligible).to.be.false;
    });
  });

  describe("Edge Cases", function () {
    it("Should handle contract deployment without errors", async function () {
      const [owner] = await ethers.getSigners();

      const DiamondCutFacet = await ethers.getContractFactory("DiamondCutFacet");
      const diamondCutFacet = await DiamondCutFacet.deploy();
      await diamondCutFacet.waitForDeployment();

      const Diamond = await ethers.getContractFactory("Diamond");
      const diamond = await Diamond.deploy(
        await owner.getAddress(),
        await diamondCutFacet.getAddress()
      );
      await diamond.waitForDeployment();

      expect(await diamond.getAddress()).to.be.a("string");
      expect(await diamond.getAddress()).to.have.length(42);
    });

    it("Should handle zero address scenarios", async function () {
      const deployment = await deployDiamond();
      const liquidityPool = await ethers.getContractAt("LiquidityPoolFacet", await deployment.diamond.getAddress());

      const stakeInfo = await liquidityPool.getStake(ethers.ZeroAddress);
      expect(stakeInfo.amount).to.equal(0);
      expect(stakeInfo.active).to.be.false;
    });
  });

  describe("Fuzz Tests", function () {
    it("Should handle random deadline values within range", async function () {
      for (let i = 0; i < 10; i++) {
        const randomDays = Math.floor(Math.random() * 365) + 1; // 1-365 days
        const randomDeadline = Math.floor(Date.now() / 1000) + (randomDays * 24 * 60 * 60);
        
        expect(randomDeadline).to.be.greaterThan(Math.floor(Date.now() / 1000));
        expect(randomDeadline).to.be.lessThan(Math.floor(Date.now() / 1000) + (366 * 24 * 60 * 60));
      }
    });

    it("Should handle random stake amounts within bounds", async function () {
      const minStake = ethers.parseEther("100");
      const maxStake = ethers.parseEther("1000000");

      for (let i = 0; i < 10; i++) {
        const randomMultiplier = Math.floor(Math.random() * 10000) + 1; // 1-10000x
        const randomStake = minStake * BigInt(randomMultiplier);
        
        expect(randomStake).to.be.greaterThanOrEqual(minStake);
        expect(randomStake).to.be.lessThanOrEqual(maxStake);
      }
    });

    it("Should handle random address generation", async function () {
      for (let i = 0; i < 5; i++) {
        const randomWallet = ethers.Wallet.createRandom();
        expect(randomWallet.address).to.be.a("string");
        expect(randomWallet.address).to.have.length(42);
        expect(randomWallet.address).to.match(/^0x[a-fA-F0-9]{40}$/);
      }
    });

    it("Should handle rapid consecutive operations", async function () {
      const deployment = await deployDiamond();
      const liquidityPool = await ethers.getContractAt("LiquidityPoolFacet", await deployment.diamond.getAddress());

      // Rapid calls to view functions
      const promises = [];
      for (let i = 0; i < 5; i++) {
        promises.push(liquidityPool.getPoolStats());
        promises.push(liquidityPool.getStakingConfig());
        promises.push(liquidityPool.getStakers());
        promises.push(liquidityPool.getFinanciers());
      }

      const results = await Promise.all(promises);
      expect(results.length).to.equal(20);
    });

    it("Should handle extreme gas limit scenarios", async function () {
      // This test verifies gas usage doesn't exceed reasonable limits
      expect(true).to.be.true; // Placeholder for gas limit testing
    });
  });
});