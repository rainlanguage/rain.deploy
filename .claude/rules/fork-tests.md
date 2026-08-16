---
paths:
  - "test/**/*.sol"
  - "foundry.toml"
---

# Fork tests need every RPC endpoint, not just the one under test

`RainDeployVerifyChain` forks every network in
`LibRainDeploy.supportedNetworks()`, so ALL of the `[rpc_endpoints]` aliases in
`foundry.toml` must resolve. They read from a gitignored `.env`:

```bash
ARBITRUM_RPC_URL=https://arb1.arbitrum.io/rpc
BASE_RPC_URL=https://mainnet.base.org
BASE_SEPOLIA_RPC_URL=https://sepolia.base.org
FLARE_RPC_URL=https://flare-api.flare.network/ext/C/rpc
POLYGON_RPC_URL=https://polygon-bor-rpc.publicnode.com
```

A missing or rate-limited endpoint fails as a `vm.createSelectFork` error. That
is a different failure from the `NotDeployedOnNetwork` a reachable network
raises, and only the second one is a statement about the deployment — do not
read a flaky endpoint as a missing deploy.
