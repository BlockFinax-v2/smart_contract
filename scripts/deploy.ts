import { ethers, run, network } from "hardhat";
import * as dotenv from "dotenv";
import { Contract } from "ethers";
import { testDiamondIntegration } from "./test-diamond";

dotenv.config();

// Environment variables with validation
const PRIVATE_KEY = process.env.PRIVATE_KEY;
const BASESCAN_API_KEY = process.env.BASESCAN_API_KEY;
const BASE_SEPOLIA_RPC = process.env.BASE_SEPOLIA_RPC;
const BASE_RPC = process.env.BASE_RPC;

// Pre-deployed facet addresses (from failed attempt)
const PRE_DEPLOYED_FACETS = {
  DiamondCutFacet: "0x0a814753E5B05233b2398B8eaB2E0F2d0Ef589cf",
  DiamondLoupeFacet: "0x97d51c6a4915545313d0BaE70c2a8bbDC86319b1",
  OwnershipFacet: "0x8e2D993A7203c11bb117F2408b7C4a1146cCdb16",
  ContractManagementFacet: "0x178FA94E28e9127ffDC9Ef7275144EF78Fe4D62a",
  DocumentManagementFacet: "0x8641a30b50562cC85dF9f705dDb99F614CA615D1",
  EscrowFacet: "0x6B0442851fe9163A8295393f3C601862E79488a5",
  GovernanceFacet: "0xff67b79Dea364a0C5F3b7d6c7623271AA0E2a41e",
};

// Validate environment variables
if (!PRIVATE_KEY) {
  throw new Error("PRIVATE_KEY is not set in .env file");
}

if (network.name === "baseSepolia" && !BASESCAN_API_KEY) {
  console.warn("⚠️  BASESCAN_API_KEY is not set. Contract verification will be skipped.");
}

interface DeploymentResult {
  diamond: string;
  facets: {
    DiamondCutFacet: string;
    DiamondLoupeFacet: string;
    OwnershipFacet: string;
    ContractManagementFacet: string;
    DocumentManagementFacet: string;
    EscrowFacet: string;
    GovernanceFacet: string;
    InvoiceFacet: string;
    LiquidityPoolFacet: string;
    DiamondInit: string;
  };
}

interface InitArgs {
  name: string;
  symbol: string;
  initialSupply: bigint;
  tokenPriceInWei: bigint;
  description: string;
  externalUrl: string;
  backgroundColor: string;
}

async function verify(address: string, constructorArguments: any[]): Promise<void> {
  if (network.name === "hardhat" || network.name === "localhost") {
    return;
  }

  if (!BASESCAN_API_KEY) {
    console.log(`⏭️  Skipping verification for ${address} (no API key)`);
    return;
  }

  console.log(`Verifying contract at ${address}...`);
  try {
    await run("verify:verify", {
      address: address,
      constructorArguments: constructorArguments,
    });
    
    const explorerUrl = network.name === "baseSepolia" 
      ? `https://sepolia.basescan.org/address/${address}`
      : `https://basescan.org/address/${address}`;
    console.log(`✅ Verified: ${explorerUrl}`);
  } catch (e: any) {
    if (e.message.toLowerCase().includes("already verified")) {
      const explorerUrl = network.name === "baseSepolia"
        ? `https://sepolia.basescan.org/address/${address}`
        : `https://basescan.org/address/${address}`;
      console.log(`✅ Already verified: ${explorerUrl}`);
    } else {
      console.log(`❌ Verification failed: ${e.message}`);
    }
  }
}

