// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../libraries/LibDiamond.sol";

/**
 * @title ContractManagementFacet
 * @dev Facet for managing trade contracts with escrow and collateralization
 */
contract ContractManagementFacet {
    
    uint256 private _contractIdCounter;
    
    // Contract status enum
    enum ContractStatus {
        PendingApproval,
        Active,
        InTransit,
        Delivered,
        Completed,
        Cancelled,
        Rejected,
        Negotiating,
        Archived
    }
    
    // Trade contract structure
    struct TradeContract {
        uint256 id;
        address seller;
        address buyer;
        string title;
        string description;
        uint256 totalValue;
        uint256 escrowAmount;
        uint256 collateralAmount;
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
        uint256 discountRate; // Basis points for collateral discount
    }
    
    // Storage
    mapping(uint256 => TradeContract) public contracts;
    mapping(address => uint256[]) public userContracts;
    mapping(uint256 => mapping(address => uint256)) public collateralBalances; // contractId => user => amount
    mapping(address => bool) public verifiedUsers;
    mapping(string => bool) public supportedCountries;
    mapping(string => bool) public supportedCurrencies;
    
    // Storage for reentrancy guard  
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;
    
    // Storage for pausable functionality
    bool private _paused;
    
    // Events
    event ContractCreated(uint256 indexed contractId, address indexed seller, address indexed buyer, uint256 value);
    event ContractApproved(uint256 indexed contractId, address indexed approver);
    event ContractRejected(uint256 indexed contractId, address indexed rejector, string reason);
    event ContractNegotiationStarted(uint256 indexed contractId, address indexed proposer);
    event ContractTermsProposed(uint256 indexed contractId, address indexed proposer, string proposalHash);
    event ContractFunded(uint256 indexed contractId, uint256 amount);
    event ContractStatusChanged(uint256 indexed contractId, ContractStatus status);
    event FundsReleased(uint256 indexed contractId, uint256 amount);
    event ContractArchived(uint256 indexed contractId);
    event CollateralDeposited(uint256 indexed contractId, address indexed user, uint256 amount);
    event CollateralWithdrawn(uint256 indexed contractId, address indexed user, uint256 amount);
    event DiscountApplied(uint256 indexed contractId, uint256 discountAmount);
    
    // Events for pausable
    event Paused(address account);
    event Unpaused(address account);

    // Configuration
    uint256 public minContractValue = 100;
    uint256 public maxContractDuration = 365 days;
    uint256 public platformFeeRate = 250; // 2.5% in basis points
    uint256 public maxCollateralRate = 2000; // 20% in basis points
    address public feeRecipient;
    
    // Modifiers
    modifier onlyOwner() {
        LibDiamond.enforceIsContractOwner();
        _;
    }
    
    modifier onlyVerifiedUser() {
        require(verifiedUsers[msg.sender], "User not verified");
        _;
    }
    
    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
    
    modifier whenNotPaused() {
        require(!_paused, "Pausable: paused");
        _;
    }
    
    modifier whenPaused() {
        require(_paused, "Pausable: not paused");
        _;
    }
    
    modifier contractExists(uint256 contractId) {
        require(contractId > 0 && contractId <= _contractIdCounter, "Contract does not exist");
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
    
    modifier validContractStatus(uint256 contractId, ContractStatus expectedStatus) {
        require(contracts[contractId].status == expectedStatus, "Invalid contract status");
        _;
    }
    
    /**
     * @dev Initialize the contract management system
     */
    function initializeContractManagement() external onlyOwner {
        require(_status == 0, "Already initialized");
        _status = _NOT_ENTERED;
        _paused = false;
        
        feeRecipient = LibDiamond.contractOwner();
        
        // Initialize supported countries and currencies
        supportedCountries["US"] = true;
        supportedCountries["CN"] = true;
        supportedCountries["DE"] = true;
        supportedCountries["JP"] = true;
        supportedCountries["UK"] = true;
        
        supportedCurrencies["USD"] = true;
        supportedCurrencies["EUR"] = true;
        supportedCurrencies["CNY"] = true;
        supportedCurrencies["JPY"] = true;
        supportedCurrencies["GBP"] = true;
    }
    
    constructor() {
        // Empty constructor for facet
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
        require(supportedCountries[_originCountry], "Origin country not supported");
        require(supportedCountries[_destinationCountry], "Destination country not supported");
        require(supportedCurrencies[_currency], "Currency not supported");
        require(verifiedUsers[_buyer], "Buyer not verified");
        require(verifiedUsers[msg.sender], "Seller not verified");
        
        _contractIdCounter++;
        uint256 contractId = _contractIdCounter;
        
        contracts[contractId] = TradeContract({
            id: contractId,
            seller: msg.sender,
            buyer: _buyer,
            title: _title,
            description: _description,
            totalValue: _totalValue,
            escrowAmount: 0,
            collateralAmount: 0,
            creationTime: block.timestamp,
            deliveryDeadline: _deliveryDeadline,
            paymentDeadline: _paymentDeadline,
            status: ContractStatus.PendingApproval,
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
            destinationCountry: _destinationCountry,
            discountRate: 0
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
        validContractStatus(contractId, ContractStatus.PendingApproval) 
        onlyContractParties(contractId) 
    {
        TradeContract storage tradeContract = contracts[contractId];
        require(msg.sender == tradeContract.buyer, "Only buyer can approve");
        
        tradeContract.buyerApproval = true;
        tradeContract.status = ContractStatus.Active;
        
        emit ContractApproved(contractId, msg.sender);
        emit ContractStatusChanged(contractId, ContractStatus.Active);
    }
    
    /**
     * @dev Reject contract
     */
    function rejectContract(uint256 contractId, string calldata reason) external 
        contractExists(contractId) 
        validContractStatus(contractId, ContractStatus.PendingApproval) 
        onlyContractParties(contractId) 
    {
        TradeContract storage tradeContract = contracts[contractId];
        require(msg.sender == tradeContract.buyer, "Only buyer can reject");
        
        tradeContract.status = ContractStatus.Rejected;
        
        emit ContractRejected(contractId, msg.sender, reason);
        emit ContractStatusChanged(contractId, ContractStatus.Rejected);
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
        TradeContract storage tradeContract = contracts[contractId];
        require(
            tradeContract.status == ContractStatus.PendingApproval ||
            tradeContract.status == ContractStatus.Negotiating,
            "Contract not in negotiable state"
        );
        require(bytes(proposalIpfsHash).length > 0, "Proposal hash required");
        
        tradeContract.status = ContractStatus.Negotiating;
        
        emit ContractNegotiationStarted(contractId, msg.sender);
        emit ContractTermsProposed(contractId, msg.sender, proposalIpfsHash);
        emit ContractStatusChanged(contractId, ContractStatus.Negotiating);
    }
    
    /**
     * @dev Accept proposed changes and finalize contract
     */
    function acceptProposedChanges(uint256 contractId) external 
        contractExists(contractId) 
        validContractStatus(contractId, ContractStatus.Negotiating) 
        onlyContractParties(contractId) 
    {
        TradeContract storage tradeContract = contracts[contractId];
        
        // Only the other party can accept changes
        bool canAccept = (msg.sender == tradeContract.buyer && tradeContract.sellerApproval) ||
                        (msg.sender == tradeContract.seller && tradeContract.buyerApproval);
        require(canAccept, "Not authorized to accept changes");
        
        tradeContract.status = ContractStatus.Active;
        tradeContract.buyerApproval = true;
        tradeContract.sellerApproval = true;
        
        emit ContractApproved(contractId, msg.sender);
        emit ContractStatusChanged(contractId, ContractStatus.Active);
    }
    
    /**
     * @dev Deposit collateral for discount eligibility
     */
    function depositCollateral(uint256 contractId) external payable 
        contractExists(contractId) 
        onlyContractParties(contractId) 
        nonReentrant 
    {
        require(msg.value > 0, "Collateral amount must be greater than 0");
        TradeContract storage tradeContract = contracts[contractId];
        
        // // Only allow collateral deposits for active or pending contracts
        // require(
        //     tradeContract.status == ContractStatus.Pending || 
        //     tradeContract.status == ContractStatus.Active,
        //     "Cannot deposit collateral in current status"
        // );
        
        uint256 maxCollateral = (tradeContract.totalValue * maxCollateralRate) / 10000;
        require(
            collateralBalances[contractId][msg.sender] + msg.value <= maxCollateral,
            "Collateral exceeds maximum allowed"
        );
        
        collateralBalances[contractId][msg.sender] += msg.value;
        tradeContract.collateralAmount += msg.value;
        
        // Calculate discount rate based on collateral ratio with bounds checking
        uint256 collateralRatio = (tradeContract.collateralAmount * 10000) / tradeContract.totalValue;
        if (collateralRatio >= 1000) { // 10% collateral = 2% discount
            uint256 discountCalc = (collateralRatio * 20) / 100; // 0.2% per 1% collateral
            // Cap discount at 5% (500 basis points) to prevent overflow and excessive discounts
            tradeContract.discountRate = discountCalc > 500 ? 500 : discountCalc;
        }
        
        emit CollateralDeposited(contractId, msg.sender, msg.value);
    }
    
    /**
     * @dev Withdraw collateral after contract completion
     */
    function withdrawCollateral(uint256 contractId) external 
        contractExists(contractId) 
        nonReentrant 
    {
        require(
            contracts[contractId].status == ContractStatus.Completed ||
            contracts[contractId].status == ContractStatus.Cancelled ||
            contracts[contractId].status == ContractStatus.Rejected,
            "Contract not in withdrawable state"
        );
        
        uint256 amount = collateralBalances[contractId][msg.sender];
        require(amount > 0, "No collateral to withdraw");
        
        collateralBalances[contractId][msg.sender] = 0;
        contracts[contractId].collateralAmount -= amount;
        
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "Collateral withdrawal failed");
        
        emit CollateralWithdrawn(contractId, msg.sender, amount);
    }
    
    /**
     * @dev Fund escrow for approved contract with discount application
     */
    function fundEscrow(uint256 contractId) external payable 
        contractExists(contractId) 
        validContractStatus(contractId, ContractStatus.Active) 
        nonReentrant 
    {
        TradeContract storage tradeContract = contracts[contractId];
        require(msg.sender == tradeContract.buyer, "Only buyer can fund escrow");
        require(tradeContract.buyerApproval, "Contract not approved by buyer");
        require(tradeContract.escrowAmount == 0, "Escrow already funded");
        
        // Calculate discounted amount if collateral exists
        uint256 requiredAmount = tradeContract.totalValue;
        if (tradeContract.discountRate > 0) {
            uint256 discountAmount = (tradeContract.totalValue * tradeContract.discountRate) / 10000;
            requiredAmount = tradeContract.totalValue - discountAmount;
            emit DiscountApplied(contractId, discountAmount);
        }
        
        require(msg.value == requiredAmount, "Incorrect escrow amount");
        
        tradeContract.escrowAmount = msg.value;
        
        emit ContractFunded(contractId, msg.value);
    }
    
    /**
     * @dev Send payment directly (without escrow)
     */
    function sendPayment(uint256 contractId, address payable recipient) external payable 
        contractExists(contractId) 
        onlyContractParties(contractId) 
        nonReentrant 
    {
        require(msg.value > 0, "Payment amount must be greater than 0");
        require(recipient != address(0), "Invalid recipient");
        
        TradeContract storage tradeContract = contracts[contractId];
        require(tradeContract.status == ContractStatus.Active, "Contract not active");
        
        // Transfer payment
        (bool success, ) = recipient.call{value: msg.value}("");
        require(success, "Payment transfer failed");
        
        // Update contract status if this completes the payment
        if (msg.value >= tradeContract.totalValue) {
            tradeContract.status = ContractStatus.Completed;
            emit ContractStatusChanged(contractId, ContractStatus.Completed);
        }
    }
    
    /**
     * @dev Receive payment confirmation
     */
    function confirmPaymentReceived(uint256 contractId, uint256 amount) external 
        contractExists(contractId) 
        onlyContractParties(contractId) 
    {
        TradeContract storage tradeContract = contracts[contractId];
        require(tradeContract.status == ContractStatus.Active, "Contract not active");
        
        // Mark status as delivered if payment confirmed
        if (amount >= tradeContract.totalValue) {
            tradeContract.status = ContractStatus.Delivered;
            emit ContractStatusChanged(contractId, ContractStatus.Delivered);
        }
    }
    /**
     * @dev Confirm delivery and release funds
     */
    function confirmDelivery(uint256 contractId) external 
        contractExists(contractId) 
        validContractStatus(contractId, ContractStatus.Delivered) 
    {
        require(msg.sender == contracts[contractId].buyer, "Only buyer can confirm delivery");
        
        contracts[contractId].status = ContractStatus.Completed;
        emit ContractStatusChanged(contractId, ContractStatus.Completed);
        
        _releaseFunds(contractId);
    }
    
    /**
     * @dev Emergency release after deadline
     */
    function emergencyRelease(uint256 contractId) external contractExists(contractId) {
        TradeContract storage tradeContract = contracts[contractId];
        require(msg.sender == tradeContract.seller, "Only seller can request emergency release");
        require(
            block.timestamp > tradeContract.paymentDeadline + 7 days,
            "Emergency release not yet available"
        );
        require(
            tradeContract.status == ContractStatus.Delivered ||
            tradeContract.status == ContractStatus.InTransit,
            "Invalid status for emergency release"
        );
        require(!tradeContract.fundsReleased, "Funds already released");
        
        tradeContract.status = ContractStatus.Completed;
        _releaseFunds(contractId);
    }
    
    /**
     * @dev Internal function to release funds
     */
    function _releaseFunds(uint256 contractId) internal {
        TradeContract storage tradeContract = contracts[contractId];
        require(!tradeContract.fundsReleased, "Funds already released");
        require(tradeContract.escrowAmount > 0, "No funds in escrow");
        
        uint256 escrowAmount = tradeContract.escrowAmount;
        uint256 platformFee = (escrowAmount * platformFeeRate) / 10000;
        uint256 sellerAmount = escrowAmount - platformFee;
        
        // Update state BEFORE external calls (CEI pattern)
        tradeContract.fundsReleased = true;
        tradeContract.escrowAmount = 0; // Prevent re-release
        
        // External calls after state changes
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
        TradeContract storage tradeContract = contracts[contractId];
        require(
            tradeContract.status == ContractStatus.Completed ||
            tradeContract.status == ContractStatus.Rejected ||
            tradeContract.status == ContractStatus.Cancelled,
            "Contract not in archivable state"
        );
        
        _archiveContract(contractId);
    }
    
    /**
     * @dev Internal function to archive contract
     */
    function _archiveContract(uint256 contractId) internal {
        contracts[contractId].status = ContractStatus.Archived;
        emit ContractArchived(contractId);
        emit ContractStatusChanged(contractId, ContractStatus.Archived);
    }
    
    /**
     * @dev Verify user for trading
     */
    function verifyUser(address user) external onlyOwner {
        verifiedUsers[user] = true;
    }
    
    /**
     * @dev Revoke user verification
     */
    function revokeUserVerification(address user) external onlyOwner {
        verifiedUsers[user] = false;
    }
    
    /**
     * @dev Add supported country
     */
    function addSupportedCountry(string calldata countryCode) external onlyOwner {
        supportedCountries[countryCode] = true;
    }
    
    /**
     * @dev Add supported currency
     */
    function addSupportedCurrency(string calldata currencyCode) external onlyOwner {
        supportedCurrencies[currencyCode] = true;
    }
    
    // View functions
    function getContract(uint256 contractId) external view returns (
        address seller,
        address buyer,
        uint256 totalValue,
        ContractStatus status
    ) {
        TradeContract memory _contract = contracts[contractId];
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
    
    function getContractDetails(uint256 contractId) external view returns (TradeContract memory) {
        return contracts[contractId];
    }
    
    function getCollateralBalance(uint256 contractId, address user) external view returns (uint256) {
        return collateralBalances[contractId][user];
    }
    
    function isUserVerified(address user) external view returns (bool) {
        return verifiedUsers[user];
    }
    
    function isCountrySupported(string calldata countryCode) external view returns (bool) {
        return supportedCountries[countryCode];
    }
    
    function isCurrencySupported(string calldata currencyCode) external view returns (bool) {
        return supportedCurrencies[currencyCode];
    }
    
    // Modifiers (already defined above, but keeping for completeness)
    
    modifier validContractStatuses(uint256 contractId, ContractStatus[] memory allowedStatuses) {
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
        require(contractId > 0 && contractId <= _contractIdCounter, "Invalid contract ID");
        TradeContract memory _contract = contracts[contractId];
        
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
    
    function updateMaxCollateralRate(uint256 newRate) external onlyOwner {
        require(newRate <= 5000, "Max collateral rate too high"); // Max 50%
        maxCollateralRate = newRate;
    }
    
    function updateFeeRecipient(address newRecipient) external onlyOwner {
        require(newRecipient != address(0), "Invalid fee recipient");
        feeRecipient = newRecipient;
    }
    
    /**
     * @dev Pause the contract management system
     */
    function pauseContractManagement() external onlyOwner {
        _paused = true;
        emit Paused(msg.sender);
    }
    
    /**
     * @dev Unpause the contract management system
     */
    function unpauseContractManagement() external onlyOwner {
        _paused = false;
        emit Unpaused(msg.sender);
    }
    
    /**
     * @dev Check if contract management is paused
     */
    function isContractManagementPaused() external view returns (bool) {
        return _paused;
    }
}