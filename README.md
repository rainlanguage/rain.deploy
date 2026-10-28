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
  registry access by `LibConfigRegistry` and `LibMigrationRegistry`.
- A config registry binding names to ABI-encoded values, read at run time rather
  than compiled into creation code, and a post-deploy check that every target
  network's deployment took the value it was supposed to, of any type.
- A migration registry, so operational scripts record what they applied and when
  it ran, each onto the head it is applying to, and tests assert the state that
  implies rather than branching on a deadline.
- One inherited deploy-pin verification, parameterized over versions, rather
  than assertions hand-enumerated per version and per chain in every deploy
  repo.

## One declaration, deployed and verified

A repo declares its suites ONCE. A suite is a named snapshot: a key, the
creation code, the recorded address/code hash/runtime code, the artifact path
and the dependencies that must already be on chain before it can be deployed —
each of those an address paired with the runtime code that belongs at it.

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
    function generatedContracts() internal view override returns (GeneratedContract[] memory);
    function regenerateSnapshots() internal override;
}

// test/src/abstract/MyDeployVerify.t.sol
contract MyDeployVerifyTest is MyDeploySuites, RainDeployVerify {}
```

`RainDeployVerify` is the whole of the verification binding, deliberately. It is
the union of `RainDeployVerifyChain` and `RainDeployVerifySnapshot`, so a check
added to either — or to the union — reaches every consumer on a version bump
with no downstream edit. A check a consumer has to remember to bind is a check
most consumers do not run, so a new assertion goes into something this already
inherits rather than into an abstract beside it. The pair underneath stays two
contracts because that split is runtime rather than binding: the chain half
forks every supported network and the snapshot half touches none, so a job with
no RPC credentials binds `RainDeployVerifySnapshot` alone and `--match-contract`
selects it.

The broadcast and the verification read the SAME array. "The deploy script ships
one contract while the tests verify another" is therefore not a statement that
can be true — not because something checks for it, but because there is nothing
for it to disagree with. A repo that wrote its suites out twice would have that
bug available to it; this one does not.

`BuildScript` carries both build entry points concrete. `run()` regenerates the
generated sources and the network config, and freezes nothing; `cutRelease()`
regenerates, freezes the release as `src/generated/<tag>/`, then regenerates
from the record that now holds it. The config is written by `run()` alone: it is
not part of a release record, and `cutRelease()` is the one operation that
cannot be repeated. Neither is `virtual`, so the entry point CI runs on every
push has no way to cut a release.

Suites are a **registry the abstract iterates**, not a chain of `else if`.
Adding a suite is adding an array entry. A mistyped `DEPLOYMENT_SUITE` reports
the valid keys built from that same array, so the error cannot fall behind the
suites it describes, and keys are checked unique because the key is what selects
what gets broadcast. They are also checked against an **alphabet**: kebab case,
optionally followed by `@` and a release tag, which is the shape a repo writes
by hand and the shape a cut release generates. A key outside it is one the
reported list cannot be read back as — a comma or a space in a key renders as
two keys and sends a reader after one that is declared nowhere — and the empty
key falls to the same rule, which matters most: the empty string is what an
unset `DEPLOYMENT_SUITE` arrives as, so leaving it declarable would let a
dispatch with the suite input blank select something instead of reporting that
it was told nothing.

Every suite is individually selectable, including a frozen release — which is
how a snapshot from before a network existed reaches that network.

### Other mechanisms

A suite with empty `mechanismData` deploys through Zoltu; every Zoltu hook
refuses non-empty data with `UnexpectedMechanismData`. Another mechanism is an
abstract extending `RainDeploySuitesBase` that overrides its `virtual` mechanism
hooks (`deployedAddress`, `recordedAddress`, `addressChainIds`,
`deployStepData`, `deployStep`, `deployLocally`, `deployLocallyOnChain`,
`withUnrecordedNetworks`, `appendExtendedNetworks`, `checkNetworkFrozen`,
`suiteBeacon`, `logVerification`, `writeSuiteSnapshot`, `releasedMechanismData`)
for the `mechanismData` it owns and falls through to `super` for the rest.
Broadcast, every verification group and `BuildScript` reach a suite only through
those hooks. Factory clones and beacon proxies are `RainDeployCloneSuitesBase`
in `rain-factory`.

### Upgradeable beacons

Declare every beacon with its network's chain id, naming implementations by
suite key and moving them through `MigrationRegistry` migrations:

```solidity
function beacons() internal view override returns (ChainBeacon[] memory) {
    ChainBeacon[] memory chainBeacons = new ChainBeacon[](1);
    chainBeacons[0].chainId = ARBITRUM_ONE_CHAIN_ID;
    DeployBeacon memory beacon = chainBeacons[0].beacon;
    beacon.beaconSuite = "vault-beacon@0_1_0";
    beacon.initial = BeaconState({implementation: "vault@0_1_1", owner: ARBITRUM_TIMELOCK});
    beacon.transitions = new BeaconTransition[](1);
    beacon.transitions[0] = BeaconTransition({
        migration: Prerequisite({writer: SAFE, namespace: NAMESPACE, migration: UPGRADE_0_2_0}),
        state: BeaconState({implementation: "vault@0_2_0", owner: ARBITRUM_TIMELOCK})
    });
    return chainBeacons;
}
```

On each network's fork the chain group expects the state of the latest
transition the network's registry reports `appliedV4`, else `initial`: the
beacon at its code hash, `implementation()` at that suite's address on the
network, `owner()` at that owner, and the beacon's own suite, when it names one,
and that state's implementation suite live there as any suite is. A suite a
beacon names MUST be released, refused otherwise with `BeaconSuiteNotReleased`:
a candidate's address moves with its source. Name a beacon that is itself a
released suite by its suite key in `beaconSuite`, and any other (one a
set-deployer `new`s, nonce-deployed per chain, or one deployed elsewhere) by
both `beacon` and `beaconCodeHash`; naming it by `beaconSuite` and by either
`beacon` or `beaconCodeHash` is refused with `BeaconNamedTwice`, and naming it
by neither, or, without `beaconSuite`, by only one of `beacon` and
`beaconCodeHash`, with `BeaconUnnamed`. A beacon whose chain id is not one of
`supportedNetworks()`, in the catalogue or not, is refused with
`BeaconOnUncheckedNetwork`, and a second declaration of a beacon on its network
with `BeaconDeclaredTwice`. A beacon named by `beaconSuite` is deployed locally
at its address under its network's chain id, with only its suite's declared
dependencies etched, so its constructor MUST succeed there, and is refused with
`BeaconSeatedOwner` or `BeaconSeatedImplementation` when it answers `owner()` or
`implementation()` with data other than its initial state; a read that reverts
or answers nothing is left to the chain group. These refusals, and
`BeaconTransitionMigrationRepeated` and `BeaconTransitionMigrationUnnamed`
below, are raised offline for every beacon by the Beacons group
(`testBeaconDeclarationsResolve`, inherited through
`RainDeployVerifySnapshotBase`), and by the chain group, before any network is
forked, for the beacons on the networks it checks; `BeaconOnUncheckedNetwork`
there covers every beacon. A beacon with transitions reads `MigrationRegistry`
on its network, which MUST be deployed there. The chain group reads `owner()`,
and refuses a beacon that answers `pendingOwner()` with one nonzero word with
`BeaconPendingOwner`, or with data that is not one word with
`BeaconPendingOwnerUnreadable`; a `pendingOwner()` that reverts or returns
nothing passes. A two-step handover is red from `transferOwnership` until the
batch that accepts it applies its migration. Assert any other authority a beacon
exposes (roles) yourself, including that the deploy key holds none of it. The
deploy key is never a declared owner of any state, past states included, and a
broadcast whose key is one is refused with `BeaconOwnedByDeployKey` before any
network is read. A beacon named by `beacon` and `beaconCodeHash` that was owned
by a deploy key and has since been handed over declares its post-handover state
as `initial`, with no transition for the handover. A beacon named by
`beaconSuite` declares as `initial` the owner its suite seats
(`BeaconSeatedOwner` holds it there), so a released beacon suite that seated the
deploy key is declared by `beacon` and `beaconCodeHash`. A broadcast is also
refused before any network is read when its suite, deployed locally with the
deploy key as sender and origin under each target's chain id, answers `owner()`
with a first word whose low 160 bits are the deploy key (`SuiteSeatsDeployKey`),
so a suite seats its governance, not the deploy key, from its first state. For a
suite whose `addressChainIds` is non-empty the targets are those chain ids only
(its candidate's added networks included), each deploying only that network's
address; for any other suite they are every supported network, the networks the
broadcast does not reach included, then each network it reaches that is not
supported. The suite's constructor runs on the local EVM with only its declared
dependencies etched, so it MUST succeed there under each target's chain id: one
that reverts locally refuses the broadcast to every network. That check reads
`owner()` only: roles, pending owners, admin slots and contracts a constructor
creates are not read, so assert those yourself.

Declare transitions in the order their migrations are applied: each applied
transition's record MUST reach the latest earlier-declared applied one through
`appliedAfterV4` (its line's head, then its prerequisites), refused otherwise
with `BeaconTransitionsOutOfOrder`; moments are never compared. Each transition
names a distinct migration, refused otherwise with
`BeaconTransitionMigrationRepeated`, and one the registry can record (nonzero
writer and namespace, a migration neither zero nor `MIGRATION_HEAD_GENESIS`),
refused otherwise with `BeaconTransitionMigrationUnnamed`. A transition written
in another line names the earlier one, or a record after it, as a prerequisite.
The order walk is unbounded and costs a fork read per record it reaches: apply
each transition onto the previous transition's migration as its line's head or,
when it is written in another line, name it as a prerequisite, so the walk reads
one record. Otherwise it reads at most every record reachable from the later
transition, across lines, in fewer steps than the earlier one, and every
reachable record back to each line's genesis when the earlier one is not
reached. Apply a transition's migration in the same transaction as the beacon
change it describes (one Safe batch: `upgradeTo` or `transferOwnership`, then
`applyMigrationV4`; for an `Ownable2Step` beacon the handover's migration goes
in the batch that calls `acceptOwnership`, as `owner()` moves only then).
Between two separate transactions the chain group refuses the network, as the
chain and the registry disagree.

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

**A suite's declared dependencies are etched for the derivation, and only the
dependencies.** The local derivation runs before anything forks, so a declared
dependency is absent there and a constructor that reads one cannot run.
`deriveDeployment` etches each declared dependency's runtime code at its
declared address, inside the state snapshot it already reverts. A dependency is
declared as an address AND that code — the depended-on snapshot's published
`DEPLOYED_ADDRESS` and `RUNTIME_CODE` — because an address alone cannot say what
to put there. The dependencies are etched first, then the derived address is
cleared, then the factory is planted, so a declaration can reach neither the
subject's address nor the factory's.

Five groups, sorted by what each is anchored to and therefore by what each can
catch:

| Group    | Anchored to                | Catches                                                                                                                                         | Cannot catch                     |
| -------- | -------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------- |
| Internal | the recorded set           | an inconsistently generated set                                                                                                                 | a snapshot of the wrong contract |
| Source   | `vm.getCode(artifactPath)` | a snapshot of the wrong contract                                                                                                                | anything about any chain         |
| Record   | the frozen record          | a release the declaration missed                                                                                                                | what a declared suite records    |
| Beacons  | the beacon declarations    | a beacon misnamed, unreleased, off the supported networks, declared twice, seating other than its initial state, or with a malformed transition | what any beacon holds on chain   |
| Chain    | the networks               | a missing deployment, an alias on another chain, or a beacon off its declared state                                                             | anything about a candidate       |

The internal group's blind spot is not a gap to close there: every check in it
asks the recorded bytes to agree with each other, and the wrong contract's bytes
agree with each other perfectly. The source anchor is the only thing that
catches it, and it applies to the **candidates only** — a released tag is meant
to have diverged from current source, so anchoring one to source asserts
something false by design. That is a property of the assertion, and there is no
field on a released version with which to opt in or out.

Neither is there a field on a CANDIDATE with which to satisfy it. A candidate
names the contract it is a snapshot of, in its `artifactPath`, and that is the
whole of what it says about its source; the anchor resolves that `<path>:<Name>`
through `vm.getCode` and compares the record against what the compiler's own
artifact holds. A declaration that supplied the source side as a value could
point it at the same generated constant as the record and make the one check
that catches a snapshot of the wrong contract compare a value with itself —
green for any candidate whatsoever, on the broadcast path as well as in CI. It
used to be able to (rainlanguage/rain.factory.deploy#34); the field is gone.

One kind of candidate cannot be anchored at all, and SAYS so. A third party
deployment vendored as a pinned hex literal, and a data contract assembled from
generated tables, have no source file: `vm.getCode` resolves nothing, so the
anchor has no second operand rather than a disagreeing one, and the recorded
bytes are the only statement of what the code is that exists. Such a candidate
declares an `unanchorableReason` — prose, in its own declaration, saying why no
compiler produces it — and the anchor passes over it. The field carries no
BYTES, so there is still nothing for a consumer to point at the record and
nothing for the check to compare with itself; and it is REFUSED wherever the
`artifactPath` does resolve (`CandidateSourceCompiles`), so it cannot be spelled
on an ordinary candidate as a way out of the check. Nothing reads what it says.
It is held to being said.

`artifactPath` is therefore LOAD-BEARING on a candidate. It must resolve,
uniquely, to the contract the snapshot is of. A path left behind by a moved or
renamed source file now fails at the anchor — before the broadcast — where it
previously only produced a `forge verify-contract` line a human read after the
deploy. On a candidate that declares itself unanchorable it is the other way
round: resolving to nothing is the state being declared, and resolving to an
artifact is what refuses the declaration.

Uniqueness is not something `vm.getCode` reports. It resolves a BARE contract
name to whichever same-named artifact comes first, and answers rather than
reverting when several match, so a bare name anchors a candidate to a contract
that merely shares a name and nothing anywhere says which one it took. Every
candidate is therefore held to `<path>:<Name>` —
`UnqualifiedCandidateArtifactPath`, raised from the same read as
`NoDeployCandidates` — including one declaring itself unanchorable, which spells
the path of the file it would have had.

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
Neither exemption is a field a caller can set; both follow from which side of
the declaration an entry is on.

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

**The network config is generated, not compared.**
`LibRainDeploy.supportedNetworkConfigs()` is the catalogue — each network's
name, chain id, explorer url and default endpoint — `supportedNetworks()` on the
suites declaration selects which of its entries a repo deals with, and
`BuildScript.run()` writes `foundry.toml`'s `[rpc_endpoints]` and `[etherscan]`
sections and `.env.example`'s endpoint variables from that selection.
`Git is
clean` is the enforcement, the same mechanism already holding
`src/generated/`: a tree whose config has drifted from the declaration it pins
fails the job every push runs.

It reaches `foundry.toml` in two steps, because foundry refuses a filesystem
cheatcode write to the project root's own config whatever `fs_permissions` says.
`run()` stages the spliced files under `.staged-config/` and rainix's
`rainix-copy-artifacts` installs them — see [Install](#install). Reads are
allowed, which is what makes the splice possible at all, and staging removes the
hazard the direct write would have carried: nothing under `forge test` can race
a rewrite of the config every other test reads, because nothing rewrites it.

That is what a config group used to be for, and comparing is the weaker half of
it. A comparison keeps both statements, so every assertion in it is one somebody
had to think of and the prose around them drifts silently; generation leaves one
statement and there is nothing left to compare. It also settles what a
comparison could only report: every generated `[etherscan]` entry states
`chain`, so an entry carrying neither `chain` nor `url` under an alias foundry
cannot resolve — which takes verification down for every entry in the section
and not only its own — is no longer a state a consumer can be in.

The catalogue is deliberately not overridable — a network's chain id and
explorer are facts about the network, so one arrives in a consumer's config by a
version bump and by nothing else. WHICH of them a repo emits is overridable, and
through exactly one hook: `supportedNetworks()`, the same answer the broadcast
targets and the chain group forks. A declared name the catalogue says nothing
about is refused, `NetworkNotInCatalogue`, on the build that would have
generated from it.

The one thing generation cannot settle is whether a declared chain id is the one
the bound endpoint reports. That is a claim about the world rather than about
the text, and it is what `--verify` submits, so it sits in the chain group:
`testSupportedNetworkChainIdsAreBound` forks every declared network and compares
`block.chainid` against the catalogue. A wrong id there is config that resolves,
passes everything that reads the file, and verifies a deployment against the
wrong explorer.

## Config registry

`ConfigRegistry` binds an opaque `bytes32` name to ABI-encoded `bytes`: an
address, a role id, a threshold, a list of accounts, anything a deployment would
otherwise compile in. Bindings are keyed by authority: any account binds a name
under its own address, or under an authority that approved it as a delegate for
that name (`approveV4`, `revokeV4`, read by `approvedV4`); anyone reads a name
under an authority it names, and reading a name that authority has not bound
reverts rather than answering empty. The interface is `IConfigRegistryV4`. There
is no removal, no upgrade, and no way to write under an account that has not
approved the writer.

A bind is `registerV4(authority, name, valueType, value, meta)`. `valueType` is
the value's normalized ABI type as a string — `address`, `uint256`,
`(address,uint256)` — and an empty one is refused (`EmptyValueType`). The
registry stores only its hash, `keccak256(bytes(valueType))`, beside the value
and the moment it was bound, replacing all three on a rebind, and `getV4`
returns `(value, registeredAt, valueTypeHash)`. The string itself appears only
in the `Register(sender, authority, name, valueType, value)` event. The registry
never checks a type against its value and never canonicalises it: the hash is of
the exact string bound.

`meta` is optional rain metadata. When it is non-empty the same write emits
`MetaV1_2(sender, subject, meta)` (`IMetaV1_2` from `rain.metadata`), with
`sender` the caller and `subject` `keccak256(abi.encode(authority, name))`, the
same for every bind of that name under that authority. An empty `meta` emits
nothing. A non-empty `meta` without the rain meta magic number reverts
`NotRainMetaV1`, as `LibIMetaBoardV1_2.emitMeta` checks it. It is never stored,
and nothing past that prefix is validated: it lives in the logs only.

A consumer names the authority it trusts beside the name it resolves, both in
its own creation code, and gets only what that authority bound. What the
consumer then trusts, and what a contract authority must do on every network, is
in `IConfigRegistryV4`'s NatSpec under "The authority and its delegates are the
whole access control" and "Delegation is per authority and name". A delegate can
rebind the name it was approved for, so a consumer's prod tests assert
`approvedV4` is false for every retired delegate beside the true answers for the
live ones.

Bindings do not carry over from the deprecated `AddressRegistry`. Once the
registry is deployed on a network, an authority binds each name its consumers
resolve with `script/RegisterConfig.sol` (value
`cast abi-encode "f(address)" <account>`, value type `address`, and
`CONFIG_REGISTRY_NETWORKS` naming the networks it is deployed on until that is
every declared one) before those consumers deploy against it. Which names and
which authority are each consumer's to declare; until a name is bound under that
authority, its `LibConfigRegistry.resolve` reverts.

Bindings are **mutable**, because the configuration they name is. Rotating an
owning multisig is ordinary business and has to be expressible without moving
anybody's deterministic address — which a binding welded to one value forever
would make impossible, because the name is in the consumer's creation code, so a
new name means new creation code and a new address. That is the problem the
registry exists to remove, not a property worth keeping.

Mutability costs nothing already deployed. A consumer resolves a name **once**,
in its constructor, and stores the answer; it never reads the registry again. So
re-binding a name changes what the _next_ deployment resolves and nothing else,
which makes a rotation a deliberate migration rather than a silent change to
live contracts.

`LibConfigRegistry.resolve(authority, name, valueTypeHash)` is the read,
verifying the registry's code hash first, the same way `LibRainDeploy` verifies
the Zoltu factory's. It resolves a name under an authority to the bound bytes
and the moment they were bound, and reverts `ValueTypeMismatch` unless the name
is bound as the type whose hash the consumer passes, `keccak256("address")` for
an address; `resolveSafe(authority, name, valueTypeHash, minAge)` takes the same
hash. Neither decodes the value: the consumer decodes, as
`abi.decode(value, (address))` for an address. What it does with the value, and
when, is the consumer's business.

`LibRainDeploy` carries the **post-deploy** verification: on every target
network, the deployed contract must hold the value the deployment expected. It
runs after the deploy and before anything depends on it, against state the
deployment has already settled, so nothing it reads can move underneath it. The
same check run beforehand would be worth nothing against a mutable source. A
network where the deployment took something else is a burned deterministic
address, found while nothing points at it yet.

"After the deploy" is two different places, and they read two different chains.
A deploy script broadcasts nothing itself: it simulates on a fork per network
and records the transactions, which forge submits only once the script has
returned. So for as long as the script runs, the deployment is on the deploy's
own forks and nowhere else.

- **Simulation verification** is `checkResolvedAddressesOnForks`
  (`checkResolvedValuesOnForks` for a value of any type), handed the fork ids
  `deployToNetworks` returns. The only place a first-time deployment can be
  verified in the run that deploys it.
- **Confirmed-deployment verification** is `checkResolvedAddressesOnNetworks`
  (`checkResolvedValuesOnNetworks` for a value of any type), a run of its own
  that forks each network fresh, once the transactions have been submitted and
  mined. In the same script as the deploy it reads chains that have no code at
  the address yet and takes the run down before forge broadcasts anything.

Only the consumer knows where it stored what it resolved, so the consumer
supplies the reads (`abi.encodeCall(IERC5313.owner, ())` and the like) and this
library supplies the fork loop and the comparison. The address checks require
each answer to be one address word; the value checks compare the exact return
bytes, such as `abi.encode(uint256(3))` for a threshold or `abi.encode(signers)`
for an `address[]`.

## Managing the config registry

Both registries have one root authority, the same on every network:
`LibRegistryAuthority.ROOT_AUTHORITY`,
`0x0b300013CD54a8F1aC40981f80FaaA18b8Cc1E4c`. Consumers import it rather than
redefining it. The scripts below act under it only; nothing selects another.

The authority, or a delegate it approved, binds a name with
`script/RegisterConfig.sol`, signed on the Trezor that holds it: the script
binds under the root authority and, on each network, refuses a signer that is
neither the authority nor a delegate the authority approved there for the name
(`SenderNotApproved`), since the registry refuses that bind. It is run by hand
on the machine the Trezor is plugged into, never in CI: forge's own `--trezor`
signer asks the device for each signature, and the key never leaves it.

The script signs as an EOA. A Safe or timelock authority either approves that
EOA as a delegate, once per network through its own execution path
(`approveV4(name, delegate)`), after which the EOA runs the script with
`--sender` set to itself, or submits
`registerV4(authority, keccak256("<org>.<name>"), valueType, value, meta)` to
the registry itself and then runs step 3 below (`verify`), which reads under any
authority. An approval lets the delegate rebind that one name under the
authority until it is revoked (`revokeV4(name, delegate)`) on that network. An
EOA authority approves or revokes a delegate, such as a Safe, with
`script/ApproveConfigDelegate.sol` ("Approving a delegate" below).

**The name is the string consumers hash.** Consumers derive a name as
`keccak256("<org>.<name>")` — st0x resolves its token-owner Safe as
`keccak256("st0x.token-owner-safe")` — so the script takes that string and
hashes it itself. There is no `bytes32` input, so there is no other encoding to
bind under by mistake. The string must be lowercase letters and digits with
single `.` or `-` separators, starting with a letter and containing the `.`
after its `<org>`; anything else (a capital, a stray space or newline, an
already-hashed `0x…`, a name with its `<org>.` dropped) is refused, because it
is a near miss of a real name that no consumer resolves.

**The value is ABI-encoded.** The script binds ABI-encoded values only and
refuses one that is not a whole number of 32-byte words, though the registry
itself binds any non-empty bytes.

**The value type is named.** `CONFIG_REGISTRY_VALUE_TYPE` is the value's
normalized ABI type, `address` for an address, bound as given; the run refuses
it empty. `CONFIG_REGISTRY_META`, optional, is `0x` hex rain metadata emitted
with each bind; unset, the binds carry none.

It binds on every declared network by default — one binding everywhere, as the
deployment is the same everywhere — and a network already bound to the same
value as the same type is skipped, so a run that stopped partway is fixed by
running it again. The default needs the registry deployed on every declared
network: it checks the registry's code hash on each and reverts
`UnexpectedConfigRegistryCodeHash` on the first one without it, binding nothing.
While the registry is on only some networks, set `CONFIG_REGISTRY_NETWORKS` to
those.

### Before the first run

- The Trezor: unlocked, with the passphrase of the authority's wallet if it has
  one, and Trezor Suite closed (it holds the USB connection).
- Name the signer: the root authority itself, or a delegate it approved on every
  network the run binds on:

  ```sh
  export CONFIG_REGISTRY_SENDER=0x0b300013CD54a8F1aC40981f80FaaA18b8Cc1E4c # or the delegate
  ```

- Check the device answers as the signer (add
  `--mnemonic-derivation-path "<path>"` after `--trezor` inside the `$(…)` if
  the signer is not the first Ethereum account in Trezor Suite, and the same
  path as `--mnemonic-derivation-paths "<path>"` on the `forge script` commands
  below):

  ```sh
  [ "$(nix develop -c cast wallet address --trezor)" = "${CONFIG_REGISTRY_SENDER:?}" ] && echo "signer OK" || echo "NOT the signer"
  ```

- The signer needs native gas on every network it binds on.
- `cp .env.example .env` for the network endpoints. They are public and
  rate-limit; replace any that fail with your own.

### Binding a name

```sh
export CONFIG_REGISTRY_NAME=st0x.token-owner-safe
# The value, as 0x hex of its ABI encoding. For an address:
export CONFIG_REGISTRY_VALUE=$(nix develop -c cast abi-encode "f(address)" 0x...)
# Its normalized ABI type:
export CONFIG_REGISTRY_VALUE_TYPE=address
# Optional rain metadata, as 0x hex, emitted with each bind:
# export CONFIG_REGISTRY_META=0x...
# Optional, to bind on fewer networks than all of them:
# export CONFIG_REGISTRY_NETWORKS=base,arbitrum

