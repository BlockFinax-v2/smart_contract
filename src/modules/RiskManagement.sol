// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../libraries/TradeStructs.sol";
import "../BaseModule.sol";

/**
 * @title RiskManagement
 * @dev Module for risk assessment and management
 */
contract RiskManagement is BaseModule {
    
    // Storage
    mapping(uint256 => TradeStructs.RiskAssessment) public riskAssessments;
    mapping(address => bool) public riskAssessors;
    mapping(address => uint256) public userRiskScores;
    mapping(string => uint256) public countryRiskScores;
    mapping(string => uint256) public currencyRiskScores;
    
    // Risk thresholds
    uint256 public constant LOW_RISK_THRESHOLD = 25;
    uint256 public constant MEDIUM_RISK_THRESHOLD = 50;
    uint256 public constant HIGH_RISK_THRESHOLD = 75;
    
    // Events
    event RiskAssessed(uint256 indexed contractId, TradeStructs.RiskLevel level, uint256 score);
    event RiskAssessorAdded(address indexed assessor);
    event RiskAssessorRemoved(address indexed assessor);
    event UserRiskScoreUpdated(address indexed user, uint256 newScore);
    event CountryRiskUpdated(string indexed country, uint256 riskScore);
    
    modifier onlyRiskAssessor() {
        require(riskAssessors[msg.sender] || msg.sender == owner(), "Not authorized risk assessor");
        _;
    }
    
    constructor() {
        _initializeCountryRisks();
        _initializeCurrencyRisks();
    }
    
    /**
     * @dev Initialize default country risk scores
     */
    function _initializeCountryRisks() internal {
        // Lower scores = lower risk
        countryRiskScores["NG"] = 15; // Nigeria
        countryRiskScores["GH"] = 10; // Ghana  
        countryRiskScores["KE"] = 12; // Kenya
        countryRiskScores["ET"] = 20; // Ethiopia
        countryRiskScores["MA"] = 8;  // Morocco
        countryRiskScores["EG"] = 18; // Egypt
        countryRiskScores["ZA"] = 10; // South Africa
        countryRiskScores["RW"] = 8;  // Rwanda
        countryRiskScores["SN"] = 12; // Senegal
        countryRiskScores["CI"] = 15; // Cote d'Ivoire
    }
    
    /**
     * @dev Initialize currency risk scores
     */
    function _initializeCurrencyRisks() internal {
        currencyRiskScores["USD"] = 5;  // US Dollar
        currencyRiskScores["EUR"] = 5;  // Euro
        currencyRiskScores["NGN"] = 15; // Nigerian Naira
        currencyRiskScores["GHS"] = 12; // Ghanaian Cedi
        currencyRiskScores["KES"] = 10; // Kenyan Shilling
        currencyRiskScores["ETB"] = 18; // Ethiopian Birr
        currencyRiskScores["MAD"] = 8;  // Moroccan Dirham
        currencyRiskScores["EGP"] = 15; // Egyptian Pound
        currencyRiskScores["ZAR"] = 12; // South African Rand
    }
    
    /**
     * @dev Perform comprehensive risk assessment for a contract
     */
    function assessContractRisk(
        uint256 contractId,
        uint256 totalValue,
        string memory currency,
        string memory originCountry,
        string memory destinationCountry,
        uint256 deliveryDeadline,
        uint256 creationTime,
        address seller,
        address buyer
    ) external onlyRiskAssessor returns (uint256) {
        require(contractId > 0, "Invalid contract ID");
        
        uint256 riskScore = 0;
        string[] memory factors = new string[](10);
        uint256 factorCount = 0;
        
        // 1. Contract value risk (0-25 points)
        if (totalValue > 100000 ether) {
            riskScore += 25;
            factors[factorCount] = "Very high contract value";
            factorCount++;
        } else if (totalValue > 50000 ether) {
            riskScore += 20;
            factors[factorCount] = "High contract value";
            factorCount++;
        } else if (totalValue > 10000 ether) {
            riskScore += 15;
            factors[factorCount] = "Medium contract value";
            factorCount++;
        } else if (totalValue > 1000 ether) {
            riskScore += 10;
            factors[factorCount] = "Low-medium contract value";
            factorCount++;
        }
        
        // 2. Currency risk (0-20 points)
        uint256 currencyRisk = currencyRiskScores[currency];
        riskScore += currencyRisk;
        if (currencyRisk > 10) {
            factors[factorCount] = "High currency volatility";
            factorCount++;
        }
        
        // 3. Country risk (0-25 points)
        uint256 originRisk = countryRiskScores[originCountry];
        uint256 destRisk = countryRiskScores[destinationCountry];
        uint256 countryRisk = (originRisk + destRisk) / 2;
        riskScore += countryRisk;
        
        if (countryRisk > 15) {
            factors[factorCount] = "High country risk";
            factorCount++;
        }
        
        // Cross-border trade adds complexity
        if (!_compareStrings(originCountry, destinationCountry)) {
            riskScore += 10;
            factors[factorCount] = "Cross-border transaction";
            factorCount++;
        }
        
        // 4. Timeline risk (0-15 points)
        uint256 timelineDays = (deliveryDeadline - creationTime) / 1 days;
        if (timelineDays > 90) {
            riskScore += 15;
            factors[factorCount] = "Extended delivery timeline";
            factorCount++;
        } else if (timelineDays > 60) {
            riskScore += 10;
            factors[factorCount] = "Long delivery timeline";
            factorCount++;
        } else if (timelineDays < 7) {
            riskScore += 12;
            factors[factorCount] = "Very short delivery timeline";
            factorCount++;
        }
        
        // 5. User risk scores (0-15 points)
        uint256 sellerRisk = userRiskScores[seller];
        uint256 buyerRisk = userRiskScores[buyer];
        uint256 userRisk = (sellerRisk + buyerRisk) / 2;
        riskScore += userRisk;
        
        if (userRisk > 10) {
            factors[factorCount] = "High user risk profile";
            factorCount++;
        }
        
        // Determine risk level
        TradeStructs.RiskLevel level;
        bool requiresApproval = false;
        string memory mitigation;
        
        if (riskScore < LOW_RISK_THRESHOLD) {
            level = TradeStructs.RiskLevel.Low;
            mitigation = "Standard monitoring protocols";
        } else if (riskScore < MEDIUM_RISK_THRESHOLD) {
            level = TradeStructs.RiskLevel.Medium;
            mitigation = "Enhanced monitoring and documentation required";
        } else if (riskScore < HIGH_RISK_THRESHOLD) {
            level = TradeStructs.RiskLevel.High;
            mitigation = "Manual review and additional verification required";
            requiresApproval = true;
        } else {
            level = TradeStructs.RiskLevel.Critical;
            mitigation = "Executive approval and comprehensive due diligence required";
            requiresApproval = true;
        }
        
        // Resize factors array to actual count
        string[] memory finalFactors = new string[](factorCount);
        for (uint256 i = 0; i < factorCount; i++) {
            finalFactors[i] = factors[i];
        }
        
        riskAssessments[contractId] = TradeStructs.RiskAssessment({
            contractId: contractId,
            level: level,
            riskFactors: finalFactors,
            score: riskScore,
            mitigation: mitigation,
            assessmentDate: block.timestamp,
            assessor: msg.sender,
            requiresApproval: requiresApproval
        });
        
        emit RiskAssessed(contractId, level, riskScore);
        
        return riskScore;
    }
    
    /**
     * @dev Update user risk score based on trading history
     */
    function updateUserRiskScore(address user, uint256 newScore) external onlyRiskAssessor {
        require(user != address(0), "Invalid user address");
        require(newScore <= 100, "Risk score cannot exceed 100");
        
        userRiskScores[user] = newScore;
        emit UserRiskScoreUpdated(user, newScore);
    }
    
    /**
     * @dev Batch update multiple user risk scores
     */
    function batchUpdateUserRiskScores(
        address[] calldata users,
        uint256[] calldata scores
    ) external onlyRiskAssessor {
        require(users.length == scores.length, "Array length mismatch");
        
        for (uint256 i = 0; i < users.length; i++) {
            require(scores[i] <= 100, "Risk score cannot exceed 100");
            userRiskScores[users[i]] = scores[i];
            emit UserRiskScoreUpdated(users[i], scores[i]);
        }
    }
    
    /**
     * @dev Update country risk score
     */
    function updateCountryRiskScore(string calldata country, uint256 riskScore) external onlyRiskAssessor {
        require(riskScore <= 50, "Country risk score too high");
        require(_isCountrySupported(country), "Country not supported");
        
        countryRiskScores[country] = riskScore;
        emit CountryRiskUpdated(country, riskScore);
    }
    
    /**
     * @dev Get comprehensive risk assessment
     */
    function getRiskAssessment(uint256 contractId) external view returns (TradeStructs.RiskAssessment memory) {
        require(riskAssessments[contractId].contractId != 0, "Risk assessment not found");
        return riskAssessments[contractId];
    }
    
    /**
     * @dev Check if contract requires manual approval
     */
    function requiresManualApproval(uint256 contractId) external view returns (bool) {
        TradeStructs.RiskAssessment memory assessment = riskAssessments[contractId];
        return assessment.requiresApproval;
    }
    
    /**
     * @dev Get user risk profile
     */
    function getUserRiskProfile(address user) external view returns (
        uint256 riskScore,
        string memory riskLevel,
        string memory recommendation
    ) {
        riskScore = userRiskScores[user];
        
        if (riskScore < 10) {
            riskLevel = "Low";
            recommendation = "Standard processing approved";
        } else if (riskScore < 25) {
            riskLevel = "Medium";
            recommendation = "Enhanced monitoring recommended";
        } else if (riskScore < 40) {
            riskLevel = "High";
            recommendation = "Additional verification required";
        } else {
            riskLevel = "Critical";
            recommendation = "Manual review mandatory";
        }
    }
    
    /**
     * @dev Get country risk information
     */
    function getCountryRisk(string calldata country) external view returns (
        uint256 riskScore,
        bool isSupported
    ) {
        riskScore = countryRiskScores[country];
        isSupported = _isCountrySupported(country);
    }
    
    /**
     * @dev Calculate dynamic risk score for real-time assessment
     */
    function calculateDynamicRisk(
        uint256 baseRiskScore,
        uint256 contractValue,
        uint256 timeElapsed,
        bool hasDisputes,
        bool hasDelays
    ) external pure returns (uint256) {
        uint256 dynamicScore = baseRiskScore;
        
        // Time-based risk increase
        uint256 daysPassed = timeElapsed / 1 days;
        if (daysPassed > 30) {
            dynamicScore += (daysPassed - 30) / 10; // +1 point per 10 days after 30 days
        }
        
        // Dispute history increases risk
        if (hasDisputes) {
            dynamicScore += 20;
        }
        
        // Delivery delays increase risk
        if (hasDelays) {
            dynamicScore += 15;
        }
        
        // Cap at 100
        return dynamicScore > 100 ? 100 : dynamicScore;
    }
    
    /**
     * @dev Generate risk mitigation recommendations
     */
    function getRiskMitigationRecommendations(uint256 contractId) external view returns (string[] memory) {
        TradeStructs.RiskAssessment memory assessment = riskAssessments[contractId];
        require(assessment.contractId != 0, "Risk assessment not found");
        
        string[] memory recommendations = new string[](5);
        uint256 count = 0;
        
        if (assessment.level >= TradeStructs.RiskLevel.Medium) {
            recommendations[count] = "Require additional documentation verification";
            count++;
        }
        
        if (assessment.level >= TradeStructs.RiskLevel.High) {
            recommendations[count] = "Implement milestone-based payment releases";
            count++;
            recommendations[count] = "Require insurance coverage";
            count++;
        }
        
        if (assessment.level == TradeStructs.RiskLevel.Critical) {
            recommendations[count] = "Conduct enhanced due diligence";
            count++;
            recommendations[count] = "Consider escrow service upgrade";
            count++;
        }
        
        // Resize array
        string[] memory finalRecommendations = new string[](count);
        for (uint256 i = 0; i < count; i++) {
            finalRecommendations[i] = recommendations[i];
        }
        
        return finalRecommendations;
    }
    
    // Admin functions
    function addRiskAssessor(address assessor) external onlyOwner {
        require(assessor != address(0), "Invalid assessor address");
        riskAssessors[assessor] = true;
        emit RiskAssessorAdded(assessor);
    }
    
    function removeRiskAssessor(address assessor) external onlyOwner {
        riskAssessors[assessor] = false;
        emit RiskAssessorRemoved(assessor);
    }
    
    function isRiskAssessor(address assessor) external view returns (bool) {
        return riskAssessors[assessor];
    }
}