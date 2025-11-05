// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

library LibMultiSig {
    // keccak256(abi.encode(uint256(keccak256("bll.storage.multisig")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 constant MULTISIG_STORAGE_POSITION = 0x3c7e9f8a6d5b4e3c2d1b0a9f8e7d6c5b4a3e2d1c0b9a8f7e6d5c4b3a2e1d0c00;

    struct Transaction {
        address to;
        uint256 value;
        bytes data;
        bool executed;
        uint256 confirmations;
    }

    struct MultiSigStorage {
        address[] owners;
        mapping(address => bool) isOwner;
        uint256 requiredConfirmations;
        
        Transaction[] transactions;
        mapping(uint256 => mapping(address => bool)) confirmations;
    }

    function multiSigStorage() internal pure returns (MultiSigStorage storage ms) {
        bytes32 position = MULTISIG_STORAGE_POSITION;
        assembly {
            ms.slot := position
        }
    }
}
