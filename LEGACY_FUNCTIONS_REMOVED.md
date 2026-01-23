# Legacy Single-Token Functions Removed

The following legacy USDC-only staking functions have been removed and replaced with multi-token equivalents:

## Removed Functions:

1. **stake()** → Replaced by **stakeToken()**
2. **stakeAsFinancier()** → Replaced by **stakeTokenAsFinancier()**
3. **unstake()** → Replaced by **unstakeToken()**
4. **emergencyWithdraw()** → Will be added as **emergencyWithdrawToken()**
5. **claimRewards()** → Replaced by **claimTokenRewards()**
6. **revokeFinancierStatus()** → Handled by multi-token logic in applyAsFinancier
7. **setCustomDeadline()** → Will be added as **setTokenDeadline()**
8. **getStake()** → Replaced by **getStakeForToken()** and **getAllStakesForUser()**
9. **getFinanciers()** → Needs multi-token implementation
10. **getPoolStats()** → Replaced by **getTotalStakedUSD()** and **getAllTokenStats()**
11. **getStakers()** → Still exists (tracks all stakers across all tokens)
12. **getPendingRewards()** → Replaced by **\_calculateTokenRewards()**
13. **distributeRewards()** → Legacy single-token, can be removed
14. **\_updateRewards()** → Replaced by **\_updateTokenRewards()**
15. **\_recalculateVotingPowers()** → Replaced by **\_recalculateAllVotingPowers()**

## Multi-Token Functions Available:

- `stakeToken()` - Stake any supported token as normal staker
- `stakeTokenAsFinancier()` - Stake any supported token as financier
- `unstakeToken()` - Unstake specific token
- `claimTokenRewards()` - Claim rewards for specific token
- `getStakeForToken()` - Get stake info for specific token
- `getAllStakesForUser()` - Get all stakes across all tokens
- `isFinancier()` - Multi-token aware financier check
- `applyAsFinancier()` - Multi-token financier application
- `getTotalStakedUSD()` - Get total USD value staked
- `getAllTokenStats()` - Get stats for all tokens
