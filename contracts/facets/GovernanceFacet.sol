// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../libraries/LibAppStorage.sol";
import "../libraries/LibDiamond.sol";
import "../libraries/LibPausable.sol";
import "../libraries/LibAddressResolver.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

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
    error ExcessiveAmount();
    error InvalidVotingPower();
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
    event FinancierRevocationCancelled(
        address indexed financier,
        uint256 cancelTime
    );
    event FinancierStatusChanged(address indexed staker, bool isFinancier);
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

        // Resolve address to primary identity (EOA)
        address staker = LibAddressResolver.resolveToEOA(msg.sender);

        // Check multi-token storage
        uint256 totalUsdValue = 0;
        bool hasFinancierStake = false;
        bool hasRevocationPending = false;

        for (uint256 i = 0; i < s.supportedStakingTokens.length; i++) {
            address tokenAddress = s.supportedStakingTokens[i];
            LibAppStorage.Stake storage tokenStake = s.stakesPerToken[staker][
                tokenAddress
            ];

            if (tokenStake.active && tokenStake.amount > 0) {
                totalUsdValue += tokenStake.usdEquivalent;
                if (tokenStake.isFinancier) {
                    hasFinancierStake = true;
                    // Check if revocation is pending
                    if (tokenStake.revocationRequested) {
                        hasRevocationPending = true;
                    }
                }
            }
        }

        if (!hasFinancierStake || totalUsdValue < s.minimumFinancierStake) {
            revert NotFinancier();
        }
        // Block if revocation is pending - they should not participate while exiting
        if (hasRevocationPending) {
            revert("Cannot participate in governance during revocation period");
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
     * @notice Create DAO proposal
     * @dev Uses address resolution: EOA is primary identity
     */
    function createProposal(
        string calldata proposalId,
        string calldata category,
        string calldata title,
        string calldata description
    ) external whenNotPaused onlyFinancier nonReentrant {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        // Resolve address to primary identity (EOA)
        address proposer = LibAddressResolver.resolveToEOA(msg.sender);

        // Security: Prevent zero address exploitation
        if (proposer == address(0)) revert ZeroAddress();

        // Checks - Input validation with bounds
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

        // Check multi-token storage for proposal threshold
        uint256 totalStakedUsd = 0;
        uint256 tokensLength = s.supportedStakingTokens.length;
        for (uint256 i = 0; i < tokensLength; ) {
            address tokenAddress = s.supportedStakingTokens[i];
            LibAppStorage.Stake storage tokenStake = s.stakesPerToken[proposer][
                tokenAddress
            ];
            if (tokenStake.active && tokenStake.amount > 0) {
                // Security: Prevent overflow when summing stakes
                unchecked {
                    if (
                        totalStakedUsd + tokenStake.usdEquivalent <
                        totalStakedUsd
                    ) {
                        revert ExcessiveAmount();
                    }
                }
                totalStakedUsd += tokenStake.usdEquivalent;
            }

            unchecked {
                ++i; // Safe: bounded by tokensLength
            }
        }
        if (totalStakedUsd < s.proposalThreshold) revert InsufficientStake();

        // Effects
        // Security: Validate voting duration to prevent timestamp manipulation
        if (s.votingDuration > 365 days) revert InvalidDuration();
        uint256 votingDeadline = block.timestamp + s.votingDuration;
        // Security: Prevent deadline overflow
        if (votingDeadline < block.timestamp) revert InvalidDuration();

        s.proposals[proposalId] = LibAppStorage.Proposal({
            proposalId: proposalId,
            proposer: proposer,
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
            proposer,
            votingDeadline
        );
    }

    /**
     * @notice Vote on DAO proposal
     * @dev Uses address resolution: EOA is primary identity
     * Security: Implements checks-effects-interactions pattern
     */
    function voteOnProposal(
        string calldata proposalId,
        bool support
    ) external onlyFinancier nonReentrant {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        LibAppStorage.Proposal storage proposal = s.proposals[proposalId];

        // Resolve address to primary identity (EOA)
        address voter = LibAddressResolver.resolveToEOA(msg.sender);

        // Security: Prevent zero address exploitation
        if (voter == address(0)) revert ZeroAddress();

        // Checks
        if (proposal.createdAt == 0) revert ProposalNotFound();
        if (proposal.status != LibAppStorage.ProposalStatus.Active)
            revert ProposalNotActive();
        if (block.timestamp > proposal.votingDeadline)
            revert VotingPeriodEnded();
        if (s.hasVotedOnProposal[proposalId][voter]) revert AlreadyVoted();

        // Calculate voting power from multi-token storage
        uint256 votingPower = 0;
        uint256 tokensLength = s.supportedStakingTokens.length;
        for (uint256 i = 0; i < tokensLength; ) {
            address tokenAddress = s.supportedStakingTokens[i];
            LibAppStorage.Stake storage tokenStake = s.stakesPerToken[voter][
                tokenAddress
            ];
            if (tokenStake.active && tokenStake.amount > 0) {
                // Security: Prevent voting power overflow
                unchecked {
                    if (votingPower + tokenStake.votingPower < votingPower) {
                        revert InvalidVotingPower();
                    }
                }
                votingPower += tokenStake.votingPower;
            }

            unchecked {
                ++i; // Safe: bounded by tokensLength
            }
        }
        if (votingPower == 0) revert InsufficientStake();

        // Effects
        s.hasVotedOnProposal[proposalId][voter] = true;
        s.voterSupport[proposalId][voter] = support;

        if (support) {
            // Security: Prevent vote count overflow
            unchecked {
                if (proposal.votesFor + votingPower < proposal.votesFor) {
                    revert InvalidVotingPower();
                }
            }
            proposal.votesFor += votingPower;
        } else {
            unchecked {
                if (
                    proposal.votesAgainst + votingPower < proposal.votesAgainst
                ) {
                    revert InvalidVotingPower();
                }
            }
            proposal.votesAgainst += votingPower;
        }

        // Interactions (events)
        emit ProposalVoteCast(proposalId, voter, support, votingPower);

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
     * @dev Resolves address to primary identity (EOA)
     */
    function getVoteStatus(
        string memory proposalId,
        address voter
    ) external view returns (bool hasVoted, bool support) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        // Resolve address to primary identity (EOA)
        address resolvedVoter = LibAddressResolver.resolveToEOA(voter);

        return (
            s.hasVotedOnProposal[proposalId][resolvedVoter],
            s.voterSupport[proposalId][resolvedVoter]
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
     * @notice Recalculate voting powers for all stakers (imported from LiquidityPoolFacet)
     * @dev Must be called after financier status changes
     */
    function _recalculateAllVotingPowers() internal {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        if (s.totalStaked == 0) return;

        uint256 stakersLength = s.stakers.length;
        if (stakersLength > 10000) return;

        for (uint256 i = 0; i < stakersLength; ) {
            address staker = s.stakers[i];
            uint256 totalUserUsd = 0;

            uint256 tokensLength = s.supportedStakingTokens.length;
            for (uint256 j = 0; j < tokensLength; ) {
                address token = s.supportedStakingTokens[j];
                if (s.stakesPerToken[staker][token].active) {
                    // Zero out voting power if revocation is pending
                    if (s.stakesPerToken[staker][token].revocationRequested) {
                        s.stakesPerToken[staker][token].votingPower = 0;
                    } else {
                        totalUserUsd += s
                            .stakesPerToken[staker][token]
                            .usdEquivalent;

                        if (totalUserUsd > type(uint256).max / 1e6) {
                            s.stakesPerToken[staker][token].votingPower = 1e6;
                        } else {
                            s.stakesPerToken[staker][token].votingPower =
                                (s.stakesPerToken[staker][token].usdEquivalent *
                                    1e6) /
                                s.totalStaked;
                        }
                    }
                }

                unchecked {
                    ++j;
                }
            }

            if (s.stakes[staker].active && s.stakes[staker].amount > 0) {
                totalUserUsd += s.stakes[staker].amount;
                if (totalUserUsd > type(uint256).max / 1e6) {
                    s.stakes[staker].votingPower = 1e6;
                } else {
                    s.stakes[staker].votingPower =
                        (s.stakes[staker].amount * 1e6) /
                        s.totalStaked;
                }
            }

            unchecked {
                ++i;
            }
        }
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
        else if (totalVotes >= 1e6) {
            // Minimum participation threshold (1 full voting power unit)
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
        address staker = LibAddressResolver.resolveToEOA(msg.sender);

        // Check multi-token storage for financier status
        uint256 totalUsdValue = 0;
        bool hasFinancierStake = false;
        for (uint256 i = 0; i < s.supportedStakingTokens.length; i++) {
            address tokenAddress = s.supportedStakingTokens[i];
            LibAppStorage.Stake storage tokenStake = s.stakesPerToken[staker][
                tokenAddress
            ];
            if (tokenStake.active && tokenStake.amount > 0) {
                totalUsdValue += tokenStake.usdEquivalent;
                if (tokenStake.isFinancier) {
                    hasFinancierStake = true;
                    // Check revocation status
                    if (tokenStake.revocationRequested)
                        revert RevocationAlreadyRequested();
                }
            }
        }

        if (!hasFinancierStake || totalUsdValue < s.minimumFinancierStake)
            revert NotAFinancier();

        // Effects - mark all financier stakes as revocation requested
        for (uint256 i = 0; i < s.supportedStakingTokens.length; i++) {
            address tokenAddress = s.supportedStakingTokens[i];
            LibAppStorage.Stake storage tokenStake = s.stakesPerToken[staker][
                tokenAddress
            ];
            if (tokenStake.active && tokenStake.isFinancier) {
                tokenStake.revocationRequested = true;
                tokenStake.revocationRequestTime = block.timestamp;
            }
        }

        // Recalculate voting powers immediately to prevent stale voting power during revocation period
        _recalculateAllVotingPowers();

        // Interactions (events)
        emit FinancierRevocationRequested(msg.sender, block.timestamp);
    }

    /**
     * @notice Cancel financier revocation request
     * @dev Restores full financier rights and voting power
     * If they request revocation again, the 30-day period starts fresh
     */
    function cancelFinancierRevocation() external nonReentrant {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        address staker = LibAddressResolver.resolveToEOA(msg.sender);

        // Checks - verify revocation was requested
        bool hasRevocationRequest = false;
        for (uint256 i = 0; i < s.supportedStakingTokens.length; i++) {
            address tokenAddress = s.supportedStakingTokens[i];
            LibAppStorage.Stake storage tokenStake = s.stakesPerToken[staker][
                tokenAddress
            ];
            if (
                tokenStake.active &&
                tokenStake.isFinancier &&
                tokenStake.revocationRequested
            ) {
                hasRevocationRequest = true;
                break;
            }
        }

        if (!hasRevocationRequest) revert NoRevocationRequested();

        // Effects - clear revocation flags (keep isFinancier = true)
        for (uint256 i = 0; i < s.supportedStakingTokens.length; i++) {
            address tokenAddress = s.supportedStakingTokens[i];
            LibAppStorage.Stake storage tokenStake = s.stakesPerToken[staker][
                tokenAddress
            ];
            if (tokenStake.active && tokenStake.isFinancier) {
                tokenStake.revocationRequested = false;
                tokenStake.revocationRequestTime = 0;
            }
        }

        // Recalculate voting powers to restore full voting power
        _recalculateAllVotingPowers();

        // Interactions (events)
        emit FinancierRevocationCancelled(msg.sender, block.timestamp);
    }

    /**
     * @notice Execute financier revocation after waiting period
     */

    function executeFinancierRevocation() external nonReentrant {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        address staker = LibAddressResolver.resolveToEOA(msg.sender);

        // Checks - verify revocation was requested and period completed
        bool hasRevocationRequest = false;
        uint256 earliestRequestTime = type(uint256).max;

        for (uint256 i = 0; i < s.supportedStakingTokens.length; i++) {
            address tokenAddress = s.supportedStakingTokens[i];
            LibAppStorage.Stake storage tokenStake = s.stakesPerToken[staker][
                tokenAddress
            ];
            if (
                tokenStake.active &&
                tokenStake.isFinancier &&
                tokenStake.revocationRequested
            ) {
                hasRevocationRequest = true;
                if (tokenStake.revocationRequestTime < earliestRequestTime) {
                    earliestRequestTime = tokenStake.revocationRequestTime;
                }
            }
        }

        if (!hasRevocationRequest) revert NoRevocationRequested();
        if (block.timestamp < earliestRequestTime + s.revocationPeriod) {
            revert RevocationPeriodNotCompleted();
        }

        // Effects - revoke financier status and clear revocation flags
        for (uint256 i = 0; i < s.supportedStakingTokens.length; i++) {
            address tokenAddress = s.supportedStakingTokens[i];
            LibAppStorage.Stake storage tokenStake = s.stakesPerToken[staker][
                tokenAddress
            ];
            if (tokenStake.active && tokenStake.isFinancier) {
                tokenStake.isFinancier = false;
                tokenStake.revocationRequested = false;
                tokenStake.revocationRequestTime = 0;
            }
        }

        // Recalculate voting powers after revocation
        _recalculateAllVotingPowers();

        // Interactions (events)
        emit FinancierRevocationExecuted(msg.sender, block.timestamp);
        emit FinancierStatusChanged(staker, false);
    }

    /**
     * @notice Check if emergency withdrawal is allowed for caller
     */
    function isEmergencyWithdrawAllowed(
        address user
    ) external view returns (bool) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        address resolvedUser = LibAddressResolver.resolveToEOA(user);

        // Check multi-token storage - financiers cannot use emergency withdrawal
        uint256 totalUsdValue = 0;
        bool hasFinancierStake = false;

        for (uint256 i = 0; i < s.supportedStakingTokens.length; i++) {
            address tokenAddress = s.supportedStakingTokens[i];
            LibAppStorage.Stake storage tokenStake = s.stakesPerToken[
                resolvedUser
            ][tokenAddress];
            if (tokenStake.active && tokenStake.amount > 0) {
                totalUsdValue += tokenStake.usdEquivalent;
                if (tokenStake.isFinancier) {
                    hasFinancierStake = true;
                }
            }
        }

        if (hasFinancierStake && totalUsdValue >= s.minimumFinancierStake) {
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
     * @dev Only supports tokens with 6-18 decimals (standard ERC20 range)
     */
    function addSupportedStakingToken(address tokenAddress) external {
        LibDiamond.enforceIsContractOwner();
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        if (tokenAddress == address(0)) revert ZeroAddress();
        require(
            !s.isStakingTokenSupported[tokenAddress],
            "Token already supported"
        );

        // CRITICAL: Validate token decimals to prevent decimal conversion underflow
        // Most stablecoins use 6 or 18 decimals, we support 6-18 range
        try IERC20Metadata(tokenAddress).decimals() returns (uint8 decimals) {
            require(
                decimals >= 6 && decimals <= 18,
                "Token decimals must be between 6 and 18"
            );
        } catch {
            revert("Token must implement decimals()");
        }
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

    /**
     * @notice Get total USD value staked across all supported tokens
     * @dev Returns the sum of all USD equivalents across all tokens
     * @return Total USD value with 18 decimals precision (matches s.totalStaked)
     */
    function getTotalStakedUSD() external view returns (uint256) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        return s.totalStaked;
    }

    /**
     * @notice Get detailed stats for all supported staking tokens
     * @dev Returns arrays of token addresses, their staked amounts, and count
     * @return tokens Array of supported token addresses
     * @return stakedAmounts Array of total staked amounts per token (in token's decimals)
     * @return totalUsdValue Total USD value across all tokens (18 decimals)
     * @return tokenCount Number of supported tokens
     */
    function getAllTokenStats()
        external
        view
        returns (
            address[] memory tokens,
            uint256[] memory stakedAmounts,
            uint256 totalUsdValue,
            uint256 tokenCount
        )
    {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        tokenCount = s.supportedStakingTokens.length;
        tokens = new address[](tokenCount);
        stakedAmounts = new uint256[](tokenCount);

        for (uint256 i = 0; i < tokenCount; i++) {
            tokens[i] = s.supportedStakingTokens[i];
            stakedAmounts[i] = s.totalStakedPerToken[tokens[i]];
        }

        totalUsdValue = s.totalStaked;
    }
}
