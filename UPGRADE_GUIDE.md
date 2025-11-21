# LiquidityPoolFacet & LibAppStorage Upgrade Guide

This guide explains how to upgrade your deployed Diamond proxy contract with the updated `LiquidityPoolFacet.sol` and `LibAppStorage.sol` files.

## 🎯 Upgrade Overview

**What's being upgraded:**

- `contracts/facets/LiquidityPoolFacet.sol` - Updated implementation with new features
- `contracts/libraries/LibAppStorage.sol` - Updated storage library (automatically included)

**What stays the same:**

- Diamond proxy address: `0x65C4ce15C9DFA916db081A41340C3c862F0a3343`
- All other facets and functionality
- Your users continue using the same contract address

## 🚀 Quick Start

### Option 1: Complete Upgrade (Recommended)

Runs the full upgrade process including verification:

```bash
npm run upgrade:complete
```

### Option 2: Step-by-Step Upgrade

For more control over the process:

```bash
# 1. Upgrade just the LiquidityPoolFacet
npm run upgrade:liquidity-pool

# 2. Verify the new contract (update address first)
npm run verify:upgrade
```

## 📋 Pre-Upgrade Checklist

- [ ] ✅ Backup your `.env` file
- [ ] ✅ Ensure `PRIVATE_KEY` is set (deployer wallet)
- [ ] ✅ Ensure `BASESCAN_API_KEY` is set for verification
- [ ] ✅ Deployer wallet has enough ETH for gas fees (~0.01 ETH)
- [ ] ✅ Contracts compile successfully: `npm run compile`
- [ ] ✅ You are the owner of the Diamond contract
- [ ] ✅ Test the upgrade on a fork/testnet first (if on mainnet)

## 🔧 Environment Setup

Create/update your `.env` file:

```bash
# Your deployer private key (the one that deployed the Diamond)
PRIVATE_KEY=your_private_key_here

# For contract verification on Basescan
BASESCAN_API_KEY=your_basescan_api_key

# RPC URLs (optional - defaults will be used)
BASE_SEPOLIA_RPC=https://sepolia.base.org
BASE_RPC=https://mainnet.base.org
```

## 📖 Detailed Upgrade Process

### Step 1: Deploy New LiquidityPoolFacet

The upgrade script will:

1. Deploy a new `LiquidityPoolFacet` contract with your updates
2. The updated `LibAppStorage` is automatically included in the compilation
3. Get function selectors for the new implementation

### Step 2: Execute Diamond Cut

The script performs a "Replace" operation:

- Removes the old `LiquidityPoolFacet` implementation
- Adds the new `LiquidityPoolFacet` implementation
- Preserves all existing data and other facets
- Maintains the same Diamond proxy address

### Step 3: Verification & Testing

- Verifies the new contract on Basescan
- Tests basic functionality
- Generates upgrade logs for tracking

## 📄 Upgrade Scripts Explained

### 1. `complete-upgrade.ts`

**The recommended script** - handles everything:

- Deploys new LiquidityPoolFacet
- Executes Diamond cut
- Verifies on Basescan
- Tests functionality
- Saves upgrade logs

### 2. `upgrade-liquidity-pool.ts`

**Upgrade only** - just the core upgrade:

- Deploys and replaces the facet
- Basic verification
- Minimal logging

### 3. `verify-upgrade.ts`

**Verification only** - for post-upgrade verification:

- Verifies contracts on Basescan
- Updates contract addresses
- Useful for re-verification

## 🔍 Monitoring & Verification

### Explorer Links (Base Sepolia)

- Diamond Proxy: https://sepolia.basescan.org/address/0x65C4ce15C9DFA916db081A41340C3c862F0a3343
- Transaction will be displayed after upgrade

### After Upgrade

1. Check the upgrade transaction on Basescan
2. Verify the new LiquidityPoolFacet contract is verified
3. Test key functionality through the Diamond proxy
4. Monitor the first few transactions for any issues

## ⚠️ Important Notes

### Diamond Pattern Key Points

- **Always interact with the Diamond proxy address, not the facet addresses**
- Facet addresses are implementation contracts only
- The Diamond proxy maintains state and routing
- Your users continue using the same Diamond address

### Gas Costs

- Deploying new facet: ~1-3M gas
- Diamond cut operation: ~100-300k gas
- Total cost: ~0.005-0.02 ETH (depends on network congestion)

### Safety Features

- The upgrade is atomic (all or nothing)
- No state is lost during the upgrade
- Other facets continue working normally
- Can be reverted by deploying the old implementation

## 🚨 Troubleshooting

### Common Issues

**"Not contract owner" error:**

- Ensure you're using the same private key that deployed the Diamond
- Check that the deployer is still the owner (ownership may have been transferred)

**"Already exists" selector error:**

- Function signatures conflict with existing facets
- Remove conflicting selectors or use different function names

**Gas estimation failed:**

- Increase gas limits in hardhat config
- Ensure sufficient ETH balance
- Check network congestion

**Contract not verified:**

- Basescan API key issues
- Contract bytecode doesn't match source
- Try manual verification on Basescan

### Recovery Options

If something goes wrong:

1. **Revert upgrade**: Deploy the old LiquidityPoolFacet implementation and replace again
2. **Emergency pause**: Use the pause functionality in EscrowFacet
3. **Owner functions**: Use Diamond owner functions to fix issues

## 📊 Upgrade Log Format

The upgrade script saves detailed logs in `upgrade-logs/`:

```json
{
  "timestamp": "2024-01-01T00:00:00.000Z",
  "network": "baseSepolia",
  "chainId": 84532,
  "success": true,
  "diamond": "0x65C4ce15C9DFA916db081A41340C3c862F0a3343",
  "oldLiquidityPoolFacet": "0x2a32b6c004A1f71412FaF82c9E65db17232e6E1b",
  "newLiquidityPoolFacet": "0x...",
  "transactionHash": "0x...",
  "gasUsed": "234567",
  "blockNumber": 12345678
}
```

## 🎯 Testing the Upgrade

### Basic Tests

```bash
# Compile to ensure no errors
npm run compile

# Run unit tests
npm test

# Test Diamond integration
npm run test:diamond
```

### Manual Testing

After upgrade, test through the Diamond proxy:

1. Call view functions to ensure they work
2. Test new LiquidityPoolFacet functionality
3. Verify other facets still work
4. Check event emissions

## 🌐 Network Configuration

### Base Sepolia (Testnet)

- Chain ID: 84532
- Explorer: https://sepolia.basescan.org
- Use for testing upgrades

### Base Mainnet

- Chain ID: 8453
- Explorer: https://basescan.org
- Use for production upgrades

## 📞 Support

If you encounter issues:

1. Check the troubleshooting section above
2. Review the upgrade logs in `upgrade-logs/`
3. Verify your environment configuration
4. Test on Base Sepolia first if upgrading mainnet

## 🔄 Rollback Process

If you need to rollback the upgrade:

1. Deploy the old LiquidityPoolFacet implementation
2. Execute another Diamond cut with the old address
3. Or use the backup deployment if available

```bash
# This would need to be customized with the old implementation
npx hardhat run scripts/rollback-upgrade.ts --network baseSepolia
```
