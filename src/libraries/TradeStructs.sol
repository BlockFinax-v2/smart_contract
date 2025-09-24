// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title TradeStructs
 * @dev Library containing all data structures for the BlockFinax Trade Platform
 */
library TradeStructs {
    // Enums
    enum ContractStatus {
        Draft,           // 0 - Initial contract creation
        PendingApproval, // 1 - Waiting for counterparty approval
        Negotiating,     // 2 - Contract under negotiation
        Rejected,        // 3 - Contract rejected by counterparty
        Active,          // 4 - Contract funded and active
        InTransit,       // 5 - Goods shipped
        Delivered,       // 6 - Goods delivered
        Completed,       // 7 - Transaction completed
        Disputed,        // 8 - Under dispute
        Cancelled,       // 9 - Contract cancelled
        Expired,         // 10 - Contract expired
        Archived         // 11 - Contract archived
    }
    
    enum DocumentType {
        Contract,
        Invoice,
        PackingList,
        BillOfLading,
        Certificate,
        Insurance,
        Customs,
        Other
    }
    
    enum InvoiceStatus {
        Draft,
        Sent,
        Accepted,
        Paid,
        Overdue,
        Cancelled
    }
    
    enum RiskLevel {
        Low,
        Medium,
        High,
        Critical
    }
    
    enum ShipmentStatus {
        Pending,
        Picked,
        InTransit,
        Delivered,
        Delayed,
        Lost
    }
    
    // Main Structures
    struct TradeContract {
        uint256 id;
        address seller;
        address buyer;
        string title;
        string description;
        uint256 totalValue;
        uint256 escrowAmount;
        uint256 creationTime;
        uint256 deliveryDeadline;
        uint256 paymentDeadline;
        ContractStatus status;
        string deliveryTerms;
        string paymentTerms;
        string productDetails;
        uint256 quantity;
        string unitOfMeasure;
        uint256 unitPrice;
        bool buyerApproval;
        bool sellerApproval;
        bool fundsReleased;
        uint256 riskScore;
        string currency;
        string originCountry;
        string destinationCountry;
    }
    
    struct Document {
        uint256 id;
        uint256 contractId;
        string name;
        string ipfsHash;
        DocumentType docType;
        address uploader;
        uint256 timestamp;
        bool isVerified;
        bool isRequired;
        string description;
        bytes32 checksum;
    }
    
    struct Invoice {
        uint256 id;
        uint256 contractId;
        address issuer;
        address recipient;
        uint256 amount;
        string currency;
        uint256 issueDate;
        uint256 dueDate;
        InvoiceStatus status;
        string description;
        uint256[] lineItems;
        uint256 taxAmount;
        uint256 discountAmount;
        string paymentInstructions;
        bool isPaid;
    }
    
    struct LineItem {
        string description;
        uint256 quantity;
        uint256 unitPrice;
        uint256 totalPrice;
        string itemCode;
    }
    
    struct Shipment {
        uint256 id;
        uint256 contractId;
        string trackingNumber;
        string carrier;
        address shipper;
        string originAddress;
        string destinationAddress;
        uint256 shipDate;
        uint256 estimatedDelivery;
        uint256 actualDelivery;
        ShipmentStatus status;
        string[] checkpoints;
        bool insuranceClaimed;
        uint256 insuranceAmount;
    }
    
    struct RiskAssessment {
        uint256 contractId;
        RiskLevel level;
        string[] riskFactors;
        uint256 score;
        string mitigation;
        uint256 assessmentDate;
        address assessor;
        bool requiresApproval;
    }
    
    struct Dispute {
        uint256 contractId;
        address initiator;
        string reason;
        uint256 timestamp;
        bool resolved;
        address winner;
        string resolution;
        uint256 evidenceCount;
    }
}
