// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../libraries/LibAppStorage.sol";
import "../libraries/LibDiamond.sol";
import "../libraries/LibPausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title GovernanceFacet
 * @notice DAO governance system for BlockFinax protocol
 * @dev Handles proposal creation, voting, and execution for protocol governance
 */
contract GovernanceFacet is ReentrancyGuard {
    // Custom Errors
    error ContractPaused();
    error NotAuthorized();
    error NotFinancier();
    error InsufficientStake();
    error InvalidProposalId();
    error InvalidCategory();
    error InvalidTitle();
    error InvalidDescription();
    error ProposalAlreadyExists();
    error ProposalNotFound();
    error ProposalNotActive();
    error ProposalNotPassed();
    error ProposalAlreadyExecuted();
    error VotingPeriodEnded();
    error VotingPeriodNotEnded();
    error AlreadyVoted();
    error InvalidDuration();
    error InvalidThreshold();
    error InvalidPenalty();
    error InvalidTokenAddress();
    error InvalidMinimumStake();
    error InvalidAPR();
    error NotAFinancier();
    error RevocationAlreadyRequested();
    error NoRevocationRequested();
    error RevocationPeriodNotCompleted();
    error ZeroAddress();
    error InvalidPercentage();
    // DAO Proposal Events
    event ProposalCreated(
        string indexed proposalId,
        string indexed category,
        string indexed title,
        address proposer,
        uint256 votingDeadline
    );
    event ProposalVoteCast(
        string indexed proposalId,
        address indexed voter,
        bool support,
        uint256 votingPower
    );
    event ProposalStatusChanged(
        string indexed proposalId,
        LibAppStorage.ProposalStatus status
    );
    event ProposalExecuted(string indexed proposalId, address executor);
    event ParameterUpdated(string indexed parameter, uint256 value);
    event FinancierRevocationRequested(
        address indexed financier,
        uint256 requestTime
    );
    event FinancierRevocationExecuted(
        address indexed financier,
        uint256 executionTime
    );
    event ProposalExecutionVoteCast(
        string indexed proposalId,
        address indexed financier
    );
    event Paused(address account);
    event Unpaused(address account);

    modifier whenNotPaused() {
        if (LibPausable.isPaused()) revert ContractPaused();
        _;
    }

    modifier onlyFinancier() {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        if (
            !s.stakes[msg.sender].active ||
            !s.stakes[msg.sender].isFinancier ||
            s.stakes[msg.sender].amount < s.minimumFinancierStake
        ) {
            revert NotFinancier();
        }
        _;
    }

    /**
     * @notice Pause the contract (owner only)
     * @dev Implements checks-effects-interactions pattern
     */
    function pause() external {
        LibPausable.pause();
        emit Paused(msg.sender);
    }

    /**
     * @notice Unpause the contract (owner only)
     * @dev Implements checks-effects-interactions pattern
     */
    function unpause() external {
        LibPausable.unpause();
        emit Unpaused(msg.sender);
    }

    function paused() external view returns (bool) {
        return LibPausable.isPaused();
    }

    /**
     * @notice Check if an address is a financier
     * @param account Address to check
     * @return bool True if address is a financier
     */
    function isFinancier(address account) external view returns (bool) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        return
            s.stakes[account].active &&
            s.stakes[account].isFinancier &&
            s.stakes[account].amount >= s.minimumFinancierStake;
    }

    /**
     * @notice Create DAO proposal
     */
    function createProposal(
        string calldata proposalId,
        string calldata category,
        string calldata title,
        string calldata description
    ) external whenNotPaused onlyFinancier nonReentrant {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        // Checks
        if (bytes(proposalId).length == 0) revert InvalidProposalId();
        if (bytes(proposalId).length > 64) revert InvalidProposalId(); // Reasonable limit
        if (bytes(category).length == 0) revert InvalidCategory();
        if (bytes(category).length > 32) revert InvalidCategory();
        if (bytes(title).length == 0) revert InvalidTitle();
        if (bytes(title).length > 128) revert InvalidTitle();
        if (bytes(description).length == 0) revert InvalidDescription();
        if (bytes(description).length > 1024) revert InvalidDescription(); // Reasonable limit
        if (s.proposals[proposalId].createdAt != 0)
            revert ProposalAlreadyExists();
        if (s.stakes[msg.sender].amount < s.proposalThreshold)
            revert InsufficientStake();

        // Effects
        uint256 votingDeadline = block.timestamp + s.votingDuration;

        s.proposals[proposalId] = LibAppStorage.Proposal({
            proposalId: proposalId,
            proposer: msg.sender,
            category: category,
            title: title,
            description: description,
            votesFor: 0,
            votesAgainst: 0,
            createdAt: block.timestamp,
            votingDeadline: votingDeadline,
            status: LibAppStorage.ProposalStatus.Active,
            executed: false
        });

        s.proposalIds.push(proposalId);
        unchecked {
            s.totalProposals++; // Safe from overflow in practical scenarios
        }

        // Interactions (events)
        emit ProposalCreated(
            proposalId,
            category,
            title,
            msg.sender,
            votingDeadline
        );
    }

    /**
     * @notice Vote on DAO proposal
     */
    function voteOnProposal(
        string calldata proposalId,
        bool support
    ) external onlyFinancier nonReentrant {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        LibAppStorage.Proposal storage proposal = s.proposals[proposalId];

        // Checks
        if (proposal.createdAt == 0) revert ProposalNotFound();
        if (proposal.status != LibAppStorage.ProposalStatus.Active)
            revert ProposalNotActive();
        if (block.timestamp > proposal.votingDeadline)
            revert VotingPeriodEnded();
        if (s.hasVotedOnProposal[proposalId][msg.sender]) revert AlreadyVoted();

        uint256 votingPower = s.stakes[msg.sender].votingPower;
        if (votingPower == 0) revert InsufficientStake();

        // Effects
        s.hasVotedOnProposal[proposalId][msg.sender] = true;
        s.voterSupport[proposalId][msg.sender] = support;

        if (support) {
            proposal.votesFor += votingPower;
        } else {
            proposal.votesAgainst += votingPower;
        }

        // Interactions (events)
        emit ProposalVoteCast(proposalId, msg.sender, support, votingPower);

        // Internal function call (safe)
        _checkProposalThreshold(proposalId);
    }

    /**
     * @notice Get proposal details
     */
    function getProposal(
        string memory proposalId
    )
        external
        view
        returns (
            address proposer,
            string memory category,
            string memory title,
            string memory description,
            uint256 votesFor,
            uint256 votesAgainst,
            uint256 createdAt,
            uint256 votingDeadline,
            LibAppStorage.ProposalStatus status,
            bool executed
        )
    {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        LibAppStorage.Proposal memory p = s.proposals[proposalId];
        return (
            p.proposer,
            p.category,
            p.title,
            p.description,
            p.votesFor,
            p.votesAgainst,
            p.createdAt,
            p.votingDeadline,
            p.status,
            p.executed
        );
    }

    /**
     * @notice Get all proposal IDs
     */
    function getAllProposals() external view returns (string[] memory) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        return s.proposalIds;
    }

    /**
     * @notice Get vote status for a proposal
     */
    function getVoteStatus(
        string memory proposalId,
        address voter
    ) external view returns (bool hasVoted, bool support) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        return (
            s.hasVotedOnProposal[proposalId][voter],
            s.voterSupport[proposalId][voter]
        );
    }

    /**
     * @notice Get active proposals
     */
    function getActiveProposals() external view returns (string[] memory) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        string[] memory activeProposals = new string[](s.proposalIds.length);
        uint256 activeCount = 0;

        for (uint256 i = 0; i < s.proposalIds.length; i++) {
            string memory proposalId = s.proposalIds[i];
            if (
                s.proposals[proposalId].status ==
                LibAppStorage.ProposalStatus.Active &&
                block.timestamp <= s.proposals[proposalId].votingDeadline
            ) {
                activeProposals[activeCount] = proposalId;
                activeCount++;
            }
        }

        // Resize array to actual active count
        string[] memory result = new string[](activeCount);
        for (uint256 i = 0; i < activeCount; i++) {
            result[i] = activeProposals[i];
        }

        return result;
    }

    /**
     * @notice Execute passed proposal (financier only)
     */
    function executeProposal(
        string calldata proposalId
    ) external onlyFinancier nonReentrant {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        LibAppStorage.Proposal storage proposal = s.proposals[proposalId];

        // Checks
        if (proposal.createdAt == 0) revert ProposalNotFound();
        if (proposal.status != LibAppStorage.ProposalStatus.Passed)
            revert ProposalNotPassed();
        if (proposal.executed) revert ProposalAlreadyExecuted();

        // Effects
        proposal.executed = true;
        proposal.status = LibAppStorage.ProposalStatus.Executed;

        // Interactions (events)
        emit ProposalExecuted(proposalId, msg.sender);
        emit ProposalStatusChanged(
            proposalId,
            LibAppStorage.ProposalStatus.Executed
        );
    }

    /**
     * @notice Get DAO governance stats
     */
    function getDAOStats()
        external
        view
        returns (
            uint256 totalProposals,
            uint256 activeProposals,
            uint256 passedProposals,
            uint256 executedProposals
        )
    {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        uint256 active = 0;
        uint256 passed = 0;
        uint256 executed = 0;

        for (uint256 i = 0; i < s.proposalIds.length; i++) {
            LibAppStorage.Proposal storage proposal = s.proposals[
                s.proposalIds[i]
            ];
            if (proposal.status == LibAppStorage.ProposalStatus.Active) {
                active++;
            } else if (proposal.status == LibAppStorage.ProposalStatus.Passed) {
                passed++;
            } else if (
                proposal.status == LibAppStorage.ProposalStatus.Executed
            ) {
                executed++;
            }
        }

        return (s.totalProposals, active, passed, executed);
    }

    /**
     * @notice Finalize vote time expired proposals
     */
    function finalizeVote(
        string calldata proposalId
    ) external onlyFinancier nonReentrant {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        LibAppStorage.Proposal storage proposal = s.proposals[proposalId];

        // Checks
        if (proposal.createdAt == 0) revert ProposalNotFound();
        if (proposal.status != LibAppStorage.ProposalStatus.Active)
            revert ProposalNotActive();
        if (block.timestamp <= proposal.votingDeadline)
            revert VotingPeriodNotEnded();

        uint256 totalVotes = proposal.votesFor + proposal.votesAgainst;

        if (totalVotes > 0) {
            uint256 approvalPercentage = (proposal.votesFor * 100) / totalVotes;

            if (approvalPercentage >= s.approvalThreshold) {
                proposal.status = LibAppStorage.ProposalStatus.Passed;
                emit ProposalStatusChanged(
                    proposalId,
                    LibAppStorage.ProposalStatus.Passed
                );
            } else {
                proposal.status = LibAppStorage.ProposalStatus.Failed;
                emit ProposalStatusChanged(
                    proposalId,
                    LibAppStorage.ProposalStatus.Failed
                );
            }
        } else {
            proposal.status = LibAppStorage.ProposalStatus.Failed;
            emit ProposalStatusChanged(
                proposalId,
                LibAppStorage.ProposalStatus.Failed
            );
        }
    }

    // ==================== GOVERNANCE SETTER FUNCTIONS ====================

    /**
     * @notice Set minimum stake amount for regular stakers (owner only)
     */
    function setMinimumStake(uint256 _minimumStake) external nonReentrant {
        LibDiamond.enforceIsContractOwner();
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        // Checks
        if (_minimumStake == 0) revert InvalidMinimumStake();
        if (_minimumStake > 1e30) revert InvalidMinimumStake(); // Reasonable upper bound

        // Effects
        s.minimumStake = _minimumStake;

        // Interactions (events)
        emit ParameterUpdated("minimumStake", _minimumStake);
    }

    /**
     * @notice Set minimum stake amount for financiers (owner only)
     */
    function setMinimumFinancierStake(
        uint256 _minimumFinancierStake
    ) external nonReentrant {
        LibDiamond.enforceIsContractOwner();
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        // Checks
        if (_minimumFinancierStake < s.minimumStake)
            revert InvalidMinimumStake();
        if (_minimumFinancierStake > 1e30) revert InvalidMinimumStake();

        // Effects
        s.minimumFinancierStake = _minimumFinancierStake;

        // Interactions (events)
        emit ParameterUpdated("minimumFinancierStake", _minimumFinancierStake);
    }

    /**
     * @notice Set USDC token address (owner only)
     */
    function setUsdcToken(address _usdcToken) external nonReentrant {
        LibDiamond.enforceIsContractOwner();
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        // Checks
        if (_usdcToken == address(0)) revert ZeroAddress();
        if (_usdcToken == address(this)) revert InvalidTokenAddress();

        // Effects
        s.usdcToken = _usdcToken;

        // Interactions (events)
        emit ParameterUpdated("usdcToken", uint256(uint160(_usdcToken)));
    }

    /**
     * @notice Set voting duration for proposals (owner only)
     */
    function setVotingDuration(uint256 _votingDuration) external nonReentrant {
        LibDiamond.enforceIsContractOwner();
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        // Checks
        if (_votingDuration < 1 days || _votingDuration > 30 days)
            revert InvalidDuration();

        // Effects
        s.votingDuration = _votingDuration;

        // Interactions (events)
        emit ParameterUpdated("votingDuration", _votingDuration);
    }

    /**
     * @notice Set proposal threshold (minimum stake to create proposal) (owner only)
     */
    function setProposalThreshold(
        uint256 _proposalThreshold
    ) external nonReentrant {
        LibDiamond.enforceIsContractOwner();
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        // Checks
        if (_proposalThreshold < s.minimumFinancierStake)
            revert InvalidThreshold();
        if (_proposalThreshold > 1e30) revert InvalidThreshold();

        // Effects
        s.proposalThreshold = _proposalThreshold;

        // Interactions (events)
        emit ParameterUpdated("proposalThreshold", _proposalThreshold);
    }

    /**
     * @notice Set approval threshold percentage (owner only)
     */
    function setApprovalThreshold(
        uint256 _approvalThreshold
    ) external nonReentrant {
        LibDiamond.enforceIsContractOwner();
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        // Checks
        if (_approvalThreshold == 0 || _approvalThreshold > 100)
            revert InvalidPercentage();

        // Effects
        s.approvalThreshold = _approvalThreshold;

        // Interactions (events)
        emit ParameterUpdated("approvalThreshold", _approvalThreshold);
    }

    /**
     * @notice Set financier lock duration (owner only)
     */
    function setMinFinancierLockDuration(
        uint256 _minFinancierLockDuration
    ) external nonReentrant {
        LibDiamond.enforceIsContractOwner();
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        // Checks
        if (_minFinancierLockDuration < 1 days) revert InvalidDuration();
        if (_minFinancierLockDuration > 365 days) revert InvalidDuration();

        // Effects
        s.minFinancierLockDuration = _minFinancierLockDuration;

        // Interactions (events)
        emit ParameterUpdated(
            "minFinancierLockDuration",
            _minFinancierLockDuration
        );
    }

    /**
     * @notice Set normal staker lock duration (owner only)
     */
    function setMinNormalStakerLockDuration(
        uint256 _minNormalStakerLockDuration
    ) external nonReentrant {
        LibDiamond.enforceIsContractOwner();
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        // Checks
        if (_minNormalStakerLockDuration < 1 hours) revert InvalidDuration();
        if (_minNormalStakerLockDuration > 365 days) revert InvalidDuration();

        // Effects
        s.minNormalStakerLockDuration = _minNormalStakerLockDuration;

        // Interactions (events)
        emit ParameterUpdated(
            "minNormalStakerLockDuration",
            _minNormalStakerLockDuration
        );
    }

    /**
     * @notice Set initial APR (owner only)
     */
    function setInitialApr(uint256 _initialApr) external nonReentrant {
        LibDiamond.enforceIsContractOwner();
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        // Checks
        if (_initialApr == 0 || _initialApr > 10000) revert InvalidAPR();

        // Effects
        s.initialApr = _initialApr;
        s.currentRewardRate = _initialApr; // Update current rate too

        // Interactions (events)
        emit ParameterUpdated("initialApr", _initialApr);
    }

    /**
     * @notice Set minimum lock duration (owner only)
     */
    function setMinLockDuration(
        uint256 _minLockDuration
    ) external nonReentrant {
        LibDiamond.enforceIsContractOwner();
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        // Checks
        if (_minLockDuration < 1 hours) revert InvalidDuration();
        if (_minLockDuration > 365 days) revert InvalidDuration();

        // Effects
        s.minLockDuration = _minLockDuration;

        // Interactions (events)
        emit ParameterUpdated("minLockDuration", _minLockDuration);
    }

    /**
     * @notice Set APR reduction per thousand tokens (owner only)
     */
    function setAprReductionPerThousand(
        uint256 _aprReductionPerThousand
    ) external nonReentrant {
        LibDiamond.enforceIsContractOwner();
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        // Checks
        if (_aprReductionPerThousand > 1000) revert InvalidAPR();

        // Effects
        s.aprReductionPerThousand = _aprReductionPerThousand;

        // Interactions (events)
        emit ParameterUpdated(
            "aprReductionPerThousand",
            _aprReductionPerThousand
        );
    }

    /**
     * @notice Set emergency withdraw penalty (owner only)
     */
    function setEmergencyWithdrawPenalty(
        uint256 _emergencyWithdrawPenalty
    ) external nonReentrant {
        LibDiamond.enforceIsContractOwner();
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        // Checks
        if (_emergencyWithdrawPenalty > 100) revert InvalidPenalty();

        // Effects
        s.emergencyWithdrawPenalty = _emergencyWithdrawPenalty;

        // Interactions (events)
        emit ParameterUpdated(
            "emergencyWithdrawPenalty",
            _emergencyWithdrawPenalty
        );
    }

    /**
     * @notice Initialize complete staking and governance configuration (owner only)
     */
    function initializeComplete(
        address _usdcToken,
        uint256 _minimumStake,
        uint256 _initialApr,
        uint256 _minLockDuration,
        uint256 _aprReductionPerThousand,
        uint256 _emergencyWithdrawPenalty
    ) external {
        LibDiamond.enforceIsContractOwner();
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        require(_initialApr > 0, "Invalid APR");
        require(_minLockDuration > 0, "Invalid lock duration");
        require(_emergencyWithdrawPenalty <= 100, "Invalid penalty");
        require(_usdcToken != address(0), "Invalid token address");
        require(_minimumStake > 0, "Invalid minimum stake");

        s.usdcToken = _usdcToken;
        s.minimumStake = _minimumStake;
        s.initialApr = _initialApr;
        s.currentRewardRate = _initialApr;
        s.minLockDuration = _minLockDuration;
        s.aprReductionPerThousand = _aprReductionPerThousand;
        s.emergencyWithdrawPenalty = _emergencyWithdrawPenalty;

        // Set default financier configuration
        s.minimumFinancierStake = _minimumStake * 10; // 10x minimum for financiers
        s.minFinancierLockDuration = _minLockDuration * 2; // 2x lock duration
        s.minNormalStakerLockDuration = _minLockDuration;

        // Set default DAO parameters
        s.votingDuration = 7 days;
        s.proposalThreshold = _minimumStake * 5; // 5x minimum to create proposal
        s.approvalThreshold = 51; // 51% approval needed
        s.revocationPeriod = 30 days; // 30 day waiting period for financier revocation
    }

    /**
     * @notice Check proposal voting threshold and update status
     */
    function _checkProposalThreshold(string memory proposalId) internal {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        LibAppStorage.Proposal storage proposal = s.proposals[proposalId];

        uint256 totalVotes = proposal.votesFor + proposal.votesAgainst;
        if (totalVotes == 0) return;

        // Check if voting period ended
        if (block.timestamp > proposal.votingDeadline) {
            uint256 approvalPercentage = (proposal.votesFor * 100) / totalVotes;

            if (approvalPercentage >= s.approvalThreshold) {
                proposal.status = LibAppStorage.ProposalStatus.Passed;
                emit ProposalStatusChanged(
                    proposalId,
                    LibAppStorage.ProposalStatus.Passed
                );
            } else {
                proposal.status = LibAppStorage.ProposalStatus.Failed;
                emit ProposalStatusChanged(
                    proposalId,
                    LibAppStorage.ProposalStatus.Failed
                );
            }
        }
        // If voting period not ended but we have enough votes, we can still determine outcome
        else if (totalVotes >= 1e18) {
            // Minimum participation threshold
            uint256 approvalPercentage = (proposal.votesFor * 100) / totalVotes;

            if (approvalPercentage >= s.approvalThreshold) {
                proposal.status = LibAppStorage.ProposalStatus.Passed;
                emit ProposalStatusChanged(
                    proposalId,
                    LibAppStorage.ProposalStatus.Passed
                );
            }
        }
    }

    /**
     * @notice Request to revoke financier status (financier only)
     */
    function requestFinancierRevocation() external nonReentrant {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        // Checks
        if (s.stakes[msg.sender].amount < s.minimumFinancierStake)
            revert NotAFinancier();
        if (s.stakes[msg.sender].revocationRequested)
            revert RevocationAlreadyRequested();

        // Effects
        s.stakes[msg.sender].revocationRequested = true;
        s.stakes[msg.sender].revocationRequestTime = block.timestamp;

        // Interactions (events)
        emit FinancierRevocationRequested(msg.sender, block.timestamp);
    }

    /**
     * @notice Execute financier revocation after waiting period
     */

    function executeFinancierRevocation() external nonReentrant {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        // Checks
        if (!s.stakes[msg.sender].revocationRequested)
            revert NoRevocationRequested();
        if (
            block.timestamp <
            s.stakes[msg.sender].revocationRequestTime + s.revocationPeriod
        ) {
            revert RevocationPeriodNotCompleted();
        }

        // Effects
        s.stakes[msg.sender].revocationRequested = false;
        s.stakes[msg.sender].revocationRequestTime = 0;

        // Interactions (events)
        emit FinancierRevocationExecuted(msg.sender, block.timestamp);
    }

    /**
     * @notice Check if emergency withdrawal is allowed for caller
     */
    function isEmergencyWithdrawAllowed(
        address user
    ) external view returns (bool) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        // Financiers cannot use emergency withdrawal
        if (s.stakes[user].amount >= s.minimumFinancierStake) {
            return false;
        }

        return true;
    }

    /**
     * @notice Get DAO configuration parameters
     */
    function getDAOConfig()
        external
        view
        returns (
            uint256 minimumFinancierStake,
            uint256 votingDuration,
            uint256 approvalThreshold,
            uint256 revocationPeriod
        )
    {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        return (
            s.minimumFinancierStake,
            s.votingDuration,
            s.approvalThreshold,
            s.revocationPeriod
        );
    }

    // ========================================
    // TOKEN MANAGEMENT (ADMIN FUNCTIONS)
    // ========================================

    event StakingTokenAdded(address indexed tokenAddress);
    event StakingTokenRemoved(address indexed tokenAddress);

    /**
     * @notice Add a new supported staking token (OWNER ONLY)
     */
    function addSupportedStakingToken(address tokenAddress) external {
        LibDiamond.enforceIsContractOwner();
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        if (tokenAddress == address(0)) revert ZeroAddress();
        require(
            !s.isStakingTokenSupported[tokenAddress],
            "Token already supported"
        );

        s.supportedStakingTokens.push(tokenAddress);
        s.isStakingTokenSupported[tokenAddress] = true;

        emit StakingTokenAdded(tokenAddress);
    }

    /**
     * @notice Remove a supported staking token (OWNER ONLY)
     */
    function removeSupportedStakingToken(address tokenAddress) external {
        LibDiamond.enforceIsContractOwner();
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        require(s.isStakingTokenSupported[tokenAddress], "Token not supported");
        require(
            s.totalStakedPerToken[tokenAddress] == 0,
            "Token has active stakes"
        );

        s.isStakingTokenSupported[tokenAddress] = false;

        // Remove from array
        for (uint256 i = 0; i < s.supportedStakingTokens.length; i++) {
            if (s.supportedStakingTokens[i] == tokenAddress) {
                s.supportedStakingTokens[i] = s.supportedStakingTokens[
                    s.supportedStakingTokens.length - 1
                ];
                s.supportedStakingTokens.pop();
                break;
            }
        }

        emit StakingTokenRemoved(tokenAddress);
    }

    /**
     * @notice Get all supported staking tokens
     */
    function getSupportedStakingTokens()
        external
        view
        returns (address[] memory)
    {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        return s.supportedStakingTokens;
    }

    /**
     * @notice Check if a token is supported for staking
     */
    function isTokenSupported(
        address tokenAddress
    ) external view returns (bool) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        return s.isStakingTokenSupported[tokenAddress];
    }

    /**
     * @notice Get total staked amount for a specific token
     */
    function getTotalStakedForToken(
        address tokenAddress
    ) external view returns (uint256) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        return s.totalStakedPerToken[tokenAddress];
    }
}
