// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../libraries/LibAppStorage.sol";
import "../libraries/LibDiamond.sol";

contract LiquidityPoolFacet {
    using SafeERC20 for IERC20;

    event Staked(address indexed staker, uint256 amount, uint256 votingPower);
    event Unstaked(address indexed staker, uint256 amount);
    event RewardsDistributed(address indexed staker, uint256 amount);
    event Paused(address account);
    event Unpaused(address account);

    bool private _paused;

    modifier whenNotPaused() {
        require(!_paused, "Pausable: paused");
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == LibDiamond.contractOwner(), "Must be contract owner");
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
     * @notice Stake USDC tokens to become LP provider
     */
    function stake(uint256 amount) external whenNotPaused {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        
        require(amount >= s.minimumStake, "Below minimum stake");
        IERC20 usdc = IERC20(s.usdcToken);
        require(usdc.balanceOf(msg.sender) >= amount, "Insufficient balance");
        
        // Transfer USDC from staker to diamond
        usdc.safeTransferFrom(msg.sender, address(this), amount);
        
        // Update stake record
        if (s.stakes[msg.sender].amount == 0) {
            s.stakers.push(msg.sender);
            s.totalLPs++;
        }
        
        s.stakes[msg.sender].amount += amount;
        s.stakes[msg.sender].timestamp = block.timestamp;
        s.stakes[msg.sender].active = true;
        
        // Calculate voting power
        s.totalStaked += amount;
        s.stakes[msg.sender].votingPower = (s.stakes[msg.sender].amount * 1e18) / s.totalStaked;
        
        // Recalculate all voting powers
        _recalculateVotingPowers();
        
        emit Staked(msg.sender, amount, s.stakes[msg.sender].votingPower);
    }

    /**
     * @notice Unstake USDC tokens
     */
    function unstake() external whenNotPaused {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        
        require(s.stakes[msg.sender].active, "No active stake");
        require(s.stakes[msg.sender].amount > 0, "Nothing to unstake");
        
        uint256 amount = s.stakes[msg.sender].amount;
        
        // Update state
        s.stakes[msg.sender].amount = 0;
        s.stakes[msg.sender].active = false;
        s.stakes[msg.sender].votingPower = 0;
        s.totalStaked -= amount;
        s.totalLPs--;
        
        // Recalculate voting powers
        _recalculateVotingPowers();
        
        // Transfer USDC back
        IERC20(s.usdcToken).safeTransfer(msg.sender, amount);
        
        emit Unstaked(msg.sender, amount);
    }

    /**
     * @notice Get stake information
     */
    function getStake(address staker) external view returns (
        uint256 amount,
        uint256 timestamp,
        uint256 votingPower,
        bool active
    ) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        LibAppStorage.Stake memory stakeData = s.stakes[staker];
        return (stakeData.amount, stakeData.timestamp, stakeData.votingPower, stakeData.active);
    }

    /**
     * @notice Get pool statistics
     */
    function getPoolStats() external view returns (
        uint256 totalStaked,
        uint256 totalLPs,
        uint256 contractBalance
    ) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        return (
            s.totalStaked,
            s.totalLPs,
            IERC20(s.usdcToken).balanceOf(address(this))
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
     * @notice Distribute rewards (owner only)
     */
    function distributeRewards(address staker, uint256 amount) external {
        LibDiamond.enforceIsContractOwner();
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        
        require(s.stakes[staker].active, "Staker not active");
        IERC20(s.usdcToken).safeTransfer(staker, amount);
        
        emit RewardsDistributed(staker, amount);
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
                s.stakes[staker].votingPower = (s.stakes[staker].amount * 1e18) / s.totalStaked;
            }
        }
    }
}
