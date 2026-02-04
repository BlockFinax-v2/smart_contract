const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");
const { deployDiamond, setupFinancier } = require("./helpers/diamondHelper");

describe("TradeFinanceFacet Comprehensive Tests", function () {

    describe("PGA Creation", function () {
        it("Should create a valid PGA", async function () {
            const deployment = await deployDiamond();
            const tradeFinanceFacet = await ethers.getContractAt("TradeFinanceFacet", await deployment.diamond.getAddress());

            const pgaId = "PGA-001";
            const seller = await deployment.addr1.getAddress();
            const tradeValue = ethers.parseUnits("1000", 6); // USDC 6 decimals
            const guaranteeAmount = ethers.parseUnits("100", 6);
            const collateralAmount = ethers.parseUnits("10", 6);
            const duration = 30 * 24 * 60 * 60; // 30 days
            const metadataURI = "ipfs://test";
            const documentURIs = ["ipfs://doc1"];
            const companyName = "Test Company";
            const registrationNumber = "REG123";
            const tradeDescription = "Importing Electronics";
            const beneficiaryName = "Supplier Inc";
            const beneficiaryWallet = await deployment.addr2.getAddress();

            await expect(
                tradeFinanceFacet.connect(deployment.owner).createPGA(
                    pgaId,
                    seller,
                    companyName,
                    registrationNumber,
                    tradeDescription,
                    tradeValue,
                    guaranteeAmount,
                    collateralAmount,
                    duration,
                    beneficiaryName,
                    beneficiaryWallet,
                    metadataURI,
                    documentURIs
                )
            ).to.emit(tradeFinanceFacet, "PGACreated");
        });

        it("Should revert if buyer is same as seller", async function () {
            const deployment = await deployDiamond();
            const tradeFinanceFacet = await ethers.getContractAt("TradeFinanceFacet", await deployment.diamond.getAddress());

            await expect(
                tradeFinanceFacet.connect(deployment.owner).createPGA(
                    "PGA-FAIL",
                    await deployment.owner.getAddress(), // Seller matches buyer
                    "Company", "REG", "Desc",
                    1000, 100, 10, 86400,
                    "Ben", await deployment.addr2.getAddress(),
                    "uri", []
                )
            ).to.be.revertedWithCustomError(tradeFinanceFacet, "InvalidAddress");
        });
    });

    describe("PGA Voting Flow", function () {
        let deployment;
        let tradeFinanceFacet;
        let pgaId = "PGA-VOTE";

        beforeEach(async function () {
            deployment = await deployDiamond();
            tradeFinanceFacet = await ethers.getContractAt("TradeFinanceFacet", await deployment.diamond.getAddress());

            // Setup financier
            await setupFinancier(deployment.diamond, deployment.mockUSDC, deployment.owner);

            // Create PGA
            const seller = await deployment.addr1.getAddress();
            await tradeFinanceFacet.connect(deployment.addr2).createPGA(
                pgaId,
                seller,
                "Comp", "Reg", "Desc",
                ethers.parseUnits("1000", 6),
                ethers.parseUnits("100", 6),
                ethers.parseUnits("10", 6),
                86400,
                "Ben", seller,
                "uri", []
            );
        });

        it("Should allow financier to vote", async function () {
            await expect(
                tradeFinanceFacet.connect(deployment.owner).voteOnPGA(pgaId, true)
            ).to.emit(tradeFinanceFacet, "PGAVoteCast");
        });

        it("Should not allow non-financier to vote", async function () {
            await expect(
                tradeFinanceFacet.connect(deployment.addr1).voteOnPGA(pgaId, true)
            ).to.be.revertedWithCustomError(tradeFinanceFacet, "NotFinancier");
        });

        it("Should approve guarantee when threshold met", async function () {
            // Owner has 100% of voting power (only one staked) -> >51% threshold
            await expect(
                tradeFinanceFacet.connect(deployment.owner).voteOnPGA(pgaId, true)
            ).to.emit(tradeFinanceFacet, "PGAStatusChanged");
        });
    });

    describe("Full Lifecycle", function () {
        it("Should complete full PGA lifecycle", async function () {
            const deployment = await deployDiamond();
            const tradeFinanceFacet = await ethers.getContractAt("TradeFinanceFacet", await deployment.diamond.getAddress());
            const liquidityPool = await ethers.getContractAt("LiquidityPoolFacet", await deployment.diamond.getAddress()); // For staking checks if needed? Actually mostly token transfers
            const mockUSDC = deployment.mockUSDC;
            const mockUSDCAddress = await mockUSDC.getAddress();

            // 1. Setup Financier
            await setupFinancier(deployment.diamond, mockUSDC, deployment.owner);

            // 2. Create PGA (Buyer = addr2, Seller = addr1)
            const pgaId = "PGA-FULL";
            const buyer = deployment.addr2;
            const seller = deployment.addr1;
            const sellerAddress = await seller.getAddress();
            const buyerAddress = await buyer.getAddress();

            const tradeValue = ethers.parseUnits("1000", 18); // Use 18 for mock token (default is 18 in mock deploy)
            const guaranteeAmount = ethers.parseUnits("100", 18);
            const collateralAmount = ethers.parseUnits("10", 18);

            await tradeFinanceFacet.connect(buyer).createPGA(
                pgaId,
                sellerAddress,
                "Comp", "Reg", "Desc",
                tradeValue,
                guaranteeAmount,
                collateralAmount,
                86400 * 30,
                "Ben", sellerAddress,
                "uri", []
            );

            // 3. Financier Votes -> GuaranteeApproved
            await tradeFinanceFacet.connect(deployment.owner).voteOnPGA(pgaId, true);

            // 4. Seller Approves
            await expect(
                tradeFinanceFacet.connect(seller).sellerVoteOnPGA(pgaId, true)
            ).to.emit(tradeFinanceFacet, "PGAStatusChanged"); // -> SellerApproved

            // 5. Buyer Pays Collateral
            // Msg.sender (Buyer) must have tokens and approve
            await mockUSDC.mint(buyerAddress, collateralAmount);
            await mockUSDC.connect(buyer).approve(await deployment.diamond.getAddress(), collateralAmount);

            await expect(
                tradeFinanceFacet.connect(buyer).payCollateral(pgaId, await mockUSDC.getAddress())
            ).to.emit(tradeFinanceFacet, "PGAStatusChanged"); // -> CollateralPaid

            // 6. Logistics Partner Confirms Shipment
            // Authorize logistics partner first
            const logisticsPartner = deployment.addr2;
            await tradeFinanceFacet.connect(deployment.owner).authorizeLogisticsPartner(await logisticsPartner.getAddress(), true);

            // Confirm shipment
            await expect(
                tradeFinanceFacet.connect(logisticsPartner).confirmGoodsShipped(pgaId, "FastLogistics")
            ).to.emit(tradeFinanceFacet, "PGAStatusChanged"); // -> GoodsShipped

            // 7. Buyer Pays Balance
            // Balance = 1000 - 10 = 990
            const balanceAmount = tradeValue - collateralAmount;
            await mockUSDC.mint(buyerAddress, balanceAmount);
            await mockUSDC.connect(buyer).approve(await deployment.diamond.getAddress(), balanceAmount);

            await expect(
                tradeFinanceFacet.connect(buyer).payBalancePayment(pgaId, await mockUSDC.getAddress())
            ).to.emit(tradeFinanceFacet, "PGAStatusChanged"); // -> BalancePaymentPaid

            // 8. Issue Certificate
            await expect(
                tradeFinanceFacet.connect(buyer).issueCertificate(pgaId)
            ).to.emit(tradeFinanceFacet, "PGAStatusChanged") // -> CertificateIssued
                .and.to.emit(tradeFinanceFacet, "CertificateIssued");

            // 9. Create Delivery Agreement (Logistics Partner or Delivery Person)
            const deliveryPerson = deployment.addr2;
            // Authorize first (already logistic partner so OK, but check logic: Is AuthorizedDeliveryPerson OR LogisticsPartner? Yes)
            const agreementId = "AGREE-001";
            const deadline = (await time.latest()) + 86400;

            await expect(
                tradeFinanceFacet.connect(deliveryPerson).createDeliveryAgreement(
                    agreementId, pgaId, deadline, "Notes", "proof"
                )
            ).to.emit(tradeFinanceFacet, "PGAStatusChanged"); // -> DeliveryAwaitingConsent

            // 10. Buyer Consent
            await expect(
                tradeFinanceFacet.connect(buyer).buyerConsentToDelivery(agreementId, true)
            ).to.emit(tradeFinanceFacet, "PGAStatusChanged") // -> Completed
                .and.to.emit(tradeFinanceFacet, "PGACompleted");
        });
    });
});
