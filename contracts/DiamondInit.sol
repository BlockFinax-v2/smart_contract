// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {LibDiamond} from "./libraries/LibDiamond.sol";
import {LibAppStorage} from "./libraries/LibAppStorage.sol";
import {IDiamondCut} from "./interfaces/IDiamondCut.sol";

contract DiamondInit {
    function init(
        address _usdcToken,
        uint256 _minimumStake,
        uint256 _initialApr,
        uint256 _minLockDuration,
        uint256 _aprReductionPerThousand,
        uint256 _emergencyWithdrawPenalty
    ) external {
        // Initialize LibAppStorage with provided values
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        // Set token and staking configuration
        s.usdcToken = _usdcToken;
        s.minimumStake = _minimumStake;
        s.initialApr = _initialApr;
        s.currentRewardRate = _initialApr;
        s.minLockDuration = _minLockDuration;
        s.aprReductionPerThousand = _aprReductionPerThousand;
        s.emergencyWithdrawPenalty = _emergencyWithdrawPenalty;

        // Set initial DAO configuration
        s.votingDuration = 7 days;
        s.proposalThreshold = _minimumStake * 5; // 5x minimum for proposals
        s.approvalThreshold = 51; // 51%
        s.minimumFinancierStake = _minimumStake * 10; // 10x minimum for financiers
        s.minFinancierLockDuration = _minLockDuration * 2; // 2x lock duration
        s.minNormalStakerLockDuration = _minLockDuration;
        s.revocationPeriod = 30 days;

        // Initialize Diamond storage with supported interfaces
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        ds.supportedInterfaces[type(IDiamondCut).interfaceId] = true;
        ds.supportedInterfaces[0x01ffc9a7] = true; // ERC165
        ds.supportedInterfaces[0x48e2b093] = true; // DiamondLoupe
        ds.supportedInterfaces[0x7f5828d0] = true; // ERC173 (Ownership)
    }
}