# 1. Dry run. Executes every check and the bind itself on a fork of each
#    network, and sends nothing.
nix develop -c forge script script/RegisterConfig.sol:RegisterConfig \
  --sender "$CONFIG_REGISTRY_SENDER" --trezor --legacy

# 2. The same command with --broadcast. The device asks once per network the
#    dry run marked BIND or REBIND.
nix develop -c forge script script/RegisterConfig.sol:RegisterConfig \
  --sender "$CONFIG_REGISTRY_SENDER" --trezor --legacy --broadcast

# 3. Once every transaction is mined: reads every network fresh and fails
#    unless the name resolves to the value, as the type, under the authority
#    on each.
nix develop -c forge script script/RegisterConfig.sol:RegisterConfig --sig "verify()"
```

`--legacy` because HyperEVM's RPC rejects the fee-history ranges EIP-1559
estimation asks for. No `--rpc-url`: the script forks each network's alias
itself.

Before anything is signed the run refuses, with an error naming what is wrong: a
non-canonical name, an empty value, a value that is not a whole number of
32-byte words (a bare 20-byte address, say, rather than its ABI encoding), an
empty value type, a network the repo does not support or one named twice, a
network whose endpoint reports another chain id than the catalogue states for
it, a registry address that does not hold the pinned registry code, and a signer
that is neither the authority nor a delegate the authority approved on that
network. With `--broadcast`, forge itself is a second layer: it refuses a device
that is not the signer before sending on any network, with
`No associated wallet for addresses: [<signer>]`. A refused run signs nothing.

The dry run prints the name, its hash, the value type, its hash, the value, the
meta, the authority, the signer, the registry address and the exact calldata,
then for each network its chain id, the authority's current binding (`unbound`,
or the value, its type hash and the moment it was bound) and what will happen:
`BIND` or `REBIND` to the value as the type, or `SKIP` where the name is bound
to both already. That is the record to approve against. For each transaction the
device shows:

- **Recipient**: the registry address the dry run printed
  (`LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS`);
- **Amount**: 0;
- **Network**: the network's name or chain id, which must be one the dry run
  marked `BIND` or `REBIND`;
- **Data**: exactly the `Calldata:` line the dry run printed: `registerV4`'s
  selector `0x41f0fc94`, the authority, the name hash, the offsets of the value
  type, the value and the meta (the first is `0xa0`), then the value type's
  length and bytes, the value's length and bytes, and the meta's length and
  bytes, each padded to a multiple of 32 bytes. The device cannot decode
  `registerV4`, so it shows the raw bytes; open the full data on the device to
  compare them.

Labels vary by firmware; whatever they are called, the recipient, amount, chain
and raw calldata must each match the dry run. Reject on the device if any of
them differs.

### Approving a delegate

`script/ApproveConfigDelegate.sol` approves a delegate for one name under the
root authority, or revokes it, on every declared network by default. `approveV4`
and `revokeV4` act under their caller, so the signer is the root authority, and
the run refuses any other `--sender` (`SenderNotAuthority`) before forking. It
takes its own variables, so nothing exported for `RegisterConfig` carries over.
The Trezor setup is "Before the first run" above, with the authority as the
signer.

```sh
export CONFIG_DELEGATE_SCOPE=st0x.token-owner-safe
export CONFIG_DELEGATE_ADDRESS=0x... # the delegate, such as the Safe
# Optional: false revokes. Unset approves.
# export CONFIG_DELEGATE_APPROVED=false
# Optional, to act on fewer networks than all of them:
# export CONFIG_DELEGATE_NETWORKS=base,arbitrum

