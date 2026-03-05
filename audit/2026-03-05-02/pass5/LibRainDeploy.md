# Pass 5 - Correctness / Intent Verification: LibRainDeploy

**Audit:** 2026-03-05-02
**Agent:** A01
**File:** `src/lib/LibRainDeploy.sol`
**Test file:** `test/src/lib/LibRainDeploy.t.sol`

---

## Evidence of Thorough Reading

### `src/lib/LibRainDeploy.sol`

**Library:** `LibRainDeploy` (line 14)

**Functions:**

| Function | Line |
|---|---|
| `etchZoltuFactory(Vm)` | 60 |
| `deployZoltu(bytes memory)` | 68 |
| `supportedNetworks()` | 87 |
| `checkDependencies(Vm, string[], address[], mapping)` | 102 |
| `deployToNetworks(Vm, string[], address, bytes, string, address, bytes32, address[], mapping)` | 145 |
| `deployAndBroadcast(Vm, string[], uint256, bytes, string, address, bytes32, address[], mapping)` | 222 |

**Errors:**

| Error | Line |
|---|---|
| `DeployFailed(bool success, address deployedAddress)` | 18 |
| `MissingDependency(string network, address dependency)` | 21 |
| `UnexpectedDeployedAddress(address expected, address actual)` | 24 |
| `UnexpectedDeployedCodeHash(bytes32 expected, bytes32 actual)` | 27 |
| `DependencyChanged(string network, address dependency, bytes32 expectedCodeHash, bytes32 actualCodeHash)` | 31 |
| `NoNetworks()` | 34 |

**Constants:**

| Constant | Line | Value |
|---|---|---|
| `ZOLTU_FACTORY` | 37 | `0x7A0D94F55792C434d74a40883C6ed8545E406D12` |
| `ZOLTU_FACTORY_CODEHASH` | 40 | `0x5acaad953250bec20933f7c72a25bb03bfa54767ebd3a750396276512c46a79c` |
| `ZOLTU_FACTORY_BYTECODE` | 43 | `hex"6000368182..."` (30 bytes) |
| `ARBITRUM_ONE` | 46 | `"arbitrum"` |
| `BASE` | 49 | `"base"` |
| `FLARE` | 52 | `"flare"` |
| `POLYGON` | 55 | `"polygon"` |

### `test/src/lib/LibRainDeploy.t.sol`

**Contracts:**
- `MockDeployable` (line 10) - minimal deployment target with `uint256 public value = 42`
- `LibRainDeployTest is Test` (line 19)

**State:**
- `sDepCodeHashes` (line 20) - `mapping(string => mapping(address => bytes32))`

**Functions (test contract):**

| Function | Line |
|---|---|
| `testSupportedNetworks()` | 24 |
| `testZoltuFactoryCodehash()` | 35 |
| `testZoltuFactoryBytecode()` | 42 |
| `testEtchZoltuFactory()` | 49 |
| `externalDeployAndBroadcast(...)` | 66 |
| `testNoNetworksReverts()` | 89 |
| `externalCheckDependencies(...)` | 100 |
| `externalDeployToNetworks(...)` | 114 |
| `externalDeployZoltu(...)` | 139 |
| `testDeployZoltu()` | 145 |
| `testDeployZoltuRevertsNoFactory()` | 153 |
| `testUnexpectedDeployedAddressReverts()` | 162 |
| `testUnexpectedDeployedCodeHashReverts()` | 181 |
| `testDeployAndBroadcastHappyPath()` | 202 |
| `testCheckDependenciesRecordsCodehash()` | 220 |
| `testMissingDependencyReverts()` | 233 |
| `testDependencyChangedCodehashReverts()` | 250 |
| `testDependencyChangedCodeLengthReverts()` | 277 |

---

## Verification Results

### Constants and Magic Numbers

1. **`ZOLTU_FACTORY_CODEHASH`**: Independently computed `keccak256(ZOLTU_FACTORY_BYTECODE)` = `0x5acaad953250bec20933f7c72a25bb03bfa54767ebd3a750396276512c46a79c`. Matches the constant at line 40. **Correct.**

2. **`ZOLTU_FACTORY_BYTECODE`**: Disassembled and traced the bytecode. It implements:
   - Copy all calldata to memory at offset 0
   - CREATE2 with salt=0, value=callvalue, creation code from memory
   - On failure: REVERT with empty data
   - On success: MSTORE address at offset 0, RETURN(offset=12, size=20) returning the 20-byte address
   This is the standard Zoltu deterministic deployment proxy pattern. **Correct.**

3. **Empty account codehash** `0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470` used in `testDependencyChangedCodeLengthReverts` (line 295): Independently computed `keccak256("")` matches. This is the codehash of an existing account with no code (not a non-existent account, which returns `bytes32(0)`). The test uses `address(0xdead)` on Arbitrum fork, which is expected to exist (have balance). **Correct.**

### Assembly Correctness (`deployZoltu`, lines 71-75)

Traced the assembly step by step:

- `mstore(0, 0)`: Zeroes scratch space `memory[0:32]`. **Correct.**
- `call(gas(), zoltuFactory, 0, add(creationCode, 0x20), mload(creationCode), 12, 20)`:
  - Input: `memory[creationCode+0x20]` for `mload(creationCode)` bytes (skips ABI length prefix, passes raw bytes). **Correct.**
  - Output: writes 20 bytes of return data to `memory[12:32]`. **Correct.**
