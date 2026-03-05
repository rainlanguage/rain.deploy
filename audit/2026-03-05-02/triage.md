# Audit Triage — 2026-03-05-02

## Prior Audit

Previous audit `2026-03-05-01` fully triaged (10 FIXED, 1 DISMISSED). Current P1-A01-1 is a refinement of previous P1-A01-1 (which added `NoNetworks()` to `deployAndBroadcast` but not to sub-functions). No other duplicates.

## Findings Index (LOW+ only, sorted by pass then agent ID)

| ID | Pass | Severity | Title | Status |
|----|------|----------|-------|--------|
| P0-A01-1 | 0 | LOW | CI missing FLARE_RPC_URL and POLYGON_RPC_URL env vars | FIXED |
| P0-A01-2 | 0 | LOW | CLAUDE.md RPC section has placeholder values for Flare and Polygon | FIXED |
| P1-A01-1 | 1 | LOW | `deployToNetworks` and `checkDependencies` lack empty-networks guard | FIXED |
| P2-A01-1 | 2 | MEDIUM | `checkDependencies` -- `MissingDependency` for Zoltu factory is untested | FIXED |
| P2-A01-2 | 2 | MEDIUM | `checkDependencies` -- `DependencyChanged` for Zoltu factory codehash mismatch is untested | FIXED |
| P2-A01-3 | 2 | MEDIUM | `deployToNetworks` -- `DependencyChanged` for Zoltu factory is untested | FIXED |
| P2-A01-4 | 2 | LOW | `deployZoltu` -- `DeployFailed` with `success=false` is untested | FIXED |
| P2-A01-5 | 2 | LOW | `deployToNetworks` -- skip-deployment path is untested | FIXED |
| P3-A01-1 | 3 | LOW | ZOLTU_FACTORY NatSpec calls it a "proxy" instead of "factory" | FIXED |
| P3-A01-2 | 3 | LOW | DependencyChanged NatSpec is narrower than actual usage | FIXED |
| P4-A01-1 | 4 | LOW | `(forkId);` no-op pattern to suppress unused variable warning | DOCUMENTED |
| P4-A01-2 | 4 | LOW | Inconsistent error handling between `checkDependencies` and `deployToNetworks` | FIXED |
| P4-A01-3 | 4 | LOW | Magic numbers `12` and `20` in assembly block lack inline documentation | FIXED |

## Triage Decisions

### P0-A01-1 — CI missing FLARE_RPC_URL and POLYGON_RPC_URL env vars
**Status:** FIXED — Added `FLARE_RPC_URL` and `POLYGON_RPC_URL` env vars to `.github/workflows/rainix.yaml`.

### P0-A01-2 — CLAUDE.md RPC section has placeholder values for Flare and Polygon
**Status:** FIXED — Replaced placeholders with real public RPC URLs (`https://flare-api.flare.network/ext/C/rpc` and `https://polygon-rpc.com`).

### P1-A01-1 — `deployToNetworks` and `checkDependencies` lack empty-networks guard
**Status:** FIXED — Added `NoNetworks()` guard to both `checkDependencies` and `deployToNetworks`. Added tests `testCheckDependenciesNoNetworksReverts` and `testDeployToNetworksNoNetworksReverts`.

### P2-A01-1 — `checkDependencies` -- `MissingDependency` for Zoltu factory is untested
**Status:** FIXED — Added `testCheckDependenciesMissingZoltuFactoryReverts` which etches factory to empty (with `makePersistent`) and expects `MissingDependency(ARBITRUM_ONE, ZOLTU_FACTORY)`.

### P2-A01-2 — `checkDependencies` -- `DependencyChanged` for Zoltu factory codehash mismatch is untested
**Status:** FIXED — Added `testCheckDependenciesZoltuFactoryCodehashChangedReverts` which etches factory to `hex"00"` (with `makePersistent`) and expects `DependencyChanged` with `keccak256(hex"00")` as actual codehash.

### P2-A01-3 — `deployToNetworks` -- `DependencyChanged` for Zoltu factory is untested
**Status:** FIXED — Added `testDeployToNetworksZoltuFactoryMissingReverts` (factory etched empty, expects codehash `0xc5d246...`) and `testDeployToNetworksZoltuFactoryCodehashChangedReverts` (factory etched to `hex"00"`, expects `keccak256(hex"00")`).

### P2-A01-4 — `deployZoltu` -- `DeployFailed` with `success=false` is untested
**Status:** FIXED — Added `MockReverter` contract with reverting constructor and `testDeployZoltuRevertsRevertingConstructor` which expects `DeployFailed(false, address(0))`.

### P2-A01-5 — `deployToNetworks` -- skip-deployment path is untested
**Status:** FIXED — Added `testDeployToNetworksSkipsWhenAlreadyDeployed` which deploys `MockDeployable` first (with `makePersistent`), then calls `deployToNetworks` again verifying the skip path returns the correct address with matching codehash.

### P3-A01-1 — ZOLTU_FACTORY NatSpec calls it a "proxy" instead of "factory"
**Status:** FIXED — Changed "Zoltu proxy" to "Zoltu factory" in NatSpec comment.

### P3-A01-2 — DependencyChanged NatSpec is narrower than actual usage
**Status:** FIXED — Changed NatSpec to "Thrown when a dependency's code hash does not match the expected value."

### P4-A01-1 — `(forkId);` no-op pattern to suppress unused variable warning
**Status:** DOCUMENTED — Added inline comment explaining the pattern is to suppress slither unused-return warning.

### P4-A01-2 — Inconsistent error handling between `checkDependencies` and `deployToNetworks`
**Status:** FIXED — Split combined `||` checks in `deployToNetworks` into two-step pattern matching `checkDependencies`: first check `code.length == 0` → `MissingDependency`, then check codehash → `DependencyChanged`. Updated tests `testDeployToNetworksZoltuFactoryMissingReverts` and `testDependencyMissingAtDeployTimeReverts` to expect `MissingDependency`.

### P4-A01-3 — Magic numbers `12` and `20` in assembly block lack inline documentation
**Status:** FIXED — Added inline comments explaining the memory layout: 20 is the address size, 12 = 32 - 20 is the padding offset to right-align the address in the 32-byte scratch space word.
