# Known false positives

Mutants that survive an offline run (no RPC URLs) because the only lines they
touch are reached by fork tests alone. Each is killed by the named fork test
when the `[rpc_endpoints]` aliases resolve.

| Mutant                                                        | Line                                                                                     | Killed with RPC by                                                                                                                       |
| ------------------------------------------------------------- | ---------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| D10: `checkResolvedValuesOnForks` selects only the first fork | `src/lib/LibRainDeploy.sol` `vm.selectFork(forkIds[i]);` in `checkResolvedValuesOnForks` | `LibRainDeployResolvedValuesTest.testCheckResolvedValuesOnForksReachesEveryFork`, `testCheckResolvedValuesOnNetworksReachesEveryNetwork` |

## Unobservable or equivalent

Mutants no test can kill. A `console2.log` call is answered by forge itself and
never reaches the EVM: `vm.recordLogs` does not record it and `vm.expectCall` on
the console address sees zero calls. What each log prints is pinned instead as
the value the function returns.

| Mutant                                                     | Line                                                                                                                                                | Why it cannot be killed                                                                                                                                                         |
| ---------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| N10: required-nowhere scan `break` removed                 | `src/abstract/RainDeployVerifyChain.sol` `break;` after `requiredSomewhere = true;`                                                                 | Equivalent: the remaining iterations only set `requiredSomewhere` to true again.                                                                                                |
| N11: chain skip log removed                                | `src/abstract/RainDeployVerifyChain.sol` `console2.log("Not required on network:", ...)`                                                            | Console output. The skip itself is pinned by `RainDeployVerifyChainNotRequiredLocalTest.testNotRequiredNetworksAreSkipped`.                                                     |
| N13 (R26): `registerOnNetworks` inputs log removed         | `src/lib/LibConfigRegistryRegister.sol` `console2.log(record);` in `registerOnNetworks`                                                             | Console output. The record is returned and pinned by `LibConfigRegistryRegisterOnForksTest.testRegisterOnNetworksBindsEverySelected`.                                           |
| N14: `registerOnSelectedChain` network log removed         | `src/lib/LibConfigRegistryRegister.sol` `console2.log(record);` in `registerOnSelectedChain`                                                        | Console output. The record is returned and pinned by `LibConfigRegistryRegisterTest.testRegisterUnbound`, `testRegisterRebinds`, `testRegisterSkipsSameBinding`.                |
| M32: chain suite log removed                               | `src/abstract/RainDeployVerifyChain.sol` `console2.log("Checking suite on network:", ...)` in `checkSuiteOnNetwork`                                 | Console output. The check it announces is pinned by `RainDeployVerifyChainNotRequiredLocalTest.testRequiredSuiteIsStillCheckedEverywhere`.                                      |
| R07: `registerOnNetworks` forwards `sender` as `authority` | `src/lib/LibConfigRegistryRegister.sol` `registerOnForks(vm, selected, declared, forkIds, sender, authority, name, value);` in `registerOnNetworks` | Equivalent: `checkInputs` has already refused `sender != authority`.                                                                                                            |
| M64: seated-state revert-failure names no suite            | `src/abstract/RainDeployVerifyBase.sol` `revert DerivationSnapshotRevertFailed(resolved.suite.suite, snapshotId);` in `checkSeatedState`            | Unreachable: `vm.revertToState` of a snapshot taken in the same call, with no revert or other snapshot between, returns true, so the guard never fires.                         |
| G03: `deployStep` final revert removed                     | `src/lib/LibRainDeployMechanism.sol` `revert UnknownDeployMechanism(uint8(suite.mechanism));` in `deployStep`                                       | Unreachable: every `DeployMechanism` member returns before it, and an out-of-range value panics 0x21 on read before reaching it. It guards a member added later without an arm. |
| G05: `mechanismName` revert becomes an empty return        | `src/lib/LibRainDeploySnapshot.sol` `revert UnknownDeployMechanism(uint8(kind));` in `mechanismName`                                                | Unreachable for the same reason as G03.                                                                                                                                         |
| B44: seat-check revert-failure arguments changed           | `src/abstract/RainDeployBroadcast.sol` `revert DerivationSnapshotRevertFailed(suite.suite, snapshotId);` in `checkSeatsNoDeployKey`                 | Unreachable: `vm.revertToState` of a snapshot taken in the same loop iteration, with no revert or other snapshot between, returns true, so the guard never fires.               |

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
- `LibConfigRegistryRegister`'s sender and authority after `checkInputs`'
  `checkSender(sender, authority)`, which reverts `SenderNotAuthority` unless
  the two are equal, so either can stand for the other on every later line:
  `checkInputs` describing `sender` in place of `authority` (S07),
  `registerOnNetworks` passing `authority` as the sender to `registerOnForks`
  (R16), and `registerOnForks` passing `authority` as the sender to
  `registerOnSelectedChain` (R13). R07, passing `sender` as the authority, is in
  the table above. These are known false positives of the `SenderNotAuthority`
  check, which stays: a mutant it makes equivalent is recorded here, never
  killed by deleting the check.
