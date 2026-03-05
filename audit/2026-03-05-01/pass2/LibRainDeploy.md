# Pass 2: Test Coverage -- LibRainDeploy.sol

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
| Constant | Line |
|----------|------|
| `ZOLTU_FACTORY` | 30 |
| `ARBITRUM_ONE` | 33 |
| `BASE` | 36 |
| `FLARE` | 39 |
| `POLYGON` | 42 |

## Test File Search

- `test/` directory: does not exist
- Grep for `LibRainDeploy` across all `.sol` files: only found in `src/lib/LibRainDeploy.sol` itself
- No test files exist anywhere in the project (excluding `lib/forge-std/test/`)

## Findings

### A01-1 [HIGH] No test file exists for LibRainDeploy.sol

**Description:**
The sole source file in this project has zero test coverage. There is no `test/` directory and no test files anywhere in the repo (outside of the forge-std submodule).

Functions with no test coverage:
- `deployZoltu` — the core deployment mechanism using inline assembly
- `supportedNetworks` — pure function returning network list
- `deployAndBroadcastToSupportedNetworks` — the main orchestration function

Error paths with no test coverage:
- `DeployFailed` revert (line 61) — when Zoltu factory call fails or returns zero address
- `MissingDependency` revert (lines 106, 112) — when Zoltu factory or dependencies missing on a network
- `UnexpectedDeployedAddress` revert (line 132) — when deployed address doesn't match expected
- `UnexpectedDeployedCodeHash` revert (line 136) — when code hash doesn't match expected

Edge cases with no coverage:
- Empty `networks` array (returns `address(0)` silently — see Pass 1 A01-1)
- Empty `dependencies` array (valid but untested)
- Empty `creationCode` (behavior undefined)
- `creationCode` that reverts during construction
- Re-deployment when code already exists at expected address (skip path, line 127)

Note: Testing this library is non-trivial because it relies on Foundry VM cheatcodes (`createSelectFork`, `startBroadcast`, `rememberKey`) and external network state. However, Foundry supports forked-mode testing which can exercise these paths.
