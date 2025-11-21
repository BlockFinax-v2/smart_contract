const { expect } = require("chai");
const { ethers } = require("hardhat");
const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");

describe("LiquidityPoolFacet - Minimal Working Test", function() {
    async function deployMinimalFixture() {
        const [owner, user1, user2] = await ethers.getSigners();
        
        // Deploy MockERC20 for testing
        const MockERC20 = await ethers.getContractFactory("MockERC20");
        const mockUSDC = await MockERC20.deploy("Mock USDC", "mUSDC", 6);
        
        // Deploy LiquidityPoolFacet directly (not through Diamond)
        const LiquidityPoolFacet = await ethers.getContractFactory("LiquidityPoolFacet");
        const liquidityPoolFacet = await LiquidityPoolFacet.deploy();
        
        const facetAddress = await liquidityPoolFacet.getAddress();
        
        // Mint tokens to users
        await mockUSDC.mint(await user1.getAddress(), ethers.parseUnits("100000", 6));
        await mockUSDC.mint(await user2.getAddress(), ethers.parseUnits("100000", 6));
        await mockUSDC.mint(await owner.getAddress(), ethers.parseUnits("1000000", 6)); // For rewards
        
        // Approve tokens
        await mockUSDC.connect(user1).approve(facetAddress, ethers.MaxUint256);
        await mockUSDC.connect(user2).approve(facetAddress, ethers.MaxUint256);
        await mockUSDC.connect(owner).approve(facetAddress, ethers.MaxUint256);
        
        return {
            owner,
            user1,
            user2,
            mockUSDC,
            liquidityPoolFacet,
            facetAddress
        };
    }

    describe("Ethers v6 Compatibility", function() {
        it("Should deploy contracts successfully", async function() {
            const { mockUSDC, liquidityPoolFacet, facetAddress } = await loadFixture(deployMinimalFixture);
            
            // Test ethers v6 syntax
            expect(await mockUSDC.getAddress()).to.be.properAddress;
            expect(facetAddress).to.be.properAddress;
            expect(await mockUSDC.name()).to.equal("Mock USDC");
            expect(await mockUSDC.symbol()).to.equal("mUSDC");
            expect(await mockUSDC.decimals()).to.equal(6);
        });

        it("Should handle token operations with ethers v6", async function() {
            const { user1, user2, mockUSDC } = await loadFixture(deployMinimalFixture);
            
            const user1Address = await user1.getAddress();
            const user2Address = await user2.getAddress();
            
            // Test balances using ethers v6 parseUnits
            const user1Balance = await mockUSDC.balanceOf(user1Address);
            expect(user1Balance).to.equal(ethers.parseUnits("100000", 6));
            
            // Test transfer
            const transferAmount = ethers.parseUnits("1000", 6);
            await mockUSDC.connect(user1).transfer(user2Address, transferAmount);
            
            const user1NewBalance = await mockUSDC.balanceOf(user1Address);
            const user2NewBalance = await mockUSDC.balanceOf(user2Address);
            
            expect(user1NewBalance).to.equal(ethers.parseUnits("99000", 6));
            expect(user2NewBalance).to.equal(ethers.parseUnits("101000", 6));
        });

        it("Should handle contract addresses correctly", async function() {
            const { owner, liquidityPoolFacet, mockUSDC } = await loadFixture(deployMinimalFixture);
            
            // Test async address resolution (ethers v6 requirement)
            const facetAddress = await liquidityPoolFacet.getAddress();
            const tokenAddress = await mockUSDC.getAddress();
            const ownerAddress = await owner.getAddress();
            
            expect(facetAddress).to.be.properAddress;
            expect(tokenAddress).to.be.properAddress;
            expect(ownerAddress).to.be.properAddress;
            
            // Test that addresses are different
            expect(facetAddress).to.not.equal(tokenAddress);
            expect(facetAddress).to.not.equal(ownerAddress);
            expect(tokenAddress).to.not.equal(ownerAddress);
        });

        it("Should handle MaxUint256 correctly", async function() {
            const { user1, mockUSDC, facetAddress } = await loadFixture(deployMinimalFixture);
            
            // Test ethers v6 MaxUint256 (not ethers.constants.MaxUint256)
            const allowance = await mockUSDC.allowance(await user1.getAddress(), facetAddress);
            expect(allowance).to.equal(ethers.MaxUint256);
        });

        it("Should handle parseUnits and parseEther correctly", async function() {
            // Test various ethers v6 parsing functions
            const usdcAmount = ethers.parseUnits("1000.50", 6);  // 6 decimals for USDC
            const ethAmount = ethers.parseEther("1.5");          // 18 decimals for ETH
            const customAmount = ethers.parseUnits("100", 8);    // 8 decimals custom
            
            expect(usdcAmount).to.equal(1000500000n);      // 1000.50 with 6 decimals
            expect(ethAmount).to.equal(1500000000000000000n); // 1.5 with 18 decimals  
            expect(customAmount).to.equal(10000000000n);    // 100 with 8 decimals
        });

        it("Should demonstrate contract interface access", async function() {
            const { liquidityPoolFacet } = await loadFixture(deployMinimalFixture);
            
            // Test that contract interface is accessible
            expect(liquidityPoolFacet.interface).to.exist;
            expect(liquidityPoolFacet.interface.fragments).to.be.an('array');
            expect(liquidityPoolFacet.interface.fragments.length).to.be.greaterThan(0);
        });

        it("Should show proper error handling patterns", async function() {
            const { liquidityPoolFacet, user1 } = await loadFixture(deployMinimalFixture);
            
            // This test shows how to properly handle reverts with ethers v6
            // Since we don't have proper Diamond setup, calls should revert
            await expect(
                liquidityPoolFacet.connect(user1).pause()
            ).to.be.reverted; // Will revert because of missing Diamond storage or owner setup
        });
    });
    
    describe("Mathematical Operations", function() {
        it("Should handle large number calculations", async function() {
            // Test mathematical operations with BigInt (ethers v6 uses BigInt)
            const amount1 = ethers.parseUnits("1000000", 6);  // 1M USDC
            const amount2 = ethers.parseUnits("500000", 6);   // 500K USDC
            
            expect(amount1 + amount2).to.equal(ethers.parseUnits("1500000", 6));
            expect(amount1 - amount2).to.equal(ethers.parseUnits("500000", 6));
            expect(amount1 * 2n).to.equal(ethers.parseUnits("2000000", 6));
        });

        it("Should handle precision calculations", async function() {
            // Test precision with different decimals
            const highPrecision = ethers.parseUnits("1.123456789012345678", 18);
            const mediumPrecision = ethers.parseUnits("1.123456", 6);
            const lowPrecision = ethers.parseUnits("1.12", 2);
            
            expect(highPrecision).to.equal(1123456789012345678n);
            expect(mediumPrecision).to.equal(1123456n);
            expect(lowPrecision).to.equal(112n);
        });
    });
});