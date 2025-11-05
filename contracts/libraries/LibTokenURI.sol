// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

library LibTokenURI {
    // keccak256(abi.encode(uint256(keccak256("bll.storage.tokenuri")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 constant TOKENURI_STORAGE_POSITION = 0x4d8f0a9b7e6c5d4a3b2e1d0c9f8e7d6c5b4a3e2d1c0b9a8f7e6d5c4b3a2e1d00;

    struct TokenURIStorage {
        string description;
        string externalUrl;
        string backgroundColor;
    }

    function tokenURIStorage() internal pure returns (TokenURIStorage storage ts) {
        bytes32 position = TOKENURI_STORAGE_POSITION;
        assembly {
            ts.slot := position
        }
    }
}