# 1. Dry run.
nix develop -c forge script script/ApproveConfigDelegate.sol:ApproveConfigDelegate \
  --sender 0x0b300013CD54a8F1aC40981f80FaaA18b8Cc1E4c --trezor --legacy

# 2. The same command with --broadcast. The device asks once per network the
#    dry run marked APPROVE or REVOKE.
nix develop -c forge script script/ApproveConfigDelegate.sol:ApproveConfigDelegate \
  --sender 0x0b300013CD54a8F1aC40981f80FaaA18b8Cc1E4c --trezor --legacy --broadcast

# 3. Once every transaction is mined: reads every network fresh and fails
#    unless the delegate is approved (or, with false, not approved) on each.
nix develop -c forge script script/ApproveConfigDelegate.sol:ApproveConfigDelegate --sig "verify()"
```

Before anything is signed the run refuses a signer that is not the authority, a
zero delegate, and every name, network, chain id and registry refusal of
`RegisterConfig`. A network already in the target state is `SKIP`, so a run that
stopped partway is fixed by running it again. An approval covers that one name;
each name the delegate binds is a run of its own.

The dry run prints the name, its hash, the authority, the delegate, the target,
the registry address and the exact calldata, then for each network its chain id,
the size of the code at the delegate (`none` where the delegate has no code
there: a Safe not yet deployed on that network), whether it is approved now, and
`APPROVE`, `REVOKE` or `SKIP`. The device shows the registry as recipient,
amount 0, the network, and the `Calldata:` line as data: `approveV4`'s selector
`0xeb34d125` or `revokeV4`'s `0x8f02e4a5`, then the name hash and the delegate.

A Safe delegate then binds by executing
`registerV4(authority, keccak256("<org>.<name>"), valueType, value, meta)` on
the registry from the Safe, on each network, and `RegisterConfig`'s `verify()`
checks the binding under the authority.

## Migration registry

`MigrationRegistry` records that a migration has been applied, when, and after
what: a write names its writer and a namespace, and that writer or a delegate it
approved for the namespace applies one migration in that line after one list —
the migration it believes ran last in that line, then the migrations in any
other line it waits on (`applyMigrationV4`, or `applyMigrationHistoryV4` for one
that already ran). Anyone reads when a given writer's line in a given namespace
applied a given one (`appliedV4`), what it applied it onto (`appliedOntoV4`),
what it applied it after (`appliedAfterV4`), which account wrote the record
(`appliedByV4`), and where that line has got to (`headV4`). A writer approves
and revokes delegates per namespace (`approveV4`, `revokeV4`, read by
`approvedV4`). There is no removal and no upgrade. The interface is
`IMigrationRegistryV4`.

The two writes differ in exactly one thing: where the recorded moment comes
from. `applyMigrationV4` stamps the block the record lands in, for a script
applying its own migration in the same atomic unit as the migration itself.
`applyMigrationHistoryV4` takes the moment as an argument, so a migration that
ran before the registry reached the chain is recordable with the time it
actually ran. They write the same record, into the same line, and make the same
refusals.

Both take a trailing `bytes meta`, as `registerV4` does: non-empty, the same
write emits `MetaV1_2(sender, subject, meta)` with `sender` the caller and
`subject` `keccak256(abi.encode(writer, namespace, migration))`; empty, nothing.
Non-empty `meta` without the rain meta magic number reverts `NotRainMetaV1`; it
is never stored, and nothing past that prefix is validated.

It exists because prod-state tests otherwise decide what to assert by reading
the **clock**. The pattern that emerges without it is a dual-state invariant —
accept either the pre- or the post-migration value until a hardcoded deadline,
and only the post value after it. That window asserts nothing during the one
period you most want to know about, every migration costs a manual refactor to
add and another to delete, and once the deadline passes CI red-lines on a date
rather than on a fact. What you actually want is "**exactly** the value implied
by the migrations that have run", which needs the chain to hold which ones have:

```solidity
if (LibMigrationRegistry.appliedV4(SAFE, NAMESPACE, MIGRATION_V2) != 0) {
    assertEq(vault.owner(), NEW_OWNER);
} else {
    assertEq(vault.owner(), OLD_OWNER);
}
```

Both branches assert exactly. Neither skips, and `appliedV4` answering zero is
an ordinary expected answer rather than a revert — it is the state of every
migration before it runs, and of every migration on a chain that never got it.

**`appliedV4` is a timestamp, not a flag.** "Which invariant applies" is
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
nothing strands the line, because the registry refuses anything not applied onto
the current head, so a writer that skipped its past migrations cannot record its
next one either.

What a reader gives up is **not** authenticity. A record is keyed by its writer
and no authority checks it, so every entry is already exactly as trustworthy as
that writer and the delegates it approved, and no more; a writer free to invent
an id was always free to invent the fact. What a reader gives up is precisely
that `appliedAt` is the block the record landed in. Everything else is kept, by
three refusals:

- **Never zero** (`ZeroTimestamp`), or the record would read back through
  `appliedV4` as no record while the head had moved and the migration could
  never be applied again.
- **Never after the block it is written in** (`FutureTimestamp`). A migration
  that has run has run, so a moment still to come is not a late record of
  anything, and a consumer measuring an interval since the migration — a cliff,
  a grace period, a rate that changes a week later — can subtract it from the
  current block without underflowing.
- **Never before the record it is applied onto** (`TimestampBeforeHead`), so a
  line's moments never go backwards along its chain and the gap between two of
  its migrations subtracts in chain order without underflowing either. The first
  migration in a line is applied onto `MIGRATION_HEAD_GENESIS`, which holds no
  record and so bounds nothing.

Equal is allowed wherever there is a neighbour. A moment may be exactly the
block it is written in, and two records may carry the same moment: two
migrations applied in one transaction share a block, and two backfilled to the
same day share a moment, so forcing them apart would demand a precision the
moments do not have. Which of them ran first is the chain, not the moments —
total order comes from `appliedOntoV4`, and the bound above only stops a record
claiming to predate the one it is chained onto.

Both writes get all three, `block.timestamp` included: a block whose timestamp
is zero is `ZeroTimestamp` on `applyMigrationV4`, which a test that warps to
zero and a chain configured from a zero genesis both reach.

**A set of applied migrations, not a high-water mark.** A mark needs a total
order consumers do not have: two migrations authored on one day collide, and one
migration split across two scripts because it landed on two networks a week
apart cannot be one comparable value at all. A set represents both exactly, and
the ordering between migrations moves into the assertion —
`appliedV4(V5) != 0 ? … : appliedV4(V4) != 0 ? … : …` — which is where the
semantic dependency actually lives.

**A head, so a step cannot be skipped or repeated.** A line — one writer's
records in one namespace — has a head: the migration it applied most recently,
or `MIGRATION_HEAD_GENESIS` if it has applied none. Both writes name the head
they are applying onto as the first entry of their list, under the writer in the
namespace being written, so a chain that never got the predecessor fails at the
moment of applying rather than diverging silently, and two migrations dispatched
at once cannot land in the wrong order. An empty list, a first entry under
anyone but the writer or in any namespace but the one being written, or one
naming anything but the head is `UnexpectedMigrationHead`. An entry after the
first in the writer's own line is `OwnPrerequisite`: the head already says
everything about that line, so every later entry names a record in another line.

```solidity
Prerequisite[] memory prerequisites = new Prerequisite[](1);
// The first migration in a line, applied in this transaction.
prerequisites[0] = Prerequisite({writer: address(this), namespace: NAMESPACE, migration: MIGRATION_HEAD_GENESIS});
LibMigrationRegistry.applyMigrationV4(address(this), NAMESPACE, MIGRATION_V1, prerequisites, "");
// Every later one names its predecessor.
prerequisites[0] = Prerequisite({writer: address(this), namespace: NAMESPACE, migration: MIGRATION_V1});
LibMigrationRegistry.applyMigrationV4(address(this), NAMESPACE, MIGRATION_V2, prerequisites, "");
// One that ran before the registry reached this chain names the moment it ran.
prerequisites[0] = Prerequisite({writer: address(this), namespace: NAMESPACE, migration: MIGRATION_V2});
LibMigrationRegistry.applyMigrationHistoryV4(address(this), NAMESPACE, MIGRATION_V3, 1750000000, prerequisites, "");
```

Each record keeps that first entry, which `appliedOntoV4` reads back, so a line
is a chain in storage rather than a set of moments to sort: from `headV4`, each
answer names the record before it, down to `MIGRATION_HEAD_GENESIS`. That chain
is the order the migrations ran in whatever moments the records carry.

Genesis is deliberately **not zero**. Zero is what an uninitialised `bytes32`
constant reads as, and a zero genesis would make a mis-set predecessor constant
a _successful_ first application on any line that happens to be empty — the
state of every chain that has not been migrated yet, which is exactly where such
a mistake is most likely. A nonzero genesis makes it a revert everywhere.

The head does **not** replace the per-migration refusal, and both are kept.
Re-applying a migration whose successor has landed names a head that matches
perfectly; without `MigrationAlreadyApplied` it would drag the head backwards
and overwrite the original timestamp, which is a record un-happening. The two
answer different questions — the head is _where in the sequence_, the record is
_whether at all_.

**A namespace is a line within a writer.** One key writes for several repos —
the CI deploy key and the token-owner Safe each broadcast migrations for more
than one — and every repo keeps its own migration history. Under the writer
alone those histories would land in one line with one head: a migration in one
repo would name, as its head, whatever the last migration in some other repo
was, every dispatch across the repos would contend on one compare-and-set, and a
stalled line in one repo would hold the head for all of them. So records are
keyed by `(writer, namespace, migration)`, with a head per writer and namespace,
and the same key keeps one line per repo. A namespace is an opaque `bytes32` the
repo declares beside its migration ids, one named constant per repo; the
registry refuses only zero (`ZeroNamespace`), on every read and on every write
by the writer itself (any other caller is `NotApproved` first, since no approval
names zero), for the same reason it refuses the zero writer. There is no plain
line outside the namespaces: every write names one, and the writer's other
namespaces are other lines, which a write may wait on exactly as it waits on
another writer's.

**A migration may wait on migrations in other lines.** Every entry after the
head in the list of `Prerequisite { writer, namespace, migration }` is one, and
both writes check them in two passes. The first refuses an entry with a zero key
as a read would (`ZeroWriter`, `ZeroNamespace`, `ZeroMigration`,
`GenesisMigration`), and one in the line being written (`OwnPrerequisite`). Only
then does the second refuse with
`PrerequisiteNotApplied(writer, namespace, migration)` for the first entry whose
record does not exist on this registry. The head alone is a migration that waits
on nothing else. A dependent script names the migration it is waiting on as a
fact the registry checks, instead of re-deriving the other script's post-state,
and the head still orders its own line exactly as before.

```solidity
// Lands only once FLEET_SAFE has recorded FLEET_UPGRADE in FLEET_NAMESPACE;
// refused with `PrerequisiteNotApplied(FLEET_SAFE, FLEET_NAMESPACE, FLEET_UPGRADE)`
// until then.
Prerequisite[] memory prerequisites = new Prerequisite[](2);
prerequisites[0] = Prerequisite({writer: address(this), namespace: NAMESPACE, migration: MIGRATION_V2});
prerequisites[1] = Prerequisite({writer: FLEET_SAFE, namespace: FLEET_NAMESPACE, migration: FLEET_UPGRADE});
LibMigrationRegistry.applyMigrationV4(address(this), NAMESPACE, MIGRATION_V3, prerequisites, "");
```

The list is the record, and `appliedAfterV4` reads it back exactly as the write
gave it: the head under the writer's own line first, then the prerequisites as
listed, duplicates included. A line's first migration's answer starts with
`MIGRATION_HEAD_GENESIS`, the one entry that is a head and not a record. Empty
only for a migration never applied. Within a line `appliedOntoV4` walks the
chain back to genesis; `appliedAfterV4` walks from a record to every record it
waited on, its predecessor included, so the cross-line order is on chain and not
only in the log. `Migrated` says nothing about the list: it is in the record,
not beside it. A prerequisite is an index check, not proof: it says the other
writer recorded its migration, not that the state it produced holds, and
consumers keep their pins. It bounds no moment either — a backfilled record may
carry an earlier moment than its prerequisite, because what is checked is that
the record existed when this write landed, which is chain order, and the moments
in another line are that writer's data.

The refusals and their order are specified once, on
`IMigrationRegistryV4.applyMigrationHistoryV4`. Duplicates are ordinary index
checks.

**The writer decides who writes its lines, and that is the whole access
control.** A write names its writer, and the registry refuses it with
`NotApproved` unless the caller is that writer or an account the writer approved
for that namespace (`approveV4`, `revokeV4`, `approvedV4`). An approval names
one namespace under the approving writer and nothing else, so a Safe and a
timelock can both write one line without either owning it, and moving a role
between them never moves where its records go. Anyone may write, but only into
their own lines or ones they were approved for, so a reader asking about the
lines of an authority it already trusts is reading something only that authority
or a delegate it approved could have written; every other writer's lines hold
unforgeable claims nobody asks about. A line is therefore only as trustworthy as
every delegate it has ever had, revoked ones included, so each record keeps the
account that wrote it (`appliedByV4`). An approved delegate can also move the
line's head onto any id, which no write can undo, so a compromised delegate can
stop every script queued against the line, leaving a new namespace as the only
way out. Approve only accounts held to the writer's own custody, and revoke
before rotating one out. Approvals cannot be enumerated on chain, only asked
about one delegate at a time, so a consumer's prod tests assert `approvedV4` is
false for every retired delegate beside the true answers for the live ones. A
namespace is not an authority: it is the writer's to name, and a record in it is
that writer's claim. The repo's scripts write under the one root authority,
`LibRegistryAuthority.ROOT_AUTHORITY`.

**An index, not proof.** The registry says which invariant applies. It does not
say the invariant holds — a multisig can act out of band and nothing here moves.
Keep both layers: this selects, codehash and bytecode pins verify. Replacing the
pins with it trades a clock-guess for a bookkeeping-guess.

`LibMigrationRegistry` is the surface — `appliedV4`, `appliedOntoV4`,
`appliedAfterV4`, `appliedByV4`, `headV4`, `approvedV4`, `approveV4`,
`revokeV4`, `applyMigrationV4` and `applyMigrationHistoryV4`, plus the `*Call`
builders for a bundle, each verifying the registry's code hash before it reads
or writes, and the pure `onto`, which builds the head-only list. There is
deliberately **no broadcast runner**: the dominant real shape is a Safe
executing a bundle that never broadcasts, and such a script appends the
`applyMigrationV4Call` output to the bundle it is already emitting, which makes
the record atomic with the migration it describes.

## Managing the migration registry

`script/ApproveMigrationDelegate.sol` approves a delegate to write one
namespace's line under the root authority, or revokes it, on every declared
network by default. `approveV4` and `revokeV4` act under their caller, so the
signer is the root authority, and the run refuses any other `--sender`
(`SenderNotAuthority`) before forking. The namespace is the string the consumer
hashes, refused unless canonical as a config name is. Everything else — the
Trezor setup, the refusals, the dry run's record and `SKIP` — is "Approving a
delegate" above, with the migration registry as the recipient.

```sh
export MIGRATION_DELEGATE_SCOPE=st0x.deploy
export MIGRATION_DELEGATE_ADDRESS=0x... # the delegate, such as a Safe or timelock
# Optional: false revokes. Unset approves.
# export MIGRATION_DELEGATE_APPROVED=false
# Optional, to act on fewer networks than all of them:
# export MIGRATION_DELEGATE_NETWORKS=base,arbitrum

