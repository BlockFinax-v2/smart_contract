// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../libraries/TradeStructs.sol";
import "../BaseModule.sol";

/**
 * @title DisputeManagement
 * @dev Module for handling trade disputes and resolution
 */
contract DisputeManagement is BaseModule {
    
    // Storage
    mapping(uint256 => TradeStructs.Dispute) public disputes;
    mapping(uint256 => string[]) public disputeEvidence;
    mapping(uint256 => address[]) public disputeArbitrators;
    mapping(address => bool) public authorizedArbitrators;
    mapping(address => uint256) public arbitratorCaseCount;
    mapping(uint256 => uint256) public disputeVotes; // disputeId => votes for winner
    
    // Dispute settings
    uint256 public constant ARBITRATION_FEE = 0.01 ether;
    uint256 public constant EVIDENCE_SUBMISSION_PERIOD = 7 days;
    uint256 public constant ARBITRATION_PERIOD = 14 days;
    uint256 public maxArbitrators = 3;
    
    // Events
    event DisputeRaised(uint256 indexed contractId, address indexed initiator, string reason);
    event DisputeResolved(uint256 indexed contractId, address indexed winner, string resolution);
    event EvidenceSubmitted(uint256 indexed contractId, address indexed submitter, string evidence);
    event ArbitratorAssigned(uint256 indexed contractId, address indexed arbitrator);
    event ArbitrationVote(uint256 indexed contractId, address indexed arbitrator, address winner);
    event ArbitratorAdded(address indexed arbitrator);
    event ArbitratorRemoved(address indexed arbitrator);
    
    modifier onlyArbitrator() {
        require(authorizedArbitrators[msg.sender], "Not authorized arbitrator");
        _;
    }
    
    modifier disputeExists(uint256 contractId) {
        require(disputes[contractId].contractId != 0, "Dispute does not exist");
        _;
    }
    
    modifier disputeNotResolved(uint256 contractId) {
        require(!disputes[contractId].resolved, "Dispute already resolved");
        _;
    }
    
    /**
     * @dev Raise a dispute for a contract
     */
    function raiseDispute(
        uint256 contractId,
        address initiator,
        string calldata reason
    ) external whenNotPaused returns (bool) {
        require(contractId > 0, "Invalid contract ID");
        require(initiator != address(0), "Invalid initiator address");
        require(bytes(reason).length > 0, "Dispute reason required");
        require(disputes[contractId].contractId == 0, "Dispute already exists");
        
        disputes[contractId] = TradeStructs.Dispute({
            contractId: contractId,
            initiator: initiator,
            reason: reason,
            timestamp: block.timestamp,
            resolved: false,
            winner: address(0),
            resolution: "",
            evidenceCount: 0
        });
        
        // Assign arbitrators
        _assignArbitrators(contractId);
        
        emit DisputeRaised(contractId, initiator, reason);
        
        return true;
    }
    
    /**
     * @dev Submit evidence for a dispute
     */
    function submitEvidence(
        uint256 contractId,
        string calldata evidence
    ) external disputeExists(contractId) disputeNotResolved(contractId) {
        require(bytes(evidence).length > 0, "Evidence cannot be empty");
        require(
            block.timestamp <= disputes[contractId].timestamp + EVIDENCE_SUBMISSION_PERIOD,
            "Evidence submission period expired"
        );
        
        disputeEvidence[contractId].push(evidence);
        disputes[contractId].evidenceCount++;
        
        emit EvidenceSubmitted(contractId, msg.sender, evidence);
    }
    
    /**
     * @dev Arbitrator vote on dispute resolution
     */
    function submitArbitrationVote(
        uint256 contractId,
        address winner,
        string calldata reasoning
    ) external onlyArbitrator disputeExists(contractId) disputeNotResolved(contractId) {
        require(_isAssignedArbitrator(contractId, msg.sender), "Not assigned to this dispute");
        require(winner != address(0), "Invalid winner address");
        require(
            block.timestamp > disputes[contractId].timestamp + EVIDENCE_SUBMISSION_PERIOD,
            "Evidence submission period not ended"
        );
        require(
            block.timestamp <= disputes[contractId].timestamp + EVIDENCE_SUBMISSION_PERIOD + ARBITRATION_PERIOD,
            "Arbitration period expired"
        );
        
        // Record vote (simplified - in production, implement proper voting mechanism)
        disputeVotes[contractId]++;
        
        emit ArbitrationVote(contractId, msg.sender, winner);
        
        // Check if majority reached (simplified logic)
        if (disputeVotes[contractId] >= (disputeArbitrators[contractId].length / 2) + 1) {
            _resolveDispute(contractId, winner, reasoning);
        }
    }
    
    /**
     * @dev Resolve dispute manually (owner only)
     */
    function resolveDisputeManually(
        uint256 contractId,
        address winner,
        string calldata resolution
    ) external onlyOwner disputeExists(contractId) disputeNotResolved(contractId) {
        _resolveDispute(contractId, winner, resolution);
    }
    
    /**
     * @dev Internal function to resolve dispute
     */
    function _resolveDispute(
        uint256 contractId,
        address winner,
        string memory resolution
    ) internal {
        disputes[contractId].resolved = true;
        disputes[contractId].winner = winner;
        disputes[contractId].resolution = resolution;
        
        // Update arbitrator case counts
        address[] memory arbitrators = disputeArbitrators[contractId];
        for (uint256 i = 0; i < arbitrators.length; i++) {
            arbitratorCaseCount[arbitrators[i]]++;
        }
        
        emit DisputeResolved(contractId, winner, resolution);
    }
    
    /**
     * @dev Auto-resolve dispute after timeout
     */
    function autoResolveDisputeTimeout(uint256 contractId) external disputeExists(contractId) disputeNotResolved(contractId) {
        require(
            block.timestamp > disputes[contractId].timestamp + EVIDENCE_SUBMISSION_PERIOD + ARBITRATION_PERIOD + 1 days,
            "Timeout period not reached"
        );
        
        // Default resolution - return funds to buyer if no arbitration
        _resolveDispute(contractId, disputes[contractId].initiator, "Auto-resolved due to arbitration timeout");
    }
    
    /**
     * @dev Assign arbitrators to a dispute
     */
    function _assignArbitrators(uint256 contractId) internal {
        // Simple assignment logic - in production, implement more sophisticated selection
        address[] memory availableArbitrators = _getAvailableArbitrators();
        require(availableArbitrators.length >= 1, "No arbitrators available");
        
        uint256 arbitratorsToAssign = availableArbitrators.length < maxArbitrators ? 
            availableArbitrators.length : maxArbitrators;
        
        for (uint256 i = 0; i < arbitratorsToAssign; i++) {
            disputeArbitrators[contractId].push(availableArbitrators[i]);
            emit ArbitratorAssigned(contractId, availableArbitrators[i]);
        }
    }
    
    /**
     * @dev Get available arbitrators
     */
    function _getAvailableArbitrators() internal view returns (address[] memory) {
        // Simplified implementation - in production, implement proper arbitrator pool management
        address[] memory temp = new address[](10); // Max temp array
        uint256 count = 0;
        
        // This is a simplified approach - in production, maintain a proper arbitrator registry
        // For now, return first available arbitrators
        return temp;
    }
    
    /**
     * @dev Check if address is assigned arbitrator for dispute
     */
    function _isAssignedArbitrator(uint256 contractId, address arbitrator) internal view returns (bool) {
        address[] memory arbitrators = disputeArbitrators[contractId];
        for (uint256 i = 0; i < arbitrators.length; i++) {
            if (arbitrators[i] == arbitrator) {
                return true;
            }
        }
        return false;
    }
    
    /**
     * @dev Appeal dispute resolution
     */
    function appealDispute(
        uint256 contractId,
        string calldata appealReason
    ) external payable disputeExists(contractId) {
        require(disputes[contractId].resolved, "Dispute not resolved yet");
        require(msg.value >= ARBITRATION_FEE * 2, "Insufficient appeal fee"); // Double fee for appeals
        require(bytes(appealReason).length > 0, "Appeal reason required");
        require(
            block.timestamp <= disputes[contractId].timestamp + ARBITRATION_PERIOD + 7 days,
            "Appeal period expired"
        );
        
        // Reset dispute for re-arbitration
        disputes[contractId].resolved = false;
        disputes[contractId].winner = address(0);
        disputes[contractId].resolution = "";
        disputes[contractId].evidenceCount = 0;
        
        // Clear previous evidence and assign new arbitrators
        delete disputeEvidence[contractId];
        delete disputeArbitrators[contractId];
        disputeVotes[contractId] = 0;
        
        _assignArbitrators(contractId);
        
        // Add appeal reason as evidence
        disputeEvidence[contractId].push(string(abi.encodePacked("APPEAL: ", appealReason)));
        disputes[contractId].evidenceCount = 1;
        
        emit EvidenceSubmitted(contractId, msg.sender, appealReason);
    }
    
    // View functions
    function getDispute(uint256 contractId) external view returns (TradeStructs.Dispute memory) {
        require(disputes[contractId].contractId != 0, "Dispute does not exist");
        return disputes[contractId];
    }
    
    function getDisputeEvidence(uint256 contractId) external view returns (string[] memory) {
        return disputeEvidence[contractId];
    }
    
    function getDisputeArbitrators(uint256 contractId) external view returns (address[] memory) {
        return disputeArbitrators[contractId];
    }
    
    function getArbitratorStats(address arbitrator) external view returns (
        bool isAuthorized,
        uint256 casesHandled,
        uint256 currentCaseload
    ) {
        isAuthorized = authorizedArbitrators[arbitrator];
        casesHandled = arbitratorCaseCount[arbitrator];
        // Calculate current active cases (simplified)
        currentCaseload = 0; // Would need to track active cases in production
    }
    
    function isDisputeActive(uint256 contractId) external view returns (bool) {
        return disputes[contractId].contractId != 0 && !disputes[contractId].resolved;
    }
    
    function getDisputeStatus(uint256 contractId) external view returns (
        bool exists,
        bool resolved,
        address winner,
        uint256 evidenceCount,
        bool inArbitrationPeriod,
        bool canAppeal
    ) {
        TradeStructs.Dispute memory dispute = disputes[contractId];
        exists = dispute.contractId != 0;
        resolved = dispute.resolved;
        winner = dispute.winner;
        evidenceCount = dispute.evidenceCount;
        
        if (exists) {
            uint256 arbitrationStart = dispute.timestamp + EVIDENCE_SUBMISSION_PERIOD;
            uint256 arbitrationEnd = arbitrationStart + ARBITRATION_PERIOD;
            
            inArbitrationPeriod = block.timestamp >= arbitrationStart && block.timestamp <= arbitrationEnd;
            canAppeal = resolved && block.timestamp <= arbitrationEnd + 7 days;
        }
    }
    
    // Admin functions
    function addArbitrator(address arbitrator) external onlyOwner {
        require(arbitrator != address(0), "Invalid arbitrator address");
        require(!authorizedArbitrators[arbitrator], "Already authorized");
        
        authorizedArbitrators[arbitrator] = true;
        emit ArbitratorAdded(arbitrator);
    }
    
    function removeArbitrator(address arbitrator) external onlyOwner {
        require(authorizedArbitrators[arbitrator], "Not authorized arbitrator");
        
        authorizedArbitrators[arbitrator] = false;
        emit ArbitratorRemoved(arbitrator);
    }
    
    function setMaxArbitrators(uint256 _maxArbitrators) external onlyOwner {
        require(_maxArbitrators > 0 && _maxArbitrators <= 5, "Invalid arbitrator count");
        maxArbitrators = _maxArbitrators;
    }
    
    function withdrawArbitrationFees() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No fees to withdraw");
        
        (bool success, ) = payable(owner()).call{value: balance}("");
        require(success, "Withdrawal failed");
    }
}