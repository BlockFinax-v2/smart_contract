# Diamond Contract Configuration Values

This document contains all the configuration values needed to set up your Diamond contract on any network.

## 📋 Configuration Parameters

### 1. **Initial Deployment (via DiamondInit.init)**

These values are set during the initial `diamondCut` with `DiamondInit.init()`:

```typescript
DiamondInit.init(
  usdcToken, // Address of primary stablecoin (USDC)
  minimumStake, // Minimum stake for normal stakers
  initialApr, // Initial APR (basis points)
  minLockDuration, // Minimum lock duration (seconds)
  aprReductionPerThousand, // APR reduction per 1000 tokens staked
  emergencyWithdrawPenalty, // Emergency withdrawal penalty (percentage)
);
```

### 2. **Multi-Token Support (via GovernanceFacet)**

After deployment, add supported staking tokens:

```typescript
GovernanceFacet.addSupportedStakingToken(tokenAddress);
```

---

## 🔧 Current Configuration Values (from deploy.ts)

### **Default Values Used in Deployment Script:**

| Parameter                  | Value                      | Converted Value              | Description                      |
| -------------------------- | -------------------------- | ---------------------------- | -------------------------------- |
| `usdcToken`                | `<mockUSDC or real USDC>`  | Address                      | Primary stablecoin contract      |
| `minimumStake`             | `ethers.parseEther("100")` | **100 tokens** (100 USDC)    | Minimum stake for normal stakers |
| `initialApr`               | `1200`                     | **12%** (12.00%)             | Initial APR in basis points      |
| `minLockDuration`          | `7 * 24 * 60 * 60`         | **7 days** (604,800 seconds) | Minimum lock duration            |
| `aprReductionPerThousand`  | `50`                       | **0.5%**                     | APR reduction per 1000 tokens    |
| `emergencyWithdrawPenalty` | `10`                       | **10%**                      | Penalty for emergency withdrawal |

### **Auto-Calculated Values (set in DiamondInit):**

These are automatically calculated based on the input parameters:

| Parameter                     | Formula               | Default Value    | Description                         |
| ----------------------------- | --------------------- | ---------------- | ----------------------------------- |
| `minimumFinancierStake`       | `minimumStake * 10`   | **1,000 tokens** | 10x minimum stake                   |
| `minFinancierLockDuration`    | `minLockDuration * 2` | **14 days**      | 2x lock duration                    |
| `minNormalStakerLockDuration` | `minLockDuration`     | **7 days**       | Same as min lock                    |
| `votingDuration`              | Fixed                 | **7 days**       | Proposal voting period              |
| `proposalThreshold`           | `minimumStake * 5`    | **500 tokens**   | Minimum to create proposal          |
| `approvalThreshold`           | Fixed                 | **51%**          | Percentage needed to pass           |
| `revocationPeriod`            | Fixed                 | **30 days**      | Financier revocation waiting period |

---

## 📍 Network-Specific Token Addresses

### **Ethereum Sepolia (Chain ID: 11155111)**

```
Diamond: 0xA4d19a7b133d2A9fAce5b1ad407cA7b9D4Ee9284
MockUSDC: 0x67172ca742090F6670803D9fF0745BeFb55E3dC9
```

**Tokens to Add:**

- USDC: `0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238`
- USDT: `0x523C8591Fbe215B5aF0bEad65e65dF783A37BCBC`

---

### **Base Sepolia (Chain ID: 84532)**

```
Diamond: 0xb899A968e785dD721dbc40e71e2FAEd7B2d84711
MockUSDC: 0xC88f9782CEC37b35E324a12B8CF1785E607b33Ea
```

**Tokens to Add:**

- USDC: `0x036CbD53842c5426634e7929541eC2318f3dCF7e`

---

### **Lisk Sepolia (Chain ID: 4202)**

```
Diamond: 0xE133CD2eE4d835AC202942Baff2B1D6d47862d34
MockUSDC: 0xE7c962b20f397473Df0610403c5E0c3f2b298e59
```

**Tokens to Add:**

- USDC: `0x17b3531549F842552911CB287CCf7a5F328ff7d1`
- USDT: `0xa3f3aA5B62237961AF222B211477e572149EBFAe`

---

## 🛠️ Manual Configuration Steps

### **Step 1: Verify Initial Configuration**

Check if Diamond was initialized during deployment:

