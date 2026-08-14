# rain.deploy

Tooling to deploy Solidity contracts deterministically across EVM networks via
the Zoltu deployment proxy.

Fundamentally Rain code is EVM-compatible and permissionlessly deployable
anywhere, but only a curated subset of networks are active deploy targets for
the Rain organisation. This library provides shared infrastructure for that
subset.

It answers:

- Are the dependencies of the current deployment available on this network?
- Does this deployment match other deployments on other networks?
- Have I deployed successfully to all expected networks?
- How do I track deployments over time and share addresses with other people?
- How do I ensure deployed code is bytecode-equivalent to local compilations?
- How does a deployment get a configured address — an owner, say — without
  baking one into its creation code, where changing it would move every future
  deployment?
- Is every version I have ever released still live, with the code I compiled, on
  every network I support?

Approach:

- Zoltu deterministic deployment proxy: same address on every supported network.
- Caller-provided supported-network and dependency lists.
- Hard guards against deploying to networks where dependencies are missing.
- Pre-calculated addresses asserted against the creation code before deploying,
  and against the chain after: silent failures fail loudly.
- Bytecode integrity checks (e.g. via the Rain Extrospection lib) supported
  post-deploy.
- An address registry, read at run time rather than compiled into creation code,
  and a post-deploy check that every target network's deployment took the
  address it was supposed to.
- One inherited deploy-pin verification, parameterized over versions, rather
  than assertions hand-enumerated per version and per chain in every deploy
  repo.

## One declaration, deployed and verified

A repo declares its suites ONCE. A suite is a named snapshot: a key, the
creation code, the recorded address/code hash/runtime code, the artifact path
and the addresses that must already be on chain before it can be deployed.

```solidity
// src/abstract/MyDeploySuites.sol
abstract contract MyDeploySuites is RainDeploySuitesBase {
    function releasedSuites() internal pure override returns (DeploySuite[] memory);
    function candidateSuites() internal pure override returns (DeployCandidate[] memory);
}

// script/Deploy.sol
contract Deploy is MyDeploySuites, RainDeployBroadcast {}

// test/src/concrete/MyDeploySnapshot.t.sol
contract MyDeploySnapshotTest is MyDeploySuites, RainDeployVerifySnapshot {}

// test/src/concrete/MyDeployChain.t.sol
contract MyDeployChainTest is MyDeploySuites, RainDeployVerifyChain {}
```

The broadcast and the verification read the SAME array. "The deploy script ships
one contract while the tests verify another" is therefore not a statement that
can be true — not because something checks for it, but because there is nothing
for it to disagree with. A repo that wrote its suites out twice would have that
bug available to it; this one does not.

Suites are a **registry the abstract iterates**, not a chain of `else if`.
Adding a suite is adding an array entry. A mistyped `DEPLOYMENT_SUITE` reports
the valid keys built from that same array, so the error cannot fall behind the
suites it describes, and keys are checked unique because the key is what selects
what gets broadcast.

Every suite is individually selectable, including a frozen release — which is
how a snapshot from before a network existed reaches that network.

## Deploy verification

**The creation code is the only input.** The Zoltu factory is `CREATE2` over its
calldata under a zero salt, so the address is a pure function of the creation
code and identical on every network, and running that creation code once locally
yields the runtime code and its hash. Everything else a suite records is a
checked output.

Recorded rather than derived, deliberately. `LibRainDeploy` compares the
recorded address against the creation code **before it forks anything**, so a
stale pin fails instead of deploying to wherever the code happens to land.
Deriving the pins at broadcast time would make that comparison
derived-against-derived, and a guard that compares a value to itself is not a
guard.

Four groups, sorted by what each is anchored to and therefore by what each can
catch:

| Group    | Anchored to            | Catches                               | Cannot catch                     |
| -------- | ---------------------- | ------------------------------------- | -------------------------------- |
| Internal | the recorded set       | an inconsistently generated set       | a snapshot of the wrong contract |
| Source   | `type(X).creationCode` | a snapshot of the wrong contract      | anything about any chain         |
| Record   | the frozen record      | a release the declaration missed      | what a declared suite records    |
| Chain    | the networks           | never deployed, or not there any more | anything about a candidate       |

The internal group's blind spot is not a gap to close there: every check in it
asks the recorded bytes to agree with each other, and the wrong contract's bytes
agree with each other perfectly. The source anchor is the only thing that
catches it, and it applies to the **candidates only** — a released tag is meant
to have diverged from current source, so anchoring one to source asserts
something false by design. That is a property of the assertion, and there is no
field on a released version with which to opt in or out.

It runs over EVERY candidate, and a declaration that names none at all is
refused with `NoDeployCandidates` rather than passed as a loop with nothing in
it. A candidate the source anchor never reaches is a contract whose snapshot
nothing anywhere anchors, and a repo with several contracts is exactly where a
snapshot generated from the wrong one comes from.

The chain group carries the mirror image of that exemption: it applies to
**released versions only**. A release IS a deployment that happened, so "it is
live on every supported network" is either true of it or a defect. A candidate
is what the next release will be, ordinarily ahead of anything on chain, so
demanding it be live asserts something false by design in the other direction.
Neither exemption is a field a caller can set.

Scoping to releases puts the whole weight on `releasedSuites()` naming every
release, which is what the record group is for. A frozen tag the declaration
misses is not an entry that turns up missing somewhere — it is a release the
chain group is never handed, and a check with no subject cannot fail on it, so
that release drops out of everything while the suite stays green. The
declaration is generated from the append-only `src/generated/<tag>/` record and
checked back against it, matched by address, since matching by name would assert
only that a convention was followed.

