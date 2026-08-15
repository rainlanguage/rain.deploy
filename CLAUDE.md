<!-- SPDX-License-Identifier: LicenseRef-DCL-1.0 -->
<!-- SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd -->

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with
code in this repository.

## Project Overview

rain.deploy is a Solidity library for deploying Rain Protocol contracts via the
Zoltu deterministic deployment proxy to multiple EVM networks. It ensures
identical contract addresses across all supported chains (Arbitrum, Base, Base
Sepolia, Flare, Polygon) because the Zoltu proxy is deployed at the same address
on every chain and deploys with `CREATE2` over its calldata under a zero salt,
so a contract's address is a pure function of its creation code.

## Build & Development

This project uses **Foundry** (forge) for Solidity development and **Nix** for
environment management.

```bash
# Enter the nix dev shell (provides forge and all tooling)
nix develop

# Build
nix develop -c forge build

# Run tests
nix develop -c forge test -vvv

# Run a single test
nix develop -c forge test --match-test "testName"

# Static analysis / linting
nix develop -c slither .
nix develop -c forge fmt --check
nix develop -c rainix-sol-single-contract

# License/legal checks (REUSE compliance)
nix develop -c reuse lint
```

CI runs three matrix tasks: `rainix-sol-legal`, `rainix-sol-test`,
`rainix-sol-static`. Those are rainix reusable workflow names, not commands —
the block above is what they run.

A fourth workflow, `Manual sol artifacts`, is `workflow_dispatch` only and is
the on-chain deploy — nothing automatic ever broadcasts.

## RPC Configuration

Fork tests require RPC endpoints defined in `.env` (gitignored):

```bash
ARBITRUM_RPC_URL=https://arb1.arbitrum.io/rpc
BASE_RPC_URL=https://mainnet.base.org
BASE_SEPOLIA_RPC_URL=https://sepolia.base.org
FLARE_RPC_URL=https://flare-api.flare.network/ext/C/rpc
POLYGON_RPC_URL=https://polygon-bor-rpc.publicnode.com
```

All five are needed: `RainDeployVerifyChain` forks every network in
`supportedNetworks()`, so a missing or rate-limited endpoint fails it. Those
failures are `vm.createSelectFork` errors, distinct from the
`NotDeployedOnNetwork` a reachable network raises.

These are referenced in `foundry.toml` under `[rpc_endpoints]`.

## Architecture

**`src/lib/LibRainDeploy.sol`** — the deploy library:

