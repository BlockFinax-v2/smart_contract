# BlockFinax Trade Platform

A comprehensive smart contract platform for international trade within the African Continental Free Trade Area (AFCFTA), providing secure escrow services, document management, risk assessment, and dispute resolution.

## 🌟 Features

### Core Functionality
- **Smart Contract Management**: Automated trade contract lifecycle management
- **Escrow Services**: Secure fund holding with automated release mechanisms
- **Document Management**: IPFS-based document storage with verification
- **Invoice Management**: Comprehensive invoicing with line items and payment tracking
- **Shipment Tracking**: Real-time logistics monitoring with carrier integration
- **Risk Assessment**: AI-powered risk scoring and mitigation recommendations
- **Dispute Resolution**: Decentralized arbitration system

### Platform Benefits
- **Multi-currency Support**: USD, EUR, and major African currencies
- **Cross-border Trade**: Optimized for AFCFTA member countries
- **Regulatory Compliance**: Built-in compliance frameworks
- **Modular Architecture**: Upgradeable and maintainable smart contracts
- **Gas Optimization**: Efficient contract design for cost-effective operations

## 🏗️ Architecture

The platform uses a modular architecture with separate contracts for different functionalities:

```
BlockFinaxTradePlatform (Main Contract)
├── ContractManagement      # Trade contract lifecycle
├── DocumentManagement      # IPFS document handling  
├── InvoiceManagement      # Billing and payments
├── ShipmentManagement     # Logistics tracking
├── RiskManagement         # Risk assessment engine
└── DisputeManagement      # Arbitration system
```

## 📁 Project Structure

```
contracts/
├── interfaces/
│   └── IBlockFinaxTradePlatform.sol    # Main interface
├── libraries/
│   └── TradeStructs.sol                # Data structures
├── modules/
│   ├── BaseModule.sol                  # Common functionality
│   ├── ContractManagement.sol          # Contract lifecycle
│   ├── DocumentManagement.sol          # Document handling
│   ├── InvoiceManagement.sol           # Invoice management
│   ├── ShipmentManagement.sol          # Shipment tracking
│   ├── RiskManagement.sol              # Risk assessment
│   └── DisputeManagement.sol           # Dispute resolution
└── BlockFinaxTradePlatform.sol         # Main orchestrator contract

scripts/
└── deploy.js                          # Deployment script

test/
└── (test files)                       # Comprehensive test suite
```

## 🚀 Quick Start

### Prerequisites
- Node.js >= 16.0.0
- npm or yarn
- Git

### Installation

1. **Clone the repository**
```bash
git clone https://github.com/blockfinax/trade-platform
cd trade-platform
```

2. **Install dependencies**
```bash
npm install
```

3. **Set up environment variables**
```bash
cp .env.example .env
# Edit .env with your configuration
```

4. **Compile contracts**
```bash
npm run compile
```

5. **Run tests**
```bash
npm run test
```

### Deployment

#### Local Development
```bash
# Start local Hardhat network
npm run node

# Deploy to local network
npm run deploy:localhost
```

#### Testnet Deployment
```bash
# Deploy to Goerli testnet
npm run deploy:goerli

# Deploy to Sepolia testnet
npm run deploy:sepolia

# Deploy to Polygon Mumbai testnet
npm run deploy:mumbai
```

#### Mainnet Deployment
```bash
# Deploy to Ethereum mainnet
npm run deploy:mainnet

# Deploy to Polygon mainnet
npm run deploy:polygon
```

## 🔧 Configuration

### Environment Variables

Create a `.env` file with the following variables:

```env
# Network URLs
GOERLI_URL=https://goerli.infura.io/v3/YOUR_PROJECT_ID
SEPOLIA_URL=https://sepolia.infura.io/v3/YOUR_PROJECT_ID
POLYGON_URL=https://polygon-rpc.com
MUMBAI_URL=https://matic-mumbai.chainstacklabs.com

# Private Keys (use environment variables in production)
PRIVATE_KEY=your_private_key_here
DEPLOYER_PRIVATE_KEY=your_deployer_private_key

# Etherscan API Keys
ETHERSCAN_API_KEY=your_etherscan_api_key
POLYGONSCAN_API_KEY=your_polygonscan_api_key

# Platform Configuration
FEE_RECIPIENT=0x1234567890123456789012345678901234567890
PLATFORM_FEE_RATE=250  # 2.5% in basis points
MIN_CONTRACT_VALUE=100
MAX_CONTRACT_DURATION=31536000  # 1 year in seconds

# IPFS Configuration
IPFS_GATEWAY=https://ipfs.io/ipfs/
PINATA_API_KEY=your_pinata_api_key
PINATA_SECRET_KEY=your_pinata_secret_key

# Oracle Configuration
CHAINLINK_PRICE_FEED=0x...  # ETH/USD price feed address
```

