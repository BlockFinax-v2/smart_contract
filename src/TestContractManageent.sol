// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./TestBase.sol";

contract ContractManagementTest is BaseTest {
    
    function test_CreateContract() public {
        expectContractCreatedEvent(seller, buyer, DEFAULT_CONTRACT_VALUE);
        
        uint256 contractId = createBasicContract();
        
        // Verify contract details
        (address contractSeller, address contractBuyer, uint256 totalValue, TradeStructs.ContractStatus status) = 
            platform.getContract(contractId);
        
        assertEq(contractSeller, seller);
        assertEq(contractBuyer, buyer);
        assertEq(totalValue, DEFAULT_CONTRACT_VALUE);
        assertEq(uint256(status), uint256(TradeStructs.ContractStatus.Draft));
        
        // Verify contract is in user's contract list
        uint256[] memory sellerContracts = platform.getUserContracts(seller);
        uint256[] memory buyerContracts = platform.getUserContracts(buyer);
        
        assertEq(sellerContracts.length, 1);
        assertEq(buyerContracts.length, 1);
        assertEq(sellerContracts[0], contractId);
        assertEq(buyerContracts[0], contractId);
    }
    
    function test_CreateContract_RevertInvalidBuyer() public {
        vm.expectRevert("Invalid buyer address");
        vm.prank(seller);
        platform.createContract(
            address(0), // Invalid buyer
            "Test Contract",
            "Description",
            DEFAULT_CONTRACT_VALUE,
            block.timestamp + 30 days,
            block.timestamp + 45 days,
            "FOB Lagos",
            "Net 30",
            "Test product",
            100,
            "kg",
            10 ether,
            "USD",
            "NG",
            "GH"
        );
    }
    
    function test_CreateContract_RevertSellerAsBuyer() public {
        vm.expectRevert("Seller cannot be buyer");
        vm.prank(seller);
        platform.createContract(
            seller, // Same as seller
            "Test Contract",
            "Description",
            DEFAULT_CONTRACT_VALUE,
            block.timestamp + 30 days,
            block.timestamp + 45 days,
            "FOB Lagos",
            "Net 30",
            "Test product",
            100,
            "kg",
            10 ether,
            "USD",
            "NG",
            "GH"
        );
    }
    
    function test_CreateContract_RevertUnverifiedUser() public {
        address unverifiedUser = makeAddr("unverified");
        
        vm.expectRevert("User not verified");
        vm.prank(unverifiedUser);
        platform.createContract(
            buyer,
            "Test Contract",
            "Description",
            DEFAULT_CONTRACT_VALUE,
            block.timestamp + 30 days,
            block.timestamp + 60 days,
            "FOB Shipping Point",
            "Net 30",
            "Test Product",
            100,
            "kg",
            1000,
            "USD",
            "US",
            "CA"
        );
    }
}