# 1. Dry run.
nix develop -c forge script script/ApproveMigrationDelegate.sol:ApproveMigrationDelegate \
  --sender 0x0b300013CD54a8F1aC40981f80FaaA18b8Cc1E4c --trezor --legacy

# 2. The same command with --broadcast.
nix develop -c forge script script/ApproveMigrationDelegate.sol:ApproveMigrationDelegate \
  --sender 0x0b300013CD54a8F1aC40981f80FaaA18b8Cc1E4c --trezor --legacy --broadcast

# 3. Once every transaction is mined.
nix develop -c forge script script/ApproveMigrationDelegate.sol:ApproveMigrationDelegate --sig "verify()"
```

The device shows `approveV4`'s selector `0xeb34d125` or `revokeV4`'s
`0x8f02e4a5`, then the namespace hash and the delegate. An approval covers that
one namespace; each delegate is a run of its own.

## Deploying, and then releasing

Four separate steps, in this order. Nothing automatic ever broadcasts.

1. **Deploy.** Dispatch the
   [`Manual sol artifacts`](.github/workflows/manual-sol-artifacts.yaml)
   workflow, choosing a `suite`. It runs `script/Deploy.sol` and broadcasts that
   suite to every network in `supportedNetworks()`. One suite per dispatch, so
   this repo's two registries are two dispatches. `workflow_dispatch` only: this
   is key custody and real money, and no merge or tag should be able to trigger
   it. It is idempotent — a network that already has the code is skipped — so a
   partial run is fixed by running it again rather than by unpicking anything.
2. **Cut.** Set `[external.package].version` in `foundry.toml` to the release
   version first, because `cutRelease()` freezes under that version's tag. Then
   run `nix develop -c forge script ./script/Build.sol --sig 'cutRelease()'`,
   then `nix develop -c forge script ./script/Build.sol` FOLLOWED BY
   `nix run github:rainlanguage/rainix#rainix-static -- install-staged-config`,
   and open the release PR. Its CI checks the newly released suites on chain, so
   merge it only once step 1 has landed on every supported network. A release
   freezes every contract the release before it froze, unless
   `Build.retiredContracts()` lists it: `testNoReleaseDropsAContract` refuses
   any other drop. Retiring a contract is moving it from `generatedContracts()`
   to `retiredContracts()`, as `AddressRegistry` was.
