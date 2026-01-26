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
    ) external {
        LibDiamond.enforceIsContractOwner();
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        s.authorizedLogisticsPartners[partner] = authorized;
        emit LogisticPartnerAuthorized(partner, authorized, block.timestamp);
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
        string calldata pgaId
    ) external whenNotPaused nonReentrant {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        LibAppStorage.PoolGuaranteeApplication storage pga = s.pgas[pgaId];

        // Validation
        if (pga.status == LibAppStorage.PGAStatus.None) revert PGANotFound();
        if (pga.status != LibAppStorage.PGAStatus.SellerApproved)
            revert InvalidPGAStatus();

        address resolvedBuyer = LibAddressResolver.resolveToEOA(msg.sender);
        address pgaBuyer = LibAddressResolver.resolveToEOA(pga.buyer);

        if (resolvedBuyer != pgaBuyer) revert OnlyBuyerAllowed();
        if (pga.collateralPaid) revert CollateralAlreadyPaid();

        // Transfer collateral to Treasury Pool (this contract)
        IERC20 usdcToken = IERC20(s.usdcToken);
        uint256 collateralAmount = pga.collateralAmount;

        if (usdcToken.balanceOf(msg.sender) < collateralAmount)
            revert InsufficientBalance();
        if (usdcToken.allowance(msg.sender, address(this)) < collateralAmount)
            revert InsufficientAllowance();

        usdcToken.safeTransferFrom(msg.sender, address(this), collateralAmount);

        // Update PGA status
        pga.collateralPaid = true;
        LibAppStorage.PGAStatus oldStatus = pga.status;
        pga.status = LibAppStorage.PGAStatus.CollateralPaid;

        emit PGAStatusChanged(
            pgaId,
            oldStatus,
            LibAppStorage.PGAStatus.CollateralPaid,
            block.timestamp
        );
        emit CollateralPaid(
            pgaId,
            pga.buyer,
            collateralAmount,
            block.timestamp
        );
    }

    /**
     * @notice Logistics partner confirms goods shipment
     * @dev Only authorized logistics partners can confirm shipment
     */
    function confirmGoodsShipped(
        string calldata pgaId,
        string calldata logisticPartnerName
    ) external whenNotPaused nonReentrant {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        LibAppStorage.PoolGuaranteeApplication storage pga = s.pgas[pgaId];

        // Validation
        if (pga.status == LibAppStorage.PGAStatus.None) revert PGANotFound();
        if (pga.status != LibAppStorage.PGAStatus.CollateralPaid)
            revert InvalidPGAStatus();
        if (!s.authorizedLogisticsPartners[msg.sender])
            revert OnlyLogisticsPartner();
        if (pga.goodsShipped) revert InvalidPGAStatus();

        // Update PGA status
        pga.goodsShipped = true;
        pga.logisticPartner = logisticPartnerName;
        LibAppStorage.PGAStatus oldStatus = pga.status;
        pga.status = LibAppStorage.PGAStatus.GoodsShipped;

        emit PGAStatusChanged(
            pgaId,
            oldStatus,
            LibAppStorage.PGAStatus.GoodsShipped,
            block.timestamp
        );
        emit GoodsShipped(
            pgaId,
            msg.sender,
            logisticPartnerName,
            block.timestamp
        );
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

        if (usdcToken.balanceOf(msg.sender) < balanceAmount)
            revert InsufficientBalance();
        if (usdcToken.allowance(msg.sender, address(this)) < balanceAmount)
            revert InsufficientAllowance();

        usdcToken.safeTransferFrom(msg.sender, address(this), balanceAmount);

        // Update PGA status to BalancePaymentPaid
        pga.balancePaymentPaid = true;
        LibAppStorage.PGAStatus oldStatus = pga.status;
        pga.status = LibAppStorage.PGAStatus.BalancePaymentPaid;

        emit PGAStatusChanged(
            pgaId,
            oldStatus,
            LibAppStorage.PGAStatus.BalancePaymentPaid,
            block.timestamp
        );
        emit BalancePaymentReceived(
            pgaId,
            pga.buyer,
            balanceAmount,
            block.timestamp
        );
    }

    /**
     * @notice Issue certificate after balance payment confirmed
     * @dev Can be called by buyer or contract owner after balance payment confirmation
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
        pga.status = LibAppStorage.PGAStatus.CertificateIssued;

        emit PGAStatusChanged(
            pgaId,
            oldStatus,
            LibAppStorage.PGAStatus.CertificateIssued,
            block.timestamp
        );

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
     * @notice Delivery person creates delivery agreement
     * @dev Creates agreement awaiting buyer consent
     */
    function createDeliveryAgreement(
        string calldata agreementId,
        string calldata pgaId,
        uint256 agreementDeadline,
        string calldata deliveryNotes,
        string calldata deliveryProofURI
    ) external whenNotPaused nonReentrant {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        LibAppStorage.PoolGuaranteeApplication storage pga = s.pgas[pgaId];

        // Validation
        if (pga.status == LibAppStorage.PGAStatus.None) revert PGANotFound();
        if (pga.status != LibAppStorage.PGAStatus.CertificateIssued)
            revert InvalidPGAStatus();
        if (bytes(agreementId).length == 0) revert InvalidString();
        if (s.deliveryAgreements[agreementId].createdAt != 0)
            revert DeliveryAgreementExists();
        if (agreementDeadline <= block.timestamp) revert InvalidDuration();

        // Only authorized delivery persons or logistics partners can create delivery agreements
        if (
            !s.authorizedDeliveryPersons[msg.sender] &&
            !s.authorizedLogisticsPartners[msg.sender]
        ) revert NotAuthorized();

        // Create delivery agreement
        LibAppStorage.DeliveryAgreement storage agreement = s
            .deliveryAgreements[agreementId];
        agreement.agreementId = agreementId;
        agreement.pgaId = pgaId;
        agreement.deliveryPerson = msg.sender;
        agreement.buyer = pga.buyer;
        agreement.createdAt = block.timestamp;
        agreement.deadline = agreementDeadline;
        agreement.buyerConsent = false;
        agreement.buyerSignedAt = 0;
        agreement.deliveryNotes = deliveryNotes;
        agreement.deliveryProofURI = deliveryProofURI;

        // Link agreement to PGA
        s.pgaToDeliveryAgreements[pgaId].push(agreementId);

        // Update PGA status
        LibAppStorage.PGAStatus oldStatus = pga.status;
        pga.status = LibAppStorage.PGAStatus.DeliveryAwaitingConsent;
        pga.deliveryAgreementId = agreementId;

        emit PGAStatusChanged(
            pgaId,
            oldStatus,
            LibAppStorage.PGAStatus.DeliveryAwaitingConsent,
            block.timestamp
        );
        emit DeliveryAgreementCreated(
            agreementId,
            pgaId,
            msg.sender,
            pga.buyer,
            block.timestamp,
            agreementDeadline,
            deliveryNotes
        );
    }

    /**
     * @notice Buyer gives consent to delivery agreement
     * @dev Only buyer can sign, completes the PGA
     */
    function buyerConsentToDelivery(
        string calldata agreementId,
        bool consent
    ) external whenNotPaused nonReentrant {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        LibAppStorage.DeliveryAgreement storage agreement = s
            .deliveryAgreements[agreementId];

        // Validation
        if (agreement.createdAt == 0) revert DeliveryAgreementNotFound();
        if (agreement.buyerConsent) revert BuyerConsentAlreadyGiven();

        address resolvedBuyer = LibAddressResolver.resolveToEOA(msg.sender);
        address agreementBuyer = LibAddressResolver.resolveToEOA(
            agreement.buyer
        );

        if (resolvedBuyer != agreementBuyer) revert OnlyBuyerAllowed();
        if (block.timestamp > agreement.deadline) revert PGAExpired();

        LibAppStorage.PoolGuaranteeApplication storage pga = s.pgas[
            agreement.pgaId
        ];
        if (pga.status != LibAppStorage.PGAStatus.DeliveryAwaitingConsent)
            revert InvalidPGAStatus();

        if (consent) {
            // Update agreement
            agreement.buyerConsent = true;
            agreement.buyerSignedAt = block.timestamp;

            // Complete PGA
            LibAppStorage.PGAStatus oldStatus = pga.status;
            pga.status = LibAppStorage.PGAStatus.Completed;
            s.totalActivePGAs--;

            emit BuyerConsentGiven(
                agreementId,
                agreement.pgaId,
                agreement.buyer,
                block.timestamp
            );
            emit PGAStatusChanged(
                agreement.pgaId,
                oldStatus,
                LibAppStorage.PGAStatus.Completed,
                block.timestamp
            );
            emit PGACompleted(
                agreement.pgaId,
                pga.buyer,
                pga.seller,
                block.timestamp
            );
        } else {
            // Buyer rejected delivery - mark as disputed
            // CRITICAL FIX: Set to Disputed, not Rejected. Rejected allows immediate refund.
            // Disputed requires owner intervention via resolveDeliveryDispute.
            LibAppStorage.PGAStatus oldStatus = pga.status;
            pga.status = LibAppStorage.PGAStatus.Disputed;
            // Do NOT decrease totalActivePGAs yet as it is still active/disputed

            emit PGAStatusChanged(
                agreement.pgaId,
                oldStatus,
                LibAppStorage.PGAStatus.Disputed,
                block.timestamp
            );
        }
    }

    /**
     * @notice Owner resolves delivery dispute when buyer rejects delivery
     * @dev Emergency function to handle delivery disputes
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
        // Allow resolution for Disputed status as well
        if (
            pga.status != LibAppStorage.PGAStatus.Disputed &&
            pga.status != LibAppStorage.PGAStatus.DeliveryAwaitingConsent
        ) {
            // We allow owner to intervene in Disputed or AwaitingConsent (if stuck)
            // But primarily for Disputed
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
     * @notice Authorize or deauthorize logistics partner
     * @dev Only contract owner can manage logistics partners
     */
    function setLogisticsPartner(address partner, bool authorized) external {
        LibDiamond.enforceIsContractOwner();
        if (partner == address(0)) revert ZeroAddress();

        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        s.authorizedLogisticsPartners[partner] = authorized;

        emit LogisticPartnerAuthorized(partner, authorized, block.timestamp);
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
     * @notice Get PGA details
     * @param pgaId The PGA identifier
     */
    function getPGA(
        string memory pgaId
    )
        external
        view
        returns (
            address buyer,
            address seller,
            uint256 tradeValue,
            uint256 guaranteeAmount,
            uint256 collateralAmount,
            uint256 duration,
            uint256 votesFor,
            uint256 votesAgainst,
            uint256 createdAt,
            uint256 votingDeadline,
            LibAppStorage.PGAStatus status,
            bool collateralPaid,
            bool balancePaymentPaid,
            bool goodsShipped,
            string memory logisticPartner,
            uint256 certificateIssuedAt,
            string memory deliveryAgreementId,
            string memory metadataURI
        )
    {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        LibAppStorage.PoolGuaranteeApplication storage pga = s.pgas[pgaId];

        return (
            pga.buyer,
            pga.seller,
            pga.tradeValue,
            pga.guaranteeAmount,
            pga.collateralAmount,
            pga.duration,
            pga.votesFor,
            pga.votesAgainst,
            pga.createdAt,
            pga.votingDeadline,
            pga.status,
            pga.collateralPaid,
            pga.balancePaymentPaid,
            pga.goodsShipped,
            pga.logisticPartner,
            pga.certificateIssuedAt,
            pga.deliveryAgreementId,
            pga.metadataURI
        );
    }

    /**
     * @notice Get PGA uploaded documents
     */
    function getPGADocuments(
        string memory pgaId
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
                pga.status == LibAppStorage.PGAStatus.Created ||
                pga.status == LibAppStorage.PGAStatus.GuaranteeApproved ||
                pga.status == LibAppStorage.PGAStatus.SellerApproved ||
                pga.status == LibAppStorage.PGAStatus.CollateralPaid ||
                pga.status == LibAppStorage.PGAStatus.GoodsShipped ||
                pga.status == LibAppStorage.PGAStatus.BalancePaymentPaid ||
                pga.status == LibAppStorage.PGAStatus.CertificateIssued ||
                pga.status == LibAppStorage.PGAStatus.DeliveryAwaitingConsent
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
                pga.status == LibAppStorage.PGAStatus.Created ||
                pga.status == LibAppStorage.PGAStatus.GuaranteeApproved ||
                pga.status == LibAppStorage.PGAStatus.SellerApproved ||
                pga.status == LibAppStorage.PGAStatus.CollateralPaid ||
                pga.status == LibAppStorage.PGAStatus.GoodsShipped ||
                pga.status == LibAppStorage.PGAStatus.BalancePaymentPaid ||
                pga.status == LibAppStorage.PGAStatus.CertificateIssued ||
                pga.status == LibAppStorage.PGAStatus.DeliveryAwaitingConsent
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
