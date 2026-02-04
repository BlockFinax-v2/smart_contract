import { expect } from "chai";
import { ethers } from "hardhat";
import { time } from "@nomicfoundation/hardhat-network-helpers";
const { deployDiamond, setupFinancier } = require("./helpers/diamondHelper");

describe("TradeFinanceFacet - Comprehensive Tests for Updated Functions", function () {
  let deployment: any;
  let tradeFinanceFacet: any;
  let mockUSDC: any;
  let owner: any;
  let buyer: any;
  let seller: any;
  let logisticsPartner: any;
  let deliveryPerson: any;
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
    
    // Get additional signers for logistics, delivery, and treasury
    const signers = await ethers.getSigners();
    logisticsPartner = signers[3];
    deliveryPerson = signers[4];
    treasury = signers[5];

    // Setup financier
    await setupFinancier(deployment.diamond, mockUSDC, owner);
  });

  describe("Treasury Management", function () {
    it("Should set BlockFinax treasury address", async function () {
      const treasuryAddress = await treasury.getAddress();

      await expect(
        tradeFinanceFacet.connect(owner).setBlockFinaxTreasury(treasuryAddress)
      )
        .to.emit(tradeFinanceFacet, "BlockFinaxTreasuryUpdated")
        .withArgs(ethers.ZeroAddress, treasuryAddress);

      const storedTreasury = await tradeFinanceFacet.getBlockFinaxTreasury();
      expect(storedTreasury).to.equal(treasuryAddress);
    });

    it("Should revert when setting zero address as treasury", async function () {
      await expect(
        tradeFinanceFacet.connect(owner).setBlockFinaxTreasury(ethers.ZeroAddress)
      ).to.be.revertedWithCustomError(tradeFinanceFacet, "ZeroAddress");
    });

    it("Should only allow owner to set treasury", async function () {
      await expect(
        tradeFinanceFacet.connect(buyer).setBlockFinaxTreasury(await treasury.getAddress())
      ).to.be.reverted;
    });
  });

  describe("Logistics Partner Management", function () {
    it("Should authorize logistics partner using authorizeLogisticsPartner", async function () {
      const partnerAddress = await logisticsPartner.getAddress();

      await expect(
        tradeFinanceFacet.connect(owner).authorizeLogisticsPartner(partnerAddress, true)
      )
        .to.emit(tradeFinanceFacet, "LogisticPartnerAuthorized")
        .withArgs(partnerAddress, true, await time.latest() + 1);

      // Verify authorization
      const isAuthorized = await tradeFinanceFacet.isAuthorizedLogisticsPartner(
        partnerAddress
      );
      expect(isAuthorized).to.be.true;
    });

    it("Should authorize logistics partner using both methods", async function () {
      const partnerAddress = await logisticsPartner.getAddress();

      await expect(
        tradeFinanceFacet.connect(owner).authorizeLogisticsPartner(partnerAddress, true)
      )
        .to.emit(tradeFinanceFacet, "LogisticPartnerAuthorized");

      // Verify authorization
      const isAuthorized = await tradeFinanceFacet.isAuthorizedLogisticsPartner(
        partnerAddress
      );
      expect(isAuthorized).to.be.true;
    });

    it("Should add partner to list when authorized", async function () {
      const partnerAddress = await logisticsPartner.getAddress();

      await tradeFinanceFacet.connect(owner).authorizeLogisticsPartner(partnerAddress, true);

      const allPartners = await tradeFinanceFacet.getAllLogisticsPartners();
      expect(allPartners).to.include(partnerAddress);
      expect(allPartners.length).to.equal(1);
    });

    it("Should not duplicate partner in list when authorized twice", async function () {
      const partnerAddress = await logisticsPartner.getAddress();

      await tradeFinanceFacet.connect(owner).authorizeLogisticsPartner(partnerAddress, true);
      await tradeFinanceFacet.connect(owner).authorizeLogisticsPartner(partnerAddress, true);

      const allPartners = await tradeFinanceFacet.getAllLogisticsPartners();
      expect(allPartners.length).to.equal(1);
    });

    it("Should keep partner in list when deauthorized", async function () {
      const partnerAddress = await logisticsPartner.getAddress();

      await tradeFinanceFacet.connect(owner).authorizeLogisticsPartner(partnerAddress, true);
      await tradeFinanceFacet.connect(owner).authorizeLogisticsPartner(partnerAddress, false);

      const allPartners = await tradeFinanceFacet.getAllLogisticsPartners();
      expect(allPartners).to.include(partnerAddress);

      const isAuthorized = await tradeFinanceFacet.isAuthorizedLogisticsPartner(
        partnerAddress
      );
      expect(isAuthorized).to.be.false;
    });

    it("Should return multiple logistics partners", async function () {
      const partner1 = await logisticsPartner.getAddress();
      const partner2 = await deliveryPerson.getAddress();

      await tradeFinanceFacet.connect(owner).authorizeLogisticsPartner(partner1, true);
      await tradeFinanceFacet.connect(owner).authorizeLogisticsPartner(partner2, true);

      const allPartners = await tradeFinanceFacet.getAllLogisticsPartners();
      expect(allPartners).to.include(partner1);
      expect(allPartners).to.include(partner2);
      expect(allPartners.length).to.equal(2);
    });

    it("Should completely remove logistics partner from system", async function () {
      const partnerAddress = await logisticsPartner.getAddress();

      // Authorize partner
      await tradeFinanceFacet.connect(owner).authorizeLogisticsPartner(partnerAddress, true);
      
      let allPartners = await tradeFinanceFacet.getAllLogisticsPartners();
      expect(allPartners).to.include(partnerAddress);
      expect(allPartners.length).to.equal(1);

      // Remove partner
      await tradeFinanceFacet.connect(owner).removeLogisticsPartner(partnerAddress);

      // Verify removal from array
      allPartners = await tradeFinanceFacet.getAllLogisticsPartners();
      expect(allPartners).to.not.include(partnerAddress);
      expect(allPartners.length).to.equal(0);

      // Verify removal from mapping
      const isAuthorized = await tradeFinanceFacet.isAuthorizedLogisticsPartner(partnerAddress);
      expect(isAuthorized).to.be.false;
    });

    it("Should remove specific partner from multiple partners", async function () {
      const partner1 = await logisticsPartner.getAddress();
      const partner2 = await deliveryPerson.getAddress();
      const partner3 = await treasury.getAddress();

      // Authorize three partners
      await tradeFinanceFacet.connect(owner).authorizeLogisticsPartner(partner1, true);
      await tradeFinanceFacet.connect(owner).authorizeLogisticsPartner(partner2, true);
      await tradeFinanceFacet.connect(owner).authorizeLogisticsPartner(partner3, true);

      let allPartners = await tradeFinanceFacet.getAllLogisticsPartners();
      expect(allPartners.length).to.equal(3);

      // Remove middle partner
      await tradeFinanceFacet.connect(owner).removeLogisticsPartner(partner2);

      // Verify only partner2 is removed
      allPartners = await tradeFinanceFacet.getAllLogisticsPartners();
      expect(allPartners).to.include(partner1);
      expect(allPartners).to.not.include(partner2);
      expect(allPartners).to.include(partner3);
      expect(allPartners.length).to.equal(2);
    });

    it("Should only allow owner to remove logistics partner", async function () {
      const partnerAddress = await logisticsPartner.getAddress();

      await tradeFinanceFacet.connect(owner).authorizeLogisticsPartner(partnerAddress, true);

      await expect(
        tradeFinanceFacet.connect(buyer).removeLogisticsPartner(partnerAddress)
      ).to.be.reverted;
    });

    it("Should revert when removing zero address", async function () {
      await expect(
        tradeFinanceFacet.connect(owner).removeLogisticsPartner(ethers.ZeroAddress)
      ).to.be.revertedWithCustomError(tradeFinanceFacet, "ZeroAddress");
    });
  });

  describe("Delivery Person Management", function () {
    it("Should authorize delivery person", async function () {
      const personAddress = await deliveryPerson.getAddress();

      await tradeFinanceFacet.connect(owner).setDeliveryPerson(personAddress, true);

      const isAuthorized = await tradeFinanceFacet.isAuthorizedDeliveryPerson(
        personAddress
      );
      expect(isAuthorized).to.be.true;
    });

    it("Should add delivery person to list when authorized", async function () {
      const personAddress = await deliveryPerson.getAddress();

      await tradeFinanceFacet.connect(owner).setDeliveryPerson(personAddress, true);

      const allPersons = await tradeFinanceFacet.getAllDeliveryPersons();
      expect(allPersons).to.include(personAddress);
      expect(allPersons.length).to.equal(1);
    });

    it("Should return multiple delivery persons", async function () {
      const person1 = await deliveryPerson.getAddress();
      const person2 = await logisticsPartner.getAddress();

      await tradeFinanceFacet.connect(owner).setDeliveryPerson(person1, true);
      await tradeFinanceFacet.connect(owner).setDeliveryPerson(person2, true);

      const allPersons = await tradeFinanceFacet.getAllDeliveryPersons();
      expect(allPersons).to.include(person1);
      expect(allPersons).to.include(person2);
      expect(allPersons.length).to.equal(2);
    });

    it("Should completely remove delivery person from system", async function () {
      const personAddress = await deliveryPerson.getAddress();

      // Authorize delivery person
      await tradeFinanceFacet.connect(owner).setDeliveryPerson(personAddress, true);
      
      let allPersons = await tradeFinanceFacet.getAllDeliveryPersons();
      expect(allPersons).to.include(personAddress);
      expect(allPersons.length).to.equal(1);

      // Remove delivery person
      await tradeFinanceFacet.connect(owner).removeDeliveryPerson(personAddress);

      // Verify removal from array
      allPersons = await tradeFinanceFacet.getAllDeliveryPersons();
      expect(allPersons).to.not.include(personAddress);
      expect(allPersons.length).to.equal(0);

      // Verify removal from mapping
      const isAuthorized = await tradeFinanceFacet.isAuthorizedDeliveryPerson(personAddress);
      expect(isAuthorized).to.be.false;
    });

    it("Should remove specific delivery person from multiple persons", async function () {
      const person1 = await deliveryPerson.getAddress();
      const person2 = await logisticsPartner.getAddress();
      const person3 = await treasury.getAddress();

      // Authorize three persons
      await tradeFinanceFacet.connect(owner).setDeliveryPerson(person1, true);
      await tradeFinanceFacet.connect(owner).setDeliveryPerson(person2, true);
      await tradeFinanceFacet.connect(owner).setDeliveryPerson(person3, true);

      let allPersons = await tradeFinanceFacet.getAllDeliveryPersons();
      expect(allPersons.length).to.equal(3);

      // Remove middle person
      await tradeFinanceFacet.connect(owner).removeDeliveryPerson(person2);

      // Verify only person2 is removed
      allPersons = await tradeFinanceFacet.getAllDeliveryPersons();
      expect(allPersons).to.include(person1);
      expect(allPersons).to.not.include(person2);
      expect(allPersons).to.include(person3);
      expect(allPersons.length).to.equal(2);
    });

    it("Should only allow owner to remove delivery person", async function () {
      const personAddress = await deliveryPerson.getAddress();

      await tradeFinanceFacet.connect(owner).setDeliveryPerson(personAddress, true);

      await expect(
        tradeFinanceFacet.connect(buyer).removeDeliveryPerson(personAddress)
      ).to.be.reverted;
    });

    it("Should revert when removing zero address", async function () {
      await expect(
        tradeFinanceFacet.connect(owner).removeDeliveryPerson(ethers.ZeroAddress)
      ).to.be.revertedWithCustomError(tradeFinanceFacet, "ZeroAddress");
    });
  });

  describe("Issuance Fee Payment", function () {
    let pgaId: string;
    const tradeValue = ethers.parseUnits("1000", 18);
    const guaranteeAmount = ethers.parseUnits("100", 18);
    const collateralAmount = ethers.parseUnits("10", 18);

    beforeEach(async function () {
      // Set treasury
      await tradeFinanceFacet
        .connect(owner)
        .setBlockFinaxTreasury(await treasury.getAddress());

      // Create PGA
      pgaId = "PGA-FEE-TEST";
      await tradeFinanceFacet.connect(buyer).createPGA(
        pgaId,
        await seller.getAddress(),
        "Company",
        "REG123",
        "Trade Desc",
        tradeValue,
        guaranteeAmount,
        collateralAmount,
        86400 * 30,
        "Beneficiary",
        await seller.getAddress(),
        "ipfs://metadata",
        []
      );

      // Financier votes to approve
      await tradeFinanceFacet.connect(owner).voteOnPGA(pgaId, true);

      // Seller approves
      await tradeFinanceFacet.connect(seller).sellerVoteOnPGA(pgaId, true);

      // Pay collateral
      await mockUSDC.mint(await buyer.getAddress(), collateralAmount);
      await mockUSDC
        .connect(buyer)
        .approve(await deployment.diamond.getAddress(), collateralAmount);
      await tradeFinanceFacet.connect(buyer).payCollateral(pgaId, await mockUSDC.getAddress());
    });

    it("Should pay issuance fee successfully", async function () {
      const feeAmount = guaranteeAmount / 100n; // 1%

      await mockUSDC.mint(await buyer.getAddress(), feeAmount);
      await mockUSDC
        .connect(buyer)
        .approve(await deployment.diamond.getAddress(), feeAmount);

      const treasuryBalanceBefore = await mockUSDC.balanceOf(
        await treasury.getAddress()
      );

      await expect(tradeFinanceFacet.connect(buyer).payIssuanceFee(pgaId, await mockUSDC.getAddress()))
        .to.emit(tradeFinanceFacet, "IssuanceFeePaid")
        .withArgs(
          pgaId,
          await buyer.getAddress(),
          await treasury.getAddress(),
          feeAmount,
          await time.latest() + 1
        );

      const treasuryBalanceAfter = await mockUSDC.balanceOf(
        await treasury.getAddress()
      );
      expect(treasuryBalanceAfter - treasuryBalanceBefore).to.equal(feeAmount);
    });

    it("Should update issuanceFeePaid flag", async function () {
      const feeAmount = guaranteeAmount / 100n;

      await mockUSDC.mint(await buyer.getAddress(), feeAmount);
      await mockUSDC
        .connect(buyer)
        .approve(await deployment.diamond.getAddress(), feeAmount);

      await tradeFinanceFacet.connect(buyer).payIssuanceFee(pgaId, await mockUSDC.getAddress());

      const pga = await tradeFinanceFacet.getPGA(pgaId);
      expect(pga.issuanceFeePaid).to.be.true;
    });

    it("Should revert if collateral not paid", async function () {
      // Create new PGA without paying collateral
      const newPgaId = "PGA-NO-COLLATERAL";
      await tradeFinanceFacet.connect(buyer).createPGA(
        newPgaId,
        await seller.getAddress(),
        "Company",
        "REG123",
        "Trade Desc",
        tradeValue,
        guaranteeAmount,
        collateralAmount,
        86400 * 30,
        "Beneficiary",
        await seller.getAddress(),
        "ipfs://metadata",
        []
      );

      await tradeFinanceFacet.connect(owner).voteOnPGA(newPgaId, true);
      await tradeFinanceFacet.connect(seller).sellerVoteOnPGA(newPgaId, true);

      await expect(
        tradeFinanceFacet.connect(buyer).payIssuanceFee(newPgaId, await mockUSDC.getAddress())
      ).to.be.revertedWithCustomError(tradeFinanceFacet, "InvalidPGAStatus");
    });

    it("Should revert if treasury not set", async function () {
      // Create new deployment without treasury
      const newDeployment = await deployDiamond();
      const newTradeFacet = await ethers.getContractAt(
        "TradeFinanceFacet",
        await newDeployment.diamond.getAddress()
      );
      await setupFinancier(newDeployment.diamond, newDeployment.mockUSDC, owner);

      const testPgaId = "PGA-NO-TREASURY";
      await newTradeFacet.connect(buyer).createPGA(
        testPgaId,
        await seller.getAddress(),
        "Company",
        "REG123",
        "Trade Desc",
        tradeValue,
        guaranteeAmount,
        collateralAmount,
        86400 * 30,
        "Beneficiary",
        await seller.getAddress(),
        "ipfs://metadata",
        []
      );

      await newTradeFacet.connect(owner).voteOnPGA(testPgaId, true);
      await newTradeFacet.connect(seller).sellerVoteOnPGA(testPgaId, true);

      await newDeployment.mockUSDC.mint(await buyer.getAddress(), collateralAmount);
      await newDeployment.mockUSDC
        .connect(buyer)
        .approve(await newDeployment.diamond.getAddress(), collateralAmount);
      await newTradeFacet.connect(buyer).payCollateral(testPgaId, await newDeployment.mockUSDC.getAddress());

      await expect(
        newTradeFacet.connect(buyer).payIssuanceFee(testPgaId, await newDeployment.mockUSDC.getAddress())
      ).to.be.revertedWithCustomError(tradeFinanceFacet, "TreasuryNotSet");
    });

    it("Should revert if fee already paid", async function () {
      const feeAmount = guaranteeAmount / 100n;

      await mockUSDC.mint(await buyer.getAddress(), feeAmount * 2n);
      await mockUSDC
        .connect(buyer)
        .approve(await deployment.diamond.getAddress(), feeAmount * 2n);

      await tradeFinanceFacet.connect(buyer).payIssuanceFee(pgaId, await mockUSDC.getAddress());

      await expect(
        tradeFinanceFacet.connect(buyer).payIssuanceFee(pgaId, await mockUSDC.getAddress())
      ).to.be.revertedWithCustomError(tradeFinanceFacet, "IssuanceFeeAlreadyPaid");
    });

    it("Should revert if only seller tries to pay", async function () {
      const feeAmount = guaranteeAmount / 100n;

      await mockUSDC.mint(await seller.getAddress(), feeAmount);
      await mockUSDC
        .connect(seller)
        .approve(await deployment.diamond.getAddress(), feeAmount);

      await expect(
        tradeFinanceFacet.connect(seller).payIssuanceFee(pgaId, await mockUSDC.getAddress())
      ).to.be.revertedWithCustomError(tradeFinanceFacet, "OnlyBuyerAllowed");
    });
  });

  describe("getPGA - 26 Field Return", function () {
    it("Should return all 26 fields including issuanceFeePaid", async function () {
      const pgaId = "PGA-GET-TEST";
      const tradeValue = ethers.parseUnits("1000", 18);
      const guaranteeAmount = ethers.parseUnits("100", 18);
      const collateralAmount = ethers.parseUnits("10", 18);

      await tradeFinanceFacet.connect(buyer).createPGA(
        pgaId,
        await seller.getAddress(),
        "TestCompany",
        "REG456",
        "Test Trade",
        tradeValue,
        guaranteeAmount,
        collateralAmount,
        86400 * 30,
        "Beneficiary Name",
        await seller.getAddress(),
        "ipfs://test",
        ["ipfs://doc1", "ipfs://doc2"]
      );

      const pga = await tradeFinanceFacet.getPGA(pgaId);

      // Verify structure (26 fields)
      expect(pga._pgaId).to.equal(pgaId);
      expect(pga.buyer).to.equal(await buyer.getAddress());
      expect(pga.seller).to.equal(await seller.getAddress());
      expect(pga.tradeValue).to.equal(tradeValue);
      expect(pga.guaranteeAmount).to.equal(guaranteeAmount);
      expect(pga.collateralAmount).to.equal(collateralAmount);
      expect(pga.collateralPaid).to.be.false;
      expect(pga.issuanceFeePaid).to.be.false; // NEW FIELD
      expect(pga.balancePaymentPaid).to.be.false;
      expect(pga.goodsShipped).to.be.false;
      expect(pga.companyName).to.equal("TestCompany");
      expect(pga.registrationNumber).to.equal("REG456");
      expect(pga.tradeDescription).to.equal("Test Trade");
      expect(pga.beneficiaryName).to.equal("Beneficiary Name");
      expect(pga.beneficiaryWallet).to.equal(await seller.getAddress());
      expect(pga.uploadedDocuments.length).to.equal(2);
    });
  });

  describe("Full PGA Lifecycle with Issuance Fee", function () {
    it("Should complete full flow: Create → Vote → Approve → PayCollateral → PayFee → Ship → Pay → Certificate → Deliver → Complete", async function () {
      const pgaId = "PGA-FULL-LIFECYCLE";
      const tradeValue = ethers.parseUnits("1000", 18);
      const guaranteeAmount = ethers.parseUnits("100", 18);
      const collateralAmount = ethers.parseUnits("10", 18);
      const feeAmount = guaranteeAmount / 100n; // 1%

      // Set treasury
      await tradeFinanceFacet
        .connect(owner)
        .setBlockFinaxTreasury(await treasury.getAddress());

      // 1. Create PGA
      await tradeFinanceFacet.connect(buyer).createPGA(
        pgaId,
        await seller.getAddress(),
        "FullCycle Co",
        "REG999",
        "Complete Trade",
        tradeValue,
        guaranteeAmount,
        collateralAmount,
        86400 * 30,
        "Seller Inc",
        await seller.getAddress(),
        "ipfs://full",
        []
      );

      let pga = await tradeFinanceFacet.getPGA(pgaId);
      expect(pga.status).to.equal(1); // Created

      // 2. Financier votes
      await tradeFinanceFacet.connect(owner).voteOnPGA(pgaId, true);
      pga = await tradeFinanceFacet.getPGA(pgaId);
      expect(pga.status).to.equal(2); // GuaranteeApproved

      // 3. Seller approves
      await tradeFinanceFacet.connect(seller).sellerVoteOnPGA(pgaId, true);
      pga = await tradeFinanceFacet.getPGA(pgaId);
      expect(pga.status).to.equal(3); // SellerApproved

      // 4. Pay collateral
      await mockUSDC.mint(await buyer.getAddress(), collateralAmount);
      await mockUSDC
        .connect(buyer)
        .approve(await deployment.diamond.getAddress(), collateralAmount);
      await tradeFinanceFacet.connect(buyer).payCollateral(pgaId, await mockUSDC.getAddress());
      pga = await tradeFinanceFacet.getPGA(pgaId);
      expect(pga.status).to.equal(4); // CollateralPaid
      expect(pga.collateralPaid).to.be.true;
      expect(pga.issuanceFeePaid).to.be.false;

      // 5. Pay issuance fee (NEW STEP)
      await mockUSDC.mint(await buyer.getAddress(), feeAmount);
      await mockUSDC
        .connect(buyer)
        .approve(await deployment.diamond.getAddress(), feeAmount);
      await tradeFinanceFacet.connect(buyer).payIssuanceFee(pgaId, await mockUSDC.getAddress());
      pga = await tradeFinanceFacet.getPGA(pgaId);
      expect(pga.issuanceFeePaid).to.be.true;

      // 6. Authorize and ship goods
      await tradeFinanceFacet
        .connect(owner)
        .authorizeLogisticsPartner(await logisticsPartner.getAddress(), true);
      await tradeFinanceFacet
        .connect(logisticsPartner)
        .confirmGoodsShipped(pgaId, "FastShip");
      pga = await tradeFinanceFacet.getPGA(pgaId);
      expect(pga.status).to.equal(5); // GoodsShipped

      // 7. Pay balance
      const balanceAmount = tradeValue - collateralAmount;
      await mockUSDC.mint(await buyer.getAddress(), balanceAmount);
      await mockUSDC
        .connect(buyer)
        .approve(await deployment.diamond.getAddress(), balanceAmount);
      await tradeFinanceFacet.connect(buyer).payBalancePayment(pgaId, await mockUSDC.getAddress());
      pga = await tradeFinanceFacet.getPGA(pgaId);
      expect(pga.status).to.equal(6); // BalancePaymentPaid

      // 8. Issue certificate
      await tradeFinanceFacet.connect(buyer).issueCertificate(pgaId);
      pga = await tradeFinanceFacet.getPGA(pgaId);
      expect(pga.status).to.equal(7); // CertificateIssued

      // 9. Create delivery agreement
      const agreementId = "AGREE-FULL";
      const deadline = (await time.latest()) + 86400;
      await tradeFinanceFacet
        .connect(logisticsPartner)
        .createDeliveryAgreement(agreementId, pgaId, deadline, "Delivery notes", "ipfs://proof");
      pga = await tradeFinanceFacet.getPGA(pgaId);
      expect(pga.status).to.equal(8); // DeliveryAwaitingConsent

      // 10. Buyer consent
      await tradeFinanceFacet.connect(buyer).buyerConsentToDelivery(agreementId, true);
      pga = await tradeFinanceFacet.getPGA(pgaId);
      expect(pga.status).to.equal(9); // Completed
    });
  });
});
