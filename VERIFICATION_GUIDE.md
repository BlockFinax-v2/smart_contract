# 🔐 Contract Verification Guide

## Step 1: Get Your Basescan API Key

### 1.1 Visit Basescan
Go to: **https://basescan.org/myapikey**

### 1.2 Create Account (if needed)
- Click "Sign Up" in top right
- Complete registration
- Verify your email

### 1.3 Generate API Key
- Log in to your account
- Go to "API Keys" section
- Click "Add" to create new API key
- Give it a name (e.g., "BlockFinax Verification")
- Copy the generated API key

---

## Step 2: Update Your .env File

Open your `.env` file and replace the empty quotes with your API key:

```bash
BASESCAN_API_KEY="YOUR_API_KEY_HERE"
```

**Example:**
```bash
BASESCAN_API_KEY="ABC123XYZ789YOURAPIKEY"
```

⚠️ **Important:** Never commit your API key to git! The .env file should already be in .gitignore.

---

## Step 3: Run Automated Verification

Once you've added your API key, run:

```bash
npx hardhat run scripts/verify-all-contracts.ts --network baseSepolia
```

This will verify all 11 contracts automatically!

---

## Step 4: Verify Individual Contracts (If Needed)

If automatic verification fails for any contract, use these commands:

### Diamond Proxy
```bash
npx hardhat verify --network baseSepolia \
  0x65C4ce15C9DFA916db081A41340C3c862F0a3343 \
  "0xf070F568c125b2740391136662Fc600A2A29D2A6" \
  "0xA02409fB50c90D97304fF37230e2202E3EA384be"
```

### DiamondCutFacet
```bash
npx hardhat verify --network baseSepolia \
  0xA02409fB50c90D97304fF37230e2202E3EA384be
```

### DiamondLoupeFacet
```bash
npx hardhat verify --network baseSepolia \
  0x471Fb8C51430C145bcae95f78a0A66E4A63520C9
```

### OwnershipFacet
```bash
npx hardhat verify --network baseSepolia \
  0xE65B037ec83eA37E86Cd72675407BaA3594941Bb
```

### ContractManagementFacet
```bash
npx hardhat verify --network baseSepolia \
  0x2a2e859241FafABc8fAa515Fd69736e7cB53c7d6
```

### DocumentManagementFacet
```bash
npx hardhat verify --network baseSepolia \
  0x1479c03b2F6a797061C9BBF566CcdD5E97FB7a3d
```

### EscrowFacet
```bash
npx hardhat verify --network baseSepolia \
  0xE55711F2f4f564D187082eE187FCc03F4be7FC43
```

### GovernanceFacet
```bash
npx hardhat verify --network baseSepolia \
  0xB92925516501f9bf5bAD5643b276AE384852b508
```

### InvoiceFacet
```bash
npx hardhat verify --network baseSepolia \
  0x72e1831B54cA0b089c811adD6e16732f77e90f77
```

### LiquidityPoolFacet
```bash
npx hardhat verify --network baseSepolia \
  0x2a32b6c004A1f71412FaF82c9E65db17232e6E1b
```

### DiamondInit
```bash
npx hardhat verify --network baseSepolia \
  0x2776C557702e297fb25603c89604683DDD5F5023
```

---

## Step 5: Verify Success

After verification, check on Basescan:

### Main Diamond Address
https://sepolia.basescan.org/address/0x65C4ce15C9DFA916db081A41340C3c862F0a3343

You should see:
- ✅ **Contract** tab with verified source code
- ✅ **Read Contract** tab to view all functions
- ✅ **Write Contract** tab to interact with functions
- ✅ Green checkmark next to contract address

---

## Troubleshooting

### Error: "Invalid API Key"
- Double-check your API key in .env
- Make sure there are no extra spaces
- Verify you're using the correct network (baseSepolia)

### Error: "Already Verified"
- Contract is already verified ✅
- Nothing to do!

### Error: "Unable to locate ContractName"
- Hardhat might not be able to find the contract
- Try verifying manually with the full contract path:
```bash
npx hardhat verify --network baseSepolia \
  --contract contracts/facets/YourFacet.sol:YourFacet \
  0xYourAddress
```

### Error: "Constructor arguments mismatch"
- Only the Diamond contract has constructor arguments
- All facets have NO constructor arguments
- Make sure you're using the correct format

---

## What Happens After Verification?

Once verified, users can:
- ✅ Read your contract's source code on Basescan
- ✅ Interact with your Diamond through Basescan's UI
- ✅ See all 107 functions in the "Read/Write Contract" tabs
- ✅ Verify function calls and transactions
- ✅ Audit your code for security

---

## Quick Reference

**All Contracts:** 11 total
- 1 Diamond Proxy
- 9 Facets
- 1 Init Contract

**Total Functions:** 107 accessible through Diamond

**Network:** Base Sepolia (Chain ID: 84532)

**Explorer:** https://sepolia.basescan.org

---

## Next Steps After Verification

1. **Test Your Diamond**
   ```bash
   npx hardhat console --network baseSepolia
   ```
   
2. **Interact Through Basescan**
   - Go to your Diamond address
   - Click "Write Contract"
   - Connect your wallet
   - Test functions

3. **Share With Your Team**
   - Share the Diamond address: `0x65C4ce15C9DFA916db081A41340C3c862F0a3343`
   - Point them to Basescan for interaction

4. **Monitor Activity**
   - Watch transactions on Basescan
   - Set up alerts for important events

---

## Need Help?

If you encounter any issues:
1. Check the error message carefully
2. Verify your .env file has the correct API key
3. Make sure you're on the correct network
4. Try manual verification commands
5. Check Hardhat documentation: https://hardhat.org/hardhat-runner/plugins/nomicfoundation-hardhat-verify

---

*Last Updated: October 11, 2025*
*Network: Base Sepolia*
