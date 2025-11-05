#!/bin/bash

echo "🔍 Checking Contract Verification Status"
echo "========================================"
echo ""

CONTRACTS=(
    "0x65C4ce15C9DFA916db081A41340C3c862F0a3343:Diamond"
    "0xA02409fB50c90D97304fF37230e2202E3EA384be:DiamondCutFacet"
    "0x471Fb8C51430C145bcae95f78a0A66E4A63520C9:DiamondLoupeFacet"
    "0xE65B037ec83eA37E86Cd72675407BaA3594941Bb:OwnershipFacet"
    "0x2a2e859241FafABc8fAa515Fd69736e7cB53c7d6:ContractManagementFacet"
    "0x1479c03b2F6a797061C9BBF566CcdD5E97FB7a3d:DocumentManagementFacet"
    "0xE55711F2f4f564D187082eE187FCc03F4be7FC43:EscrowFacet"
    "0xB92925516501f9bf5bAD5643b276AE384852b508:GovernanceFacet"
    "0x72e1831B54cA0b089c811adD6e16732f77e90f77:InvoiceFacet"
    "0x2a32b6c004A1f71412FaF82c9E65db17232e6E1b:LiquidityPoolFacet"
    "0x2776C557702e297fb25603c89604683DDD5F5023:DiamondInit"
)

BASE_URL="https://sepolia.basescan.org/address"

echo "Network: Base Sepolia"
echo "Explorer: https://sepolia.basescan.org"
echo ""
echo "Contracts to check: ${#CONTRACTS[@]}"
echo ""

for contract in "${CONTRACTS[@]}"; do
    IFS=':' read -r address name <<< "$contract"
    echo "📍 $name"
    echo "   Address: $address"
    echo "   URL: $BASE_URL/$address"
    echo ""
done

echo "✅ Open each URL to check if contracts are verified"
echo ""
echo "Look for:"
echo "  ✅ Green checkmark next to contract address"
echo "  ✅ 'Contract' tab showing source code"
echo "  ✅ 'Read Contract' and 'Write Contract' tabs available"
echo ""
echo "If not verified, follow VERIFICATION_GUIDE.md"
