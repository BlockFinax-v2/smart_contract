# Deployment Scripts

This directory contains deployment and upgrade scripts for the BlockFinax Diamond smart contracts.

## Prerequisites

1. Install dependencies:

```bash
npm install
```

2. Set up your `.env` file with the following variables:

```env
PRIVATE_KEY=your_private_key_here
LISK_SEPOLIA_RPC=https://rpc.sepolia-api.lisk.com
LISK_RPC=https://rpc.api.lisk.com
LISK_EXPLORER_KEY=your_lisk_explorer_key
BASE_SEPOLIA_RPC=https://sepolia.base.org
BASE_RPC=https://mainnet.base.org
BASESCAN_API_KEY=your_basescan_api_key
```

## Deployment Script (`deploy.ts`)

The deployment script intelligently deploys only new or updated contracts. It:

- Tracks contract changes using content hashes
- Reuses unchanged contracts to save gas
- Automatically verifies contracts on block explorers
- Maintains deployment history per network
- Marks updated contracts for future upgrades

### Usage

```bash
# Make the script executable (one time only)
chmod +x scripts/deploy.ts

# Deploy to Lisk Sepolia Testnet
npx ts-node scripts/deploy.ts liskSepolia
# or
npx ts-node scripts/deploy.ts lisk testnet

# Deploy to Lisk Mainnet
npx ts-node scripts/deploy.ts lisk
# or
npx ts-node scripts/deploy.ts lisk mainnet

# Deploy to Base Sepolia Testnet
npx ts-node scripts/deploy.ts baseSepolia
# or
npx ts-node scripts/deploy.ts base testnet

# Deploy to Base Mainnet
npx ts-node scripts/deploy.ts base
# or
npx ts-node scripts/deploy.ts base mainnet
```

### What It Does

1. **Checks for Updates**: Compares current contract code with previously deployed versions
2. **Deploys New/Updated Contracts**: Only deploys contracts that have changed
3. **Reuses Existing Contracts**: References previously deployed contracts that haven't changed
4. **Initializes Diamond**: Sets up the Diamond proxy with all facets (only on first deployment)
5. **Verifies Contracts**: Automatically verifies all new contracts on the block explorer
6. **Saves Deployment Info**: Stores addresses and deployment details in `deployments/deployments.json`
7. **Updates Hashes**: Records current contract hashes in `deployments/contract-hashes.json`

### Output Files

- `deployments/deployments.json`: Contains deployment addresses and metadata for each network
- `deployments/contract-hashes.json`: Stores content hashes to detect contract changes