### Supported Countries

The platform supports all AFCFTA member countries:
- Nigeria (NG)
- Ghana (GH)
- Kenya (KE)
- Ethiopia (ET)
- Morocco (MA)
- Egypt (EG)
- South Africa (ZA)
- Rwanda (RW)
- Senegal (SN)
- Cote d'Ivoire (CI)

### Supported Currencies

- **Stable Coins**: USD, EUR
- **African Currencies**: NGN, GHS, KES, ETB, MAD, EGP, ZAR

## 📚 Usage Examples

### Creating a Trade Contract

```javascript
const platform = await ethers.getContractAt("BlockFinaxTradePlatform", platformAddress);

const tx = await platform.createContract(
  buyerAddress,           // Buyer address
  "Coffee Beans Export",  // Contract title
  "High quality coffee beans from Ethiopia", // Description
  ethers.utils.parseEther("5000"), // Total value in wei
  Math.floor(Date.now() / 1000) + 86400 * 30, // Delivery deadline (30 days)
  Math.floor(Date.now() / 1000) + 86400 * 45, // Payment deadline (45 days)
  "FOB Addis Ababa",     // Delivery terms
  "Net 30",              // Payment terms
  "Arabica coffee beans, grade A", // Product details
  1000,                  // Quantity
  "kg",                  // Unit of measure
  ethers.utils.parseEther("5"), // Unit price
  "USD",                 // Currency
  "ET",                  // Origin country (Ethiopia)
  "US"                   // Destination country
);

const receipt = await tx.wait();
const contractId = receipt.events[0].args.contractId;
```

### Uploading Documents

```javascript
const documentTx = await platform.uploadDocument(
  contractId,
  "Commercial Invoice",
  "QmYourIPFSHashHere",
  0, // DocumentType.Contract
  true, // isRequired
  "Official commercial invoice for the transaction",
  ethers.utils.keccak256(ethers.utils.toUtf8Bytes("document_content"))
);
```

### Creating Shipments

```javascript
const shipmentTx = await platform.createShipment(
  contractId,
  "TRACK123456789",
  "DHL Express",
  "Addis Ababa, Ethiopia",
  "New York, USA",
  Math.floor(Date.now() / 1000) + 86400 * 7, // 7 days delivery
  ethers.utils.parseEther("1000") // Insurance amount
);
```

## 🧪 Testing

The project includes comprehensive tests covering all modules:

```bash
# Run all tests
npm run test

# Run tests with coverage
npm run coverage

# Run gas consumption report
npm run gas-report

# Run specific test file
npx hardhat test test/ContractManagement.test.js
```

### Test Categories

- **Unit Tests**: Individual contract functions
- **Integration Tests**: Cross-module interactions  
- **Security Tests**: Reentrancy, access control
- **Gas Optimization Tests**: Transaction cost analysis
- **Edge Case Tests**: Boundary conditions and error scenarios

## 🛡️ Security

### Security Features

- **ReentrancyGuard**: Protection against reentrancy attacks
- **Access Control**: Role-based permissions system
- **Pausable Contracts**: Emergency stop functionality
- **Input Validation**: Comprehensive parameter checking
- **Safe Math**: Overflow/underflow protection

### Security Best Practices

1. **Multi-signature Wallets**: Use for admin functions
2. **Time Delays**: Implement for critical operations
3. **Regular Audits**: Schedule periodic security reviews
4. **Monitoring**: Set up real-time transaction monitoring
5. **Upgrades**: Test thoroughly on testnets before mainnet

### Audit Status

- [ ] Internal Security Review
- [ ] External Security Audit
- [ ] Bug Bounty Program
- [ ] Formal Verification

## 📊 Gas Optimization

The contracts are optimized for gas efficiency:

| Function | Gas Cost (avg) | Optimization Notes |
|----------|----------------|-------------------|
| Create Contract | ~180,000 | Packed structs, efficient storage |
| Fund Escrow | ~65,000 | Minimal external calls |
| Upload Document | ~85,000 | IPFS hash storage only |