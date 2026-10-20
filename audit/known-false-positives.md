# Known false positives

Mutants that survive an offline run (no RPC URLs) because the only lines they
touch are reached by fork tests alone. Each is killed by the named fork test
when the `[rpc_endpoints]` aliases resolve.

| Mutant                                                           | Line                                                                                                                            | Killed with RPC by                                                                                                                       |
| ---------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| R28: `registerOnForks` selects only the first fork               | `src/lib/LibConfigRegistryRegister.sol` `vm.selectFork(forkIds[i]);` in `registerOnForks`                                       | `LibConfigRegistryRegisterOnForksTest.testRegisterOnForksBindsOnEachFork`, `testRegisterOnEveryNetwork`                                  |
| R32: `registerOnNetworks` returns no fork ids                    | `src/lib/LibConfigRegistryRegister.sol` `return (forkIds, record);` in `registerOnNetworks`                                     | `LibConfigRegistryRegisterOnForksTest.testRegisterOnNetworksBindsEverySelected`, `RegisterConfigTest.testWiring`                         |
| `registerOnForks` registers every fork against the first network | `src/lib/LibConfigRegistryRegister.sol` `registerOnSelectedChain(vm, networks[i], sender, hashed, value);` in `registerOnForks` | `LibConfigRegistryRegisterOnForksTest.testRegisterOnForksBindsOnEachFork`                                                                |
| `registerOnNetworks` returns an empty record                     | `src/lib/LibConfigRegistryRegister.sol` `return (forkIds, record);` in `registerOnNetworks`                                     | `LibConfigRegistryRegisterOnForksTest.testRegisterOnNetworksBindsEverySelected`                                                          |
| `checkRegisteredOnForks` selects only the first fork             | `src/lib/LibConfigRegistryRegister.sol` `vm.selectFork(forkIds[i]);` in `checkRegisteredOnForks`                                | `LibConfigRegistryRegisterOnForksTest.testRegisterOnSubset`, `testRegisterOnEveryNetwork`                                                |
| S01: `RegisterConfig` ignores the networks env var               | `script/RegisterConfig.sol` `return vm.envOr(NETWORKS_VAR, ",", supportedNetworks());`                                          | `RegisterConfigTest.testWiring`                                                                                                          |
| S02: `RegisterConfig.run` signs as `tx.origin`                   | `script/RegisterConfig.sol` `vm, selectedNetworks(), supportedNetworks(), msg.sender, ...` in `run`                             | `RegisterConfigTest.testWiring`                                                                                                          |
| S03: `RegisterConfig.verify` ignores the selection               | `script/RegisterConfig.sol` `vm, selectedNetworks(), supportedNetworks(), vm.envString(NAME_VAR), ...` in `verify`              | `RegisterConfigTest.testWiring`                                                                                                          |
| D10: `checkResolvedValuesOnForks` selects only the first fork    | `src/lib/LibRainDeploy.sol` `vm.selectFork(forkIds[i]);` in `checkResolvedValuesOnForks`                                        | `LibRainDeployResolvedValuesTest.testCheckResolvedValuesOnForksReachesEveryFork`, `testCheckResolvedValuesOnNetworksReachesEveryNetwork` |

## Unobservable or equivalent

Mutants no test can kill. A `console2.log` call is answered by forge itself and
never reaches the EVM: `vm.recordLogs` does not record it and `vm.expectCall` on
the console address sees zero calls. What each log prints is pinned instead as
the value the function returns.

| Mutant                                             | Line                                                                                         | Why it cannot be killed                                                                                                                                          |
| -------------------------------------------------- | -------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| N10: required-nowhere scan `break` removed         | `src/abstract/RainDeployVerifyChain.sol` `break;` after `requiredSomewhere = true;`          | Equivalent: the remaining iterations only set `requiredSomewhere` to true again.                                                                                 |
| N11: chain skip log removed                        | `src/abstract/RainDeployVerifyChain.sol` `console2.log("Not required on network:", ...)`     | Console output. The skip itself is pinned by `RainDeployVerifyChainNotRequiredLocalTest.testNotRequiredNetworksAreSkipped`.                                      |
| N13 (R26): `registerOnNetworks` inputs log removed | `src/lib/LibConfigRegistryRegister.sol` `console2.log(record);` in `registerOnNetworks`      | Console output. The record is returned and pinned by `LibConfigRegistryRegisterOnForksTest.testRegisterOnNetworksBindsEverySelected`.                            |
| N14: `registerOnSelectedChain` network log removed | `src/lib/LibConfigRegistryRegister.sol` `console2.log(record);` in `registerOnSelectedChain` | Console output. The record is returned and pinned by `LibConfigRegistryRegisterTest.testRegisterUnbound`, `testRegisterRebinds`, `testRegisterSkipsSameBinding`. |

## Equivalent mutants

- `LibRainDeployMechanism.deployAndBroadcast`: `UnverifiableSource`'s entry
  address read from `deploys.derivedAddresses[0]` instead of
  `deploys.expectedAddresses[0]` (Z7). `deployStepToNetworks` refuses any
  network whose derived address differs from its expected one before the event,
  so the two are equal there.
- `LibRainDeploySnapshot.declarationValue`: the value read as
  `tokens[tokens.length - 1]` instead of `tokens[4]` (D7), or the final
  `tokens.length == 5` relaxed to `tokens.length <= 5` (T5G, D4). The count is
  already pinned to exactly 5 when the value is read, and a line reaching that
  check never holds fewer than five tokens: an unwrapped line holding exactly
  four takes the wrapped branch, and a wrapped line's four-space prefix splits
  into four empty tokens before its value.
- `RainDeployVerifySnapshotBase.declaredValue`'s and
  `LibRainDeploySnapshot.declarationAddress`'s `if (!readable)` guards (D08,
  N07): both guards removed as redundant.
- `RainDeployBroadcast.broadcastSuite` passes `candidateOf(frozen)`;
  `candidateOf(suite)` is equivalent (R03): `candidateOf` keys on `.suite`
  alone, which `withExtendedNetworks` preserves, and in the no-candidate
  fallback `withUnrecordedNetworks` appends nothing for either argument because
  `suite`'s networks are a subset of `frozen`'s.
