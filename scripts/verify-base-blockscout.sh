#!/bin/bash

echo "🚀 Verifying all remaining Base Sepolia contracts on Blockscout..."
echo ""

# DiamondLoupeFacet
echo "📋 Verifying DiamondLoupeFacet..."
npx hardhat verify --network baseSepolia 0x048Cc025b826678485Aaaf5DbFE12f677CA339E9 --contract contracts/facets/DiamondLoupeFacet.sol:DiamondLoupeFacet
echo ""

# OwnershipFacet
echo "👑 Verifying OwnershipFacet..."
npx hardhat verify --network baseSepolia 0xF7250C12cEEf0173E0005eDeE20C9B35c1a4b064 --contract contracts/facets/OwnershipFacet.sol:OwnershipFacet
echo ""

# DiamondCutFacet
echo "✂️  Verifying DiamondCutFacet..."
npx hardhat verify --network baseSepolia 0x34a15ca403360F2F7b3389e3A70Fb8958aB518e6 --contract contracts/facets/DiamondCutFacet.sol:DiamondCutFacet
echo ""

# Diamond (with constructor args)
echo "💎 Verifying Diamond..."
npx hardhat verify --network baseSepolia 0xb899A968e785dD721dbc40e71e2FAEd7B2d84711 0xf070F568c125b2740391136662Fc600A2A29D2A6 0x34a15ca403360F2F7b3389e3A70Fb8958aB518e6 --contract contracts/Diamond.sol:Diamond
echo ""

# DiamondInit
echo "🔧 Verifying DiamondInit..."
npx hardhat verify --network baseSepolia 0xaCbC3778082DA33b382FE5a0581dEBCD4C552385 --contract contracts/DiamondInit.sol:DiamondInit
echo ""

echo "✅ All contracts verification complete!"
#!/bin/bash

echo "🚀 Verifying all remaining Base Sepolia contracts on Blockscout..."
echo ""

# DiamondLoupeFacet
echo "📋 Verifying DiamondLoupeFacet..."
npx hardhat verify --network baseSepolia 0x048Cc025b826678485Aaaf5DbFE12f677CA339E9 --contract contracts/facets/DiamondLoupeFacet.sol:DiamondLoupeFacet
echo ""

# OwnershipFacet
echo "👑 Verifying OwnershipFacet..."
npx hardhat verify --network baseSepolia 0xF7250C12cEEf0173E0005eDeE20C9B35c1a4b064 --contract contracts/facets/OwnershipFacet.sol:OwnershipFacet
echo ""

# DiamondCutFacet
echo "✂️  Verifying DiamondCutFacet..."
npx hardhat verify --network baseSepolia 0x34a15ca403360F2F7b3389e3A70Fb8958aB518e6 --contract contracts/facets/DiamondCutFacet.sol:DiamondCutFacet
echo ""

# Diamond (with constructor args)
echo "💎 Verifying Diamond..."
npx hardhat verify --network baseSepolia 0xb899A968e785dD721dbc40e71e2FAEd7B2d84711 0xf070F568c125b2740391136662Fc600A2A29D2A6 0x34a15ca403360F2F7b3389e3A70Fb8958aB518e6 --contract contracts/Diamond.sol:Diamond
echo ""

# DiamondInit
echo "🔧 Verifying DiamondInit..."
npx hardhat verify --network baseSepolia 0xaCbC3778082DA33b382FE5a0581dEBCD4C552385 --contract contracts/DiamondInit.sol:DiamondInit
echo ""

echo "✅ All contracts verification complete!"
