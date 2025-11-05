import { run } from "hardhat";

// Deployed contract addresses
const ADDRESSES = {
  diamond: "0x65C4ce15C9DFA916db081A41340C3c862F0a3343",
  diamondCutFacet: "0xA02409fB50c90D97304fF37230e2202E3EA384be",
  diamondLoupeFacet: "0x471Fb8C51430C145bcae95f78a0A66E4A63520C9",
  ownershipFacet: "0xE65B037ec83eA37E86Cd72675407BaA3594941Bb",
  contractManagementFacet: "0x2a2e859241FafABc8fAa515Fd69736e7cB53c7d6",
  documentManagementFacet: "0x1479c03b2F6a797061C9BBF566CcdD5E97FB7a3d",
  escrowFacet: "0xE55711F2f4f564D187082eE187FCc03F4be7FC43",
  governanceFacet: "0xB92925516501f9bf5bAD5643b276AE384852b508",
  invoiceFacet: "0x72e1831B54cA0b089c811adD6e16732f77e90f77",
  liquidityPoolFacet: "0x2a32b6c004A1f71412FaF82c9E65db17232e6E1b",
  diamondInit: "0x2776C557702e297fb25603c89604683DDD5F5023",
};

const DEPLOYER = "0xf070F568c125b2740391136662Fc600A2A29D2A6";

async function sleep(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function verifyContract(
  address: string,
  constructorArguments: any[],
  name: string
) {
  console.log(`\n⏳ Verifying ${name}...`);
  console.log(`   Address: ${address}`);

  try {
    await run("verify:verify", {
      address: address,
      constructorArguments: constructorArguments,
    });
    console.log(`✅ ${name} verified successfully!`);
    return true;
  } catch (error: any) {
    if (error.message.includes("Already Verified")) {
      console.log(`✅ ${name} already verified`);
      return true;
    } else if (error.message.includes("does not have bytecode")) {
      console.log(`❌ ${name} - No bytecode found (contract may not be deployed)`);
      return false;
    } else {
      console.log(`❌ ${name} verification failed:`);
      console.log(`   ${error.message}`);
      return false;
    }
  }
}

async function main() {
  console.log("\n🔍 BASESCAN CONTRACT VERIFICATION");
  console.log("================================\n");
  console.log("Network: Base Sepolia");
  console.log("Explorer: https://sepolia.basescan.org\n");

  const results: { [key: string]: boolean } = {};

  // Verify Diamond Proxy (with constructor arguments)
  console.log("\n📍 Part 1: Diamond Proxy");
  console.log("========================");
  results.diamond = await verifyContract(
    ADDRESSES.diamond,
    [DEPLOYER, ADDRESSES.diamondCutFacet],
    "Diamond"
  );
  await sleep(2000); // Wait between verifications

  // Verify all facets (no constructor arguments)
  console.log("\n📍 Part 2: Diamond Standard Facets");
  console.log("===================================");

  const facets = [
    { address: ADDRESSES.diamondCutFacet, name: "DiamondCutFacet" },
    { address: ADDRESSES.diamondLoupeFacet, name: "DiamondLoupeFacet" },
    { address: ADDRESSES.ownershipFacet, name: "OwnershipFacet" },
  ];

  for (const facet of facets) {
    results[facet.name] = await verifyContract(facet.address, [], facet.name);
    await sleep(2000);
  }

  // Verify business logic facets
  console.log("\n📍 Part 3: Business Logic Facets");
  console.log("=================================");

  const businessFacets = [
    { address: ADDRESSES.contractManagementFacet, name: "ContractManagementFacet" },
    { address: ADDRESSES.documentManagementFacet, name: "DocumentManagementFacet" },
    { address: ADDRESSES.escrowFacet, name: "EscrowFacet" },
    { address: ADDRESSES.governanceFacet, name: "GovernanceFacet" },
    { address: ADDRESSES.invoiceFacet, name: "InvoiceFacet" },
    { address: ADDRESSES.liquidityPoolFacet, name: "LiquidityPoolFacet" },
  ];

  for (const facet of businessFacets) {
    results[facet.name] = await verifyContract(facet.address, [], facet.name);
    await sleep(2000);
  }

  // Verify initialization contract
  console.log("\n📍 Part 4: Initialization Contract");
  console.log("===================================");
  results.DiamondInit = await verifyContract(
    ADDRESSES.diamondInit,
    [],
    "DiamondInit"
  );

  // Summary
  console.log("\n\n🎯 VERIFICATION SUMMARY");
  console.log("======================\n");

  const successful = Object.values(results).filter((r) => r === true).length;
  const total = Object.keys(results).length;

  console.log(`Total Contracts: ${total}`);
  console.log(`✅ Verified: ${successful}`);
  console.log(`❌ Failed: ${total - successful}\n`);

  console.log("Detailed Results:");
  console.log("-----------------");
  for (const [name, success] of Object.entries(results)) {
    const status = success ? "✅" : "❌";
    console.log(`${status} ${name}`);
  }

  if (successful === total) {
    console.log("\n🎉 ALL CONTRACTS VERIFIED SUCCESSFULLY!");
    console.log("\n📍 View on Basescan:");
    console.log(`Diamond: https://sepolia.basescan.org/address/${ADDRESSES.diamond}`);
  } else {
    console.log("\n⚠️  Some contracts failed to verify.");
    console.log("You can try verifying them manually using:");
    console.log("npx hardhat verify --network baseSepolia <ADDRESS> <ARGS>\n");
  }

  console.log("\n✨ Verification process complete!\n");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("\n❌ Verification script error:", error);
    process.exit(1);
  });
