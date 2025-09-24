// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";

// Copy the BaseModule code directly to avoid dependency issues
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

/**
 * @title BaseModule
 * @dev Base contract for all platform modules with common functionality
 */
abstract contract BaseModule is ReentrancyGuard, Ownable, Pausable {
    mapping(address => bool) public verifiedUsers;
    mapping(string => bool) public supportedCountries;
    mapping(string => bool) public supportedCurrencies;
    
    event UserVerified(address indexed user);
    
    constructor() {
        _initializeSupportedCountries();
        _initializeSupportedCurrencies();
    }
    
    function _initializeSupportedCountries() internal {
        supportedCountries["NG"] = true; // Nigeria
        supportedCountries["GH"] = true; // Ghana
        supportedCountries["KE"] = true; // Kenya
        supportedCountries["ET"] = true; // Ethiopia
        supportedCountries["MA"] = true; // Morocco
        supportedCountries["EG"] = true; // Egypt
        supportedCountries["ZA"] = true; // South Africa
        supportedCountries["RW"] = true; // Rwanda
        supportedCountries["SN"] = true; // Senegal
        supportedCountries["CI"] = true; // Cote d'Ivoire
    }
    
    function _initializeSupportedCurrencies() internal {
        supportedCurrencies["USD"] = true;
        supportedCurrencies["EUR"] = true;
        supportedCurrencies["NGN"] = true; // Nigerian Naira
        supportedCurrencies["GHS"] = true; // Ghanaian Cedi
        supportedCurrencies["KES"] = true; // Kenyan Shilling
        supportedCurrencies["ETB"] = true; // Ethiopian Birr
        supportedCurrencies["MAD"] = true; // Moroccan Dirham
        supportedCurrencies["EGP"] = true; // Egyptian Pound
        supportedCurrencies["ZAR"] = true; // South African Rand
    }
    
    modifier onlyVerifiedUser() {
        require(verifiedUsers[msg.sender], "User not verified");
        _;
    }

    function _isUserVerified(address user) internal view returns (bool) {
        return verifiedUsers[user];
    }
    
    function _isCountrySupported(string memory countryCode) internal view returns (bool) {
        return supportedCountries[countryCode];
    }
    
    function _isCurrencySupported(string memory currency) internal view returns (bool) {
        return supportedCurrencies[currency];
    }
    
    function _compareStrings(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }

    function verifyUser(address user) external onlyOwner {
        verifiedUsers[user] = true;
        emit UserVerified(user);
    }
    
    function revokeUserVerification(address user) external onlyOwner {
        verifiedUsers[user] = false;
    }
    
    function addSupportedCountry(string calldata countryCode) external onlyOwner {
        supportedCountries[countryCode] = true;
    }
    
    function removeSupportedCountry(string calldata countryCode) external onlyOwner {
        supportedCountries[countryCode] = false;
    }
    
    function addSupportedCurrency(string calldata currency) external onlyOwner {
        supportedCurrencies[currency] = true;
    }
    
    function removeSupportedCurrency(string calldata currency) external onlyOwner {
        supportedCurrencies[currency] = false;
    }
    
    function pause() external onlyOwner {
        _pause();
    }
    
    function unpause() external onlyOwner {
        _unpause();
    }

    function isCountrySupported(string calldata countryCode) external view returns (bool) {
        return supportedCountries[countryCode];
    }
    
    function isCurrencySupported(string calldata currency) external view returns (bool) {
        return supportedCurrencies[currency];
    }
}

// Create a concrete implementation of BaseModule for testing
contract TestableBaseModule is BaseModule {
    function testFunction() external onlyVerifiedUser returns (bool) {
        return true;
    }
}

