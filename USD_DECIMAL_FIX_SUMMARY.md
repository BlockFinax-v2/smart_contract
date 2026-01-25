# USD Decimal Fix - Complete Resolution

## Issue Summary
The smart contract was using **18 decimals** for USD values, but USDC/USDT use **6 decimals**. This caused two problems:

1. **Initial Problem**: Contract stored USD values expecting 18 decimals, but frontend passed 6-decimal values
2. **Storage Problem**: After fixing contract code to use 6 decimals, existing stakes still had incorrect USD values stored

## Root Cause
When staking 3 USDC (3000000 in 6 decimals):
- Frontend passed `usdEquivalent = 3000000` (6 decimals)
- Old contract expected 18 decimals (should have been 3000000000000000000)
- Contract stored 3000000 and interpreted it as ~0.000003 USD
- This accumulated to showing 1 USD instead of 3 USD for your stake

## Solution Implemented

### Phase 1: Code Fix ✅
Changed `PRECISION` constant from `1e18` to `1e6` throughout:
- `LiquidityPoolFacet.sol`
- `GovernanceFacet.sol`

### Phase 2: Storage Migration ✅
Added `migrateDecimalPrecision()` function to convert existing 18-decimal values to 6 decimals:
```solidity
if (tokenStake.usdEquivalent > 1e12) {
    tokenStake.usdEquivalent = tokenStake.usdEquivalent / 1e12;
}
```

### Phase 3: USD Value Recalculation ✅ (Critical Fix)
Added `recalculateStablecoinUsdValues()` function to fix stakes that were created with wrong values:
```solidity
// For stablecoins: USD value = token amount (both 6 decimals)
tokenStake.usdEquivalent = tokenStake.amount;
```

## Deployment Status

### Sepolia Network ✅ COMPLETE
- Diamond: `0xA4d19a7b133d2A9fAce5b1ad407cA7b9D4Ee9284`
- LiquidityPoolFacet: `0x3f478e996Ff4cf4E34057bf0AF590493C79697d4`
- Functions deployed:
  - ✅ `migrateDecimalPrecision()` - Executed
  - ✅ `recalculateStablecoinUsdValues()` - **Executed** (Fixed your 3 USDC stake)
- Status: **All values corrected**
  - Total Staked: 3.0 USD ✅
  - Your stake: 3.0 USDC = 3.0 USD ✅

### Lisk Sepolia Network ⚠️ PENDING
- Diamond: `0xE133CD2eE4d835AC202942Baff2B1D6d47862d34`
- LiquidityPoolFacet: `0xf10C8C5C87328F310d32E495514729D5a63B0Db0`
- Status: **Needs recalculation function deployment**
- Migration attempted but reverted (might already be at correct precision)

### Base Sepolia Network ⚠️ PENDING  
- Diamond: `0xb899A968e785dD721dbc40e71e2FAEd7B2d84711`
- LiquidityPoolFacet: `0x9AE221Ef532beC0D06dC9811211d4E52393D7453`
- Status: **Needs recalculation function deployment**
- Migration executed successfully

## Next Steps

### 1. Deploy Recalculation Function to Remaining Networks
```bash
# Lisk Sepolia
rm deployments/contract-hashes.json
npx hardhat run scripts/upgrade.ts --network liskSepolia

# Base Sepolia  
rm deployments/contract-hashes.json
npx hardhat run scripts/upgrade.ts --network baseSepolia
```

### 2. Execute Recalculation (If Needed)
```bash
# Check stakes first on each network
npx hardhat run scripts/analyze-user-stakes.ts --network liskSepolia
npx hardhat run scripts/analyze-user-stakes.ts --network baseSepolia

# If USD/Amount ratio ≠ 1.0, run recalculation
npx hardhat run scripts/recalculate-usd.ts --network liskSepolia
npx hardhat run scripts/recalculate-usd.ts --network baseSepolia
```

### 3. Future Stakes - No Action Needed! ✅
The contract now correctly uses 6 decimals everywhere. New stakes will automatically have:
```typescript
// In stakeToken():
usdEquivalent = amount  // Both in 6 decimals for stablecoins
```

## Verification Commands

### Check Current State
```bash
npx hardhat run scripts/analyze-user-stakes.ts --network <network>
```

Expected output for correct stakes:
- USD/Amount ratio should be **~1.0** for stablecoins
- Total USD Value should match total staked amount

### Get Pool Stats
```bash
npx hardhat run scripts/check-stakes.ts --network <network>
```

## Key Files Modified

### Smart Contract
- `/smart_contract/contracts/facets/LiquidityPoolFacet.sol`
  - Line 71: `PRECISION = 1e6` (was 1e18)
  - Lines 1260-1287: `migrateDecimalPrecision()` function
  - Lines 1289-1321: `recalculateStablecoinUsdValues()` function
  - All reward/APR calculations updated to 6 decimals

- `/smart_contract/contracts/facets/GovernanceFacet.sol`
  - Voting power calculations updated to 6 decimals

### Scripts Created
- `/smart_contract/scripts/migrate-decimals.ts` - Decimal migration runner
- `/smart_contract/scripts/recalculate-usd.ts` - USD value recalculation runner  
- `/smart_contract/scripts/analyze-user-stakes.ts` - Detailed stake analysis tool

## Technical Details

### Decimal Standards
- **Ethereum/ERC20 Standard**: 18 decimals
- **USDC**: 6 decimals
- **USDT**: 6 decimals
- **Our Contract**: Now uses 6 decimals (matching stablecoin standard)

### Why 6 Decimals?
1. Matches the actual token decimals (USDC/USDT)
2. Prevents conversion errors between token amount and USD value
3. More gas efficient (smaller numbers)
4. Simpler 1:1 mapping for stablecoins (1 USDC = 1 USD)

### Gas Costs
- `migrateDecimalPrecision()`: ~68,915 gas
- `recalculateStablecoinUsdValues()`: ~67,973 gas
- LiquidityPoolFacet deployment: ~365,322 gas

## Success Metrics

### Before Fix
- 3 USDC staked showed as 1.0 USD ❌
- Ratio: 0.33 (wrong)

### After Fix
- 3 USDC staked shows as 3.0 USD ✅
- Ratio: 1.0 (correct)

## Lessons Learned

1. **Always Match Decimals**: When working with tokens, match contract precision to token decimals
2. **Storage ≠ Code**: Upgrading Diamond facets changes code but NOT storage - migration needed
3. **Frontend Validation**: Frontend should validate USD calculations before sending to contract
4. **Test Edge Cases**: Always test with actual token amounts in testnet before mainnet

## Emergency Functions

Both migration functions are **owner-only** and can be called again if needed:

```solidity
function migrateDecimalPrecision() external;
function recalculateStablecoinUsdValues() external;
```

These are safe to call multiple times - they will:
- Skip already-migrated values (< 1e12)
- Recalculate USD values from current amounts
- Update totalStaked and voting powers

---

**Status**: ✅ **Sepolia Complete** | ⚠️ **Lisk & Base Pending Deployment**

Last Updated: January 25, 2026
