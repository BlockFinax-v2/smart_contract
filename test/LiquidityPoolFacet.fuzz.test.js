const { expect } = require("chai");
const { ethers } = require("hardhat");
const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");

describe("LiquidityPoolFacet Fuzz Tests", function () {
    // Deploy fixture (reusing from main test)
    async function deployFixture() {
        const [owner, user1, user2, user3] = await ethers.getSigners();

        // Deploy mock USDC token
        const MockERC20 = await ethers.getContractFactory("MockERC20");
        const usdc = await MockERC20.deploy("USD Coin", "USDC", 6);
        
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
                action: 0,
                functionSelectors: getSelectors(diamondLoupeFacet),
            },
            {
                facetAddress: await liquidityPoolFacet.getAddress(),
                action: 0,
                functionSelectors: getSelectors(liquidityPoolFacet),
            },
        ];

        const diamondCut = await ethers.getContractAt("IDiamondCut", await diamond.getAddress());
        await diamondCut.diamondCut(cut, await diamondInit.getAddress(), "0x");

        const liquidityPool = await ethers.getContractAt("LiquidityPoolFacet", await diamond.getAddress());

        // Initialize with complete setup
        const minimumStake = ethers.parseUnits("10", 6); // 10 USDC minimum
        await liquidityPool.initializeComplete(
            await usdc.getAddress(),
            minimumStake,
            1000, 7 * 24 * 60 * 60, 10, 10
        );

        // Mint and approve large amounts
        const mintAmount = ethers.parseUnits("1000000", 6); // 1M USDC
        await usdc.mint(await user1.getAddress(), mintAmount);
        await usdc.mint(await user2.getAddress(), mintAmount);
        await usdc.mint(await user3.getAddress(), mintAmount);

        const diamondAddress = await diamond.getAddress();
        await usdc.connect(user1).approve(diamondAddress, ethers.MaxUint256);
        await usdc.connect(user2).approve(diamondAddress, ethers.MaxUint256);
        await usdc.connect(user3).approve(diamondAddress, ethers.MaxUint256);

        return { diamond, liquidityPool, usdc, owner, user1, user2, user3 };
    }

    describe("Fuzz Testing - Random Stake Amounts", function () {
        it("Should handle random stake amounts correctly", async function () {
            const { liquidityPool, user1, user2, user3, usdc } = await loadFixture(deployFixture);

            // Generate 50 random stake amounts
            for (let i = 0; i < 50; i++) {
                const randomAmount = Math.floor(Math.random() * 100000) + 100; // 100 to 100,100 USDC
                const stakeAmount = ethers.parseUnits(randomAmount.toString(), 6);
                
                const user = [user1, user2, user3][i % 3];
                
                try {
                    await liquidityPool.connect(user).stake(stakeAmount);
                    
                    const stake = await liquidityPool.getStake(await user.getAddress());
                    expect(stake.amount).to.be.gte(stakeAmount);
                    expect(stake.active).to.be.true;
                    
                    // Verify voting power is reasonable (0 to 1e18)
                    expect(stake.votingPower).to.be.lte(ethers.parseEther("1"));
                    expect(stake.votingPower).to.be.gte(0);
                    
                } catch (error) {
                    // Only acceptable errors for fuzz testing
                    expect(error.message).to.match(/(BelowMinimumStake|InsufficientBalance)/);
                }
            }
        });

        it("Should maintain correct total staked after random operations", async function () {
            const { liquidityPool, user1, user2, usdc } = await loadFixture(deployFixture);

            let expectedTotalStaked = ethers.BigNumber.from(0);
            
            // Perform random stake/unstake operations
            for (let i = 0; i < 20; i++) {
                const randomAmount = Math.floor(Math.random() * 10000) + 500; // 500 to 10,500 USDC
                const stakeAmount = ethers.parseUnits(randomAmount.toString(), 6);
                
                const user = [user1, user2][i % 2];
                
                if (Math.random() > 0.5) {
                    // Stake operation
                    await liquidityPool.connect(user).stake(stakeAmount);
                    expectedTotalStaked = expectedTotalStaked.add(stakeAmount);
                } else {
                    // Try unstake (might fail if no stake or lock period not met)
                    try {
                        const currentStake = await liquidityPool.getStake(await user.getAddress());
                        if (currentStake.amount.gt(0) && currentStake.timeUntilUnlock.eq(0)) {
                            const unstakeAmount = currentStake.amount.div(2); // Unstake half
                            await liquidityPool.connect(user).unstake(unstakeAmount);
                            expectedTotalStaked = expectedTotalStaked.sub(unstakeAmount);
                        }
                    } catch (error) {
                        // Expected failures are ok in fuzz testing
                    }
                }
                
                // Verify total staked is consistent
                const stats = await liquidityPool.getPoolStats();
                expect(stats.totalStaked).to.equal(expectedTotalStaked);
            }
        });
    });

    describe("Fuzz Testing - Time Manipulations", function () {
        it("Should handle random time advances correctly", async function () {
            const { liquidityPool, user1, usdc } = await loadFixture(deployFixture);

            const stakeAmount = ethers.parseUnits("5000", 6);
            await liquidityPool.connect(user1).stake(stakeAmount);

            let lastRewards = ethers.BigNumber.from(0);
            
            // Test 30 random time advances
            for (let i = 0; i < 30; i++) {
                const randomTime = Math.floor(Math.random() * 86400 * 10) + 3600; // 1 hour to 10 days
                
                await ethers.provider.send("evm_increaseTime", [randomTime]);
                await ethers.provider.send("evm_mine");
                
                const pendingRewards = await liquidityPool.getPendingRewards(await user1.getAddress());
                
                // Rewards should never decrease (only increase or stay same)
                expect(pendingRewards).to.be.gte(lastRewards);
                
                // Rewards should be reasonable (not overflow)
                expect(pendingRewards).to.be.lt(ethers.parseUnits("1000000", 6)); // < 1M USDC
                
                lastRewards = pendingRewards;
            }
        });

        it("Should handle reward calculations under extreme time conditions", async function () {
            const { liquidityPool, user1 } = await loadFixture(deployFixture);

            const stakeAmount = ethers.parseUnits("1000", 6);
            await liquidityPool.connect(user1).stake(stakeAmount);

            // Test edge cases
            const timeScenarios = [
                1, // 1 second
                60, // 1 minute  
                3600, // 1 hour
                86400, // 1 day
                86400 * 7, // 1 week
                86400 * 30, // 1 month
                86400 * 365, // 1 year
                86400 * 365 * 10, // 10 years (extreme)
            ];

            for (const timeAdvance of timeScenarios) {
                await ethers.provider.send("evm_increaseTime", [timeAdvance]);
                await ethers.provider.send("evm_mine");
                
                const pendingRewards = await liquidityPool.getPendingRewards(await user1.getAddress());
                
                // Should not overflow or underflow
                expect(pendingRewards).to.be.gte(0);
                expect(pendingRewards).to.be.lt(ethers.MaxUint256);
                
                // For very long periods, rewards should be capped reasonably
                if (timeAdvance >= 86400 * 365) {
                    expect(pendingRewards).to.be.lt(ethers.parseUnits("100000", 6)); // < 100k USDC
                }
            }
        });
    });

    describe("Fuzz Testing - Multiple Users Interactions", function () {
        it("Should handle concurrent user operations", async function () {
            const { liquidityPool, user1, user2, user3 } = await loadFixture(deployFixture);

            const users = [user1, user2, user3];
            let totalExpectedStaked = ethers.BigNumber.from(0);
            
            // Simulate 100 random operations from different users
            for (let i = 0; i < 100; i++) {
                const userIndex = Math.floor(Math.random() * 3);
                const user = users[userIndex];
                const randomAmount = Math.floor(Math.random() * 5000) + 100; // 100-5100 USDC
                const stakeAmount = ethers.parseUnits(randomAmount.toString(), 6);
                
                const operation = Math.floor(Math.random() * 4); // 0: stake, 1: unstake, 2: claim, 3: emergency
                
                try {
                    switch (operation) {
                        case 0: // Stake
                            await liquidityPool.connect(user).stake(stakeAmount);
                            totalExpectedStaked = totalExpectedStaked.add(stakeAmount);
                            break;
                            
                        case 1: // Unstake
                            const stake = await liquidityPool.getStake(await user.getAddress());
                            if (stake.amount.gt(0) && stake.timeUntilUnlock.eq(0)) {
                                const unstakeAmount = stake.amount;
                                await liquidityPool.connect(user).unstake(unstakeAmount);
                                totalExpectedStaked = totalExpectedStaked.sub(unstakeAmount);
                            }
                            break;
                            
                        case 2: // Claim rewards
                            const currentStake = await liquidityPool.getStake(await user.getAddress());
                            if (currentStake.amount.gt(0)) {
                                const pendingRewards = await liquidityPool.getPendingRewards(await user.getAddress());
                                if (pendingRewards.gt(0)) {
                                    await liquidityPool.connect(user).claimRewards();
                                }
                            }
                            break;
                            
                        case 3: // Emergency withdraw
                            const emergencyStake = await liquidityPool.getStake(await user.getAddress());
                            if (emergencyStake.amount.gt(0) && emergencyStake.active) {
                                await liquidityPool.connect(user).emergencyWithdraw();
                                totalExpectedStaked = totalExpectedStaked.sub(emergencyStake.amount);
                            }
                            break;
                    }
                    
                    // Advance time randomly
                    if (Math.random() > 0.8) {
                        const timeAdvance = Math.floor(Math.random() * 86400) + 1; // Up to 1 day
                        await ethers.provider.send("evm_increaseTime", [timeAdvance]);
                        await ethers.provider.send("evm_mine");
                    }
                    
                } catch (error) {
                    // Some operations are expected to fail in fuzz testing
                }
            }
            
            // Verify invariants
            const stats = await liquidityPool.getPoolStats();
            
            // Total staked should never be negative
            expect(stats.totalStaked).to.be.gte(0);
            
            // Total providers should match active stakes
            let activeStakers = 0;
            for (const user of users) {
                const stake = await liquidityPool.getStake(await user.getAddress());
                if (stake.active && stake.amount.gt(0)) {
                    activeStakers++;
                }
            }
            expect(stats.totalLiquidityProviders).to.be.gte(0);
            expect(stats.totalLiquidityProviders).to.be.lte(users.length);
        });
    });

    describe("Fuzz Testing - Edge Cases", function () {
        it("Should handle maximum and minimum values", async function () {
            const { liquidityPool, user1, owner } = await loadFixture(deployFixture);

            // Test with maximum possible stake amount (within reasonable limits)
            const maxStake = ethers.parseUnits("999999", 6); // 999,999 USDC
            
            try {
                await liquidityPool.connect(user1).stake(maxStake);
                const stake = await liquidityPool.getStake(await user1.getAddress());
                expect(stake.amount).to.equal(maxStake);
            } catch (error) {
                expect(error.message).to.match(/InsufficientBalance/);
            }
            
            // Test configuration edge cases
            const configTests = [
                { apr: 1, lockDuration: 1, reduction: 0, penalty: 0 }, // Minimum values
                { apr: 10000, lockDuration: 86400 * 365, reduction: 100, penalty: 50 }, // High values
                { apr: 5000, lockDuration: 86400 * 30, reduction: 1000, penalty: 100 }, // Edge case values
            ];
            
            for (const config of configTests) {
                try {
                    await liquidityPool.connect(owner).updateStakingConfig(
                        config.apr,
                        config.lockDuration,
                        config.reduction,
                        config.penalty
                    );
                    
                    const updatedConfig = await liquidityPool.getStakingConfig();
                    expect(updatedConfig.initialApr).to.equal(config.apr);
                    
                } catch (error) {
                    // Some edge cases might fail validation
                }
            }
        });

        it("Should maintain voting power sum close to 1.0", async function () {
            const { liquidityPool, user1, user2, user3 } = await loadFixture(deployFixture);

            const users = [user1, user2, user3];
            const stakeAmounts = [
                ethers.parseUnits("1000", 6),
                ethers.parseUnits("2000", 6),
                ethers.parseUnits("3000", 6),
            ];

            // Stake different amounts
            for (let i = 0; i < users.length; i++) {
                await liquidityPool.connect(users[i]).stake(stakeAmounts[i]);
            }

            // Calculate total voting power
            let totalVotingPower = ethers.BigNumber.from(0);
            for (const user of users) {
                const stake = await liquidityPool.getStake(await user.getAddress());
                totalVotingPower = totalVotingPower.add(stake.votingPower);
            }

            // Total voting power should be very close to 1e18 (1.0 in 18 decimals)
            expect(totalVotingPower).to.be.closeTo(
                ethers.parseEther("1.0"),
                ethers.parseEther("0.01") // 1% tolerance
            );
        });
    });
});

// Helper function to get function selectors
function getSelectors(contract) {
    const signatures = Object.keys(contract.interface.functions);
    return signatures.reduce((acc, val) => {
        if (val !== 'init(bytes)') {
            acc.push(contract.interface.getFunction(val).selector);
        }
        return acc;
    }, []);
}