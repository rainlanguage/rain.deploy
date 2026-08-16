---
paths:
  - "src/**/*.sol"
  - "script/**/*.sol"
  - "test/**/*.sol"
  - "slither.config.json"
---

# `src/` holds the deploy machinery here, and that is a SCOPED exception

`src/abstract/RainDeploy*.sol` and `src/abstract/RegistryDeploySuites.sol` are
test and script infrastructure, and they live in `src/` rather than `test/`. Two
reasons, and the second is the one that matters:

1. `.soldeerignore` excludes `test/` from the published package, and a
   downstream repo has to import all of this — its `script/Deploy.sol` inherits
   `RainDeployBroadcast`, its test contracts inherit `RainDeployVerify*`. An
   abstract in a path the package excludes is unusable by every consumer.
2. **This repo's PRODUCT is the deployment process.** Machinery for deploying,
   and for verifying deployments, is not scaffolding that happens to live here —
   it is the thing the package exists to publish.

**Do not copy this into a consumer repo.** There, `src/` is the product —
tokens, vaults, a factory — and deploy verification is scaffolding around it, so
the usual convention stands unchanged: `test/src/**` mirrors `src/**`, and test
abstracts live under `test/`. The exception is earned by what this repo IS, and
a repo that merely USES this machinery has not earned it.

Even here it is scoped to the deploy/verify abstracts and the suite declaration.
`src/concrete/AddressRegistry.sol` and `src/concrete/MigrationRegistry.sol` are
ordinary deployed contracts, tested from `test/src/concrete/` exactly as the
convention requires.

## Why `slither.config.json` filters those files by name

They are the only `src/` files it filters out. They are inherited by test
contracts and never deployed, so slither's detectors — all of which are about
deployed-code risk — have nothing to say about them beyond an abstract not
implementing its own virtuals, a cheatcode called in a loop, and (because
slither skips `test/` and `script/`) an abstract's virtuals having no caller.

The filter matches those filenames exactly rather than the `src/abstract/`
prefix, so a file added there later — including a deployable one — is analysed
rather than silently exempted. Keep it that way when adding an abstract.
