// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../libraries/LibDiamond.sol";

/**
 * @title DocumentManagementFacet
 * @dev Facet for managing trade documents and verification with hashing capabilities
 */
contract DocumentManagementFacet {
    
    uint256 private _documentIdCounter;
    
    // Document types enum
    enum DocumentType {
        Contract,
        Invoice,
        BillOfLading,
        Certificate,
        Insurance,
        CustomsDeclaration,
        QualityReport,
        Other
    }
    
    // Document structure
    struct Document {
        uint256 id;
        uint256 contractId;
        string name;
        string ipfsHash;
        DocumentType docType;
        address uploader;
        uint256 timestamp;
        bool isVerified;
        bool isRequired;
        string description;
        bytes32 checksum;
        bytes32 documentHash; // SHA256 hash of document content
    }
    
    // Storage
    mapping(uint256 => Document) public documents;
    mapping(uint256 => uint256[]) public contractDocuments;
    mapping(bytes32 => bool) public usedChecksums; // Prevent duplicate uploads
    mapping(bytes32 => uint256) public hashToDocumentId; // Map hash to document ID
    
    // Events
    event DocumentUploaded(uint256 indexed documentId, uint256 indexed contractId, DocumentType docType);
    event DocumentVerified(uint256 indexed documentId, address indexed verifier);
    event DocumentUpdated(uint256 indexed documentId, string newIpfsHash);
    event DocumentRevoked(uint256 indexed documentId, string reason);
    event DocumentHashVerified(uint256 indexed documentId, bytes32 documentHash);
    
    // Storage for reentrancy guard
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;
    
    // Storage for pausable functionality
    bool private _paused;
    
    // Events for pausable
    event Paused(address account);
    event Unpaused(address account);
    
    // Modifiers
    modifier onlyOwner() {
        LibDiamond.enforceIsContractOwner();
        _;
    }
    
    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
    
    modifier whenNotPaused() {
        require(!_paused, "Pausable: paused");
        _;
    }
    
    modifier whenPaused() {
        require(_paused, "Pausable: not paused");
        _;
    }
    
    /**
     * @dev Upload document with enhanced metadata and hashing
     */
    function uploadDocument(
        uint256 contractId,
        string calldata _name,
        string calldata _ipfsHash,
        DocumentType _docType,
        bool _isRequired,
        string calldata _description,
        bytes32 _checksum,
        bytes calldata _documentContent
    ) external whenNotPaused returns (uint256) {
        require(contractId > 0, "Invalid contract ID");
        require(bytes(_name).length > 0, "Document name required");
        require(bytes(_ipfsHash).length > 0, "IPFS hash required");
        require(!usedChecksums[_checksum], "Document already exists");
        require(_documentContent.length > 0, "Document content required");
        
        // Generate document hash
        bytes32 documentHash = sha256(_documentContent);
        require(hashToDocumentId[documentHash] == 0, "Document with same content already exists");
        
        _documentIdCounter++;
        uint256 documentId = _documentIdCounter;
        
        documents[documentId] = Document({
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
            checksum: _checksum,
            documentHash: documentHash
        });
        
        contractDocuments[contractId].push(documentId);
        usedChecksums[_checksum] = true;
        hashToDocumentId[documentHash] = documentId;
        
        emit DocumentUploaded(documentId, contractId, _docType);
        emit DocumentHashVerified(documentId, documentHash);
        
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
     * @dev Verify document content against stored hash
     */
    function verifyDocumentContent(uint256 documentId, bytes calldata content) external view returns (bool) {
        require(documents[documentId].id != 0, "Document does not exist");
        bytes32 contentHash = sha256(content);
        return contentHash == documents[documentId].documentHash;
    }
    
    /**
     * @dev Get document hash for external verification
     */
    function getDocumentHash(uint256 documentId) external view returns (bytes32) {
        require(documents[documentId].id != 0, "Document does not exist");
        return documents[documentId].documentHash;
    }
    
    /**
     * @dev Update document IPFS hash and content (for version control)
     */
    function updateDocument(
        uint256 documentId, 
        string calldata newIpfsHash,
        bytes32 newChecksum,
        bytes calldata newContent
    ) external {
        require(documents[documentId].id != 0, "Document does not exist");
        require(documents[documentId].uploader == msg.sender, "Only uploader can update");
        require(!usedChecksums[newChecksum], "New document version already exists");
        require(newContent.length > 0, "Document content required");
        
        // Generate new document hash
        bytes32 newDocumentHash = sha256(newContent);
        require(hashToDocumentId[newDocumentHash] == 0, "Document with same content already exists");
        
        // Clean up old mappings
        usedChecksums[documents[documentId].checksum] = false;
        hashToDocumentId[documents[documentId].documentHash] = 0;
        
        // Update with new values
        usedChecksums[newChecksum] = true;
        hashToDocumentId[newDocumentHash] = documentId;
        
        documents[documentId].ipfsHash = newIpfsHash;
        documents[documentId].checksum = newChecksum;
        documents[documentId].documentHash = newDocumentHash;
        documents[documentId].isVerified = false; // Require re-verification
        documents[documentId].timestamp = block.timestamp;
        
        emit DocumentUpdated(documentId, newIpfsHash);
        emit DocumentHashVerified(documentId, newDocumentHash);
    }
    
    
    /**
     * @dev Revoke document (mark as invalid)
     */
    function revokeDocument(uint256 documentId, string calldata reason) external onlyOwner {
        require(documents[documentId].id != 0, "Document does not exist");
        
        // Remove from used checksums and hash mappings to allow re-upload
        usedChecksums[documents[documentId].checksum] = false;
        hashToDocumentId[documents[documentId].documentHash] = 0;
        
        // Clear sensitive data
        documents[documentId].ipfsHash = "";
        documents[documentId].isVerified = false;
        documents[documentId].documentHash = bytes32(0);
        
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
    function getDocument(uint256 documentId) external view returns (Document memory) {
        require(documents[documentId].id != 0, "Document does not exist");
        return documents[documentId];
    }
    
    /**
     * @dev Get documents by type for a contract
     */
    function getDocumentsByType(
        uint256 contractId, 
        DocumentType docType
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
            Document memory doc = documents[contractDocs[i]];
            if (doc.isRequired && doc.isVerified) {
                if (doc.docType == DocumentType.Contract) {
                    hasContract = true;
                } else if (doc.docType == DocumentType.Invoice) {
                    hasInvoice = true;
                } else if (doc.docType == DocumentType.BillOfLading) {
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
            Document memory doc = documents[contractDocs[i]];
            
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
    
    /**
     * @dev Pause the contract
     */
    function pauseDocumentManagement() external onlyOwner {
        _paused = true;
        emit Paused(msg.sender);
    }
    
    /**
     * @dev Unpause the contract
     */
    function unpauseDocumentManagement() external onlyOwner {
        _paused = false;
        emit Unpaused(msg.sender);
    }
    
    /**
     * @dev Check if contract is paused
     */
    function isDocumentManagementPaused() external view returns (bool) {
        return _paused;
    }
    
    /**
     * @dev Initialize the storage variables
     */
    function initializeDocumentManagement() external onlyOwner {
        require(_status == 0, "Already initialized");
        _status = _NOT_ENTERED;
        _paused = false;
    }
}