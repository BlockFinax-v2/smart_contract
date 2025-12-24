/**
 * Verify all Base Sepolia contracts
 */

import { execSync } from "child_process";

const contracts = [
  {
    name: "LiquidityPoolFacet",
    address: "0x10650e68021dcB92EAd3a7e413b6EEe30f281578",
    contract: "contracts/facets/LiquidityPoolFacet.sol:LiquidityPoolFacet",
    args: []
  },
  {
    name: "DiamondLoupeFacet",
    address: "0x048Cc025b826678485Aaaf5DbFE12f677CA339E9",
    contract: "contracts/facets/DiamondLoupeFacet.sol:DiamondLoupeFacet",
    args: []
  },
  {
    name: "OwnershipFacet",
    address: "0xF7250C12cEEf0173E0005eDeE20C9B35c1a4b064",
    contract: "contracts/facets/OwnershipFacet.sol:OwnershipFacet",
    args: []
  },
  {
    name: "DiamondCutFacet",
    address: "0x34a15ca403360F2F7b3389e3A70Fb8958aB518e6",
    contract: "contracts/facets/DiamondCutFacet.sol:DiamondCutFacet",
    args: []
  },
  {
    name: "Diamond",
    address: "0xb899A968e785dD721dbc40e71e2FAEd7B2d84711",
    contract: "contracts/Diamond.sol:Diamond",
    args: ["0xf070F568c125b2740391136662Fc600A2A29D2A6", "0x34a15ca403360F2F7b3389e3A70Fb8958aB518e6"]
  },
  {
    name: "DiamondInit",
    address: "0xaCbC3778082DA33b382FE5a0581dEBCD4C552385",
    contract: "contracts/DiamondInit.sol:DiamondInit",
    args: []
  }
];

async function verifyContract(
  name: string,
  address: string,
  contractPath: string,
  args: string[]
): Promise<void> {
  console.log(`\n🔍 Verifying ${name}...`);
  console.log(`   Address: ${address}`);
  
  try {
    const argsString = args.join(" ");
    const cmd = `npx hardhat verify --network baseSepolia ${address} ${argsString} --contract ${contractPath}`;
    
    execSync(cmd, { stdio: "inherit" });
    console.log(`   ✅ ${name} verified successfully!`);
  } catch (error: any) {
    if (error.message && error.message.includes("Already Verified")) {
      console.log(`   ✅ ${name} already verified`);
    } else {
      console.log(`   ⚠️  ${name} verification failed (may already be verified)`);
    }
  }
  
  // Wait a bit between verifications to avoid rate limiting
  await new Promise(resolve => setTimeout(resolve, 2000));
}

async function main() {
  console.log("\n🚀 Verifying all Base Sepolia contracts...\n");
  
  for (const contract of contracts) {
    await verifyContract(
      contract.name,
      contract.address,
      contract.contract,
      contract.args
    );
  }
  
  console.log("\n\n✅ Verification process complete!");
  console.log("\n📋 Contract Addresses:");
  for (const contract of contracts) {
    console.log(`   ${contract.name}: ${contract.address}`);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
