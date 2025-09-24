// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./interfaces/IBlockFinaxTradePlatform.sol";
import "./modules/ContractManagement.sol";
import "./modules/DocumentManagement.sol";
import "./modules/InvoiceManagement.sol";
import "./modules/ShipmentManagement.sol";
import "./modules/RiskManagement.sol";
import "./modules/DisputeManagement.sol";
import "./libraries/TradeStructs.sol";

/**
 * @title BlockFinaxTradePlatform
 * @dev Main contract that orchestrates all trade platform modules
 * Comprehensive smart contract for AFCFTA international trade platform
 */
contract BlockFinaxTradePlatform is IBlockFinaxTradePlatform {
    
    // Module contracts
    ContractManagement public contractManagement;
    DocumentManagement public documentManagement;
    InvoiceManagement public invoiceManagement;
    ShipmentManagement public shipmentManagement;
    RiskManagement public riskManagement;
    DisputeManagement public disputeManagement;
    
    // Platform owner
    address public owner;
    bool public paused;
    
    // Events
    event ModuleUpgraded(string indexed moduleName, address indexed newAddress);
    event PlatformPaused();
    event PlatformUnpaused();
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }
    
    modifier whenNotPaused() {
        require(!paused, "Platform is paused");
        _;
    }
    
    constructor(address _feeRecipient) {
        owner = msg.sender;
        
        // Deploy and initialize modules
        contractManagement = new ContractManagement(_feeRecipient);
        documentManagement = new DocumentManagement();
        invoiceManagement = new InvoiceManagement();
        shipmentManagement = new ShipmentManagement();
        riskManagement = new RiskManagement();
        disputeManagement = new DisputeManagement();
    }
    
    /**
     * @dev Create a new trade contract
     */
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
    ) external override whenNotPaused returns (uint256) {
        // Create contract through contract management module
        uint256 contractId = contractManagement.createContract(
            _buyer,
            _title,
            _description,
            _totalValue,
            _deliveryDeadline,
            _paymentDeadline,
            _deliveryTerms,
            _paymentTerms,
            _productDetails,
            _quantity,
            _unitOfMeasure,
            _unitPrice,
            _currency,
            _originCountry,
            _destinationCountry
        );
        
        // Perform risk assessment
        riskManagement.assessContractRisk(
            contractId,
            _totalValue,
            _currency,
            _originCountry,
            _destinationCountry,
            _deliveryDeadline,
            block.timestamp,
            msg.sender,
            _buyer
        );
        
        return contractId;
    }
    
    /**
     * @dev Approve contract
     */
    function approveContract(uint256 contractId) external override whenNotPaused {
        contractManagement.approveContract(contractId);
    }
    
    /**
     * @dev Fund escrow for contract
     */
    function fundEscrow(uint256 contractId) external payable override whenNotPaused {
        // Check if high-risk contract requires manual approval
        if (riskManagement.requiresManualApproval(contractId)) {
            revert("High-risk contract requires manual approval before funding");
        }
        
        contractManagement.fundEscrow{value: msg.value}(contractId);
        
        // Contract status updates are handled by individual modules
        emit ContractFunded(contractId, msg.value);
    }
    
    /**
     * @dev Confirm delivery
     */
    function confirmDelivery(uint256 contractId) external override whenNotPaused {
        contractManagement.confirmDelivery(contractId);
    }
    
    /**
     * @dev Upload document
     */
    function uploadDocument(
        uint256 contractId,
        string calldata _name,
        string calldata _ipfsHash,
        TradeStructs.DocumentType _docType,
        bool _isRequired,
        string calldata _description,
        bytes32 _checksum
    ) external override whenNotPaused returns (uint256) {
        return documentManagement.uploadDocument(
            contractId,
            _name,
            _ipfsHash,
            _docType,
            _isRequired,
            _description,
            _checksum
        );
    }
    
    /**
     * @dev Create invoice
     */
    function createInvoice(
        uint256 contractId,
        uint256 _amount,
        string calldata _currency,
        uint256 _dueDate,
        string calldata _description,
        string calldata _paymentInstructions,
        uint256 _taxAmount,
        uint256 _discountAmount
    ) external override whenNotPaused returns (uint256) {
        return invoiceManagement.createInvoice(
            contractId,
            _amount,
            _currency,
            _dueDate,
            _description,
            _paymentInstructions,
            _taxAmount,
            _discountAmount
        );
    }
    
    /**
     * @dev Create shipment
     */
    function createShipment(
        uint256 contractId,
        string calldata _trackingNumber,
        string calldata _carrier,
        string calldata _originAddress,
        string calldata _destinationAddress,
        uint256 _estimatedDelivery,
        uint256 _insuranceAmount
    ) external override whenNotPaused returns (uint256) {
        uint256 shipmentId = shipmentManagement.createShipment(
            contractId,
            _trackingNumber,
            _carrier,
            _originAddress,
            _destinationAddress,
            _estimatedDelivery,
            _insuranceAmount
        );
        
        // Update contract status to InTransit
        // This would need to be coordinated between modules in production
        return shipmentId;
    }
    
    /**
     * @dev Update shipment status
     */
    function updateShipmentStatus(
        uint256 shipmentId,
        TradeStructs.ShipmentStatus _status,
        string calldata _checkpoint
    ) external override whenNotPaused {
        shipmentManagement.updateShipmentStatus(shipmentId, _status, _checkpoint);
        
        // If delivered, update contract status
        if (_status == TradeStructs.ShipmentStatus.Delivered) {
            // Get shipment details to find contract ID
            TradeStructs.Shipment memory shipment = shipmentManagement.getShipment(shipmentId);
            // Contract status update would be handled through module communication
        }
    }
    
    /**
     * @dev Raise dispute
     */
    function raiseDispute(uint256 contractId, string calldata _reason) external override whenNotPaused returns (uint256) {
        // Validate contract exists and caller is authorized
        (address seller, address buyer,,) = contractManagement.getContract(contractId);
        require(msg.sender == seller || msg.sender == buyer, "Not authorized to raise dispute");
        
        disputeManagement.raiseDispute(contractId, msg.sender, _reason);
        
        emit DisputeRaised(contractId, msg.sender);
        return contractId;
    }
    
    // View functions implementing interface
    function getContract(uint256 contractId) external view override returns (
        address seller,
        address buyer,
        uint256 totalValue,
        TradeStructs.ContractStatus status
    ) {
        return contractManagement.getContract(contractId);
    }
    
    function getUserContracts(address user) external view override returns (uint256[] memory) {
        return contractManagement.getUserContracts(user);
    }
    
    function getContractDocuments(uint256 contractId) external view override returns (uint256[] memory) {
        return documentManagement.getContractDocuments(contractId);
    }
    
    // Additional view functions
    function getContractDetails(uint256 contractId) external view returns (TradeStructs.TradeContract memory) {
        return contractManagement.getContractDetails(contractId);
    }
    
    function getDocument(uint256 documentId) external view returns (TradeStructs.Document memory) {
        return documentManagement.getDocument(documentId);
    }
    
    function getInvoice(uint256 invoiceId) external view returns (TradeStructs.Invoice memory) {
        return invoiceManagement.getInvoice(invoiceId);
    }
    
    function getShipment(uint256 shipmentId) external view returns (TradeStructs.Shipment memory) {
        return shipmentManagement.getShipment(shipmentId);
    }
    
    function getRiskAssessment(uint256 contractId) external view returns (TradeStructs.RiskAssessment memory) {
        return riskManagement.getRiskAssessment(contractId);
    }
    
    function getDispute(uint256 contractId) external view returns (TradeStructs.Dispute memory) {
        return disputeManagement.getDispute(contractId);
    }
    
    // Module management functions
    function upgradeModule(
        string calldata moduleName,
        address newModuleAddress
    ) external onlyOwner {
        require(newModuleAddress != address(0), "Invalid module address");
        
        if (_compareStrings(moduleName, "CONTRACT_MANAGEMENT")) {
            contractManagement = ContractManagement(newModuleAddress);
        } else if (_compareStrings(moduleName, "DOCUMENT_MANAGEMENT")) {
            documentManagement = DocumentManagement(newModuleAddress);
        } else if (_compareStrings(moduleName, "INVOICE_MANAGEMENT")) {
            invoiceManagement = InvoiceManagement(newModuleAddress);
        } else if (_compareStrings(moduleName, "SHIPMENT_MANAGEMENT")) {
            shipmentManagement = ShipmentManagement(newModuleAddress);
        } else if (_compareStrings(moduleName, "RISK_MANAGEMENT")) {
            riskManagement = RiskManagement(newModuleAddress);
        } else if (_compareStrings(moduleName, "DISPUTE_MANAGEMENT")) {
            disputeManagement = DisputeManagement(newModuleAddress);
        } else {
            revert("Unknown module name");
        }
        
        emit ModuleUpgraded(moduleName, newModuleAddress);
    }
    
    // Platform administration
    function verifyUser(address user) external onlyOwner {
        contractManagement.verifyUser(user);
        documentManagement.verifyUser(user);
        invoiceManagement.verifyUser(user);
        shipmentManagement.verifyUser(user);
        riskManagement.verifyUser(user);
        disputeManagement.verifyUser(user);
    }
    
    function addSupportedCountry(string calldata countryCode) external onlyOwner {
        contractManagement.addSupportedCountry(countryCode);
        documentManagement.addSupportedCountry(countryCode);
        invoiceManagement.addSupportedCountry(countryCode);
        shipmentManagement.addSupportedCountry(countryCode);
        riskManagement.addSupportedCountry(countryCode);
        disputeManagement.addSupportedCountry(countryCode);
    }
    
    function addSupportedCurrency(string calldata currency) external onlyOwner {
        contractManagement.addSupportedCurrency(currency);
        documentManagement.addSupportedCurrency(currency);
        invoiceManagement.addSupportedCurrency(currency);
        shipmentManagement.addSupportedCurrency(currency);
        riskManagement.addSupportedCurrency(currency);
        disputeManagement.addSupportedCurrency(currency);
    }
    
    function pausePlatform() external onlyOwner {
        paused = true;
        
        // Pause all modules
        contractManagement.pause();
        documentManagement.pause();
        invoiceManagement.pause();
        shipmentManagement.pause();
        riskManagement.pause();
        disputeManagement.pause();
        
        emit PlatformPaused();
    }
    
    function unpausePlatform() external onlyOwner {
        paused = false;
        
        // Unpause all modules
        contractManagement.unpause();
        documentManagement.unpause();
        invoiceManagement.unpause();
        shipmentManagement.unpause();
        riskManagement.unpause();
        disputeManagement.unpause();
        
        emit PlatformUnpaused();
    }
    
    // Utility functions
    function _compareStrings(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }
    
    // Platform info
    function getPlatformInfo() external view returns (
        address contractMgmt,
        address docMgmt,
        address invoiceMgmt,
        address shipmentMgmt,
        address riskMgmt,
        address disputeMgmt,
        bool isPaused
    ) {
        return (
            address(contractManagement),
            address(documentManagement),
            address(invoiceManagement),
            address(shipmentManagement),
            address(riskManagement),
            address(disputeManagement),
            paused
        );
    }
    
    // Emergency functions
    function emergencyWithdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No funds to withdraw");
        
        (bool success, ) = payable(owner).call{value: balance}("");
        require(success, "Emergency withdrawal failed");
    }
    
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Invalid new owner");
        owner = newOwner;
    }
    
    // Receive function to accept ETH
    receive() external payable {}
    
    // Fallback function
    fallback() external payable {}
}