# Pass 1: Security — A01 — LibRainDeploy

**Agent:** A01
**File:** `src/lib/LibRainDeploy.sol` (253 lines)

## Evidence of Thorough Reading

**Library name:** `LibRainDeploy` (line 14)

**Functions:**
| Function | Line | Visibility |
|----------|------|------------|
| `etchZoltuFactory(Vm vm)` | 60 | internal |
| `deployZoltu(bytes memory creationCode)` | 68 | internal |
| `supportedNetworks()` | 87 | internal pure |
| `checkDependencies(Vm, string[], address[], mapping(...))` | 102 | internal |
| `deployToNetworks(Vm, string[], address, bytes, string, address, bytes32, address[], mapping(...))` | 145 | internal |
| `deployAndBroadcast(Vm, string[], uint256, bytes, string, address, bytes32, address[], mapping(...))` | 222 | internal |

**Errors:**
| Error | Line |
|-------|------|
| `DeployFailed(bool success, address deployedAddress)` | 18 |
| `MissingDependency(string network, address dependency)` | 21 |
| `UnexpectedDeployedAddress(address expected, address actual)` | 24 |
| `UnexpectedDeployedCodeHash(bytes32 expected, bytes32 actual)` | 27 |
| `DependencyChanged(string network, address dependency, bytes32 expectedCodeHash, bytes32 actualCodeHash)` | 31 |
| `NoNetworks()` | 34 |

**Constants:**
| Constant | Line | Type |
|----------|------|------|
| `ZOLTU_FACTORY` | 37 | `address` |
| `ZOLTU_FACTORY_CODEHASH` | 40 | `bytes32` |
| `ZOLTU_FACTORY_BYTECODE` | 43 | `bytes` |
| `ARBITRUM_ONE` | 46 | `string` |
| `BASE` | 49 | `string` |
| `FLARE` | 52 | `string` |
| `POLYGON` | 55 | `string` |

**Types:** None defined.

**Imports:** `Vm` from `forge-std/Vm.sol` (line 5), `console2` from `forge-std/console2.sol` (line 6).

## Security Checklist Analysis

### Memory safety in assembly blocks

The assembly block at lines 71-75 is annotated `"memory-safe"` and operates exclusively on scratch space (memory offsets 0-31). The sequence `mstore(0, 0)` zeroes 32 bytes, then the `call` return buffer writes 20 bytes at offset 12 (filling bytes 12-31), and `mload(0)` reads the full 32 bytes back as a properly left-padded address. The input pointer `add(creationCode, 0x20)` and length `mload(creationCode)` correctly dereference a `bytes memory` argument. No memory beyond scratch space is written, so the `memory-safe` annotation is valid.

### Input validation

`deployAndBroadcast` validates `networks.length == 0` (line 233). `deployZoltu` validates the call result, zero-address, and empty-code conditions (line 76). `deployToNetworks` verifies the deployed address and code hash post-deployment (lines 191-197). See finding A01-1 regarding `deployToNetworks` and `checkDependencies` lacking their own empty-networks guard.

### Reentrancy and state consistency

Not applicable. This is a library of `internal` functions used in Foundry scripts. There are no external entry points, no state variables, and no callbacks. The `call` on line 73 targets the Zoltu factory which executes CREATE and returns; it does not call back into the deployer.

### Arithmetic safety

No arithmetic operations beyond loop counters incrementing from 0 to `networks.length` and `dependencies.length`. Overflow is not possible for realistic array lengths under Solidity 0.8.x checked arithmetic.

### Error handling

All error paths use custom errors (`DeployFailed`, `MissingDependency`, `UnexpectedDeployedAddress`, `UnexpectedDeployedCodeHash`, `DependencyChanged`, `NoNetworks`). No string reverts or `require` statements found.

### Cryptographic issues

The library relies on `codehash` (EXTCODEHASH opcode, keccak256 of runtime bytecode) for integrity verification. This is the standard EVM mechanism and is not vulnerable to known attacks.

### Resource management

Fork creation via `vm.createSelectFork` is a Foundry cheatcode. Fork IDs are obtained but intentionally unused (suppressed with `(forkId);` on lines 110 and 159). Each fork remains active in Foundry's state until the script ends. This is standard Foundry usage with no leak risk.

### Bytecode hash verification

`ZOLTU_FACTORY_CODEHASH` (line 40) is checked against the on-chain `codehash` in both `checkDependencies` (line 119) and `deployToNetworks` (line 163). `ZOLTU_FACTORY_BYTECODE` (line 43) is used only in `etchZoltuFactory` for local test environments. Consistency between `ZOLTU_FACTORY_BYTECODE` and `ZOLTU_FACTORY_CODEHASH` is verified by existing tests (`testZoltuFactoryBytecodeMatchesOnChain` and `testEtchZoltuFactory`).

## Findings

### A01-1 [LOW] `deployToNetworks` and `checkDependencies` lack empty-networks guard

**Location:** `src/lib/LibRainDeploy.sol`:102, `src/lib/LibRainDeploy.sol`:145

**Description:**
`deployAndBroadcast` (line 233) reverts with `NoNetworks()` when `networks.length == 0`, but neither `checkDependencies` nor `deployToNetworks` performs this check. Both are `internal` functions that could be called directly by consuming contracts that do not route through `deployAndBroadcast`.

If `deployToNetworks` is called with an empty `networks` array, the for-loop on line 156 is skipped entirely and `deployedAddress` defaults to `address(0)`, which is returned as a successful result. A consumer relying on the returned address would proceed with `address(0)` as if it were a valid deployment.

Similarly, `checkDependencies` with an empty array silently succeeds, recording no dependency hashes, which would cause `deployToNetworks` to accept any codehash for dependencies (since the mapping returns `bytes32(0)` for unset keys -- though this would then fail because no real contract has codehash `bytes32(0)`).

**Impact:** A consuming contract that calls `deployToNetworks` directly with an empty networks array receives `address(0)` as a valid deployed address. Defense-in-depth is weakened by not validating at each function boundary.

---

No CRITICAL, HIGH, or MEDIUM findings identified.
