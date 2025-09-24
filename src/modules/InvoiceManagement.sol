// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/utils/Counters.sol";
import "../libraries/TradeStructs.sol";
import "../BaseModule.sol";

/**
 * @title InvoiceManagement
 * @dev Module for managing invoices and payment tracking
 */
contract InvoiceManagement is BaseModule {
    using Counters for Counters.Counter;
    
    Counters.Counter private _invoiceIds;
    Counters.Counter private _lineItemIds;
    
    // Storage
    mapping(uint256 => TradeStructs.Invoice) public invoices;
    mapping(uint256 => TradeStructs.LineItem) public lineItems;
    mapping(uint256 => uint256) public contractInvoices;
    mapping(address => uint256[]) public userInvoices;

    // Events
    event InvoiceCreated(uint256 indexed invoiceId, uint256 indexed contractId, uint256 amount);
    event InvoiceStatusChanged(uint256 indexed invoiceId, TradeStructs.InvoiceStatus status);
    event InvoicePaid(uint256 indexed invoiceId, uint256 amount);
    event LineItemAdded(uint256 indexed invoiceId, uint256 indexed lineItemId);
    
    /**
     * @dev Create invoice with comprehensive details
     */
    function createInvoice(
        uint256 contractId,
        uint256 _amount,
        string calldata _currency,
        uint256 _dueDate,
        string calldata _description,
        string calldata _paymentInstructions,
        uint256 _taxAmount,
        uint256 _discountAmount
    ) external whenNotPaused returns (uint256) {
        require(contractId > 0, "Invalid contract ID");
        require(_amount > 0, "Invoice amount must be greater than zero");
        require(_dueDate > block.timestamp, "Invalid due date");
        require(_isCurrencySupported(_currency), "Currency not supported");
        require(contractInvoices[contractId] == 0, "Invoice already exists for this contract");
        
        _invoiceIds.increment();
        uint256 invoiceId = _invoiceIds.current();
        
        invoices[invoiceId] = TradeStructs.Invoice({
            id: invoiceId,
            contractId: contractId,
            issuer: msg.sender,
            recipient: address(0), // Will be set based on contract
            amount: _amount,
            currency: _currency,
            issueDate: block.timestamp,
            dueDate: _dueDate,
            status: TradeStructs.InvoiceStatus.Draft,
            description: _description,
            lineItems: new uint256[](0),
            taxAmount: _taxAmount,
            discountAmount: _discountAmount,
            paymentInstructions: _paymentInstructions,
            isPaid: false
        });
        
        contractInvoices[contractId] = invoiceId;
        userInvoices[msg.sender].push(invoiceId);
        
        emit InvoiceCreated(invoiceId, contractId, _amount);
        
        return invoiceId;
    }
    
    /**
     * @dev Add line item to invoice
     */
    function addLineItem(
        uint256 invoiceId,
        string calldata _description,
        uint256 _quantity,
        uint256 _unitPrice,
        string calldata _itemCode
    ) external returns (uint256) {
        require(invoices[invoiceId].id != 0, "Invoice does not exist");
        require(invoices[invoiceId].issuer == msg.sender, "Only issuer can add line items");
        require(invoices[invoiceId].status == TradeStructs.InvoiceStatus.Draft, "Cannot modify sent invoice");
        require(_quantity > 0, "Quantity must be greater than zero");
        require(_unitPrice > 0, "Unit price must be greater than zero");
        
        _lineItemIds.increment();
        uint256 lineItemId = _lineItemIds.current();
        
        uint256 totalPrice = _quantity * _unitPrice;
        
        lineItems[lineItemId] = TradeStructs.LineItem({
            description: _description,
            quantity: _quantity,
            unitPrice: _unitPrice,
            totalPrice: totalPrice,
            itemCode: _itemCode
        });
        
        invoices[invoiceId].lineItems.push(lineItemId);
        
        emit LineItemAdded(invoiceId, lineItemId);
        
        return lineItemId;
    }
    
    /**
     * @dev Send invoice to recipient
     */
    function sendInvoice(uint256 invoiceId, address recipient) external {
        require(invoices[invoiceId].id != 0, "Invoice does not exist");
        require(invoices[invoiceId].issuer == msg.sender, "Only issuer can send invoice");
        require(invoices[invoiceId].status == TradeStructs.InvoiceStatus.Draft, "Invoice already sent");
        require(recipient != address(0), "Invalid recipient address");
        
        invoices[invoiceId].recipient = recipient;
        invoices[invoiceId].status = TradeStructs.InvoiceStatus.Sent;
        
        userInvoices[recipient].push(invoiceId);
        
        emit InvoiceStatusChanged(invoiceId, TradeStructs.InvoiceStatus.Sent);
    }
    
    /**
     * @dev Accept invoice (by recipient)
     */
    function acceptInvoice(uint256 invoiceId) external {
        require(invoices[invoiceId].id != 0, "Invoice does not exist");
        require(invoices[invoiceId].recipient == msg.sender, "Only recipient can accept invoice");
        require(invoices[invoiceId].status == TradeStructs.InvoiceStatus.Sent, "Invoice not in sent status");
        
        invoices[invoiceId].status = TradeStructs.InvoiceStatus.Accepted;
        
        emit InvoiceStatusChanged(invoiceId, TradeStructs.InvoiceStatus.Accepted);
    }
    
    /**
     * @dev Mark invoice as paid
     */
    function markInvoicePaid(uint256 invoiceId) external {
        require(invoices[invoiceId].id != 0, "Invoice does not exist");
        require(
            invoices[invoiceId].issuer == msg.sender || 
            invoices[invoiceId].recipient == msg.sender,
            "Only invoice parties can mark as paid"
        );
        require(invoices[invoiceId].status == TradeStructs.InvoiceStatus.Accepted, "Invoice not accepted");
        require(!invoices[invoiceId].isPaid, "Invoice already paid");
        
        invoices[invoiceId].status = TradeStructs.InvoiceStatus.Paid;
        invoices[invoiceId].isPaid = true;
        
        emit InvoicePaid(invoiceId, invoices[invoiceId].amount);
        emit InvoiceStatusChanged(invoiceId, TradeStructs.InvoiceStatus.Paid);
    }
    
    /**
     * @dev Mark invoice as overdue (automated or manual)
     */
    function markInvoiceOverdue(uint256 invoiceId) external {
        require(invoices[invoiceId].id != 0, "Invoice does not exist");
        require(
            block.timestamp > invoices[invoiceId].dueDate,
            "Invoice not yet due"
        );
        require(!invoices[invoiceId].isPaid, "Invoice already paid");
        require(
            invoices[invoiceId].status == TradeStructs.InvoiceStatus.Sent ||
            invoices[invoiceId].status == TradeStructs.InvoiceStatus.Accepted,
            "Invalid status for overdue"
        );
        
        invoices[invoiceId].status = TradeStructs.InvoiceStatus.Overdue;
        
        emit InvoiceStatusChanged(invoiceId, TradeStructs.InvoiceStatus.Overdue);
    }
    
    /**
     * @dev Cancel invoice
     */
    function cancelInvoice(uint256 invoiceId, string calldata reason) external {
        require(invoices[invoiceId].id != 0, "Invoice does not exist");
        require(invoices[invoiceId].issuer == msg.sender, "Only issuer can cancel invoice");
        require(!invoices[invoiceId].isPaid, "Cannot cancel paid invoice");
        
        invoices[invoiceId].status = TradeStructs.InvoiceStatus.Cancelled;
        
        emit InvoiceStatusChanged(invoiceId, TradeStructs.InvoiceStatus.Cancelled);
    }
    
    // View functions
    function getInvoice(uint256 invoiceId) external view returns (TradeStructs.Invoice memory) {
        require(invoices[invoiceId].id != 0, "Invoice does not exist");
        return invoices[invoiceId];
    }
    
    function getInvoiceLineItems(uint256 invoiceId) external view returns (TradeStructs.LineItem[] memory) {
        require(invoices[invoiceId].id != 0, "Invoice does not exist");
        
        uint256[] memory lineItemIds = invoices[invoiceId].lineItems;
        TradeStructs.LineItem[] memory items = new TradeStructs.LineItem[](lineItemIds.length);
        
        for (uint256 i = 0; i < lineItemIds.length; i++) {
            items[i] = lineItems[lineItemIds[i]];
        }
        
        return items;
    }
    
    function getUserInvoices(address user) external view returns (uint256[] memory) {
        return userInvoices[user];
    }
    
    function getContractInvoice(uint256 contractId) external view returns (uint256) {
        return contractInvoices[contractId];
    }
    
    /**
     * @dev Get invoice total including tax and discount
     */
    function getInvoiceTotal(uint256 invoiceId) external view returns (uint256) {
        require(invoices[invoiceId].id != 0, "Invoice does not exist");
        
        TradeStructs.Invoice memory invoice = invoices[invoiceId];
        uint256 subtotal = invoice.amount;
        uint256 total = subtotal + invoice.taxAmount - invoice.discountAmount;
        
        return total;
    }
    
    /**
     * @dev Get overdue invoices for a user
     */
    function getOverdueInvoices(address user) external view returns (uint256[] memory) {
        uint256[] memory userInvoiceList = userInvoices[user];
        uint256[] memory overdueList = new uint256[](userInvoiceList.length);
        uint256 count = 0;
        
        for (uint256 i = 0; i < userInvoiceList.length; i++) {
            uint256 invoiceId = userInvoiceList[i];
            TradeStructs.Invoice memory invoice = invoices[invoiceId];
            
            if (block.timestamp > invoice.dueDate && 
                !invoice.isPaid && 
                invoice.status != TradeStructs.InvoiceStatus.Cancelled) {
                overdueList[count] = invoiceId;
                count++;
            }
        }
        
        // Resize array
        assembly {
            mstore(overdueList, count)
        }
        
        return overdueList;
    }
}