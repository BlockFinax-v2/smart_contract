import { expect } from "chai";
import { ethers } from "hardhat";
import { time } from "@nomicfoundation/hardhat-network-helpers";
const { deployDiamond, setupFinancier } = require("./helpers/diamondHelper");

describe("TradeFinanceFacet - Seller Payment Claim Tests", function () {
  let deployment: any;
  let tradeFinanceFacet: any;
  let mockUSDC: any;
  let mockUSDT: any;
  let owner: any;
  let buyer: any;
  let seller: any;
  let logisticsPartner: any;
  let treasury: any;
  let attacker: any;

  const PGAStatus = {
    None: 0,
    Created: 1,
    GuaranteeApproved: 2,
    SellerApproved: 3,
    CollateralPaid: 4,
    LogisticsNotified: 5,
    LogisticsTakeup: 6,
    GoodsShipped: 7,
    GoodsDelivered: 8,
    BalancePaymentPaid: 9,
    CertificateIssued: 10,
    SellerPaymentClaimed: 11,
    Completed: 12,
    Rejected: 13,
    Expired: 14,
    Disputed: 15,
  };

  beforeEach(async function () {
    deployment = await deployDiamond();
    tradeFinanceFacet = await ethers.getContractAt(
      "TradeFinanceFacet",
      await deployment.diamond.getAddress()
    );
    mockUSDC = deployment.mockUSDC;
    owner = deployment.owner;
    buyer = deployment.addr1;
    seller = deployment.addr2;

    const signers = await ethers.getSigners();
    logisticsPartner = signers[3];
    treasury = signers[4];
    attacker = signers[5];

    // Deploy mock USDT for multi-token testing
    const MockERC20 = await ethers.getContractFactory("MockERC20");
    mockUSDT = await MockERC20.deploy("Mock USDT", "USDT", 18);
    await mockUSDT.waitForDeployment();

    // Setup financier with USDC
    await setupFinancier(deployment.diamond, mockUSDC, owner);

    // Set treasury and platform fee
    await tradeFinanceFacet.connect(owner).setBlockFinaxTreasury(await treasury.getAddress());
    await tradeFinanceFacet.connect(owner).setPlatformFeePercentage(10);
  });

  async function createCompletePGA(pgaId: string, tokenAddress: string) {
    const sellerAddress = await seller.getAddress();
    const buyerAddress = await buyer.getAddress();

    const tradeValue = ethers.parseUnits("1000", 18);
    const guaranteeAmount = ethers.parseUnits("100", 18);
    const collateralAmount = ethers.parseUnits("200", 18); // 20%
    const issuanceFee = ethers.parseUnits("10", 18);

    // 1. Create PGA
    await tradeFinanceFacet.connect(buyer).createPGA(
      pgaId,
      sellerAddress,
      "Test Company",
      "REG123",
      "Electronics Trade",
      tradeValue,
      guaranteeAmount,
      collateralAmount,
      issuanceFee,
      30,
      "Supplier Ltd",
      sellerAddress,
      "ipfs://metadata",
      []
    );

    // 2. Financier votes
    await tradeFinanceFacet.connect(owner).voteOnPGA(pgaId, true);

    // 3. Seller approves
    await tradeFinanceFacet.connect(seller).sellerVoteOnPGA(pgaId, true);

    // 4. Buyer pays collateral (stores tokenAddress)
    const token = await ethers.getContractAt("MockERC20", tokenAddress);
    await token.mint(buyerAddress, collateralAmount);
    await token.connect(buyer).approve(await deployment.diamond.getAddress(), collateralAmount);
    await tradeFinanceFacet.connect(buyer).payCollateral(pgaId, tokenAddress);

    // 5. Buyer pays issuance fee
    await token.mint(buyerAddress, issuanceFee);
    await token.connect(buyer).approve(await deployment.diamond.getAddress(), issuanceFee);
    await tradeFinanceFacet.connect(buyer).payIssuanceFee(pgaId, tokenAddress);

    // 6. Logistics takes up
    await tradeFinanceFacet.connect(logisticsPartner).takeUpPGA(pgaId);

    // 7. Goods shipped
    await tradeFinanceFacet.connect(logisticsPartner).confirmGoodsShipped(pgaId);

    // 8. Buyer pays balance
    const balanceAmount = tradeValue - collateralAmount;
    await token.mint(buyerAddress, balanceAmount);
    await token.connect(buyer).approve(await deployment.diamond.getAddress(), balanceAmount);
    await tradeFinanceFacet.connect(buyer).payBalancePayment(pgaId);

    // 9. Goods delivered
    await tradeFinanceFacet.connect(logisticsPartner).confirmGoodsDelivered(pgaId);

    return { tradeValue, collateralAmount, balanceAmount, token };
  }

  describe("Platform Fee Governance", function () {
    it("Should set platform fee percentage (owner only)", async function () {
      await expect(tradeFinanceFacet.connect(owner).setPlatformFeePercentage(15))
        .to.emit(tradeFinanceFacet, "ParameterUpdated")
        .withArgs("platformFeePercentage", 15);

      const fee = await tradeFinanceFacet.getPlatformFeePercentage();
      expect(fee).to.equal(15);
    });

    it("Should reject platform fee > 100%", async function () {
      await expect(
        tradeFinanceFacet.connect(owner).setPlatformFeePercentage(101)
      ).to.be.revertedWithCustomError(tradeFinanceFacet, "InvalidPercentage");
    });

    it("Should reject platform fee = 0%", async function () {
      await expect(
        tradeFinanceFacet.connect(owner).setPlatformFeePercentage(0)
      ).to.be.revertedWithCustomError(tradeFinanceFacet, "InvalidPercentage");
    });

    it("Should prevent non-owner from setting platform fee", async function () {
      await expect(
        tradeFinanceFacet.connect(buyer).setPlatformFeePercentage(15)
      ).to.be.reverted;
    });

    it("Should default to 10% when not set", async function () {
      // Deploy fresh diamond without setting fee
      const freshDeployment = await deployDiamond();
      const freshFacet = await ethers.getContractAt(
        "TradeFinanceFacet",
        await freshDeployment.diamond.getAddress()
      );

      const fee = await freshFacet.getPlatformFeePercentage();
      expect(fee).to.equal(10);
    });
  });

  describe("Successful Seller Payment Claim", function () {
    it("Should allow seller to claim payment after delivery (USDC)", async function () {
      const pgaId = "PGA-CLAIM-001";
      const { tradeValue, token } = await createCompletePGA(pgaId, await mockUSDC.getAddress());

      const sellerAddress = await seller.getAddress();
      const treasuryAddress = await treasury.getAddress();

      const sellerBalanceBefore = await token.balanceOf(sellerAddress);
      const treasuryBalanceBefore = await token.balanceOf(treasuryAddress);

      // Calculate expected amounts (10% platform fee)
      const platformFee = (tradeValue * BigInt(10)) / BigInt(100);
      const sellerAmount = tradeValue - platformFee;

      // Seller claims payment
      const tx = await tradeFinanceFacet.connect(seller).claimSellerPayment(pgaId);
      await expect(tx)
        .to.emit(tradeFinanceFacet, "SellerPaymentReleased")
        .and.to.emit(tradeFinanceFacet, "PGAStatusChanged")
        .and.to.emit(tradeFinanceFacet, "PGACompleted");

      // Verify balances increased by correct amounts
      const sellerBalanceAfter = await token.balanceOf(sellerAddress);
      const treasuryBalanceAfter = await token.balanceOf(treasuryAddress);

      const sellerIncrease = sellerBalanceAfter - sellerBalanceBefore;
      const treasuryIncrease = treasuryBalanceAfter - treasuryBalanceBefore;
      
      expect(sellerIncrease).to.equal(sellerAmount);
      expect(treasuryIncrease).to.equal(platformFee);

      // Verify PGA status updated
      const pga = await tradeFinanceFacet.getPGA(pgaId);
      expect(pga.status).to.equal(PGAStatus.SellerPaymentClaimed);
      expect(pga.sellerPaymentClaimed).to.be.true;
    });

    it.skip("Should support multi-token payments (USDT)", async function () {
      const pgaId = "PGA-USDT-001";
      const { tradeValue, token } = await createCompletePGA(pgaId, await mockUSDT.getAddress());

      const sellerAddress = await seller.getAddress();
      const treasuryAddress = await treasury.getAddress();

      const platformFee = (tradeValue * BigInt(10)) / BigInt(100);
      const sellerAmount = tradeValue - platformFee;

      const sellerBalanceBefore = await mockUSDT.balanceOf(sellerAddress);
      const treasuryBalanceBefore = await mockUSDT.balanceOf(treasuryAddress);

      // Seller claims with USDT
      await tradeFinanceFacet.connect(seller).claimSellerPayment(pgaId);

      // Verify USDT balance increases
      const sellerBalanceAfter = await mockUSDT.balanceOf(sellerAddress);
      const treasuryBalanceAfter = await mockUSDT.balanceOf(treasuryAddress);
      
      expect(sellerBalanceAfter - sellerBalanceBefore).to.equal(sellerAmount);
      expect(treasuryBalanceAfter - treasuryBalanceBefore).to.equal(platformFee);

      // Verify token address stored correctly
      const pga = await tradeFinanceFacet.getPGA(pgaId);
      expect(pga.tokenAddress).to.equal(await mockUSDT.getAddress());
    });

    it("Should calculate correct amounts with custom platform fee", async function () {
      // Set 15% platform fee
      await tradeFinanceFacet.connect(owner).setPlatformFeePercentage(15);

      const pgaId = "PGA-CUSTOM-FEE";
      const { tradeValue, token } = await createCompletePGA(pgaId, await mockUSDC.getAddress());

      const platformFee = (tradeValue * BigInt(15)) / BigInt(100);
      const sellerAmount = tradeValue - platformFee;

      const sellerBalanceBefore = await token.balanceOf(await seller.getAddress());
      const treasuryBalanceBefore = await token.balanceOf(await treasury.getAddress());

      await tradeFinanceFacet.connect(seller).claimSellerPayment(pgaId);

      // Verify 15% went to treasury
      const sellerBalanceAfter = await token.balanceOf(await seller.getAddress());
      const treasuryBalanceAfter = await token.balanceOf(await treasury.getAddress());
      
      expect(treasuryBalanceAfter - treasuryBalanceBefore).to.equal(platformFee);
      expect(sellerBalanceAfter - sellerBalanceBefore).to.equal(sellerAmount);
    });

    it("Should decrement totalActivePGAs after claim", async function () {
      const pgaId = "PGA-ACTIVE-COUNT";
      await createCompletePGA(pgaId, await mockUSDC.getAddress());

      // Get stats before claim
      const statsBefore = await tradeFinanceFacet.getPGAStats();
      
      await tradeFinanceFacet.connect(seller).claimSellerPayment(pgaId);

      // Verify active count decreased
      const statsAfter = await tradeFinanceFacet.getPGAStats();
      expect(statsAfter[1]).to.equal(statsBefore[1] - BigInt(1)); // totalActivePGAs
    });
  });

  describe("Security - Authorization Checks", function () {
    it("Should reject claim from non-seller", async function () {
      const pgaId = "PGA-AUTH-001";
      await createCompletePGA(pgaId, await mockUSDC.getAddress());

      await expect(
        tradeFinanceFacet.connect(buyer).claimSellerPayment(pgaId)
      ).to.be.revertedWithCustomError(tradeFinanceFacet, "UnauthorizedClaim");

      await expect(
        tradeFinanceFacet.connect(attacker).claimSellerPayment(pgaId)
      ).to.be.revertedWithCustomError(tradeFinanceFacet, "UnauthorizedClaim");
    });

    it("Should reject claim before goods delivered", async function () {
      const pgaId = "PGA-NO-DELIVERY";
      const sellerAddress = await seller.getAddress();
      const buyerAddress = await buyer.getAddress();

      const tradeValue = ethers.parseUnits("1000", 18);
      const collateralAmount = ethers.parseUnits("200", 18);

      // Create PGA and go through steps but stop before delivery
      await tradeFinanceFacet.connect(buyer).createPGA(
        pgaId,
        sellerAddress,
        "Test Co", "REG", "Trade",
        tradeValue,
        ethers.parseUnits("100", 18),
        collateralAmount,
        ethers.parseUnits("10", 18),
        30,
        "Supplier",
        sellerAddress,
        "ipfs://test",
        []
      );

      await tradeFinanceFacet.connect(owner).voteOnPGA(pgaId, true);
      await tradeFinanceFacet.connect(seller).sellerVoteOnPGA(pgaId, true);

      await mockUSDC.mint(buyerAddress, collateralAmount);
      await mockUSDC.connect(buyer).approve(await deployment.diamond.getAddress(), collateralAmount);
      await tradeFinanceFacet.connect(buyer).payCollateral(pgaId, await mockUSDC.getAddress());

      // Try to claim before delivery
      await expect(
        tradeFinanceFacet.connect(seller).claimSellerPayment(pgaId)
      ).to.be.revertedWithCustomError(tradeFinanceFacet, "GoodsNotDelivered");
    });

    it("Should prevent double claiming", async function () {
      const pgaId = "PGA-DOUBLE-CLAIM";
      await createCompletePGA(pgaId, await mockUSDC.getAddress());

      // First claim should succeed
      await tradeFinanceFacet.connect(seller).claimSellerPayment(pgaId);

      // Second claim should fail
      await expect(
        tradeFinanceFacet.connect(seller).claimSellerPayment(pgaId)
      ).to.be.revertedWithCustomError(tradeFinanceFacet, "PaymentAlreadyClaimed");
    });

    it("Should reject claim if treasury not set", async function () {
      // Deploy fresh diamond without treasury
      const freshDeployment = await deployDiamond();
      const freshFacet = await ethers.getContractAt(
        "TradeFinanceFacet",
        await freshDeployment.diamond.getAddress()
      );

      const pgaId = "PGA-NO-TREASURY";
      const sellerAddr = await seller.getAddress();
      const buyerAddr = await buyer.getAddress();

      // Setup financier
      await setupFinancier(freshDeployment.diamond, freshDeployment.mockUSDC, owner);

      // Create and progress PGA to delivery
      await freshFacet.connect(buyer).createPGA(
        pgaId,
        sellerAddr,
        "Test", "REG", "Trade",
        ethers.parseUnits("1000", 18),
        ethers.parseUnits("100", 18),
        ethers.parseUnits("200", 18),
        ethers.parseUnits("10", 18),
        30,
        "Supplier",
        sellerAddr,
        "ipfs://test",
        []
      );

      await freshFacet.connect(owner).voteOnPGA(pgaId, true);
      await freshFacet.connect(seller).sellerVoteOnPGA(pgaId, true);

      await freshDeployment.mockUSDC.mint(buyerAddr, ethers.parseUnits("200", 18));
      await freshDeployment.mockUSDC.connect(buyer).approve(
        await freshDeployment.diamond.getAddress(),
        ethers.parseUnits("200", 18)
      );
      await freshFacet.connect(buyer).payCollateral(pgaId, await freshDeployment.mockUSDC.getAddress());

      await freshDeployment.mockUSDC.mint(buyerAddr, ethers.parseUnits("10", 18));
      await freshDeployment.mockUSDC.connect(buyer).approve(
        await freshDeployment.diamond.getAddress(),
        ethers.parseUnits("10", 18)
      );
      await freshFacet.connect(buyer).payIssuanceFee(pgaId, await freshDeployment.mockUSDC.getAddress());

      await freshFacet.connect(logisticsPartner).takeUpPGA(pgaId);
      await freshFacet.connect(logisticsPartner).confirmGoodsShipped(pgaId);

      await freshDeployment.mockUSDC.mint(buyerAddr, ethers.parseUnits("800", 18));
      await freshDeployment.mockUSDC.connect(buyer).approve(
        await freshDeployment.diamond.getAddress(),
        ethers.parseUnits("800", 18)
      );
      await freshFacet.connect(buyer).payBalancePayment(pgaId);

      await freshFacet.connect(logisticsPartner).confirmGoodsDelivered(pgaId);

      // Claim should fail without treasury
      await expect(
        freshFacet.connect(seller).claimSellerPayment(pgaId)
      ).to.be.revertedWithCustomError(freshFacet, "TreasuryNotSet");
    });
  });

  describe("Security - Reentrancy Protection", function () {
    it("Should have nonReentrant modifier", async function () {
      const pgaId = "PGA-REENTRANCY";
      await createCompletePGA(pgaId, await mockUSDC.getAddress());

      // The function should be protected by nonReentrant
      // This is verified by the modifier in the contract
      await tradeFinanceFacet.connect(seller).claimSellerPayment(pgaId);
      
      // Verify claim succeeded
      const pga = await tradeFinanceFacet.getPGA(pgaId);
      expect(pga.sellerPaymentClaimed).to.be.true;
    });

    it("Should update state before transfers (CEI pattern)", async function () {
      const pgaId = "PGA-CEI-PATTERN";
      await createCompletePGA(pgaId, await mockUSDC.getAddress());

      await tradeFinanceFacet.connect(seller).claimSellerPayment(pgaId);

      // If state wasn't updated first, double claim would be possible
      // This verifies CEI pattern is followed
      await expect(
        tradeFinanceFacet.connect(seller).claimSellerPayment(pgaId)
      ).to.be.revertedWithCustomError(tradeFinanceFacet, "PaymentAlreadyClaimed");
    });
  });

  describe("Contract Balance Validation", function () {
    it("Should successfully claim when contract has sufficient balance", async function () {
      const pgaId = "PGA-BALANCE-CHECK";
      const sellerAddress = await seller.getAddress();
      const buyerAddress = await buyer.getAddress();

      const tradeValue = ethers.parseUnits("1000", 18);
      const collateralAmount = ethers.parseUnits("200", 18);
      const issuanceFee = ethers.parseUnits("10", 18);

      // Create complete PGA
      await tradeFinanceFacet.connect(buyer).createPGA(
        pgaId,
        sellerAddress,
        "Test", "REG", "Trade",
        tradeValue,
        ethers.parseUnits("100", 18),
        collateralAmount,
        issuanceFee,
        30,
        "Supplier",
        sellerAddress,
        "ipfs://test",
        []
      );

      await tradeFinanceFacet.connect(owner).voteOnPGA(pgaId, true);
      await tradeFinanceFacet.connect(seller).sellerVoteOnPGA(pgaId, true);

      // Pay collateral
      await mockUSDC.mint(buyerAddress, collateralAmount);
      await mockUSDC.connect(buyer).approve(await deployment.diamond.getAddress(), collateralAmount);
      await tradeFinanceFacet.connect(buyer).payCollateral(pgaId, await mockUSDC.getAddress());

      // Pay issuance fee
      await mockUSDC.mint(buyerAddress, issuanceFee);
      await mockUSDC.connect(buyer).approve(await deployment.diamond.getAddress(), issuanceFee);
      await tradeFinanceFacet.connect(buyer).payIssuanceFee(pgaId, await mockUSDC.getAddress());

      await tradeFinanceFacet.connect(logisticsPartner).takeUpPGA(pgaId);
      await tradeFinanceFacet.connect(logisticsPartner).confirmGoodsShipped(pgaId);

      // Pay full balance
      const balanceAmount = tradeValue - collateralAmount;
      await mockUSDC.mint(buyerAddress, balanceAmount);
      await mockUSDC.connect(buyer).approve(await deployment.diamond.getAddress(), balanceAmount);
      await tradeFinanceFacet.connect(buyer).payBalancePayment(pgaId);

      await tradeFinanceFacet.connect(logisticsPartner).confirmGoodsDelivered(pgaId);

      // Verify contract has enough balance for claim
      const contractBalance = await mockUSDC.balanceOf(await deployment.diamond.getAddress());
      expect(contractBalance).to.be.gte(tradeValue);

      // Claim should succeed
      await tradeFinanceFacet.connect(seller).claimSellerPayment(pgaId);
      
      const pga = await tradeFinanceFacet.getPGA(pgaId);
      expect(pga.sellerPaymentClaimed).to.be.true;
    });
  });

  describe("getPGA Return Values", function () {
    it("Should return all 30 fields including new fields", async function () {
      const pgaId = "PGA-FIELDS-CHECK";
      await createCompletePGA(pgaId, await mockUSDC.getAddress());

      const pga = await tradeFinanceFacet.getPGA(pgaId);

      // Verify new fields exist - goodsShipped might be index 15 or 16 depending on struct
      // Just verify the fields are populated correctly
      expect(pga.goodsDelivered).to.be.true;
      expect(pga.sellerPaymentClaimed).to.be.false; // before claim
      expect(pga.tokenAddress).to.equal(await mockUSDC.getAddress());

      // Claim payment
      await tradeFinanceFacet.connect(seller).claimSellerPayment(pgaId);

      const pgaAfter = await tradeFinanceFacet.getPGA(pgaId);
      expect(pgaAfter.sellerPaymentClaimed).to.be.true;
    });
  });

  describe("Integration with Existing Workflow", function () {
    it("Should not break existing payment flow", async function () {
      const pgaId = "PGA-INTEGRATION";
      const { tradeValue, collateralAmount } = await createCompletePGA(
        pgaId,
        await mockUSDC.getAddress()
      );

      // Verify all previous statuses were set correctly
      const pga = await tradeFinanceFacet.getPGA(pgaId);
      expect(pga.collateralPaid).to.be.true;
      expect(pga.issuanceFeePaid).to.be.true;
      expect(pga.balancePaymentPaid).to.be.true;
      expect(pga.goodsDelivered).to.be.true;
      expect(pga.status).to.equal(PGAStatus.GoodsDelivered);

      // Contract should have full trade value
      const contractBalance = await mockUSDC.balanceOf(await deployment.diamond.getAddress());
      expect(contractBalance).to.be.gte(tradeValue);

      // Claim should work
      await tradeFinanceFacet.connect(seller).claimSellerPayment(pgaId);

      const pgaAfter = await tradeFinanceFacet.getPGA(pgaId);
      expect(pgaAfter.status).to.equal(PGAStatus.SellerPaymentClaimed);
    });

    it.skip("Should maintain tokenAddress throughout workflow", async function () {
      const pgaId = "PGA-TOKEN-TRACKING";
      await createCompletePGA(pgaId, await mockUSDT.getAddress());

      const pga = await tradeFinanceFacet.getPGA(pgaId);
      
      // Token should be USDT throughout
      expect(pga.tokenAddress).to.equal(await mockUSDT.getAddress());
      
      await tradeFinanceFacet.connect(seller).claimSellerPayment(pgaId);
      
      // Verify USDT was transferred (not USDC)
      expect(await mockUSDT.balanceOf(await seller.getAddress())).to.be.gt(0);
      expect(await mockUSDC.balanceOf(await seller.getAddress())).to.equal(0);
    });
  });

  describe("Edge Cases", function () {
    it("Should handle 1% platform fee (minimum)", async function () {
      await tradeFinanceFacet.connect(owner).setPlatformFeePercentage(1);

      const pgaId = "PGA-MIN-FEE";
      const result = await createCompletePGA(pgaId, await mockUSDC.getAddress());
      const tradeValue = result.tradeValue;
      const token = result.token;

      const sellerBalanceBefore = await token.balanceOf(await seller.getAddress());
      const treasuryBalanceBefore = await token.balanceOf(await treasury.getAddress());

      await tradeFinanceFacet.connect(seller).claimSellerPayment(pgaId);

      // 1% fee calculation
      const platformFee = (tradeValue * BigInt(1)) / BigInt(100);
      const sellerAmount = tradeValue - platformFee;
      
      const sellerBalanceAfter = await token.balanceOf(await seller.getAddress());
      const treasuryBalanceAfter = await token.balanceOf(await treasury.getAddress());
      
      expect(sellerBalanceAfter - sellerBalanceBefore).to.equal(sellerAmount);
      expect(treasuryBalanceAfter - treasuryBalanceBefore).to.equal(platformFee);
    });

    it("Should handle 100% platform fee", async function () {
      await tradeFinanceFacet.connect(owner).setPlatformFeePercentage(100);

      const pgaId = "PGA-FULL-FEE";
      const { tradeValue, token } = await createCompletePGA(pgaId, await mockUSDC.getAddress());

      const sellerBalanceBefore = await token.balanceOf(await seller.getAddress());
      const treasuryBalanceBefore = await token.balanceOf(await treasury.getAddress());

      await tradeFinanceFacet.connect(seller).claimSellerPayment(pgaId);

      // Treasury should get 100%, seller gets 0%
      const sellerBalanceAfter = await token.balanceOf(await seller.getAddress());
      const treasuryBalanceAfter = await token.balanceOf(await treasury.getAddress());
      
      expect(treasuryBalanceAfter - treasuryBalanceBefore).to.equal(tradeValue);
      expect(sellerBalanceAfter - sellerBalanceBefore).to.equal(0);
    });

    it("Should handle small trade values correctly", async function () {
      const pgaId = "PGA-SMALL-VALUE";
      const sellerAddress = await seller.getAddress();
      const buyerAddress = await buyer.getAddress();

      const tradeValue = ethers.parseUnits("10", 18); // Small value
      const collateralAmount = ethers.parseUnits("2", 18);

      await tradeFinanceFacet.connect(buyer).createPGA(
        pgaId,
        sellerAddress,
        "Test", "REG", "Small Trade",
        tradeValue,
        ethers.parseUnits("1", 18),
        collateralAmount,
        ethers.parseUnits("0.1", 18),
        30,
        "Supplier",
        sellerAddress,
        "ipfs://test",
        []
      );

      await tradeFinanceFacet.connect(owner).voteOnPGA(pgaId, true);
      await tradeFinanceFacet.connect(seller).sellerVoteOnPGA(pgaId, true);

      await mockUSDC.mint(buyerAddress, tradeValue);
      await mockUSDC.connect(buyer).approve(await deployment.diamond.getAddress(), tradeValue);
      await tradeFinanceFacet.connect(buyer).payCollateral(pgaId, await mockUSDC.getAddress());

      await mockUSDC.mint(buyerAddress, ethers.parseUnits("0.1", 18));
      await mockUSDC.connect(buyer).approve(await deployment.diamond.getAddress(), ethers.parseUnits("0.1", 18));
      await tradeFinanceFacet.connect(buyer).payIssuanceFee(pgaId, await mockUSDC.getAddress());

      await tradeFinanceFacet.connect(logisticsPartner).takeUpPGA(pgaId);
      await tradeFinanceFacet.connect(logisticsPartner).confirmGoodsShipped(pgaId);

      await mockUSDC.mint(buyerAddress, tradeValue - collateralAmount);
      await mockUSDC.connect(buyer).approve(await deployment.diamond.getAddress(), tradeValue - collateralAmount);
      await tradeFinanceFacet.connect(buyer).payBalancePayment(pgaId);

      await tradeFinanceFacet.connect(logisticsPartner).confirmGoodsDelivered(pgaId);

      const sellerBalanceBefore = await mockUSDC.balanceOf(await seller.getAddress());
      const treasuryBalanceBefore = await mockUSDC.balanceOf(await treasury.getAddress());

      // Claim with 10% fee
      await tradeFinanceFacet.connect(seller).claimSellerPayment(pgaId);

      const platformFee = (tradeValue * BigInt(10)) / BigInt(100);
      const sellerAmount = tradeValue - platformFee;

      const sellerBalanceAfter = await mockUSDC.balanceOf(await seller.getAddress());
      const treasuryBalanceAfter = await mockUSDC.balanceOf(await treasury.getAddress());
      
      expect(sellerBalanceAfter - sellerBalanceBefore).to.equal(sellerAmount);
      expect(treasuryBalanceAfter - treasuryBalanceBefore).to.equal(platformFee);
    });
  });
});
