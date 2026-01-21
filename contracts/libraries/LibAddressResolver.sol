// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./LibAppStorage.sol";

/**
 * @title LibAddressResolver
 * @notice Library for resolving Smart Account addresses to EOA (primary identity)
 * @dev This ensures users have a single identity regardless of transaction method (EOA vs AA)
 *
 * DESIGN PHILOSOPHY:
 * - EOA = Primary Identity (used in all mappings/storage)
 * - Smart Account = Transaction Method (underground, linked to EOA)
 * - All contract state keyed by EOA address
 * - Smart account transactions automatically resolve to EOA
 */
library LibAddressResolver {
    /**
     * @notice Resolve any address to its primary identity (EOA)
     * @dev If address is a linked smart account, returns the linked EOA
     *      If address is an EOA (or unlinked), returns the address itself
     * @param user Address to resolve (could be EOA or Smart Account)
     * @return Primary identity address (always EOA)
     */
    function resolveToEOA(address user) internal view returns (address) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        // If this is a linked smart account, return the linked EOA
        if (s.isLinkedSmartAccount[user]) {
            return s.smartAccountToEOA[user];
        }

        // Otherwise, return the address as-is (it's already an EOA or unlinked)
        return user;
    }

    /**
     * @notice Link a smart account to an EOA (primary identity)
     * @dev Can only be called once per smart account
     *      The msg.sender must be the EOA that owns the smart account
     * @param smartAccount The smart account address to link
     * @param eoa The EOA address (primary identity)
     */
    function linkSmartAccount(address smartAccount, address eoa) internal {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        require(smartAccount != address(0), "Invalid smart account");
        require(eoa != address(0), "Invalid EOA");
        require(
            !s.isLinkedSmartAccount[smartAccount],
            "Smart account already linked"
        );
        require(
            s.eoaToSmartAccount[eoa] == address(0),
            "EOA already has linked smart account"
        );

        // Create bidirectional link
        s.smartAccountToEOA[smartAccount] = eoa;
        s.eoaToSmartAccount[eoa] = smartAccount;
        s.isLinkedSmartAccount[smartAccount] = true;
    }

    /**
     * @notice Auto-link smart account to EOA if transaction is from smart account
     * @dev Automatically creates link when smart account first interacts
     *      This enables seamless UX - no manual linking required
     * @param possibleSmartAccount The address that might be a smart account
     * @param eoa The EOA that owns the smart account
     */
    function autoLinkIfNeeded(
        address possibleSmartAccount,
        address eoa
    ) internal {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        // Skip if already linked or if addresses are the same
        if (
            s.isLinkedSmartAccount[possibleSmartAccount] ||
            possibleSmartAccount == eoa
        ) {
            return;
        }

        // Auto-link if EOA doesn't have a smart account yet
        if (s.eoaToSmartAccount[eoa] == address(0)) {
            linkSmartAccount(possibleSmartAccount, eoa);
        }
    }

    /**
     * @notice Get the smart account linked to an EOA
     * @param eoa The EOA address
     * @return The linked smart account address (address(0) if none)
     */
    function getLinkedSmartAccount(
        address eoa
    ) internal view returns (address) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        return s.eoaToSmartAccount[eoa];
    }

    /**
     * @notice Check if an address is a linked smart account
     * @param account The address to check
     * @return True if it's a linked smart account
     */
    function isSmartAccount(address account) internal view returns (bool) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        return s.isLinkedSmartAccount[account];
    }

    /**
     * @notice Get linking information for an address
     * @param account The address to query
     * @return isLinked Whether the address is part of a link
     * @return linkedAddress The linked address (EOA if account is SA, SA if account is EOA)
     * @return primaryIdentity The primary identity (always EOA)
     */
    function getLinkInfo(
        address account
    )
        internal
        view
        returns (bool isLinked, address linkedAddress, address primaryIdentity)
    {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        if (s.isLinkedSmartAccount[account]) {
            // Account is a smart account
            isLinked = true;
            linkedAddress = s.smartAccountToEOA[account];
            primaryIdentity = linkedAddress;
        } else if (s.eoaToSmartAccount[account] != address(0)) {
            // Account is an EOA with linked smart account
            isLinked = true;
            linkedAddress = s.eoaToSmartAccount[account];
            primaryIdentity = account;
        } else {
            // Account is unlinked
            isLinked = false;
            linkedAddress = address(0);
            primaryIdentity = account;
        }
    }
}