3. **Verify.** `RegistryDeployVerifyTest` passes only once every **released**
   suite is live on every supported network, with the code that release froze.
4. **Tag.** Push a `sol-v*` tag on the release PR's merge commit, the sole
   release trigger; a later commit whose candidate has moved fails the tag's
   frozen-equals-regenerated check. It verifies and publishes but never
   broadcasts, which is exactly why step 1 cannot be folded into it. The release
   mechanics are `rainix-tag-release`'s.

This is a deploy repo: it carries deployed concretes whose addresses and
codehashes consumers pin, so releases are **manual `sol-v*` tags**, not merges.
`[external.package].version` is the newest release cut into
`src/generated/<tag>/`: only the release PR that cuts that tag moves it, and an
ordinary PR does not. A release cut under this lifecycle also names the frozen
`src/generated/<tag>/` record `cutRelease()` wrote for it. Every version
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

The run fails unless the exchange answers `"status": "ok"` carrying the empty
envelope — `{"type": "default"}` with no `data`, which is what the live run on
record got. The tag alone is not enough: `"status": "ok"` is also how
Hyperliquid answers the actions that report a per-action outcome, with that
outcome, error included, nested under `data.statuses`. Either way the full
response is in the run log, and that log line is the record: Hyperliquid has no
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

**You also need `forge-std` 1.17.0 and `rain-sol-codegen` 0.1.39**, remapped as
`forge-std-1.17.0/` and `rain-sol-codegen-0.1.39/`. The published package ships
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
forge-std = "1.17.0"
rain-sol-codegen = "0.1.39"
rain-deploy = "<version>"
```

The versions have to match: the import paths are version-qualified, which is
deliberate — it is what stops a consumer's incompatible copy from silently
satisfying these imports.

`BuildScript.run()` regenerates the CONSUMING repo's own `foundry.toml` and
`.env.example`, so that repo has to allow it:

```toml
fs_permissions = [
  { access = "read", path = "./foundry.toml" },
  { access = "read", path = "./.env.example" },
  { access = "read-write", path = "./.staged-config" },
]
```

Read, not read-write, on the two generated files: foundry refuses every
filesystem cheatcode write to the project root's own `foundry.toml` — the guard
is on the path, so no `fs_permissions` grant and no spelling of the path gets
past it. `run()` therefore reads each file, splices its blocks, and writes the
result to `.staged-config/` under the same name.

What installs it is rainix's `rainix-copy-artifacts`, after
`forge script ./script/Build.sol` and before the `git diff` that fails a stale
tree. Locally:
`nix run github:rainlanguage/rainix#rainix-static -- install-staged-config`.

