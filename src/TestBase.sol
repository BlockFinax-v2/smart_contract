// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "./BlockFinaxtradePlatform.sol";
import "../src/modules/ContractManagement.sol";
import "../src/modules/DocumentManagement.sol";
import "../src/modules/InvoiceManagement.sol";
import "../src/modules/ShipmentManagement.sol";
import "../src/modules/RiskManagement.sol";
import "../src/modules/DisputeManagement.sol";
import "../src/libraries/TradeStructs.sol";

/**
 * @title Base Test Contract
 * @dev Provides common setup and utilities for all tests
 */
contract BaseTest is Test {
    
    // Main contracts
    BlockFinaxTradePlatform public platform;
    ContractManagement public contractManagement;
    DocumentManagement public documentManagement;
    InvoiceManagement public invoiceManagement;
    ShipmentManagement public shipmentManagement;
    RiskManagement public riskManagement;
    DisputeManagement public disputeManagement;
    
    // Test accounts
    address public owner;
    address public feeRecipient;
    address public seller;
    address public buyer;
    address public carrier;
    address public arbitrator;
    address public riskAssessor;
    
    // Test constants
    uint256 public constant DEFAULT_CONTRACT_VALUE = 1000 ether;
    uint256 public constant DEFAULT_DELIVERY_DAYS = 30;
    uint256 public constant DEFAULT_PAYMENT_DAYS = 45;
    string public constant DEFAULT_CURRENCY = "USD";
    string public constant DEFAULT_ORIGIN_COUNTRY = "NG";
    string public constant DEFAULT_DEST_COUNTRY = "GH";
    
    // Events for testing
    event ContractCreated(uint256 indexed contractId, address indexed seller, address indexed buyer, uint256 value);
    event ContractFunded(uint256 indexed contractId, uint256 amount);
    
    function setUp() public virtual {
        // Set up test accounts
        owner = address(this);
        feeRecipient = makeAddr("feeRecipient");
        seller = makeAddr("seller");
        buyer = makeAddr("buyer");
        carrier = makeAddr("carrier");
        arbitrator = makeAddr("arbitrator");
        riskAssessor = makeAddr("riskAssessor");
        
        // Give test accounts some ETH
        vm.deal(seller, 10000 ether);
        vm.deal(buyer, 10000 ether);
        vm.deal(carrier, 1000 ether);
        vm.deal(arbitrator, 1000 ether);
        
        // Deploy main platform
        platform = new BlockFinaxTradePlatform(feeRecipient);
        
        // Get module addresses
        (
            address contractMgmt,
            address docMgmt,
            address invoiceMgmt,
            address shipmentMgmt,
            address riskMgmt,
            address disputeMgmt,
        ) = platform.getPlatformInfo();
        
        // Initialize module contracts
        contractManagement = ContractManagement(contractMgmt);
        documentManagement = DocumentManagement(docMgmt);
        invoiceManagement = InvoiceManagement(invoiceMgmt);
        shipmentManagement = ShipmentManagement(shipmentMgmt);
        riskManagement = RiskManagement(riskMgmt);
        disputeManagement = DisputeManagement(disputeMgmt);
        
        // Set up initial configuration
        _setupInitialConfig();
    }
    
    function _setupInitialConfig() internal {
        // Verify test users
        platform.verifyUser(seller);
        platform.verifyUser(buyer);
        platform.verifyUser(carrier);
        platform.verifyUser(arbitrator);
        platform.verifyUser(riskAssessor);
        
        // Add risk assessor
        riskManagement.addRiskAssessor(riskAssessor);
        
        // Add arbitrator
        disputeManagement.addArbitrator(arbitrator);
        
        // Authorize carrier
        shipmentManagement.authorizeCarrier(carrier);
    }
    
    // Helper functions for creating test contracts
    function createBasicContract() public returns (uint256 contractId) {
        return createBasicContract(seller, buyer);
    }
    
    function createBasicContract(address _seller, address _buyer) public returns (uint256 contractId) {
        vm.prank(_seller);
        contractId = platform.createContract(
            _buyer,
            "Test Contract",
            "A test trade contract",
            DEFAULT_CONTRACT_VALUE,
            block.timestamp + (DEFAULT_DELIVERY_DAYS * 1 days),
            block.timestamp + (DEFAULT_PAYMENT_DAYS * 1 days),
            "FOB Lagos",
            "Net 30",
            "Test product",
            100,
            "kg",
            DEFAULT_CONTRACT_VALUE / 100,
            DEFAULT_CURRENCY,
            DEFAULT_ORIGIN_COUNTRY,
            DEFAULT_DEST_COUNTRY
        );
    }
    
    function createAndApproveContract() public returns (uint256 contractId) {
        contractId = createBasicContract();
        
        // Buyer approves
        vm.prank(buyer);
        platform.approveContract(contractId);
    }
    
    function createAndFundContract() public returns (uint256 contractId) {
        contractId = createAndApproveContract();
        
        // Buyer funds escrow
        vm.prank(buyer);
        platform.fundEscrow{value: DEFAULT_CONTRACT_VALUE}(contractId);
    }
    
    // Helper function for creating test documents
    function uploadTestDocument(uint256 contractId) public returns (uint256 documentId) {
        vm.prank(seller);
        documentId = platform.uploadDocument(
            contractId,
            "Test Document",
            "QmTestHash123",
            TradeStructs.DocumentType.Contract,
            true,
            "A test document",
            keccak256("test_document_content")
        );
    }
    
    // Helper function for creating test invoices
    function createTestInvoice(uint256 contractId) public returns (uint256 invoiceId) {
        vm.prank(seller);
        invoiceId = platform.createInvoice(
            contractId,
            DEFAULT_CONTRACT_VALUE,
            DEFAULT_CURRENCY,
            block.timestamp + 30 days,
            "Test invoice",
            "Wire transfer to account 123",
            DEFAULT_CONTRACT_VALUE / 10, // 10% tax
            0 // no discount
        );
    }
    
    // Helper function for creating test shipments
    function createTestShipment(uint256 contractId) public returns (uint256 shipmentId) {
        vm.prank(seller);
        shipmentId = platform.createShipment(
            contractId,
            "TRACK123456789",
            "DHL Express",
            "Lagos, Nigeria",
            "Accra, Ghana",
            block.timestamp + 7 days,
            DEFAULT_CONTRACT_VALUE / 10 // 10% insurance
        );
    }
    
    // Utility functions for testing
    function expectRevertWithMessage(bytes memory callData, string memory expectedMessage) internal {
        vm.expectRevert(bytes(expectedMessage));
        (bool success, bytes memory returnData) = address(platform).call(callData);
        if (success) {
            fail("Expected revert but call succeeded");
        }
        
        // Check if the error message matches
        if (returnData.length >= 68) {
            // Extract the revert message manually
            bytes memory messageBytes = new bytes(returnData.length - 68);
            for (uint i = 0; i < messageBytes.length; i++) {
                messageBytes[i] = returnData[i + 68];
            }
            string memory actualMessage = abi.decode(messageBytes, (string));
            assertEq(actualMessage, expectedMessage, "Revert message mismatch");
        }
    }
    
    // Helper to skip time
    function skipDays(uint256 numDays) internal {
        vm.warp(block.timestamp + (numDays * 1 days));
    }
    
    function skipHours(uint256 numHours) internal {
        vm.warp(block.timestamp + (numHours * 1 hours));
    }
    
    // Helper to check contract status
    function assertContractStatus(uint256 contractId, TradeStructs.ContractStatus expectedStatus) internal {
        (, , , TradeStructs.ContractStatus actualStatus) = platform.getContract(contractId);
        assertEq(uint256(actualStatus), uint256(expectedStatus), "Contract status mismatch");
    }
    
    // Helper to check balances
    function assertEtherBalance(address account, uint256 expectedBalance) internal {
        assertEq(account.balance, expectedBalance, "Ether balance mismatch");
    }
    
    function assertApproxEtherBalance(address account, uint256 expectedBalance, uint256 tolerance) internal {
        uint256 actualBalance = account.balance;
        uint256 difference = actualBalance > expectedBalance 
            ? actualBalance - expectedBalance 
            : expectedBalance - actualBalance;
        
        assertLe(difference, tolerance, "Ether balance not within tolerance");
    }
    
    // Helper for event testing
    function expectContractCreatedEvent(address _seller, address _buyer, uint256 _value) internal {
        vm.expectEmit(true, true, false, true);
        emit ContractCreated(1, _seller, _buyer, _value); // Assuming first contract has ID 1
    }
    
    function expectContractFundedEvent(uint256 contractId, uint256 amount) internal {
        vm.expectEmit(true, false, false, true);
        emit ContractFunded(contractId, amount);
    }
    
    // Helper for fuzzing bounds
    function boundContractValue(uint256 value) internal pure returns (uint256) {
        return bound(value, 100, 1_000_000 ether);
    }
    
    function boundDeliveryDays(uint256 numDays) internal pure returns (uint256) {
        return bound(numDays, 1, 365);
    }
    
    function boundPaymentDays(uint256 paymentDays, uint256 deliveryDays) internal pure returns (uint256) {
        return bound(paymentDays, deliveryDays + 1, deliveryDays + 90);
    }
}