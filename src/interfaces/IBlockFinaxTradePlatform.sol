// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../libraries/TradeStructs.sol";

/**
 * @title IBlockFinaxTradePlatform
 * @dev Interface for the BlockFinax Trade Platform
 */
interface IBlockFinaxTradePlatform {
    // Events
    event ContractCreated(uint256 indexed contractId, address indexed seller, address indexed buyer, uint256 value);
    event ContractApproved(uint256 indexed contractId, address indexed approver);
    event ContractFunded(uint256 indexed contractId, uint256 amount);
    event DocumentUploaded(uint256 indexed documentId, uint256 indexed contractId, TradeStructs.DocumentType docType);
    event DocumentVerified(uint256 indexed documentId, address indexed verifier);
    event InvoiceCreated(uint256 indexed invoiceId, uint256 indexed contractId, uint256 amount);
    event InvoicePaid(uint256 indexed invoiceId, uint256 amount);
    event ShipmentCreated(uint256 indexed shipmentId, uint256 indexed contractId, string trackingNumber);
    event ShipmentUpdated(uint256 indexed shipmentId, TradeStructs.ShipmentStatus status, string checkpoint);
    event RiskAssessed(uint256 indexed contractId, TradeStructs.RiskLevel level, uint256 score);
    event DisputeRaised(uint256 indexed contractId, address indexed initiator);
    event DisputeResolved(uint256 indexed contractId, address indexed winner);
    event FundsReleased(uint256 indexed contractId, uint256 amount);
    event ContractStatusChanged(uint256 indexed contractId, TradeStructs.ContractStatus status);
    event UserVerified(address indexed user);

    // Core contract functions
    function createContract(
        address _buyer,
        string calldata _title,
        string calldata _description,
        uint256 _totalValue,
        uint256 _deliveryDeadline,
        uint256 _paymentDeadline,
        string calldata _deliveryTerms,
        string calldata _paymentTerms,
        string calldata _productDetails,
        uint256 _quantity,
        string calldata _unitOfMeasure,
        uint256 _unitPrice,
        string calldata _currency,
        string calldata _originCountry,
        string calldata _destinationCountry
    ) external returns (uint256);

    function approveContract(uint256 contractId) external;
    function fundEscrow(uint256 contractId) external payable;
    function confirmDelivery(uint256 contractId) external;

    // Document management
    function uploadDocument(
        uint256 contractId,
        string calldata _name,
        string calldata _ipfsHash,
        TradeStructs.DocumentType _docType,
        bool _isRequired,
        string calldata _description,
        bytes32 _checksum
    ) external returns (uint256);

    // Invoice management
    function createInvoice(
        uint256 contractId,
        uint256 _amount,
        string calldata _currency,
        uint256 _dueDate,
        string calldata _description,
        string calldata _paymentInstructions,
        uint256 _taxAmount,
        uint256 _discountAmount
    ) external returns (uint256);

    // Shipment management
    function createShipment(
        uint256 contractId,
        string calldata _trackingNumber,
        string calldata _carrier,
        string calldata _originAddress,
        string calldata _destinationAddress,
        uint256 _estimatedDelivery,
        uint256 _insuranceAmount
    ) external returns (uint256);

    function updateShipmentStatus(
        uint256 shipmentId,
        TradeStructs.ShipmentStatus _status,
        string calldata _checkpoint
    ) external;

    // Dispute management
    function raiseDispute(uint256 contractId, string calldata _reason) external returns (uint256);

    // View functions
    function getContract(uint256 contractId) external view returns (
        address seller,
        address buyer,
        uint256 totalValue,
        TradeStructs.ContractStatus status
    );

    function getUserContracts(address user) external view returns (uint256[] memory);
    function getContractDocuments(uint256 contractId) external view returns (uint256[] memory);
}