```sh
# .gitignore
.staged-config
```

Both files then need the markers the generated blocks are spliced between, once
each and the begin before the end. A file carrying neither is refused, naming
the file and the block, rather than having the section appended to it — which is
a duplicate key at the next forge startup:

```toml
# rain-deploy:generated:rpc_endpoints:begin
# rain-deploy:generated:rpc_endpoints:end

# rain-deploy:generated:etherscan:begin
# rain-deploy:generated:etherscan:end
```

```sh
# .env.example
# rain-deploy:generated:env:begin
# rain-deploy:generated:env:end
```

Everything outside the markers is the consumer's, and the build neither reads
nor moves it.

A repo that deploys to FEWER networks than Rain supports overrides
`supportedNetworks()` on its suites declaration, and that one answer scopes
every side: `deployNetworks()` defaults to it, the chain group forks it, and the
generated config is the catalogue entries it names. `script/Build.sol` inherits
that declaration, which is what makes it one answer — a networks hook on the
build script instead would be a second statement of the repo's set, and config
generated from it could cover networks nothing verifies. There is deliberately
nothing per verification to override either: a verification set narrower than
the one a repo broadcasts to is every release held to nothing at all on the
networks that were dropped, with no assertion left to notice.

An `[etherscan]` entry is generated for every network in that set, from the
catalogue's own facts. Whether a network HAS an Etherscan deployment is one of
them rather than anything about the repo — Robinhood (4663) is not indexed by
Etherscan v2, so its entry carries its Blockscout url and the deployment is
verified through Sourcify.

