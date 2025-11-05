// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../libraries/LibAppStorage.sol";
import "../libraries/LibDiamond.sol";

contract GovernanceFacet {
    using SafeERC20 for IERC20;

    event RequestCreated(string indexed requestId, address indexed buyer, address indexed seller, uint256 amount);
    event VoteCast(string indexed requestId, address indexed voter, bool support, uint256 votingPower);
    event RequestApproved(string indexed requestId);
    event RequestRejected(string indexed requestId);
    event FundsReleased(string indexed requestId, address indexed seller, uint256 amount);
    event Paused(address account);
    event Unpaused(address account);

    bool private _paused;

    modifier whenNotPaused() {
        require(!_paused, "Pausable: paused");
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == LibDiamond.contractOwner(), "Must be contract owner");
        _;
    }

    function pause() external onlyOwner {
        _paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external onlyOwner {
        _paused = false;
        emit Unpaused(msg.sender);
    }

    function paused() external view returns (bool) {
        return _paused;
    }

    /**
     * @notice Create trade finance request
     */
    function createRequest(
        string memory requestId,
        address seller,
        uint256 requestedAmount,
        string memory tradeDescription
    ) external whenNotPaused {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        
        require(bytes(requestId).length > 0, "Invalid request ID");
        require(seller != address(0), "Invalid seller");
        require(requestedAmount > 0, "Invalid amount");
        require(s.requests[requestId].createdAt == 0, "Request exists");
        
        s.requests[requestId] = LibAppStorage.TradeFinanceRequest({
            requestId: requestId,
            buyer: msg.sender,
            seller: seller,
            requestedAmount: requestedAmount,
            tradeDescription: tradeDescription,
            votesFor: 0,
            votesAgainst: 0,
            createdAt: block.timestamp,
            status: LibAppStorage.RequestStatus.Pending,
            fundsReleased: false
        });
        
        s.requestIds.push(requestId);
        s.totalRequests++;
        
        emit RequestCreated(requestId, msg.sender, seller, requestedAmount);
    }

    /**
     * @notice Vote on trade finance request
     */
    function vote(string memory requestId, bool support) external {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        
        require(s.requests[requestId].createdAt > 0, "Request not found");
        require(s.requests[requestId].status == LibAppStorage.RequestStatus.Pending, "Not pending");
        require(!s.hasVoted[requestId][msg.sender], "Already voted");
        
        // Verify voter is LP
        require(s.stakes[msg.sender].active && s.stakes[msg.sender].amount > 0, "Must be LP");
        
        s.hasVoted[requestId][msg.sender] = true;
        uint256 votingPower = s.stakes[msg.sender].votingPower;
        
        if (support) {
            s.requests[requestId].votesFor += votingPower;
        } else {
            s.requests[requestId].votesAgainst += votingPower;
        }
        
        emit VoteCast(requestId, msg.sender, support, votingPower);
        
        _checkVotingThreshold(requestId);
    }

    /**
     * @notice Release funds to seller
     */
    function releaseFunds(string memory requestId) external whenNotPaused {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        LibAppStorage.TradeFinanceRequest storage request = s.requests[requestId];
        
        require(request.status == LibAppStorage.RequestStatus.Approved, "Not approved");
        require(!request.fundsReleased, "Already released");
        require(msg.sender == request.buyer, "Not buyer");
        
        uint256 balance = IERC20(s.usdcToken).balanceOf(address(this));
        require(balance >= request.requestedAmount, "Insufficient liquidity");
        
        request.fundsReleased = true;
        request.status = LibAppStorage.RequestStatus.Funded;
        s.totalFunded += request.requestedAmount;
        
        IERC20(s.usdcToken).safeTransfer(request.seller, request.requestedAmount);
        
        emit FundsReleased(requestId, request.seller, request.requestedAmount);
    }

    /**
     * @notice Get request details
     */
    function getRequest(string memory requestId) external view returns (
        address buyer,
        address seller,
        uint256 requestedAmount,
        string memory tradeDescription,
        uint256 votesFor,
        uint256 votesAgainst,
        LibAppStorage.RequestStatus status,
        bool fundsReleased
    ) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        LibAppStorage.TradeFinanceRequest memory r = s.requests[requestId];
        return (r.buyer, r.seller, r.requestedAmount, r.tradeDescription, r.votesFor, r.votesAgainst, r.status, r.fundsReleased);
    }

    /**
     * @notice Get governance stats
     */
    function getGovernanceStats() external view returns (
        uint256 totalRequests,
        uint256 totalFunded,
        uint256 pendingRequests
    ) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        uint256 pending = 0;
        for (uint256 i = 0; i < s.requestIds.length; i++) {
            if (s.requests[s.requestIds[i]].status == LibAppStorage.RequestStatus.Pending) {
                pending++;
            }
        }
        return (s.totalRequests, s.totalFunded, pending);
    }

    /**
     * @notice Check voting threshold and update status
     */
    function _checkVotingThreshold(string memory requestId) internal {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        LibAppStorage.TradeFinanceRequest storage request = s.requests[requestId];
        
        uint256 totalVotes = request.votesFor + request.votesAgainst;
        if (totalVotes == 0) return;
        
        uint256 approvalPercentage = (request.votesFor * 100) / totalVotes;
        
        if (approvalPercentage >= s.approvalThreshold) {
            request.status = LibAppStorage.RequestStatus.Approved;
            emit RequestApproved(requestId);
        } else if (totalVotes >= 1e18) {
            uint256 rejectionPercentage = (request.votesAgainst * 100) / totalVotes;
            if (rejectionPercentage > (100 - s.approvalThreshold)) {
                request.status = LibAppStorage.RequestStatus.Rejected;
                emit RequestRejected(requestId);
            }
        }
    }
}
