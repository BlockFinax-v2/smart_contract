// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../libraries/LibAppStorage.sol";
import "../libraries/LibDiamond.sol";
import "../libraries/LibPausable.sol";
import "../libraries/LibAddressResolver.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title TradeFinanceFacet
 * @notice Manages Pool Guarantee Applications (PGA) for international trade finance
 * @dev Built on top of GovernanceFacet and LiquidityPoolFacet
 */
contract TradeFinanceFacet is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Custom Errors
    error ContractPaused();
    error NotAuthorized();
    error NotFinancier();
    error InvalidPGAId();
    error InvalidAddress();
    error InvalidAmount();
    error InvalidDuration();
    error InvalidString();
    error PGAAlreadyExists();
    error PGANotFound();
    error PGANotActive();
    error PGANotApproved();
    error PGAExpired();
    error VotingPeriodEnded();
    error VotingPeriodNotEnded();
    error AlreadyVoted();
    error OnlySellerAllowed();
    error OnlyBuyerAllowed();
    error OnlyLogisticsPartner();
    error CollateralAlreadyPaid();
    error CollateralNotPaid();
    error BalanceAlreadyPaid();
    error GoodsNotShipped();
    error CertificateAlreadyIssued();
    error InvalidPGAStatus();
    error InsufficientBalance();
    error InsufficientAllowance();
    error TransferFailed();
    error DeliveryAgreementExists();
    error DeliveryAgreementNotFound();
    error BuyerConsentAlreadyGiven();
    error ZeroAddress();
    error InvalidVotingPower();
    error ExcessiveAmount();
    error IssuanceFeeAlreadyPaid();
    error IssuanceFeeNotPaid();
    error TreasuryNotSet();
    error InvalidTokenAddress();

    // Constants
    uint256 private constant PRECISION = 1e6; // 6 decimals matching voting power normalization

    // Events
    event PGACreated(
        string indexed pgaId,
        address indexed buyer,
        address indexed seller,
        uint256 tradeValue,
        uint256 guaranteeAmount,
        uint256 collateralAmount,
        uint256 duration,
        string metadataURI,
        uint256 votingDeadline,
        uint256 createdAt
    );

    event PGAVoteCast(
        string indexed pgaId,
        address indexed voter,
        bool support,
        uint256 votingPower,
        uint256 timestamp
    );

    event PGAStatusChanged(
        string indexed pgaId,
        LibAppStorage.PGAStatus oldStatus,
        LibAppStorage.PGAStatus newStatus,
        uint256 timestamp
    );

    event GuaranteeApproved(
        string indexed pgaId,
        address indexed buyer,
        address indexed seller,
        string companyName,
        string registrationNumber,
        string tradeDescription,
        uint256 tradeValue,
        uint256 guaranteeAmount,
        uint256 duration,
        string beneficiaryName,
        address beneficiaryWallet,
        uint256 timestamp
    );

    event SellerApprovalReceived(
        string indexed pgaId,
        address indexed seller,
        uint256 timestamp
    );

    event CollateralPaid(
        string indexed pgaId,
        address indexed buyer,
        uint256 collateralAmount,
        uint256 timestamp
    );

    event GoodsShipped(
        string indexed pgaId,
        address indexed logisticPartner,
        string logisticPartnerName,
        uint256 timestamp
    );

    event BalancePaymentReceived(
        string indexed pgaId,
        address indexed buyer,
        uint256 balanceAmount,
        uint256 timestamp
    );

    event CertificateIssued(
        string indexed pgaId,
        string certificateNumber,
        uint256 issueDate,
        address indexed buyer,
        address indexed seller,
        uint256 tradeValue,
        uint256 guaranteeAmount,
        uint256 validityDays,
        string blockchainNetwork,
        address smartContract
    );

    event DeliveryAgreementCreated(
        string indexed agreementId,
        string indexed pgaId,
        address indexed deliveryPerson,
        address buyer,
        uint256 createdAt,
        uint256 deadline,
        string deliveryNotes
    );

    event BuyerConsentGiven(
        string indexed agreementId,
        string indexed pgaId,
        address indexed buyer,
        uint256 timestamp
    );

    event PGACompleted(
        string indexed pgaId,
        address indexed buyer,
        address indexed seller,
        uint256 completedAt
    );

    event LogisticPartnerAuthorized(
        address indexed partner,
        bool authorized,
        uint256 timestamp
    );

    event CollateralRefunded(
        string indexed pgaId,
        address indexed buyer,
        uint256 amount,
        uint256 timestamp
    );

    event IssuanceFeePaid(
        string indexed pgaId,
        address indexed buyer,
        address indexed treasury,
        uint256 amount,
        uint256 timestamp
    );

    event BlockFinaxTreasuryUpdated(
        address indexed oldTreasury,
        address indexed newTreasury
    );

    event SellerPaymentReleased(
        string indexed pgaId,
        address indexed seller,
        uint256 amount,
        uint256 timestamp
    );

    event Paused(address account);
    event Unpaused(address account);

    // Modifiers
    modifier whenNotPaused() {
        if (LibPausable.isPaused()) revert ContractPaused();
        _;
    }

    modifier onlyFinancier() {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        // Resolve address to primary identity (EOA)
        address resolvedAddress = LibAddressResolver.resolveToEOA(msg.sender);

        // Check if user has any financier stake across all tokens
        bool isFinancier = false;
        for (uint256 i = 0; i < s.supportedStakingTokens.length; i++) {
            address tokenAddress = s.supportedStakingTokens[i];
            LibAppStorage.Stake storage stake = s.stakesPerToken[
                resolvedAddress
            ][tokenAddress];

            if (stake.active && stake.isFinancier && stake.amount > 0) {
                isFinancier = true;
                break;
            }
        }

        if (!isFinancier) revert NotFinancier();
        _;
    }

    /**
     * @notice Authorize a logistics partner
     * @dev Only contract owner can authorize
     */
    function authorizeLogisticsPartner(
        address partner,
        bool authorized
    ) public {
        LibDiamond.enforceIsContractOwner();
        if (partner == address(0)) revert ZeroAddress();

        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        // Check current authorization status BEFORE updating
        bool wasAuthorized = s.authorizedLogisticsPartners[partner];

        // Only update if status is changing
        if (authorized && !wasAuthorized) {
            // Add to list and authorize
            s.logisticsPartnersList.push(partner);
            s.authorizedLogisticsPartners[partner] = true;
            emit LogisticPartnerAuthorized(partner, true, block.timestamp);
        } else if (!authorized && wasAuthorized) {
            // Deauthorize (keep in list for history)
            s.authorizedLogisticsPartners[partner] = false;
            emit LogisticPartnerAuthorized(partner, false, block.timestamp);
        }
        // If status is not changing, do nothing
    }

    /**
     * @notice Authorize or deauthorize logistics partner (alias for compatibility)
     * @dev Only contract owner can manage logistics partners
     * @dev This is an alias for authorizeLogisticsPartner to maintain backward compatibility
     */
    function setLogisticsPartner(address partner, bool authorized) external {
        // Simply delegate to authorizeLogisticsPartner to avoid code duplication
        authorizeLogisticsPartner(partner, authorized);
    }

    /**
     * @notice Remove logistics partner completely from the system
     * @dev Only contract owner can remove logistics partners
     * @dev This completely removes the partner from both the mapping and array
     * @param partner Address of the logistics partner to remove
     */
    function removeLogisticsPartner(address partner) external {
        LibDiamond.enforceIsContractOwner();
        if (partner == address(0)) revert ZeroAddress();

        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        // Remove from mapping
        delete s.authorizedLogisticsPartners[partner];

        // Remove from array
        address[] storage list = s.logisticsPartnersList;
        for (uint256 i = 0; i < list.length; i++) {
            if (list[i] == partner) {
                // Move last element to this position and pop
                list[i] = list[list.length - 1];
                list.pop();
                break;
            }
        }

        emit LogisticPartnerAuthorized(partner, false, block.timestamp);
    }

    /**
     * @notice Remove delivery person completely from the system
     * @dev Only contract owner can remove delivery persons
     * @dev This completely removes the delivery person from both the mapping and array
     * @param deliveryPerson Address of the delivery person to remove
     */
    function removeDeliveryPerson(address deliveryPerson) external {
        LibDiamond.enforceIsContractOwner();
        if (deliveryPerson == address(0)) revert ZeroAddress();

        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        // Remove from mapping
        delete s.authorizedDeliveryPersons[deliveryPerson];

        // Remove from array
        address[] storage list = s.deliveryPersonsList;
        for (uint256 i = 0; i < list.length; i++) {
            if (list[i] == deliveryPerson) {
                // Move last element to this position and pop
                list[i] = list[list.length - 1];
                list.pop();
                break;
            }
        }

        emit LogisticPartnerAuthorized(deliveryPerson, false, block.timestamp);
    }

    /**
     * @notice Create a Pool Guarantee Application (PGA)
     * @dev Creates a new PGA and opens it for financier voting
     */
    function createPGA(
        string calldata pgaId,
        address seller,
        string calldata companyName,
        string calldata registrationNumber,
        string calldata tradeDescription,
        uint256 tradeValue,
        uint256 guaranteeAmount,
        uint256 collateralAmount,
        uint256 issuanceFee,
        uint256 duration,
        string calldata beneficiaryName,
        address beneficiaryWallet,
        string calldata metadataURI,
        string[] calldata documentURIs
    ) external whenNotPaused nonReentrant {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        // Validation
        if (bytes(pgaId).length == 0) revert InvalidPGAId();
        if (seller == address(0)) revert InvalidAddress();
        if (tradeValue == 0) revert InvalidAmount();
        if (guaranteeAmount == 0) revert InvalidAmount();
        if (guaranteeAmount > tradeValue) revert ExcessiveAmount(); // Guarantee cannot exceed trade value
        if (collateralAmount == 0) revert InvalidAmount();
        if (collateralAmount >= tradeValue) revert ExcessiveAmount(); // Collateral must be less than trade value
        if (duration == 0) revert InvalidDuration();
        if (bytes(metadataURI).length == 0) revert InvalidString();
        if (s.pgas[pgaId].status != LibAppStorage.PGAStatus.None)
            revert PGAAlreadyExists();

        // Resolve buyer address to primary identity (EOA)
        address buyer = LibAddressResolver.resolveToEOA(msg.sender);
        address resolvedSeller = LibAddressResolver.resolveToEOA(seller);

        // Buyer and seller must be different
        if (buyer == resolvedSeller) revert InvalidAddress();

        // Validate voting duration is set
        if (s.votingDuration == 0) revert InvalidDuration();

        uint256 votingDeadline = block.timestamp + s.votingDuration;

        // Create PGA
        LibAppStorage.PoolGuaranteeApplication storage pga = s.pgas[pgaId];
        pga.pgaId = pgaId;
        pga.buyer = buyer;
        pga.seller = seller;
        pga.tradeValue = tradeValue;
        pga.guaranteeAmount = guaranteeAmount;
        pga.collateralAmount = collateralAmount;
        pga.issuanceFee = issuanceFee;
        pga.duration = duration;
        pga.votesFor = 0;
        pga.votesAgainst = 0;
        pga.createdAt = block.timestamp;
        pga.votingDeadline = votingDeadline;
        pga.status = LibAppStorage.PGAStatus.Created;
        pga.collateralPaid = false;
        pga.balancePaymentPaid = false;
        pga.goodsShipped = false;
        pga.metadataURI = metadataURI;
        pga.uploadedDocuments = documentURIs;
        pga.companyName = companyName;
        pga.registrationNumber = registrationNumber;
        pga.tradeDescription = tradeDescription;
        pga.beneficiaryName = beneficiaryName;
        pga.beneficiaryWallet = beneficiaryWallet;

        s.pgaIds.push(pgaId);
        s.totalPGAs++;
        s.totalActivePGAs++;

        emit PGACreated(
            pgaId,
            buyer,
            seller,
            tradeValue,
            guaranteeAmount,
            collateralAmount,
            duration,
            metadataURI,
            votingDeadline,
            block.timestamp
        );
    }

    /**
     * @notice Financiers vote on PGA
     * @dev Only financiers can vote, similar to proposal voting
     */
    function voteOnPGA(
        string calldata pgaId,
        bool support
    ) external whenNotPaused onlyFinancier nonReentrant {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        LibAppStorage.PoolGuaranteeApplication storage pga = s.pgas[pgaId];

        // Validation
        if (pga.status == LibAppStorage.PGAStatus.None) revert PGANotFound();
        if (pga.status != LibAppStorage.PGAStatus.Created)
            revert PGANotActive();
        if (block.timestamp > pga.votingDeadline) revert VotingPeriodEnded();

        // Resolve voter address to primary identity (EOA)
        address voter = LibAddressResolver.resolveToEOA(msg.sender);

        if (s.hasVotedOnPGA[pgaId][voter]) revert AlreadyVoted();

        // Calculate voting power based on total staked USD value across all tokens
        uint256 votingPower = 0;
        for (uint256 i = 0; i < s.supportedStakingTokens.length; i++) {
            address tokenAddress = s.supportedStakingTokens[i];
            LibAppStorage.Stake storage stake = s.stakesPerToken[voter][
                tokenAddress
            ];

            if (stake.active && stake.isFinancier && stake.amount > 0) {
                votingPower += stake.votingPower;
            }
        }

        if (votingPower == 0) revert InvalidVotingPower();

        // Record vote
        s.hasVotedOnPGA[pgaId][voter] = true;
        s.pgaVoterSupport[pgaId][voter] = support;

        if (support) {
            pga.votesFor += votingPower;
        } else {
            pga.votesAgainst += votingPower;
        }

        emit PGAVoteCast(pgaId, voter, support, votingPower, block.timestamp);

        // Check if approval threshold is met
        _checkPGAApprovalThreshold(pgaId);
    }

    /**
     * @notice Check if PGA has reached approval threshold
     * @dev Internal function to evaluate and update PGA status
     */
    function _checkPGAApprovalThreshold(string memory pgaId) internal {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        LibAppStorage.PoolGuaranteeApplication storage pga = s.pgas[pgaId];

        if (pga.status != LibAppStorage.PGAStatus.Created) return;
        if (block.timestamp > pga.votingDeadline) {
            // Expired
            LibAppStorage.PGAStatus oldStatus = pga.status;
            pga.status = LibAppStorage.PGAStatus.Expired;
            s.totalActivePGAs--;
            emit PGAStatusChanged(
                pgaId,
                oldStatus,
                LibAppStorage.PGAStatus.Expired,
                block.timestamp
            );
            return;
        }

        // Calculate total voting power
        uint256 totalVotingPower = pga.votesFor + pga.votesAgainst;
        if (totalVotingPower == 0) return;

        // Quorum Check: Requires at least 10% of total voting power (normalized to PRECISION)
        // Note: s.totalStaked tracks global stake in USD, but votingPower is normalized to PRECISION
        uint256 minQuorum = (PRECISION * 10) / 100; // 10% Quorum
        if (totalVotingPower < minQuorum) return; // Not enough participation yet

        // Check if rejected - need majority against
        // Rejection requires votesAgainst > 50% of total votes cast
        if (pga.votesAgainst > totalVotingPower / 2) {
            LibAppStorage.PGAStatus oldStatus = pga.status;
            pga.status = LibAppStorage.PGAStatus.Rejected;
            s.totalActivePGAs--;
            emit PGAStatusChanged(
                pgaId,
                oldStatus,
                LibAppStorage.PGAStatus.Rejected,
                block.timestamp
            );
            return;
        }

        // Check if approved - need approval threshold met
        // Approval requires votesFor >= approvalThreshold% of total votes cast
        uint256 approvalThreshold = (totalVotingPower * s.approvalThreshold) /
            100;
        if (pga.votesFor >= approvalThreshold) {
            LibAppStorage.PGAStatus oldStatus = pga.status;
            pga.status = LibAppStorage.PGAStatus.GuaranteeApproved;

            emit PGAStatusChanged(
                pgaId,
                oldStatus,
                LibAppStorage.PGAStatus.GuaranteeApproved,
                block.timestamp
            );

            // Emit GuaranteeApproved event for seller notification
            emit GuaranteeApproved(
                pgaId,
                pga.buyer,
                pga.seller,
                pga.companyName,
                pga.registrationNumber,
                pga.tradeDescription,
                pga.tradeValue,
                pga.guaranteeAmount,
                pga.duration,
                pga.beneficiaryName,
                pga.beneficiaryWallet,
                block.timestamp
            );
        }
    }

    /**
     * @notice Seller approves or rejects the PGA
     * @dev Only the seller specified in the PGA can approve/reject
     */
    function sellerVoteOnPGA(
        string calldata pgaId,
        bool approve
    ) external whenNotPaused nonReentrant {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        LibAppStorage.PoolGuaranteeApplication storage pga = s.pgas[pgaId];

        // Validation
        if (pga.status == LibAppStorage.PGAStatus.None) revert PGANotFound();
        if (pga.status != LibAppStorage.PGAStatus.GuaranteeApproved)
            revert InvalidPGAStatus();

        // Resolve seller address
        address resolvedSeller = LibAddressResolver.resolveToEOA(msg.sender);
        address pgaSeller = LibAddressResolver.resolveToEOA(pga.seller);

        if (resolvedSeller != pgaSeller) revert OnlySellerAllowed();
        if (s.sellerHasVoted[pgaId]) revert AlreadyVoted(); // Prevent duplicate seller votes
        if (block.timestamp > pga.votingDeadline) revert PGAExpired();

        // Mark seller as voted
        s.sellerHasVoted[pgaId] = true;

        LibAppStorage.PGAStatus oldStatus = pga.status;

        if (approve) {
            pga.status = LibAppStorage.PGAStatus.SellerApproved;
            emit PGAStatusChanged(
                pgaId,
                oldStatus,
                LibAppStorage.PGAStatus.SellerApproved,
                block.timestamp
            );
            emit SellerApprovalReceived(pgaId, pga.seller, block.timestamp);
        } else {
            pga.status = LibAppStorage.PGAStatus.Rejected;
            s.totalActivePGAs--;
            emit PGAStatusChanged(
                pgaId,
                oldStatus,
                LibAppStorage.PGAStatus.Rejected,
                block.timestamp
            );
        }
    }

    /**
     * @notice Buyer pays collateral amount
     * @dev Transfers collateral to the Treasury Pool (Diamond contract)
     */
    function payCollateral(
        string calldata pgaId,
        address tokenAddress
    ) external whenNotPaused nonReentrant {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        LibAppStorage.PoolGuaranteeApplication storage pga = s.pgas[pgaId];

        // Validation
        if (pga.status == LibAppStorage.PGAStatus.None) revert PGANotFound();
        if (pga.status != LibAppStorage.PGAStatus.SellerApproved)
            revert InvalidPGAStatus();
        if (tokenAddress == address(0)) revert InvalidTokenAddress();
        require(s.isStakingTokenSupported[tokenAddress], "Token not supported");

        address resolvedBuyer = LibAddressResolver.resolveToEOA(msg.sender);
        address pgaBuyer = LibAddressResolver.resolveToEOA(pga.buyer);

        if (resolvedBuyer != pgaBuyer) revert OnlyBuyerAllowed();
        if (pga.collateralPaid) revert CollateralAlreadyPaid();

        // Transfer collateral to Treasury Pool (this contract)
        IERC20 token = IERC20(tokenAddress);
        uint256 collateralAmount = pga.collateralAmount;

        // CRITICAL: Check balance and allowance from resolvedBuyer (EOA has the funds)
        if (token.balanceOf(resolvedBuyer) < collateralAmount)
            revert InsufficientBalance();
        if (token.allowance(resolvedBuyer, address(this)) < collateralAmount)
            revert InsufficientAllowance();

        // CRITICAL: Transfer from resolvedBuyer (EOA), not msg.sender (Smart Account)
        token.safeTransferFrom(resolvedBuyer, address(this), collateralAmount);

        // Update PGA status
        pga.collateralPaid = true;
        LibAppStorage.PGAStatus oldStatus = pga.status;

        // If fee is also paid, notify logistics. Otherwise move to CollateralPaid
        if (pga.issuanceFeePaid) {
            pga.status = LibAppStorage.PGAStatus.LogisticsNotified;
        } else {
            pga.status = LibAppStorage.PGAStatus.CollateralPaid;
        }

        emit PGAStatusChanged(pgaId, oldStatus, pga.status, block.timestamp);
        emit CollateralPaid(
            pgaId,
            pga.buyer,
            collateralAmount,
            block.timestamp
        );
    }

    /**
     * @notice Set the BlockFinax treasury address for fee collection
     * @param _treasury New treasury address
     */
    function setBlockFinaxTreasury(address _treasury) external {
        LibDiamond.enforceIsContractOwner();
        if (_treasury == address(0)) revert ZeroAddress();

        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        address oldTreasury = s.blockFinaxTreasury;
        s.blockFinaxTreasury = _treasury;

        emit BlockFinaxTreasuryUpdated(oldTreasury, _treasury);
    }

    /**
     * @notice Get the current BlockFinax treasury address
     * @return Current treasury address
     */
    function getBlockFinaxTreasury() external view returns (address) {
        return LibAppStorage.appStorage().blockFinaxTreasury;
    }

    /**
     * @notice Pay the 1% issuance fee for a Pool Guarantee Application
     * @param pgaId The unique identifier of the PGA
     */
    function payIssuanceFee(
        string calldata pgaId,
        address tokenAddress
    ) external whenNotPaused nonReentrant {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        LibAppStorage.PoolGuaranteeApplication storage pga = s.pgas[pgaId];

        // Validation
        if (pga.status == LibAppStorage.PGAStatus.None) revert PGANotFound();

        // Should be either SellerApproved or CollateralPaid
        if (
            pga.status != LibAppStorage.PGAStatus.SellerApproved &&
            pga.status != LibAppStorage.PGAStatus.CollateralPaid
        ) revert InvalidPGAStatus();

        if (tokenAddress == address(0)) revert InvalidTokenAddress();
        require(s.isStakingTokenSupported[tokenAddress], "Token not supported");

        address resolvedBuyer = LibAddressResolver.resolveToEOA(msg.sender);
        address pgaBuyer = LibAddressResolver.resolveToEOA(pga.buyer);

        if (resolvedBuyer != pgaBuyer) revert OnlyBuyerAllowed();
        if (pga.issuanceFeePaid) revert IssuanceFeeAlreadyPaid();

        // Transfer fee to Treasury Pool (this contract)
        IERC20 token = IERC20(tokenAddress);
        uint256 feeAmount = pga.issuanceFee;

        // CRITICAL: Check balance and allowance from resolvedBuyer
        if (token.balanceOf(resolvedBuyer) < feeAmount)
            revert InsufficientBalance();
        if (token.allowance(resolvedBuyer, address(this)) < feeAmount)
            revert InsufficientAllowance();

        // CRITICAL: Transfer from resolvedBuyer (EOA)
        token.safeTransferFrom(resolvedBuyer, address(this), feeAmount);

        // Update PGA status
        pga.issuanceFeePaid = true;
        LibAppStorage.PGAStatus oldStatus = pga.status;

        // If collateral is also paid, notify logistics. Otherwise stay in CollateralPaid
        if (pga.collateralPaid) {
            pga.status = LibAppStorage.PGAStatus.LogisticsNotified;
        }

        emit PGAStatusChanged(pgaId, oldStatus, pga.status, block.timestamp);
        emit IssuanceFeePaid(
            pgaId,
            pga.buyer,
            address(this),
            feeAmount,
            block.timestamp
        );
    }

    /**
     * @notice Logistics partner takes up the application
     * @param pgaId The ID of the PGA
     */
    function takeUpPGA(string calldata pgaId) external whenNotPaused {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        LibAppStorage.PoolGuaranteeApplication storage pga = s.pgas[pgaId];

        if (pga.status != LibAppStorage.PGAStatus.LogisticsNotified)
            revert InvalidPGAStatus();

        // For MVP, we let any verified logistics partner (if we had a role)
        // take it up. For now, anyone can call it as long as they provide the attestation.
        LibAppStorage.PGAStatus oldStatus = pga.status;
        pga.status = LibAppStorage.PGAStatus.LogisticsTakeup;
        pga.logisticsPartner = msg.sender;

        emit PGAStatusChanged(pgaId, oldStatus, pga.status, block.timestamp);
    }

    /**
     * @notice Logistics partner attests that goods have been shipped
     */
    function confirmGoodsShipped(string calldata pgaId) external whenNotPaused {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        LibAppStorage.PoolGuaranteeApplication storage pga = s.pgas[pgaId];

        if (pga.status != LibAppStorage.PGAStatus.LogisticsTakeup)
            revert InvalidPGAStatus();
        if (msg.sender != pga.logisticsPartner) revert("Only take-up partner");

        LibAppStorage.PGAStatus oldStatus = pga.status;
        pga.status = LibAppStorage.PGAStatus.GoodsShipped;

        emit PGAStatusChanged(pgaId, oldStatus, pga.status, block.timestamp);
    }

    /**
     * @notice Logistics partner attests that goods have been delivered
     */
    function confirmGoodsDelivered(
        string calldata pgaId
    ) external whenNotPaused {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        LibAppStorage.PoolGuaranteeApplication storage pga = s.pgas[pgaId];

        if (pga.status != LibAppStorage.PGAStatus.BalancePaymentPaid)
            revert InvalidPGAStatus();
        if (msg.sender != pga.logisticsPartner) revert("Only take-up partner");
        if (!pga.balancePaymentPaid) revert("Balance not paid");

        LibAppStorage.PGAStatus oldStatus = pga.status;
        pga.status = LibAppStorage.PGAStatus.GoodsDelivered;

        emit PGAStatusChanged(pgaId, oldStatus, pga.status, block.timestamp);
    }

    /**
     * @notice Buyer pays balance amount
     * @dev Transfers balance payment to Treasury Pool, confirms payment
     */
    function payBalancePayment(
        string calldata pgaId
    ) external whenNotPaused nonReentrant {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        LibAppStorage.PoolGuaranteeApplication storage pga = s.pgas[pgaId];

        // Validation
        if (pga.status == LibAppStorage.PGAStatus.None) revert PGANotFound();
        if (pga.status != LibAppStorage.PGAStatus.GoodsShipped)
            revert InvalidPGAStatus();

        address resolvedBuyer = LibAddressResolver.resolveToEOA(msg.sender);
        address pgaBuyer = LibAddressResolver.resolveToEOA(pga.buyer);

        if (resolvedBuyer != pgaBuyer) revert OnlyBuyerAllowed();
        if (pga.balancePaymentPaid) revert BalanceAlreadyPaid();
        if (!pga.collateralPaid) revert CollateralNotPaid(); // Ensure collateral was paid first

        // Calculate balance payment (trade value - collateral)
        // Safe check: collateral should always be less than trade value (validated in createPGA)
        if (pga.collateralAmount >= pga.tradeValue) revert InvalidAmount();
        uint256 balanceAmount = pga.tradeValue - pga.collateralAmount;
        if (balanceAmount == 0) revert InvalidAmount(); // Must have balance to pay

        // Transfer balance to Treasury Pool (this contract)
        IERC20 usdcToken = IERC20(s.usdcToken);

        // FEAT: Use resolvedBuyer for funds transfer
        if (usdcToken.balanceOf(resolvedBuyer) < balanceAmount)
            revert InsufficientBalance();
        if (usdcToken.allowance(resolvedBuyer, address(this)) < balanceAmount)
            revert InsufficientAllowance();

        usdcToken.safeTransferFrom(resolvedBuyer, address(this), balanceAmount);

        // Update PGA status to BalancePaymentPaid
        pga.balancePaymentPaid = true;
        LibAppStorage.PGAStatus oldStatus = pga.status;
        pga.status = LibAppStorage.PGAStatus.BalancePaymentPaid;

        emit PGAStatusChanged(pgaId, oldStatus, pga.status, block.timestamp);
        emit BalancePaymentReceived(
            pgaId,
            pga.buyer,
            balanceAmount,
            block.timestamp
        );
    }

    /**
     * @notice Issue certificate after balance payment confirmed
     * @dev Complete the trade lifecycle
     */
    function issueCertificate(
        string calldata pgaId
    ) external whenNotPaused nonReentrant {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        LibAppStorage.PoolGuaranteeApplication storage pga = s.pgas[pgaId];

        // Validation
        if (pga.status == LibAppStorage.PGAStatus.None) revert PGANotFound();
        if (pga.status != LibAppStorage.PGAStatus.BalancePaymentPaid)
            revert InvalidPGAStatus();
        if (pga.certificateIssuedAt != 0) revert CertificateAlreadyIssued();

        // Access control: Only buyer or contract owner can issue certificate
        address resolvedCaller = LibAddressResolver.resolveToEOA(msg.sender);
        address pgaBuyer = LibAddressResolver.resolveToEOA(pga.buyer);
        bool isOwner = msg.sender == LibDiamond.contractOwner();

        if (resolvedCaller != pgaBuyer && !isOwner) revert OnlyBuyerAllowed();

        // Issue certificate
        pga.certificateIssuedAt = block.timestamp;
        LibAppStorage.PGAStatus oldStatus = pga.status;
        pga.status = LibAppStorage.PGAStatus.Completed;
        s.totalActivePGAs--;

        emit PGAStatusChanged(pgaId, oldStatus, pga.status, block.timestamp);
        emit PGACompleted(pgaId, pga.buyer, pga.seller, block.timestamp);

        // Emit certificate data for frontend
        _issueCertificate(pgaId);
    }

    /**
     * @notice Internal function to issue certificate
     * @dev Emits certificate data for frontend to generate PDF
     */
    function _issueCertificate(string memory pgaId) internal {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        LibAppStorage.PoolGuaranteeApplication storage pga = s.pgas[pgaId];

        // Certificate number format: PG-[timestamp]-[buyer_address_prefix]
        string memory certificateNumber = string(
            abi.encodePacked(
                "PG-",
                _uint2str(pga.certificateIssuedAt),
                "-",
                _addressToString(pga.buyer)
            )
        );

        emit CertificateIssued(
            pgaId,
            certificateNumber,
            pga.certificateIssuedAt,
            pga.buyer,
            pga.seller,
            pga.tradeValue,
            pga.guaranteeAmount,
            pga.duration,
            "Ethereum Sepolia", // Blockchain network
            address(this) // Smart contract address
        );
    }

    /**
     * @notice Owner resolves delivery dispute
     * @dev Emergency function to handle disputes in logistics flow
     */
    function resolveDeliveryDispute(
        string calldata pgaId,
        bool completeTransaction,
        string calldata /* resolution */
    ) external nonReentrant {
        LibDiamond.enforceIsContractOwner();

        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        LibAppStorage.PoolGuaranteeApplication storage pga = s.pgas[pgaId];

        if (pga.status == LibAppStorage.PGAStatus.None) revert PGANotFound();
        // Allow resolution for any logistics-related status if stuck
        if (
            uint256(pga.status) <
            uint256(LibAppStorage.PGAStatus.LogisticsNotified) ||
            pga.status == LibAppStorage.PGAStatus.Completed
        ) {
            revert InvalidPGAStatus();
        }

        IERC20 usdcToken = IERC20(s.usdcToken);

        if (completeTransaction) {
            // Owner decides in favor of seller - complete transaction
            LibAppStorage.PGAStatus oldStatus = pga.status;
            pga.status = LibAppStorage.PGAStatus.Completed;

            // Release payment to seller
            if (pga.collateralPaid && pga.balancePaymentPaid) {
                uint256 totalPayment = pga.tradeValue;
                // CEI Fix: Update state BEFORE external call
                pga.collateralPaid = false;
                pga.balancePaymentPaid = false;

                usdcToken.safeTransfer(pga.seller, totalPayment);

                emit SellerPaymentReleased(
                    pgaId,
                    pga.seller,
                    totalPayment,
                    block.timestamp
                );
            }

            if (oldStatus != LibAppStorage.PGAStatus.Completed) {
                s.totalActivePGAs--;
            }
            emit PGAStatusChanged(
                pgaId,
                oldStatus,
                LibAppStorage.PGAStatus.Completed,
                block.timestamp
            );
        } else {
            // Owner decides in favor of buyer - refund
            uint256 totalRefund = 0;
            if (pga.collateralPaid) {
                totalRefund += pga.collateralAmount;
            }
            if (pga.balancePaymentPaid) {
                totalRefund += (pga.tradeValue - pga.collateralAmount);
            }

            // CEI Fix: Update state BEFORE external call
            pga.collateralPaid = false;
            pga.balancePaymentPaid = false;

            LibAppStorage.PGAStatus oldStatus = pga.status;
            pga.status = LibAppStorage.PGAStatus.Rejected;

            if (totalRefund > 0) {
                usdcToken.safeTransfer(pga.buyer, totalRefund);

                emit CollateralRefunded(
                    pgaId,
                    pga.buyer,
                    totalRefund,
                    block.timestamp
                );
            }

            if (
                oldStatus != LibAppStorage.PGAStatus.Rejected &&
                oldStatus != LibAppStorage.PGAStatus.Expired &&
                oldStatus != LibAppStorage.PGAStatus.Completed
            ) {
                s.totalActivePGAs--;
            }
            emit PGAStatusChanged(
                pgaId,
                oldStatus,
                LibAppStorage.PGAStatus.Rejected,
                block.timestamp
            );
        }
    }

    /**
     * @notice Release payment to seller after successful completion
     * @dev Can be called by seller or contract owner after PGA is completed
     */
    function releasePaymentToSeller(
        string calldata pgaId
    ) external whenNotPaused nonReentrant {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        LibAppStorage.PoolGuaranteeApplication storage pga = s.pgas[pgaId];

        // Validation
        if (pga.status == LibAppStorage.PGAStatus.None) revert PGANotFound();
        if (pga.status != LibAppStorage.PGAStatus.Completed)
            revert InvalidPGAStatus();
        if (!pga.collateralPaid || !pga.balancePaymentPaid)
            revert InvalidPGAStatus();

        // Access control: Only seller or contract owner can trigger release
        address resolvedCaller = LibAddressResolver.resolveToEOA(msg.sender);
        address pgaSeller = LibAddressResolver.resolveToEOA(pga.seller);
        bool isOwner = msg.sender == LibDiamond.contractOwner();

        if (resolvedCaller != pgaSeller && !isOwner) revert OnlySellerAllowed();

        // Calculate total payment (collateral + balance)
        uint256 totalPayment = pga.tradeValue;

        // Reset payment flags to prevent double withdrawal (Effects)
        pga.collateralPaid = false;
        pga.balancePaymentPaid = false;

        // Transfer to seller (Interactions)
        IERC20 usdcToken = IERC20(s.usdcToken);
        usdcToken.safeTransfer(pga.seller, totalPayment);

        emit SellerPaymentReleased(
            pgaId,
            pga.seller,
            totalPayment,
            block.timestamp
        );
    }

    /**
     * @notice Authorize or deauthorize delivery person
     * @dev Only contract owner can manage delivery persons
     */
    function setDeliveryPerson(
        address deliveryPerson,
        bool authorized
    ) external {
        LibDiamond.enforceIsContractOwner();
        if (deliveryPerson == address(0)) revert ZeroAddress();

        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        // If authorizing and not already in the list, add to array
        if (authorized && !s.authorizedDeliveryPersons[deliveryPerson]) {
            s.deliveryPersonsList.push(deliveryPerson);
        }
        // Note: We don't remove from array when deauthorizing to preserve gas
        // The getter function will filter based on authorization status

        s.authorizedDeliveryPersons[deliveryPerson] = authorized;

        emit LogisticPartnerAuthorized(
            deliveryPerson,
            authorized,
            block.timestamp
        ); // Reuse event
    }

    /**
     * @notice Refund collateral to buyer if PGA is rejected after collateral payment
     * @dev Can be called by buyer or contract owner when status is Rejected and collateral was paid
     */
    function refundCollateral(
        string calldata pgaId
    ) external whenNotPaused nonReentrant {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        LibAppStorage.PoolGuaranteeApplication storage pga = s.pgas[pgaId];

        // Validation
        if (pga.status == LibAppStorage.PGAStatus.None) revert PGANotFound();
        if (
            pga.status != LibAppStorage.PGAStatus.Rejected &&
            pga.status != LibAppStorage.PGAStatus.Expired
        ) revert InvalidPGAStatus();
        if (!pga.collateralPaid) revert CollateralNotPaid();

        // Access control: Only buyer or contract owner can request refund
        address resolvedCaller = LibAddressResolver.resolveToEOA(msg.sender);
        address pgaBuyer = LibAddressResolver.resolveToEOA(pga.buyer);
        bool isOwner = msg.sender == LibDiamond.contractOwner();

        if (resolvedCaller != pgaBuyer && !isOwner) revert OnlyBuyerAllowed();

        // Refund collateral
        IERC20 usdcToken = IERC20(s.usdcToken);
        uint256 refundAmount = pga.collateralAmount;

        // Mark as refunded (reset collateral flag)
        pga.collateralPaid = false;

        usdcToken.safeTransfer(pga.buyer, refundAmount);

        emit CollateralRefunded(
            pgaId,
            pga.buyer,
            refundAmount,
            block.timestamp
        );
    }

    /**
     * @notice Cancel PGA before any payments if buyer changes mind
     * @dev Only buyer can cancel, only in Created or GuaranteeApproved status
     */
    function cancelPGA(
        string calldata pgaId
    ) external whenNotPaused nonReentrant {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        LibAppStorage.PoolGuaranteeApplication storage pga = s.pgas[pgaId];

        // Validation
        if (pga.status == LibAppStorage.PGAStatus.None) revert PGANotFound();
        if (
            pga.status != LibAppStorage.PGAStatus.Created &&
            pga.status != LibAppStorage.PGAStatus.GuaranteeApproved &&
            pga.status != LibAppStorage.PGAStatus.SellerApproved
        ) revert InvalidPGAStatus();
        if (pga.collateralPaid) revert InvalidPGAStatus(); // Cannot cancel after payment

        address resolvedCaller = LibAddressResolver.resolveToEOA(msg.sender);
        address pgaBuyer = LibAddressResolver.resolveToEOA(pga.buyer);

        if (resolvedCaller != pgaBuyer) revert OnlyBuyerAllowed();

        LibAppStorage.PGAStatus oldStatus = pga.status;
        pga.status = LibAppStorage.PGAStatus.Rejected;
        s.totalActivePGAs--;

        emit PGAStatusChanged(
            pgaId,
            oldStatus,
            LibAppStorage.PGAStatus.Rejected,
            block.timestamp
        );
    }

    /**
     * @notice Emergency cancel by owner - refunds payments if any
     * @dev Only contract owner for emergency situations
     */
    function emergencyCancelPGA(
        string calldata pgaId,
        string calldata /* reason */
    ) external nonReentrant {
        LibDiamond.enforceIsContractOwner();

        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        LibAppStorage.PoolGuaranteeApplication storage pga = s.pgas[pgaId];

        if (pga.status == LibAppStorage.PGAStatus.None) revert PGANotFound();
        if (pga.status == LibAppStorage.PGAStatus.Completed)
            revert InvalidPGAStatus();

        IERC20 usdcToken = IERC20(s.usdcToken);

        // Refund any payments made
        uint256 totalRefund = 0;
        if (pga.collateralPaid) {
            totalRefund += pga.collateralAmount;
        }
        if (pga.balancePaymentPaid) {
            totalRefund += (pga.tradeValue - pga.collateralAmount);
        }

        if (totalRefund > 0) {
            // CEI Fix: Update state BEFORE external call
            pga.collateralPaid = false;
            pga.balancePaymentPaid = false;

            usdcToken.safeTransfer(pga.buyer, totalRefund);
        }

        LibAppStorage.PGAStatus oldStatus = pga.status;
        pga.status = LibAppStorage.PGAStatus.Rejected;
        if (
            oldStatus != LibAppStorage.PGAStatus.Completed &&
            oldStatus != LibAppStorage.PGAStatus.Rejected &&
            oldStatus != LibAppStorage.PGAStatus.Expired
        ) {
            s.totalActivePGAs--;
        }

        emit PGAStatusChanged(
            pgaId,
            oldStatus,
            LibAppStorage.PGAStatus.Rejected,
            block.timestamp
        );
    }

    /**
     * @notice Get complete PGA details in a single call
     * @dev Returns all PGA fields - optimized for frontend with calldata for gas efficiency
     * @param pgaId The PGA identifier
     */
    function getPGA(
        string calldata pgaId
    )
        external
        view
        returns (
            string memory _pgaId,
            address buyer,
            address seller,
            uint256 tradeValue,
            uint256 guaranteeAmount,
            uint256 collateralAmount,
            uint256 issuanceFee,
            uint256 duration,
            uint256 votesFor,
            uint256 votesAgainst,
            uint256 createdAt,
            uint256 votingDeadline,
            LibAppStorage.PGAStatus status,
            bool collateralPaid,
            bool issuanceFeePaid,
            bool balancePaymentPaid,
            bool goodsShipped,
            string memory logisticPartner,
            address logisticsPartner,
            uint256 certificateIssuedAt,
            string memory deliveryAgreementId,
            string memory metadataURI,
            string memory companyName,
            string memory registrationNumber,
            string memory tradeDescription,
            string memory beneficiaryName,
            address beneficiaryWallet,
            string[] memory uploadedDocuments
        )
    {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        LibAppStorage.PoolGuaranteeApplication storage pga = s.pgas[pgaId];

        if (pga.status == LibAppStorage.PGAStatus.None) revert PGANotFound();

        return (
            pga.pgaId,
            pga.buyer,
            pga.seller,
            pga.tradeValue,
            pga.guaranteeAmount,
            pga.collateralAmount,
            pga.issuanceFee,
            pga.duration,
            pga.votesFor,
            pga.votesAgainst,
            pga.createdAt,
            pga.votingDeadline,
            pga.status,
            pga.collateralPaid,
            pga.issuanceFeePaid,
            pga.balancePaymentPaid,
            pga.goodsShipped,
            pga.logisticPartner,
            pga.logisticsPartner,
            pga.certificateIssuedAt,
            pga.deliveryAgreementId,
            pga.metadataURI,
            pga.companyName,
            pga.registrationNumber,
            pga.tradeDescription,
            pga.beneficiaryName,
            pga.beneficiaryWallet,
            pga.uploadedDocuments
        );
    }

    /**
     * @notice Get PGA uploaded documents
     */
    function getPGADocuments(
        string calldata pgaId
    ) external view returns (string[] memory) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        LibAppStorage.PoolGuaranteeApplication storage pga = s.pgas[pgaId];

        if (pga.status == LibAppStorage.PGAStatus.None) revert PGANotFound();

        return pga.uploadedDocuments;
    }

    /**
     * @notice Get all PGA IDs
     */
    function getAllPGAs() external view returns (string[] memory) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        return s.pgaIds;
    }

    /**
     * @notice Get active PGAs
     */
    function getActivePGAs() external view returns (string[] memory) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        // Count active PGAs
        uint256 activeCount = 0;
        for (uint256 i = 0; i < s.pgaIds.length; i++) {
            LibAppStorage.PoolGuaranteeApplication storage pga = s.pgas[
                s.pgaIds[i]
            ];
            if (
                pga.status != LibAppStorage.PGAStatus.None &&
                pga.status != LibAppStorage.PGAStatus.Completed &&
                pga.status != LibAppStorage.PGAStatus.Rejected
            ) {
                activeCount++;
            }
        }

        // Populate active PGAs array
        string[] memory activePGAs = new string[](activeCount);
        uint256 index = 0;
        for (uint256 i = 0; i < s.pgaIds.length; i++) {
            LibAppStorage.PoolGuaranteeApplication storage pga = s.pgas[
                s.pgaIds[i]
            ];
            if (
                pga.status != LibAppStorage.PGAStatus.None &&
                pga.status != LibAppStorage.PGAStatus.Completed &&
                pga.status != LibAppStorage.PGAStatus.Rejected
            ) {
                activePGAs[index] = s.pgaIds[i];
                index++;
            }
        }

        return activePGAs;
    }

    /**
     * @notice Get PGAs by buyer
     */
    function getPGAsByBuyer(
        address buyer
    ) external view returns (string[] memory) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        address resolvedBuyer = LibAddressResolver.resolveToEOA(buyer);

        // Count buyer's PGAs
        uint256 count = 0;
        for (uint256 i = 0; i < s.pgaIds.length; i++) {
            if (
                LibAddressResolver.resolveToEOA(s.pgas[s.pgaIds[i]].buyer) ==
                resolvedBuyer
            ) {
                count++;
            }
        }

        // Populate array
        string[] memory buyerPGAs = new string[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < s.pgaIds.length; i++) {
            if (
                LibAddressResolver.resolveToEOA(s.pgas[s.pgaIds[i]].buyer) ==
                resolvedBuyer
            ) {
                buyerPGAs[index] = s.pgaIds[i];
                index++;
            }
        }

        return buyerPGAs;
    }

    /**
     * @notice Get PGAs by seller
     */
    function getPGAsBySeller(
        address seller
    ) external view returns (string[] memory) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        address resolvedSeller = LibAddressResolver.resolveToEOA(seller);

        // Count seller's PGAs
        uint256 count = 0;
        for (uint256 i = 0; i < s.pgaIds.length; i++) {
            if (
                LibAddressResolver.resolveToEOA(s.pgas[s.pgaIds[i]].seller) ==
                resolvedSeller
            ) {
                count++;
            }
        }

        // Populate array
        string[] memory sellerPGAs = new string[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < s.pgaIds.length; i++) {
            if (
                LibAddressResolver.resolveToEOA(s.pgas[s.pgaIds[i]].seller) ==
                resolvedSeller
            ) {
                sellerPGAs[index] = s.pgaIds[i];
                index++;
            }
        }

        return sellerPGAs;
    }

    /**
     * @notice Get delivery agreement details
     */
    function getDeliveryAgreement(
        string memory agreementId
    )
        external
        view
        returns (
            string memory pgaId,
            address deliveryPerson,
            address buyer,
            uint256 createdAt,
            uint256 deadline,
            bool buyerConsent,
            uint256 buyerSignedAt,
            string memory deliveryNotes,
            string memory deliveryProofURI
        )
    {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        LibAppStorage.DeliveryAgreement storage agreement = s
            .deliveryAgreements[agreementId];

        return (
            agreement.pgaId,
            agreement.deliveryPerson,
            agreement.buyer,
            agreement.createdAt,
            agreement.deadline,
            agreement.buyerConsent,
            agreement.buyerSignedAt,
            agreement.deliveryNotes,
            agreement.deliveryProofURI
        );
    }

    /**
     * @notice Get vote status for a PGA
     */
    function getVoteStatusOnPGA(
        string memory pgaId,
        address voter
    ) external view returns (bool hasVoted, bool support) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        address resolvedVoter = LibAddressResolver.resolveToEOA(voter);

        hasVoted = s.hasVotedOnPGA[pgaId][resolvedVoter];
        support = s.pgaVoterSupport[pgaId][resolvedVoter];

        return (hasVoted, support);
    }

    /**
     * @notice Check if address is authorized logistics partner
     */
    function isAuthorizedLogisticsPartner(
        address partner
    ) external view returns (bool) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        return s.authorizedLogisticsPartners[partner];
    }

    /**
     * @notice Check if address is authorized delivery person
     */
    function isAuthorizedDeliveryPerson(
        address deliveryPerson
    ) external view returns (bool) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        return s.authorizedDeliveryPersons[deliveryPerson];
    }

    /**
     * @notice Get all logistics partners ever registered
     * @dev Returns all partners (authorized and deauthorized)
     * @dev Frontend should filter by calling isAuthorizedLogisticsPartner() for each
     * @return Array of logistics partner addresses
     */
    function getAllLogisticsPartners()
        external
        view
        returns (address[] memory)
    {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        return s.logisticsPartnersList;
    }

    /**
     * @notice Get all delivery persons ever registered
     * @dev Returns all delivery persons (authorized and deauthorized)
     * @dev Frontend should filter by calling isAuthorizedDeliveryPerson() for each
     * @return Array of delivery person addresses
     */
    function getAllDeliveryPersons() external view returns (address[] memory) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        return s.deliveryPersonsList;
    }

    /**
     * @notice Check if seller has voted on PGA
     */
    function hasSellerVoted(string memory pgaId) external view returns (bool) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        return s.sellerHasVoted[pgaId];
    }

    /**
     * @notice Get PGA statistics
     */
    function getPGAStats()
        external
        view
        returns (
            uint256 totalPGAs,
            uint256 activePGAs,
            uint256 completedPGAs,
            uint256 rejectedPGAs
        )
    {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        uint256 completed = 0;
        uint256 rejected = 0;

        for (uint256 i = 0; i < s.pgaIds.length; i++) {
            LibAppStorage.PoolGuaranteeApplication storage pga = s.pgas[
                s.pgaIds[i]
            ];
            if (pga.status == LibAppStorage.PGAStatus.Completed) {
                completed++;
            } else if (
                pga.status == LibAppStorage.PGAStatus.Rejected ||
                pga.status == LibAppStorage.PGAStatus.Expired
            ) {
                rejected++;
            }
        }

        return (s.totalPGAs, s.totalActivePGAs, completed, rejected);
    }

    // ==================== UTILITY FUNCTIONS ====================

    /**
     * @notice Convert uint256 to string
     */
    function _uint2str(uint256 _i) internal pure returns (string memory) {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint256 k = len;
        while (_i != 0) {
            k = k - 1;
            uint8 temp = (48 + uint8(_i - (_i / 10) * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }

    /**
     * @notice Convert address to string (first 8 characters)
     */
    function _addressToString(
        address _addr
    ) internal pure returns (string memory) {
        bytes32 value = bytes32(uint256(uint160(_addr)));
        bytes memory alphabet = "0123456789abcdef";
        bytes memory str = new bytes(8);

        for (uint256 i = 0; i < 4; i++) {
            str[i * 2] = alphabet[uint8(value[i + 12] >> 4)];
            str[1 + i * 2] = alphabet[uint8(value[i + 12] & 0x0f)];
        }

        return string(str);
    }
}
