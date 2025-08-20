# Zeta Arbitrage Bot — Uniswap V3 Quoter + Dynamic Fee Tiers

This repo deploys `PureTrustlessArbitrageBotZetaQuoter` to ZetaChain using **GitHub Actions**.

## Deployment via GitHub Actions (free)

1. Create a **private GitHub repo** and upload these files.
2. Add **Actions Secrets** (Repo → Settings → Secrets and variables → Actions → New repository secret):

Required:
- `PRIVATE_KEY` — deployer wallet (funded with ZETA)
- `ZETA_TESTNET_RPC` — e.g. https://rpc.ankr.com/zetachain_evm_testnet
- `ZETA_MAINNET_RPC` — e.g. https://rpc.ankr.com/zetachain

Constructor params (chain-specific addresses — set as **Secrets** too):
- `UNI_V2_ROUTER`
- `UNI_V3_ROUTER`
- `UNI_V3_QUOTER_V2`
- `WRAPPED_NATIVE`
- `SUPPORTED_TOKENS` — comma-separated addresses (e.g. 0x...,0x...,0x...)

3. Go to **Actions** tab → run **Deploy Contract to ZetaChain** (or push to `main`).

The job output will print:
```
✅ Arbitrage contract deployed at: 0xYourAddress
```

## Local usage

```bash
npm i
cp .env.example .env  # fill with keys and RPCs
npx hardhat compile
npx hardhat run scripts/deploy.js --network zetatestnet
```

### .env.example
```
PRIVATE_KEY=0xyourkey
ZETA_TESTNET_RPC=https://rpc.ankr.com/zetachain_evm_testnet
ZETA_MAINNET_RPC=https://rpc.ankr.com/zetachain
UNI_V2_ROUTER=0x...
UNI_V3_ROUTER=0x...
UNI_V3_QUOTER_V2=0x...
WRAPPED_NATIVE=0x...
SUPPORTED_TOKENS=0x...,0x...,0x...
```

---

### Security
- Use a **fresh, low-balance** deployer key.
- Review addresses and test on **testnet** first.
- Contract is provided *as-is*; audit before mainnet.
