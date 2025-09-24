// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/BlockFinaxtradePlatform.sol";
import "../src/modules/ContractManagement.sol";
import "../src/modules/DocumentManagement.sol";
import "../src/modules/InvoiceManagement.sol";
import "../src/modules/ShipmentManagement.sol";
import "../src/modules/RiskManagement.sol";
import "../src/modules/DisputeManagement.sol";

/**
 * @title Deploy Script for BlockFinax Trade Platform
 * @dev Foundry deployment script
 * 
 * Usage:
 * forge script script/Deploy.s.sol --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast --verify
 * 
 * Or with environment variables:
 * forge script script/Deploy.s.sol --rpc-url sepolia --broadcast --verify
 */
contract DeployScript is Script {
    
    // Deployment configuration
    struct DeployConfig {
        address feeRecipient;
        uint256 platformFeeRate;
        uint256 minContractValue;
        bool verifyContracts;
    }
    
    // Deployed contract addresses
    struct DeployedContracts {
        address mainPlatform;
        address contractManagement;
        address documentManagement;
        address invoiceManagement;
        address shipmentManagement;
        address riskManagement;
        address disputeManagement;
    }
    
    function run() external returns (DeployedContracts memory) {
        // Load configuration
        DeployConfig memory config = _loadConfig();
        
        console.log("=== BlockFinax Trade Platform Deployment ===");
        console.log("Network:", block.chainid);
        console.log("Deployer:", msg.sender);
        console.log("Fee Recipient:", config.feeRecipient);
        console.log("Platform Fee Rate:", config.platformFeeRate);
        
        // Start broadcasting transactions
        vm.startBroadcast();
        
        // Deploy the main platform contract
        console.log("\n1. Deploying BlockFinaxTradePlatform...");
        BlockFinaxTradePlatform platform = new BlockFinaxTradePlatform(config.feeRecipient);
        console.log("Main Platform deployed at:", address(platform));
        
        // Get module addresses from the main contract
        console.log("\n2. Getting module addresses...");
        (
            address contractMgmt,
            address docMgmt,
            address invoiceMgmt,
            address shipmentMgmt,
            address riskMgmt,
            address disputeMgmt,
            bool isPaused
        ) = platform.getPlatformInfo();
        
        console.log("Contract Management:", contractMgmt);
        console.log("Document Management:", docMgmt);
        console.log("Invoice Management:", invoiceMgmt);
        console.log("Shipment Management:", shipmentMgmt);
        console.log("Risk Management:", riskMgmt);
        console.log("Dispute Management:", disputeMgmt);
        console.log("Platform Paused:", isPaused);
        
        // Setup initial configuration
        console.log("\n3. Setting up initial configuration...");
        _setupInitialConfig(platform, contractMgmt, riskMgmt, disputeMgmt, shipmentMgmt);
        
        // Stop broadcasting
        vm.stopBroadcast();
        
        // Create deployment info
        DeployedContracts memory deployed = DeployedContracts({
            mainPlatform: address(platform),
            contractManagement: contractMgmt,
            documentManagement: docMgmt,
            invoiceManagement: invoiceMgmt,
            shipmentManagement: shipmentMgmt,
            riskManagement: riskMgmt,
            disputeManagement: disputeMgmt
        });
        
        // Save deployment information
        _saveDeploymentInfo(deployed, config);
        
        // Print verification commands if needed
        if (config.verifyContracts) {
            _printVerificationCommands(deployed, config);
        }
        
        console.log("\n=== Deployment Complete ===");
        
        return deployed;
    }
    
    function _loadConfig() internal view returns (DeployConfig memory) {
        // Try to load from environment variables, fallback to defaults
        address feeRecipient = vm.envOr("FEE_RECIPIENT", msg.sender);
        uint256 platformFeeRate = vm.envOr("PLATFORM_FEE_RATE", uint256(250)); // 2.5%
        uint256 minContractValue = vm.envOr("MIN_CONTRACT_VALUE", uint256(100));
        bool verifyContracts = vm.envOr("VERIFY_CONTRACTS", true);
        
        return DeployConfig({
            feeRecipient: feeRecipient,
            platformFeeRate: platformFeeRate,
            minContractValue: minContractValue,
            verifyContracts: verifyContracts
        });
    }
    
    function _setupInitialConfig(
        BlockFinaxTradePlatform platform,
        address contractMgmt,
        address riskMgmt,
        address disputeMgmt,
        address shipmentMgmt
    ) internal {
        // Verify deployer as first user
        platform.verifyUser(msg.sender);
        console.log("Deployer verified as user");
        
        // Setup risk management
        RiskManagement riskManagement = RiskManagement(riskMgmt);
        riskManagement.addRiskAssessor(msg.sender);
        console.log("Deployer added as risk assessor");
        
        // Setup dispute management
        DisputeManagement disputeManagement = DisputeManagement(disputeMgmt);
        disputeManagement.addArbitrator(msg.sender);
        console.log("Deployer added as arbitrator");
        
        // Setup shipment management
        ShipmentManagement shipmentManagement = ShipmentManagement(shipmentMgmt);
        shipmentManagement.authorizeCarrier(msg.sender);
        console.log("Deployer authorized as carrier");
        
        // Add additional countries if specified
        string[] memory additionalCountries = _getAdditionalCountries();
        for (uint256 i = 0; i < additionalCountries.length; i++) {
            platform.addSupportedCountry(additionalCountries[i]);
            console.log("Added country:", additionalCountries[i]);
        }
        
        // Add additional currencies if specified
        string[] memory additionalCurrencies = _getAdditionalCurrencies();
        for (uint256 i = 0; i < additionalCurrencies.length; i++) {
            platform.addSupportedCurrency(additionalCurrencies[i]);
            console.log("Added currency:", additionalCurrencies[i]);
        }
    }
    
    function _getAdditionalCountries() internal pure returns (string[] memory) {
        // Return additional countries to be added beyond defaults
        string[] memory countries = new string[](5);
        countries[0] = "UG"; // Uganda
        countries[1] = "TZ"; // Tanzania
        countries[2] = "ZM"; // Zambia
        countries[3] = "BF"; // Burkina Faso
        countries[4] = "ML"; // Mali
        return countries;
    }
    
    function _getAdditionalCurrencies() internal pure returns (string[] memory) {
        // Return additional currencies to be added beyond defaults
        string[] memory currencies = new string[](3);
        currencies[0] = "UGX"; // Ugandan Shilling
        currencies[1] = "TZS"; // Tanzanian Shilling
        currencies[2] = "ZMW"; // Zambian Kwacha
        return currencies;
    }
    
    function _saveDeploymentInfo(DeployedContracts memory deployed, DeployConfig memory config) internal {
        string memory chainName = _getChainName(block.chainid);
        
        // Create JSON object with deployment info
        string memory json = "deployment";
        vm.serializeString(json, "network", chainName);
        vm.serializeUint(json, "chainId", block.chainid);
        vm.serializeAddress(json, "deployer", msg.sender);
        vm.serializeAddress(json, "feeRecipient", config.feeRecipient);
        vm.serializeUint(json, "platformFeeRate", config.platformFeeRate);
        vm.serializeUint(json, "minContractValue", config.minContractValue);
        vm.serializeUint(json, "blockNumber", block.number);
        vm.serializeUint(json, "timestamp", block.timestamp);
        
        // Add contract addresses
        vm.serializeAddress(json, "mainPlatform", deployed.mainPlatform);
        vm.serializeAddress(json, "contractManagement", deployed.contractManagement);
        vm.serializeAddress(json, "documentManagement", deployed.documentManagement);
        vm.serializeAddress(json, "invoiceManagement", deployed.invoiceManagement);
        vm.serializeAddress(json, "shipmentManagement", deployed.shipmentManagement);
        vm.serializeAddress(json, "riskManagement", deployed.riskManagement);
        string memory finalJson = vm.serializeAddress(json, "disputeManagement", deployed.disputeManagement);
        
        // Write to file
        string memory fileName = string.concat("deployments/", chainName, "-deployment.json");
        vm.writeJson(finalJson, fileName);
        console.log("Deployment info saved to:", fileName);
    }
    
    function _printVerificationCommands(DeployedContracts memory deployed, DeployConfig memory config) internal view {
        string memory chainName = _getChainName(block.chainid);
        
        console.log("\n=== Verification Commands ===");
        console.log("Run these commands to verify contracts on Etherscan:");
        console.log("");
        
        // Main platform
        console.log("# Main Platform");
        console.log(string.concat(
            "forge verify-contract ",
            vm.toString(deployed.mainPlatform),
            " src/BlockFinaxTradePlatform.sol:BlockFinaxTradePlatform",
            " --chain-id ", vm.toString(block.chainid),
            " --constructor-args $(cast abi-encode 'constructor(address)' ",
            vm.toString(config.feeRecipient), ")"
        ));
        console.log("");
        
        // Contract Management
        console.log("# Contract Management");
        console.log(string.concat(
            "forge verify-contract ",
            vm.toString(deployed.contractManagement),
            " src/modules/ContractManagement.sol:ContractManagement",
            " --chain-id ", vm.toString(block.chainid),
            " --constructor-args $(cast abi-encode 'constructor(address)' ",
            vm.toString(config.feeRecipient), ")"
        ));
        console.log("");
        
        // Other modules (no constructor args)
        string[5] memory moduleNames = [
            "DocumentManagement",
            "InvoiceManagement", 
            "ShipmentManagement",
            "RiskManagement",
            "DisputeManagement"
        ];
        
        address[5] memory moduleAddresses = [
            deployed.documentManagement,
            deployed.invoiceManagement,
            deployed.shipmentManagement,
            deployed.riskManagement,
            deployed.disputeManagement
        ];
        
        for (uint256 i = 0; i < moduleNames.length; i++) {
            console.log(string.concat("# ", moduleNames[i]));
            console.log(string.concat(
                "forge verify-contract ",
                vm.toString(moduleAddresses[i]),
                " src/modules/", moduleNames[i], ".sol:", moduleNames[i],
                " --chain-id ", vm.toString(block.chainid)
            ));
            console.log("");
        }
    }
    
    function _getChainName(uint256 chainId) internal pure returns (string memory) {
        if (chainId == 1) return "mainnet";
        if (chainId == 5) return "goerli";
        if (chainId == 11155111) return "sepolia";
        if (chainId == 137) return "polygon";
        if (chainId == 80001) return "mumbai";
        if (chainId == 42161) return "arbitrum";
        if (chainId == 10) return "optimism";
        if (chainId == 8453) return "base";
        if (chainId == 31337) return "localhost";
        return "unknown";
    }
}

/**
 * @title Deploy Script for Development
 * @dev Simplified deployment for local development
 */
contract DeployDev is Script {
    function run() external {
        vm.startBroadcast();
        
        console.log("Deploying to local network...");
        console.log("Deployer:", msg.sender);
        
        // Deploy with deployer as fee recipient
        BlockFinaxTradePlatform platform = new BlockFinaxTradePlatform(msg.sender);
        console.log("Platform deployed at:", address(platform));
        
        // Basic setup
        platform.verifyUser(msg.sender);
        console.log("Deployer verified");
        
        vm.stopBroadcast();
        
        console.log("\nDevelopment deployment complete!");
        console.log("You can now interact with the platform at:", address(platform));
    }
}