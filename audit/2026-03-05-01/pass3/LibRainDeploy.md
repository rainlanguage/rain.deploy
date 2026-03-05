# Pass 3: Documentation -- LibRainDeploy.sol

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

## Documentation Checklist

| Item | Has `@title`? | Has `@param` for all? | Has `@return` for all? | Description accurate? |
|------|---------------|------------------------|------------------------|-----------------------|
| Library `LibRainDeploy` | Yes (line 8) | N/A | N/A | See A01-2 |
| `deployZoltu` | N/A | Yes (1/1) | Yes (1/1) | Yes |
| `supportedNetworks` | N/A | Yes (0/0) | Yes (1/1) | Yes |
| `deployAndBroadcastToSupportedNetworks` | N/A | **No (3/8)** | Yes (1/1) | **No** |
| Error `DeployFailed` | N/A | N/A | N/A | Yes |
| Error `MissingDependency` | N/A | N/A | N/A | Yes |
| Error `UnexpectedDeployedAddress` | N/A | N/A | N/A | Yes |
| Error `UnexpectedDeployedCodeHash` | N/A | N/A | N/A | Yes |
| Constant `ZOLTU_FACTORY` | N/A | N/A | N/A | Yes |
| Constant `ARBITRUM_ONE` | N/A | N/A | N/A | Yes |
| Constant `BASE` | N/A | N/A | N/A | Yes |
| Constant `FLARE` | N/A | N/A | N/A | Yes |
| Constant `POLYGON` | N/A | N/A | N/A | Yes |

## Findings

### A01-1 [LOW] `deployAndBroadcastToSupportedNetworks` is missing `@param` tags for 5 of 8 parameters

**Location:** Lines 76-82

**Description:**
The function `deployAndBroadcastToSupportedNetworks` accepts 8 parameters but only documents 3 of them via `@param` tags:

Documented:
- `@param vm` (line 79)
- `@param deployerPrivateKey` (line 80)
- `@param creationCode` (line 81)

Missing:
- `networks` (parameter on line 85) -- the list of network names to deploy to
- `contractPath` (parameter on line 88) -- used in the `forge verify-contract` log output
- `expectedAddress` (parameter on line 89) -- the expected deterministic address; also used to skip deployment if code already exists
- `expectedCodeHash` (parameter on line 90) -- used to verify the deployed bytecode
- `dependencies` (parameter on line 91) -- addresses that must have code on each network before deployment proceeds

This is over half the function's parameters left undocumented. For a deployment function that handles private keys and cross-chain orchestration, callers need clear documentation of every parameter's purpose and expectations.

### A01-2 [LOW] NatSpec description for `deployAndBroadcastToSupportedNetworks` is inaccurate

**Location:** Lines 76-78

**Description:**
The NatSpec reads:

```
/// Deploys the given creation code via the Zoltu factory to all supported
/// networks, broadcasting the deployment transaction using the given private
/// key.
```

This says "to all supported networks", but the function does not call `supportedNetworks()` internally. It deploys to whatever `networks` array is passed by the caller (line 85). The caller may pass a subset of supported networks, a single network, or even networks not in the "supported" list.

The description should reflect that it deploys to the provided `networks` array, not implicitly "all supported networks."

### A01-3 [LOW] `@return` description for `deployAndBroadcastToSupportedNetworks` is misleading

**Location:** Line 82

**Description:**
The `@return` tag reads:

```
/// @return deployedAddress The address of the deployed contract on the last network.
```

The phrase "on the last network" implies the address may differ per network, but Zoltu factory deployments are deterministic -- the same creation code always produces the same address on every chain. The function enforces this by checking `deployedAddress == expectedAddress` on every iteration (line 131-133).

A more accurate description would state that this is the deterministic deployment address, verified to match `expectedAddress` on all networks.