- `mload(0)`: Reads `memory[0:32]` as `uint256`. Bytes 0-11 are zero (from `mstore(0,0)`), bytes 12-31 contain the 20-byte address. The address is right-aligned in the 32-byte word, which is the correct representation for Solidity's `address` type. **Correct.**
- `memory-safe` annotation: All memory access is within the scratch space `[0x00, 0x40)`. The `creationCode` read is from Solidity-allocated memory. **Correct.**

### NatSpec vs Implementation

- `deployZoltu`: NatSpec says "Deploys the given creation code via the Zoltu factory. Handles the return data and errors appropriately." Implementation matches. **Correct.**
- `checkDependencies`: NatSpec says "Checks that the Zoltu factory and all dependencies have code on each network. Records each dependency's codehash in the provided mapping." Implementation matches. **Correct.**
- `supportedNetworks`: NatSpec says "Returns the list of networks currently supported by Rain deployments." Implementation returns 4 networks. **Correct.**
- `etchZoltuFactory`: NatSpec says "Etches the Zoltu factory bytecode into the factory address." Implementation calls `vm.etch`. **Correct.**
- `deployAndBroadcast`: NatSpec accurately describes the full flow. **Correct.**
- `deployToNetworks`: NatSpec says "Verifies that dependencies have not changed since the check phase, then deploys to each network via the Zoltu factory." See INFO finding below.

### Error Conditions vs Triggers

- `DeployFailed`: Triggered when `!success || deployedAddress == address(0) || deployedAddress.code.length == 0` (line 76). Matches the error description "deployment via Zoltu factory fails". **Correct.**
- `MissingDependency`: Triggered when `dependencies[j].code.length == 0` (line 125) or factory code missing (line 116-118). Matches description. **Correct.**
- `UnexpectedDeployedAddress`: Triggered when `deployedAddress != expectedAddress` (line 191). Matches description. **Correct.**
- `UnexpectedDeployedCodeHash`: Triggered when `expectedCodeHash != deployedAddress.codehash` (line 195). Matches description. **Correct.**
- `DependencyChanged`: Triggered when dependency codehash differs from recorded value (line 169-179) or factory codehash differs (line 163-165). Matches description. **Correct.**
- `NoNetworks`: Triggered when `networks.length == 0` (line 233). Matches description. **Correct.**

### Tests vs Claims

- `testSupportedNetworks`: Asserts 4 networks in correct order. **Matches claim.**
- `testZoltuFactoryCodehash`: Forks Arbitrum and asserts on-chain codehash matches constant. **Matches claim.**
- `testZoltuFactoryBytecode`: Forks Arbitrum and asserts on-chain bytecode matches constant. **Matches claim.**
- `testEtchZoltuFactory`: Verifies bytecode and codehash after etching. **Matches claim.**
- `testDeployZoltu`: Deploys MockDeployable via Zoltu on Arbitrum fork, asserts deterministic address `0xC24016f209562fc151e5Ab7F88694ED5775feb36`. **Matches claim.**
- `testDeployZoltuRevertsNoFactory`: Etches empty code at factory, expects `DeployFailed(true, address(0))`. When calling an empty account, EVM returns success with no data, so `deployedAddress` remains 0. **Matches claim.**
- `testNoNetworksReverts`: Empty array triggers `NoNetworks`. **Matches claim.**
- `testUnexpectedDeployedAddressReverts`: Passes wrong expected address, triggers `UnexpectedDeployedAddress`. **Matches claim.**
- `testUnexpectedDeployedCodeHashReverts`: Passes wrong expected codehash, triggers `UnexpectedDeployedCodeHash`. **Matches claim.**
- `testDeployAndBroadcastHappyPath`: Full end-to-end deploy, verifies correct address and codehash. **Matches claim.**
- `testCheckDependenciesRecordsCodehash`: Verifies storage mapping is populated. **Matches claim.**
- `testMissingDependencyReverts`: Uses `address(0xdead)` with no code, triggers `MissingDependency`. **Matches claim.**
- `testDependencyChangedCodehashReverts`: Pre-populates wrong codehash, triggers `DependencyChanged`. **Matches claim.**
- `testDependencyChangedCodeLengthReverts`: Pre-populates codehash for non-existent code at `0xdead`, triggers `DependencyChanged` with `keccak256("")` as actual codehash. **Matches claim.**

---

## Findings

### A01-1 [INFO] `deployToNetworks` NatSpec omits skip-if-already-deployed behavior

**Location:** `src/lib/LibRainDeploy.sol:133-134`

**Description:** The NatSpec for `deployToNetworks` says "Verifies that dependencies have not changed since the check phase, then deploys to each network via the Zoltu factory." However, the implementation (lines 183-189) skips deployment when `expectedAddress.code.length != 0` and returns the expected address directly. This skip-if-already-deployed behavior is documented in an inline comment (line 187) but not in the function-level NatSpec. A caller reading only the NatSpec would not know that the function is idempotent.

No fix file generated for INFO-level finding.
