# Pass 1: Security -- LibRainDeploy.sol

**Agent:** A01
**File:** `src/lib/LibRainDeploy.sol` (148 lines)

## Evidence of Thorough Reading

**Library name:** `LibRainDeploy` (line 14)

**Functions:**
| Function | Line | Visibility |
|----------|------|------------|
| `deployZoltu(bytes memory creationCode)` | 48 | internal |
| `supportedNetworks()` | 67 | internal pure |
| `deployAndBroadcastToSupportedNetworks(Vm, string[], uint256, bytes, string, address, bytes32, address[])` | 83 | internal |

**Errors:**
| Error | Line |
|-------|------|
| `DeployFailed(bool success, address deployedAddress)` | 18 |
| `MissingDependency(string network, address dependency)` | 21 |
| `UnexpectedDeployedAddress(address expected, address actual)` | 24 |
| `UnexpectedDeployedCodeHash(bytes32 expected, bytes32 actual)` | 27 |

**Constants:**
| Constant | Line | Value |
|----------|------|-------|
| `ZOLTU_FACTORY` | 30 | `0x7A0D94F55792C434d74a40883C6ed8545E406D12` |
| `ARBITRUM_ONE` | 33 | `"arbitrum"` |
| `BASE` | 36 | `"base"` |
| `FLARE` | 39 | `"flare"` |
| `POLYGON` | 42 | `"polygon"` |

**Types:** None defined.

**Imports:** `Vm` from `forge-std/Vm.sol` (line 5), `console2` from `forge-std/console2.sol` (line 6).

## Findings

### A01-1 [LOW] Silent `address(0)` return when `networks` array is empty

**Location:** `deployAndBroadcastToSupportedNetworks`, lines 92-147

**Description:**
If the `networks` parameter is an empty array, both for-loops (lines 98-115 and 118-146) are skipped entirely. The return variable `deployedAddress` is never assigned and defaults to `address(0)`. The function returns successfully with `address(0)`, with no error or revert.

A caller that accidentally passes an empty `networks` array -- for example by constructing it dynamically and encountering a filtering bug -- would receive `address(0)` as a valid deployed address with no indication of failure.

**Impact:** A script relying on the return value would proceed with `address(0)`, which could lead to downstream misconfiguration (e.g., setting `address(0)` as a trusted contract address in further deployment steps).

### A01-2 [LOW] TOCTOU gap between dependency checking and deployment

**Location:** `deployAndBroadcastToSupportedNetworks`, lines 98-146

**Description:**
The function performs dependency checking in a first loop (lines 98-115) by creating a fork for each network and verifying that the Zoltu factory and all dependencies have code. It then performs deployment in a second loop (lines 118-146) by creating a *new* fork for each network via `vm.createSelectFork`.

Each `createSelectFork` call fetches the chain state at the current block. Between the dependency-check fork and the deploy fork for a given network, the underlying chain advances. If a dependency contract were destroyed (via `SELFDESTRUCT` / `SELFDESTRUCT` scheduled in a prior transaction) in the intervening blocks, the deployment would proceed without re-checking, potentially deploying a contract whose constructor references a now-nonexistent dependency.

**Mitigating factors:**
- This runs as a Foundry script, not on-chain, so the window is small (seconds at most)
- `SELFDESTRUCT` of well-established dependency contracts is highly unlikely in practice
- The deployment itself would likely fail or produce wrong code, caught by the `expectedCodeHash` check on line 135

**Impact:** In a contrived scenario, a deployment could succeed on a network where a dependency has been removed between the check and deploy forks. Practically very unlikely but the two-loop pattern introduces an unnecessary gap.

### A01-3 [INFO] Typo in log message

**Location:** Line 140

**Description:**
The log message reads `"manual verficiation command:"` -- "verficiation" should be "verification". This is cosmetic and has no security impact, but could cause confusion when searching logs by keyword.
