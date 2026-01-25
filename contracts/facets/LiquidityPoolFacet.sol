// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../libraries/LibAppStorage.sol";
import "../libraries/LibDiamond.sol";
import "../libraries/LibAddressResolver.sol";
import "../libraries/LibPausable.sol";

contract LiquidityPoolFacet is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Custom Errors
    error ZeroAmount();
    error BelowMinimumStake();
    error InsufficientBalance();
    error NoActiveStake();
    error InsufficientStakedAmount();
    error LockDurationNotMet();
    error NothingToUnstake();
    error NoRewardsToCllaim();
    error StakerNotActive();
    error ContractPaused();
    error NotContractOwner();
    error InvalidAPR();
    error InvalidLockDuration();
    error InvalidPenalty();
    error InsufficientAllowance();
    error InvalidDeadline();
    error TransferFailed();
    error FinanciersCannotEmergencyWithdraw();
    error ExcessiveAmount();
    error InvalidVotingPower();
    error InvalidTokenAddress();

    event Staked(
        address indexed staker,
        uint256 amount,
        uint256 votingPower,
        uint256 currentApr,
        uint256 deadline,
        bool isFinancier
    );
    event FinancierStatusChanged(address indexed staker, bool isFinancier);
    event CustomDeadlineSet(address indexed staker, uint256 deadline);
    event Unstaked(address indexed staker, uint256 amount, uint256 rewards);
    event RewardsDistributed(address indexed staker, uint256 amount);
    event RewardsClaimed(address indexed staker, uint256 amount);
    event EmergencyWithdrawn(
        address indexed staker,
        uint256 amount,
        uint256 penalty
    );
    event RewardRateUpdated(
        uint256 oldRate,
        uint256 newRate,
        uint256 totalStaked
    );
    event StakingConfigUpdated(
        string parameter,
        uint256 oldValue,
        uint256 newValue
    );
    event Paused(address account);
    event Unpaused(address account);

    // Constants for precision and calculations
    uint256 private constant PRECISION = 1e18;
    uint256 private constant SECONDS_PER_YEAR = 365 days;
    uint256 private constant PERCENTAGE_BASE = 100;
    uint256 private constant MIN_APR = 10; // 1% minimum APR

    modifier whenNotPaused() {
        if (LibPausable.isPaused()) revert ContractPaused();
        _;
    }

    /**
     * @notice Apply to become a financier (multi-token mode)
     * @dev Upgrades all active stakes to financier status if total USD value meets minimum
     */
    function applyAsFinancier() external {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        // Resolve address to primary identity (EOA)
        address staker = LibAddressResolver.resolveToEOA(msg.sender);

        // Check multi-token stakes
        uint256 totalUsdValue = 0;
        bool hasActiveStake = false;
        bool alreadyFinancier = false;

        for (uint256 i = 0; i < s.supportedStakingTokens.length; i++) {
            address tokenAddress = s.supportedStakingTokens[i];
            LibAppStorage.Stake storage tokenStake = s.stakesPerToken[staker][
                tokenAddress
            ];

            if (tokenStake.active && tokenStake.amount > 0) {
                hasActiveStake = true;
                totalUsdValue += tokenStake.usdEquivalent;
                if (tokenStake.isFinancier) {
                    alreadyFinancier = true;
                }
            }
        }

        require(hasActiveStake, "Must be active staker");
        require(
            totalUsdValue >= s.minimumFinancierStake,
            "Insufficient stake for financier status"
        );
        require(!alreadyFinancier, "Already a financier");

        // Update all active token stakes to financier status and extend deadlines
        uint256 minFinancierDeadline = block.timestamp +
            s.minFinancierLockDuration;

        for (uint256 i = 0; i < s.supportedStakingTokens.length; i++) {
            address tokenAddress = s.supportedStakingTokens[i];
            LibAppStorage.Stake storage tokenStake = s.stakesPerToken[staker][
                tokenAddress
            ];

            if (tokenStake.active && tokenStake.amount > 0) {
                tokenStake.isFinancier = true;

                // Extend deadline if needed
                if (tokenStake.deadline < minFinancierDeadline) {
                    tokenStake.deadline = minFinancierDeadline;
                    emit CustomDeadlineSet(staker, minFinancierDeadline);
                }
            }
        }

        // Recalculate voting powers to grant financier voting power
        _recalculateAllVotingPowers();

        emit FinancierStatusChanged(staker, true);
    }

    /**
     * @notice Set custom deadline for existing stake
     * @dev Uses address resolution: EOA is primary identity
     */
    function setCustomDeadline(uint256 newDeadline) external {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        // Resolve address to primary identity (EOA)
        address staker = LibAddressResolver.resolveToEOA(msg.sender);

        // Check multi-token storage for active stakes
        bool hasActiveStake = false;
        bool hasFinancierStatus = false;

        for (uint256 i = 0; i < s.supportedStakingTokens.length; i++) {
            address tokenAddress = s.supportedStakingTokens[i];
            LibAppStorage.Stake storage tokenStake = s.stakesPerToken[staker][
                tokenAddress
            ];
            if (tokenStake.active && tokenStake.amount > 0) {
                hasActiveStake = true;
                if (tokenStake.isFinancier) {
                    hasFinancierStatus = true;
                }
            }
        }

        require(hasActiveStake, "Must be active staker");

        uint256 minDeadline;
        if (hasFinancierStatus) {
            minDeadline = block.timestamp + s.minFinancierLockDuration;
        } else {
            minDeadline = block.timestamp + s.minNormalStakerLockDuration;
        }

        require(newDeadline >= minDeadline, "Deadline below minimum required");

        // Update deadline for all active token stakes
        for (uint256 i = 0; i < s.supportedStakingTokens.length; i++) {
            address tokenAddress = s.supportedStakingTokens[i];
            LibAppStorage.Stake storage tokenStake = s.stakesPerToken[staker][
                tokenAddress
            ];
            if (tokenStake.active && tokenStake.amount > 0) {
                tokenStake.deadline = newDeadline;
            }
        }

        emit CustomDeadlineSet(staker, newDeadline);
    }

    /**
     * @notice Get stake information with financier status
     * @dev Resolves address to primary identity (EOA)
     */
    /**
     * @notice Get aggregated stake information across all tokens (LEGACY - for backward compatibility)
     * @dev Returns combined data from all token stakes for compatibility with old UI
     * @param staker Address to check
     */
    function getStake(
        address staker
    )
        external
        view
        returns (
            uint256 amount,
            uint256 timestamp,
            uint256 votingPower,
            bool active,
            uint256 pendingRewards,
            uint256 timeUntilUnlock,
            uint256 deadline,
            bool financierStatus
        )
    {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        // Resolve address to primary identity (EOA)
        address resolvedStaker = LibAddressResolver.resolveToEOA(staker);

        // Aggregate data from all token stakes
        uint256 totalUsdValue = 0;
        uint256 totalVotingPower = 0;
        uint256 earliestTimestamp = type(uint256).max;
        uint256 latestDeadline = 0;
        bool hasActiveStake = false;
        bool hasFinancierStake = false;

        for (uint256 i = 0; i < s.supportedStakingTokens.length; i++) {
            address tokenAddress = s.supportedStakingTokens[i];
            LibAppStorage.Stake storage tokenStake = s.stakesPerToken[
                resolvedStaker
            ][tokenAddress];

            if (tokenStake.active && tokenStake.amount > 0) {
                hasActiveStake = true;
                totalUsdValue += tokenStake.usdEquivalent;
                totalVotingPower += tokenStake.votingPower;

                if (tokenStake.timestamp < earliestTimestamp) {
                    earliestTimestamp = tokenStake.timestamp;
                }
                if (tokenStake.deadline > latestDeadline) {
                    latestDeadline = tokenStake.deadline;
                }
                if (tokenStake.isFinancier) {
                    hasFinancierStake = true;
                }
            }
        }

        // Calculate time until unlock based on latest deadline
        uint256 unlockTime = 0;
        if (hasActiveStake && block.timestamp < latestDeadline) {
            unlockTime = latestDeadline - block.timestamp;
        }

        // Use earliest timestamp if found, otherwise 0
        uint256 stakeTimestamp = (earliestTimestamp == type(uint256).max)
            ? 0
            : earliestTimestamp;

        return (
            totalUsdValue, // Return USD equivalent (18 decimals) instead of token amount
            stakeTimestamp,
            totalVotingPower,
            hasActiveStake,
            getPendingRewards(resolvedStaker), // Already aggregated in fixed function
            unlockTime,
            latestDeadline,
            hasFinancierStake
        );
    }

    /**
     * @notice Check if address is a financier (unified multi-token check)
     * @dev Resolves address to primary identity (EOA)
     * @dev Checks multi-token storage for financier status
     * @dev Returns false if revocation is pending (matches governance access rules)
     */
    function isFinancier(address account) external view returns (bool) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        // Resolve address to primary identity (EOA)
        address resolvedAccount = LibAddressResolver.resolveToEOA(account);

        // Check multi-token storage
        // A user is a financier if they have ANY token staked as financier with sufficient total USD value
        uint256 totalUsdValue = 0;
        bool hasFinancierStake = false;
        bool hasRevocationPending = false;

        for (uint256 i = 0; i < s.supportedStakingTokens.length; i++) {
            address tokenAddress = s.supportedStakingTokens[i];
            LibAppStorage.Stake storage tokenStake = s.stakesPerToken[
                resolvedAccount
            ][tokenAddress];

            if (tokenStake.active && tokenStake.amount > 0) {
                totalUsdValue += tokenStake.usdEquivalent;
                if (tokenStake.isFinancier) {
                    hasFinancierStake = true;
                    // Check if revocation is pending
                    if (tokenStake.revocationRequested) {
                        hasRevocationPending = true;
                    }
                }
            }
        }

        // Return false if revocation is pending (same as onlyFinancier modifier)
        if (hasRevocationPending) {
            return false;
        }

        return hasFinancierStake && totalUsdValue >= s.minimumFinancierStake;
    }

    /**
     * @notice Get all financiers
     * @dev Excludes financiers with pending revocation requests
     */
    function getFinanciers() external view returns (address[] memory) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        // Count financiers first (check multi-token storage)
        uint256 financierCount = 0;
        for (uint256 i = 0; i < s.stakers.length; i++) {
            address staker = s.stakers[i];
            bool hasFinancierStatus = false;
            bool hasRevocationPending = false;
            uint256 totalUsdValue = 0;

            // Check all tokens for this staker
            for (uint256 j = 0; j < s.supportedStakingTokens.length; j++) {
                address tokenAddress = s.supportedStakingTokens[j];
                LibAppStorage.Stake storage tokenStake = s.stakesPerToken[
                    staker
                ][tokenAddress];

                if (tokenStake.active && tokenStake.amount > 0) {
                    totalUsdValue += tokenStake.usdEquivalent;
                    if (tokenStake.isFinancier) {
                        hasFinancierStatus = true;
                        if (tokenStake.revocationRequested) {
                            hasRevocationPending = true;
                        }
                    }
                }
            }

            if (
                hasFinancierStatus &&
                !hasRevocationPending &&
                totalUsdValue >= s.minimumFinancierStake
            ) {
                financierCount++;
            }
        }

        // Create array and populate
        address[] memory financiers = new address[](financierCount);
        uint256 index = 0;

        for (uint256 i = 0; i < s.stakers.length; i++) {
            address staker = s.stakers[i];
            bool hasFinancierStatus = false;
            bool hasRevocationPending = false;
            uint256 totalUsdValue = 0;

            // Check all tokens for this staker
            for (uint256 j = 0; j < s.supportedStakingTokens.length; j++) {
                address tokenAddress = s.supportedStakingTokens[j];
                LibAppStorage.Stake storage tokenStake = s.stakesPerToken[
                    staker
                ][tokenAddress];

                if (tokenStake.active && tokenStake.amount > 0) {
                    totalUsdValue += tokenStake.usdEquivalent;
                    if (tokenStake.isFinancier) {
                        hasFinancierStatus = true;
                        if (tokenStake.revocationRequested) {
                            hasRevocationPending = true;
                        }
                    }
                }
            }

            if (
                hasFinancierStatus &&
                !hasRevocationPending &&
                totalUsdValue >= s.minimumFinancierStake
            ) {
                financiers[index] = staker;
                index++;
            }
        }

        return financiers;
    }

    /**
     * @notice Get pool statistics
     * @dev Returns aggregate stats across all supported tokens
     */
    function getPoolStats()
        external
        view
        returns (
            uint256 totalStaked,
            uint256 totalLiquidityProviders,
            uint256 contractBalance,
            uint256 currentRewardRate
        )
    {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        // Calculate total contract balance across all supported tokens
        uint256 totalBalance = 0;
        for (uint256 i = 0; i < s.supportedStakingTokens.length; i++) {
            address token = s.supportedStakingTokens[i];
            if (token != address(0)) {
                try IERC20(token).balanceOf(address(this)) returns (
                    uint256 balance
                ) {
                    totalBalance += balance;
                } catch {
                    // Skip tokens that fail to return balance
                    continue;
                }
            }
        }

        return (
            s.totalStaked,
            s.totalLiquidityProviders,
            totalBalance,
            s.currentRewardRate
        );
    }

    /**
     * @notice Get all stakers
     */
    function getStakers() external view returns (address[] memory) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        return s.stakers;
    }

    /**
     * @notice Get pending rewards for a staker
     * @dev Resolves address to primary identity (EOA)
     */
    function getPendingRewards(address staker) public view returns (uint256) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        // Resolve address to primary identity (EOA)
        address resolvedStaker = LibAddressResolver.resolveToEOA(staker);

        // Calculate total pending rewards across all token stakes
        uint256 totalPendingRewards = 0;

        for (uint256 i = 0; i < s.supportedStakingTokens.length; i++) {
            address tokenAddress = s.supportedStakingTokens[i];
            LibAppStorage.Stake storage tokenStake = s.stakesPerToken[
                resolvedStaker
            ][tokenAddress];

            if (tokenStake.amount == 0 || !tokenStake.active) {
                totalPendingRewards += tokenStake.pendingRewards;
                continue;
            }

            uint256 timeElapsed = block.timestamp -
                tokenStake.lastRewardTimestamp;

            if (timeElapsed > 0 && s.currentRewardRate > 0) {
                uint256 annualRate = (s.currentRewardRate * PRECISION) /
                    PERCENTAGE_BASE;
                uint256 rewardPerSecond = (tokenStake.usdEquivalent *
                    annualRate) / (SECONDS_PER_YEAR * PRECISION);
                uint256 newRewards = rewardPerSecond * timeElapsed;

                totalPendingRewards += tokenStake.pendingRewards + newRewards;
            } else {
                totalPendingRewards += tokenStake.pendingRewards;
            }
        }

        return totalPendingRewards;
    }

    /**
     * @notice Get staking configuration
     */
    function getStakingConfig()
        external
        view
        returns (
            uint256 initialApr,
            uint256 currentRewardRate,
            uint256 minLockDuration,
            uint256 aprReductionPerThousand,
            uint256 emergencyWithdrawPenalty,
            uint256 minimumStake,
            uint256 minimumFinancierStake,
            uint256 minFinancierLockDuration,
            uint256 minNormalStakerLockDuration
        )
    {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        return (
            s.initialApr,
            s.currentRewardRate,
            s.minLockDuration,
            s.aprReductionPerThousand,
            s.emergencyWithdrawPenalty,
            s.minimumStake,
            s.minimumFinancierStake,
            s.minFinancierLockDuration,
            s.minNormalStakerLockDuration
        );
    }

    // ========================================
    // MULTI-TOKEN STAKING FUNCTIONS
    // ========================================

    /**
     * @notice Stake any supported stablecoin (NORMAL STAKER)
     */
    function stakeToken(
        address tokenAddress,
        uint256 amount,
        uint256 customDeadline,
        uint256 usdEquivalent
    ) external nonReentrant whenNotPaused {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        // Security: Zero address checks
        if (tokenAddress == address(0)) revert InvalidTokenAddress();

        // Validations
        require(s.isStakingTokenSupported[tokenAddress], "Token not supported");
        if (amount == 0) revert ZeroAmount();
        if (usdEquivalent < s.minimumStake) revert BelowMinimumStake();
        if (amount > 1e30) revert ExcessiveAmount();

        // Security: Prevent overflow in total staked
        unchecked {
            if (s.totalStaked + usdEquivalent < s.totalStaked)
                revert ExcessiveAmount();
            if (
                s.totalStakedPerToken[tokenAddress] + amount <
                s.totalStakedPerToken[tokenAddress]
            ) revert ExcessiveAmount();
        }

        // CRITICAL FIX: Check if user is already a financier in ANY token
        // If they are, enforce financier lock duration instead
        bool isExistingFinancier = false;
        for (uint256 i = 0; i < s.supportedStakingTokens.length; i++) {
            address tokenAddr = s.supportedStakingTokens[i];
            if (
                s.stakesPerToken[msg.sender][tokenAddr].active &&
                s.stakesPerToken[msg.sender][tokenAddr].isFinancier
            ) {
                isExistingFinancier = true;
                break;
            }
        }

        // Validate custom deadline based on existing financier status
        uint256 minDeadline;
        if (isExistingFinancier) {
            minDeadline = block.timestamp + s.minFinancierLockDuration;
        } else {
            minDeadline = block.timestamp + s.minNormalStakerLockDuration;
        }

        if (customDeadline < minDeadline) {
            customDeadline = minDeadline;
        }
        if (customDeadline > block.timestamp + 365 days)
            revert InvalidDeadline();

        IERC20 token = IERC20(tokenAddress);
        if (token.balanceOf(msg.sender) < amount) revert InsufficientBalance();
        if (token.allowance(msg.sender, address(this)) < amount)
            revert InsufficientAllowance();

        // Update rewards for this specific token stake
        _updateTokenRewards(msg.sender, tokenAddress);

        // Transfer tokens
        token.safeTransferFrom(msg.sender, address(this), amount);

        // Track user if first stake
        if (s.stakesPerToken[msg.sender][tokenAddress].amount == 0) {
            if (!_isExistingStaker(msg.sender)) {
                s.stakers.push(msg.sender);
                s.totalLiquidityProviders++;
            }
        }

        // Update stake record for this token
        // Note: isExistingFinancier was already checked above for deadline validation
        s.stakesPerToken[msg.sender][tokenAddress].amount += amount;
        s.stakesPerToken[msg.sender][tokenAddress].timestamp = block.timestamp;
        s.stakesPerToken[msg.sender][tokenAddress].lastRewardTimestamp = block
            .timestamp;
        // CRITICAL: Use max of existing and new deadline to prevent lock period reduction
        if (
            s.stakesPerToken[msg.sender][tokenAddress].deadline < customDeadline
        ) {
            s
                .stakesPerToken[msg.sender][tokenAddress]
                .deadline = customDeadline;
        }
        s.stakesPerToken[msg.sender][tokenAddress].stakingToken = tokenAddress;
        s
            .stakesPerToken[msg.sender][tokenAddress]
            .usdEquivalent += usdEquivalent;
        s.stakesPerToken[msg.sender][tokenAddress].active = true;
        s
            .stakesPerToken[msg.sender][tokenAddress]
            .isFinancier = isExistingFinancier;

        // Update totals
        s.totalStakedPerToken[tokenAddress] += amount;
        s.totalStaked += usdEquivalent;

        // Update reward rate and recalculate voting powers
        _updateRewardRate();
        _recalculateAllVotingPowers();

        emit Staked(
            msg.sender,
            amount,
            s.stakesPerToken[msg.sender][tokenAddress].votingPower,
            s.currentRewardRate,
            customDeadline,
            isExistingFinancier
        );
    }

    /**
     * @notice Stake any supported stablecoin as FINANCIER
     */
    function stakeTokenAsFinancier(
        address tokenAddress,
        uint256 amount,
        uint256 customDeadline,
        uint256 usdEquivalent
    ) external nonReentrant whenNotPaused {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        // Security: Zero address checks
        if (tokenAddress == address(0)) revert InvalidTokenAddress();

        // Validations
        require(s.isStakingTokenSupported[tokenAddress], "Token not supported");
        if (amount == 0) revert ZeroAmount();
        if (usdEquivalent < s.minimumFinancierStake) {
            revert("USD equivalent below minimum financier stake");
        }
        if (amount > 1e30) revert ExcessiveAmount();

        // Security: Prevent overflow in total staked
        unchecked {
            if (s.totalStaked + usdEquivalent < s.totalStaked)
                revert ExcessiveAmount();
            if (
                s.totalStakedPerToken[tokenAddress] + amount <
                s.totalStakedPerToken[tokenAddress]
            ) revert ExcessiveAmount();
        }

        // Validate custom deadline for financiers
        uint256 minDeadline = block.timestamp + s.minFinancierLockDuration;
        if (customDeadline < minDeadline) {
            customDeadline = minDeadline;
        }
        if (customDeadline > block.timestamp + 365 days)
            revert InvalidDeadline();

        IERC20 token = IERC20(tokenAddress);
        if (token.balanceOf(msg.sender) < amount) revert InsufficientBalance();
        if (token.allowance(msg.sender, address(this)) < amount)
            revert InsufficientAllowance();

        // Update rewards for this specific token stake
        _updateTokenRewards(msg.sender, tokenAddress);

        // Transfer tokens
        token.safeTransferFrom(msg.sender, address(this), amount);

        // Track user if first stake
        if (s.stakesPerToken[msg.sender][tokenAddress].amount == 0) {
            if (!_isExistingStaker(msg.sender)) {
                s.stakers.push(msg.sender);
                s.totalLiquidityProviders++;
            }
        }

        // Update stake record for this token as FINANCIER
        s.stakesPerToken[msg.sender][tokenAddress].amount += amount;
        s.stakesPerToken[msg.sender][tokenAddress].timestamp = block.timestamp;
        s.stakesPerToken[msg.sender][tokenAddress].lastRewardTimestamp = block
            .timestamp;
        // CRITICAL: Use max of existing and new deadline to prevent lock period reduction
        if (
            s.stakesPerToken[msg.sender][tokenAddress].deadline < customDeadline
        ) {
            s
                .stakesPerToken[msg.sender][tokenAddress]
                .deadline = customDeadline;
        }
        s.stakesPerToken[msg.sender][tokenAddress].stakingToken = tokenAddress;
        s
            .stakesPerToken[msg.sender][tokenAddress]
            .usdEquivalent += usdEquivalent;
        s.stakesPerToken[msg.sender][tokenAddress].active = true;
        s.stakesPerToken[msg.sender][tokenAddress].isFinancier = true;

        // Update totals
        s.totalStakedPerToken[tokenAddress] += amount;
        s.totalStaked += usdEquivalent;

        // Update reward rate and recalculate voting powers
        _updateRewardRate();
        _recalculateAllVotingPowers();

        emit Staked(
            msg.sender,
            amount,
            s.stakesPerToken[msg.sender][tokenAddress].votingPower,
            s.currentRewardRate,
            customDeadline,
            true
        );
        emit FinancierStatusChanged(msg.sender, true);
    }

    /**
     * @notice Unstake a specific token
     * @dev Financiers must first revoke their financier status before unstaking
     */
    function unstakeToken(
        address tokenAddress,
        uint256 amount
    ) external nonReentrant whenNotPaused {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        LibAppStorage.Stake storage userStake = s.stakesPerToken[msg.sender][
            tokenAddress
        ];

        if (!userStake.active) revert NoActiveStake();
        if (amount == 0) revert ZeroAmount();
        if (amount > userStake.amount) revert InsufficientStakedAmount();
        if (block.timestamp < userStake.deadline) revert LockDurationNotMet();

        // Security: Prevent financiers from unstaking - they must use revocation system first
        if (userStake.isFinancier) {
            revert(
                "Financiers must complete 30-day revocation period before unstaking"
            );
        }

        // Update rewards before withdrawal
        _updateTokenRewards(msg.sender, tokenAddress);

        uint256 rewards = userStake.pendingRewards;
        uint256 usdToDeduct = (userStake.usdEquivalent * amount) /
            userStake.amount;

        // Update stake state
        userStake.amount -= amount;
        userStake.usdEquivalent -= usdToDeduct;
        s.totalStakedPerToken[tokenAddress] -= amount;
        s.totalStaked -= usdToDeduct;

        // If fully unstaking this token, mark as inactive
        if (userStake.amount == 0) {
            userStake.active = false;
            userStake.votingPower = 0;

            // Check if user has any other active stakes
            if (!_hasAnyActiveStake(msg.sender)) {
                s.totalLiquidityProviders--;
            }
        }

        // Update reward rate and voting powers
        _updateRewardRate();
        _recalculateAllVotingPowers();

        // Convert rewards from 18 decimals to token decimals
        uint8 tokenDecimals = IERC20Metadata(tokenAddress).decimals();
        uint256 rewardsInTokenDecimals = rewards / (10 ** (18 - tokenDecimals));

        // Transfer principal + rewards
        uint256 totalTransfer = amount + rewardsInTokenDecimals;
        if (rewards > 0) {
            userStake.pendingRewards = 0;
        }

        IERC20(tokenAddress).safeTransfer(msg.sender, totalTransfer);

        emit Unstaked(msg.sender, amount, rewardsInTokenDecimals);
    }

    /**
     * @notice Emergency withdraw with penalty for multi-token staking
     * @param tokenAddress Address of the token to emergency withdraw
     * @dev Allows immediate withdrawal with penalty before deadline
     * Financiers with high stakes cannot use emergency withdrawal
     */
    function emergencyWithdrawToken(
        address tokenAddress
    ) external nonReentrant whenNotPaused {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        LibAppStorage.Stake storage userStake = s.stakesPerToken[msg.sender][
            tokenAddress
        ];

        // Checks
        if (!userStake.active) revert NoActiveStake();
        if (userStake.amount == 0) revert NothingToUnstake();

        // Prevent financiers from using emergency withdrawal
        if (userStake.isFinancier) {
            revert FinanciersCannotEmergencyWithdraw();
        }

        IERC20 token = IERC20(tokenAddress);
        if (token.balanceOf(address(this)) < userStake.amount)
            revert InsufficientBalance();

        // Calculate amounts before effects
        uint256 amount = userStake.amount;
        uint256 usdValue = userStake.usdEquivalent;
        uint256 penalty = (amount * s.emergencyWithdrawPenalty) /
            PERCENTAGE_BASE;
        uint256 withdrawAmount = amount - penalty;

        // Effects - Reset user state
        userStake.amount = 0;
        userStake.usdEquivalent = 0;
        userStake.active = false;
        userStake.votingPower = 0;
        userStake.pendingRewards = 0;
        userStake.rewardDebt = 0;

        s.totalStakedPerToken[tokenAddress] -= amount;
        s.totalStaked -= usdValue;

        // Check if user has any other active stakes
        if (!_hasAnyActiveStake(msg.sender)) {
            s.totalLiquidityProviders--;
        }

        // Update reward rate and recalculate voting powers
        _updateRewardRate();
        _recalculateAllVotingPowers();

        // Transfer amount minus penalty
        token.safeTransfer(msg.sender, withdrawAmount);

        emit EmergencyWithdrawn(msg.sender, withdrawAmount, penalty);
    }

    /**
     * @notice Get stake for specific token
     */
    function getStakeForToken(
        address staker,
        address tokenAddress
    )
        external
        view
        returns (
            uint256 amount,
            uint256 timestamp,
            bool active,
            uint256 usdEquivalent,
            uint256 deadline,
            bool financierStatus,
            uint256 pendingRewards,
            uint256 votingPower
        )
    {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        LibAppStorage.Stake memory stakeData = s.stakesPerToken[staker][
            tokenAddress
        ];

        uint256 rewards = _calculateTokenRewards(staker, tokenAddress);

        return (
            stakeData.amount,
            stakeData.timestamp,
            stakeData.active,
            stakeData.usdEquivalent,
            stakeData.deadline,
            stakeData.isFinancier,
            rewards,
            stakeData.votingPower
        );
    }

    /**
     * @notice Get all stakes for user across all tokens
     */
    function getAllStakesForUser(
        address staker
    )
        external
        view
        returns (
            address[] memory tokens,
            uint256[] memory amounts,
            uint256[] memory usdEquivalents,
            bool[] memory isFinancierFlags,
            uint256[] memory deadlines,
            uint256[] memory pendingRewards,
            uint256 totalUsdValue
        )
    {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        uint256 tokenCount = s.supportedStakingTokens.length;
        tokens = new address[](tokenCount);
        amounts = new uint256[](tokenCount);
        usdEquivalents = new uint256[](tokenCount);
        isFinancierFlags = new bool[](tokenCount);
        deadlines = new uint256[](tokenCount);
        pendingRewards = new uint256[](tokenCount);
        totalUsdValue = 0;

        for (uint256 i = 0; i < tokenCount; i++) {
            address token = s.supportedStakingTokens[i];
            LibAppStorage.Stake memory stakeData = s.stakesPerToken[staker][
                token
            ];

            tokens[i] = token;
            amounts[i] = stakeData.amount;
            usdEquivalents[i] = stakeData.usdEquivalent;
            isFinancierFlags[i] = stakeData.isFinancier;
            deadlines[i] = stakeData.deadline;
            pendingRewards[i] = _calculateTokenRewards(staker, token);

            if (stakeData.active) {
                totalUsdValue += stakeData.usdEquivalent;
            }
        }
    }

    /**
     * @notice Claim rewards for a specific token
     */
    function claimTokenRewards(
        address tokenAddress
    ) external nonReentrant whenNotPaused {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        LibAppStorage.Stake storage userStake = s.stakesPerToken[msg.sender][
            tokenAddress
        ];

        if (!userStake.active) revert NoActiveStake();

        _updateTokenRewards(msg.sender, tokenAddress);
        uint256 rewards = userStake.pendingRewards;
        if (rewards == 0) revert NoRewardsToCllaim();

        userStake.pendingRewards = 0;
        userStake.rewardDebt = 0;

        // Convert rewards from 18 decimals to token decimals
        uint8 tokenDecimals = IERC20Metadata(tokenAddress).decimals();
        uint256 rewardsInTokenDecimals = rewards / (10 ** (18 - tokenDecimals));

        IERC20(tokenAddress).safeTransfer(msg.sender, rewardsInTokenDecimals);

        emit RewardsClaimed(msg.sender, rewardsInTokenDecimals);
    }

    // ========================================
    // INTERNAL HELPER FUNCTIONS
    // ========================================

    /**
     * @notice Update rewards for a specific token stake
     */
    function _updateTokenRewards(
        address staker,
        address tokenAddress
    ) internal {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        LibAppStorage.Stake storage user = s.stakesPerToken[staker][
            tokenAddress
        ];

        if (user.amount == 0 || !user.active) {
            return;
        }

        uint256 timeElapsed = block.timestamp - user.lastRewardTimestamp;

        if (timeElapsed > 0 && s.currentRewardRate > 0) {
            uint256 annualRate = (s.currentRewardRate * PRECISION) /
                PERCENTAGE_BASE;
            uint256 rewardPerSecond = (user.usdEquivalent * annualRate) /
                (SECONDS_PER_YEAR * PRECISION);
            uint256 newRewards = rewardPerSecond * timeElapsed;

            user.pendingRewards += newRewards;
            user.lastRewardTimestamp = block.timestamp;
        }
    }

    /**
     * @notice Calculate pending rewards for specific token
     */
    function _calculateTokenRewards(
        address staker,
        address tokenAddress
    ) internal view returns (uint256) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        LibAppStorage.Stake storage user = s.stakesPerToken[staker][
            tokenAddress
        ];

        if (user.amount == 0 || !user.active) {
            return user.pendingRewards;
        }

        uint256 timeElapsed = block.timestamp - user.lastRewardTimestamp;

        if (timeElapsed > 0 && s.currentRewardRate > 0) {
            uint256 annualRate = (s.currentRewardRate * PRECISION) /
                PERCENTAGE_BASE;
            uint256 rewardPerSecond = (user.usdEquivalent * annualRate) /
                (SECONDS_PER_YEAR * PRECISION);
            uint256 newRewards = rewardPerSecond * timeElapsed;

            return user.pendingRewards + newRewards;
        }

        return user.pendingRewards;
    }

    /**
     * @notice Check if user is already in stakers array
     */
    function _isExistingStaker(address staker) internal view returns (bool) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        for (uint256 i = 0; i < s.stakers.length; i++) {
            if (s.stakers[i] == staker) {
                return true;
            }
        }
        return false;
    }

    /**
     * @notice Check if user has any active stakes across all tokens
     */
    function _hasAnyActiveStake(address staker) internal view returns (bool) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        // Check legacy stake
        if (s.stakes[staker].active && s.stakes[staker].amount > 0) {
            return true;
        }

        // Check multi-token stakes
        for (uint256 i = 0; i < s.supportedStakingTokens.length; i++) {
            if (
                s.stakesPerToken[staker][s.supportedStakingTokens[i]].active &&
                s.stakesPerToken[staker][s.supportedStakingTokens[i]].amount > 0
            ) {
                return true;
            }
        }

        return false;
    }

    /**
     * @notice Recalculate voting powers for all stakers across all tokens
     * @dev Gas optimized with unchecked arithmetic where safe
     */
    function _recalculateAllVotingPowers() internal {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        if (s.totalStaked == 0) return;

        // Security: Prevent DOS by limiting array size processing
        uint256 stakersLength = s.stakers.length;
        if (stakersLength > 10000) return; // Prevent unbounded loop DOS

        for (uint256 i = 0; i < stakersLength; ) {
            address staker = s.stakers[i];
            uint256 totalUserUsd = 0;

            // Sum USD value across all tokens
            uint256 tokensLength = s.supportedStakingTokens.length;
            for (uint256 j = 0; j < tokensLength; ) {
                address token = s.supportedStakingTokens[j];
                if (s.stakesPerToken[staker][token].active) {
                    // Zero out voting power if revocation is pending
                    if (s.stakesPerToken[staker][token].revocationRequested) {
                        s.stakesPerToken[staker][token].votingPower = 0;
                    } else {
                        totalUserUsd += s
                            .stakesPerToken[staker][token]
                            .usdEquivalent;

                        // Update voting power for each token stake
                        // Security: Prevent overflow in voting power calculation
                        if (totalUserUsd > type(uint256).max / PRECISION) {
                            s
                                .stakesPerToken[staker][token]
                                .votingPower = PRECISION;
                        } else {
                            s.stakesPerToken[staker][token].votingPower =
                                (s.stakesPerToken[staker][token].usdEquivalent *
                                    PRECISION) /
                                s.totalStaked;
                        }
                    }
                }

                unchecked {
                    ++j; // Safe: j < tokensLength which is bounded
                }
            }

            // Also update legacy stake if active
            if (s.stakes[staker].active && s.stakes[staker].amount > 0) {
                totalUserUsd += s.stakes[staker].amount;
                if (totalUserUsd > type(uint256).max / PRECISION) {
                    s.stakes[staker].votingPower = PRECISION;
                } else {
                    s.stakes[staker].votingPower =
                        (s.stakes[staker].amount * PRECISION) /
                        s.totalStaked;
                }
            }

            unchecked {
                ++i; // Safe: i < stakersLength which is bounded
            }
        }
    }

    /**
     * @notice Distribute rewards (owner only)
     */
    function distributeRewards(address staker, uint256 amount) external {
        LibDiamond.enforceIsContractOwner();
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        if (!s.stakes[staker].active) revert StakerNotActive();
        IERC20(s.usdcToken).safeTransfer(staker, amount);

        emit RewardsDistributed(staker, amount);
    }

    /**
     * @notice Update rewards for a staker
     */
    function _updateRewards(address staker) internal {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        LibAppStorage.Stake storage user = s.stakes[staker];

        if (user.amount == 0 || !user.active) {
            return;
        }

        uint256 timeElapsed = block.timestamp - user.lastRewardTimestamp;

        if (timeElapsed > 0 && s.currentRewardRate > 0) {
            uint256 annualRate = (s.currentRewardRate * PRECISION) /
                PERCENTAGE_BASE;
            uint256 rewardPerSecond = (user.amount * annualRate) /
                (SECONDS_PER_YEAR * PRECISION);
            uint256 newRewards = rewardPerSecond * timeElapsed;

            user.pendingRewards += newRewards;
            user.lastRewardTimestamp = block.timestamp;
        }
    }

    /**
     * @notice Update reward rate based on total staked amount
     * @dev Uses safe math and proper rounding to prevent manipulation
     */
    function _updateRewardRate() internal {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        uint256 newRate = s.initialApr;

        // Apply reduction based on total staked (per 1000 tokens staked)
        // Security: Prevent division manipulation and ensure proper rounding
        if (
            s.totalStaked >= 1000 * PRECISION && s.aprReductionPerThousand > 0
        ) {
            // Use unchecked for gas optimization where overflow is impossible
            unchecked {
                uint256 thousandTokens = s.totalStaked / (1000 * PRECISION);
                uint256 reduction = thousandTokens * s.aprReductionPerThousand;

                // Ensure we don't underflow and maintain minimum APR
                newRate = reduction >= s.initialApr
                    ? MIN_APR
                    : s.initialApr - reduction;
                if (newRate < MIN_APR) newRate = MIN_APR;
            }
        }

        if (newRate != s.currentRewardRate) {
            uint256 oldRate = s.currentRewardRate;
            s.currentRewardRate = newRate;
            emit RewardRateUpdated(oldRate, newRate, s.totalStaked);
        }
    }

    /**
     * @notice Recalculate voting powers for all stakers
     */
    function _recalculateVotingPowers() internal {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        if (s.totalStaked == 0) return;

        for (uint256 i = 0; i < s.stakers.length; i++) {
            address staker = s.stakers[i];
            if (s.stakes[staker].active && s.stakes[staker].amount > 0) {
                // Prevent overflow in voting power calculation
                if (s.stakes[staker].amount > type(uint256).max / PRECISION) {
                    s.stakes[staker].votingPower = PRECISION; // Cap at 100%
                } else {
                    s.stakes[staker].votingPower =
                        (s.stakes[staker].amount * PRECISION) /
                        s.totalStaked;
                }
            }
        }
    }
}
