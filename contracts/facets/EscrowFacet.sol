// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../libraries/LibAppStorage.sol";
import "../libraries/LibDiamond.sol";

contract EscrowFacet {
    using SafeERC20 for IERC20;

    event EscrowCreated(
        uint256 indexed escrowId,
        address indexed importer,
        address indexed exporter,
        address arbitrator,
        uint256 totalAmount
    );
    event MilestoneCompleted(uint256 indexed escrowId, uint256 milestoneIndex);
    event MilestoneReleased(uint256 indexed escrowId, uint256 milestoneIndex, uint256 amount);
    event DisputeRaised(uint256 indexed escrowId, address indexed initiator, string reason);
    event DisputeResolved(uint256 indexed escrowId, address indexed arbitrator);
    event SubWalletAdded(uint256 indexed escrowId, address wallet, string role);
    event FundsDeposited(uint256 indexed escrowId, uint256 amount);
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
     * @notice Safe ETH transfer using low-level call
     */
    function _safeTransferETH(address to, uint256 amount) internal {
        (bool success, ) = payable(to).call{value: amount}("");
        require(success, "ETH transfer failed");
    }

    /**
     * @notice Calculate total milestone amount
     */
    function _calculateMilestoneTotal(uint256[] memory amounts) private pure returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            total += amounts[i];
        }
        return total;
    }

    /**
     * @notice Initialize escrow milestones
     */
    function _initializeMilestones(
        LibAppStorage.Escrow storage escrow,
        string[] memory titles,
        string[] memory descriptions,
        uint256[] memory amounts,
        uint256[] memory dueDates
    ) private {
        for (uint256 i = 0; i < titles.length; i++) {
            escrow.milestones.push(LibAppStorage.Milestone({
                title: titles[i],
                description: descriptions[i],
                amount: amounts[i],
                dueDate: dueDates[i],
                status: LibAppStorage.MilestoneStatus.Pending,
                released: false
            }));
        }
    }

    /**
     * @notice Handle escrow payment and finalize
     */
    function _handleEscrowPayment(
        LibAppStorage.Escrow storage escrow,
        address tokenAddress,
        uint256 totalAmount
    ) private {
        if (tokenAddress == address(0)) {
            require(msg.value == totalAmount, "Incorrect ETH amount");
        } else {
            IERC20(tokenAddress).safeTransferFrom(msg.sender, address(this), totalAmount);
        }
        escrow.status = LibAppStorage.EscrowStatus.Funded;
        
        emit EscrowCreated(
            escrow.id,
            escrow.importer,
            escrow.exporter,
            escrow.arbitrator,
            escrow.totalAmount
        );
    }

    /**
     * @notice Create escrow with milestones
     */
    function createEscrow(
        address _exporter,
        address _arbitrator,
        uint256 _arbitratorFee,
        uint256 _deadline,
        string memory _description,
        string memory _termsHash,
        string[] memory _milestonesTitles,
        string[] memory _milestonesDescriptions,
        uint256[] memory _milestonesAmounts,
        uint256[] memory _milestonesDueDates,
        address _tokenAddress
    ) external payable whenNotPaused returns (uint256) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        
        require(_exporter != address(0), "Invalid exporter");
        require(_arbitrator != address(0), "Invalid arbitrator");
        require(_deadline > block.timestamp, "Invalid deadline");
        require(_milestonesTitles.length == _milestonesAmounts.length, "Milestone mismatch");
        
        uint256 escrowId = ++s.escrowCounter;
        
        LibAppStorage.Escrow storage escrow = s.escrows[escrowId];
        escrow.id = escrowId;
        escrow.importer = msg.sender;
        escrow.exporter = _exporter;
        escrow.arbitrator = _arbitrator;
        escrow.totalAmount = _calculateMilestoneTotal(_milestonesAmounts) + _arbitratorFee;
        escrow.releasedAmount = 0;
        escrow.arbitratorFee = _arbitratorFee;
        escrow.deadline = _deadline;
        escrow.tokenAddress = _tokenAddress;
        escrow.status = LibAppStorage.EscrowStatus.Created;
        escrow.disputeStatus = LibAppStorage.DisputeStatus.None;
        escrow.description = _description;
        escrow.termsHash = _termsHash;
        
        _initializeMilestones(escrow, _milestonesTitles, _milestonesDescriptions, _milestonesAmounts, _milestonesDueDates);
        
        s.totalEscrows++;
        s.activeEscrows++;
        
        _handleEscrowPayment(escrow, _tokenAddress, escrow.totalAmount);
        
        return escrowId;
    }

    /**
     * @notice Add sub-wallet with role and permissions
     */
    function addSubWallet(
        uint256 _escrowId,
        address _walletAddress,
        string memory _role,
        string[] memory _permissions
    ) external {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        LibAppStorage.Escrow storage escrow = s.escrows[_escrowId];
        
        require(escrow.id > 0, "Escrow not found");
        require(
            msg.sender == escrow.importer || 
            msg.sender == escrow.exporter || 
            msg.sender == escrow.arbitrator,
            "Not authorized"
        );
        require(!escrow.isSubWallet[_walletAddress], "Already added");
        
        escrow.subWallets.push(_walletAddress);
        escrow.isSubWallet[_walletAddress] = true;
        escrow.subWalletRole[_walletAddress] = _role;
        escrow.subWalletPermissions[_walletAddress] = _permissions;
        
        emit SubWalletAdded(_escrowId, _walletAddress, _role);
    }

    /**
     * @notice Complete milestone (exporter)
     */
    function completeMilestone(uint256 _escrowId, uint256 _milestoneIndex) external whenNotPaused {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        LibAppStorage.Escrow storage escrow = s.escrows[_escrowId];
        
        require(escrow.id > 0, "Escrow not found");
        require(msg.sender == escrow.exporter, "Not exporter");
        require(_milestoneIndex < escrow.milestones.length, "Invalid milestone");
        require(
            escrow.milestones[_milestoneIndex].status == LibAppStorage.MilestoneStatus.Pending,
            "Milestone not pending"
        );
        
        escrow.milestones[_milestoneIndex].status = LibAppStorage.MilestoneStatus.Completed;
        escrow.status = LibAppStorage.EscrowStatus.InProgress;
        
        emit MilestoneCompleted(_escrowId, _milestoneIndex);
    }

    /**
     * @notice Release milestone payment (importer)
     */
    function releaseMilestonePayment(uint256 _escrowId, uint256 _milestoneIndex) external whenNotPaused {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        LibAppStorage.Escrow storage escrow = s.escrows[_escrowId];
        
        require(escrow.id > 0, "Escrow not found");
        require(msg.sender == escrow.importer, "Not importer");
        require(_milestoneIndex < escrow.milestones.length, "Invalid milestone");
        require(
            escrow.milestones[_milestoneIndex].status == LibAppStorage.MilestoneStatus.Completed,
            "Milestone not completed"
        );
        require(!escrow.milestones[_milestoneIndex].released, "Already released");
        
        uint256 amount = escrow.milestones[_milestoneIndex].amount;
        escrow.milestones[_milestoneIndex].released = true;
        escrow.milestones[_milestoneIndex].status = LibAppStorage.MilestoneStatus.Released;
        escrow.releasedAmount += amount;
        
        // Transfer funds to exporter
        if (escrow.tokenAddress == address(0)) {
            _safeTransferETH(escrow.exporter, amount);
        } else {
            IERC20(escrow.tokenAddress).safeTransfer(escrow.exporter, amount);
        }
        
        // Check if all milestones are released
        bool allReleased = true;
        for (uint256 i = 0; i < escrow.milestones.length; i++) {
            if (!escrow.milestones[i].released) {
                allReleased = false;
                break;
            }
        }
        
        if (allReleased) {
            escrow.status = LibAppStorage.EscrowStatus.Completed;
            s.activeEscrows--;
            
            // Release arbitrator fee
            if (escrow.tokenAddress == address(0)) {
                _safeTransferETH(escrow.arbitrator, escrow.arbitratorFee);
            } else {
                IERC20(escrow.tokenAddress).safeTransfer(escrow.arbitrator, escrow.arbitratorFee);
            }
        }
        
        emit MilestoneReleased(_escrowId, _milestoneIndex, amount);
    }

    /**
     * @notice Raise dispute
     */
    function raiseDispute(uint256 _escrowId, string memory _reason) external whenNotPaused {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        LibAppStorage.Escrow storage escrow = s.escrows[_escrowId];
        
        require(escrow.id > 0, "Escrow not found");
        require(
            msg.sender == escrow.importer || msg.sender == escrow.exporter,
            "Not authorized"
        );
        require(escrow.disputeStatus == LibAppStorage.DisputeStatus.None, "Dispute exists");
        
        escrow.status = LibAppStorage.EscrowStatus.Disputed;
        escrow.disputeStatus = LibAppStorage.DisputeStatus.Raised;
        
        emit DisputeRaised(_escrowId, msg.sender, _reason);
    }

    /**
     * @notice Resolve dispute (arbitrator only)
     */
    function resolveDispute(
        uint256 _escrowId,
        uint256[] memory _milestoneIndexes,
        bool[] memory _releaseToExporter
    ) external {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        LibAppStorage.Escrow storage escrow = s.escrows[_escrowId];
        
        require(escrow.id > 0, "Escrow not found");
        require(msg.sender == escrow.arbitrator, "Not arbitrator");
        require(escrow.disputeStatus == LibAppStorage.DisputeStatus.Raised, "No active dispute");
        require(_milestoneIndexes.length == _releaseToExporter.length, "Array mismatch");
        
        for (uint256 i = 0; i < _milestoneIndexes.length; i++) {
            uint256 idx = _milestoneIndexes[i];
            require(idx < escrow.milestones.length, "Invalid milestone");
            
            if (!escrow.milestones[idx].released) {
                uint256 amount = escrow.milestones[idx].amount;
                address recipient = _releaseToExporter[i] ? escrow.exporter : escrow.importer;
                
                escrow.milestones[idx].released = true;
                escrow.releasedAmount += amount;
                
                if (escrow.tokenAddress == address(0)) {
                    _safeTransferETH(recipient, amount);
                } else {
                    IERC20(escrow.tokenAddress).safeTransfer(recipient, amount);
                }
            }
        }
        
        escrow.disputeStatus = LibAppStorage.DisputeStatus.Resolved;
        escrow.status = LibAppStorage.EscrowStatus.Completed;
        s.activeEscrows--;
        
        // Pay arbitrator fee
        if (escrow.tokenAddress == address(0)) {
            _safeTransferETH(escrow.arbitrator, escrow.arbitratorFee);
        } else {
            IERC20(escrow.tokenAddress).safeTransfer(escrow.arbitrator, escrow.arbitratorFee);
        }
        
        emit DisputeResolved(_escrowId, msg.sender);
    }

    /**
     * @notice Get escrow details
     */
    function getEscrowDetails(uint256 _escrowId) external view returns (
        address importer,
        address exporter,
        address arbitrator,
        uint256 totalAmount,
        uint256 releasedAmount,
        uint256 arbitratorFee,
        uint256 deadline,
        LibAppStorage.EscrowStatus status,
        LibAppStorage.DisputeStatus disputeStatus,
        string memory description,
        string memory termsHash
    ) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        LibAppStorage.Escrow storage escrow = s.escrows[_escrowId];
        
        return (
            escrow.importer,
            escrow.exporter,
            escrow.arbitrator,
            escrow.totalAmount,
            escrow.releasedAmount,
            escrow.arbitratorFee,
            escrow.deadline,
            escrow.status,
            escrow.disputeStatus,
            escrow.description,
            escrow.termsHash
        );
    }

    /**
     * @notice Get milestone info
     */
    function getMilestone(uint256 _escrowId, uint256 _index) external view returns (
        string memory title,
        string memory description,
        uint256 amount,
        uint256 dueDate,
        LibAppStorage.MilestoneStatus status,
        bool released
    ) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        LibAppStorage.Milestone storage milestone = s.escrows[_escrowId].milestones[_index];
        
        return (
            milestone.title,
            milestone.description,
            milestone.amount,
            milestone.dueDate,
            milestone.status,
            milestone.released
        );
    }

    /**
     * @notice Get all milestones
     */
    function getMilestones(uint256 _escrowId) external view returns (LibAppStorage.Milestone[] memory) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        return s.escrows[_escrowId].milestones;
    }

    /**
     * @notice Get sub-wallets
     */
    function getSubWallets(uint256 _escrowId) external view returns (address[] memory) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        return s.escrows[_escrowId].subWallets;
    }

    /**
     * @notice Check sub-wallet permission
     */
    function hasPermission(
        uint256 _escrowId,
        address _wallet,
        string memory _permission
    ) external view returns (bool) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        LibAppStorage.Escrow storage escrow = s.escrows[_escrowId];
        
        if (!escrow.isSubWallet[_wallet]) return false;
        
        string[] memory permissions = escrow.subWalletPermissions[_wallet];
        for (uint256 i = 0; i < permissions.length; i++) {
            if (keccak256(bytes(permissions[i])) == keccak256(bytes(_permission))) {
                return true;
            }
        }
        return false;
    }

    /**
     * @notice Get escrow statistics
     */
    function getEscrowStats() external view returns (
        uint256 totalEscrows,
        uint256 activeEscrows,
        uint256 completedEscrows
    ) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        return (
            s.totalEscrows,
            s.activeEscrows,
            s.totalEscrows - s.activeEscrows
        );
    }
}
