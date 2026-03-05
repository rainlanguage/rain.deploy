# Pass 0: Process Review

## Documents Reviewed

- `CLAUDE.md` (56 lines)
- `README.md` (32 lines)
- `flake.nix` (19 lines)
- `.github/workflows/rainix.yaml` (57 lines)
- `REUSE.toml` (17 lines)
- `.gitignore` (3 lines)

## Findings

### A01-1 [LOW] Missing foundry.toml

`REUSE.toml` lists `foundry.toml` in its annotation paths (line 14), but no `foundry.toml` exists at the project root. This means either:
- The project relies on a foundry.toml provided by the rainix nix devshell at runtime, which is not documented
- The REUSE.toml annotation is stale

A future session trying to customize forge settings (e.g., remappings, optimizer settings, solc version) would not know where configuration lives or whether it's expected to exist.

### A01-2 [LOW] CLAUDE.md describes Zoltu as "CREATE2-style" but it is not CREATE2

CLAUDE.md line 7 says "by using CREATE2-style deterministic deployments." The Zoltu proxy uses `CREATE` (not `CREATE2`) — the determinism comes from the proxy's nonce being predictable (nonce 1 on first use). This could mislead a future session into reasoning about CREATE2 salt mechanics that don't apply here.

### A01-3 [INFO] CI environment variables not documented in CLAUDE.md

The CI workflow references several env vars (`ETH_RPC_URL`, `DEPLOYMENT_KEY`, `DEPLOY_BROADCAST`, `DEPLOY_VERIFIER`, `DEPLOY_METABOARD_ADDRESS`, etc.) that are not mentioned in CLAUDE.md. A future session attempting to run deployment scripts locally would not know what variables are expected.

### A01-4 [INFO] No foundry.toml means no documented solc version or optimizer settings

Without a `foundry.toml` in the repo, there's no record of which Solidity compiler version or optimizer settings are used. The pragma in the source is `^0.8.25` which allows any 0.8.x >= 0.8.25. The actual compiler version used depends on whatever the nix devshell provides, which is opaque to someone reading only this repo.
