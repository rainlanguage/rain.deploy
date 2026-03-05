# Audit Triage — 2026-03-05-01

## Findings Index (LOW+ only, sorted by pass then agent ID)

| ID | Pass | Severity | Title | Status |
|----|------|----------|-------|--------|
| P0-A01-1 | 0 | LOW | Missing foundry.toml | FIXED |
| P0-A01-2 | 0 | LOW | CLAUDE.md describes Zoltu as "CREATE2-style" | FIXED |
| P1-A01-1 | 1 | LOW | Silent `address(0)` return when networks array is empty | FIXED |
| P1-A01-2 | 1 | LOW | TOCTOU gap between dependency checking and deployment | FIXED |
| P2-A01-1 | 2 | HIGH | No test file exists for LibRainDeploy.sol | FIXED |
| P3-A01-1 | 3 | LOW | Missing @param tags for 5 of 8 parameters | FIXED |
| P3-A01-2 | 3 | LOW | NatSpec description inaccurate ("all supported networks") | FIXED |
| P3-A01-3 | 3 | LOW | @return description misleading ("on the last network") | FIXED |
| P4-A01-1 | 4 | LOW | Inconsistent comment style: `///` for inline comments | DISMISSED |
| P4-A01-2 | 4 | LOW | Typo "verficiation" in log message | FIXED |
| P5-A01-1 | 5 | LOW | Function name implies restriction to supported networks | FIXED |

## Triage Decisions

### P0-A01-1 — Missing foundry.toml
**Status:** FIXED — Added `foundry.toml` with minimal default profile (src, out, libs).

### P0-A01-2 — CLAUDE.md describes Zoltu as "CREATE2-style"
**Status:** FIXED — Updated CLAUDE.md to describe the actual mechanism (CREATE with predictable nonce).

### P1-A01-1 — Silent address(0) return when networks array is empty
**Status:** FIXED — Added `NoNetworks()` error and early revert when `networks.length == 0`.

### P1-A01-2 — TOCTOU gap between dependency checking and deployment
**Status:** FIXED — Added `depCodeHashes` storage mapping parameter, split into `checkDependencies` and `deployToNetworks`. Check phase records codehashes; deploy phase re-verifies code.length > 0 and codehash match. Added `DependencyChanged` error. Tests cover both codehash mismatch and code destruction paths.

### P2-A01-1 — No test file exists for LibRainDeploy.sol
**Status:** FIXED — Added `test/src/lib/LibRainDeploy.t.sol` with 11 tests covering all functions and error paths: `supportedNetworks`, `deployZoltu` (happy + DeployFailed), `checkDependencies` (records codehash + MissingDependency), `deployToNetworks` (UnexpectedDeployedAddress, UnexpectedDeployedCodeHash, DependencyChanged codehash, DependencyChanged code length), `deployAndBroadcastToSupportedNetworks` (happy path + NoNetworks). Also added `cbor_metadata = false` and `bytecode_hash = "none"` to `foundry.toml` for stable creation code bytecode.

### P3-A01-1 — Missing @param tags for 5 of 8 parameters
**Status:** FIXED — Added missing `@param` tags for `networks`, `contractPath`, `expectedAddress`, `expectedCodeHash`, `dependencies`, and `depCodeHashes` on `deployAndBroadcastToSupportedNetworks`.

### P3-A01-2 — NatSpec description inaccurate ("all supported networks")
**Status:** FIXED — Changed "to all supported networks" to "to the given networks".

### P3-A01-3 — @return description misleading ("on the last network")
**Status:** FIXED — Removed "on the last network" qualifier from `@return` description.

### P4-A01-1 — Inconsistent comment style: `///` for inline comments
**Status:** DISMISSED — All `///` comments are on declarations (NatSpec). Inline comments already use `//`. Finding was likely based on pre-fix code state.

### P4-A01-2 — Typo "verficiation" in log message
**Status:** FIXED — Corrected "verficiation" to "verification".

### P5-A01-1 — Function name implies restriction to supported networks
**Status:** FIXED — Renamed `deployAndBroadcastToSupportedNetworks` to `deployAndBroadcast`.
