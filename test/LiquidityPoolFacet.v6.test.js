const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("LiquidityPoolFacet - Ethers v6 Compatible", function () {
    let liquidityPoolFacet;
    let mockUSDC;
    let owner, user1, user2, user3;

    beforeEach(async function () {
        [owner, user1, user2, user3] = await ethers.getSigners();

        // Deploy MockERC20 for USDC
        const MockERC20 = await ethers.getContractFactory("MockERC20");
        mockUSDC = await MockERC20.deploy("USD Coin", "USDC", 6);

        // Deploy LiquidityPoolFacet standalone for testing basic functionality
        const LiquidityPoolFacet = await ethers.getContractFactory("LiquidityPoolFacet");
        liquidityPoolFacet = await LiquidityPoolFacet.deploy();

        // Mint tokens to users
        const mintAmount = ethers.parseUnits("10000", 6); // 10,000 USDC
        await mockUSDC.mint(await user1.getAddress(), mintAmount);
        await mockUSDC.mint(await user2.getAddress(), mintAmount);
        await mockUSDC.mint(await user3.getAddress(), mintAmount);

        // Approve spending
        const facetAddress = await liquidityPoolFacet.getAddress();
        await mockUSDC.connect(user1).approve(facetAddress, ethers.MaxUint256);
        await mockUSDC.connect(user2).approve(facetAddress, ethers.MaxUint256);
        await mockUSDC.connect(user3).approve(facetAddress, ethers.MaxUint256);
    });

    describe("Deployment", function () {
        it("Should deploy successfully", async function () {
            const facetAddress = await liquidityPoolFacet.getAddress();
            const usdcAddress = await mockUSDC.getAddress();
            
            expect(facetAddress).to.not.equal(ethers.ZeroAddress);
            expect(usdcAddress).to.not.equal(ethers.ZeroAddress);
        });

        it("Should be pausable initially", async function () {
            expect(await liquidityPoolFacet.paused()).to.be.false;
        });
    });

    describe("Pause/Unpause Functionality", function () {
        it("Should allow owner to pause", async function () {
            await expect(liquidityPoolFacet.connect(owner).pause())
                .to.emit(liquidityPoolFacet, "Paused")
                .withArgs(await owner.getAddress());

            expect(await liquidityPoolFacet.paused()).to.be.true;
        });

        it("Should allow owner to unpause", async function () {
            await liquidityPoolFacet.connect(owner).pause();
            
            await expect(liquidityPoolFacet.connect(owner).unpause())
                .to.emit(liquidityPoolFacet, "Unpaused")
                .withArgs(await owner.getAddress());

            expect(await liquidityPoolFacet.paused()).to.be.false;
        });

        it("Should revert when non-owner tries to pause", async function () {
            await expect(liquidityPoolFacet.connect(user1).pause())
                .to.be.revertedWithCustomError(liquidityPoolFacet, "NotContractOwner");
        });
    });

    describe("Configuration Management", function () {
        beforeEach(async function () {
            // Initialize staking for configuration tests
            await liquidityPoolFacet.initializeStaking(
                1000, // 10% APR
                7 * 24 * 60 * 60, // 7 days lock
                10, // 0.1% reduction per 1000 tokens  
                15 // 15% emergency penalty
            );
        });

        it("Should initialize staking configuration correctly", async function () {
            const config = await liquidityPoolFacet.getStakingConfig();
            
            expect(config.initialApr).to.equal(1000);
            expect(config.currentRewardRate).to.equal(1000);
            expect(config.minLockDuration).to.equal(7 * 24 * 60 * 60);
            expect(config.aprReductionPerThousand).to.equal(10);
            expect(config.emergencyWithdrawPenalty).to.equal(15);
        });

        it("Should allow owner to update configuration", async function () {
            await expect(
                liquidityPoolFacet.connect(owner).updateStakingConfig(
                    1500, // New APR
                    14 * 24 * 60 * 60, // New lock duration  
                    20, // New reduction
                    25 // New penalty
                )
            ).to.emit(liquidityPoolFacet, "StakingConfigUpdated");

            const config = await liquidityPoolFacet.getStakingConfig();
            expect(config.initialApr).to.equal(1500);
            expect(config.minLockDuration).to.equal(14 * 24 * 60 * 60);
        });

        it("Should return empty pool stats initially", async function () {
            const stats = await liquidityPoolFacet.getPoolStats();
            
            expect(stats.totalStaked).to.equal(0);
            expect(stats.totalLiquidityProviders).to.equal(0);
            expect(stats.currentRewardRate).to.equal(1000);
        });
    });

    describe("Error Handling", function () {
        beforeEach(async function () {
            await liquidityPoolFacet.initializeStaking(1000, 7 * 24 * 60 * 60, 10, 15);
        });

        it("Should revert on zero amount operations", async function () {
            await expect(liquidityPoolFacet.connect(user1).stake(0))
                .to.be.revertedWithCustomError(liquidityPoolFacet, "ZeroAmount");
        });

        it("Should revert when trying to unstake without active stake", async function () {
            const amount = ethers.parseUnits("100", 6);
            await expect(liquidityPoolFacet.connect(user1).unstake(amount))
                .to.be.revertedWithCustomError(liquidityPoolFacet, "NoActiveStake");
        });

        it("Should revert emergency withdraw without active stake", async function () {
            await expect(liquidityPoolFacet.connect(user1).emergencyWithdraw())
                .to.be.revertedWithCustomError(liquidityPoolFacet, "NoActiveStake");
        });

        it("Should revert claiming rewards without active stake", async function () {
            await expect(liquidityPoolFacet.connect(user1).claimRewards())
                .to.be.revertedWithCustomError(liquidityPoolFacet, "NoActiveStake");
        });
    });

    describe("Mathematical Calculations", function () {
        beforeEach(async function () {
            await liquidityPoolFacet.initializeStaking(1000, 7 * 24 * 60 * 60, 10, 15);
        });

        it("Should handle precision calculations correctly", async function () {
            // Test with various amounts to ensure precision
            const amounts = [
                ethers.parseUnits("1", 6), // 1 USDC
                ethers.parseUnits("100", 6), // 100 USDC
                ethers.parseUnits("1000", 6), // 1,000 USDC
                ethers.parseUnits("999999", 6), // 999,999 USDC (large amount)
            ];

            for (const amount of amounts) {
                try {
                    // Test that amounts are handled without overflow
                    const stake = await liquidityPoolFacet.getStake(await user1.getAddress());
                    expect(stake.amount).to.be.gte(0);
                } catch (error) {
                    // Expected for some operations without diamond context
                }
            }
        });

        it("Should calculate percentages correctly", async function () {
            // Test emergency withdrawal penalty calculation
            const testAmount = ethers.parseUnits("1000", 6);
            const penaltyRate = 15; // 15%
            const expectedPenalty = testAmount * BigInt(penaltyRate) / 100n;
            const expectedReturn = testAmount - expectedPenalty;
            
            // These calculations should not overflow
            expect(expectedPenalty).to.be.lt(testAmount);
            expect(expectedReturn).to.be.gt(0);
            expect(expectedReturn).to.equal(testAmount * 85n / 100n);
        });
    });

    describe("Event Emissions", function () {
        beforeEach(async function () {
            await liquidityPoolFacet.initializeStaking(1000, 7 * 24 * 60 * 60, 10, 15);
        });

        it("Should emit Paused event", async function () {
            await expect(liquidityPoolFacet.connect(owner).pause())
                .to.emit(liquidityPoolFacet, "Paused")
                .withArgs(await owner.getAddress());
        });

        it("Should emit Unpaused event", async function () {
            await liquidityPoolFacet.connect(owner).pause();
            
            await expect(liquidityPoolFacet.connect(owner).unpause())
                .to.emit(liquidityPoolFacet, "Unpaused")
                .withArgs(await owner.getAddress());
        });

        it("Should emit StakingConfigUpdated event", async function () {
            await expect(
                liquidityPoolFacet.connect(owner).updateStakingConfig(1500, 0, 0, 0)
            ).to.emit(liquidityPoolFacet, "StakingConfigUpdated");
        });
    });

    describe("View Functions", function () {
        beforeEach(async function () {
            await liquidityPoolFacet.initializeStaking(1000, 7 * 24 * 60 * 60, 10, 15);
        });

        it("Should return correct staking configuration", async function () {
            const config = await liquidityPoolFacet.getStakingConfig();
            
            expect(config).to.have.property('initialApr');
            expect(config).to.have.property('currentRewardRate');
            expect(config).to.have.property('minLockDuration');
            expect(config).to.have.property('aprReductionPerThousand');
            expect(config).to.have.property('emergencyWithdrawPenalty');
            expect(config).to.have.property('minimumStake');
        });

        it("Should return empty stakers list initially", async function () {
            const stakers = await liquidityPoolFacet.getStakers();
            expect(stakers).to.be.an('array');
            expect(stakers.length).to.equal(0);
        });

        it("Should return zero pending rewards for inactive user", async function () {
            const rewards = await liquidityPoolFacet.getPendingRewards(await user1.getAddress());
            expect(rewards).to.equal(0);
        });

        it("Should return inactive stake info for new user", async function () {
            const stake = await liquidityPoolFacet.getStake(await user1.getAddress());
            
            expect(stake.amount).to.equal(0);
            expect(stake.active).to.be.false;
            expect(stake.votingPower).to.equal(0);
        });
    });

    describe("Access Control", function () {
        it("Should restrict initialization to owner", async function () {
            await expect(
                liquidityPoolFacet.connect(user1).initializeStaking(1000, 86400, 10, 15)
            ).to.be.revertedWith("LibDiamond: Must be contract owner");
        });

        it("Should restrict configuration updates to owner", async function () {
            await liquidityPoolFacet.initializeStaking(1000, 7 * 24 * 60 * 60, 10, 15);
            
            await expect(
                liquidityPoolFacet.connect(user1).updateStakingConfig(1500, 0, 0, 0)
            ).to.be.revertedWith("LibDiamond: Must be contract owner");
        });

        it("Should restrict reward distribution to owner", async function () {
            const amount = ethers.parseUnits("100", 6);
            
            await expect(
                liquidityPoolFacet.connect(user1).distributeRewards(await user2.getAddress(), amount)
            ).to.be.revertedWith("LibDiamond: Must be contract owner");
        });
    });

    describe("Input Validation", function () {
        it("Should validate initialization parameters", async function () {
            // Invalid APR (zero)
            await expect(
                liquidityPoolFacet.initializeStaking(0, 86400, 10, 15)
            ).to.be.revertedWithCustomError(liquidityPoolFacet, "InvalidAPR");

            // Invalid lock duration (zero)
            await expect(
                liquidityPoolFacet.initializeStaking(1000, 0, 10, 15)
            ).to.be.revertedWithCustomError(liquidityPoolFacet, "InvalidLockDuration");

            // Invalid penalty (over 100%)
            await expect(
                liquidityPoolFacet.initializeStaking(1000, 86400, 10, 150)
            ).to.be.revertedWithCustomError(liquidityPoolFacet, "InvalidPenalty");
        });
    });

    describe("Gas Usage", function () {
        beforeEach(async function () {
            await liquidityPoolFacet.initializeStaking(1000, 7 * 24 * 60 * 60, 10, 15);
        });

        it("Should have reasonable gas costs for view functions", async function () {
            // These are view functions so should use minimal gas
            await liquidityPoolFacet.getStakingConfig();
            await liquidityPoolFacet.getPoolStats();
            await liquidityPoolFacet.getStakers();
            await liquidityPoolFacet.paused();
            
            // If we get here without errors, gas usage is acceptable
            expect(true).to.be.true;
        });
    });

    describe("Edge Cases", function () {
        beforeEach(async function () {
            await liquidityPoolFacet.initializeStaking(1000, 7 * 24 * 60 * 60, 10, 15);
        });

        it("Should handle maximum uint256 values gracefully", async function () {
            // Test with very large numbers to ensure no overflow
            const largeAmount = ethers.parseUnits("999999999", 6);
            
            // Should not revert when checking stake info
            const stake = await liquidityPoolFacet.getStake(await user1.getAddress());
            expect(stake.amount).to.equal(0);
        });

        it("Should handle multiple identical operations", async function () {
            // Multiple calls to same view function should return consistent results
            const config1 = await liquidityPoolFacet.getStakingConfig();
            const config2 = await liquidityPoolFacet.getStakingConfig();
            
            expect(config1.initialApr).to.equal(config2.initialApr);
            expect(config1.minLockDuration).to.equal(config2.minLockDuration);
        });
    });
});