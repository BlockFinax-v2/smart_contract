// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

library LibSwap {
    // keccak256(abi.encode(uint256(keccak256("bll.storage.swap")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 constant SWAP_STORAGE_POSITION = 0x2b6d8e9f7c5a4b3e2d1c0b9a8f7e6d5c4b3a2e1d0c9b8a7f6e5d4c3b2a1e0d00;

    struct SwapStorage {
        uint256 tokenPrice;
        uint256 totalEthReceived;
        bool swapEnabled;
    }

    function swapStorage() internal pure returns (SwapStorage storage ss) {
        bytes32 position = SWAP_STORAGE_POSITION;
        assembly {
            ss.slot := position
        }
    }
}
