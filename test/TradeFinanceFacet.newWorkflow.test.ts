import { expect } from "chai";
import { ethers } from "hardhat";
import { time } from "@nomicfoundation/hardhat-network-helpers";
const { deployDiamond, setupFinancier } = require("./helpers/diamondHelper");

describe("TradeFinanceFacet - New Logistics Workflow Tests", function () {
  let deployment: any;
  let tradeFinanceFacet: any;
  let mockUSDC: any;
  let owner: any;
  let buyer: any;
  let seller: any;
  let logisticsPartner: any;
  let treasury: any;

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

    // Setup financier
    await setupFinancier(deployment.diamond, mockUSDC, owner);
    
    // Set treasury
    await tradeFinanceFacet.connect(owner).setBlockFinaxTreasury(await treasury.getAddress());
  });

  it("Should complete the full new logistics workflow", async function () {
    const pgaId = "PGA-NEW-FLOW";
    const sellerAddress = await seller.getAddress();
    const buyerAddress = await buyer.getAddress();
    const logisticsPartnerAddress = await logisticsPartner.getAddress();

    const tradeValue = ethers.parseUnits("1000", 18);
    const guaranteeAmount = ethers.parseUnits("100", 18);
    const collateralAmount = ethers.parseUnits("10", 18);
    const issuanceFee = ethers.parseUnits("5", 18);

    // 1. Create PGA
    await expect(
      tradeFinanceFacet.connect(buyer).createPGA(
        pgaId,
        sellerAddress,
        "Test Comp", "REG123", "Trade electronics",
        tradeValue,
        guaranteeAmount,
        collateralAmount,
        issuanceFee, // NEW parameter
        30, // 30 days
        "Supplier", sellerAddress,
        "ipfs://test", []
      )
    ).to.emit(tradeFinanceFacet, "PGACreated");

    // 2. Financier Votes -> GuaranteeApproved
    await tradeFinanceFacet.connect(owner).voteOnPGA(pgaId, true);

    // 3. Seller Approves -> SellerApproved
    await tradeFinanceFacet.connect(seller).sellerVoteOnPGA(pgaId, true);
    
    // Verify status
    let pga = await tradeFinanceFacet.getPGA(pgaId);
    expect(pga.status).to.equal(3); // SellerApproved

    // 4. Buyer Pays Collateral
    await mockUSDC.mint(buyerAddress, collateralAmount);
    await mockUSDC.connect(buyer).approve(await deployment.diamond.getAddress(), collateralAmount);
    
    await expect(
      tradeFinanceFacet.connect(buyer).payCollateral(pgaId, await mockUSDC.getAddress())
    ).to.emit(tradeFinanceFacet, "PGAStatusChanged");
    
    pga = await tradeFinanceFacet.getPGA(pgaId);
    expect(pga.status).to.equal(4); // CollateralPaid (since fee is not paid yet)

    // 5. Buyer Pays Issuance Fee -> LogisticsNotified
    await mockUSDC.mint(buyerAddress, issuanceFee);
    await mockUSDC.connect(buyer).approve(await deployment.diamond.getAddress(), issuanceFee);
    
    await expect(
      tradeFinanceFacet.connect(buyer).payIssuanceFee(pgaId, await mockUSDC.getAddress())
    ).to.emit(tradeFinanceFacet, "PGAStatusChanged");
    
    pga = await tradeFinanceFacet.getPGA(pgaId);
    expect(pga.status).to.equal(5); // LogisticsNotified

    // 6. Logistics Partner Takes Up -> LogisticsTakeup
    // Note: We haven't restricted takeUpPGA to authorized partners in the contract yet 
    // but we'll test it anyway.
    await expect(
      tradeFinanceFacet.connect(logisticsPartner).takeUpPGA(pgaId)
    ).to.emit(tradeFinanceFacet, "PGAStatusChanged");

    pga = await tradeFinanceFacet.getPGA(pgaId);
    expect(pga.status).to.equal(6); // LogisticsTakeup
    expect(pga.logisticsPartner).to.equal(logisticsPartnerAddress);

    // 7. Confirm Goods Shipped -> GoodsShipped
    await expect(
      tradeFinanceFacet.connect(logisticsPartner).confirmGoodsShipped(pgaId)
    ).to.emit(tradeFinanceFacet, "PGAStatusChanged");

    pga = await tradeFinanceFacet.getPGA(pgaId);
    expect(pga.status).to.equal(7); // GoodsShipped

    // 8. Confirm Goods Delivered -> GoodsDelivered
    await expect(
      tradeFinanceFacet.connect(logisticsPartner).confirmGoodsDelivered(pgaId)
    ).to.emit(tradeFinanceFacet, "PGAStatusChanged");

    pga = await tradeFinanceFacet.getPGA(pgaId);
    expect(pga.status).to.equal(8); // GoodsDelivered

    // 9. Buyer Pays Balance -> BalancePaymentPaid
    const balanceAmount = tradeValue - collateralAmount;
    await mockUSDC.mint(buyerAddress, balanceAmount);
    await mockUSDC.connect(buyer).approve(await deployment.diamond.getAddress(), balanceAmount);

    await expect(
      tradeFinanceFacet.connect(buyer).payBalancePayment(pgaId)
    ).to.emit(tradeFinanceFacet, "PGAStatusChanged");

    pga = await tradeFinanceFacet.getPGA(pgaId);
    expect(pga.status).to.equal(9); // BalancePaymentPaid

    // 10. Issue Certificate -> Completed
    await expect(
      tradeFinanceFacet.connect(buyer).issueCertificate(pgaId)
    ).to.emit(tradeFinanceFacet, "PGAStatusChanged");

    pga = await tradeFinanceFacet.getPGA(pgaId);
    expect(pga.status).to.equal(11); // Completed
  });

  describe("Edge Cases and Validations", function () {
    const pgaId = "PGA-EDGE";
    let sellerAddress: string;
    let buyerAddress: string;
    let logisticsPartnerAddress: string;

    beforeEach(async function () {
      sellerAddress = await seller.getAddress();
      buyerAddress = await buyer.getAddress();
      logisticsPartnerAddress = await logisticsPartner.getAddress();

      // Create and get to approved status
      await tradeFinanceFacet.connect(buyer).createPGA(
        pgaId, sellerAddress, "Comp", "REG", "Desc",
        ethers.parseUnits("1000", 18),
        ethers.parseUnits("100", 18),
        ethers.parseUnits("10", 18),
        ethers.parseUnits("5", 18),
        30, "Ben", sellerAddress, "uri", []
      );
      await tradeFinanceFacet.connect(owner).voteOnPGA(pgaId, true);
      await tradeFinanceFacet.connect(seller).sellerVoteOnPGA(pgaId, true);
    });

    it("Should not allow taking up PGA before payments are complete", async function () {
      await expect(
        tradeFinanceFacet.connect(logisticsPartner).takeUpPGA(pgaId)
      ).to.be.revertedWithCustomError(tradeFinanceFacet, "InvalidPGAStatus");
    });

    it("Should not allow confirming shipment if not the take-up partner", async function () {
      // 1. Pay everything
      await mockUSDC.mint(buyerAddress, ethers.parseUnits("15", 18));
      await mockUSDC.connect(buyer).approve(await deployment.diamond.getAddress(), ethers.parseUnits("15", 18));
      await tradeFinanceFacet.connect(buyer).payCollateral(pgaId, await mockUSDC.getAddress());
      await tradeFinanceFacet.connect(buyer).payIssuanceFee(pgaId, await mockUSDC.getAddress());

      // 2. Logistics Partner 1 takes up
      await tradeFinanceFacet.connect(logisticsPartner).takeUpPGA(pgaId);

      // 3. Logistics Partner 2 (addr2) tries to confirm shipment
      await expect(
        tradeFinanceFacet.connect(seller).confirmGoodsShipped(pgaId)
      ).to.be.revertedWith("Only take-up partner");
    });

    it("Should not allow paying balance before goods are delivered", async function () {
      // 1. Pay everything
      await mockUSDC.mint(buyerAddress, ethers.parseUnits("15", 18));
      await mockUSDC.connect(buyer).approve(await deployment.diamond.getAddress(), ethers.parseUnits("15", 18));
      await tradeFinanceFacet.connect(buyer).payCollateral(pgaId, await mockUSDC.getAddress());
      await tradeFinanceFacet.connect(buyer).payIssuanceFee(pgaId, await mockUSDC.getAddress());

      // 2. Take up
      await tradeFinanceFacet.connect(logisticsPartner).takeUpPGA(pgaId);
      
      // 3. Try to pay balance while in LogisticsTakeup status (6)
      await expect(
        tradeFinanceFacet.connect(buyer).payBalancePayment(pgaId)
      ).to.be.revertedWithCustomError(tradeFinanceFacet, "InvalidPGAStatus");

      // 4. Ship goods
      await tradeFinanceFacet.connect(logisticsPartner).confirmGoodsShipped(pgaId);

      // 5. Try to pay balance while in GoodsShipped status (7)
      await expect(
        tradeFinanceFacet.connect(buyer).payBalancePayment(pgaId)
      ).to.be.revertedWithCustomError(tradeFinanceFacet, "InvalidPGAStatus");
    });
  });
});