async function main(): Promise<DeploymentResult> {
  const [deployer] = await ethers.getSigners();
  const deployerAddress = await deployer.getAddress();

  console.log("\n╔════════════════════════════════════════════════════════════╗");
  console.log("║         BlockFinax Diamond Token Deployment Script        ║");
  console.log(`║                     ${network.name.toUpperCase()} Network                     ║`);
  console.log("╚════════════════════════════════════════════════════════════╝\n");

  console.log("📡 Network:", network.name);
  console.log("🔗 Chain ID:", (await ethers.provider.getNetwork()).chainId);
  console.log("👤 Deployer:", deployerAddress);
  console.log("💰 Balance:", ethers.formatEther(await ethers.provider.getBalance(deployerAddress)), "ETH");
  console.log("🔑 Using Private Key:", PRIVATE_KEY ? "✓ Loaded" : "✗ Missing");
  console.log("🔐 Basescan API Key:", BASESCAN_API_KEY ? "✓ Loaded" : "✗ Missing (verification will be skipped)");
  const rpcUrl = network.name === "base" ? BASE_RPC : BASE_SEPOLIA_RPC;
  console.log("🌐 RPC URL:", rpcUrl || "Default\n");

  console.log("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");

  // Use pre-deployed facets (skip deployment, save gas)
  console.log("⏭️  Using Pre-Deployed Facets (skipping redundant deployments)...\n");
  
  const diamondCutFacetAddress = PRE_DEPLOYED_FACETS.DiamondCutFacet;
  console.log("   ✅ DiamondCutFacet:", diamondCutFacetAddress);

  const diamondLoupeFacetAddress = PRE_DEPLOYED_FACETS.DiamondLoupeFacet;
  console.log("   ✅ DiamondLoupeFacet:", diamondLoupeFacetAddress);

  const ownershipFacetAddress = PRE_DEPLOYED_FACETS.OwnershipFacet;
  console.log("   ✅ OwnershipFacet:", ownershipFacetAddress);

  const contractManagementFacetAddress = PRE_DEPLOYED_FACETS.ContractManagementFacet;
  console.log("   ✅ ContractManagementFacet:", contractManagementFacetAddress);

  const documentManagementFacetAddress = PRE_DEPLOYED_FACETS.DocumentManagementFacet;
  console.log("   ✅ DocumentManagementFacet:", documentManagementFacetAddress);

  const escrowFacetAddress = PRE_DEPLOYED_FACETS.EscrowFacet;
  console.log("   ✅ EscrowFacet:", escrowFacetAddress);

  const governanceFacetAddress = PRE_DEPLOYED_FACETS.GovernanceFacet;
  console.log("   ✅ GovernanceFacet:", governanceFacetAddress);

  console.log("\n📦 Deploying Remaining Facets...\n");

  console.log("📦 Deploying InvoiceFacet...");
  const InvoiceFacet = await ethers.getContractFactory("InvoiceFacet");
  const invoiceFacet = await InvoiceFacet.deploy();
  await invoiceFacet.waitForDeployment();
  const invoiceFacetAddress = await invoiceFacet.getAddress();
  console.log("   ✅ InvoiceFacet:", invoiceFacetAddress);

  console.log("📦 Deploying LiquidityPoolFacet...");
  const LiquidityPoolFacet = await ethers.getContractFactory("LiquidityPoolFacet");
  const liquidityPoolFacet = await LiquidityPoolFacet.deploy();
  await liquidityPoolFacet.waitForDeployment();
  const liquidityPoolFacetAddress = await liquidityPoolFacet.getAddress();
  console.log("   ✅ LiquidityPoolFacet:", liquidityPoolFacetAddress);

  console.log("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");

  // Deploy Diamond with DiamondCutFacet
  console.log("💎 Deploying Diamond Proxy...");
  const Diamond = await ethers.getContractFactory("Diamond");
  const diamond = await Diamond.deploy(deployerAddress, diamondCutFacetAddress);
  await diamond.waitForDeployment();
  const diamondAddress = await diamond.getAddress();
  console.log("   ✅ Diamond Proxy:", diamondAddress);

  console.log("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");

  // Prepare facet cuts using pre-deployed facets + newly deployed ones
  console.log("✂️  Preparing Facet Cuts...\n");
  const FacetCutAction = { Add: 0, Replace: 1, Remove: 2 };

  const cuts = [];

  // Get selectors for pre-deployed facets using contract factories (reference only)
  const DiamondLoupeFacetRef = await ethers.getContractFactory("DiamondLoupeFacet");
  const loupeFacetSelectors = getSelectors(DiamondLoupeFacetRef);
  cuts.push({
    facetAddress: diamondLoupeFacetAddress,
    action: FacetCutAction.Add,
    functionSelectors: loupeFacetSelectors,
  });
  console.log("   ✓ DiamondLoupeFacet -", loupeFacetSelectors.length, "functions");

  const OwnershipFacetRef = await ethers.getContractFactory("OwnershipFacet");
  const ownershipFacetSelectors = getSelectors(OwnershipFacetRef);
  cuts.push({
    facetAddress: ownershipFacetAddress,
    action: FacetCutAction.Add,
    functionSelectors: ownershipFacetSelectors,
  });
  console.log("   ✓ OwnershipFacet -", ownershipFacetSelectors.length, "functions");

  const ContractManagementFacetRef = await ethers.getContractFactory("ContractManagementFacet");
  const contractManagementFacetSelectors = getSelectors(ContractManagementFacetRef);
  cuts.push({
    facetAddress: contractManagementFacetAddress,
    action: FacetCutAction.Add,
    functionSelectors: contractManagementFacetSelectors,
  });
  console.log("   ✓ ContractManagementFacet -", contractManagementFacetSelectors.length, "functions");

  const DocumentManagementFacetRef = await ethers.getContractFactory("DocumentManagementFacet");
  const documentManagementFacetSelectors = getSelectors(DocumentManagementFacetRef);
  cuts.push({
    facetAddress: documentManagementFacetAddress,
    action: FacetCutAction.Add,
    functionSelectors: documentManagementFacetSelectors,
  });
  console.log("   ✓ DocumentManagementFacet -", documentManagementFacetSelectors.length, "functions");

  const EscrowFacetRef = await ethers.getContractFactory("EscrowFacet");
  const escrowFacetSelectors = getSelectors(EscrowFacetRef);
  cuts.push({
    facetAddress: escrowFacetAddress,
    action: FacetCutAction.Add,
    functionSelectors: escrowFacetSelectors,
  });
  console.log("   ✓ EscrowFacet -", escrowFacetSelectors.length, "functions (includes pause controls)");

  const GovernanceFacetRef = await ethers.getContractFactory("GovernanceFacet");
  const governanceFacetSelectors = removePauseSelectors(getSelectors(GovernanceFacetRef));
  cuts.push({
    facetAddress: governanceFacetAddress,
    action: FacetCutAction.Add,
    functionSelectors: governanceFacetSelectors,
  });
  console.log("   ✓ GovernanceFacet -", governanceFacetSelectors.length, "functions");

  const invoiceFacetSelectors = removePauseSelectors(getSelectors(invoiceFacet));
  cuts.push({
    facetAddress: invoiceFacetAddress,
    action: FacetCutAction.Add,
    functionSelectors: invoiceFacetSelectors,
  });
  console.log("   ✓ InvoiceFacet -", invoiceFacetSelectors.length, "functions");

  const liquidityPoolFacetSelectors = removePauseSelectors(getSelectors(liquidityPoolFacet));
  cuts.push({
    facetAddress: liquidityPoolFacetAddress,
    action: FacetCutAction.Add,
    functionSelectors: liquidityPoolFacetSelectors,
  });
  console.log("   ✓ LiquidityPoolFacet -", liquidityPoolFacetSelectors.length, "functions");
  
  console.log("\n   ℹ️  Note: pause/unpause/paused functions managed by EscrowFacet");

  console.log("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");

  // Deploy DiamondInit
  console.log("🔧 Deploying DiamondInit...");
  const DiamondInit = await ethers.getContractFactory("DiamondInit");
  const diamondInit = await DiamondInit.deploy();
  await diamondInit.waitForDeployment();
  const diamondInitAddress = await diamondInit.getAddress();
  console.log("   ✅ DiamondInit:", diamondInitAddress);

  // Prepare initialization data
  const initArgs: InitArgs = {
    name: "BlockFinax",
    symbol: "BLX",
    initialSupply: ethers.parseEther("1000000"),
    tokenPriceInWei: ethers.parseEther("0.001"),
    description:
      "BlockFinax - A fully upgradeable diamond proxy ERC20 token with trading, contract management, document verification, swap, multisig, and onchain SVG capabilities",
    externalUrl: "https://blockfinax.com",
    backgroundColor: "667eea",
  };

  const functionCall = diamondInit.interface.encodeFunctionData("init", [initArgs]);

  console.log("\n💫 Executing Diamond Cut...");
  // Execute diamond cut to add all facets
  const diamondCut = await ethers.getContractAt("IDiamondCut", diamondAddress);
  const tx = await diamondCut.diamondCut(cuts, diamondInitAddress, functionCall);
  console.log("   ⏳ Transaction hash:", tx.hash);
  await tx.wait();
  console.log("   ✅ Diamond Cut executed successfully!");

  console.log("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");

  // Verify all contracts
  if (network.name !== "hardhat" && network.name !== "localhost" && BASESCAN_API_KEY) {
    console.log("🔍 Verifying Contracts on Basescan...\n");
    console.log("⏳ Waiting for block confirmations...\n");
    
    await verify(diamondCutFacetAddress, []);
    await verify(diamondLoupeFacetAddress, []);
    await verify(ownershipFacetAddress, []);
    await verify(contractManagementFacetAddress, []);
    await verify(documentManagementFacetAddress, []);
    await verify(escrowFacetAddress, []);
    await verify(governanceFacetAddress, []);
    await verify(invoiceFacetAddress, []);
    await verify(liquidityPoolFacetAddress, []);
    await verify(diamondInitAddress, []);
    await verify(diamondAddress, [deployerAddress, diamondCutFacetAddress]);
    
    console.log("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");
  }

  // Log deployed and verified contract addresses
  console.log("\n╔════════════════════════════════════════════════════════════╗");
  console.log("║              Deployment Summary                            ║");
  console.log("╚════════════════════════════════════════════════════════════╝\n");

  console.log("💎 DIAMOND PROXY");
  console.log("   Address:", diamondAddress);
  const explorerUrl = network.name === "baseSepolia" 
    ? "https://sepolia.basescan.org/address/" 
    : "https://basescan.org/address/";
  if (network.name === "baseSepolia" || network.name === "base") {
    console.log("   Explorer:", explorerUrl + diamondAddress);
  }

  console.log("\n📋 IMPLEMENTATION CONTRACTS\n");
  
  const contracts = [
    { name: "DiamondCutFacet", address: diamondCutFacetAddress },
    { name: "DiamondLoupeFacet", address: diamondLoupeFacetAddress },
    { name: "OwnershipFacet", address: ownershipFacetAddress },
    { name: "ContractManagementFacet", address: contractManagementFacetAddress },
    { name: "DocumentManagementFacet", address: documentManagementFacetAddress },
    { name: "EscrowFacet", address: escrowFacetAddress },
    { name: "GovernanceFacet", address: governanceFacetAddress },
    { name: "InvoiceFacet", address: invoiceFacetAddress },
    { name: "LiquidityPoolFacet", address: liquidityPoolFacetAddress },
    { name: "DiamondInit", address: diamondInitAddress },
  ];

  for (const contract of contracts) {
    console.log(`   ${contract.name}`);
    console.log(`   └─ ${contract.address}`);
    if (network.name === "baseSepolia" || network.name === "base") {
      console.log(`      ${explorerUrl}${contract.address}`);
    }
  }

  console.log("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");
  console.log("✅ Deployment completed successfully!\n");

  // Test Diamond Integration (optional)
  try {
    await testDiamondIntegration(diamondAddress);
  } catch (error) {
    console.log("ℹ️  Skipping integration tests");
  }

  return {
    diamond: diamondAddress,
    facets: {
      DiamondCutFacet: diamondCutFacetAddress,
      DiamondLoupeFacet: diamondLoupeFacetAddress,
      OwnershipFacet: ownershipFacetAddress,
      ContractManagementFacet: contractManagementFacetAddress,
      DocumentManagementFacet: documentManagementFacetAddress,
      EscrowFacet: escrowFacetAddress,
      GovernanceFacet: governanceFacetAddress,
      InvoiceFacet: invoiceFacetAddress,
      LiquidityPoolFacet: liquidityPoolFacetAddress,
      DiamondInit: diamondInitAddress,
    },
  };
}

