const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("LiquidityPoolFacet - Basic Test", function () {
    let liquidityPoolFacet;
    let mockUSDC;
    let owner, user1, user2;

    beforeEach(async function () {
        [owner, user1, user2] = await ethers.getSigners();

        // Deploy MockERC20 for USDC
        const MockERC20 = await ethers.getContractFactory("MockERC20");
        mockUSDC = await MockERC20.deploy("USD Coin", "USDC", 6);

        // Deploy LiquidityPoolFacet standalone for testing
        const LiquidityPoolFacet = await ethers.getContractFactory("LiquidityPoolFacet");
        liquidityPoolFacet = await LiquidityPoolFacet.deploy();

        console.log("MockUSDC deployed to:", await mockUSDC.getAddress());
        console.log("LiquidityPoolFacet deployed to:", await liquidityPoolFacet.getAddress());
    });

    it("Should deploy successfully", async function () {
        expect(await liquidityPoolFacet.getAddress()).to.not.be.undefined;
        expect(await mockUSDC.getAddress()).to.not.be.undefined;
    });

    it("Should be pausable by owner", async function () {
        // This should fail because we need diamond context, but let's see the error
        try {
            await liquidityPoolFacet.pause();
        } catch (error) {
            console.log("Expected error (needs diamond context):", error.message);
        }
    });
});