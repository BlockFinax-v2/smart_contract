// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library LibAppStorage {
    bytes32 constant APP_STORAGE_POSITION = keccak256("blockfinax.app.storage");

    struct Stake {
        uint256 amount;
        uint256 timestamp;
        uint256 votingPower;
        bool active;
        address stakingToken; // Token being staked
        uint256 usdEquivalent; // USD value at stake time
        uint256 deadline; // Custom deadline set by staker
        uint256 lastRewardTimestamp;
        uint256 pendingRewards;
        uint256 rewardDebt;
        bool isFinancier; // Whether user applied as financier
        uint256 revocationRequestTime; // When revocation was requested
        bool revocationRequested; // Whether revocation is pending
    }

    struct Proposal {
        string proposalId;
        address proposer;
        string category; // Treasury, Investment, Guarantee, etc.
        string title;
        string description;
        uint256 votesFor;
        uint256 votesAgainst;
        uint256 createdAt;
        uint256 votingDeadline;
        ProposalStatus status;
        bool executed;
    }

    enum ProposalStatus {
        None, // 0 - Default/uninitialized state (security best practice)
        Active, // 1 - Proposal is open for voting
        Passed, // 2 - Proposal passed voting threshold
        Failed, // 3 - Proposal failed voting threshold
        Executed, // 4 - Proposal has been executed
        Cancelled // 5 - Proposal was cancelled
    }

    struct TradeFinanceRequest {
        string requestId;
        address buyer;
        address seller;
        uint256 requestedAmount;
        string tradeDescription;
        uint256 votesFor;
        uint256 votesAgainst;
        uint256 createdAt;
        RequestStatus status;
        bool fundsReleased;
    }

    enum RequestStatus {
        None, // 0 - Default/uninitialized state
        Pending, // 1 - Request awaiting review
        Approved, // 2 - Request approved
        Rejected, // 3 - Request rejected
        Funded, // 4 - Request funded
        Completed // 5 - Request completed
    }

    // Pool Guarantee Application (PGA) Structure
    struct PoolGuaranteeApplication {
        string pgaId;
        address buyer;
        address seller;
        uint256 tradeValue;
        uint256 guaranteeAmount;
        uint256 collateralAmount; // 10% or specified percentage
        uint256 duration; // in days
        uint256 votesFor;
        uint256 votesAgainst;
        uint256 createdAt;
        uint256 votingDeadline;
        PGAStatus status;
        bool collateralPaid;
        bool issuanceFeePaid;
        bool balancePaymentPaid;
        bool goodsShipped;
        string logisticPartner;
        uint256 certificateIssuedAt;
        string deliveryAgreementId;
        string metadataURI; // IPFS hash containing company details, contacts, description, etc.
        string[] uploadedDocuments; // IPFS hashes or URIs
        string companyName;
        string registrationNumber;
        string tradeDescription;
        string beneficiaryName;
        address beneficiaryWallet;
    }

    enum PGAStatus {
        None, // 0 - Default/uninitialized state (security)
        Created, // 1 - PGA created, awaiting financier votes
        GuaranteeApproved, // 2 - Financiers approved, awaiting seller approval
        SellerApproved, // 3 - Seller approved, awaiting collateral payment
        CollateralPaid, // 4 - Collateral paid, awaiting goods shipment
        GoodsShipped, // 5 - Goods shipped by logistics partner
        BalancePaymentPaid, // 6 - Balance payment made, ready for certificate
        CertificateIssued, // 7 - Certificate issued to buyer
        DeliveryAwaitingConsent, // 8 - Delivery agreement created, awaiting buyer consent
        Completed, // 9 - Delivery confirmed, PGA completed
        Rejected, // 10 - Rejected by financiers or seller
        Expired, // 11 - Deadline expired without completion
        Disputed // 12 - Delivery disputed by buyer
    }

    struct DeliveryAgreement {
        string agreementId;
        string pgaId;
        address deliveryPerson;
        address buyer;
        uint256 createdAt;
        uint256 deadline;
        bool buyerConsent;
        uint256 buyerSignedAt;
        string deliveryNotes;
        string deliveryProofURI; // IPFS hash or document URI
    }

    struct Milestone {
        string title;
        string description;
        uint256 amount;
        uint256 dueDate;
        MilestoneStatus status;
        bool released;
    }

    enum MilestoneStatus {
        None, // 0 - Default/uninitialized state
        Pending, // 1 - Milestone not yet completed
        Completed, // 2 - Milestone completed, awaiting release
        Released // 3 - Funds released for milestone
    }

    struct Escrow {
        uint256 id;
        address importer;
        address exporter;
        address arbitrator;
        uint256 totalAmount;
        uint256 releasedAmount;
        uint256 arbitratorFee;
        uint256 deadline;
        address tokenAddress;
        EscrowStatus status;
        DisputeStatus disputeStatus;
        string description;
        string termsHash;
        Milestone[] milestones;
        address[] subWallets;
        mapping(address => bool) isSubWallet;
        mapping(address => string) subWalletRole;
        mapping(address => string[]) subWalletPermissions;
    }

    enum EscrowStatus {
        None, // 0 - Default/uninitialized state
        Created, // 1 - Escrow created
        Funded, // 2 - Escrow funded
        InProgress, // 3 - Escrow in progress
        Completed, // 4 - Escrow completed successfully
        Disputed, // 5 - Escrow under dispute
        Refunded // 6 - Escrow refunded
    }
    enum DisputeStatus {
        None, // 0 - No dispute (default state is already safe)
        Raised, // 1 - Dispute raised
        InArbitration, // 2 - Under arbitration
        Resolved // 3 - Dispute resolved
    }

    struct Invoice {
        uint256 id;
        string invoiceNumber;
        address payer;
        address payee;
        uint256 amount;
        address tokenAddress;
        uint256 dueDate;
        InvoiceStatus status;
        uint256 paidAt;
        string description;
        string termsHash;
    }

    enum InvoiceStatus {
        None, // 0 - Default/uninitialized state
        Draft, // 1 - Invoice in draft state
        Sent, // 2 - Invoice sent to payer
        Viewed, // 3 - Invoice viewed by payer
        Paid, // 4 - Invoice paid
        Overdue, // 5 - Invoice overdue
        Cancelled // 6 - Invoice cancelled
    }

    struct DocumentRecord {
        bytes32 documentHash;
        string metadataURI; // IPFS CID or database reference
        address uploader;
        uint256 timestamp;
        DocumentType docType;
        uint256 linkedEscrowId; // 0 if not linked
        uint256 linkedInvoiceId; // 0 if not linked
        bool verified;
    }

    enum DocumentType {
        None, // 0 - Default/uninitialized state
        Contract, // 1 - Contract document
        Invoice, // 2 - Invoice document
        ProofOfDelivery, // 3 - Proof of delivery
        LegalDocument, // 4 - Legal document
        Specification, // 5 - Technical specification
        ComplianceCert, // 6 - Compliance certificate
        Other // 7 - Other document type
    }

    struct AppStorage {
        // Address Linking (AA Support) - EOA as primary identity
        mapping(address => address) smartAccountToEOA; // Smart Account -> EOA (primary identity)
        mapping(address => address) eoaToSmartAccount; // EOA -> Smart Account (reverse lookup)
        mapping(address => bool) isLinkedSmartAccount; // Quick check if address is a linked smart account
        // Liquidity Pool Storage
        address usdcToken;
        address[] supportedStakingTokens;
        mapping(address => bool) isStakingTokenSupported;
        mapping(address => uint256) totalStakedPerToken;
        mapping(address => mapping(address => Stake)) stakesPerToken;
        mapping(address => Stake) stakes;
        address[] stakers;
        uint256 totalStaked;
        uint256 totalLiquidityProviders;
        uint256 minimumStake;
        // Enhanced Staking Configuration
        uint256 initialApr;
        uint256 currentRewardRate;
        uint256 minLockDuration;
        uint256 aprReductionPerThousand;
        uint256 emergencyWithdrawPenalty;
        // Financier Configuration
        uint256 minimumFinancierStake;
        uint256 minFinancierLockDuration;
        uint256 minNormalStakerLockDuration;
        // DAO Governance Storage
        mapping(string => Proposal) proposals;
        mapping(string => mapping(address => bool)) hasVotedOnProposal;
        mapping(string => mapping(address => bool)) voterSupport; // track vote direction
        string[] proposalIds;
        uint256 totalProposals;
        uint256 votingDuration; // Default voting period
        uint256 proposalThreshold; // Min stake to create proposal
        // Legacy Governance Storage (keep for backward compatibility)
        mapping(string => TradeFinanceRequest) requests;
        mapping(string => mapping(address => bool)) hasVoted;
        string[] requestIds;
        uint256 totalRequests;
        uint256 totalFunded;
        uint256 approvalThreshold;
        // Pool Guarantee Application (PGA) Storage
        mapping(string => PoolGuaranteeApplication) pgas;
        mapping(string => mapping(address => bool)) hasVotedOnPGA;
        mapping(string => mapping(address => bool)) pgaVoterSupport;
        mapping(string => bool) sellerHasVoted; // Track if seller has voted on PGA
        string[] pgaIds;
        uint256 totalPGAs;
        uint256 totalActivePGAs;
        mapping(address => bool) authorizedLogisticsPartners;
        address[] logisticsPartnersList; // Track all logistics partners for enumeration
        mapping(address => bool) authorizedDeliveryPersons;
        address[] deliveryPersonsList; // Track all delivery persons for enumeration
        mapping(string => DeliveryAgreement) deliveryAgreements;
        mapping(string => string[]) pgaToDeliveryAgreements; // pgaId -> agreementIds
        // Escrow Storage
        mapping(uint256 => Escrow) escrows;
        uint256 escrowCounter;
        uint256 totalEscrows;
        uint256 activeEscrows;
        // Invoice Storage
        mapping(uint256 => Invoice) invoices;
        mapping(string => uint256) invoiceNumberToId;
        uint256 invoiceCounter;
        uint256 totalInvoices;
        // Document Storage
        mapping(bytes32 => DocumentRecord) documents; // hash -> document
        mapping(address => bytes32[]) userDocuments; // user -> their document hashes
        mapping(uint256 => bytes32[]) escrowDocuments; // escrow -> linked documents
        mapping(uint256 => bytes32[]) invoiceDocuments; // invoice -> linked documents
        uint256 totalDocuments;
        // DAO Multi-sig execution tracking
        mapping(string => mapping(address => bool)) proposalExecutionVotes; // proposalId -> financier -> voted
        mapping(string => uint256) proposalExecutionApprovals; // proposalId -> approval count
        uint256 revocationPeriod; // Time required before revocation (default 30 days)
        address blockFinaxTreasury; // Platform treasury for fee collection
    }

    function appStorage() internal pure returns (AppStorage storage s) {
        bytes32 position = APP_STORAGE_POSITION;
        assembly {
            s.slot := position
        }
    }
}