// Helper function to get selectors
function getSelectors(contract: any): string[] {
  const signatures = Object.keys(contract.interface.fragments)
    .filter((key) => {
      const fragment = contract.interface.fragments[key];
      return fragment.type === "function";
    })
    .map((key) => contract.interface.fragments[key].format("sighash"));

  const selectors = signatures.reduce((acc: string[], val: string) => {
    // Skip init function and common pausable functions to avoid collisions
    // Only the first facet with pause functions will keep them
    if (val !== "init(bytes)") {
      const selector = contract.interface.getFunction(val)!.selector;
      acc.push(selector);
    }
    return acc;
  }, []);
  return selectors;
}

// Helper function to remove pause-related selectors (for facets after the first)
function removePauseSelectors(selectors: string[]): string[] {
  const contract = {
    interface: {
      getFunction: (name: string) => {
        try {
          return ethers.Interface.from([
            "function pause()",
            "function unpause()",
            "function paused() view returns (bool)"
          ]).getFunction(name);
        } catch {
          return null;
        }
      }
    }
  };
  
  const pauseSelectors = [
    "0x8456cb59", // pause()
    "0x3f4ba83a", // unpause()
    "0x5c975abb"  // paused()
  ];
  
  return selectors.filter(s => !pauseSelectors.includes(s));
}

// Execute deployment
if (require.main === module) {
  main()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error("\n❌ Deployment failed:\n");
      console.error(error);
      process.exit(1);
    });
}

export { main, getSelectors };
