// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./LibDiamond.sol";

/**
 * @title LibPausable
 * @notice Library for pausable functionality to avoid duplicate function selectors across facets
 * @dev Uses diamond storage pattern to share pause state across all facets
 */
library LibPausable {
    bytes32 constant PAUSABLE_STORAGE_POSITION =
        keccak256("blockfinax.pausable.storage");

    struct PausableStorage {
        bool paused;
    }

    /**
     * @notice Get the pausable storage
     */
    function pausableStorage()
        internal
        pure
        returns (PausableStorage storage ps)
    {
        bytes32 position = PAUSABLE_STORAGE_POSITION;
        assembly {
            ps.slot := position
        }
    }

    /**
     * @notice Pause the contract (owner only)
     * @dev Can only be called by contract owner
     */
    function pause() internal {
        LibDiamond.enforceIsContractOwner();
        PausableStorage storage ps = pausableStorage();
        require(!ps.paused, "Already paused");
        ps.paused = true;
    }

    /**
     * @notice Unpause the contract (owner only)
     * @dev Can only be called by contract owner
     */
    function unpause() internal {
        LibDiamond.enforceIsContractOwner();
        PausableStorage storage ps = pausableStorage();
        require(ps.paused, "Not paused");
        ps.paused = false;
    }

    /**
     * @notice Check if contract is paused
     * @return bool True if paused, false otherwise
     */
    function isPaused() internal view returns (bool) {
        return pausableStorage().paused;
    }

    /**
     * @notice Enforce that contract is not paused
     * @dev Reverts if contract is paused
     */
    function enforceNotPaused() internal view {
        require(!pausableStorage().paused, "Contract is paused");
    }

    /**
     * @notice Enforce that contract is paused
     * @dev Reverts if contract is not paused
     */
    function enforceIsPaused() internal view {
        require(pausableStorage().paused, "Contract is not paused");
    }
}