### Upgrading from 0.1.18

`DeploySuite` gains `mechanismData`, so a consumer's generated
`Lib<Contract>Released` stops compiling before its `BuildScript` can regenerate
it. In order:

1. Add `mechanismData: ""` to every entry of the generated released libs.
2. Make `view` every function of yours that calls `checkedCandidateSuites`,
   `allSuites`, `suiteNames`, `suiteByName` or `candidateSuites`, which are
   `view` now. A `pure` override of `candidateSuites` still compiles.
3. Update the moved errors. `NetworkChainIdMismatch`, `NotDeployedOnNetwork` and
   `CodeHashMismatchOnNetwork` are members of `LibRainDeploy`: refer to them as
   `LibRainDeploy.NotDeployedOnNetwork.selector` and so on, and drop their
   imports. `NotDeployedOnNetwork` and `CodeHashMismatchOnNetwork` no longer
   carry the suite. Import `ZoltuDerivationMismatch` from
   `RainDeploySuitesBase`, and `FrozenSnapshotUnreadable` and
   `FrozenSnapshotAmbiguous` from `LibRainDeploySnapshot`.
   `FrozenSnapshotsOutnumberReleases` carries an `address[]`. A code hash
   mismatch in `deployToNetworks` reverts `CodeHashMismatchOnNetwork`, or
   `NotDeployedOnNetwork` when the address holds no code, where it reverted
   `UnexpectedDeployedCodeHash`.
