#!/bin/bash

echo "🔍 Verifying all Base Sepolia contracts..."
echo ""

# GovernanceFacet
echo "1️⃣ Verifying GovernanceFacet..."
npx hardhat verify --network baseSepolia \
  0x85c242c8EA73B35753a91971482Bd8cc5AB8e165 \
  --contract contracts/facets/GovernanceFacet.sol:GovernanceFacet

echo ""

# LiquidityPoolFacet
echo "2️⃣ Verifying LiquidityPoolFacet..."
npx hardhat verify --network baseSepolia \
  0x10650e68021dcB92EAd3a7e413b6EEe30f281578 \
  --contract contracts/facets/LiquidityPoolFacet.sol:LiquidityPoolFacet

echo ""

# DiamondLoupeFacet
echo "3️⃣ Verifying DiamondLoupeFacet..."
npx hardhat verify --network baseSepolia \
  0x048Cc025b826678485Aaaf5DbFE12f677CA339E9 \
  --contract contracts/facets/DiamondLoupeFacet.sol:DiamondLoupeFacet

echo ""

# OwnershipFacet
echo "4️⃣ Verifying OwnershipFacet..."
npx hardhat verify --network baseSepolia \
  0xF7250C12cEEf0173E0005eDeE20C9B35c1a4b064 \
  --contract contracts/facets/OwnershipFacet.sol:OwnershipFacet

echo ""

# DiamondCutFacet
echo "5️⃣ Verifying DiamondCutFacet..."
npx hardhat verify --network baseSepolia \
  0x34a15ca403360F2F7b3389e3A70Fb8958aB518e6 \
  --contract contracts/facets/DiamondCutFacet.sol:DiamondCutFacet

echo ""

# Diamond
echo "6️⃣ Verifying Diamond..."
npx hardhat verify --network baseSepolia \
  0xb899A968e785dD721dbc40e71e2FAEd7B2d84711 \
  0xf070F568c125b2740391136662Fc600A2A29D2A6 \
  0x34a15ca403360F2F7b3389e3A70Fb8958aB518e6 \
  --contract contracts/Diamond.sol:Diamond

echo ""

# DiamondInit
echo "7️⃣ Verifying DiamondInit..."
npx hardhat verify --network baseSepolia \
  0xaCbC3778082DA33b382FE5a0581dEBCD4C552385 \
  --contract contracts/DiamondInit.sol:DiamondInit

echo ""
echo "✅ Verification complete!"
