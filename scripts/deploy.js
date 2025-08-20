const hre = require("hardhat");

async function main() {
  // READ: set constructor params through env for convenience
  const uniV2 = process.env.UNI_V2_ROUTER;
  const uniV3 = process.env.UNI_V3_ROUTER;
  const quoter = process.env.UNI_V3_QUOTER_V2;
  const wrapped = process.env.WRAPPED_NATIVE;
  const supported = (process.env.SUPPORTED_TOKENS || "").split(",").filter(Boolean);

  if (!uniV2 || !uniV3 || !quoter || !wrapped || supported.length === 0) {
    console.log("❌ Missing constructor env vars:");
    console.log("UNI_V2_ROUTER, UNI_V3_ROUTER, UNI_V3_QUOTER_V2, WRAPPED_NATIVE, SUPPORTED_TOKENS (comma-separated)");
    process.exit(1);
  }

  const Arb = await hre.ethers.getContractFactory("PureTrustlessArbitrageBotZetaQuoter");
  const arb = await Arb.deploy(uniV2, uniV3, quoter, wrapped, supported);
  await arb.waitForDeployment();

  const addr = await arb.getAddress();
  console.log("✅ Arbitrage contract deployed at:", addr);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
