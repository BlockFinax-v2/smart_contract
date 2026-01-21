// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../libraries/LibAppStorage.sol";
import "../libraries/LibAddressResolver.sol";

/**
 * @title AddressLinkingFacet
 * @notice Manages linking between EOA and Smart Account addresses
 * @dev Enables Account Abstraction support with EOA as primary identity
 *
 * KEY CONCEPTS:
 * - EOA (Externally Owned Account) = Primary Identity
 * - Smart Account (ERC-4337) = Transaction Method
 * - All contract state keyed by EOA address
 * - Smart account transactions automatically resolve to EOA
 */
contract AddressLinkingFacet {
    // Events
    event SmartAccountLinked(address indexed eoa, address indexed smartAccount);
    event SmartAccountUnlinked(
        address indexed eoa,
        address indexed smartAccount
    );

    // Errors
    error InvalidAddress();
    error AlreadyLinked();
    error NotLinked();
    error UnauthorizedUnlink();

    /**
     * @notice Link a smart account to your EOA
     * @dev Can only be called from the EOA that will be the primary identity
     * @param smartAccount The smart account address to link to this EOA
     */
    function linkSmartAccount(address smartAccount) external {
        if (smartAccount == address(0)) revert InvalidAddress();
        if (smartAccount == msg.sender) revert InvalidAddress();

        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        // Check if smart account is already linked
        if (s.isLinkedSmartAccount[smartAccount]) revert AlreadyLinked();

        // Check if EOA already has a smart account linked
        if (s.eoaToSmartAccount[msg.sender] != address(0))
            revert AlreadyLinked();

        // Create bidirectional link
        s.smartAccountToEOA[smartAccount] = msg.sender;
        s.eoaToSmartAccount[msg.sender] = smartAccount;
        s.isLinkedSmartAccount[smartAccount] = true;

        emit SmartAccountLinked(msg.sender, smartAccount);
    }

    /**
     * @notice Unlink your smart account
     * @dev Can only be called from the EOA that owns the link
     */
    function unlinkSmartAccount() external {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        address smartAccount = s.eoaToSmartAccount[msg.sender];
        if (smartAccount == address(0)) revert NotLinked();

        // Remove bidirectional link
        delete s.smartAccountToEOA[smartAccount];
        delete s.eoaToSmartAccount[msg.sender];
        delete s.isLinkedSmartAccount[smartAccount];

        emit SmartAccountUnlinked(msg.sender, smartAccount);
    }

    /**
     * @notice Get the linked smart account for an EOA
     * @param eoa The EOA address to query
     * @return The linked smart account address (address(0) if none)
     */
    function getLinkedSmartAccount(
        address eoa
    ) external view returns (address) {
        return LibAddressResolver.getLinkedSmartAccount(eoa);
    }

    /**
     * @notice Get the EOA for a smart account
     * @param smartAccount The smart account address to query
     * @return The linked EOA address (address(0) if none)
     */
    function getLinkedEOA(
        address smartAccount
    ) external view returns (address) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        return s.smartAccountToEOA[smartAccount];
    }

    /**
     * @notice Check if an address is a linked smart account
     * @param account The address to check
     * @return True if it's a linked smart account
     */
    function isLinkedSmartAccount(
        address account
    ) external view returns (bool) {
        return LibAddressResolver.isSmartAccount(account);
    }

    /**
     * @notice Get comprehensive linking information for an address
     * @param account The address to query
     * @return isLinked Whether the address is part of a link
     * @return linkedAddress The linked address (EOA if account is SA, SA if account is EOA)
     * @return primaryIdentity The primary identity (always EOA)
     */
    function getLinkInfo(
        address account
    )
        external
        view
        returns (bool isLinked, address linkedAddress, address primaryIdentity)
    {
        return LibAddressResolver.getLinkInfo(account);
    }

    /**
     * @notice Resolve any address to its primary identity (EOA)
     * @dev Useful for frontend to determine which address to display
     * @param account Address to resolve (could be EOA or Smart Account)
     * @return Primary identity address (always EOA)
     */
    function resolveToPrimaryIdentity(
        address account
    ) external view returns (address) {
        return LibAddressResolver.resolveToEOA(account);
    }
}
