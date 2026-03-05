# Pass 5: Correctness / Intent Verification -- LibRainDeploy.sol

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

## Correctness Verification Summary

### `deployZoltu` Assembly Analysis

The `call` opcode on line 53:
```
call(gas(), zoltuFactory, 0, add(creationCode, 0x20), mload(creationCode), 12, 20)
```

Arguments verified:
- **gas**: `gas()` -- forwards all remaining gas. Correct.
- **addr**: `zoltuFactory` -- local copy of `ZOLTU_FACTORY`. Correct.
- **value**: `0` -- no ETH sent. Correct (Zoltu factory uses `callvalue()` in its `create2`, so zero is intentional).
- **argsOffset**: `add(creationCode, 0x20)` -- skips the 32-byte length prefix of `bytes memory`. Correct.
- **argsLength**: `mload(creationCode)` -- reads the length stored at the start of the `bytes memory`. Correct.
- **retOffset**: `12` -- return data written starting at memory byte 12. Correct (see below).
- **retSize**: `20` -- copies 20 bytes of return data. Correct (matches Zoltu factory's `return(12, 20)`).

**Return data handling:** The Zoltu deterministic deployment proxy's Yul source (`return(12, 20)`) returns exactly 20 raw bytes containing the deployed address. The code writes these 20 bytes to memory[12..31]. Combined with the prior `mstore(0, 0)` that zeroed bytes 0-31, `mload(0)` reads a 32-byte word with bytes 0-11 as zero padding and bytes 12-31 as the address -- exactly the right-aligned format Solidity uses for `address` types. **Correct.**

**`memory-safe` annotation:** The assembly only accesses scratch space (memory 0x00-0x3f) for writes and reads Solidity-allocated memory (`creationCode`) without modification. This complies with Solidity's memory-safety rules. **Correct.**

### `ZOLTU_FACTORY` Constant

`0x7A0D94F55792C434d74a40883C6ed8545E406D12` matches the canonical Zoltu deterministic deployment proxy address. **Correct.**

### `supportedNetworks`

Returns exactly 4 networks (`ARBITRUM_ONE`, `BASE`, `FLARE`, `POLYGON`) using the declared string constants. The array size (4) matches the number of assignments. **Correct.**

### `deployAndBroadcastToSupportedNetworks` -- Dependency Check

Lines 98-115: The first loop iterates all networks, forks each, and checks `code.length` for both `ZOLTU_FACTORY` and every entry in `dependencies`. If any check fails, `MissingDependency` is thrown immediately. No deployment occurs until all networks pass all checks. **Correct.**

### `deployAndBroadcastToSupportedNetworks` -- Idempotent Skip (Line 123)

`expectedAddress.code.length == 0` is evaluated against the current fork (set on line 120). If code exists, deployment is skipped and `deployedAddress` is set to `expectedAddress`. The subsequent code hash check (line 135) still runs, ensuring the existing code matches expectations. **Correct.**

### `deployAndBroadcastToSupportedNetworks` -- Code Hash Verification (Line 135)

`deployedAddress.codehash` returns the keccak256 of the runtime code per EIP-1052. Compared against `expectedCodeHash`. Runs on both the deploy and skip paths. **Correct.**

### `vm.startBroadcast` / `vm.stopBroadcast` Pairing

`vm.startBroadcast(deployer)` is called on line 122 and `vm.stopBroadcast()` on line 138 within each loop iteration. On revert paths (lines 132, 136, or via `deployZoltu` line 61), `vm.stopBroadcast()` is not reached. However, since the function is `internal`, reverts always propagate to the caller -- Foundry terminates the script and cleans up broadcast state. There is no code path where broadcast remains active after the function returns normally without calling `vm.stopBroadcast()`. **Correct.**

### Error Names vs Triggers

| Error | Trigger Condition | Match? |
|-------|-------------------|--------|
| `DeployFailed` | `!success \|\| deployedAddress == address(0) \|\| deployedAddress.code.length == 0` (line 56) | Yes -- actual deploy failure |
| `MissingDependency` | `ZOLTU_FACTORY.code.length == 0` (line 105) or `dependencies[j].code.length == 0` (line 111) | Yes -- dependency actually missing |
| `UnexpectedDeployedAddress` | `deployedAddress != expectedAddress` (line 131) | Yes -- address mismatch |
| `UnexpectedDeployedCodeHash` | `expectedCodeHash != deployedAddress.codehash` (line 135) | Yes -- hash mismatch |

All error names accurately describe their trigger conditions. **Correct.**

## Findings

### A01-1 [LOW] Function name `deployAndBroadcastToSupportedNetworks` implies restriction to supported networks but accepts arbitrary networks

**Location:** Line 83 (function declaration), line 85 (parameter `string[] memory networks`)

**Description:**
The function name contains "SupportedNetworks" which creates the expectation that deployment targets are constrained to the networks returned by `supportedNetworks()`. However, the function accepts an arbitrary `string[] memory networks` parameter with no validation that the provided networks are actually in the supported set.

A caller can pass any network names -- including networks not in the supported list, a subset, a single network, or even duplicates. The function will attempt to deploy to whatever networks are provided without checking against `supportedNetworks()`.

This is an intent mismatch: the name claims a restriction ("SupportedNetworks") that the implementation does not enforce. Prior passes flagged the NatSpec description mismatch (Pass 3, A01-2), but the function name itself is the primary source of the misleading intent signal.

This could lead a developer to assume the function inherently restricts deployment targets, when in fact the restriction must be applied by the caller. If a caller passes an incorrect network name (e.g., a typo like `"baes"` instead of `"base"`), the function would proceed and fail at `vm.createSelectFork` rather than at a validation step with a clear error message.