4. Replace the removed or re-signed internal functions and members:
   - `DerivedDeploy.deployedAddress` is `address[] deployedAddresses`, one per
     address the suite's mechanism deploys to, in the suite's address order.
   - `RainDeployVerifySnapshotBase.DEPLOYED_ADDRESS_DECLARATION` is
     `LibRainDeploySnapshot.DEPLOYED_ADDRESS_DECLARATION`.
   - `RainDeployVerifyChain.checkDeployedOnNetwork(string, DerivedDeploy)` is
     removed: call `LibRainDeploy.checkDeclaredDependencies` and
     `LibRainDeploy.checkDeployedCode` on the selected fork, or run the whole
     matrix with `checkDeployedOnNetworks(SupportedNetwork[], DeploySuite[])`.
   - `RainDeployVerifyChain.checkDeployedOnSupportedNetworks` takes
     `DeploySuite[]`, not `DerivedDeploy[]`.
   - `RainDeployVerifyChain.checkNetworkChainId(string, uint256, uint256)` is
     `LibRainDeploy.checkNetworkChainId(SupportedNetwork)`, which reads the
     selected fork's chain id.
   - `RainDeployVerifySnapshotBase.recordedDeployedAddress(string, string)` is
     `LibRainDeploySnapshot.recordedDeployedAddresses(Vm, string, string)`,
     returning the chain id and address of every declaration.
   - `RainDeployVerifySnapshotBase.withoutBlockComments` is
     `LibRainDeploySnapshot.withoutBlockComments(string)`, which takes no `Vm`.
   - `LibRainDeploy.checkDeployRequirements` is
     `LibRainDeploy.checkDeclaredDependencies`, with the same parameters.
   - `LibTimelockController.timelockInitCode` and `expectedTimelockAddress` take
     the timelock's `bytes creationCode` first, and `assertTimelockState` its
     `bytes32 bytecodeHash` first. `LibTimelockControllerDeploy.deployTimelock`
     takes both after `deployer`.
   - `LibRainDeploySnapshot.releasedImport`, `releasedImportBlock` and
     `releasedLibraryBlock` are `view`.
5. For each per-network release broadcast, or to be broadcast, to a network it
   does not record, override `extendedNetworks` to return that network as
   broadcast: declare, then broadcast. Without it the broadcast and the chain
   group refuse the release there with `ExtendedNetworkUnfrozen`. The address
   that refusal names at broadcast is what the candidate's current init data
   derives: a release already live on that network is declared with the init
   data it was broadcast with, from its `NewClone` event, not with that address.
   Then run the build and commit the record it writes under
   `src/generated/extended/` (override `extendedNetworksSpdxLicenseIdentifier`
   and `extendedNetworksCopyrightText` for a licence other than this org's): the
   broadcast and the chain group refuse a declaration it does not hold with
   `ExtendedNetworksUnrecorded`.
6. Move to the V4 migration registry. `LibMigrationRegistry.applied`,
   `appliedOnto`, `appliedAfter` and `head` are `appliedV4`, `appliedOntoV4`,
   `appliedAfterV4` and `headV4`. `applyMigration` and `applyMigrationHistory`
   are `applyMigrationV4` and `applyMigrationHistoryV4`, and take the
   `address writer` first and a trailing `bytes meta` (`""` for none);
   `applyMigrationCall` and `applyMigrationHistoryCall` are
   `applyMigrationV4Call` and `applyMigrationHistoryV4Call`, likewise.
   Delegation is `IRegistryDelegatesV2`: `approveV4`, `revokeV4` and
   `approvedV4`. Import `Prerequisite` from
   `src/interface/IMigrationRegistryV4.sol`; `IMigrationRegistryV1`,
   `IMigrationRegistryV2`, `IMigrationRegistryV3` and `IRegistryDelegatesV1`
   moved to `src/interface/deprecated/`. The registry has a new address, so
   migrations recorded in the 0.1.18 registry stay there and read as unapplied
   in V4: apply them again, with `applyMigrationHistoryV4` for one that already
   ran.
7. Regenerate: `forge script ./script/Build.sol` followed by
   `nix run github:rainlanguage/rainix#rainix-static -- install-staged-config`.

`LibRainDeploy.deployToNetworks`, `RainDeployBroadcast.deployAndBroadcast`,
`RainDeployBroadcast.broadcastSuite` and
`RainDeployVerifyChain.checkDeployedOnSupportedNetworks` take catalogue aliases
only (`NetworkNotInCatalogue`), refuse a fork reporting another chain id
(`NetworkChainIdMismatch`), and check the declared dependencies on every
network, including one the suite is already deployed on.
`RainDeployVerifyChain.checkDeployedOnNetworks` takes `SupportedNetwork` entries
as given, with no catalogue lookup, and holds each fork's chain id to its
entry's `chainId`, checking the declared dependencies likewise.
`LibRainDeploy.createForks`, `checkResolvedAddressesOnNetworks` and
`checkResolvedAddressesOnForks` take raw `[rpc_endpoints]` aliases, with no
catalogue lookup and no chain id check.

## Develop

This repo uses [nix](https://nixos.org/download.html). The default shell is the
slim `sol-shell` from [rainix](https://github.com/rainlanguage/rainix).

```sh
nix develop          # enter the shell
forge soldeer install # install deps declared in foundry.toml
forge test
```

Regenerating what this repo generates is two commands, and the second is not
optional — the first only stages the network config:

```sh
nix develop -c forge script ./script/Build.sol
nix run github:rainlanguage/rainix#rainix-static -- install-staged-config
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
