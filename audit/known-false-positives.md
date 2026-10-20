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
