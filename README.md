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
- Which operational migrations have actually been applied on this chain, and
  when they ran — including the ones that ran before there was anywhere to write
  them down — so a test can assert the state they imply instead of guessing from
  a date?
- Can a migration be skipped, repeated or applied out of order on one chain and
  not another?

Approach:

- Zoltu deterministic deployment proxy: same address on every supported network.
- Caller-provided supported-network and dependency lists.
- Hard guards against deploying to networks where dependencies are missing.
- Pre-calculated addresses asserted against the creation code before deploying,
  and against the chain after: silent failures fail loudly.
- Bytecode integrity checks post-deploy: `codehash` is compared against the
  recorded pin on every network by `RainDeployVerifyChain`, and before every
  registry access by `LibAddressRegistry` and `LibMigrationRegistry`.
- An address registry, read at run time rather than compiled into creation code,
  and a post-deploy check that every target network's deployment took the
  address it was supposed to.
- A migration registry, so operational scripts record what they applied and when
  it ran, each onto the head it is applying to, and tests assert the state that
  implies rather than branching on a deadline.
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

// script/Build.sol
contract Build is MyDeploySuites, BuildScript {
    function regenerateSnapshots() internal override;
    function regenerateLibs() internal override;
    function snapshotContractNames() internal view override returns (string[] memory);
}

// test/src/abstract/MyDeploySnapshot.t.sol
contract MyDeploySnapshotTest is MyDeploySuites, RainDeployVerifySnapshot {}

