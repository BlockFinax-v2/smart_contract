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

    event Staked(
        address indexed staker,
        uint256 amount,
        uint256 votingPower,
        uint256 currentApr
    );
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
        if (_paused) revert ContractPaused();
        _;
    }

    modifier onlyOwner() {
        if (msg.sender != LibDiamond.contractOwner()) {
            revert NotContractOwner();
        }
        _;
    }

    function pause() external onlyOwner {
        _paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external onlyOwner {
        _paused = false;
        emit Unpaused(msg.sender);
    }

    function paused() external view returns (bool) {
        return _paused;
    }

    /**
     * @notice Stake USDC tokens to become LP provider with enhanced rewards
     */
    function stake(uint256 amount) external nonReentrant whenNotPaused {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        if (amount == 0) revert ZeroAmount();
        if (amount < s.minimumStake) revert BelowMinimumStake();

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
            s.currentRewardRate
        );
    }

    /**
     * @notice Unstake USDC tokens after lock period
     */
    function unstake(uint256 amount) external nonReentrant whenNotPaused {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        if (!s.stakes[msg.sender].active) revert NoActiveStake();
        if (amount == 0) revert ZeroAmount();
        if (amount > s.stakes[msg.sender].amount)
            revert InsufficientStakedAmount();
        if (
            block.timestamp < s.stakes[msg.sender].timestamp + s.minLockDuration
        ) {
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
     * @notice Emergency withdraw with penalty (ignores lock period)
     */
    function emergencyWithdraw() external nonReentrant {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        if (!s.stakes[msg.sender].active) revert NoActiveStake();
        if (s.stakes[msg.sender].amount == 0) revert NothingToUnstake();

        uint256 amount = s.stakes[msg.sender].amount;
        uint256 penalty = (amount * s.emergencyWithdrawPenalty) /
            PERCENTAGE_BASE;
        uint256 withdrawAmount = amount - penalty;

        // Reset user state
        s.stakes[msg.sender].amount = 0;
        s.stakes[msg.sender].active = false;
        s.stakes[msg.sender].votingPower = 0;
        s.stakes[msg.sender].pendingRewards = 0;
        s.stakes[msg.sender].rewardDebt = 0;

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
     * @notice Get stake information
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
            uint256 timeUntilUnlock
        )
    {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        LibAppStorage.Stake memory stakeData = s.stakes[staker];

        uint256 unlockTime = block.timestamp >=
            stakeData.timestamp + s.minLockDuration
            ? 0
            : stakeData.timestamp + s.minLockDuration - block.timestamp;

        return (
            stakeData.amount,
            stakeData.timestamp,
            stakeData.votingPower,
            stakeData.active,
            getPendingRewards(staker),
            unlockTime
        );
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
            uint256 minimumStake
        )
    {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        return (
            s.initialApr,
            s.currentRewardRate,
            s.minLockDuration,
            s.aprReductionPerThousand,
            s.emergencyWithdrawPenalty,
            s.minimumStake
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
     * @notice Set USDC token address (owner only)
     */
    function setUsdcToken(address _usdcToken) external {
        LibDiamond.enforceIsContractOwner();
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        s.usdcToken = _usdcToken;
    }

    /**
     * @notice Set minimum stake amount (owner only)
     */
    function setMinimumStake(uint256 _minimumStake) external {
        LibDiamond.enforceIsContractOwner();
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        s.minimumStake = _minimumStake;
    }

    /**
     * @notice Initialize staking configuration (owner only)
     */
    function initializeStaking(
        uint256 _initialApr,
        uint256 _minLockDuration,
        uint256 _aprReductionPerThousand,
        uint256 _emergencyWithdrawPenalty
    ) external {
        LibDiamond.enforceIsContractOwner();
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        if (_initialApr == 0) revert InvalidAPR();
        if (_minLockDuration == 0) revert InvalidLockDuration();
        if (_emergencyWithdrawPenalty > PERCENTAGE_BASE)
            revert InvalidPenalty();

        s.initialApr = _initialApr;
        s.currentRewardRate = _initialApr;
        s.minLockDuration = _minLockDuration;
        s.aprReductionPerThousand = _aprReductionPerThousand;
        s.emergencyWithdrawPenalty = _emergencyWithdrawPenalty;
    }

    /**
     * @notice Complete initialization with token and minimum stake
     */
    function initializeComplete(
        address _usdcToken,
        uint256 _minimumStake,
        uint256 _initialApr,
        uint256 _minLockDuration,
        uint256 _aprReductionPerThousand,
        uint256 _emergencyWithdrawPenalty
    ) external {
        LibDiamond.enforceIsContractOwner();
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        if (_initialApr == 0) revert InvalidAPR();
        if (_minLockDuration == 0) revert InvalidLockDuration();
        if (_emergencyWithdrawPenalty > PERCENTAGE_BASE)
            revert InvalidPenalty();
        if (_usdcToken == address(0)) revert ZeroAmount();
        if (_minimumStake == 0) revert ZeroAmount();

        s.usdcToken = _usdcToken;
        s.minimumStake = _minimumStake;
        s.initialApr = _initialApr;
        s.currentRewardRate = _initialApr;
        s.minLockDuration = _minLockDuration;
        s.aprReductionPerThousand = _aprReductionPerThousand;
        s.emergencyWithdrawPenalty = _emergencyWithdrawPenalty;
    }

    /**
     * @notice Update staking parameters (owner only)
     */
    function updateStakingConfig(
        uint256 _initialApr,
        uint256 _minLockDuration,
        uint256 _aprReductionPerThousand,
        uint256 _emergencyWithdrawPenalty
    ) external {
        LibDiamond.enforceIsContractOwner();
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        if (_initialApr > 0 && _initialApr != s.initialApr) {
            uint256 oldValue = s.initialApr;
            s.initialApr = _initialApr;
            emit StakingConfigUpdated("initialApr", oldValue, _initialApr);
        }

        if (_minLockDuration > 0 && _minLockDuration != s.minLockDuration) {
            uint256 oldValue = s.minLockDuration;
            s.minLockDuration = _minLockDuration;
            emit StakingConfigUpdated(
                "minLockDuration",
                oldValue,
                _minLockDuration
            );
        }

        if (_aprReductionPerThousand != s.aprReductionPerThousand) {
            uint256 oldValue = s.aprReductionPerThousand;
            s.aprReductionPerThousand = _aprReductionPerThousand;
            emit StakingConfigUpdated(
                "aprReductionPerThousand",
                oldValue,
                _aprReductionPerThousand
            );
        }

        if (
            _emergencyWithdrawPenalty <= PERCENTAGE_BASE &&
            _emergencyWithdrawPenalty != s.emergencyWithdrawPenalty
        ) {
            uint256 oldValue = s.emergencyWithdrawPenalty;
            s.emergencyWithdrawPenalty = _emergencyWithdrawPenalty;
            emit StakingConfigUpdated(
                "emergencyWithdrawPenalty",
                oldValue,
                _emergencyWithdrawPenalty
            );
        }

        _updateRewardRate();
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
                s.stakes[staker].votingPower =
                    (s.stakes[staker].amount * PRECISION) /
                    s.totalStaked;
            }
        }
    }
}
