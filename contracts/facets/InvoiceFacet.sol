// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../libraries/LibAppStorage.sol";
import "../libraries/LibDiamond.sol";

contract InvoiceFacet {
    using SafeERC20 for IERC20;

    event InvoiceCreated(
        uint256 indexed invoiceId,
        string invoiceNumber,
        address indexed payer,
        address indexed payee,
        uint256 amount
    );
    event InvoiceViewed(uint256 indexed invoiceId, address indexed viewer);
    event InvoicePaid(uint256 indexed invoiceId, address indexed payer, uint256 amount);
    event InvoiceCancelled(uint256 indexed invoiceId);
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
     * @notice Create invoice
     */
    function createInvoice(
        string memory _invoiceNumber,
        address _payer,
        uint256 _amount,
        address _tokenAddress,
        uint256 _dueDate,
        string memory _description,
        string memory _termsHash
    ) external whenNotPaused returns (uint256) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        
        require(bytes(_invoiceNumber).length > 0, "Invalid invoice number");
        require(_payer != address(0), "Invalid payer");
        require(_amount > 0, "Invalid amount");
        require(_dueDate > block.timestamp, "Invalid due date");
        require(s.invoiceNumberToId[_invoiceNumber] == 0, "Invoice number exists");
        
        uint256 invoiceId = ++s.invoiceCounter;
        
        s.invoices[invoiceId] = LibAppStorage.Invoice({
            id: invoiceId,
            invoiceNumber: _invoiceNumber,
            payer: _payer,
            payee: msg.sender,
            amount: _amount,
            tokenAddress: _tokenAddress,
            dueDate: _dueDate,
            status: LibAppStorage.InvoiceStatus.Sent,
            paidAt: 0,
            description: _description,
            termsHash: _termsHash
        });
        
        s.invoiceNumberToId[_invoiceNumber] = invoiceId;
        s.totalInvoices++;
        
        emit InvoiceCreated(invoiceId, _invoiceNumber, _payer, msg.sender, _amount);
        
        return invoiceId;
    }

    /**
     * @notice Pay invoice
     */
    function payInvoice(uint256 _invoiceId) external payable whenNotPaused {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        LibAppStorage.Invoice storage invoice = s.invoices[_invoiceId];
        
        require(invoice.id > 0, "Invoice not found");
        require(msg.sender == invoice.payer, "Not payer");
        require(invoice.status != LibAppStorage.InvoiceStatus.Paid, "Already paid");
        require(invoice.status != LibAppStorage.InvoiceStatus.Cancelled, "Cancelled");
        
        if (invoice.tokenAddress == address(0)) {
            require(msg.value == invoice.amount, "Incorrect ETH amount");
            
            // CEI Pattern: Update state before external call
            invoice.status = LibAppStorage.InvoiceStatus.Paid;
            invoice.paidAt = block.timestamp;
            
            // Use call() instead of transfer() to prevent gas limit DoS
            (bool success, ) = payable(invoice.payee).call{value: invoice.amount}("");
            require(success, "ETH transfer failed");
        } else {
            IERC20(invoice.tokenAddress).safeTransferFrom(msg.sender, invoice.payee, invoice.amount);
            
            invoice.status = LibAppStorage.InvoiceStatus.Paid;
            invoice.paidAt = block.timestamp;
        }
        
        emit InvoicePaid(_invoiceId, msg.sender, invoice.amount);
    }

    /**
     * @notice Mark invoice as viewed
     */
    function markInvoiceViewed(uint256 _invoiceId) external {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        LibAppStorage.Invoice storage invoice = s.invoices[_invoiceId];
        
        require(invoice.id > 0, "Invoice not found");
        require(msg.sender == invoice.payer, "Not payer");
        
        if (invoice.status == LibAppStorage.InvoiceStatus.Sent) {
            invoice.status = LibAppStorage.InvoiceStatus.Viewed;
        }
        
        emit InvoiceViewed(_invoiceId, msg.sender);
    }

    /**
     * @notice Cancel invoice (payee only)
     */
    function cancelInvoice(uint256 _invoiceId) external whenNotPaused {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        LibAppStorage.Invoice storage invoice = s.invoices[_invoiceId];
        
        require(invoice.id > 0, "Invoice not found");
        require(msg.sender == invoice.payee, "Not payee");
        require(invoice.status != LibAppStorage.InvoiceStatus.Paid, "Already paid");
        
        invoice.status = LibAppStorage.InvoiceStatus.Cancelled;
        
        emit InvoiceCancelled(_invoiceId);
    }

    /**
     * @notice Get invoice details
     */
    function getInvoice(uint256 _invoiceId) external view returns (
        string memory invoiceNumber,
        address payer,
        address payee,
        uint256 amount,
        address tokenAddress,
        uint256 dueDate,
        LibAppStorage.InvoiceStatus status,
        uint256 paidAt,
        string memory description
    ) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        LibAppStorage.Invoice storage invoice = s.invoices[_invoiceId];
        
        return (
            invoice.invoiceNumber,
            invoice.payer,
            invoice.payee,
            invoice.amount,
            invoice.tokenAddress,
            invoice.dueDate,
            invoice.status,
            invoice.paidAt,
            invoice.description
        );
    }

    /**
     * @notice Get invoice by number
     */
    function getInvoiceByNumber(string memory _invoiceNumber) external view returns (uint256) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        return s.invoiceNumberToId[_invoiceNumber];
    }

    /**
     * @notice Update invoice to overdue if past due date (anyone can call)
     */
    function updateOverdueStatus(uint256 _invoiceId) external {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        LibAppStorage.Invoice storage invoice = s.invoices[_invoiceId];
        
        require(invoice.id > 0, "Invoice not found");
        require(
            invoice.status != LibAppStorage.InvoiceStatus.Paid &&
            invoice.status != LibAppStorage.InvoiceStatus.Cancelled,
            "Invoice already settled"
        );
        
        if (block.timestamp > invoice.dueDate && invoice.status != LibAppStorage.InvoiceStatus.Overdue) {
            invoice.status = LibAppStorage.InvoiceStatus.Overdue;
        }
    }

    /**
     * @notice Check if invoice is overdue
     */
    function isOverdue(uint256 _invoiceId) external view returns (bool) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        LibAppStorage.Invoice storage invoice = s.invoices[_invoiceId];
        
        return (
            invoice.status != LibAppStorage.InvoiceStatus.Paid &&
            invoice.status != LibAppStorage.InvoiceStatus.Cancelled &&
            block.timestamp > invoice.dueDate
        );
    }

    /**
     * @notice Get invoice statistics
     */
    function getInvoiceStats() external view returns (
        uint256 totalInvoices,
        uint256 paidInvoices,
        uint256 pendingInvoices
    ) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        
        uint256 paid = 0;
        uint256 pending = 0;
        
        for (uint256 i = 1; i <= s.invoiceCounter; i++) {
            if (s.invoices[i].status == LibAppStorage.InvoiceStatus.Paid) {
                paid++;
            } else if (
                s.invoices[i].status == LibAppStorage.InvoiceStatus.Sent ||
                s.invoices[i].status == LibAppStorage.InvoiceStatus.Viewed
            ) {
                pending++;
            }
        }
        
        return (s.totalInvoices, paid, pending);
    }
}
