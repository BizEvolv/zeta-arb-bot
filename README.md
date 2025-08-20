# ZetaChain Arbitrage Bot

This repo contains a Uniswap V2/V3 arbitrage contract with Quoter V2 integration for ZetaChain.

## Deploying

1. Create a new GitHub repo and upload this project.
2. Add the following secrets in **Repo → Settings → Secrets → Actions**:

- PRIVATE_KEY
- ZETA_TESTNET_RPC
- ZETA_MAINNET_RPC
- UNI_V2_ROUTER
- UNI_V3_ROUTER
- UNI_V3_QUOTER_V2
- WRAPPED_NATIVE
- SUPPORTED_TOKENS

3. Go to **Actions** → **Deploy Contract to ZetaChain** → **Run workflow**.
4. Choose either **Deploy to Testnet** or **Deploy to Mainnet**.
5. The contract address will be printed in the logs.
