# 🚀 Base Sepolia Testnet Deployment Guide

## Overview
This guide explains how to deploy the BlockFinax Diamond contract system to Base Sepolia testnet.

---

## 📋 Prerequisites

### 1. Get Base Sepolia ETH
You need ETH on Base Sepolia to pay for gas fees:

**Recommended Faucets:**
- **Alchemy Base Sepolia Faucet**: https://www.alchemy.com/faucets/base-sepolia
- **QuickNode Base Faucet**: https://faucet.quicknode.com/base/sepolia
- **Coinbase Wallet**: https://portal.cdp.coinbase.com/products/faucet

**Bridge from Ethereum Sepolia:**
- Official Base Bridge: https://bridge.base.org/deposit
- (Switch to "Testnet" mode in the top right)

### 2. Get Basescan API Key (Optional but Recommended)
For contract verification on Basescan:

1. Go to https://basescan.org/
2. Sign up for a free account
3. Go to https://basescan.org/myapikey
4. Create a new API key
5. Copy the key and add it to your `.env` file

---

## ⚙️ Configuration

Your configuration has been updated for Base Sepolia:

### Network Details
- **Network Name**: Base Sepolia
- **Chain ID**: 84532
- **RPC URL**: https://sepolia.base.org
- **Block Explorer**: https://sepolia.basescan.org
- **Symbol**: ETH
- **Currency**: Ether

### Environment Variables (.env)

```bash
# Private Key (without 0x prefix)
PRIVATE_KEY="your_private_key_here"

# Base Sepolia RPC (default provided)
BASE_SEPOLIA_RPC="https://sepolia.base.org"

# Basescan API Key (get from https://basescan.org/myapikey)
BASESCAN_API_KEY="your_api_key_here"

# Optional: Gas Reporter
REPORT_GAS="false"
```

**⚠️ SECURITY WARNING:**
- Never commit your `.env` file to git
- Never share your private key
- Use a separate wallet for testing
- Keep your private key secure

---

## 🏗️ Diamond Standard Implementation

This deployment follows the EIP-2535 Diamond Standard:

### Architecture
```
                    Diamond Proxy (Upgradeable)
                            │
                            │ delegatecall
                            ▼
    ┌──────────────────────────────────────────────┐
    │           Diamond Standard Facets            │
    ├──────────────────────────────────────────────┤
    │ • DiamondCutFacet   (Upgrade mechanism)     │
    │ • DiamondLoupeFacet (Introspection)         │
    │ • OwnershipFacet    (Owner management)      │
    └──────────────────────────────────────────────┘
                            │
                            ▼
    ┌──────────────────────────────────────────────┐
    │          Business Logic Facets               │
    ├──────────────────────────────────────────────┤
    │ • ContractManagementFacet                    │
    │ • DocumentManagementFacet                    │
    │ • EscrowFacet                                │
    │ • GovernanceFacet                            │
    │ • InvoiceFacet                               │
    │ • LiquidityPoolFacet                         │
    └──────────────────────────────────────────────┘
                            │
                            ▼
                      Shared Storage
                      (LibAppStorage)
```

### Deployed Facets

**Standard Facets (EIP-2535):**
1. **DiamondCutFacet** - Handles upgrades via `diamondCut()`
2. **DiamondLoupeFacet** - Provides introspection functions
3. **OwnershipFacet** - Manages contract ownership

**Business Logic Facets:**
4. **ContractManagementFacet** - Trade contract lifecycle with security fixes
5. **DocumentManagementFacet** - Document verification with IPFS
6. **EscrowFacet** - Milestone-based escrow with emergency pause
7. **GovernanceFacet** - Voting and governance with pause controls
8. **InvoiceFacet** - Invoice management with security hardening
9. **LiquidityPoolFacet** - Liquidity staking with pause mechanism

**Initialization:**
10. **DiamondInit** - One-time initialization contract

---

## 🚀 Deployment Commands

