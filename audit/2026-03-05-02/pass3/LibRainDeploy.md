# Pass 3 (Documentation) - LibRainDeploy.sol

**Agent:** A01
**File:** `src/lib/LibRainDeploy.sol`

## Evidence of Thorough Reading

**Library:** `LibRainDeploy` (line 14)

**Functions:**
1. `etchZoltuFactory(Vm vm)` -- line 60
2. `deployZoltu(bytes memory creationCode)` -- line 68
3. `supportedNetworks()` -- line 87
4. `checkDependencies(Vm, string[], address[], mapping)` -- line 102
5. `deployToNetworks(Vm, string[], address, bytes, string, address, bytes32, address[], mapping)` -- line 145
6. `deployAndBroadcast(Vm, string[], uint256, bytes, string, address, bytes32, address[], mapping)` -- line 222

**Errors:**
1. `DeployFailed(bool, address)` -- line 18
2. `MissingDependency(string, address)` -- line 21
3. `UnexpectedDeployedAddress(address, address)` -- line 24
4. `UnexpectedDeployedCodeHash(bytes32, bytes32)` -- line 27
5. `DependencyChanged(string, address, bytes32, bytes32)` -- line 31
6. `NoNetworks()` -- line 34

**Constants:**
1. `ZOLTU_FACTORY` (address) -- line 37
2. `ZOLTU_FACTORY_CODEHASH` (bytes32) -- line 40
3. `ZOLTU_FACTORY_BYTECODE` (bytes) -- line 43
4. `ARBITRUM_ONE` (string) -- line 46
5. `BASE` (string) -- line 49
6. `FLARE` (string) -- line 52
7. `POLYGON` (string) -- line 55

**Types:** None.

## Documentation Completeness

All 6 functions have NatSpec documentation with `@param` and `@return` tags.
All 6 errors have NatSpec documentation.
All 7 constants have NatSpec documentation.

## Findings

### A01-1: ZOLTU_FACTORY NatSpec calls it a "proxy" instead of "factory"

- **Severity:** LOW
- **Location:** `src/lib/LibRainDeploy.sol:36`
- **Description:** The NatSpec for the `ZOLTU_FACTORY` constant reads "Zoltu proxy is the same on every network." The word "proxy" is inaccurate -- the constant is named `ZOLTU_FACTORY`, the library title refers to it as a "factory", and the Zoltu contract is a deterministic deployment factory, not a proxy. The NatSpec should say "factory" instead of "proxy" to avoid confusion.

### A01-2: DependencyChanged NatSpec is narrower than actual usage

- **Severity:** LOW
- **Location:** `src/lib/LibRainDeploy.sol:29-31`
- **Description:** The NatSpec for `DependencyChanged` reads: "Thrown when a dependency's code hash or size changed between the dependency check and the deployment." This implies the error is only thrown during re-verification in `deployToNetworks`. However, the error is also thrown during the initial `checkDependencies` phase (line 120) when the Zoltu factory exists but has an unexpected codehash -- this is not "between the dependency check and the deployment" but during the check itself. The NatSpec should describe the error more broadly, e.g., "Thrown when a dependency's code hash does not match the expected value."

### A01-3: checkDependencies NatSpec understates Zoltu factory verification

- **Severity:** INFO
- **Location:** `src/lib/LibRainDeploy.sol:96-97`
- **Description:** The NatSpec for `checkDependencies` says "Checks that the Zoltu factory and all dependencies have code on each network." This understates what the function does for the Zoltu factory specifically: it also verifies the factory's codehash matches the expected `ZOLTU_FACTORY_CODEHASH` constant (line 119), not merely that code exists. A more complete description would be "Checks that the Zoltu factory has the expected codehash and all dependencies have code on each network."
