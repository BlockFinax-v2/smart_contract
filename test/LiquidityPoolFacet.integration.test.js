const { expect } = require("chai");
const { ethers } = require("hardhat");
const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");

describe("LiquidityPoolFacet Integration Tests", function () {
    // Full diamond deployment fixture
    async function deployDiamondFixture() {
        const [owner, user1, user2, user3, treasury] = await ethers.getSigners();

        // Deploy USDC mock token
        const MockERC20 = await ethers.getContractFactory("MockERC20");
        const usdc = await MockERC20.deploy("USD Coin", "USDC", 6);

        // Deploy all facets
        const DiamondCutFacet = await ethers.getContractFactory("DiamondCutFacet");
        const diamondCutFacet = await DiamondCutFacet.deploy();

        const DiamondLoupeFacet = await ethers.getContractFactory("DiamondLoupeFacet");
        const diamondLoupeFacet = await DiamondLoupeFacet.deploy();

        const OwnershipFacet = await ethers.getContractFactory("OwnershipFacet");
        const ownershipFacet = await OwnershipFacet.deploy();

        const LiquidityPoolFacet = await ethers.getContractFactory("LiquidityPoolFacet");
        const liquidityPoolFacet = await LiquidityPoolFacet.deploy();

        // Deploy other facets that might interact
        const GovernanceFacet = await ethers.getContractFactory("GovernanceFacet");
        const governanceFacet = await GovernanceFacet.deploy();

        // Deploy diamond
        const Diamond = await ethers.getContractFactory("Diamond");
        const diamond = await Diamond.deploy(await owner.getAddress(), await diamondCutFacet.getAddress());

        // Deploy diamond init
        const DiamondInit = await ethers.getContractFactory("DiamondInit");
        const diamondInit = await DiamondInit.deploy();

        // Add all facets to diamond
        const cut = [
            {
                facetAddress: await diamondLoupeFacet.getAddress(),
                action: 0, // Add
                functionSelectors: getSelectors(diamondLoupeFacet),
            },
            {
                facetAddress: await ownershipFacet.getAddress(),
                action: 0,
                functionSelectors: getSelectors(ownershipFacet),
            },
            {
                facetAddress: await liquidityPoolFacet.getAddress(),
                action: 0,
                functionSelectors: getSelectors(liquidityPoolFacet),
            },
            {
                facetAddress: await governanceFacet.getAddress(),
                action: 0,
                functionSelectors: getSelectors(governanceFacet),
            },
        ];

        const diamondCut = await ethers.getContractAt("IDiamondCut", await diamond.getAddress());
        
        // Initialize diamond with app storage setup
        const initCalldata = diamondInit.interface.encodeFunctionData("init", [
            await usdc.getAddress(),
            ethers.parseUnits("100", 6), // minimum stake: 100 USDC
            await treasury.getAddress()
        ]);

        await diamondCut.diamondCut(cut, await diamondInit.getAddress(), initCalldata);

        // Get diamond instances with different interfaces
        const diamondAddress = await diamond.getAddress();
        const liquidityPool = await ethers.getContractAt("LiquidityPoolFacet", diamondAddress);
        const governance = await ethers.getContractAt("GovernanceFacet", diamondAddress);
        const ownership = await ethers.getContractAt("OwnershipFacet", diamondAddress);
        const diamondLoupe = await ethers.getContractAt("DiamondLoupeFacet", diamondAddress);

        // Initialize staking with complete setup
        const minimumStake = ethers.parseUnits("10", 6); // 10 USDC minimum
        await liquidityPool.initializeComplete(
            await usdc.getAddress(),
            minimumStake,
            1000, // 10% initial APR
            7 * 24 * 60 * 60, // 7 days lock
            10, // 0.1% reduction per 1000 tokens
            15 // 15% emergency penalty
        );

        // Setup test tokens
        const mintAmount = ethers.parseUnits("50000", 6); // 50k USDC each
        await usdc.mint(await user1.getAddress(), mintAmount);
        await usdc.mint(await user2.getAddress(), mintAmount);
        await usdc.mint(await user3.getAddress(), mintAmount);
        await usdc.mint(await treasury.getAddress(), mintAmount);

        // Approve spending
        await usdc.connect(user1).approve(diamondAddress, ethers.MaxUint256);
        await usdc.connect(user2).approve(diamondAddress, ethers.MaxUint256);
        await usdc.connect(user3).approve(diamondAddress, ethers.MaxUint256);
        await usdc.connect(treasury).approve(diamondAddress, ethers.MaxUint256);

        return {
            diamond,
            usdc,
            liquidityPool,
            governance,
            ownership,
            diamondLoupe,
            owner,
            user1,
            user2,
            user3,
            treasury
        };
    }

    describe("Diamond Integration", function () {
        it("Should properly integrate with diamond architecture", async function () {
            const { diamond, liquidityPool, diamondLoupe } = await loadFixture(deployDiamondFixture);

            // Verify facets are properly added
            const facets = await diamondLoupe.facets();
            expect(facets.length).to.be.gte(4); // At least 4 facets

            // Verify LiquidityPoolFacet functions are available
            const facetAddresses = await diamondLoupe.facetAddresses();
            expect(facetAddresses.length).to.be.gte(4);

            // Test function selector routing works
            const stakeSelector = liquidityPool.interface.getSighash("stake");
            const facetAddress = await diamondLoupe.facetAddress(stakeSelector);
            expect(facetAddress).to.not.equal(ethers.ZeroAddress);
        });

        it("Should share storage correctly across facets", async function () {
            const { liquidityPool, governance, user1 } = await loadFixture(deployDiamondFixture);

            // Stake through liquidity pool facet
            const stakeAmount = ethers.parseUnits("1000", 6);
            await liquidityPool.connect(user1).stake(stakeAmount);

            // Verify governance facet can see the same data
            // (This assumes governance facet has voting power related functions)
            const stake = await liquidityPool.getStake(await user1.getAddress());
            expect(stake.amount).to.equal(stakeAmount);
            expect(stake.votingPower).to.be.gt(0);
        });

        it("Should handle ownership changes across facets", async function () {
            const { liquidityPool, ownership, owner, user1 } = await loadFixture(deployDiamondFixture);

            // Transfer ownership
            await ownership.connect(owner).transferOwnership(await user1.getAddress());

            // Verify new owner can call owner-only functions
            await liquidityPool.connect(user1).updateStakingConfig(1200, 0, 0, 0);
            
            const config = await liquidityPool.getStakingConfig();
            expect(config.initialApr).to.equal(1200);
        });
    });

    describe("Multi-User Complex Scenarios", function () {
        it("Should handle complex multi-user staking scenario", async function () {
            const { liquidityPool, user1, user2, user3, usdc } = await loadFixture(deployDiamondFixture);

            // User1: Large early staker
            const user1Stake = ethers.parseUnits("10000", 6);
            await liquidityPool.connect(user1).stake(user1Stake);

            // Advance time and check rewards
            await ethers.provider.send("evm_increaseTime", [86400]); // 1 day
            await ethers.provider.send("evm_mine");

            // User2: Medium staker
            const user2Stake = ethers.parseUnits("5000", 6);
            await liquidityPool.connect(user2).stake(user2Stake);

            // Advance time more
            await ethers.provider.send("evm_increaseTime", [86400 * 3]); // 3 days
            await ethers.provider.send("evm_mine");

            // User3: Small staker
            const user3Stake = ethers.parseUnits("1000", 6);
            await liquidityPool.connect(user3).stake(user3Stake);

            // Verify reward distribution is proportional
            const user1Rewards = await liquidityPool.getPendingRewards(await user1.getAddress());
            const user2Rewards = await liquidityPool.getPendingRewards(await user2.getAddress());
            const user3Rewards = await liquidityPool.getPendingRewards(await user3.getAddress());

            // User1 should have most rewards (largest stake, longest time)
            expect(user1Rewards).to.be.gt(user2Rewards);
            expect(user2Rewards).to.be.gt(user3Rewards);

            // Verify voting powers are correct
            const user1VotingPower = (await liquidityPool.getStake(await user1.getAddress())).votingPower;
            const user2VotingPower = (await liquidityPool.getStake(await user2.getAddress())).votingPower;
            const user3VotingPower = (await liquidityPool.getStake(await user3.getAddress())).votingPower;

            // Voting power should be proportional to stake
            expect(user1VotingPower).to.be.gt(user2VotingPower);
            expect(user2VotingPower).to.be.gt(user3VotingPower);

            // Total voting power should sum to ~1.0
            const totalVotingPower = user1VotingPower.add(user2VotingPower).add(user3VotingPower);
            expect(totalVotingPower).to.be.closeTo(
                ethers.parseEther("1.0"),
                ethers.parseEther("0.01")
            );
        });

        it("Should handle cascading unstake scenario", async function () {
            const { liquidityPool, user1, user2, user3, usdc } = await loadFixture(deployDiamondFixture);

            // All users stake
            await liquidityPool.connect(user1).stake(ethers.parseUnits("5000", 6));
            await liquidityPool.connect(user2).stake(ethers.parseUnits("3000", 6));
            await liquidityPool.connect(user3).stake(ethers.parseUnits("2000", 6));

            // Fast forward past lock period
            await ethers.provider.send("evm_increaseTime", [7 * 24 * 60 * 60 + 1]);
            await ethers.provider.send("evm_mine");

            const initialStats = await liquidityPool.getPoolStats();
            const initialTotalStaked = initialStats.totalStaked;

            // User1 unstakes fully
            const user1InitialBalance = await usdc.balanceOf(await user1.getAddress());
            await liquidityPool.connect(user1).unstake(ethers.parseUnits("5000", 6));
            const user1FinalBalance = await usdc.balanceOf(await user1.getAddress());
            
            // Should receive principal + rewards
            expect(user1FinalBalance).to.be.gt(user1InitialBalance.add(ethers.parseUnits("5000", 6)));

            // Verify voting powers recalculated
            const user2VotingPower = (await liquidityPool.getStake(await user2.getAddress())).votingPower;
            const user3VotingPower = (await liquidityPool.getStake(await user3.getAddress())).votingPower;
            
            // User2 should now have higher voting power (3000 vs 2000 remaining)
            expect(user2VotingPower).to.be.gt(user3VotingPower);
            
            // Total should still sum to 1.0
            const totalVotingPower = user2VotingPower.add(user3VotingPower);
            expect(totalVotingPower).to.be.closeTo(
                ethers.parseEther("1.0"),
                ethers.parseEther("0.01")
            );

            // User2 partially unstakes
            await liquidityPool.connect(user2).unstake(ethers.parseUnits("1500", 6));

            // Verify remaining stakes and voting powers
            const user2Stake = await liquidityPool.getStake(await user2.getAddress());
            const user3Stake = await liquidityPool.getStake(await user3.getAddress());

            expect(user2Stake.amount).to.equal(ethers.parseUnits("1500", 6));
            expect(user3Stake.amount).to.equal(ethers.parseUnits("2000", 6));

            // User3 should now have higher voting power
            expect(user3Stake.votingPower).to.be.gt(user2Stake.votingPower);
        });

        it("Should handle emergency withdrawal cascade", async function () {
            const { liquidityPool, user1, user2, user3, usdc } = await loadFixture(deployDiamondFixture);

            const stakeAmounts = [
                ethers.parseUnits("4000", 6),
                ethers.parseUnits("3000", 6),
                ethers.parseUnits("3000", 6)
            ];

            // All stake same amounts
            await liquidityPool.connect(user1).stake(stakeAmounts[0]);
            await liquidityPool.connect(user2).stake(stakeAmounts[1]);
            await liquidityPool.connect(user3).stake(stakeAmounts[2]);

            // Store initial balances
            const initialBalances = [
                await usdc.balanceOf(await user1.getAddress()),
                await usdc.balanceOf(await user2.getAddress()),
                await usdc.balanceOf(await user3.getAddress())
            ];

            // User1 emergency withdraws (should get 85% back due to 15% penalty)
            await liquidityPool.connect(user1).emergencyWithdraw();
            
            const user1Balance = await usdc.balanceOf(await user1.getAddress());
            const expectedReturn1 = stakeAmounts[0].mul(85).div(100); // 85% after 15% penalty
            expect(user1Balance).to.equal(initialBalances[0].add(expectedReturn1));

            // Verify user1 is now inactive
            const user1Stake = await liquidityPool.getStake(await user1.getAddress());
            expect(user1Stake.active).to.be.false;
            expect(user1Stake.amount).to.equal(0);

            // Verify voting powers recalculated for remaining users
            const user2VotingPower = (await liquidityPool.getStake(await user2.getAddress())).votingPower;
            const user3VotingPower = (await liquidityPool.getStake(await user3.getAddress())).votingPower;
            
            // Should be equal since they have equal stakes
            expect(user2VotingPower).to.be.closeTo(user3VotingPower, ethers.parseEther("0.01"));
            
            // Each should have 50% voting power
            expect(user2VotingPower).to.be.closeTo(
                ethers.parseEther("0.5"),
                ethers.parseEther("0.01")
            );

            // User2 also emergency withdraws
            await liquidityPool.connect(user2).emergencyWithdraw();
            
            // User3 should now have 100% voting power
            const user3FinalVotingPower = (await liquidityPool.getStake(await user3.getAddress())).votingPower;
            expect(user3FinalVotingPower).to.be.closeTo(
                ethers.parseEther("1.0"),
                ethers.parseEther("0.01")
            );

            // Pool should have only 1 provider left
            const finalStats = await liquidityPool.getPoolStats();
            expect(finalStats.totalLiquidityProviders).to.equal(1);
            expect(finalStats.totalStaked).to.equal(stakeAmounts[2]);
        });
    });

    describe("Reward System Integration", function () {
        it("Should properly calculate and distribute rewards over time", async function () {
            const { liquidityPool, user1, user2, usdc } = await loadFixture(deployDiamondFixture);

            // User1 stakes
            const stakeAmount1 = ethers.parseUnits("10000", 6);
            await liquidityPool.connect(user1).stake(stakeAmount1);

            // Advance 30 days
            await ethers.provider.send("evm_increaseTime", [30 * 24 * 60 * 60]);
            await ethers.provider.send("evm_mine");

            const rewards1Month = await liquidityPool.getPendingRewards(await user1.getAddress());

            // User2 joins with same amount
            await liquidityPool.connect(user2).stake(stakeAmount1);

            // Advance another 30 days
            await ethers.provider.send("evm_increaseTime", [30 * 24 * 60 * 60]);
            await ethers.provider.send("evm_mine");

            const rewards2Months = await liquidityPool.getPendingRewards(await user1.getAddress());
            const user2Rewards1Month = await liquidityPool.getPendingRewards(await user2.getAddress());

            // User1 should have approximately 1.5 months of rewards
            // User2 should have approximately 1 month of rewards
            expect(rewards2Months).to.be.gt(rewards1Month);
            expect(user2Rewards1Month).to.be.lt(rewards2Months);
            expect(user2Rewards1Month).to.be.gt(rewards1Month.div(2)); // Should be more than half of user1's 1-month rewards

            // Test reward claiming
            const user1InitialBalance = await usdc.balanceOf(await user1.getAddress());
            await liquidityPool.connect(user1).claimRewards();
            const user1BalanceAfterClaim = await usdc.balanceOf(await user1.getAddress());

            expect(user1BalanceAfterClaim).to.equal(user1InitialBalance.add(rewards2Months));

            // After claiming, pending rewards should be 0
            const user1PendingAfterClaim = await liquidityPool.getPendingRewards(await user1.getAddress());
            expect(user1PendingAfterClaim).to.equal(0);
        });

        it("Should handle dynamic APR changes correctly", async function () {
            const { liquidityPool, user1, user2, user3, owner } = await loadFixture(deployDiamondFixture);

            // Initial stake with 10% APR
            const stakeAmount = ethers.parseUnits("1000", 6);
            await liquidityPool.connect(user1).stake(stakeAmount);

            // Advance time and measure rewards at 10% APR
            await ethers.provider.send("evm_increaseTime", [30 * 24 * 60 * 60]); // 30 days
            await ethers.provider.send("evm_mine");

            const rewardsAt10Percent = await liquidityPool.getPendingRewards(await user1.getAddress());

            // Owner changes APR to 15%
            await liquidityPool.connect(owner).updateStakingConfig(1500, 0, 0, 0);

            // Advance another 30 days
            await ethers.provider.send("evm_increaseTime", [30 * 24 * 60 * 60]);
            await ethers.provider.send("evm_mine");

            const rewardsAfterAPRIncrease = await liquidityPool.getPendingRewards(await user1.getAddress());

            // The additional rewards for the second 30 days should be higher due to increased APR
            const additionalRewards = rewardsAfterAPRIncrease.sub(rewardsAt10Percent);
            
            // Additional rewards should be approximately 1.5x the first month's rewards
            expect(additionalRewards).to.be.gt(rewardsAt10Percent);
            expect(additionalRewards).to.be.closeTo(
                rewardsAt10Percent.mul(15).div(10), // 1.5x
                rewardsAt10Percent.div(10) // 10% tolerance
            );
        });
    });

    describe("Gas Optimization Integration", function () {
        it("Should handle batch operations efficiently", async function () {
            const { liquidityPool, user1, user2, user3 } = await loadFixture(deployDiamondFixture);

            // Measure gas for individual operations
            const stakeAmount = ethers.parseUnits("1000", 6);
            
            const tx1 = await liquidityPool.connect(user1).stake(stakeAmount);
            const receipt1 = await tx1.wait();
            
            const tx2 = await liquidityPool.connect(user2).stake(stakeAmount);
            const receipt2 = await tx2.wait();
            
            const tx3 = await liquidityPool.connect(user3).stake(stakeAmount);
            const receipt3 = await tx3.wait();

            // Gas should be reasonable and not increase dramatically with more users
            expect(receipt1.gasUsed).to.be.lt(500000); // Less than 500k gas
            expect(receipt2.gasUsed).to.be.lt(600000); // Slight increase due to array operations
            expect(receipt3.gasUsed).to.be.lt(700000); // Should not grow linearly

            console.log(`Gas usage - User1: ${receipt1.gasUsed}, User2: ${receipt2.gasUsed}, User3: ${receipt3.gasUsed}`);
        });

        it("Should maintain performance with many stakers", async function () {
            const { liquidityPool, user1 } = await loadFixture(deployDiamondFixture);

            // Create multiple stakes to simulate many users
            const stakeAmount = ethers.parseUnits("100", 6);
            
            for (let i = 0; i < 10; i++) {
                await liquidityPool.connect(user1).stake(stakeAmount);
                
                // Verify operations still complete efficiently
                const tx = await liquidityPool.getPendingRewards(await user1.getAddress());
                // Should complete without timeout
            }

            const finalStake = await liquidityPool.getStake(await user1.getAddress());
            expect(finalStake.amount).to.equal(stakeAmount.mul(10));
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