contract BaseModuleStandaloneTest is Test {
    TestableBaseModule public baseModule;
    
    // Test accounts
    address public owner;
    address public user1;
    address public user2;
    address public nonOwner;
    
    // Events to test
    event UserVerified(address indexed user);
    
    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        nonOwner = makeAddr("nonOwner");
        
        baseModule = new TestableBaseModule();
    }
    
    function test_InitialState() public {
        assertEq(baseModule.owner(), owner);
        assertFalse(baseModule.paused());
        
        // Test AFCFTA countries
        assertTrue(baseModule.isCountrySupported("NG"));
        assertTrue(baseModule.isCountrySupported("GH"));
        assertTrue(baseModule.isCountrySupported("KE"));
        assertFalse(baseModule.isCountrySupported("US"));
        
        // Test currencies
        assertTrue(baseModule.isCurrencySupported("USD"));
        assertTrue(baseModule.isCurrencySupported("NGN"));
        assertFalse(baseModule.isCurrencySupported("JPY"));
        
        // Test users not verified initially
        assertFalse(baseModule.verifiedUsers(user1));
    }
    
    function test_UserVerification() public {
        vm.expectEmit(true, false, false, false);
        emit UserVerified(user1);
        
        baseModule.verifyUser(user1);
        assertTrue(baseModule.verifiedUsers(user1));
        
        // Test verified user can access protected function
        vm.prank(user1);
        assertTrue(baseModule.testFunction());
    }
    
    function test_UserVerification_RevertNonOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert();
        baseModule.verifyUser(user1);
    }
    
    function test_RevokeVerification() public {
        baseModule.verifyUser(user1);
        assertTrue(baseModule.verifiedUsers(user1));
        
        baseModule.revokeUserVerification(user1);
        assertFalse(baseModule.verifiedUsers(user1));
    }
    
    function test_OnlyVerifiedUserModifier() public {
        vm.prank(user1);
        vm.expectRevert("User not verified");
        baseModule.testFunction();
        
        baseModule.verifyUser(user1);
        vm.prank(user1);
        assertTrue(baseModule.testFunction());
    }
    
    function test_CountryManagement() public {
        string memory newCountry = "US";
        assertFalse(baseModule.isCountrySupported(newCountry));
        
        baseModule.addSupportedCountry(newCountry);
        assertTrue(baseModule.isCountrySupported(newCountry));
        
        baseModule.removeSupportedCountry(newCountry);
        assertFalse(baseModule.isCountrySupported(newCountry));
    }
    
    function test_CurrencyManagement() public {
        string memory newCurrency = "JPY";
        assertFalse(baseModule.isCurrencySupported(newCurrency));
        
        baseModule.addSupportedCurrency(newCurrency);
        assertTrue(baseModule.isCurrencySupported(newCurrency));
        
        baseModule.removeSupportedCurrency(newCurrency);
        assertFalse(baseModule.isCurrencySupported(newCurrency));
    }
    
    function test_PauseUnpause() public {
        assertFalse(baseModule.paused());
        
        baseModule.pause();
        assertTrue(baseModule.paused());
        
        baseModule.unpause();
        assertFalse(baseModule.paused());
    }
    
    function test_PauseRevertNonOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert();
        baseModule.pause();
    }
    
    function test_FullWorkflow() public {
        // Complete integration test
        baseModule.addSupportedCountry("BR");
        baseModule.addSupportedCurrency("BRL");
        baseModule.verifyUser(user1);
        
        assertTrue(baseModule.isCountrySupported("BR"));
        assertTrue(baseModule.isCurrencySupported("BRL"));
        assertTrue(baseModule.verifiedUsers(user1));
        
        vm.prank(user1);
        assertTrue(baseModule.testFunction());
        
        baseModule.pause();
        assertTrue(baseModule.paused());
        
        baseModule.unpause();
        assertFalse(baseModule.paused());
        
        baseModule.revokeUserVerification(user1);
        assertFalse(baseModule.verifiedUsers(user1));
        
        vm.prank(user1);
        vm.expectRevert("User not verified");
        baseModule.testFunction();
    }
}