### 1. Deploy to Base Sepolia

```bash
npx hardhat run scripts/deploy.ts --network baseSepolia
```

This will:
- Deploy all 9 facets
- Deploy the Diamond proxy
- Add all facets to the Diamond
- Initialize the contract
- Verify contracts on Basescan (if API key is provided)

### 2. Verify Deployment

Check your deployment on Base Sepolia:
- Explorer: https://sepolia.basescan.org

### 3. Test Diamond Functions

The deployment script automatically runs integration tests:
- Verifies all facets are attached
- Tests function selectors
- Validates ownership

---

## 📊 Deployment Process

The deployment follows this sequence:

```
1. Deploy DiamondCutFacet        ✓
2. Deploy DiamondLoupeFacet      ✓
3. Deploy OwnershipFacet         ✓
4. Deploy Business Facets (6)    ✓
   ├── ContractManagementFacet
   ├── DocumentManagementFacet
   ├── EscrowFacet
   ├── GovernanceFacet
   ├── InvoiceFacet
   └── LiquidityPoolFacet
5. Deploy Diamond Proxy          ✓
6. Deploy DiamondInit            ✓
7. Execute DiamondCut            ✓
   └── Add all facets
   └── Initialize contract
8. Verify on Basescan            ✓
9. Run Integration Tests         ✓
```

---

## 🔍 Post-Deployment Verification

### 1. Check Diamond Proxy
```bash
npx hardhat console --network baseSepolia
```

```javascript
const diamondAddress = "YOUR_DIAMOND_ADDRESS";
const diamond = await ethers.getContractAt("IDiamondLoupe", diamondAddress);

// Get all facets
const facets = await diamond.facets();
console.log("Facets:", facets);

// Get owner
const owner = await ethers.getContractAt("IERC173", diamondAddress);
console.log("Owner:", await owner.owner());
```

### 2. Verify Contract on Basescan

If automatic verification fails, manually verify:

```bash
npx hardhat verify --network baseSepolia DIAMOND_ADDRESS "OWNER_ADDRESS" "DIAMONDCUT_ADDRESS"
```

---

## 💰 Gas Estimates

Expected gas costs for Base Sepolia deployment:

| Contract | Estimated Gas | Cost @ 1 Gwei |
|----------|---------------|---------------|
| DiamondCutFacet | ~800,000 | ~0.0008 ETH |
| DiamondLoupeFacet | ~500,000 | ~0.0005 ETH |
| OwnershipFacet | ~300,000 | ~0.0003 ETH |
| ContractManagementFacet | ~3,500,000 | ~0.0035 ETH |
| DocumentManagementFacet | ~2,000,000 | ~0.0020 ETH |
| EscrowFacet | ~2,500,000 | ~0.0025 ETH |
| GovernanceFacet | ~1,200,000 | ~0.0012 ETH |
| InvoiceFacet | ~1,500,000 | ~0.0015 ETH |
| LiquidityPoolFacet | ~1,000,000 | ~0.0010 ETH |
| Diamond Proxy | ~1,000,000 | ~0.0010 ETH |
| DiamondInit | ~500,000 | ~0.0005 ETH |
| Diamond Cut | ~2,000,000 | ~0.0020 ETH |
| **Total** | **~16,800,000** | **~0.0168 ETH** |

**Note:** Base Sepolia gas prices are typically very low (< 1 Gwei)

---

## 🛠️ Troubleshooting

### Issue: "Insufficient funds"
**Solution:** Get more Base Sepolia ETH from faucets listed above

### Issue: "Nonce too low"
**Solution:** 
```bash
# Reset nonce in Hardhat
npx hardhat clean
# Or manually increment nonce in deployment
```

### Issue: "Contract already verified"
**Solution:** This is not an error - your contract is already on Basescan!

### Issue: "Verification failed"
**Solution:** Wait a few minutes and try manual verification:
```bash
npx hardhat verify --network baseSepolia ADDRESS CONSTRUCTOR_ARGS
```