// test/src/abstract/MyDeployChain.t.sol
contract MyDeployChainTest is MyDeploySuites, RainDeployVerifyChain {}
```

The broadcast and the verification read the SAME array. "The deploy script ships
one contract while the tests verify another" is therefore not a statement that
can be true — not because something checks for it, but because there is nothing
for it to disagree with. A repo that wrote its suites out twice would have that
bug available to it; this one does not.

`BuildScript` carries both build entry points concrete. `run()` regenerates the
generated sources and freezes nothing; `cutRelease()` regenerates, freezes the
release as `src/generated/<tag>/`, then regenerates from the record that now
holds it. Neither is `virtual`, so the entry point CI runs on every push has no
way to cut a release.

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

The source group is also the only one that is not only a test. It is defined on
the suite declaration, and the broadcast runs it before it selects a suite or
reads a key. The deploy reads the same recorded bytes, and the only other guard
in front of the `CREATE2` compares the recorded address against what the
recorded creation code derives — both out of the same generated file, so it
catches a stale pin and cannot catch a snapshot of the wrong contract. An anchor
only a test contract could reach would be an anchor the irreversible action does
not run, and `CREATE2` at a zero salt puts the wrong bytes at their own
permanent address on every chain the dispatch reached.

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

**Root is `address(0)` during rollout, so a registry deployed now is inert.**
`ADDRESS_REGISTRY_ROOT` in `src/concrete/AddressRegistry.sol` is the one place
that value lives. Nothing calls from the zero address, so no name can be bound,
and every read of an unbound name reverts — it fails loudly in both directions
and can never answer with a wrong address. Root is welded into the creation
code, so setting a real one moves the deploy address, the code hash and the
snapshot with it: the registry compiled under a zero root is not the one a
consumer will eventually resolve against, and deploying it now is not
preparation for the one that is.

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

## Migration registry

`MigrationRegistry` records that a migration has been applied, when, and onto
what: a writer applies one of its own onto the migration it believes ran last
(`applyMigration`, or `applyMigrationHistory` for one that already ran), anyone
reads when a given writer applied a given one (`applied`), what that writer
applied it onto (`appliedOnto`), and where a given writer's sequence has got to
(`head`). There is no removal and no upgrade.

The two writes differ in exactly one thing: where the recorded moment comes
from. `applyMigration` stamps the block the record lands in, for a script
applying its own migration in the same atomic unit as the migration itself.
`applyMigrationHistory` takes the moment as an argument, so a migration that ran
before the registry reached the chain is recordable with the time it actually
ran. They write the same record, into the same namespace, and make the same
refusals.

It exists because prod-state tests otherwise decide what to assert by reading
the **clock**. The pattern that emerges without it is a dual-state invariant —
accept either the pre- or the post-migration value until a hardcoded deadline,
and only the post value after it. That window asserts nothing during the one
period you most want to know about, every migration costs a manual refactor to
add and another to delete, and once the deadline passes CI red-lines on a date
rather than on a fact. What you actually want is "**exactly** the value implied
by the migrations that have run", which needs the chain to hold which ones have:

```solidity
if (LibMigrationRegistry.applied(SAFE, MIGRATION_V2) != 0) {
    assertEq(vault.owner(), NEW_OWNER);
} else {
    assertEq(vault.owner(), OLD_OWNER);
}
```

Both branches assert exactly. Neither skips, and `applied` answering zero is an
ordinary expected answer rather than a revert — it is the state of every
migration before it runs, and of every migration on a chain that never got it.

**`applied` is a timestamp, not a flag.** "Which invariant applies" is
frequently "which invariant applies _yet_": a cliff that starts at the
migration, a rate that changes a week after it. A flag sends a consumer that
needs the moment back to a hardcoded date, which is the thing this registry
exists to delete. Zero and nonzero carry the same two distinct facts a flag did,
with the nonzero case saying more — and zero stays unambiguous because a zero
moment is refused outright rather than written as a record that reads back as no
record.

**The moment is the caller's, inside a window the registry enforces.** The fact
being recorded is that a migration RAN, and the moment it ran is not in general
the moment anybody gets to write it down. A registry that could only stamp its
own block offers a writer with history two options and no third: record a time
that is false for every past migration, or record nothing — and recording
nothing strands the namespace, because the registry refuses anything not applied
onto the current head, so a writer that skipped its past migrations cannot
record its next one either.

What a reader gives up is **not** authenticity. A record is namespaced by the
account that wrote it and no authority checks it, so every entry is already
exactly as trustworthy as its writer and no more; a writer free to invent an id
was always free to invent the fact. What a reader gives up is precisely that
`appliedAt` is the block the record landed in. Everything else is kept, by three
refusals:

- **Never zero** (`ZeroTimestamp`), or the record would read back through
  `applied` as no record while the head had moved and the migration could never
  be applied again.
- **Never after the block it is written in** (`FutureTimestamp`). A migration
  that has run has run, so a moment still to come is not a late record of
  anything, and a consumer measuring an interval since the migration — a cliff,
  a grace period, a rate that changes a week later — can subtract it from the
  current block without underflowing.
- **Never before the record it is applied onto** (`TimestampBeforeHead`), so a
  namespace's moments never go backwards along its chain and the gap between two
  of its migrations subtracts in chain order without underflowing either. The
  first migration in a namespace is applied onto `MIGRATION_HEAD_GENESIS`, which
  holds no record and so bounds nothing.

Equal is allowed wherever there is a neighbour. A moment may be exactly the
block it is written in, and two records may carry the same moment: two
migrations applied in one transaction share a block, and two backfilled to the
same day share a moment, so forcing them apart would demand a precision the
moments do not have. Which of them ran first is the chain, not the moments —
total order comes from `appliedOnto`, and the bound above only stops a record
claiming to predate the one it is chained onto.

Both writes get all three, `block.timestamp` included: a block whose timestamp
is zero is `ZeroTimestamp` on `applyMigration`, which a test that warps to zero
and a chain configured from a zero genesis both reach.

**A set of applied migrations, not a high-water mark.** A mark needs a total
order consumers do not have: two migrations authored on one day collide, and one
migration split across two scripts because it landed on two networks a week
apart cannot be one comparable value at all. A set represents both exactly, and
the ordering between migrations moves into the assertion —
`applied(V5) != 0 ? … : applied(V4) != 0 ? … : …` — which is where the semantic
dependency actually lives.

**A head, so a step cannot be skipped or repeated.** A namespace has a head: the
migration it applied most recently, or `MIGRATION_HEAD_GENESIS` if it has
applied none. Both writes name the head they are applying onto, so a chain that
never got the predecessor fails at the moment of applying rather than diverging
silently, and two migrations dispatched at once cannot land in the wrong order.

```solidity
// The first migration in a namespace, applied in this transaction.
LibMigrationRegistry.applyMigration(MIGRATION_HEAD_GENESIS, MIGRATION_V1);
// Every later one names its predecessor.
LibMigrationRegistry.applyMigration(MIGRATION_V1, MIGRATION_V2);
// One that ran before the registry reached this chain names the moment it ran.
LibMigrationRegistry.applyMigrationHistory(MIGRATION_V2, MIGRATION_V3, 1750000000);
```

Each record also keeps the head it was applied onto, which `appliedOnto` reads
back, so a namespace is a chain in storage rather than a set of moments to sort:
from `head`, each answer names the record before it, down to
`MIGRATION_HEAD_GENESIS`. That chain is the order the migrations ran in whatever
moments the records carry.

Genesis is deliberately **not zero**. Zero is what an uninitialised `bytes32`
constant reads as, and a zero genesis would make a mis-set predecessor constant
a _successful_ first application on any namespace that happens to be empty — the
state of every chain that has not been migrated yet, which is exactly where such
a mistake is most likely. A nonzero genesis makes it a revert everywhere.

The head does **not** replace the per-migration refusal, and both are kept.
Re-applying a migration whose successor has landed names a head that matches
perfectly; without `MigrationAlreadyApplied` it would drag the head backwards
and overwrite the original timestamp, which is a record un-happening. The two
answer different questions — the head is _where in the sequence_, the record is
_whether at all_.

One namespace on one chain is therefore one linear sequence. Two unrelated sets
of migrations applied from the same account interleave into one chain of heads,
so a consumer that wants two independent sequences applies them from two
accounts — the same lever that already decides who a reader trusts.

**The namespace is `msg.sender`, and that is the whole access control.** Anyone
may write, but only under themselves, so a reader asking about the namespace of
an authority it already trusts is reading something only that authority could
have written; every other namespace holds unforgeable claims nobody asks about.
A root would have to be welded into the creation code, the way
`ADDRESS_REGISTRY_ROOT` is — and the account that applies a migration is a
different Safe, deployer or timelock for every consumer and every chain, so one
root would have to be all of them, and baking each consumer's authority in would
give each a different address for what is meant to be one shared registry. With
nothing to configure there is also no rollout state in which it is inert.

**An index, not proof.** The registry says which invariant applies. It does not
say the invariant holds — a multisig can act out of band and nothing here moves.
Keep both layers: this selects, codehash and bytecode pins verify. Replacing the
pins with it trades a clock-guess for a bookkeeping-guess.

`LibMigrationRegistry` is the surface — `applied`, `appliedOnto`, `head`,
`applyMigration` and `applyMigrationHistory`, each verifying the registry's code
hash before it reads or writes. There is deliberately **no broadcast runner**:
the dominant real shape is a Safe executing a bundle that never broadcasts, and
such a script appends `applyMigration` to the bundle it is already emitting,
which makes the record atomic with the migration it describes.

## Deploying, and then releasing

Three separate steps, in this order. Nothing automatic ever broadcasts.

1. **Deploy.** Dispatch the
   [`Manual sol artifacts`](.github/workflows/manual-sol-artifacts.yaml)
   workflow, choosing a `suite`. It runs `script/Deploy.sol` and broadcasts that
   suite to every network in `supportedNetworks()`. One suite per dispatch, so
   this repo's two registries are two dispatches. `workflow_dispatch` only: this
   is key custody and real money, and no merge or tag should be able to trigger
   it. It is idempotent — a network that already has the code is skipped — so a
   partial run is fixed by running it again rather than by unpicking anything.
2. **Verify.** `RegistryDeployChainTest` passes only once every **released**
   suite is live on every supported network, with the code that release froze.
3. **Tag.** Push a `sol-v*` tag, the sole release trigger. It verifies and
   publishes but never broadcasts, which is exactly why step 1 cannot be folded
   into it. The release mechanics are `rainix-tag-release`'s.

This is a deploy repo: it carries deployed concretes whose addresses and
codehashes consumers pin, so releases are **manual `sol-v*` tags**, not merges.
`[external.package].version` is the version of the LAST Soldeer publish, and
only a release moves it. A release cut under this lifecycle also names the
frozen `src/generated/<tag>/` record `cutRelease()` wrote for it. Every version
published under the previous merge-driven lifecycle predates that record and has
none, so `src/generated/` holds no directory for it; those versions stay
published, and consumers pin exact versions and are unaffected.

## Crediting the deployer's HyperCore account

HyperEVM interleaves small fast blocks with large slow ones, and a deployment
too big for the fast block's gas cap has to go in a big block. Big blocks are
opted into with an `evmUserModify` action, which HyperCore accepts only from an
address it already knows — one that holds a Core asset. A deployer funded purely
to pay EVM gas is not that address, so the deploy above cannot reach HyperEVM at
all until something puts an asset on Core for it.

Nothing external has to. HYPE is HyperEVM's native gas token rather than an
ERC20, and value sent to the system contract at
`0x2222222222222222222222222222222222222222` is credited on Core to whoever sent
it. The deployer already holds HYPE, because that is what it pays gas in, so it
credits itself.

The canonical way to run it is the
[`Manual credit hypercore`](.github/workflows/manual-credit-hypercore.yaml)
workflow. The amount is its `credit-wei` input, typed under its own name — which
is why this is not a `Manual sol artifacts` dispatch: that workflow exports
`DEPLOYMENT_SUITE`, `DEPLOYMENT_NETWORK` and `DEPLOYMENT_KEY` and nothing else,
so an amount of real money could only travel through it under a name that means
something else. Every dispatch executes the dry run; broadcasting takes the
`broadcast` input flipped to true as well, and even then the dry run still runs
and refuses first. Dispatching is admin-gated: GitHub itself gates
`workflow_dispatch` at write access and nothing finer, so the workflow's first
step asks GitHub what permission the dispatching actor holds on this repo and
fails the run unless the answer is `admin` — who dispatched and what they held
is in the run log either way.

The fallback, for when the workflow itself is what is broken, is the same script
by hand:

```sh
read -rs DEPLOYMENT_KEY && export DEPLOYMENT_KEY
HYPERCORE_CREDIT_WEI=10000000000000000 \
  nix develop -c forge script script/CreditHyperCore.sol:CreditHyperCore --legacy
