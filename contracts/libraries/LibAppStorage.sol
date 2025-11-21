// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library LibAppStorage {
    bytes32 constant APP_STORAGE_POSITION = keccak256("blockfinax.app.storage");

    struct Stake {
        uint256 amount;
        uint256 timestamp;
        uint256 votingPower;
        bool active;
        uint256 lastRewardTimestamp;
        uint256 pendingRewards;
        uint256 rewardDebt;
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
        Pending,
        Approved,
        Rejected,
        Funded,
        Completed
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
        Pending,
        Completed,
        Released
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
        Created,
        Funded,
        InProgress,
        Completed,
        Disputed,
        Refunded
    }
    enum DisputeStatus {
        None,
        Raised,
        InArbitration,
        Resolved
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
        Draft,
        Sent,
        Viewed,
        Paid,
        Overdue,
        Cancelled
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
        Contract,
        Invoice,
        ProofOfDelivery,
        LegalDocument,
        Specification,
        ComplianceCert,
        Other
    }

    struct AppStorage {
        // Liquidity Pool Storage
        address usdcToken;
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
        // Governance Storage
        mapping(string => TradeFinanceRequest) requests;
        mapping(string => mapping(address => bool)) hasVoted;
        string[] requestIds;
        uint256 totalRequests;
        uint256 totalFunded;
        uint256 approvalThreshold;
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
    }

    function appStorage() internal pure returns (AppStorage storage s) {
        bytes32 position = APP_STORAGE_POSITION;
        assembly {
            s.slot := position
        }
    }
}
