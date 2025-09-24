// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

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