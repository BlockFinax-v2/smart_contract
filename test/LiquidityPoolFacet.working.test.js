const { expect } = require("chai");
const { ethers } = require("hardhat");
const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");

describe("LiquidityPoolFacet - Working Tests", function () {
    // Simple deployment fixture
    async function deploySimpleFixture() {
        const [owner, user1, user2, user3] = await ethers.getSigners();

        // Deploy MockERC20 for USDC
        const MockERC20 = await ethers.getContractFactory("MockERC20");
        const usdc = await MockERC20.deploy("USD Coin", "USDC", 6);

        // Deploy facets
        const DiamondCutFacet = await ethers.getContractFactory("DiamondCutFacet");
        const diamondCutFacet = await DiamondCutFacet.deploy();

        const DiamondLoupeFacet = await ethers.getContractFactory("DiamondLoupeFacet");
        const diamondLoupeFacet = await DiamondLoupeFacet.deploy();

        const LiquidityPoolFacet = await ethers.getContractFactory("LiquidityPoolFacet");
        const liquidityPoolFacet = await LiquidityPoolFacet.deploy();

        // Deploy Diamond
        const Diamond = await ethers.getContractFactory("Diamond");
        const diamond = await Diamond.deploy(await owner.getAddress(), await diamondCutFacet.getAddress());

        // Deploy DiamondInit
        const DiamondInit = await ethers.getContractFactory("DiamondInit");
        const diamondInit = await DiamondInit.deploy();

        // Get function selectors
        const diamondLoupeSelectors = getSelectors(diamondLoupeFacet);
        const liquidityPoolSelectors = getSelectors(liquidityPoolFacet);

        // Add facets
        const cut = [
            {
                facetAddress: await diamondLoupeFacet.getAddress(),
                action: 0, // Add
                functionSelectors: diamondLoupeSelectors,
            },
            {
                facetAddress: await liquidityPoolFacet.getAddress(),
                action: 0, // Add
                functionSelectors: liquidityPoolSelectors,
            },
        ];

        const diamondCut = await ethers.getContractAt("IDiamondCut", await diamond.getAddress());
        await diamondCut.diamondCut(cut, await diamondInit.getAddress(), "0x");

        // Get diamond with LiquidityPoolFacet interface
        const liquidityPool = await ethers.getContractAt("LiquidityPoolFacet", await diamond.getAddress());

        // Initialize staking with complete setup
        const minimumStake = ethers.parseUnits("10", 6); // 10 USDC minimum
        await liquidityPool.initializeComplete(
            await usdc.getAddress(),
            minimumStake,
            1000, // 10% APR
            7 * 24 * 60 * 60, // 7 days lock
            10, // 0.1% reduction per 1000 tokens
            15 // 15% emergency penalty
        );

        // Setup tokens
        const mintAmount = ethers.parseUnits("10000", 6);
        await usdc.mint(await user1.getAddress(), mintAmount);
        await usdc.mint(await user2.getAddress(), mintAmount);
        await usdc.mint(await user3.getAddress(), mintAmount);

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
        };
    }

    describe("Basic Functionality", function () {
        it("Should initialize staking configuration", async function () {
            const { liquidityPool } = await loadFixture(deploySimpleFixture);

            const config = await liquidityPool.getStakingConfig();
            expect(config.initialApr).to.equal(1000);
            expect(config.currentRewardRate).to.equal(1000);
            expect(config.minLockDuration).to.equal(7 * 24 * 60 * 60);
            expect(config.emergencyWithdrawPenalty).to.equal(15);
        });

        it("Should return empty pool stats initially", async function () {
            const { liquidityPool } = await loadFixture(deploySimpleFixture);

            const stats = await liquidityPool.getPoolStats();
            expect(stats.totalStaked).to.equal(0);
            expect(stats.totalLiquidityProviders).to.equal(0);
            expect(stats.currentRewardRate).to.equal(1000);
        });

        it("Should allow basic staking", async function () {
            const { liquidityPool, user1 } = await loadFixture(deploySimpleFixture);

            const stakeAmount = ethers.parseUnits("1000", 6);
            
            await expect(liquidityPool.connect(user1).stake(stakeAmount))
                .to.emit(liquidityPool, "Staked");

            const stake = await liquidityPool.getStake(await user1.getAddress());
            expect(stake.amount).to.equal(stakeAmount);
            expect(stake.active).to.be.true;
        });

        it("Should revert staking zero amount", async function () {
            const { liquidityPool, user1 } = await loadFixture(deploySimpleFixture);

            await expect(liquidityPool.connect(user1).stake(0))
                .to.be.revertedWithCustomError(liquidityPool, "ZeroAmount");
        });

        it("Should handle pause functionality", async function () {
            const { liquidityPool, owner } = await loadFixture(deploySimpleFixture);

            await expect(liquidityPool.connect(owner).pause())
                .to.emit(liquidityPool, "Paused");

            expect(await liquidityPool.paused()).to.be.true;

            await expect(liquidityPool.connect(owner).unpause())
                .to.emit(liquidityPool, "Unpaused");

            expect(await liquidityPool.paused()).to.be.false;
        });

        it("Should calculate voting power correctly for multiple users", async function () {
            const { liquidityPool, user1, user2 } = await loadFixture(deploySimpleFixture);

            const stake1 = ethers.parseUnits("1000", 6);
            const stake2 = ethers.parseUnits("3000", 6);

            await liquidityPool.connect(user1).stake(stake1);
            await liquidityPool.connect(user2).stake(stake2);

            const user1Stake = await liquidityPool.getStake(await user1.getAddress());
            const user2Stake = await liquidityPool.getStake(await user2.getAddress());

            // User1: 1000/4000 = 0.25, User2: 3000/4000 = 0.75
            expect(user1Stake.votingPower).to.be.closeTo(
                ethers.parseEther("0.25"), 
                ethers.parseEther("0.01")
            );
            expect(user2Stake.votingPower).to.be.closeTo(
                ethers.parseEther("0.75"), 
                ethers.parseEther("0.01")
            );
        });

        it("Should handle emergency withdrawal", async function () {
            const { liquidityPool, user1, usdc } = await loadFixture(deploySimpleFixture);

            const stakeAmount = ethers.parseUnits("1000", 6);
            const initialBalance = await usdc.balanceOf(await user1.getAddress());
            
            await liquidityPool.connect(user1).stake(stakeAmount);

            // Emergency withdraw should deduct 15% penalty
            await expect(liquidityPool.connect(user1).emergencyWithdraw())
                .to.emit(liquidityPool, "EmergencyWithdrawn");

            const finalBalance = await usdc.balanceOf(await user1.getAddress());
            const penalty = stakeAmount * 15n / 100n; // 15% penalty
            const expectedReturn = stakeAmount - penalty;

            expect(finalBalance).to.equal(initialBalance - penalty);

            // User should be inactive
            const stake = await liquidityPool.getStake(await user1.getAddress());
            expect(stake.active).to.be.false;
        });

        it("Should accumulate rewards over time", async function () {
            const { liquidityPool, user1 } = await loadFixture(deploySimpleFixture);

            const stakeAmount = ethers.parseUnits("1000", 6);
            await liquidityPool.connect(user1).stake(stakeAmount);

            // Fast forward 1 day
            await ethers.provider.send("evm_increaseTime", [86400]);
            await ethers.provider.send("evm_mine");

            const rewards = await liquidityPool.getPendingRewards(await user1.getAddress());
            expect(rewards).to.be.gt(0);
        });

        it("Should allow owner to update configuration", async function () {
            const { liquidityPool, owner } = await loadFixture(deploySimpleFixture);

            await expect(
                liquidityPool.connect(owner).updateStakingConfig(1500, 0, 0, 20)
            ).to.emit(liquidityPool, "StakingConfigUpdated");

            const config = await liquidityPool.getStakingConfig();
            expect(config.initialApr).to.equal(1500);
            expect(config.emergencyWithdrawPenalty).to.equal(20);
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