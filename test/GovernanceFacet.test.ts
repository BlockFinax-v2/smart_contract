const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");
const { deployDiamond, setupFinancier } = require("./helpers/diamondHelper");

describe("GovernanceFacet Comprehensive Tests", function () {

  describe("Contract Initialization", function () {
    it("Should deploy GovernanceFacet successfully", async function () {
      const GovernanceFacet = await ethers.getContractFactory("GovernanceFacet");
      const governanceFacet = await GovernanceFacet.deploy();
      await governanceFacet.waitForDeployment();

      expect(await governanceFacet.getAddress()).to.be.a("string");
      expect(await governanceFacet.getAddress()).to.have.length(42);
    });

    it("Should initialize with correct default values", async function () {
      const deployment = await deployDiamond();
      const governanceFacet = await ethers.getContractAt("GovernanceFacet", await deployment.diamond.getAddress());
      const config = await governanceFacet.getDAOConfig();

      expect(config[0]).to.be.a("bigint"); // minimumFinancierStake
      expect(config[1]).to.be.a("bigint"); // votingDuration
      expect(config[2]).to.be.a("bigint"); // approvalThreshold
      expect(config[3]).to.be.a("bigint"); // revocationPeriod
    });
  });

  describe("Pause/Unpause Functionality", function () {
    it("Should allow owner to pause contract", async function () {
      const deployment = await deployDiamond();
      const governanceFacet = await ethers.getContractAt("GovernanceFacet", await deployment.diamond.getAddress());

      await expect(governanceFacet.connect(deployment.owner).pause())
        .to.emit(governanceFacet, "Paused")
        .withArgs(await deployment.owner.getAddress());

      expect(await governanceFacet.paused()).to.be.true;
    });

    it("Should allow owner to unpause contract", async function () {
      const deployment = await deployDiamond();
      const governanceFacet = await ethers.getContractAt("GovernanceFacet", await deployment.diamond.getAddress());

      await governanceFacet.connect(deployment.owner).pause();

      await expect(governanceFacet.connect(deployment.owner).unpause())
        .to.emit(governanceFacet, "Unpaused")
        .withArgs(await deployment.owner.getAddress());

      expect(await governanceFacet.paused()).to.be.false;
    });

    it("Should not allow non-owner to pause", async function () {
      const deployment = await deployDiamond();
      const governanceFacet = await ethers.getContractAt("GovernanceFacet", await deployment.diamond.getAddress());

      await expect(
        governanceFacet.connect(deployment.addr1).pause()
      ).to.be.revertedWith("LibDiamond: Must be contract owner");
    });

    it("Should not allow non-owner to unpause", async function () {
      const deployment = await deployDiamond();
      const governanceFacet = await ethers.getContractAt("GovernanceFacet", await deployment.diamond.getAddress());

      await governanceFacet.connect(deployment.owner).pause();

      await expect(
        governanceFacet.connect(deployment.addr1).unpause()
      ).to.be.revertedWith("LibDiamond: Must be contract owner");
    });

    it("Should prevent operations when paused", async function () {
      const deployment = await deployDiamond();
      const governanceFacet = await ethers.getContractAt("GovernanceFacet", await deployment.diamond.getAddress());

      await governanceFacet.connect(deployment.owner).pause();

      await expect(
        governanceFacet.createProposal("PROP-001", "FINANCIAL", "Test", "Description")
      ).to.be.revertedWithCustomError(governanceFacet, "ContractPaused");
    });
  });

  describe("DAO Configuration Management", function () {
    it("Should return initial DAO config", async function () {
      const deployment = await deployDiamond();
      const governanceFacet = await ethers.getContractAt("GovernanceFacet", await deployment.diamond.getAddress());

      const config = await governanceFacet.getDAOConfig();
      expect(config[0]).to.be.a("bigint"); // minimumFinancierStake
      expect(config[1]).to.be.a("bigint"); // votingDuration
      expect(config[2]).to.be.a("bigint"); // approvalThreshold
      expect(config[3]).to.be.a("bigint"); // revocationPeriod
    });

    it("Should allow owner to update voting duration", async function () {
      const deployment = await deployDiamond();
      const governanceFacet = await ethers.getContractAt("GovernanceFacet", await deployment.diamond.getAddress());

      const newDuration = 7 * 24 * 60 * 60; // 7 days

      await expect(
        governanceFacet.connect(deployment.owner).setVotingDuration(newDuration)
      ).to.emit(governanceFacet, "ParameterUpdated")
        .withArgs("votingDuration", newDuration);
    });

    it("Should not allow zero voting duration", async function () {
      const deployment = await deployDiamond();
      const governanceFacet = await ethers.getContractAt("GovernanceFacet", await deployment.diamond.getAddress());

      await expect(
        governanceFacet.connect(deployment.owner).setVotingDuration(0)
      ).to.be.revertedWithCustomError(governanceFacet, "InvalidDuration");
    });

    it("Should not allow excessive voting duration", async function () {
      const deployment = await deployDiamond();
      const governanceFacet = await ethers.getContractAt("GovernanceFacet", await deployment.diamond.getAddress());

      const excessiveDuration = 365 * 24 * 60 * 60; // 1 year

      await expect(
        governanceFacet.connect(deployment.owner).setVotingDuration(excessiveDuration)
      ).to.be.revertedWithCustomError(governanceFacet, "InvalidDuration");
    });

    it("Should allow updating proposal threshold", async function () {
      const deployment = await deployDiamond();
      const governanceFacet = await ethers.getContractAt("GovernanceFacet", await deployment.diamond.getAddress());

      const newThreshold = ethers.parseUnits("2000", 18); // Must be >= minimumFinancierStake (1000)

      await expect(
        governanceFacet.connect(deployment.owner).setProposalThreshold(newThreshold)
      ).to.emit(governanceFacet, "ParameterUpdated")
        .withArgs("proposalThreshold", newThreshold);
    });

    it("Should allow updating approval threshold", async function () {
      const deployment = await deployDiamond();
      const governanceFacet = await ethers.getContractAt("GovernanceFacet", await deployment.diamond.getAddress());

      const newThreshold = 51; // 51% (must be between 1-100)

      await expect(
        governanceFacet.connect(deployment.owner).setApprovalThreshold(newThreshold)
      ).to.emit(governanceFacet, "ParameterUpdated")
        .withArgs("approvalThreshold", newThreshold);
    });

    it("Should not allow approval threshold above 100", async function () {
      const deployment = await deployDiamond();
      const governanceFacet = await ethers.getContractAt("GovernanceFacet", await deployment.diamond.getAddress());

      await expect(
        governanceFacet.connect(deployment.owner).setApprovalThreshold(101)
      ).to.be.revertedWithCustomError(governanceFacet, "InvalidPercentage");
    });

    it("Should not allow non-owner to update config", async function () {
      const deployment = await deployDiamond();
      const governanceFacet = await ethers.getContractAt("GovernanceFacet", await deployment.diamond.getAddress());

      await expect(
        governanceFacet.connect(deployment.addr1).setVotingDuration(3600)
      ).to.be.revertedWith("LibDiamond: Must be contract owner");
    });
  });

  describe("Proposal Management", function () {
    it("Should allow creating a proposal", async function () {
      const deployment = await deployDiamond();
      const governanceFacet = await ethers.getContractAt("GovernanceFacet", await deployment.diamond.getAddress());

      // Setup financier
      await setupFinancier(deployment.diamond, deployment.mockUSDC, deployment.owner);

      const proposalId = "PROP-001";
      const category = "FINANCIAL";
      const title = "Test Proposal";
      const description = "Test proposal description";

      await expect(
        governanceFacet.connect(deployment.owner).createProposal(proposalId, category, title, description)
      ).to.emit(governanceFacet, "ProposalCreated");
      // Event has 5 parameters: proposalId, category, title, proposer, votingDeadline
    });

    it("Should not allow empty proposal ID", async function () {
      const deployment = await deployDiamond();
      const governanceFacet = await ethers.getContractAt("GovernanceFacet", await deployment.diamond.getAddress());

      // Setup financier
      await setupFinancier(deployment.diamond, deployment.mockUSDC, deployment.owner);

      await expect(
        governanceFacet.connect(deployment.owner).createProposal("", "FINANCIAL", "Test", "Description")
      ).to.be.revertedWithCustomError(governanceFacet, "InvalidProposalId");
    });

    it("Should not allow empty title", async function () {
      const deployment = await deployDiamond();
      const governanceFacet = await ethers.getContractAt("GovernanceFacet", await deployment.diamond.getAddress());

      // Setup financier
      await setupFinancier(deployment.diamond, deployment.mockUSDC, deployment.owner);

      await expect(
        governanceFacet.connect(deployment.owner).createProposal("PROP-001", "FINANCIAL", "", "Description")
      ).to.be.revertedWithCustomError(governanceFacet, "InvalidTitle");
    });

    it("Should not allow empty description", async function () {
      const deployment = await deployDiamond();
      const governanceFacet = await ethers.getContractAt("GovernanceFacet", await deployment.diamond.getAddress());

      // Setup financier
      await setupFinancier(deployment.diamond, deployment.mockUSDC, deployment.owner);

      await expect(
        governanceFacet.connect(deployment.owner).createProposal("PROP-001", "FINANCIAL", "Title", "")
      ).to.be.revertedWithCustomError(governanceFacet, "InvalidDescription");
    });

    it("Should not allow invalid category", async function () {
      const deployment = await deployDiamond();
      const governanceFacet = await ethers.getContractAt("GovernanceFacet", await deployment.diamond.getAddress());

      // Setup financier
      await setupFinancier(deployment.diamond, deployment.mockUSDC, deployment.owner);

      // Test empty category
      await expect(
        governanceFacet.connect(deployment.owner).createProposal("PROP-001", "", "Title", "Description")
      ).to.be.revertedWithCustomError(governanceFacet, "InvalidCategory");
    });

    it("Should not allow duplicate proposal IDs", async function () {
      const deployment = await deployDiamond();
      const governanceFacet = await ethers.getContractAt("GovernanceFacet", await deployment.diamond.getAddress());

      // Setup financier
      await setupFinancier(deployment.diamond, deployment.mockUSDC, deployment.owner);

      const proposalId = "PROP-001";
      const category = "FINANCIAL";
      const title = "Test Proposal";
      const description = "Test proposal description";

      await governanceFacet.connect(deployment.owner).createProposal(proposalId, category, title, description);

      await expect(
        governanceFacet.connect(deployment.owner).createProposal(proposalId, category, title, description)
      ).to.be.revertedWithCustomError(governanceFacet, "ProposalAlreadyExists");
    });

    it("Should return proposal details", async function () {
      const deployment = await deployDiamond();
      const governanceFacet = await ethers.getContractAt("GovernanceFacet", await deployment.diamond.getAddress());

      // Setup financier
      await setupFinancier(deployment.diamond, deployment.mockUSDC, deployment.owner);

      const proposalId = "PROP-001";
      const category = "FINANCIAL";
      const title = "Test Proposal";
      const description = "Test proposal description";

      await governanceFacet.connect(deployment.owner).createProposal(proposalId, category, title, description);

      const proposal = await governanceFacet.getProposal(proposalId);
      expect(proposal.category).to.equal(category);
      expect(proposal.title).to.equal(title);
      expect(proposal.description).to.equal(description);
      expect(proposal.proposer).to.equal(await deployment.owner.getAddress());
    });

    it("Should return default values for non-existent proposal", async function () {
      const deployment = await deployDiamond();
      const governanceFacet = await ethers.getContractAt("GovernanceFacet", await deployment.diamond.getAddress());

      const proposal = await governanceFacet.getProposal("NON-EXISTENT");
      expect(proposal.createdAt).to.equal(0);
    });
  });

  describe("Voting System", function () {
    it("Should allow voting on proposals", async function () {
      const deployment = await deployDiamond();
      const governanceFacet = await ethers.getContractAt("GovernanceFacet", await deployment.diamond.getAddress());

      // Setup financier
      await setupFinancier(deployment.diamond, deployment.mockUSDC, deployment.owner);

      await governanceFacet.connect(deployment.owner).createProposal(
        "VOTE-TEST-001",
        "FINANCIAL",
        "Voting Test Proposal",
        "Test proposal for voting functionality"
      );

      await expect(
        governanceFacet.connect(deployment.owner).voteOnProposal("VOTE-TEST-001", true)
      ).to.emit(governanceFacet, "ProposalVoteCast");
    });

    it("Should not allow voting twice", async function () {
      const deployment = await deployDiamond();
      const governanceFacet = await ethers.getContractAt("GovernanceFacet", await deployment.diamond.getAddress());

      // Setup two financiers so voting power is split and first vote doesn't auto-pass
      await setupFinancier(deployment.diamond, deployment.mockUSDC, deployment.owner);
      await setupFinancier(deployment.diamond, deployment.mockUSDC, deployment.addr1);

      await governanceFacet.connect(deployment.owner).createProposal(
        "VOTE-TEST-001",
        "FINANCIAL",
        "Voting Test Proposal",
        "Test proposal for voting functionality"
      );

      // First vote from owner (50% voting power)
      await governanceFacet.connect(deployment.owner).voteOnProposal("VOTE-TEST-001", true);

      // Try to vote again from same address
      await expect(
        governanceFacet.connect(deployment.owner).voteOnProposal("VOTE-TEST-001", false)
      ).to.be.revertedWithCustomError(governanceFacet, "AlreadyVoted");
    });

    it("Should not allow voting on non-existent proposal", async function () {
      const deployment = await deployDiamond();
      const governanceFacet = await ethers.getContractAt("GovernanceFacet", await deployment.diamond.getAddress());

      // Setup as financier first, otherwise NotFinancier error is thrown first
      await setupFinancier(deployment.diamond, deployment.mockUSDC, deployment.owner);

      await expect(
        governanceFacet.connect(deployment.owner).voteOnProposal("NON-EXISTENT", true)
      ).to.be.revertedWithCustomError(governanceFacet, "ProposalNotFound");
    });

    it("Should track vote counts", async function () {
      const deployment = await deployDiamond();
      const governanceFacet = await ethers.getContractAt("GovernanceFacet", await deployment.diamond.getAddress());

      // Setup financier
      await setupFinancier(deployment.diamond, deployment.mockUSDC, deployment.owner);

      // Setup another user as financier
      await setupFinancier(deployment.diamond, deployment.mockUSDC, deployment.addr1);

      await governanceFacet.connect(deployment.owner).createProposal(
        "VOTE-TEST-001",
        "FINANCIAL",
        "Voting Test Proposal",
        "Test proposal for voting functionality"
      );

      await governanceFacet.connect(deployment.owner).voteOnProposal("VOTE-TEST-001", true);
      await governanceFacet.connect(deployment.addr1).voteOnProposal("VOTE-TEST-001", false);

      const proposal = await governanceFacet.getProposal("VOTE-TEST-001");
      // Voting power is a percentage (0-1e6), with 2 equal financiers each has 500000
      // Total voting power should be 1e6 (100%) when both vote
      const expectedTotal = 1000000n; // 100% in 6 decimals
      expect(proposal.votesFor + proposal.votesAgainst).to.equal(expectedTotal);
    });

    it("Should handle voting after deadline", async function () {
      const deployment = await deployDiamond();
      const governanceFacet = await ethers.getContractAt("GovernanceFacet", await deployment.diamond.getAddress());

      // Setup financier
      await setupFinancier(deployment.diamond, deployment.mockUSDC, deployment.owner);

      await governanceFacet.connect(deployment.owner).createProposal(
        "VOTE-TEST-001",
        "FINANCIAL",
        "Voting Test Proposal",
        "Test proposal for voting functionality"
      );

      // Fast forward time past voting deadline
      await time.increase(8 * 24 * 60 * 60); // 8 days

      await expect(
        governanceFacet.connect(deployment.owner).voteOnProposal("VOTE-TEST-001", true)
      ).to.be.revertedWithCustomError(governanceFacet, "VotingPeriodEnded");
    });
  });

  /* // Financier Management functions don't exist in GovernanceFacet - they are in LiquidityPoolFacet
  describe("Financier Management", function () {
    it("Should allow adding financiers", async function () {
      const [owner, financier1] = await ethers.getSigners();

      const GovernanceFacet = await ethers.getContractFactory("GovernanceFacet");
      const governanceFacet = await GovernanceFacet.deploy();
      await governanceFacet.waitForDeployment();

      const financierAddress = await financier1.getAddress();
      
      await expect(
        governanceFacet.addFinancier(financierAddress)
      ).to.emit(governanceFacet, "FinancierAdded")
        .withArgs(financierAddress);
    });

    it("Should not allow adding zero address as financier", async function () {
      const GovernanceFacet = await ethers.getContractFactory("GovernanceFacet");
      const governanceFacet = await GovernanceFacet.deploy();
      await governanceFacet.waitForDeployment();

      await expect(
        governanceFacet.addFinancier(ethers.ZeroAddress)
      ).to.be.revertedWithCustomError(governanceFacet, "ZeroAddress");
    });

    it("Should allow removing financiers", async function () {
      const [owner, financier1] = await ethers.getSigners();

      const GovernanceFacet = await ethers.getContractFactory("GovernanceFacet");
      const governanceFacet = await GovernanceFacet.deploy();
      await governanceFacet.waitForDeployment();

      const financierAddress = await financier1.getAddress();
      
      await governanceFacet.addFinancier(financierAddress);
      
      await expect(
        governanceFacet.removeFinancier(financierAddress)
      ).to.emit(governanceFacet, "FinancierRemoved")
        .withArgs(financierAddress);
    });

    it("Should check if address is financier", async function () {
      const [owner, financier1, user1] = await ethers.getSigners();

      const GovernanceFacet = await ethers.getContractFactory("GovernanceFacet");
      const governanceFacet = await GovernanceFacet.deploy();
      await governanceFacet.waitForDeployment();

      const financierAddress = await financier1.getAddress();
      const userAddress = await user1.getAddress();
      
      await governanceFacet.addFinancier(financierAddress);
      
      expect(await governanceFacet.isFinancier(financierAddress)).to.be.true;
      expect(await governanceFacet.isFinancier(userAddress)).to.be.false;
    });

    it("Should not allow duplicate financier addition", async function () {
      const [owner, financier1] = await ethers.getSigners();

      const GovernanceFacet = await ethers.getContractFactory("GovernanceFacet");
      const governanceFacet = await GovernanceFacet.deploy();
      await governanceFacet.waitForDeployment();

      const financierAddress = await financier1.getAddress();
      
      await governanceFacet.addFinancier(financierAddress);
      
      await expect(
        governanceFacet.addFinancier(financierAddress)
      ).to.be.revertedWith("Already a financier");
    });
  });
  */ // End of commented Financier Management section

  describe("Access Control", function () {
    it("Should restrict owner-only functions", async function () {
      const [owner, user1, user2] = await ethers.getSigners();

      const GovernanceFacet = await ethers.getContractFactory("GovernanceFacet");
      const governanceFacet = await GovernanceFacet.deploy();
      await governanceFacet.waitForDeployment();

      await expect(
        governanceFacet.connect(user1).setVotingDuration(3600)
      ).to.be.reverted; // Owner-only function should revert when called by non-owner
    });

    it("Should restrict financier-only functions", async function () {
      const deployment = await deployDiamond();

      const liquidityPoolFacet = await ethers.getContractAt("LiquidityPoolFacet", await deployment.diamond.getAddress());

      // For now, we'll test that non-financier cannot perform certain actions
      expect(await liquidityPoolFacet.isFinancier(await deployment.addr1.getAddress())).to.be.false;
    });
  });

  describe("Edge Cases", function () {
    it("Should handle very long proposal IDs", async function () {
      const deployment = await deployDiamond();
      const governanceFacet = await ethers.getContractAt("GovernanceFacet", await deployment.diamond.getAddress());

      // Setup financier
      await setupFinancier(deployment.diamond, deployment.mockUSDC, deployment.owner);

      const longProposalId = "PROP-" + "A".repeat(50); // Reasonable length

      await expect(
        governanceFacet.connect(deployment.owner).createProposal(longProposalId, "FINANCIAL", "Title", "Description")
      ).to.not.be.reverted;
    });

    it("Should handle very long proposal titles and descriptions", async function () {
      const deployment = await deployDiamond();
      const governanceFacet = await ethers.getContractAt("GovernanceFacet", await deployment.diamond.getAddress());

      // Setup financier
      await setupFinancier(deployment.diamond, deployment.mockUSDC, deployment.owner);

      const longTitle = "Title " + "A".repeat(120); // Within 128 char limit
      const longDescription = "Description " + "B".repeat(1000); // Within 1024 char limit

      await expect(
        governanceFacet.connect(deployment.owner).createProposal("PROP-001", "FINANCIAL", longTitle, longDescription)
      ).to.not.be.reverted;
    });

    it("Should handle maximum voting duration", async function () {
      const deployment = await deployDiamond();
      const governanceFacet = await ethers.getContractAt("GovernanceFacet", await deployment.diamond.getAddress());

      const maxDuration = 30 * 24 * 60 * 60; // 30 days

      await expect(
        governanceFacet.connect(deployment.owner).setVotingDuration(maxDuration)
      ).to.not.be.reverted;
    });
  });

  describe("Fuzz Tests", function () {
    it("Should handle random valid proposal IDs", async function () {
      const deployment = await deployDiamond();
      const governanceFacet = await ethers.getContractAt("GovernanceFacet", await deployment.diamond.getAddress());

      // Setup financier
      await setupFinancier(deployment.diamond, deployment.mockUSDC, deployment.owner);

      for (let i = 0; i < 10; i++) {
        const randomId = `PROP-${Math.random().toString(36).substring(2, 15)}`;
        const randomTitle = `Title-${i}`;
        const randomDescription = `Description-${i}`;

        await expect(
          governanceFacet.connect(deployment.owner).createProposal(randomId, "FINANCIAL", randomTitle, randomDescription)
        ).to.not.be.reverted;
      }
    });

    it("Should handle random voting patterns", async function () {
      const deployment = await deployDiamond();
      const governanceFacet = await ethers.getContractAt("GovernanceFacet", await deployment.diamond.getAddress());

      // Setup multiple financiers
      await setupFinancier(deployment.diamond, deployment.mockUSDC, deployment.owner);
      await setupFinancier(deployment.diamond, deployment.mockUSDC, deployment.addr1);
      await setupFinancier(deployment.diamond, deployment.mockUSDC, deployment.addr2);

      await governanceFacet.connect(deployment.owner).createProposal("FUZZ-001", "FINANCIAL", "Fuzz Test", "Random voting test");

      // Random voting by different users
      const users = [deployment.owner, deployment.addr1, deployment.addr2];
      for (let i = 0; i < Math.min(3, users.length); i++) {
        const support = Math.random() > 0.5;

        await expect(
          governanceFacet.connect(users[i]).voteOnProposal("FUZZ-001", support)
        ).to.not.be.reverted;
      }
    });

    it("Should handle random threshold values", async function () {
      const deployment = await deployDiamond();
      const governanceFacet = await ethers.getContractAt("GovernanceFacet", await deployment.diamond.getAddress());

      for (let i = 0; i < 10; i++) {
        const randomThreshold = Math.floor(Math.random() * 100) + 1; // 1 to 100

        await expect(
          governanceFacet.connect(deployment.owner).setApprovalThreshold(randomThreshold)
        ).to.not.be.reverted;
      }
    });

    it("Should handle random durations within valid range", async function () {
      const deployment = await deployDiamond();
      const governanceFacet = await ethers.getContractAt("GovernanceFacet", await deployment.diamond.getAddress());

      for (let i = 0; i < 10; i++) {
        // Use a reasonable range that won't exceed contract limits
        const randomDuration = Math.floor(Math.random() * (30 * 24 * 60 * 60 - 1 * 24 * 60 * 60)) + (1 * 24 * 60 * 60); // 1 to 30 days

        await expect(
          governanceFacet.connect(deployment.owner).setVotingDuration(randomDuration)
        ).to.not.be.reverted;
      }
    });

    it("Should handle rapid consecutive operations", async function () {
      const deployment = await deployDiamond();
      const governanceFacet = await ethers.getContractAt("GovernanceFacet", await deployment.diamond.getAddress());

      // Setup financier
      await setupFinancier(deployment.diamond, deployment.mockUSDC, deployment.owner);

      // Rapid proposal creation
      const promises = [];
      for (let i = 0; i < 5; i++) {
        promises.push(
          governanceFacet.connect(deployment.owner).createProposal(`RAPID-${i}`, "FINANCIAL", `Title ${i}`, `Description ${i}`)
        );
      }

      await Promise.all(promises);

      // Verify all proposals were created
      for (let i = 0; i < 5; i++) {
        const proposal = await governanceFacet.getProposal(`RAPID-${i}`);
        expect(proposal.title).to.equal(`Title ${i}`);
      }
    });
  });
});