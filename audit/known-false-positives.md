# Known false positives

## Equivalent mutant: `suiteIndex` returning the last match instead of the first

`src/abstract/RainDeploySuitesBase.sol`, `suiteIndex`. Returning the last index
whose key matches instead of the first changes nothing while keys are unique,
because then at most one index matches. `allSuites()` refuses a duplicate key
with `DuplicateDeploySuite`: `suiteByName` searches `allSuites()` itself, and
the released suites `resolveReleased` searches are among those
`testSnapshotInternallyConsistent` holds to `allSuites()`.