```typescript
// Connect to Diamond as GovernanceFacet
const governance = await ethers.getContractAt(
  "GovernanceFacet",
  diamondAddress,
);

// Check current values
const minimumStake = await governance.getMinimumStake();
const initialApr = await governance.getInitialApr();
const usdcToken = await governance.getUsdcToken();

console.log("Minimum Stake:", minimumStake);
console.log("Initial APR:", initialApr);
console.log("USDC Token:", usdcToken);
```

### **Step 2: Add Supported Staking Tokens**

For each network, add USDC and USDT (if applicable):

```typescript
const governance = await ethers.getContractAt(
  "GovernanceFacet",
  diamondAddress,
);

// Add USDC
await governance.addSupportedStakingToken(
  "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238",
);
console.log("✅ USDC added");

// Add USDT (if network supports it)
await governance.addSupportedStakingToken(
  "0x523C8591Fbe215B5aF0bEad65e65dF783A37BCBC",
);
console.log("✅ USDT added");

// Verify
const supportedTokens = await governance.getSupportedStakingTokens();
console.log("Supported Tokens:", supportedTokens);
```

### **Step 3: Update Configuration (if needed)**

If you need to change any values after deployment:

```typescript
const governance = await ethers.getContractAt(
  "GovernanceFacet",
  diamondAddress,
);

// Update minimum stake
await governance.setMinimumStake(ethers.parseEther("100"));

// Update minimum financier stake
await governance.setMinimumFinancierStake(ethers.parseEther("1000"));

// Update APR
await governance.setInitialApr(1200); // 12%

// Update lock durations
await governance.setMinLockDuration(7 * 24 * 60 * 60); // 7 days
await governance.setMinFinancierLockDuration(14 * 24 * 60 * 60); // 14 days
await governance.setMinNormalStakerLockDuration(7 * 24 * 60 * 60); // 7 days

// Update voting parameters
await governance.setVotingDuration(7 * 24 * 60 * 60); // 7 days
await governance.setProposalThreshold(ethers.parseEther("500"));
await governance.setApprovalThreshold(51); // 51%

// Update penalty
await governance.setEmergencyWithdrawPenalty(10); // 10%
await governance.setAprReductionPerThousand(50); // 0.5%
```

---

## 📊 Comparison: Current Network Configurations

| Network              | Diamond Address | USDC | USDT | Configured?               |
| -------------------- | --------------- | ---- | ---- | ------------------------- |
| **Ethereum Sepolia** | `0xA4d...9284`  | ✅   | ✅   | ⚠️ **Needs tokens added** |
| **Base Sepolia**     | `0xb899...4711` | ✅   | ❌   | ✅ Already configured     |
| **Lisk Sepolia**     | `0xE133...2d34` | ✅   | ✅   | ✅ Already configured     |

---

## 🚀 Quick Setup Script (Run this for Ethereum Sepolia)

```bash
# Navigate to smart contract directory
cd /home/bilal/bilal_projects/BlockFinax/smart_contract

# Run the add-tokens script
npx hardhat run scripts/add-tokens.ts --network sepolia
```

This will:

1. Check current supported tokens
2. Add USDC (`0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238`)
3. Add USDT (`0x523C8591Fbe215B5aF0bEad65e65dF783A37BCBC`)
4. Verify the final state

---

## ✅ Checklist for New Network Deployment

- [ ] Deploy Diamond contract
- [ ] Initialize with DiamondInit.init() (done during deployment)
- [ ] Add USDC token via `addSupportedStakingToken()`
- [ ] Add USDT token via `addSupportedStakingToken()` (if applicable)
- [ ] Verify supported tokens via `getSupportedStakingTokens()`
- [ ] Test staking functionality
- [ ] Update frontend token addresses to match

---

## 📝 Notes

1. **MockUSDC vs Real USDC**: The deployment script uses MockUSDC on testnets. After deployment, you add the real testnet USDC/USDT addresses via `addSupportedStakingToken()`.

2. **Multi-Token Support**: Your contract already supports multiple tokens! Just need to add them via `addSupportedStakingToken()`.

3. **Token Decimals**: All stablecoin amounts should be in their native decimals (usually 6 for USDC/USDT).

4. **Owner Only**: All setter functions require contract owner permissions.

---

## 🔍 Getter Functions (Check Current Values)

```typescript
// View functions to check configuration
governance.getMinimumStake();
governance.getMinimumFinancierStake();
governance.getUsdcToken();
governance.getInitialApr();
governance.getMinLockDuration();
governance.getVotingDuration();
governance.getProposalThreshold();
governance.getApprovalThreshold();
governance.getSupportedStakingTokens();
governance.isSupportedToken(tokenAddress);
```
