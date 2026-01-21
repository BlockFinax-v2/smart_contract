// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../libraries/LibAppStorage.sol";
import "../libraries/LibDiamond.sol";
import "../libraries/LibAddressResolver.sol";

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

    bool private _paused;

    // Constants for precision and calculations
    uint256 private constant PRECISION = 1e18;
    uint256 private constant SECONDS_PER_YEAR = 365 days;
    uint256 private constant PERCENTAGE_BASE = 100;
    uint256 private constant MIN_APR = 10; // 1% minimum APR

    modifier whenNotPaused() {
        if (_isPaused()) revert ContractPaused();
        _;
    }

    // Pause functions removed - handled by GovernanceFacet to avoid selector conflicts
    // Use the diamond's GovernanceFacet.pause(), unpause(), paused() functions instead

    function _pause() internal {
        _paused = true;
        emit Paused(msg.sender);
    }

    function _unpause() internal {
        _paused = false;
        emit Unpaused(msg.sender);
    }

    function _isPaused() internal view returns (bool) {
        return _paused;
    }

    /**
     * @notice Stake USDC tokens to become LP provider with custom deadline
     * @dev Uses address resolution: EOA is primary identity, smart account transactions resolve to EOA
     */
    function stake(
        uint256 amount,
        uint256 customDeadline
    ) external nonReentrant whenNotPaused {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        // Resolve address to primary identity (EOA)
        address staker = LibAddressResolver.resolveToEOA(msg.sender);

        // Checks
        if (amount == 0) revert ZeroAmount();
        if (amount < s.minimumStake) revert BelowMinimumStake();
        if (amount > 1e30) revert ExcessiveAmount(); // Reasonable upper bound

        // Validate custom deadline
        uint256 minDeadline = block.timestamp + s.minNormalStakerLockDuration;
        if (customDeadline < minDeadline) {
            customDeadline = minDeadline;
        }
        if (customDeadline > block.timestamp + 365 days)
            revert InvalidDeadline(); // Max 1 year

        IERC20 usdc = IERC20(s.usdcToken);
        if (usdc.balanceOf(msg.sender) < amount) revert InsufficientBalance();
        if (usdc.allowance(msg.sender, address(this)) < amount)
            revert InsufficientAllowance();

        // Effects - Update rewards before modifying stake
        _updateRewards(staker);

        // Interactions (external calls)
        usdc.safeTransferFrom(msg.sender, address(this), amount);

        // Update stake record (using primary identity)
        if (s.stakes[staker].amount == 0) {
            s.stakers.push(staker);
            s.totalLiquidityProviders++;
        }

        s.stakes[staker].amount += amount;
        s.stakes[staker].timestamp = block.timestamp;
        s.stakes[staker].lastRewardTimestamp = block.timestamp;
        s.stakes[staker].deadline = customDeadline;
        s.stakes[staker].active = true;

        // Update total staked and reward rate
        s.totalStaked += amount;
        _updateRewardRate();

        // Calculate voting power
        s.stakes[staker].votingPower =
            (s.stakes[staker].amount * PRECISION) /
            s.totalStaked;

        // Recalculate all voting powers
        _recalculateVotingPowers();

        emit Staked(
            staker,
            amount,
            s.stakes[staker].votingPower,
            s.currentRewardRate,
            customDeadline,
            s.stakes[staker].isFinancier
        );
    }

    /**
     * @notice Stake as financier with higher minimum and voting rights
     * @dev Uses address resolution: EOA is primary identity
     */
    function stakeAsFinancier(
        uint256 amount,
        uint256 customDeadline
    ) external nonReentrant whenNotPaused {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        // Resolve address to primary identity (EOA)
        address staker = LibAddressResolver.resolveToEOA(msg.sender);

        if (amount == 0) revert ZeroAmount();
        if (amount < s.minimumFinancierStake) {
            revert("Amount below minimum financier stake");
        }

        // Validate custom deadline for financiers
        uint256 minDeadline = block.timestamp + s.minFinancierLockDuration;
        if (customDeadline < minDeadline) {
            customDeadline = minDeadline;
        }

        IERC20 usdc = IERC20(s.usdcToken);
        if (usdc.balanceOf(msg.sender) < amount) revert InsufficientBalance();

        // Update rewards before modifying stake
        _updateRewards(staker);

        // Transfer USDC from staker to diamond
        usdc.safeTransferFrom(msg.sender, address(this), amount);

        // Update stake record (using primary identity)
        if (s.stakes[staker].amount == 0) {
            s.stakers.push(staker);
            s.totalLiquidityProviders++;
        }

        s.stakes[staker].amount += amount;
        s.stakes[staker].timestamp = block.timestamp;
        s.stakes[staker].lastRewardTimestamp = block.timestamp;
        s.stakes[staker].deadline = customDeadline;
        s.stakes[staker].active = true;
        s.stakes[staker].isFinancier = true; // Mark as financier

        // Update total staked and reward rate
        s.totalStaked += amount;
        _updateRewardRate();

        // Calculate voting power
        s.stakes[staker].votingPower =
            (s.stakes[staker].amount * PRECISION) /
            s.totalStaked;

        // Recalculate all voting powers
        _recalculateVotingPowers();

        emit Staked(
            staker,
            amount,
            s.stakes[staker].votingPower,
            s.currentRewardRate,
            customDeadline,
            true
        );
        emit FinancierStatusChanged(staker, true);
    }

    /**
     * @notice Unstake USDC tokens after custom deadline
     * @dev Uses address resolution: EOA is primary identity
     */
    function unstake(uint256 amount) external nonReentrant whenNotPaused {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        // Resolve address to primary identity (EOA)
        address staker = LibAddressResolver.resolveToEOA(msg.sender);

        if (!s.stakes[staker].active) revert NoActiveStake();
        if (amount == 0) revert ZeroAmount();
        if (amount > s.stakes[staker].amount) revert InsufficientStakedAmount();
        if (block.timestamp < s.stakes[staker].deadline) {
            revert LockDurationNotMet();
        }

        // Update rewards before withdrawal
        _updateRewards(staker);

        uint256 rewards = s.stakes[staker].pendingRewards;

        // Update stake state
        s.stakes[staker].amount -= amount;
        s.totalStaked -= amount;

        // If fully unstaking, mark as inactive and remove from providers
        if (s.stakes[staker].amount == 0) {
            s.stakes[staker].active = false;
            s.stakes[staker].votingPower = 0;
            s.totalLiquidityProviders--;
        }

        // Update reward rate and recalculate voting powers
        _updateRewardRate();
        _recalculateVotingPowers();

        // Transfer principal + rewards
        uint256 totalTransfer = amount + rewards;
        if (rewards > 0) {
            s.stakes[staker].pendingRewards = 0;
        }

        IERC20(s.usdcToken).safeTransfer(msg.sender, totalTransfer);

        emit Unstaked(staker, amount, rewards);
    }

    /**
     * @notice Emergency withdraw with penalty (ignores lock period, not available for financiers)
     * @dev Uses address resolution: EOA is primary identity
     */
    function emergencyWithdraw() external nonReentrant {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        // Resolve address to primary identity (EOA)
        address staker = LibAddressResolver.resolveToEOA(msg.sender);
        LibAppStorage.Stake storage userStake = s.stakes[staker];

        // Checks
        if (!userStake.active) revert NoActiveStake();
        if (userStake.amount == 0) revert NothingToUnstake();

        // Prevent financiers from using emergency withdrawal
        if (userStake.amount >= s.minimumFinancierStake) {
            revert FinanciersCannotEmergencyWithdraw();
        }

        IERC20 token = IERC20(s.usdcToken);
        if (token.balanceOf(address(this)) < userStake.amount)
            revert InsufficientBalance();

        // Calculate amounts before effects
        uint256 amount = userStake.amount;
        uint256 penalty = (amount * s.emergencyWithdrawPenalty) /
            PERCENTAGE_BASE;
        uint256 withdrawAmount = amount - penalty;

        // Effects - Reset user state
        userStake.amount = 0;
        userStake.active = false;
        userStake.votingPower = 0;
        userStake.pendingRewards = 0;
        userStake.rewardDebt = 0;

        s.totalStaked -= amount;
        s.totalLiquidityProviders--;

        // Update reward rate and recalculate voting powers
        _updateRewardRate();
        _recalculateVotingPowers();

        // Transfer amount minus penalty
        IERC20(s.usdcToken).safeTransfer(msg.sender, withdrawAmount);

        emit EmergencyWithdrawn(staker, withdrawAmount, penalty);
    }

    /**
     * @notice Claim accumulated rewards without unstaking
     * @dev Uses address resolution: EOA is primary identity
     */
    function claimRewards() external nonReentrant whenNotPaused {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        // Resolve address to primary identity (EOA)
        address staker = LibAddressResolver.resolveToEOA(msg.sender);

        if (!s.stakes[staker].active) revert NoActiveStake();

        _updateRewards(staker);
        uint256 rewards = s.stakes[staker].pendingRewards;
        if (rewards == 0) revert NoRewardsToCllaim();

        s.stakes[staker].pendingRewards = 0;
        s.stakes[staker].rewardDebt = 0;

        IERC20(s.usdcToken).safeTransfer(msg.sender, rewards);

        emit RewardsClaimed(staker, rewards);
    }

    /**
     * @notice Apply to become a financier (must already have minimum stake)
     * @dev Uses address resolution: EOA is primary identity
     */
    function applyAsFinancier() external {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        // Resolve address to primary identity (EOA)
        address staker = LibAddressResolver.resolveToEOA(msg.sender);

        require(s.stakes[staker].active, "Must be active staker");
        require(
            s.stakes[staker].amount >= s.minimumFinancierStake,
            "Insufficient stake for financier status"
        );
        require(!s.stakes[staker].isFinancier, "Already a financier");

        // Update deadline to meet financier minimum
        uint256 minFinancierDeadline = block.timestamp +
            s.minFinancierLockDuration;
        if (s.stakes[staker].deadline < minFinancierDeadline) {
            s.stakes[staker].deadline = minFinancierDeadline;
            emit CustomDeadlineSet(staker, minFinancierDeadline);
        }

        s.stakes[staker].isFinancier = true;
        emit FinancierStatusChanged(staker, true);
    }

    /**
     * @notice Revoke financier status (cannot vote anymore)
     * @dev Uses address resolution: EOA is primary identity
     */
    function revokeFinancierStatus() external {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        // Resolve address to primary identity (EOA)
        address staker = LibAddressResolver.resolveToEOA(msg.sender);

        require(s.stakes[staker].isFinancier, "Not a financier");

        s.stakes[staker].isFinancier = false;
        emit FinancierStatusChanged(staker, false);
    }

    /**
     * @notice Set custom deadline for existing stake
     * @dev Uses address resolution: EOA is primary identity
     */
    function setCustomDeadline(uint256 newDeadline) external {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        // Resolve address to primary identity (EOA)
        address staker = LibAddressResolver.resolveToEOA(msg.sender);

        require(s.stakes[staker].active, "Must be active staker");

        uint256 minDeadline;
        if (s.stakes[staker].isFinancier) {
            minDeadline = block.timestamp + s.minFinancierLockDuration;
        } else {
            minDeadline = block.timestamp + s.minNormalStakerLockDuration;
        }

        require(newDeadline >= minDeadline, "Deadline below minimum required");

        s.stakes[staker].deadline = newDeadline;
        emit CustomDeadlineSet(staker, newDeadline);
    }

    /**
     * @notice Get stake information with financier status
     * @dev Resolves address to primary identity (EOA)
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
            bool isFinancier
        )
    {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        // Resolve address to primary identity (EOA)
        address resolvedStaker = LibAddressResolver.resolveToEOA(staker);
        LibAppStorage.Stake memory stakeData = s.stakes[resolvedStaker];

        uint256 unlockTime = block.timestamp >= stakeData.deadline
            ? 0
            : stakeData.deadline - block.timestamp;

        return (
            stakeData.amount,
            stakeData.timestamp,
            stakeData.votingPower,
            stakeData.active,
            getPendingRewards(resolvedStaker),
            unlockTime,
            stakeData.deadline,
            stakeData.isFinancier
        );
    }

    /**
     * @notice Check if address is eligible financier
     * @dev Resolves address to primary identity (EOA)
     */
    function isEligibleFinancier(address staker) external view returns (bool) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        // Resolve address to primary identity (EOA)
        address resolvedStaker = LibAddressResolver.resolveToEOA(staker);

        return
            s.stakes[resolvedStaker].active &&
            s.stakes[resolvedStaker].isFinancier &&
            s.stakes[resolvedStaker].amount >= s.minimumFinancierStake;
    }

    /**
     * @notice Get all financiers
     */
    function getFinanciers() external view returns (address[] memory) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        // Count financiers first
        uint256 financierCount = 0;
        for (uint256 i = 0; i < s.stakers.length; i++) {
            if (
                s.stakes[s.stakers[i]].active &&
                s.stakes[s.stakers[i]].isFinancier
            ) {
                financierCount++;
            }
        }

        // Create array and populate
        address[] memory financiers = new address[](financierCount);
        uint256 index = 0;
        for (uint256 i = 0; i < s.stakers.length; i++) {
            address staker = s.stakers[i];
            if (s.stakes[staker].active && s.stakes[staker].isFinancier) {
                financiers[index] = staker;
                index++;
            }
        }

        return financiers;
    }

    /**
     * @notice Get pool statistics
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
        return (
            s.totalStaked,
            s.totalLiquidityProviders,
            IERC20(s.usdcToken).balanceOf(address(this)),
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
        LibAppStorage.Stake storage user = s.stakes[resolvedStaker];

        if (user.amount == 0 || !user.active) {
            return user.pendingRewards;
        }

        uint256 timeElapsed = block.timestamp - user.lastRewardTimestamp;

        if (timeElapsed > 0 && s.currentRewardRate > 0) {
            uint256 annualRate = (s.currentRewardRate * PRECISION) /
                PERCENTAGE_BASE;
            uint256 rewardPerSecond = (user.amount * annualRate) /
                (SECONDS_PER_YEAR * PRECISION);
            uint256 newRewards = rewardPerSecond * timeElapsed;

            return user.pendingRewards + newRewards;
        }

        return user.pendingRewards;
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

        // Validations
        require(s.isStakingTokenSupported[tokenAddress], "Token not supported");
        if (amount == 0) revert ZeroAmount();
        if (usdEquivalent < s.minimumStake) revert BelowMinimumStake();
        if (amount > 1e30) revert ExcessiveAmount();

        // Validate custom deadline for normal stakers
        uint256 minDeadline = block.timestamp + s.minNormalStakerLockDuration;
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
        s.stakesPerToken[msg.sender][tokenAddress].amount += amount;
        s.stakesPerToken[msg.sender][tokenAddress].timestamp = block.timestamp;
        s.stakesPerToken[msg.sender][tokenAddress].lastRewardTimestamp = block
            .timestamp;
        s.stakesPerToken[msg.sender][tokenAddress].deadline = customDeadline;
        s.stakesPerToken[msg.sender][tokenAddress].stakingToken = tokenAddress;
        s
            .stakesPerToken[msg.sender][tokenAddress]
            .usdEquivalent = usdEquivalent;
        s.stakesPerToken[msg.sender][tokenAddress].active = true;
        s.stakesPerToken[msg.sender][tokenAddress].isFinancier = false;

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
            false
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

        // Validations
        require(s.isStakingTokenSupported[tokenAddress], "Token not supported");
        if (amount == 0) revert ZeroAmount();
        if (usdEquivalent < s.minimumFinancierStake) {
            revert("USD equivalent below minimum financier stake");
        }
        if (amount > 1e30) revert ExcessiveAmount();

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
        s.stakesPerToken[msg.sender][tokenAddress].deadline = customDeadline;
        s.stakesPerToken[msg.sender][tokenAddress].stakingToken = tokenAddress;
        s
            .stakesPerToken[msg.sender][tokenAddress]
            .usdEquivalent = usdEquivalent;
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
            bool isFinancier,
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
     */
    function _recalculateAllVotingPowers() internal {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        if (s.totalStaked == 0) return;

        for (uint256 i = 0; i < s.stakers.length; i++) {
            address staker = s.stakers[i];
            uint256 totalUserUsd = 0;

            // Sum USD value across all tokens
            for (uint256 j = 0; j < s.supportedStakingTokens.length; j++) {
                address token = s.supportedStakingTokens[j];
                if (s.stakesPerToken[staker][token].active) {
                    totalUserUsd += s
                        .stakesPerToken[staker][token]
                        .usdEquivalent;

                    // Update voting power for each token stake
                    if (totalUserUsd > type(uint256).max / PRECISION) {
                        s.stakesPerToken[staker][token].votingPower = PRECISION;
                    } else {
                        s.stakesPerToken[staker][token].votingPower =
                            (s.stakesPerToken[staker][token].usdEquivalent *
                                PRECISION) /
                            s.totalStaked;
                    }
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
     */
    function _updateRewardRate() internal {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        uint256 newRate = s.initialApr;

        // Apply reduction based on total staked (per 1000 tokens staked)
        if (
            s.totalStaked >= 1000 * PRECISION && s.aprReductionPerThousand > 0
        ) {
            uint256 thousandTokens = s.totalStaked / (1000 * PRECISION);
            uint256 reduction = thousandTokens * s.aprReductionPerThousand;

            // Ensure we don't underflow and maintain minimum APR
            newRate = reduction >= s.initialApr
                ? MIN_APR
                : s.initialApr - reduction;
            if (newRate < MIN_APR) newRate = MIN_APR;
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
