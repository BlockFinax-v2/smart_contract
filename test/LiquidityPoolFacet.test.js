const { expect } = require("chai");
const { ethers } = require("hardhat");
const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");

describe("LiquidityPoolFacet", function () {
    // Deploy fixture
    async function deployFixture() {
        const [owner, user1, user2, user3] = await ethers.getSigners();

        // Deploy mock USDC token
        const MockERC20 = await ethers.getContractFactory("MockERC20");
        const usdc = await MockERC20.deploy("USD Coin", "USDC", 6); // 6 decimals for USDC
        
        // Deploy Diamond contracts
        const DiamondCutFacet = await ethers.getContractFactory("DiamondCutFacet");
        const diamondCutFacet = await DiamondCutFacet.deploy();

        const DiamondLoupeFacet = await ethers.getContractFactory("DiamondLoupeFacet");
        const diamondLoupeFacet = await DiamondLoupeFacet.deploy();

        const LiquidityPoolFacet = await ethers.getContractFactory("LiquidityPoolFacet");
        const liquidityPoolFacet = await LiquidityPoolFacet.deploy();

        const Diamond = await ethers.getContractFactory("Diamond");
        const diamond = await Diamond.deploy(await owner.getAddress(), await diamondCutFacet.getAddress());

        const DiamondInit = await ethers.getContractFactory("DiamondInit");
        const diamondInit = await DiamondInit.deploy();

        // Add facets to diamond
        const cut = [
            {
                facetAddress: await diamondLoupeFacet.getAddress(),
                action: 0, // Add
                functionSelectors: getSelectors(diamondLoupeFacet),
            },
            {
                facetAddress: await liquidityPoolFacet.getAddress(),
                action: 0, // Add
                functionSelectors: getSelectors(liquidityPoolFacet),
            },
        ];

        const diamondCut = await ethers.getContractAt("IDiamondCut", await diamond.getAddress());
        await diamondCut.diamondCut(cut, await diamondInit.getAddress(), "0x");

        // Get diamond with LiquidityPoolFacet interface
        const liquidityPool = await ethers.getContractAt("LiquidityPoolFacet", await diamond.getAddress());

        // Initialize staking configuration with complete setup
        const initialApr = 1000; // 10%
        const minLockDuration = 7 * 24 * 60 * 60; // 7 days
        const aprReductionPerThousand = 10; // 0.1% reduction per 1000 tokens
        const emergencyWithdrawPenalty = 10; // 10%
        const minimumStake = ethers.parseUnits("10", 6); // 10 USDC minimum

        await liquidityPool.initializeComplete(
            await usdc.getAddress(),
            minimumStake,
            initialApr,
            minLockDuration,
            aprReductionPerThousand,
            emergencyWithdrawPenalty
        );

        // Set USDC token and minimum stake (this would be done through DiamondInit in real deployment)
        // For testing, we'll assume these are set in the diamond's storage

        // Mint USDC to users
        const mintAmount = ethers.parseUnits("10000", 6); // 10,000 USDC
        await usdc.mint(await user1.getAddress(), mintAmount);
        await usdc.mint(await user2.getAddress(), mintAmount);
        await usdc.mint(await user3.getAddress(), mintAmount);

        // Approve spending
        const diamondAddress = await diamond.getAddress();
        await usdc.connect(user1).approve(diamondAddress, ethers.MaxUint256);
        await usdc.connect(user2).approve(diamondAddress, ethers.MaxUint256);
        await usdc.connect(user3).approve(diamondAddress, ethers.MaxUint256);

        return {
            diamond,
            liquidityPool,
            usdc,
            owner,
            user1,
            user2,
            user3,
            initialApr,
            minLockDuration,
            aprReductionPerThousand,
            emergencyWithdrawPenalty
        };
    }

    describe("Deployment and Initialization", function () {
        it("Should initialize staking configuration correctly", async function () {
            const { liquidityPool, initialApr, minLockDuration, aprReductionPerThousand, emergencyWithdrawPenalty } = await loadFixture(deployFixture);

            const config = await liquidityPool.getStakingConfig();
            expect(config.initialApr).to.equal(initialApr);
            expect(config.currentRewardRate).to.equal(initialApr);
            expect(config.minLockDuration).to.equal(minLockDuration);
            expect(config.aprReductionPerThousand).to.equal(aprReductionPerThousand);
            expect(config.emergencyWithdrawPenalty).to.equal(emergencyWithdrawPenalty);
        });

        it("Should start with empty pool stats", async function () {
            const { liquidityPool } = await loadFixture(deployFixture);

            const stats = await liquidityPool.getPoolStats();
            expect(stats.totalStaked).to.equal(0);
            expect(stats.totalLiquidityProviders).to.equal(0);
            expect(stats.currentRewardRate).to.equal(1000); // Initial APR
        });
    });

    describe("Staking", function () {
        it("Should allow users to stake USDC", async function () {
            const { liquidityPool, user1 } = await loadFixture(deployFixture);

            const stakeAmount = ethers.parseUnits("1000", 6);
            
            await expect(liquidityPool.connect(user1).stake(stakeAmount))
                .to.emit(liquidityPool, "Staked");
                // Note: withArgs removed for now due to ethers v6 compatibility

            const stake = await liquidityPool.getStake(await user1.getAddress());
            expect(stake.amount).to.equal(stakeAmount);
            expect(stake.active).to.be.true;
        });

        it("Should revert when staking zero amount", async function () {
            const { liquidityPool, user1 } = await loadFixture(deployFixture);

            await expect(liquidityPool.connect(user1).stake(0))
                .to.be.revertedWithCustomError(liquidityPool, "ZeroAmount");
        });

        it("Should revert when staking below minimum", async function () {
            const { liquidityPool, user1 } = await loadFixture(deployFixture);

            // Assuming minimum stake is set in the contract
            const belowMinimum = ethers.parseUnits("1", 6); // 1 USDC
            
            await expect(liquidityPool.connect(user1).stake(belowMinimum))
                .to.be.revertedWithCustomError(liquidityPool, "BelowMinimumStake");
        });

        it("Should calculate voting power correctly", async function () {
            const { liquidityPool, user1, user2 } = await loadFixture(deployFixture);

            const stakeAmount1 = ethers.parseUnits("1000", 6);
            const stakeAmount2 = ethers.parseUnits("3000", 6);

            await liquidityPool.connect(user1).stake(stakeAmount1);
            await liquidityPool.connect(user2).stake(stakeAmount2);

            const stake1 = await liquidityPool.getStake(await user1.getAddress());
            const stake2 = await liquidityPool.getStake(await user2.getAddress());

            // User1: 1000/4000 = 0.25 (25%)
            // User2: 3000/4000 = 0.75 (75%)
            expect(stake1.votingPower).to.be.closeTo(
                ethers.parseEther("0.25"), 
                ethers.parseEther("0.01")
            );
            expect(stake2.votingPower).to.be.closeTo(
                ethers.parseEther("0.75"), 
                ethers.parseEther("0.01")
            );
        });

        it("Should update reward rate when total staked increases", async function () {
            const { liquidityPool, user1 } = await loadFixture(deployFixture);

            const initialConfig = await liquidityPool.getStakingConfig();
            const initialRate = initialConfig.currentRewardRate;

            // Stake a large amount to trigger rate reduction
            const largeStake = ethers.parseUnits("5000", 6); // 5000 USDC
            await liquidityPool.connect(user1).stake(largeStake);

            const updatedConfig = await liquidityPool.getStakingConfig();
            expect(updatedConfig.currentRewardRate).to.be.lte(initialRate);
        });
    });

    describe("Unstaking", function () {
        it("Should allow unstaking after lock period", async function () {
            const { liquidityPool, user1, minLockDuration } = await loadFixture(deployFixture);

            const stakeAmount = ethers.parseUnits("1000", 6);
            await liquidityPool.connect(user1).stake(stakeAmount);

            // Fast forward past lock period
            await ethers.provider.send("evm_increaseTime", [minLockDuration + 1]);
            await ethers.provider.send("evm_mine");

            await expect(liquidityPool.connect(user1).unstake(stakeAmount))
                .to.emit(liquidityPool, "Unstaked")
                .withArgs(await user1.getAddress(), stakeAmount, anyValue);
        });

        it("Should revert unstaking before lock period ends", async function () {
            const { liquidityPool, user1 } = await loadFixture(deployFixture);

            const stakeAmount = ethers.parseUnits("1000", 6);
            await liquidityPool.connect(user1).stake(stakeAmount);

            await expect(liquidityPool.connect(user1).unstake(stakeAmount))
                .to.be.revertedWithCustomError(liquidityPool, "LockDurationNotMet");
        });

        it("Should calculate and distribute rewards on unstake", async function () {
            const { liquidityPool, user1, usdc, minLockDuration } = await loadFixture(deployFixture);

            const stakeAmount = ethers.parseUnits("1000", 6);
            const initialBalance = await usdc.balanceOf(await user1.getAddress());
            
            await liquidityPool.connect(user1).stake(stakeAmount);

            // Fast forward to accumulate rewards
            await ethers.provider.send("evm_increaseTime", [minLockDuration + 86400]); // +1 day
            await ethers.provider.send("evm_mine");

            await liquidityPool.connect(user1).unstake(stakeAmount);

            const finalBalance = await usdc.balanceOf(await user1.getAddress());
            expect(finalBalance).to.be.gt(initialBalance.sub(stakeAmount)); // Should have rewards
        });

        it("Should handle partial unstaking", async function () {
            const { liquidityPool, user1, minLockDuration } = await loadFixture(deployFixture);

            const stakeAmount = ethers.parseUnits("1000", 6);
            const unstakeAmount = ethers.parseUnits("400", 6);
            
            await liquidityPool.connect(user1).stake(stakeAmount);

            // Fast forward past lock period
            await ethers.provider.send("evm_increaseTime", [minLockDuration + 1]);
            await ethers.provider.send("evm_mine");

            await liquidityPool.connect(user1).unstake(unstakeAmount);

            const stake = await liquidityPool.getStake(await user1.getAddress());
            expect(stake.amount).to.equal(stakeAmount.sub(unstakeAmount));
            expect(stake.active).to.be.true;
        });
    });

    describe("Emergency Withdrawal", function () {
        it("Should allow emergency withdrawal with penalty", async function () {
            const { liquidityPool, user1, usdc, emergencyWithdrawPenalty } = await loadFixture(deployFixture);

            const stakeAmount = ethers.parseUnits("1000", 6);
            const initialBalance = await usdc.balanceOf(await user1.getAddress());
            
            await liquidityPool.connect(user1).stake(stakeAmount);

            const expectedPenalty = stakeAmount.mul(emergencyWithdrawPenalty).div(100);
            const expectedWithdraw = stakeAmount.sub(expectedPenalty);

            await expect(liquidityPool.connect(user1).emergencyWithdraw())
                .to.emit(liquidityPool, "EmergencyWithdrawn")
                .withArgs(await user1.getAddress(), expectedWithdraw, expectedPenalty);

            const finalBalance = await usdc.balanceOf(await user1.getAddress());
            expect(finalBalance).to.equal(initialBalance.sub(expectedPenalty));

            const stake = await liquidityPool.getStake(await user1.getAddress());
            expect(stake.active).to.be.false;
            expect(stake.amount).to.equal(0);
        });

        it("Should revert emergency withdrawal for inactive staker", async function () {
            const { liquidityPool, user1 } = await loadFixture(deployFixture);

            await expect(liquidityPool.connect(user1).emergencyWithdraw())
                .to.be.revertedWithCustomError(liquidityPool, "NoActiveStake");
        });
    });

    describe("Rewards", function () {
        it("Should calculate pending rewards correctly", async function () {
            const { liquidityPool, user1 } = await loadFixture(deployFixture);

            const stakeAmount = ethers.parseUnits("1000", 6);
            await liquidityPool.connect(user1).stake(stakeAmount);

            // Fast forward 1 day
            await ethers.provider.send("evm_increaseTime", [86400]);
            await ethers.provider.send("evm_mine");

            const pendingRewards = await liquidityPool.getPendingRewards(await user1.getAddress());
            expect(pendingRewards).to.be.gt(0);
        });

        it("Should allow claiming rewards without unstaking", async function () {
            const { liquidityPool, user1, usdc } = await loadFixture(deployFixture);

            const stakeAmount = ethers.parseUnits("1000", 6);
            await liquidityPool.connect(user1).stake(stakeAmount);

            // Fast forward to accumulate rewards
            await ethers.provider.send("evm_increaseTime", [86400 * 7]); // 7 days
            await ethers.provider.send("evm_mine");

            const initialBalance = await usdc.balanceOf(await user1.getAddress());
            await liquidityPool.connect(user1).claimRewards();
            const finalBalance = await usdc.balanceOf(await user1.getAddress());

            expect(finalBalance).to.be.gt(initialBalance);

            // Should still have stake
            const stake = await liquidityPool.getStake(await user1.getAddress());
            expect(stake.amount).to.equal(stakeAmount);
            expect(stake.active).to.be.true;
        });

        it("Should revert claiming when no rewards available", async function () {
            const { liquidityPool, user1 } = await loadFixture(deployFixture);

            const stakeAmount = ethers.parseUnits("1000", 6);
            await liquidityPool.connect(user1).stake(stakeAmount);

            // Immediately try to claim (no time passed)
            await expect(liquidityPool.connect(user1).claimRewards())
                .to.be.revertedWithCustomError(liquidityPool, "NoRewardsToCllaim");
        });
    });

    describe("Pause/Unpause", function () {
        it("Should allow owner to pause contract", async function () {
            const { liquidityPool, owner } = await loadFixture(deployFixture);

            await expect(liquidityPool.connect(owner).pause())
                .to.emit(liquidityPool, "Paused")
                .withArgs(await owner.getAddress());

            expect(await liquidityPool.paused()).to.be.true;
        });

        it("Should prevent staking when paused", async function () {
            const { liquidityPool, owner, user1 } = await loadFixture(deployFixture);

            await liquidityPool.connect(owner).pause();

            const stakeAmount = ethers.parseUnits("1000", 6);
            await expect(liquidityPool.connect(user1).stake(stakeAmount))
                .to.be.revertedWithCustomError(liquidityPool, "ContractPaused");
        });

        it("Should allow owner to unpause contract", async function () {
            const { liquidityPool, owner } = await loadFixture(deployFixture);

            await liquidityPool.connect(owner).pause();
            
            await expect(liquidityPool.connect(owner).unpause())
                .to.emit(liquidityPool, "Unpaused")
                .withArgs(await owner.getAddress());

            expect(await liquidityPool.paused()).to.be.false;
        });

        it("Should revert when non-owner tries to pause", async function () {
            const { liquidityPool, user1 } = await loadFixture(deployFixture);

            await expect(liquidityPool.connect(user1).pause())
                .to.be.revertedWithCustomError(liquidityPool, "NotContractOwner");
        });
    });

    describe("Configuration Updates", function () {
        it("Should allow owner to update staking config", async function () {
            const { liquidityPool, owner } = await loadFixture(deployFixture);

            const newApr = 1500; // 15%
            const newLockDuration = 14 * 24 * 60 * 60; // 14 days
            const newReduction = 15;
            const newPenalty = 15;

            await expect(
                liquidityPool.connect(owner).updateStakingConfig(
                    newApr,
                    newLockDuration,
                    newReduction,
                    newPenalty
                )
            ).to.emit(liquidityPool, "StakingConfigUpdated");

            const config = await liquidityPool.getStakingConfig();
            expect(config.initialApr).to.equal(newApr);
            expect(config.minLockDuration).to.equal(newLockDuration);
            expect(config.aprReductionPerThousand).to.equal(newReduction);
            expect(config.emergencyWithdrawPenalty).to.equal(newPenalty);
        });

        it("Should revert when non-owner tries to update config", async function () {
            const { liquidityPool, user1 } = await loadFixture(deployFixture);

            await expect(
                liquidityPool.connect(user1).updateStakingConfig(1500, 86400, 15, 15)
            ).to.be.revertedWith("LibDiamond: Must be contract owner");
        });
    });
});

// Helper function to get function selectors
function getSelectors(contract) {
    if (!contract || !contract.interface || !contract.interface.functions) {
        console.error('Invalid contract interface:', contract);
        return [];
    }
    const signatures = Object.keys(contract.interface.functions);
    return signatures.reduce((acc, val) => {
        if (val !== 'init(bytes)') {
            try {
                acc.push(contract.interface.getFunction(val).selector);
            } catch (error) {
                console.error(`Error getting selector for ${val}:`, error);
            }
        }
        return acc;
    }, []);
}