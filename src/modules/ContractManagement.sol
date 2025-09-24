// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/utils/Counters.sol";
import "../libraries/TradeStructs.sol";
import "../BaseModule.sol";

/**
 * @title ContractManagement
 * @dev Module for managing trade contracts
 */
contract ContractManagement is BaseModule {
    using Counters for Counters.Counter;
    
    Counters.Counter private _contractIds;
    
    // Storage
    mapping(uint256 => TradeStructs.TradeContract) public contracts;
    mapping(address => uint256[]) public userContracts;
    
    // Events
    event ContractCreated(uint256 indexed contractId, address indexed seller, address indexed buyer, uint256 value);
    event ContractApproved(uint256 indexed contractId, address indexed approver);
    event ContractRejected(uint256 indexed contractId, address indexed rejector, string reason);
    event ContractNegotiationStarted(uint256 indexed contractId, address indexed proposer);
    event ContractTermsProposed(uint256 indexed contractId, address indexed proposer, string proposalHash);
    event ContractFunded(uint256 indexed contractId, uint256 amount);
    event ContractStatusChanged(uint256 indexed contractId, TradeStructs.ContractStatus status);
    event FundsReleased(uint256 indexed contractId, uint256 amount);
    event ContractArchived(uint256 indexed contractId);

    // Configuration
    uint256 public minContractValue = 100;
    uint256 public maxContractDuration = 365 days;
    uint256 public platformFeeRate = 250; // 2.5% in basis points
    address public feeRecipient;
    
    constructor(address _feeRecipient) {
        feeRecipient = _feeRecipient;
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
    ) external onlyVerifiedUser returns (uint256) {
        require(_buyer != address(0), "Invalid buyer address");
        require(_buyer != msg.sender, "Seller cannot be buyer");
        require(_totalValue >= minContractValue, "Contract value below minimum");
        require(_deliveryDeadline > block.timestamp, "Invalid delivery deadline");
        require(_paymentDeadline > _deliveryDeadline, "Payment deadline must be after delivery");
        require(_isCountrySupported(_originCountry), "Origin country not supported");
        require(_isCountrySupported(_destinationCountry), "Destination country not supported");
        require(_isCurrencySupported(_currency), "Currency not supported");
        require(_isUserVerified(_buyer), "Buyer not verified");
        
        _contractIds.increment();
        uint256 contractId = _contractIds.current();
        
        contracts[contractId] = TradeStructs.TradeContract({
            id: contractId,
            seller: msg.sender,
            buyer: _buyer,
            title: _title,
            description: _description,
            totalValue: _totalValue,
            escrowAmount: 0,
            creationTime: block.timestamp,
            deliveryDeadline: _deliveryDeadline,
            paymentDeadline: _paymentDeadline,
            status: TradeStructs.ContractStatus.PendingApproval,
            deliveryTerms: _deliveryTerms,
            paymentTerms: _paymentTerms,
            productDetails: _productDetails,
            quantity: _quantity,
            unitOfMeasure: _unitOfMeasure,
            unitPrice: _unitPrice,
            buyerApproval: false,
            sellerApproval: true,
            fundsReleased: false,
            riskScore: 0,
            currency: _currency,
            originCountry: _originCountry,
            destinationCountry: _destinationCountry
        });
        
        userContracts[msg.sender].push(contractId);
        userContracts[_buyer].push(contractId);
        
        emit ContractCreated(contractId, msg.sender, _buyer, _totalValue);
        
        return contractId;
    }
    
    /**
     * @dev Approve contract (buyer approval)
     */
    function approveContract(uint256 contractId) external 
        contractExists(contractId) 
        validContractStatus(contractId, TradeStructs.ContractStatus.PendingApproval) 
        onlyContractParties(contractId) 
    {
        TradeStructs.TradeContract storage tradeContract = contracts[contractId];
        require(msg.sender == tradeContract.buyer, "Only buyer can approve");
        
        tradeContract.buyerApproval = true;
        tradeContract.status = TradeStructs.ContractStatus.Active;
        
        emit ContractApproved(contractId, msg.sender);
        emit ContractStatusChanged(contractId, TradeStructs.ContractStatus.Active);
    }
    
    /**
     * @dev Reject contract
     */
    function rejectContract(uint256 contractId, string calldata reason) external 
        contractExists(contractId) 
        validContractStatus(contractId, TradeStructs.ContractStatus.PendingApproval) 
        onlyContractParties(contractId) 
    {
        TradeStructs.TradeContract storage tradeContract = contracts[contractId];
        require(msg.sender == tradeContract.buyer, "Only buyer can reject");
        
        tradeContract.status = TradeStructs.ContractStatus.Rejected;
        
        emit ContractRejected(contractId, msg.sender, reason);
        emit ContractStatusChanged(contractId, TradeStructs.ContractStatus.Rejected);
    }
    
    /**
     * @dev Propose contract changes (start negotiation)
     */
    function proposeContractChanges(
        uint256 contractId,
        string calldata proposalIpfsHash
    ) external 
        contractExists(contractId) 
        onlyContractParties(contractId) 
    {
        TradeStructs.TradeContract storage tradeContract = contracts[contractId];
        require(
            tradeContract.status == TradeStructs.ContractStatus.PendingApproval ||
            tradeContract.status == TradeStructs.ContractStatus.Negotiating,
            "Contract not in negotiable state"
        );
        require(bytes(proposalIpfsHash).length > 0, "Proposal hash required");
        
        tradeContract.status = TradeStructs.ContractStatus.Negotiating;
        
        emit ContractNegotiationStarted(contractId, msg.sender);
        emit ContractTermsProposed(contractId, msg.sender, proposalIpfsHash);
        emit ContractStatusChanged(contractId, TradeStructs.ContractStatus.Negotiating);
    }
    
    /**
     * @dev Accept proposed changes and finalize contract
     */
    function acceptProposedChanges(uint256 contractId) external 
        contractExists(contractId) 
        validContractStatus(contractId, TradeStructs.ContractStatus.Negotiating) 
        onlyContractParties(contractId) 
    {
        TradeStructs.TradeContract storage tradeContract = contracts[contractId];
        
        // Only the other party can accept changes
        bool canAccept = (msg.sender == tradeContract.buyer && tradeContract.sellerApproval) ||
                        (msg.sender == tradeContract.seller && tradeContract.buyerApproval);
        require(canAccept, "Not authorized to accept changes");
        
        tradeContract.status = TradeStructs.ContractStatus.Active;
        tradeContract.buyerApproval = true;
        tradeContract.sellerApproval = true;
        
        emit ContractApproved(contractId, msg.sender);
        emit ContractStatusChanged(contractId, TradeStructs.ContractStatus.Active);
    }
    
    /**
     * @dev Fund escrow for approved contract
     */
    function fundEscrow(uint256 contractId) external payable 
        contractExists(contractId) 
        validContractStatus(contractId, TradeStructs.ContractStatus.Active) 
        nonReentrant 
    {
        TradeStructs.TradeContract storage tradeContract = contracts[contractId];
        require(msg.sender == tradeContract.buyer, "Only buyer can fund escrow");
        require(tradeContract.buyerApproval, "Contract not approved by buyer");
        require(tradeContract.escrowAmount == 0, "Escrow already funded");
        require(msg.value == tradeContract.totalValue, "Incorrect escrow amount");
        
        tradeContract.escrowAmount = msg.value;
        
        emit ContractFunded(contractId, msg.value);
    }
    
    /**
     * @dev Confirm delivery and release funds
     */
    function confirmDelivery(uint256 contractId) external 
        contractExists(contractId) 
        validContractStatus(contractId, TradeStructs.ContractStatus.Delivered) 
    {
        require(msg.sender == contracts[contractId].buyer, "Only buyer can confirm delivery");
        
        contracts[contractId].status = TradeStructs.ContractStatus.Completed;
        emit ContractStatusChanged(contractId, TradeStructs.ContractStatus.Completed);
        
        _releaseFunds(contractId);
    }
    
    /**
     * @dev Emergency release after deadline
     */
    function emergencyRelease(uint256 contractId) external contractExists(contractId) {
        TradeStructs.TradeContract storage tradeContract = contracts[contractId];
        require(msg.sender == tradeContract.seller, "Only seller can request emergency release");
        require(
            block.timestamp > tradeContract.paymentDeadline + 7 days,
            "Emergency release not yet available"
        );
        require(
            tradeContract.status == TradeStructs.ContractStatus.Delivered ||
            tradeContract.status == TradeStructs.ContractStatus.InTransit,
            "Invalid status for emergency release"
        );
        require(!tradeContract.fundsReleased, "Funds already released");
        
        tradeContract.status = TradeStructs.ContractStatus.Completed;
        _releaseFunds(contractId);
    }
    
    /**
     * @dev Internal function to release funds
     */
    function _releaseFunds(uint256 contractId) internal {
        TradeStructs.TradeContract storage tradeContract = contracts[contractId];
        require(!tradeContract.fundsReleased, "Funds already released");
        require(tradeContract.escrowAmount > 0, "No funds in escrow");
        
        uint256 platformFee = (tradeContract.escrowAmount * platformFeeRate) / 10000;
        uint256 sellerAmount = tradeContract.escrowAmount - platformFee;
        
        tradeContract.fundsReleased = true;
        
        (bool success1, ) = payable(tradeContract.seller).call{value: sellerAmount}("");
        require(success1, "Transfer to seller failed");
        
        (bool success2, ) = payable(feeRecipient).call{value: platformFee}("");
        require(success2, "Fee transfer failed");
        
        emit FundsReleased(contractId, sellerAmount);
        
        // Auto-archive completed contracts
        _archiveContract(contractId);
    }
    
    /**
     * @dev Archive completed or rejected contracts
     */
    function archiveContract(uint256 contractId) external contractExists(contractId) onlyContractParties(contractId) {
        TradeStructs.TradeContract storage tradeContract = contracts[contractId];
        require(
            tradeContract.status == TradeStructs.ContractStatus.Completed ||
            tradeContract.status == TradeStructs.ContractStatus.Rejected ||
            tradeContract.status == TradeStructs.ContractStatus.Cancelled,
            "Contract not in archivable state"
        );
        
        _archiveContract(contractId);
    }
    
    /**
     * @dev Internal function to archive contract
     */
    function _archiveContract(uint256 contractId) internal {
        contracts[contractId].status = TradeStructs.ContractStatus.Archived;
        emit ContractArchived(contractId);
        emit ContractStatusChanged(contractId, TradeStructs.ContractStatus.Archived);
    }
    
    // View functions
    function getContract(uint256 contractId) external view returns (
        address seller,
        address buyer,
        uint256 totalValue,
        TradeStructs.ContractStatus status
    ) {
        TradeStructs.TradeContract memory _contract = contracts[contractId];
        return (
            _contract.seller,
            _contract.buyer,
            _contract.totalValue,
            _contract.status
        );
    }
    
    function getUserContracts(address user) external view returns (uint256[] memory) {
        return userContracts[user];
    }
    
    function getContractDetails(uint256 contractId) external view returns (TradeStructs.TradeContract memory) {
        return contracts[contractId];
    }
    
    // Modifiers
    modifier contractExists(uint256 contractId) {
        require(contractId > 0 && contractId <= _contractIds.current(), "Contract does not exist");
        _;
    }
    
    modifier onlyContractParties(uint256 contractId) {
        require(
            msg.sender == contracts[contractId].seller || 
            msg.sender == contracts[contractId].buyer,
            "Not authorized: must be contract party"
        );
        _;
    }
    
    modifier validContractStatus(uint256 contractId, TradeStructs.ContractStatus expectedStatus) {
        require(contracts[contractId].status == expectedStatus, "Invalid contract status");
        _;
    }
    
    modifier validContractStatuses(uint256 contractId, TradeStructs.ContractStatus[] memory allowedStatuses) {
        bool validStatus = false;
        for (uint i = 0; i < allowedStatuses.length; i++) {
            if (contracts[contractId].status == allowedStatuses[i]) {
                validStatus = true;
                break;
            }
        }
        require(validStatus, "Invalid contract status");
        _;
    }
    
    /**
     * @dev Generate reference ID for contract (combination of timestamp and contract ID)
     */
    function generateReferenceId(uint256 contractId) external view returns (string memory) {
        require(contractId > 0 && contractId <= _contractIds.current(), "Invalid contract ID");
        TradeStructs.TradeContract memory _contract = contracts[contractId];
        
        return string(abi.encodePacked(
            "BFX-",
            _toString(_contract.creationTime),
            "-",
            _toString(contractId)
        ));
    }
    
    /**
     * @dev Convert uint to string
     */
    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        
        return string(buffer);
    }
    
    // Admin functions
    function updateFeeRate(uint256 newRate) external onlyOwner {
        require(newRate <= 1000, "Fee rate too high"); // Max 10%
        platformFeeRate = newRate;
    }
    
    function updateMinContractValue(uint256 newValue) external onlyOwner {
        minContractValue = newValue;
    }
}