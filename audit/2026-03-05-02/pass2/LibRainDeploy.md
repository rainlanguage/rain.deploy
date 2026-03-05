# Pass 2: Test Coverage -- A01 -- LibRainDeploy

**Agent:** A01
**Source file:** `src/lib/LibRainDeploy.sol` (253 lines)
**Test file:** `test/src/lib/LibRainDeploy.t.sol` (300 lines)

## Evidence of Thorough Reading

### Source: `LibRainDeploy` (library, line 14)

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

### Test: `LibRainDeployTest` (contract, line 19) with `MockDeployable` (line 10)

**Tests:**
| Test | Line |
|------|------|
| `testSupportedNetworks()` | 24 |
| `testZoltuFactoryCodehash()` | 35 |
| `testZoltuFactoryBytecode()` | 42 |
| `testEtchZoltuFactory()` | 49 |
| `testNoNetworksReverts()` | 89 |
| `testDeployZoltu()` | 145 |
| `testDeployZoltuRevertsNoFactory()` | 153 |
| `testUnexpectedDeployedAddressReverts()` | 162 |
| `testUnexpectedDeployedCodeHashReverts()` | 181 |
| `testDeployAndBroadcastHappyPath()` | 202 |
| `testCheckDependenciesRecordsCodehash()` | 220 |
| `testMissingDependencyReverts()` | 233 |
| `testDependencyChangedCodehashReverts()` | 250 |
| `testDependencyChangedCodeLengthReverts()` | 277 |

**External wrappers:**
| Wrapper | Line |
|---------|------|
| `externalDeployAndBroadcast(...)` | 66 |
| `externalCheckDependencies(...)` | 100 |
| `externalDeployToNetworks(...)` | 114 |
| `externalDeployZoltu(...)` | 139 |

**Mock contracts:**
| Contract | Line | Purpose |
|----------|------|---------|
| `MockDeployable` | 10 | Minimal contract with `value = 42` for Zoltu deployment tests |

**Storage:**
| Variable | Line | Type |
|----------|------|------|
| `sDepCodeHashes` | 20 | `mapping(string => mapping(address => bytes32))` |

### Indirect Coverage Search

Grepping for all source function names and error names across `/test` found references only in `test/src/lib/LibRainDeploy.t.sol`. No other test files reference `LibRainDeploy`.

## Coverage Matrix

| Source Function / Error Path | Test(s) | Covered? |
|------------------------------|---------|----------|
| `etchZoltuFactory` happy path | `testEtchZoltuFactory` | YES |
| `deployZoltu` happy path | `testDeployZoltu` | YES |
| `deployZoltu` -- `DeployFailed` (success=true, addr=0) | `testDeployZoltuRevertsNoFactory` | YES |
| `deployZoltu` -- `DeployFailed` (success=false) | *none* | **NO** |
| `supportedNetworks` | `testSupportedNetworks` | YES |
| `checkDependencies` happy path | `testCheckDependenciesRecordsCodehash` | YES |
| `checkDependencies` -- `MissingDependency` (user dep) | `testMissingDependencyReverts` | YES |
| `checkDependencies` -- `MissingDependency` (Zoltu factory) | *none* | **NO** |
| `checkDependencies` -- `DependencyChanged` (Zoltu codehash) | *none* | **NO** |
| `deployToNetworks` happy path | `testDeployAndBroadcastHappyPath` (indirectly) | YES |
| `deployToNetworks` -- `UnexpectedDeployedAddress` | `testUnexpectedDeployedAddressReverts` | YES |
| `deployToNetworks` -- `UnexpectedDeployedCodeHash` | `testUnexpectedDeployedCodeHashReverts` | YES |
| `deployToNetworks` -- `DependencyChanged` (dep codehash) | `testDependencyChangedCodehashReverts` | YES |
| `deployToNetworks` -- `DependencyChanged` (dep code.length=0) | `testDependencyChangedCodeLengthReverts` | YES |
| `deployToNetworks` -- `DependencyChanged` (Zoltu factory) | *none* | **NO** |
| `deployToNetworks` -- skip deployment (code already exists) | *none* | **NO** |
| `deployAndBroadcast` happy path | `testDeployAndBroadcastHappyPath` | YES |
| `deployAndBroadcast` -- `NoNetworks` | `testNoNetworksReverts` | YES |
| Constants verified on-chain | `testZoltuFactoryCodehash`, `testZoltuFactoryBytecode` | YES |

