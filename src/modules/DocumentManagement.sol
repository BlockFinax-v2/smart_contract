// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/utils/Counters.sol";
import "../libraries/TradeStructs.sol";
import "../BaseModule.sol";

/**
 * @title DocumentManagement
 * @dev Module for managing trade documents and verification
 */
contract DocumentManagement is BaseModule {
    using Counters for Counters.Counter;
    
    Counters.Counter private _documentIds;
    
    // Storage
    mapping(uint256 => TradeStructs.Document) public documents;
    mapping(uint256 => uint256[]) public contractDocuments;
    mapping(bytes32 => bool) public usedChecksums; // Prevent duplicate uploads
    
    // Events
    event DocumentUploaded(uint256 indexed documentId, uint256 indexed contractId, TradeStructs.DocumentType docType);
    event DocumentVerified(uint256 indexed documentId, address indexed verifier);
    event DocumentUpdated(uint256 indexed documentId, string newIpfsHash);
    event DocumentRevoked(uint256 indexed documentId, string reason);
    
    /**
     * @dev Upload document with enhanced metadata
     */
    function uploadDocument(
        uint256 contractId,
        string calldata _name,
        string calldata _ipfsHash,
        TradeStructs.DocumentType _docType,
        bool _isRequired,
        string calldata _description,
        bytes32 _checksum
    ) external whenNotPaused returns (uint256) {
        require(contractId > 0, "Invalid contract ID");
        require(bytes(_name).length > 0, "Document name required");
        require(bytes(_ipfsHash).length > 0, "IPFS hash required");
        require(!usedChecksums[_checksum], "Document already exists");
        
        _documentIds.increment();
        uint256 documentId = _documentIds.current();
        
        documents[documentId] = TradeStructs.Document({
            id: documentId,
            contractId: contractId,
            name: _name,
            ipfsHash: _ipfsHash,
            docType: _docType,
            uploader: msg.sender,
            timestamp: block.timestamp,
            isVerified: false,
            isRequired: _isRequired,
            description: _description,
            checksum: _checksum
        });
        
        contractDocuments[contractId].push(documentId);
        usedChecksums[_checksum] = true;
        
        emit DocumentUploaded(documentId, contractId, _docType);
        
        return documentId;
    }
    
    /**
     * @dev Verify document authenticity
     */
    function verifyDocument(uint256 documentId) external onlyOwner {
        require(documents[documentId].id != 0, "Document does not exist");
        require(!documents[documentId].isVerified, "Document already verified");
        
        documents[documentId].isVerified = true;
        emit DocumentVerified(documentId, msg.sender);
    }
    
    /**
     * @dev Update document IPFS hash (for version control)
     */
    function updateDocument(
        uint256 documentId, 
        string calldata newIpfsHash,
        bytes32 newChecksum
    ) external {
        require(documents[documentId].id != 0, "Document does not exist");
        require(documents[documentId].uploader == msg.sender, "Only uploader can update");
        require(!usedChecksums[newChecksum], "New document version already exists");
        
        // Mark old checksum as unused and new one as used
        usedChecksums[documents[documentId].checksum] = false;
        usedChecksums[newChecksum] = true;
        
        documents[documentId].ipfsHash = newIpfsHash;
        documents[documentId].checksum = newChecksum;
        documents[documentId].isVerified = false; // Require re-verification
        documents[documentId].timestamp = block.timestamp;
        
        emit DocumentUpdated(documentId, newIpfsHash);
    }
    
    /**
     * @dev Revoke document (mark as invalid)
     */
    function revokeDocument(uint256 documentId, string calldata reason) external onlyOwner {
        require(documents[documentId].id != 0, "Document does not exist");
        
        // Remove from used checksums to allow re-upload
        usedChecksums[documents[documentId].checksum] = false;
        
        // Clear sensitive data
        documents[documentId].ipfsHash = "";
        documents[documentId].isVerified = false;
        
        emit DocumentRevoked(documentId, reason);
    }
    
    /**
     * @dev Get documents by contract ID
     */
    function getContractDocuments(uint256 contractId) external view returns (uint256[] memory) {
        return contractDocuments[contractId];
    }
    
    /**
     * @dev Get document details
     */
    function getDocument(uint256 documentId) external view returns (TradeStructs.Document memory) {
        require(documents[documentId].id != 0, "Document does not exist");
        return documents[documentId];
    }
    
    /**
     * @dev Get documents by type for a contract
     */
    function getDocumentsByType(
        uint256 contractId, 
        TradeStructs.DocumentType docType
    ) external view returns (uint256[] memory) {
        uint256[] memory contractDocs = contractDocuments[contractId];
        uint256[] memory result = new uint256[](contractDocs.length);
        uint256 count = 0;
        
        for (uint256 i = 0; i < contractDocs.length; i++) {
            if (documents[contractDocs[i]].docType == docType) {
                result[count] = contractDocs[i];
                count++;
            }
        }
        
        // Resize array to actual count
        assembly {
            mstore(result, count)
        }
        
        return result;
    }
    
    /**
     * @dev Check if all required documents are uploaded and verified for a contract
     */
    function areRequiredDocumentsComplete(uint256 contractId) external view returns (bool) {
        uint256[] memory contractDocs = contractDocuments[contractId];
        
        // Define minimum required document types
        bool hasContract = false;
        bool hasInvoice = false;
        bool hasBillOfLading = false;
        
        for (uint256 i = 0; i < contractDocs.length; i++) {
            TradeStructs.Document memory doc = documents[contractDocs[i]];
            if (doc.isRequired && doc.isVerified) {
                if (doc.docType == TradeStructs.DocumentType.Contract) {
                    hasContract = true;
                } else if (doc.docType == TradeStructs.DocumentType.Invoice) {
                    hasInvoice = true;
                } else if (doc.docType == TradeStructs.DocumentType.BillOfLading) {
                    hasBillOfLading = true;
                }
            }
        }
        
        return hasContract && hasInvoice && hasBillOfLading;
    }
    
    /**
     * @dev Get document verification status for a contract
     */
    function getDocumentVerificationStatus(uint256 contractId) external view returns (
        uint256 totalDocuments,
        uint256 verifiedDocuments,
        uint256 requiredDocuments,
        uint256 verifiedRequiredDocuments
    ) {
        uint256[] memory contractDocs = contractDocuments[contractId];
        
        totalDocuments = contractDocs.length;
        verifiedDocuments = 0;
        requiredDocuments = 0;
        verifiedRequiredDocuments = 0;
        
        for (uint256 i = 0; i < contractDocs.length; i++) {
            TradeStructs.Document memory doc = documents[contractDocs[i]];
            
            if (doc.isVerified) {
                verifiedDocuments++;
            }
            
            if (doc.isRequired) {
                requiredDocuments++;
                if (doc.isVerified) {
                    verifiedRequiredDocuments++;
                }
            }
        }
    }
    
    /**
     * @dev Batch verify multiple documents
     */
    function batchVerifyDocuments(uint256[] calldata documentIds) external onlyOwner {
        for (uint256 i = 0; i < documentIds.length; i++) {
            uint256 documentId = documentIds[i];
            require(documents[documentId].id != 0, "Document does not exist");
            require(!documents[documentId].isVerified, "Document already verified");
            
            documents[documentId].isVerified = true;
            emit DocumentVerified(documentId, msg.sender);
        }
    }
}