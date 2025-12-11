// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../libraries/LibAppStorage.sol";
import "../libraries/LibDiamond.sol";

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
     */
    function stake(
        uint256 amount,
        uint256 customDeadline
    ) external nonReentrant whenNotPaused {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

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
        _updateRewards(msg.sender);

        // Interactions (external calls)
        usdc.safeTransferFrom(msg.sender, address(this), amount);

        // Update stake record
        if (s.stakes[msg.sender].amount == 0) {
            s.stakers.push(msg.sender);
            s.totalLiquidityProviders++;
        }

        s.stakes[msg.sender].amount += amount;
        s.stakes[msg.sender].timestamp = block.timestamp;
        s.stakes[msg.sender].lastRewardTimestamp = block.timestamp;
        s.stakes[msg.sender].deadline = customDeadline;
        s.stakes[msg.sender].active = true;

        // Update total staked and reward rate
        s.totalStaked += amount;
        _updateRewardRate();

        // Calculate voting power
        s.stakes[msg.sender].votingPower =
            (s.stakes[msg.sender].amount * PRECISION) /
            s.totalStaked;

        // Recalculate all voting powers
        _recalculateVotingPowers();

        emit Staked(
            msg.sender,
            amount,
            s.stakes[msg.sender].votingPower,
            s.currentRewardRate,
            customDeadline,
            s.stakes[msg.sender].isFinancier
        );
    }

    /**
     * @notice Stake as financier with higher minimum and voting rights
     */
    function stakeAsFinancier(
        uint256 amount,
        uint256 customDeadline
    ) external nonReentrant whenNotPaused {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

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
        _updateRewards(msg.sender);

        // Transfer USDC from staker to diamond
        usdc.safeTransferFrom(msg.sender, address(this), amount);

        // Update stake record
        if (s.stakes[msg.sender].amount == 0) {
            s.stakers.push(msg.sender);
            s.totalLiquidityProviders++;
        }

        s.stakes[msg.sender].amount += amount;
        s.stakes[msg.sender].timestamp = block.timestamp;
        s.stakes[msg.sender].lastRewardTimestamp = block.timestamp;
        s.stakes[msg.sender].deadline = customDeadline;
        s.stakes[msg.sender].active = true;
        s.stakes[msg.sender].isFinancier = true; // Mark as financier

        // Update total staked and reward rate
        s.totalStaked += amount;
        _updateRewardRate();

        // Calculate voting power
        s.stakes[msg.sender].votingPower =
            (s.stakes[msg.sender].amount * PRECISION) /
            s.totalStaked;

        // Recalculate all voting powers
        _recalculateVotingPowers();

        emit Staked(
            msg.sender,
            amount,
            s.stakes[msg.sender].votingPower,
            s.currentRewardRate,
            customDeadline,
            true
        );
        emit FinancierStatusChanged(msg.sender, true);
    }

    /**
     * @notice Unstake USDC tokens after custom deadline
     */
    function unstake(uint256 amount) external nonReentrant whenNotPaused {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        if (!s.stakes[msg.sender].active) revert NoActiveStake();
        if (amount == 0) revert ZeroAmount();
        if (amount > s.stakes[msg.sender].amount)
            revert InsufficientStakedAmount();
        if (block.timestamp < s.stakes[msg.sender].deadline) {
            revert LockDurationNotMet();
        }

        // Update rewards before withdrawal
        _updateRewards(msg.sender);

        uint256 rewards = s.stakes[msg.sender].pendingRewards;

        // Update stake state
        s.stakes[msg.sender].amount -= amount;
        s.totalStaked -= amount;

        // If fully unstaking, mark as inactive and remove from providers
        if (s.stakes[msg.sender].amount == 0) {
            s.stakes[msg.sender].active = false;
            s.stakes[msg.sender].votingPower = 0;
            s.totalLiquidityProviders--;
        }

        // Update reward rate and recalculate voting powers
        _updateRewardRate();
        _recalculateVotingPowers();

        // Transfer principal + rewards
        uint256 totalTransfer = amount + rewards;
        if (rewards > 0) {
            s.stakes[msg.sender].pendingRewards = 0;
        }

        IERC20(s.usdcToken).safeTransfer(msg.sender, totalTransfer);

        emit Unstaked(msg.sender, amount, rewards);
    }

    /**
     * @notice Emergency withdraw with penalty (ignores lock period, not available for financiers)
     */
    function emergencyWithdraw() external nonReentrant {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        LibAppStorage.Stake storage userStake = s.stakes[msg.sender];

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

        emit EmergencyWithdrawn(msg.sender, withdrawAmount, penalty);
    }

    /**
     * @notice Claim accumulated rewards without unstaking
     */
    function claimRewards() external nonReentrant whenNotPaused {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        if (!s.stakes[msg.sender].active) revert NoActiveStake();

        _updateRewards(msg.sender);
        uint256 rewards = s.stakes[msg.sender].pendingRewards;
        if (rewards == 0) revert NoRewardsToCllaim();

        s.stakes[msg.sender].pendingRewards = 0;
        s.stakes[msg.sender].rewardDebt = 0;

        IERC20(s.usdcToken).safeTransfer(msg.sender, rewards);

        emit RewardsClaimed(msg.sender, rewards);
    }

    /**
     * @notice Apply to become a financier (must already have minimum stake)
     */
    function applyAsFinancier() external {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        require(s.stakes[msg.sender].active, "Must be active staker");
        require(
            s.stakes[msg.sender].amount >= s.minimumFinancierStake,
            "Insufficient stake for financier status"
        );
        require(!s.stakes[msg.sender].isFinancier, "Already a financier");

        // Update deadline to meet financier minimum
        uint256 minFinancierDeadline = block.timestamp +
            s.minFinancierLockDuration;
        if (s.stakes[msg.sender].deadline < minFinancierDeadline) {
            s.stakes[msg.sender].deadline = minFinancierDeadline;
            emit CustomDeadlineSet(msg.sender, minFinancierDeadline);
        }

        s.stakes[msg.sender].isFinancier = true;
        emit FinancierStatusChanged(msg.sender, true);
    }

    /**
     * @notice Revoke financier status (cannot vote anymore)
     */
    function revokeFinancierStatus() external {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        require(s.stakes[msg.sender].isFinancier, "Not a financier");

        s.stakes[msg.sender].isFinancier = false;
        emit FinancierStatusChanged(msg.sender, false);
    }

    /**
     * @notice Set custom deadline for existing stake
     */
    function setCustomDeadline(uint256 newDeadline) external {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        require(s.stakes[msg.sender].active, "Must be active staker");

        uint256 minDeadline;
        if (s.stakes[msg.sender].isFinancier) {
            minDeadline = block.timestamp + s.minFinancierLockDuration;
        } else {
            minDeadline = block.timestamp + s.minNormalStakerLockDuration;
        }

        require(newDeadline >= minDeadline, "Deadline below minimum required");

        s.stakes[msg.sender].deadline = newDeadline;
        emit CustomDeadlineSet(msg.sender, newDeadline);
    }

    /**
     * @notice Get stake information with financier status
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
        LibAppStorage.Stake memory stakeData = s.stakes[staker];

        uint256 unlockTime = block.timestamp >= stakeData.deadline
            ? 0
            : stakeData.deadline - block.timestamp;

        return (
            stakeData.amount,
            stakeData.timestamp,
            stakeData.votingPower,
            stakeData.active,
            getPendingRewards(staker),
            unlockTime,
            stakeData.deadline,
            stakeData.isFinancier
        );
    }

    /**
     * @notice Check if address is eligible financier
     */
    function isEligibleFinancier(address staker) external view returns (bool) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        return
            s.stakes[staker].active &&
            s.stakes[staker].isFinancier &&
            s.stakes[staker].amount >= s.minimumFinancierStake;
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
     */
    function getPendingRewards(address staker) public view returns (uint256) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        LibAppStorage.Stake storage user = s.stakes[staker];

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
