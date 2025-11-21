import { run } from "hardhat";

// Updated deployment addresses after upgrade
// Note: Update the newLiquidityPoolFacet address after running the upgrade script
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
  oldLiquidityPoolFacet: "0x2a32b6c004A1f71412FaF82c9E65db17232e6E1b", // Old address
  newLiquidityPoolFacet: "UPDATE_THIS_ADDRESS_AFTER_UPGRADE", // New address from upgrade script
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

  if (address === "UPDATE_THIS_ADDRESS_AFTER_UPGRADE") {
    console.log(`   ⏭️  Skipping ${name} - Address not updated yet`);
    return false;
  }

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
  console.log("\n🔍 BASESCAN VERIFICATION - UPGRADED CONTRACTS");
  console.log("==============================================\n");
  console.log("Network: Base Sepolia");
  console.log("Explorer: https://sepolia.basescan.org\n");

  const results: { [key: string]: boolean } = {};

  // Verify only the new LiquidityPoolFacet (others should already be verified)
  console.log("\n📍 Verifying Upgraded Contract");
  console.log("==============================");
  
  results.newLiquidityPoolFacet = await verifyContract(
    ADDRESSES.newLiquidityPoolFacet,
    [],
    "New LiquidityPoolFacet"
  );
  await sleep(2000);

  // Optionally re-verify other contracts if needed
  console.log("\n📍 Optional: Re-verify Existing Contracts");
  console.log("==========================================");
  console.log("ℹ️  These should already be verified from previous deployment");

  const existingContracts = [
    { address: ADDRESSES.diamond, name: "Diamond", args: [DEPLOYER, ADDRESSES.diamondCutFacet] },
    { address: ADDRESSES.diamondCutFacet, name: "DiamondCutFacet", args: [] },
    { address: ADDRESSES.diamondLoupeFacet, name: "DiamondLoupeFacet", args: [] },
    { address: ADDRESSES.ownershipFacet, name: "OwnershipFacet", args: [] },
    { address: ADDRESSES.contractManagementFacet, name: "ContractManagementFacet", args: [] },
    { address: ADDRESSES.documentManagementFacet, name: "DocumentManagementFacet", args: [] },
    { address: ADDRESSES.escrowFacet, name: "EscrowFacet", args: [] },
    { address: ADDRESSES.governanceFacet, name: "GovernanceFacet", args: [] },
    { address: ADDRESSES.invoiceFacet, name: "InvoiceFacet", args: [] },
    { address: ADDRESSES.diamondInit, name: "DiamondInit", args: [] },
  ];

  // Ask user if they want to re-verify existing contracts
  console.log("⏭️  Skipping re-verification of existing contracts");
  console.log("   Run with --force-reverify flag to verify all contracts\n");

  // Summary
  console.log("\n🎯 VERIFICATION SUMMARY");
  console.log("=======================\n");

  const successful = Object.values(results).filter((r) => r === true).length;
  const total = Object.keys(results).length;

  console.log(`New Contracts Verified: ${successful}/${total}`);

  console.log("\nDetailed Results:");
  console.log("-----------------");
  for (const [name, success] of Object.entries(results)) {
    const status = success ? "✅" : "❌";
    console.log(`${status} ${name}`);
  }

  console.log("\n📍 UPDATED CONTRACT ADDRESSES");
  console.log("==============================");
  console.log(`Diamond (unchanged): ${ADDRESSES.diamond}`);
  console.log(`Old LiquidityPoolFacet: ${ADDRESSES.oldLiquidityPoolFacet}`);
  console.log(`New LiquidityPoolFacet: ${ADDRESSES.newLiquidityPoolFacet}`);

  console.log("\n🔗 EXPLORER LINKS");
  console.log("==================");
  console.log(`Diamond: https://sepolia.basescan.org/address/${ADDRESSES.diamond}`);
  if (ADDRESSES.newLiquidityPoolFacet !== "UPDATE_THIS_ADDRESS_AFTER_UPGRADE") {
    console.log(`New LiquidityPoolFacet: https://sepolia.basescan.org/address/${ADDRESSES.newLiquidityPoolFacet}`);
  }

  console.log("\n📝 INSTRUCTIONS:");
  console.log("==================");
  console.log("1. After running the upgrade script, update the 'newLiquidityPoolFacet' address above");
  console.log("2. Re-run this verification script to verify the new contract");
  console.log("3. Test the upgraded functionality");
  console.log("4. Update your application to use the new Diamond address (unchanged)");

  console.log("\n✨ Verification process complete!\n");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("\n❌ Verification script error:", error);
    process.exit(1);
  });