```

The key is read rather than written into the command, because a
`DEPLOYMENT_KEY=0x...` prefix is a private key in the shell's history file,
where it outlives the run and the terminal both.

Run exactly that first, without `--broadcast`: it is a dry run against a fork of
HyperEVM that executes every guard and the transfer itself and sends nothing, so
anything the real run would refuse is refused there for free. Add `--broadcast`
to send it. `--legacy` for the same reason the deploy workflow carries a
`legacy` input — HyperEVM's RPC rejects the fee-history ranges EIP-1559
estimation asks for. No `--rpc-url`: the script forks the `hyperevm` alias
itself.

`HYPERCORE_CREDIT_WEI` is EVM wei, and required — an amount of real money is not
something to default. It has to be a whole number of Core wei, which is
`10 ** 10` EVM wei, because HYPE has 8 wei decimals on Core against 18 on the
EVM and the remainder is **burned** rather than credited. An amount smaller than
that is burned in full: the transfer succeeds, the HYPE is gone, and the address
is still not a HyperCore user. `LibHyperCore` refuses it rather than rounding.

It also refuses to run anywhere but chain 999. That address is a system contract
on HyperEVM and an ordinary unowned address on every other chain, where value
sent to it is not rejected, just unrecoverable — so the chain id is checked
before anything else, and the code hash at the system address is checked against
a pin straight after, because a chain id alone does not say the contract behind
it is the one that emits the log Core credits from.

However it is run, it is run once per deployer address and never again: a
HyperCore user does not stop being one, so a second run is more money for no
further effect.

## Toggling big blocks

Crediting made the deployer a HyperCore user; opting into big blocks is a
separate action on that user, and the one the credit exists to make possible.
`{"type": "evmUserModify", "usingBigBlocks": true}`, signed by the deployer key
and POSTed to HyperCore's exchange endpoint, sends the deployer's HyperEVM
transactions to big blocks from then on. The flag is persistent per address:
nothing expires it, so the same action with `false` is how the deployer gets
back OUT of big blocks once the sizeable deploy is done — which is why one
workflow serves both directions and its `using-big-blocks` input is required
rather than defaulted.

The canonical way to toggle it is the
[`Manual big blocks`](.github/workflows/manual-big-blocks.yaml) workflow,
admin-gated exactly as `Manual credit hypercore` is, and `workflow_dispatch`
only for the same reason: signing with the deployment key is key custody. The
signing scheme — msgpack of the action and nonce, keccak, an EIP-712 "phantom
agent" — is the official Hyperliquid Rust SDK's, called by the small
[`tools/hyperliquid-big-blocks`](tools/hyperliquid-big-blocks/) crate and
deliberately not hand-rolled: an encoding wrong by one byte still yields a
signature that recovers as some OTHER address, which is not a failure mode to
meet live. The SDK is pinned to an exact git rev in the crate's manifest, which
also says why a rev rather than a crates.io version, and the `big-blocks-tool`
CI job builds and tests the crate on every push, so the first dispatch is not
the first compile.

The run fails unless the exchange answers `"status": "ok"`, and the full
response is in the run log. That log line is the record: Hyperliquid has no
info-endpoint query that reads `usingBigBlocks` back, so the only observable of
the flag afterwards is which blocks the deployer's next transactions land in.

The fallback, for when the workflow itself is what is broken, is the same crate
by hand — the key read rather than written into the command, for the same
shell-history reason as the credit:

```sh
read -rs DEPLOYMENT_KEY && export DEPLOYMENT_KEY
USING_BIG_BLOCKS=true nix develop github:rainlanguage/rainix#rust-shell \
  -c cargo run --locked --manifest-path tools/hyperliquid-big-blocks/Cargo.toml
