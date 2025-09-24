// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/BaseModule.sol";

/**
 * @title BaseModule Test Contract
 * @dev Comprehensive tests for BaseModule functionality
 */

// Create a concrete implementation of BaseModule for testing
contract TestableBaseModule is BaseModule {
    // This allows us to test the abstract BaseModule
    function testFunction() external onlyVerifiedUser returns (bool) {
        return true;
    }
}

contract BaseModuleTest is Test {
    TestableBaseModule public baseModule;
    
    // Test accounts
    address public owner;
    address public user1;
    address public user2;
    address public nonOwner;
    
    // Events to test
    event UserVerified(address indexed user);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event Paused(address account);
    event Unpaused(address account);
    
    function setUp() public {
        // Set up test accounts
        owner = address(this); // Test contract is owner
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        nonOwner = makeAddr("nonOwner");
        
        // Deploy BaseModule
        baseModule = new TestableBaseModule();
    }
    
    // ==========================================
    // INITIALIZATION TESTS
    // ==========================================
    
    function test_InitialState() public {
        // Test initial ownership
        assertEq(baseModule.owner(), owner);
        assertFalse(baseModule.paused());
        
        // Test supported countries are initialized
        assertTrue(baseModule.isCountrySupported("NG")); // Nigeria
        assertTrue(baseModule.isCountrySupported("GH")); // Ghana
        assertTrue(baseModule.isCountrySupported("KE")); // Kenya
        assertTrue(baseModule.isCountrySupported("ET")); // Ethiopia
        assertTrue(baseModule.isCountrySupported("MA")); // Morocco
        assertTrue(baseModule.isCountrySupported("EG")); // Egypt
        assertTrue(baseModule.isCountrySupported("ZA")); // South Africa
        assertTrue(baseModule.isCountrySupported("RW")); // Rwanda
        assertTrue(baseModule.isCountrySupported("SN")); // Senegal
        assertTrue(baseModule.isCountrySupported("CI")); // Cote d'Ivoire
        
        // Test unsupported country
        assertFalse(baseModule.isCountrySupported("US"));
        
        // Test supported currencies are initialized
        assertTrue(baseModule.isCurrencySupported("USD"));
        assertTrue(baseModule.isCurrencySupported("EUR"));
        assertTrue(baseModule.isCurrencySupported("NGN")); // Nigerian Naira
        assertTrue(baseModule.isCurrencySupported("GHS")); // Ghanaian Cedi
        assertTrue(baseModule.isCurrencySupported("KES")); // Kenyan Shilling
        assertTrue(baseModule.isCurrencySupported("ETB")); // Ethiopian Birr
        assertTrue(baseModule.isCurrencySupported("MAD")); // Moroccan Dirham
        assertTrue(baseModule.isCurrencySupported("EGP")); // Egyptian Pound
        assertTrue(baseModule.isCurrencySupported("ZAR")); // South African Rand
        
        // Test unsupported currency
        assertFalse(baseModule.isCurrencySupported("JPY"));
        
        // Test no users are verified initially
        assertFalse(baseModule.verifiedUsers(user1));
        assertFalse(baseModule.verifiedUsers(user2));
    }
    
    // ==========================================
    // USER VERIFICATION TESTS
    // ==========================================
    
    function test_VerifyUser() public {
        // Test user verification by owner
        vm.expectEmit(true, false, false, false);
        emit UserVerified(user1);
        
        baseModule.verifyUser(user1);
        
        assertTrue(baseModule.verifiedUsers(user1));
        assertFalse(baseModule.verifiedUsers(user2)); // Other user should remain unverified
    }
    
    function test_VerifyUser_RevertNonOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        baseModule.verifyUser(user1);
    }
    
    function test_RevokeUserVerification() public {
        // First verify user
        baseModule.verifyUser(user1);
        assertTrue(baseModule.verifiedUsers(user1));
        
        // Then revoke verification
        baseModule.revokeUserVerification(user1);
        assertFalse(baseModule.verifiedUsers(user1));
    }
    
    function test_RevokeUserVerification_RevertNonOwner() public {
        baseModule.verifyUser(user1);
        
        vm.prank(nonOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        baseModule.revokeUserVerification(user1);
    }
    
    function test_OnlyVerifiedUserModifier() public {
        // Unverified user should fail
        vm.prank(user1);
        vm.expectRevert("User not verified");
        baseModule.testFunction();
        
        // Verify user
        baseModule.verifyUser(user1);
        
        // Now it should work
        vm.prank(user1);
        assertTrue(baseModule.testFunction());
    }
    
    // ==========================================
    // COUNTRY MANAGEMENT TESTS
    // ==========================================
    
    function test_AddSupportedCountry() public {
        string memory newCountry = "US";
        assertFalse(baseModule.isCountrySupported(newCountry));
        
        baseModule.addSupportedCountry(newCountry);
        assertTrue(baseModule.isCountrySupported(newCountry));
    }
    
    function test_AddSupportedCountry_RevertNonOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        baseModule.addSupportedCountry("US");
    }
    
    function test_RemoveSupportedCountry() public {
        string memory country = "NG";
        assertTrue(baseModule.isCountrySupported(country));
        
        baseModule.removeSupportedCountry(country);
        assertFalse(baseModule.isCountrySupported(country));
    }
    
    function test_RemoveSupportedCountry_RevertNonOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        baseModule.removeSupportedCountry("NG");
    }
    
    // ==========================================
    // CURRENCY MANAGEMENT TESTS
    // ==========================================
    
    function test_AddSupportedCurrency() public {
        string memory newCurrency = "JPY";
        assertFalse(baseModule.isCurrencySupported(newCurrency));
        
        baseModule.addSupportedCurrency(newCurrency);
        assertTrue(baseModule.isCurrencySupported(newCurrency));
    }
    
    function test_AddSupportedCurrency_RevertNonOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        baseModule.addSupportedCurrency("JPY");
    }
    
    function test_RemoveSupportedCurrency() public {
        string memory currency = "USD";
        assertTrue(baseModule.isCurrencySupported(currency));
        
        baseModule.removeSupportedCurrency(currency);
        assertFalse(baseModule.isCurrencySupported(currency));
    }
    
    function test_RemoveSupportedCurrency_RevertNonOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        baseModule.removeSupportedCurrency("USD");
    }
    
    // ==========================================
    // PAUSE/UNPAUSE TESTS
    // ==========================================
    
    function test_Pause() public {
        assertFalse(baseModule.paused());
        
        vm.expectEmit(true, false, false, false);
        emit Paused(owner);
        
        baseModule.pause();
        assertTrue(baseModule.paused());
    }
    
    function test_Pause_RevertNonOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        baseModule.pause();
    }
    
    function test_Unpause() public {
        baseModule.pause();
        assertTrue(baseModule.paused());
        
        vm.expectEmit(true, false, false, false);
        emit Unpaused(owner);
        
        baseModule.unpause();
        assertFalse(baseModule.paused());
    }
    
    function test_Unpause_RevertNonOwner() public {
        baseModule.pause();
        
        vm.prank(nonOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        baseModule.unpause();
    }
    
    // ==========================================
    // INTERNAL FUNCTION TESTS (via public view functions)
    // ==========================================
    
    function test_InternalHelperFunctions() public {
        // Test _isCountrySupported via public function
        assertTrue(baseModule.isCountrySupported("NG"));
        assertFalse(baseModule.isCountrySupported("XX"));
        
        // Test _isCurrencySupported via public function
        assertTrue(baseModule.isCurrencySupported("USD"));
        assertFalse(baseModule.isCurrencySupported("XXX"));
        
        // Test user verification
        assertFalse(baseModule.verifiedUsers(user1));
        baseModule.verifyUser(user1);
        assertTrue(baseModule.verifiedUsers(user1));
    }
    
    // ==========================================
    // EDGE CASE TESTS
    // ==========================================
    
    function test_EmptyStringCountry() public {
        assertFalse(baseModule.isCountrySupported(""));
    }
    
    function test_EmptyStringCurrency() public {
        assertFalse(baseModule.isCurrencySupported(""));
    }
    
    function test_VerifyZeroAddress() public {
        vm.expectRevert(); // Should revert on zero address operations
        baseModule.verifyUser(address(0));
    }
    
    function test_MultipleUserVerifications() public {
        // Verify multiple users
        baseModule.verifyUser(user1);
        baseModule.verifyUser(user2);
        
        assertTrue(baseModule.verifiedUsers(user1));
        assertTrue(baseModule.verifiedUsers(user2));
        
        // Revoke one user
        baseModule.revokeUserVerification(user1);
        
        assertFalse(baseModule.verifiedUsers(user1));
        assertTrue(baseModule.verifiedUsers(user2)); // Other user should remain verified
    }
    
    function test_ReVerifyUser() public {
        // Verify user
        baseModule.verifyUser(user1);
        assertTrue(baseModule.verifiedUsers(user1));
        
        // Verify same user again (should not cause issues)
        baseModule.verifyUser(user1);
        assertTrue(baseModule.verifiedUsers(user1));
    }
    
    function test_RevokeUnverifiedUser() public {
        // Revoking unverified user should not cause issues
        assertFalse(baseModule.verifiedUsers(user1));
        baseModule.revokeUserVerification(user1);
        assertFalse(baseModule.verifiedUsers(user1));
    }
    
    // ==========================================
    // INTEGRATION TESTS
    // ==========================================
    
    function test_FullWorkflow() public {
        // 1. Initial state check
        assertFalse(baseModule.paused());
        assertFalse(baseModule.verifiedUsers(user1));
        
        // 2. Add new country and currency
        baseModule.addSupportedCountry("BR");
        baseModule.addSupportedCurrency("BRL");
        assertTrue(baseModule.isCountrySupported("BR"));
        assertTrue(baseModule.isCurrencySupported("BRL"));
        
        // 3. Verify user
        baseModule.verifyUser(user1);
        assertTrue(baseModule.verifiedUsers(user1));
        
        // 4. User should be able to call protected function
        vm.prank(user1);
        assertTrue(baseModule.testFunction());
        
        // 5. Pause platform
        baseModule.pause();
        assertTrue(baseModule.paused());
        
        // 6. Unpause platform
        baseModule.unpause();
        assertFalse(baseModule.paused());
        
        // 7. Remove country and currency
        baseModule.removeSupportedCountry("BR");
        baseModule.removeSupportedCurrency("BRL");
        assertFalse(baseModule.isCountrySupported("BR"));
        assertFalse(baseModule.isCurrencySupported("BRL"));
        
        // 8. Revoke user verification
        baseModule.revokeUserVerification(user1);
        assertFalse(baseModule.verifiedUsers(user1));
        
        // 9. User should no longer be able to call protected function
        vm.prank(user1);
        vm.expectRevert("User not verified");
        baseModule.testFunction();
    }
    
    // ==========================================
    // GAS OPTIMIZATION TESTS
    // ==========================================
    
    function test_GasUsage() public {
        uint256 gasBefore;
        uint256 gasAfter;
        
        // Test gas usage for user verification
        gasBefore = gasleft();
        baseModule.verifyUser(user1);
        gasAfter = gasleft();
        console.log("Gas used for user verification:", gasBefore - gasAfter);
        
        // Test gas usage for country support check
        gasBefore = gasleft();
        baseModule.isCountrySupported("NG");
        gasAfter = gasleft();
        console.log("Gas used for country support check:", gasBefore - gasAfter);
        
        // Test gas usage for currency support check
        gasBefore = gasleft();
        baseModule.isCurrencySupported("USD");
        gasAfter = gasleft();
        console.log("Gas used for currency support check:", gasBefore - gasAfter);
    }
}