**Chain-independent runtime code is a requirement, not a caveat.** One recorded
code hash per version can only be true if the runtime code is the same
everywhere. A constructor that reads `block.chainid` deploys different code per
chain: deploying through Zoltu buys address predictability, and such a
constructor spends it. So a per-chain difference fails hard, naming the chain
and both hashes, and there is deliberately no per-chain code hash to record.

## Address registry

`AddressRegistry` binds an opaque `bytes32` name to an address. An immutable
root authority binds a name, anyone reads a bound name, and reading an unbound
name reverts rather than answering with the zero address. There is no removal,
no upgrade and no authority besides root.

Bindings are **mutable**, because the addresses they name are. Rotating an
owning multisig is ordinary business and has to be expressible without moving
anybody's deterministic address — which a binding welded to one address forever
would make impossible, because the name is in the consumer's creation code, so a
new name means new creation code and a new address. That is the problem the
registry exists to remove, not a property worth keeping.

Mutability costs nothing already deployed. A consumer resolves a name **once**,
in its constructor, and stores the answer; it never reads the registry again. So
re-binding a name changes what the _next_ deployment resolves and nothing else,
which makes a rotation a deliberate migration rather than a silent change to
live contracts.

`LibAddressRegistry.resolve` is the read, verifying the registry's code hash
first, the same way `LibRainDeploy` verifies the Zoltu factory's. It resolves a
name to an address and stops there — what a consumer does with the address, and
when, is the consumer's business.

`LibRainDeploy.checkResolvedAddressesOnNetworks` is the **post-deploy**
verification: on every target network, the deployed contract must hold the
address the deployment expected. It runs after the deploy and before anything
depends on it, against state the deployment has already settled, so nothing it
reads can move underneath it. The same check run beforehand would be worth
nothing against a mutable source. A network where the deployment took something
else is a burned deterministic address, found while nothing points at it yet.

Only the consumer knows where it stored what it resolved, so the consumer
supplies the reads (`abi.encodeCall(IOwnable.owner, ())` and the like) and this
library supplies the fork loop and the comparison.

## Deploying, and then releasing

Three separate steps, in this order. Nothing automatic ever broadcasts.

1. **Deploy.** Dispatch the
   [`Manual sol artifacts`](.github/workflows/manual-sol-artifacts.yaml)
   workflow, which runs `script/Deploy.sol` and broadcasts `AddressRegistry` to
   every network in `supportedNetworks()`. `workflow_dispatch` only: this is key
   custody and real money, and no merge or tag should be able to trigger it. It
   is idempotent — a network that already has the code is skipped — so a partial
   run is fixed by running it again rather than by unpicking anything.
2. **Verify.** `AddressRegistryDeployChainTest` passes only once every supported
   network has the registry, with the code this repo compiles. It is red today
   because step 1 has never been run.
3. **Tag.** Push a `sol-v*` tag. `rainix-tag-release` regenerates the snapshot
   for the version the tag names, verifies the live chains against those fresh
   pins, publishes to Soldeer and commits the frozen snapshot back to `main`. It
   verifies and publishes; it never broadcasts, which is exactly why step 1
   cannot be folded into it.

This is a deploy repo: it carries a deployed concrete whose address and codehash
consumers pin, so releases are **manual `sol-v*` tags**, not merges.
`[package].version` is the LAST released version, naming the current
`src/generated/<tag>/` snapshot, and only a release moves it. Every version
published under the previous merge-driven lifecycle stays published; consumers
pin exact versions and are unaffected.

## Install

Via [soldeer](https://soldeer.xyz):

```sh
forge soldeer install rain-deploy~<version>
```

**You also need `forge-std` 1.16.1**, remapped as `forge-std-1.16.1/`. The
published package deliberately ships only `src/` and `script/` — no
`remappings.txt`, no `soldeer.lock`, no `dependencies/` — so a consumer resolves
`forge-std` itself. The requirement is transitive rather than incidental: the
deployed contract imports nothing outside this package, but every abstract a
consumer inherits pulls forge-std in — `Script` via `RainDeployBroadcast`,
`Test` via `RainDeployVerifyBase`, and `Vm` via `LibRainDeploy` beneath both:

```toml
[dependencies]
forge-std = "1.16.1"
rain-deploy = "<version>"
```

The version has to match: the import paths are version-qualified, which is
deliberate — it is what stops a consumer's incompatible `forge-std` from
silently satisfying these imports.

## Develop

This repo uses [nix](https://nixos.org/download.html). The default shell is the
slim `sol-shell` from [rainix](https://github.com/rainlanguage/rainix).

```sh
nix develop          # enter the shell
forge soldeer install # install deps declared in foundry.toml
forge test
```

The three CI jobs are rainix reusable workflows, not commands in the shell. What
each of them runs, which is what reproduces it locally:

- `rainix-sol-test` — `forge test -vvv`
- `rainix-sol-legal` — `reuse lint`
- `rainix-sol-static` — `slither .`, `forge fmt --check`, then
  `rainix-sol-single-contract`

Use the nix-pinned `forge` for all development.

## License

DecentraLicense 1.0 (DCL-1.0) — full text in
[`LICENSES/`](LICENSES/LicenseRef-DCL-1.0.txt). Roughly `CAL-1.0`
([opensource.org](https://opensource.org/license/cal-1-0)) plus user-data
disclosure obligations consistent with permissionless-blockchain assumptions.

This repo is [REUSE 3.2](https://reuse.software/spec-3.2/) compliant. Verify
locally:

```sh
nix develop -c reuse lint
```

## Contributions

Welcome under the same license. Contributors warrant that their contributions
are compliant.