### Issue: "Transaction underpriced"
**Solution:** Increase gas price in hardhat.config.ts:
```typescript
baseSepolia: {
  url: BASE_SEPOLIA_RPC,
  accounts: [PRIVATE_KEY],
  chainId: 84532,
  gasPrice: 1000000000 // 1 Gwei
}
```

---

## 🔐 Security Features Deployed

All facets include security hardening:

### ✅ Critical Security Fixes
- **Reentrancy Protection**: CEI pattern in fund transfers
- **Integer Overflow Protection**: Bounds checking on calculations
- **DoS Prevention**: `call()` instead of `transfer()`
- **Status Validation**: State checks before operations

### ✅ Emergency Controls
- **Pausable Pattern**: Owner can pause critical functions
- **Per-Facet Control**: Granular emergency stops
- **4 Protected Facets**: Escrow, Governance, Invoice, LiquidityPool

---

## 📝 After Deployment Checklist

- [ ] Save Diamond proxy address
- [ ] Save all facet addresses
- [ ] Verify all contracts on Basescan
- [ ] Test basic functions (transfer, approve, etc.)
- [ ] Test emergency pause mechanism
- [ ] Document contract addresses
- [ ] Set up monitoring (optional)
- [ ] Configure multi-sig for owner (recommended)

---

## 🌐 Useful Resources

### Base Network
- **Official Website**: https://base.org
- **Base Docs**: https://docs.base.org
- **Base Sepolia Explorer**: https://sepolia.basescan.org
- **Base Bridge**: https://bridge.base.org

### Diamond Standard (EIP-2535)
- **EIP-2535 Spec**: https://eips.ethereum.org/EIPS/eip-2535
- **Nick Mudge's Guide**: https://eip2535diamonds.substack.com
- **Diamond Reference**: https://github.com/mudgen/diamond

### Tools
- **Hardhat**: https://hardhat.org
- **Ethers.js v6**: https://docs.ethers.org/v6
- **OpenZeppelin**: https://docs.openzeppelin.com

---

## 🆚 Migration from Lisk to Base

### Key Changes Made

| Aspect | Before (Lisk) | After (Base) |
|--------|---------------|--------------|
| Network | Lisk Sepolia | Base Sepolia |
| Chain ID | 4202 | 84532 |
| RPC URL | rpc.sepolia-api.lisk.com | sepolia.base.org |
| Explorer | sepolia-blockscout.lisk.com | sepolia.basescan.org |
| Verification | Blockscout API | Basescan API |
| EVM Version | paris | cancun |

### Why Base?

✅ **Ethereum L2** - Full EVM compatibility
✅ **Low Gas Fees** - Much cheaper than L1
✅ **Fast Finality** - ~2 second block times
✅ **Growing Ecosystem** - Backed by Coinbase
✅ **Better Tools** - Basescan verification support
✅ **Bridge Support** - Easy ETH bridging from Ethereum

---

## 📞 Support

If you encounter issues:

1. Check the Troubleshooting section above
2. Review deployment logs for specific errors
3. Verify your `.env` configuration
4. Ensure sufficient Base Sepolia ETH
5. Check Base Network status: https://status.base.org

---

## 🎯 Next Steps

After successful deployment:

1. **Test on Testnet**
   - Run comprehensive tests
   - Verify all functions work correctly
   - Test emergency pause mechanisms

2. **Mainnet Preparation**
   - Address remaining medium severity issues
   - Get external security audit
   - Set up multi-sig wallet
   - Implement monitoring

3. **Production Deployment**
   - Deploy to Base mainnet (chainId: 8453)
   - Update configuration for mainnet
   - Verify all contracts
   - Announce deployment

---

**🚀 Happy Deploying on Base Sepolia!**

*Last Updated: [Current Date]*
*Network: Base Sepolia (Chain ID: 84532)*
*Standard: EIP-2535 Diamond*