- `etchZoltuFactory(Vm)` — etches the Zoltu factory bytecode at the factory
  address (for networks where it isn't deployed)
- `zoltuAddress(bytes creationCode)` — derives the address the factory deploys
  creation code to, without deploying
- `deployZoltu(bytes creationCode)` — deploys creation code via the Zoltu
  factory (`0x7A0D94F55792C434d74a40883C6ed8545E406D12`) using low-level `call`,
  returns the deployed address
- `supportedNetworks()` — returns the list of Rain-supported network names (used
  as foundry RPC config aliases)
- `isStartBlock(...)` — reads two adjacent blocks: true when the target has the
  expected code hash at a block and does not have it at the block before
- `findDeployBlock(...)` — binary searches a fork's history for a block where
  the target has the expected code hash and did not have it at the block before.
  Either one is "the block a contract first appears at" only where that code
  hash is monotone; against a target that held the hash, lost it and holds it
  again both answer about an appearance neither can identify
- `checkResolvedAddresses(...)` — asserts an already-deployed contract holds the
  addresses the deployment expected, on the currently selected fork, via
  consumer-supplied static reads
- `checkResolvedAddressesOnNetworks(...)` — runs that check on every network. It
  runs AFTER the deploy, against state the deployment has already settled, which
  is the only point at which such a check means anything: registry bindings are
  mutable, so a pre-deploy check would read a source that can change before the
  constructor that consumes it
- `deployToNetworks(...)` — forks each network; where the expected address is
  still empty it verifies the factory and dependencies on that fork, deploys via
  Zoltu and checks the address; the code hash is checked on every network,
  deployed here or already there
- `deployAndBroadcast(...)` — the main entry point: derives the deployer from a
  private key, then `deployToNetworks`

**`src/interface/IAddressRegistryV1.sol`** — the address registry interface: an
immutable root binds a `bytes32` name to an address (`register`), anyone reads a
bound name (`get`), and reading an unbound name reverts. Bindings are mutable so
an owning multisig can rotate without moving any consumer's deterministic
address; a consumer resolves once in its constructor and stores the answer, so a
re-binding never moves anything already deployed.

**`src/concrete/AddressRegistry.sol`** — the implementation. Two functions and
nothing else. `ADDRESS_REGISTRY_ROOT` is a compile-time constant and therefore
part of the creation code, so changing it moves the deterministic address and
code hash.

`ADDRESS_REGISTRY_ROOT` is `address(0)` during rollout. Nothing calls from the
zero address, so no name can be bound, and `get` reverts on every name that is
not bound — a registry compiled under this root answers every read with a revert
and can never answer one with an address. Setting a real root later is an
ordinary source change that moves the creation code, the address, the code hash
and the snapshot together.

**`src/lib/LibAddressRegistryDeploy.sol`** — those pins, derived from the
creation code this repo compiles under this repo's own settings and checked
against it by `RegistryDeploySnapshotTest`. GENERATED by `script/Build.sol`,
aliasing the rolling `src/generated/candidate/` snapshot.

**`src/interface/IMigrationRegistryV1.sol`** — the migration registry interface:
a writer applies one of its own migrations onto the head it believes its
namespace is at (`applyMigration`), anyone reads when a given writer applied a
given migration (`applied`), and anyone reads where that writer's namespace is
(`head`). There is no removal, no upgrade and no authority beyond the writer
over its own namespace.

It exists so a prod-state test decides what to assert by reading what happened
on chain rather than by reading the clock. Without it, a test that spans a
migration accepts either the pre- or the post-migration value until a hardcoded
deadline — which asserts nothing during the one window where it matters, and
red-lines CI on a date rather than on a fact once the deadline passes.

It is an INDEX, not proof. It says which invariant applies; codehash and
bytecode pins are what say the invariant holds. A multisig can act out of band,
so replacing the pins with this would trade a clock-guess for a bookkeeping
guess.

`applied` answers a TIMESTAMP, and zero still means "not applied". Time-shaped
invariants — a cliff, a rate change, a grace period — need the moment as well as
the fact, and a flag sends them back to the hardcoded date. Zero stays
unambiguous because `applyMigration` refuses to write in a block whose timestamp
is zero, rather than write a record that reads back as no record.

The HEAD is what makes a sequence ordered. `applyMigration` names the migration
it is applying onto and refuses to write unless the namespace is there, so a
skipped predecessor and an out-of-order concurrent dispatch both fail at apply
time instead of diverging silently; the applied migration becomes the new head.
`MIGRATION_HEAD_GENESIS` is the head of a namespace that has applied nothing,
and it is deliberately NOT zero: a zero genesis would make an uninitialised
predecessor constant a successful first application on any empty namespace,
which is the state of every chain not yet migrated. It is not a valid migration
id either, for the same reason a head must mean one thing.

The head does not replace the per-migration refusal. Re-applying a migration
whose successor has landed presents a matching head, and without
`MigrationAlreadyApplied` would drag the head backwards and overwrite the
original timestamp. One namespace on one chain is one linear sequence, so two
independent sequences want two writer accounts.

**`src/concrete/MigrationRegistry.sol`** — the implementation. Three functions
and nothing else, and — unlike `AddressRegistry` — nothing CONFIGURED at compile
time. `MIGRATION_HEAD_GENESIS` is a compile-time constant, but it is one value
for every consumer on every chain and names nobody, so it cannot fragment the
deterministic address the way a root would.

The namespace is `msg.sender`, which is the whole access control. A root would
have to be welded into the creation code, as `ADDRESS_REGISTRY_ROOT` is, and the
account that applies a migration is a different Safe, deployer or timelock for
every consumer and every chain — so one root would have to be all of them, and
baking each consumer's authority in would give each of them a different address
for what is meant to be one shared registry. Anyone may write, but only under
themselves, so a reader asking about an authority it already trusts is reading
something only that authority could have written.

With nothing to configure there is no rollout state in which it is inert: it
does its whole job the moment it exists on a chain, which is the opposite of
`AddressRegistry` under a zero root.

**`src/lib/LibMigrationRegistry.sol`** — the consumer surface: `applied`, `head`
and `applyMigration`, all verifying the registry's code hash first, exactly as
`LibAddressRegistry.resolve` does. There is deliberately no broadcast runner:
the dominant real migration shape is a Safe executing a bundle that never
broadcasts, and such a script appends `applyMigration` to the bundle it is
already emitting, which is what makes the record atomic with the migration.

**`src/lib/LibMigrationRegistryDeploy.sol`** — its pins, generated exactly as
`LibAddressRegistryDeploy` is.

### Generated snapshots, and the assertions that specify their shape

Every deploy snapshot in this repo is GENERATED and committed. There is no
hand-maintained hex anywhere: `src/generated/candidate/` holds one deploy record
per deployed contract — `AddressRegistry.sol` and `MigrationRegistry.sol` — from
`forge script script/Build.sol`.

`script/Build.sol` declares those contracts ONCE, in `generatedContracts()`, and
the regeneration, both lib writers and the freeze all read that list. A contract
added to it is generated, aliased, released and frozen together. That matters
most for the freeze: a contract regenerated but absent from the names `freeze`
is given is a contract silently missing from the release, and a tag that never
held it has nothing missing from it for anything downstream to notice.

A compiler or optimiser change is therefore "run the script, commit". Never
hand-edit a generated file.

`src/generated/<tag>/` directories are the FROZEN record: what each release
deployed, written once by `cutRelease()` and never again. That tree is the only
description of what this repo has released that cannot fall behind, which is why
`RainDeployVerifySnapshot` checks the generated `releasedSuites()` against it.
`LibRainDeploySnapshot.frozenSnapshotPaths` is the walk: every file inside a
release-tag directory, where a release tag is exactly what `tagForVersion`
produces — so `candidate/`, a scratch directory and a `0_1_7-rc1` nobody could
have frozen all fall out under the same rule, and there is no name to remember
to exclude.

**`GeneratedSnapshotShapeTest` is the specification of the shape.** It asserts
named properties against the compiler's AST — not against a second reference
file, so there is no question of that file's provenance, and not against source
text, so formatting cannot affect it:

1. exactly four constants, in order: `bytes32 BYTECODE_HASH`,
   `address DEPLOYED_ADDRESS`, `bytes CREATION_CODE`, `bytes RUNTIME_CODE`
2. every declaration is `constant`
3. no `ImportDirective` — a snapshot is read by repos that do not have the
   contract it describes, which is the whole reason a frozen release stays
   verifiable after its source has changed or gone
4. no `ContractDefinition` — it is a record, not code
5. the generated-file header is present

Values are deliberately not asserted: a solc change moves every literal without
changing anything the shape test is about, and a wrong literal is caught
immediately by the group 1 derivation checks in `RainDeployVerifySnapshot`.

`ast = true` in `foundry.toml` is what puts the AST in the artifacts a plain
`forge test` produces.

### `src/` holds the deploy machinery here. That is a SCOPED EXCEPTION.

`src/abstract/RainDeploy*.sol` are test and script infrastructure, and they live
in `src/` rather than `test/`. Two reasons, and the second is the one that
matters:

1. `.soldeerignore` excludes `test/` from the published package, and a
   downstream repo has to import all of this — its `script/Deploy.sol` inherits
   `RainDeployBroadcast`, its test contracts inherit `RainDeployVerify*`. An
   abstract in a path the package excludes is unusable by every consumer.
2. **This repo's PRODUCT is the deployment process.** Machinery for deploying
   and for verifying deployments is not scaffolding that happens to live here —
   it is the thing the package exists to publish. So `src/` is where it belongs.

**Do not copy this into a consumer repo.** There, `src/` is the product —
tokens, vaults, a factory — and deploy verification is scaffolding around it, so
the usual convention stands unchanged: `test/src/**` mirrors `src/**`, and test
abstracts live under `test/`. The exception is earned by what this repo IS, and
a repo that merely USES this machinery has not earned it.

The exception is scoped to the deploy/verify abstracts and the suite
declaration. `src/concrete/AddressRegistry.sol` and
`src/concrete/MigrationRegistry.sol` are ordinary deployed contracts, tested
from `test/src/concrete/` exactly as the convention requires.

**`src/abstract/RainDeploySuitesBase.sol`** — the ONE declaration of what a repo
deploys: per suite, a key, the creation code, the recorded address/code
hash/runtime code, an artifact path, and dependencies.

Both sides read it. `RainDeployBroadcast` deploys from it and
`RainDeployVerify*` verify against it, so "the deploy script broadcasts one
contract while the tests verify another" is not a statement that can be true —
not because something checks for it, but because there is one array and all
three contracts read it.

Suites are a REGISTRY the abstract iterates, not a chain of `else if`. A repo
adds a suite by adding an array entry; the keys reported by a mistyped
`DEPLOYMENT_SUITE` are built from that same array, so the failure message cannot
fall behind the suites it describes. Keys are checked unique, because the key is
what selects what gets broadcast.

**`src/abstract/RainDeployBroadcast.sol`** — the broadcast. Selects one suite by
`DEPLOYMENT_SUITE` and deploys it, before reading `DEPLOYMENT_KEY` so a mistyped
suite fails naming the valid ones rather than on a missing key.
`deployNetworks()` defaults to `supportedNetworks()` and is overridable for
repos that bootstrap one chain per dispatch.

**`script/Deploy.sol`** —
`contract Deploy is RegistryDeploySuites,
RainDeployBroadcast {}`. Empty on
purpose: the suites and the broadcast are both inherited. Run only via the
`Manual sol artifacts` workflow.

**`src/abstract/RegistryDeploySuites.sol`** — this repo's own declaration, one
named candidate per deployed registry, inherited by `script/Deploy.sol`,
`script/Build.sol`, the pins test contracts and `GeneratedSnapshotShapeTest`.

**`src/abstract/RainDeployVerify*.sol`** — the deploy-pin verification every
deploy repo inherits instead of hand-writing.

Nothing is per suite beyond an array entry, and nothing anywhere is per network.

The creation code is the only parameter. The Zoltu factory is `CREATE2` over its
calldata under a zero salt, so the address is a pure function of it, and running
it once locally gives the runtime code and its hash. The address, code hash and
runtime code a generated file records are checked OUTPUTS.

Four groups, sorted by what they are anchored to:

1. **Internal to the recorded set** (`RainDeployVerifySnapshot`) — what a
   version records is what its own creation code derives. Catches a set
   generated inconsistently. CANNOT catch a snapshot of the wrong contract: a
   consistent snapshot of the wrong thing satisfies all of it, which
   `testWrongContractSnapshotPassesInternalConsistency` pins.
2. **Anchored to source** (`RainDeployVerifySnapshot`) — EVERY candidate's
   recorded creation code is `type(X).creationCode`. The only check that catches
   a wrong-contract snapshot. Candidates only, because a released tag is MEANT
   to diverge from current source; there is no field on a released version to
   spell it, so it cannot be opted into or out of. Every one, and refusing an
   empty list, because a candidate the loop never reaches is a contract whose
   snapshot nothing anywhere anchors — see `NoDeployCandidates`.
3. **Anchored to the record** (`RainDeployVerifySnapshot`) — every file in the
   append-only `src/generated/<tag>/` tree is declared by a released suite,
   matched by the address that file's creation code derives. `releasedSuites()`
   is generated from that same record and everything anchored to a chain reads
   it, so a frozen tag it does not name is a release that quietly drops out of
   every check there is — which is what this catches when the generated file is
   hand edited, a record directory arrives out of band, or nobody re-ran the
   generator after the record moved. Matched against RELEASED suites only: a
   release and the candidate it was cut from are byte-identical from the moment
   the release is cut, so matching the whole declaration would let a candidate
   declare a release.
4. **Anchored to chain** (`RainDeployVerifyChain`) — across
   `supportedNetworks()`, every RELEASED version's derived address carries code
   with its derived code hash. The only check that catches "never deployed" or
   "not there any more", neither of which the repo can hold: both go false with
   nobody touching it.

Group 4 is released-only for the mirror image of group 2's reason. A release IS
a deployment that happened; a candidate is what the next release will be, and
between releases it is ordinarily ahead of anything on chain, so demanding it be
live asserts something false by design. Neither exemption is a field a caller
can set. Group 3 is what makes group 4's scope complete — a release group 4 is
never handed is a release it cannot fail on.

Group 4 lives in its own contract so an unreachable RPC endpoint fails only it,
never the snapshot assertions, and a failure names which of the two it was.

A single recorded code hash per version can only be true if the runtime code is
the same on every network, so a constructor reading `block.chainid` or similar
is a DEFECT: it fails hard, naming the chain and both hashes. There is
deliberately no per-chain code hash to record.

The `src/abstract/` files are the only `src/` files `slither.config.json`
filters out, by name. They are inherited by test contracts and never deployed,
so slither's detectors — all of which are about deployed-code risk — have
nothing to say about them except that an abstract does not implement its own
virtuals and that a cheatcode is called in a loop, and — because slither skips
`test/` and `script/` — that an abstract's virtuals have no caller. The filter
matches those filenames exactly, not the `src/abstract/` prefix, so a file added
there later — including a deployable one — is analyzed rather than silently
exempted.

The libraries are designed to be called from Foundry scripts (`forge script`) in
consuming repos, not directly. Consuming repos provide their own creation code,
expected addresses, expected code hashes, and dependency lists.

## Key Design Patterns

- **Deterministic addresses**: Zoltu proxy ensures same address on every chain.
  Deployments fail if the resulting address doesn't match `expectedAddress`.
- **Code hash verification**: Post-deploy bytecode integrity is verified against
  `expectedCodeHash`. The address registry is verified the same way before it is
  read.
- **Dependency checking**: per network, and only where the deploy actually runs.
  On a network with no code at `expectedAddress`, the Zoltu factory must have
  code and match `ZOLTU_FACTORY_CODEHASH` and every dependency must have code,
  all read on that network's own fork immediately before broadcasting. A network
  that already has the code skips the deploy and the dependency check with it: a
  contract that is already deployed does not need its dependencies present to
  stay deployed. There is no all-network pre-flight.
- **Idempotent deploys**: If code already exists at the expected address,
  deployment is skipped for that network.
- **Resolve once, verify after**: registry bindings are mutable, so the
  meaningful check is not "does the registry say what I expect" before a deploy
  but "does the deployed contract hold what I expect" after one. A consumer
  resolves in its constructor; the deployment is then verified across every
  network before anything migrates onto it.
- **Deploy-repo lifecycle**: a manual `sol-v*` tag is the sole release trigger
  (`rainix-tag-release`), because this repo carries deployed concretes whose
  pins consumers rely on. `[package].version` is the LAST released version and
  moves only in lockstep with its snapshots.
- **Deploy, then verify, then tag** — in that order, and they are three separate
  things. `script/Deploy.sol` broadcasts the suite `DEPLOYMENT_SUITE` names to
  every network in `supportedNetworks()`, dispatched by hand through
  `.github/workflows/manual-sol-artifacts.yaml`, whose `suite` input is a choice
  over the declared keys. One suite per dispatch, so this repo's two registries
  are two dispatches. Only then is there a deployment for `rainix-tag-release`
  to verify pins against — it verifies and publishes, it never broadcasts.
  Broadcasting is key custody and real money, so it is `workflow_dispatch` and
  nothing else. Deploying is idempotent: a network that already has the code is
  skipped, so a partial run is fixed by running it again.

  `RegistryDeployChainTest` is what verifies it, and it checks the RELEASED
  suites. Nothing is released yet, so it has nothing to check and forks nothing.
  It gets a subject the moment a release is frozen and declared — from then on
  it is red until that release is live on every supported network, which is why
  the deploy comes first.

## License

DecentraLicense 1.0 (LicenseRef-DCL-1.0). All source files must have SPDX
headers. REUSE compliance is enforced in CI.