```

`rust-shell` comes from rainix directly because this repo's own dev shell is the
slim `sol-shell`, which carries no cargo.

## Install

Via [soldeer](https://soldeer.xyz):

```sh
forge soldeer install rain-deploy~<version>
```

**You also need `forge-std` 1.16.2 and `rain-sol-codegen` 0.1.36**, remapped as
`forge-std-1.16.2/` and `rain-sol-codegen-0.1.36/`. The published package ships
`src/`, `script/` and the licence and README files — no `test/`, no
`foundry.toml`, no `remappings.txt`, no `soldeer.lock`, no `dependencies/` — so
a consumer resolves both itself. The requirement is transitive rather than
incidental: the deployed contract imports nothing outside this package, but
every abstract a consumer inherits pulls them in — `Script` via
`RainDeployBroadcast`, `Test` via `RainDeployVerifyBase`, `Vm` via
`LibRainDeploy` beneath both, and `LibCodeGen`/`LibFs` via
`LibRainDeploySnapshot`, which `RainDeployVerifySnapshot` imports:

```toml
[dependencies]
forge-std = "1.16.2"
rain-sol-codegen = "0.1.36"
rain-deploy = "<version>"
```

The versions have to match: the import paths are version-qualified, which is
deliberate — it is what stops a consumer's incompatible copy from silently
satisfying these imports.

## Develop

This repo uses [nix](https://nixos.org/download.html). The default shell is the
slim `sol-shell` from [rainix](https://github.com/rainlanguage/rainix).

```sh
nix develop          # enter the shell
forge soldeer install # install deps declared in foundry.toml
forge test
```

Three of the CI jobs are rainix reusable workflows, not commands in the shell,
and the fourth is repo-local. What each of them runs, which is what reproduces
it locally:

- `rainix-sol-test` — `forge test -vvv`
- `rainix-sol-legal` — `reuse lint`
- `rainix-sol-static` — `slither .`, `forge fmt --check`, then
  `rainix-sol-single-contract`
- `big-blocks-tool` — `cargo fmt --all -- --check`, `cargo clippy` and
  `cargo test --locked` in `tools/hyperliquid-big-blocks/`, in rainix's
  `rust-shell`

Use the nix-pinned `forge` for all development.

## License

DecentraLicense 1.0 (SPDX: `LicenseRef-DCL-1.0`) — full text in
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
