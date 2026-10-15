# Known false positives

## Equivalent mutant: `suiteIndex` returning the last match instead of the first

`src/abstract/RainDeploySuitesBase.sol`, `suiteIndex`. Returning the last index
whose key matches instead of the first changes nothing while keys are unique,
because then at most one index matches. `allSuites()` refuses a duplicate key
with `DuplicateDeploySuite`: `suiteByName` searches `allSuites()` itself, and
the released suites `resolveReleased` searches are among those
`testSnapshotInternallyConsistent` holds to `allSuites()`.

## Equivalent mutant: `doubled` copying from index 1 instead of 0

`src/lib/LibRainDeployBeacon.sol`, `doubled`. Index 0 is always `later`, read
before anything else is reached. A record names only records that exist when it
is written (`PrerequisiteNotApplied`) and is never rewritten
(`MigrationAlreadyApplied`), so no walk reaches `later` again and dropping its
record and key changes nothing.