## Findings

### P2-A01-1 [MEDIUM] `checkDependencies` -- `MissingDependency` for Zoltu factory is untested

**Location:** `src/lib/LibRainDeploy.sol`:116-118

**Description:**
Lines 116-118 revert with `MissingDependency(networks[i], ZOLTU_FACTORY)` when the Zoltu factory has no code on a network. No test exercises this path. The existing `testMissingDependencyReverts` only tests a user-provided dependency (`address(0xdead)`) missing code, not the Zoltu factory itself being absent.

This is a distinct code path from any dependency check: the Zoltu factory check happens before the dependency loop (lines 116-121 vs. lines 123-129), and uses a hardcoded address constant.

---

### P2-A01-2 [MEDIUM] `checkDependencies` -- `DependencyChanged` for Zoltu factory codehash mismatch is untested

**Location:** `src/lib/LibRainDeploy.sol`:119-121

**Description:**
Lines 119-121 revert with `DependencyChanged(networks[i], ZOLTU_FACTORY, ZOLTU_FACTORY_CODEHASH, ZOLTU_FACTORY.codehash)` when the Zoltu factory exists but has a wrong codehash. No test exercises this path through `checkDependencies`.

The existing `testDependencyChangedCodehashReverts` triggers the analogous check in `deployToNetworks` (lines 163-165) for a user dependency, not for the Zoltu factory, and not via `checkDependencies`.

---

### P2-A01-3 [MEDIUM] `deployToNetworks` -- `DependencyChanged` for Zoltu factory is untested

**Location:** `src/lib/LibRainDeploy.sol`:163-165

**Description:**
Lines 163-165 revert with `DependencyChanged(...)` when the Zoltu factory has no code or a wrong codehash at deploy time. No test exercises this specific path. The existing `testDependencyChangedCodehashReverts` tests a user *dependency* codehash mismatch (lines 168-180), not the Zoltu factory re-verification.

There are two sub-conditions:
1. `ZOLTU_FACTORY.code.length == 0` -- factory destroyed between check and deploy
2. `ZOLTU_FACTORY.codehash != ZOLTU_FACTORY_CODEHASH` -- factory replaced between check and deploy

Neither is tested.

---

### P2-A01-4 [LOW] `deployZoltu` -- `DeployFailed` with `success=false` is untested

**Location:** `src/lib/LibRainDeploy.sol`:76

**Description:**
The revert condition on line 76 includes `!success`, covering the case where the low-level `call` to the Zoltu factory itself reverts (e.g., creation code with a reverting constructor). The existing `testDeployZoltuRevertsNoFactory` only triggers `DeployFailed(true, address(0))` by etching the factory to empty bytecode, which makes the call succeed (no code = no revert) but return zero. No test triggers the `success=false` branch where the inner CREATE causes the factory call to revert.

---

### P2-A01-5 [LOW] `deployToNetworks` -- skip-deployment path is untested

**Location:** `src/lib/LibRainDeploy.sol`:183-189

**Description:**
When `expectedAddress.code.length > 0` (line 183), deployment is skipped and `deployedAddress` is set to `expectedAddress` (line 188). This "already deployed" branch is never exercised by any test. All existing deploy tests start from a clean state where the expected address has no code.

This path has production relevance: when re-running deployments across multiple networks, some networks may already have the contract. If the skip logic has a bug (e.g., not verifying the codehash of the pre-existing code), it would go undetected.
