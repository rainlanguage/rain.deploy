// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @dev The head of a namespace that has never applied a migration. A writer's
/// first `applyMigration` names this, and every later one names the migration
/// before it.
///
/// It is deliberately NOT zero. Zero is what an uninitialised `bytes32` constant
/// reads as, and a genesis of zero would make an uninitialised predecessor
/// constant a SUCCESSFUL first application on any namespace that happens to be
/// empty — which is the state of every namespace on every chain the consumer
/// has not migrated yet, i.e. exactly where a mis-set constant is most likely
/// and most expensive. Under a nonzero genesis that same constant is a revert
/// in every namespace state, empty or not, for the same reason `ZeroMigration`
/// and `ZeroWriter` exist: an uninitialised value is a mistake to be reported,
/// never a question to be answered.
///
/// It is one shared value rather than anything derived per writer or per
/// consumer, so it configures nothing and cannot fragment the implementation's
/// deterministic address.
///
/// It is not a migration, and an implementation MUST refuse it as one. A head
/// holds exactly two kinds of value: an applied migration, or this. Letting a
/// migration BE this would put a namespace that has applied something at a head
/// indistinguishable from one that has applied nothing, which is the same
/// collapse of two distinct facts into one value that `ZeroMigration` exists to
/// refuse — the two values a head can hold that are not migrations are exactly
/// the two values a migration id may not be.
bytes32 constant MIGRATION_HEAD_GENESIS = keccak256("rain.migration-registry.head.genesis");

/// @title IMigrationRegistryV1
/// @notice A per-writer record of which migrations have been applied and when,
/// with exactly three operations: a writer applies one of its own migrations
/// onto the head it believes its namespace is at (`applyMigration`), anyone
/// reads when a given writer applied a given migration (`applied`), and anyone
/// reads where a given writer's namespace currently is (`head`). There is no
/// removal, no upgrade and no authority beyond the writer over its own
/// namespace, and an implementation MUST NOT add any.
///
/// It exists so that a test can decide what to assert by reading what happened
/// on chain rather than by reading the clock. Without it, a test that spans a
/// migration accepts EITHER the pre-migration or the post-migration value until
/// a hardcoded deadline, which asserts nothing at all during the one window
/// where it matters most, and red-lines on a date rather than on a fact once
/// the deadline passes. With it, a test asserts EXACTLY the value implied by
/// the migrations that have run, in both branches.
///
/// ## An index, not proof
///
/// This registry says which invariant applies. It does NOT say that the
/// invariant holds. A multisig can act out of band — a beacon is upgraded by
/// hand and nothing here moves — and then a reader would confidently assert the
/// wrong state.
///
/// So a consumer keeps both layers, with distinct jobs: this registry SELECTS
/// which invariant applies, and codehash or bytecode pins VERIFY that it
/// actually holds. Replacing the pins with this registry trades a clock-guess
/// for a bookkeeping-guess, which is not an improvement. An implementation MUST
/// NOT offer anything that invites it, and in particular MUST NOT record
/// anything about the state a migration produced — only that it was applied,
/// and when.
///
/// The timestamp is a fact about the RECORD, not about the state: it is the
/// block the record landed in, which the record's own log already carries, and
/// it says nothing whatsoever about what the migration did. Reading it back does
/// not become proof of anything, for the same reason reading the record back
/// does not.
///
/// ## `applied` answers WHEN, and zero still means "not applied"
///
/// `applied` is a timestamp rather than a flag because "which invariant applies"
/// is frequently "which invariant applies YET": a migration that starts a
/// vesting cliff, a rate change, a grace period. A flag forces a consumer that
/// needs the moment to go and find the log for it, or — worse — to go back to
/// the deadline constant this registry exists to delete.
///
/// A migration nobody applied answers zero, and that is an ANSWER rather than a
/// revert: it is the ordinary state of every migration before it runs and of
/// every migration on a chain that never got it, and it is the branch a caller
/// asserts the pre-migration state in. Zero and nonzero are therefore the same
/// two distinct facts a flag carried, with the nonzero case saying more.
///
/// That distinction is only sound while a real record can never BE zero, so an
/// implementation MUST refuse to write a record in a block whose timestamp is
/// zero rather than write one that reads back as no record at all. That is not a
/// hypothetical branch: a test can `vm.warp(0)`, and a chain can be configured
/// from a zero genesis.
///
/// ## The head is what makes an ordered sequence ordered
///
/// A namespace has a HEAD: the migration most recently applied under it, or
/// `MIGRATION_HEAD_GENESIS` if it has never applied one. `applyMigration` takes
/// the head the caller believes its namespace is at and refuses to write unless
/// that is where the namespace actually is; on success the applied migration
/// becomes the new head.
///
/// This is what blocks a SKIPPED step. A migration script names its predecessor,
/// so a chain that never got the predecessor is a loud revert at the moment of
/// applying rather than a namespace that silently diverges from every other
/// chain's. It is equally what blocks two migrations dispatched concurrently
/// from landing in whichever order the mempool chose: the second one names a
/// head that has moved.
///
/// It does NOT block a DUPLICATE, and `MigrationAlreadyApplied` is not
/// redundant beside it. Re-applying a migration whose successor has since
/// landed presents a head that matches perfectly, and would move the head
/// BACKWARDS and overwrite the original timestamp — a record un-happening, which
/// is the one thing this registry promises cannot occur. The two refusals answer
/// two different questions: the head is about WHERE in the sequence a caller is,
/// and the already-applied refusal is about WHETHER this particular migration
/// has run at all.
///
/// One namespace on one chain is therefore ONE linear sequence, and that is a
/// consequence to design around rather than an implementation detail. Two
/// unrelated sets of migrations applied from the same account on the same chain
/// interleave into one chain of heads, so each script's expected head is
/// whatever that account last applied rather than whatever that script's own
/// author had in mind. A consumer that wants two independent sequences applies
/// them from two accounts, which is the same lever that already decides who a
/// reader trusts.
///
/// ## The namespace is the writer, and that is the whole access control
///
/// A record is keyed by the account that wrote it. Anyone may write, but only
/// to their own namespace, so a reader that reads the namespace of an authority
/// it already trusts is reading something only that authority could have
/// written. Records under any other namespace are unforgeable garbage that no
/// reader asks for.
///
/// This is deliberately not a root authority. The account that applies a
/// migration differs per consumer, per chain and per migration — a Safe
/// executing a bundle, a deployer EOA broadcasting a script, a timelock — so a
/// single root would have to be all of them at once. It is also what lets the
/// implementation be identical for every consumer, and therefore live at one
/// deterministic address on every chain: an authority baked into creation code
/// would give every consumer a different address, which is the property this
/// registry exists inside a deterministic-deploy library to keep.
///
/// A compromised writer can therefore only lie about its own migrations, to
/// readers that have chosen to trust it. It cannot touch anybody else's record,
/// and it cannot unrecord its own.
///
/// ## Identity is opaque
///
/// A migration is an opaque 32-byte value. This interface says nothing about
/// how one is derived — hashed from a script path, a name, a counter — and an
/// implementation MUST NOT constrain it beyond the two values the head space
/// reserves: zero, which is what an empty namespace holds before it is read as
/// genesis, and `MIGRATION_HEAD_GENESIS`, which is what it reads as. Neither can
/// be a migration without a head losing the ability to say whether a namespace
/// has applied anything. Two callers agreeing on any other id is entirely their
/// business.
///
/// The convention that suits scripts-as-migrations is the hash of the script's
/// identity, e.g. `keccak256("script/20260623-upgrade-receipt-vaults.s.sol")`.
/// A date alone is not enough: two migrations authored on one day collide, and
/// consumers do author two on one day. An id is fixed at the moment it is first
/// applied, so a script renamed afterwards keeps the id it was applied under
/// rather than acquiring a new one — which is why the id belongs in a named
/// constant beside the script, not derived from a path at the call site.
///
/// A head is an id, so the same is true of the head a script names: it is the
/// predecessor's named constant, imported, not a second spelling of it.
interface IMigrationRegistryV1 {
    /// Thrown when `applyMigration` is called with the zero migration id, and
    /// by `applied` when it is asked about one. The zero id is what an
    /// uninitialised `bytes32` constant reads as, and an uninitialised id is
    /// never a migration anybody meant to name. Rejected in both directions
    /// because the read is the dangerous one: answering zero would silently
    /// send a caller down its pre-migration branch.
    ///
    /// There is no matching refusal for a zero HEAD, and adding one would be a
    /// guard on something already impossible: a head is either
    /// `MIGRATION_HEAD_GENESIS` or an applied id, both nonzero, so a zero head
    /// can never match and is already refused by `UnexpectedMigrationHead` —
    /// which names the zero it was handed, so nothing about the mistake is lost.
    error ZeroMigration();

    /// Thrown when `applyMigration` is called with `MIGRATION_HEAD_GENESIS` as
    /// the migration, and by `applied` when it is asked about it. Genesis is a
    /// head, not a migration: applying it would leave a namespace that has
    /// applied something at a head no different from one that has applied
    /// nothing, and asking `applied` about it would answer zero forever for a
    /// caller that has confused a head for a migration and will read that as
    /// its pre-migration branch.
    ///
    /// This is the same refusal as `ZeroMigration` under a different diagnosis,
    /// and they are separate errors because the mistakes are different: a zero
    /// is a constant nobody set, and this is a constant set to the wrong one of
    /// two that sit beside each other.
    error GenesisMigration();

    /// Thrown by `applied` and `head` when asked about the zero writer. No
    /// transaction can originate from the zero address, so the zero namespace is
    /// provably empty and the answer would always be "nothing applied, at
    /// genesis" — an unresolved or unset writer constant would therefore read as
    /// a pristine namespace rather than as the mistake it is.
    ///
    /// There is no matching case on `applyMigration`: `msg.sender` is never
    /// zero, so the zero namespace cannot be written to in the first place.
    error ZeroWriter();

    /// Thrown when a writer applies a migration it has already applied. This
    /// is what makes running a migration twice structurally impossible rather
    /// than a warning in a workflow dropdown asking a human not to re-dispatch
    /// it: a script consults `applied` before it acts, and this is the backstop
    /// under that consultation.
    ///
    /// Checked BEFORE the head, because it is the more specific true statement
    /// about the call and it is true whatever the head is. A re-dispatched
    /// script is told the migration already ran, rather than told the namespace
    /// has moved on and left to work out why.
    /// @param writer The namespace, which is the caller.
    /// @param migration The migration already applied under it.
    error MigrationAlreadyApplied(address writer, bytes32 migration);

    /// Thrown when a writer applies onto a head its namespace is not at. Either
    /// something the caller believed had been applied has not been, or something
    /// it did not know about has been — a skipped predecessor, a concurrent
    /// dispatch that landed first, or a chain that is simply further behind than
    /// the script assumed.
    /// @param writer The namespace, which is the caller.
    /// @param expectedHead The head the caller said it was applying onto.
    /// @param actualHead The head the namespace is actually at.
    error UnexpectedMigrationHead(address writer, bytes32 expectedHead, bytes32 actualHead);

    /// Thrown when `applyMigration` is called in a block whose timestamp is
    /// zero. A record IS its timestamp, so a zero one would read back through
    /// `applied` as no record at all, while the head moved and the migration
    /// cannot be re-applied — the worst of every branch at once. Refusing to
    /// write is the only outcome that leaves the namespace describing something
    /// true.
    error ZeroTimestamp();

    /// Emitted every time a migration is applied. A migration is applied at
    /// most once per writer, so the log is the complete history of the registry
    /// and the only way to discover a record without already knowing the id.
    ///
    /// It carries neither the head nor the timestamp because both are already
    /// there: the log is ordered, and one writer's entries in order ARE that
    /// writer's chain of heads — each entry's migration is the head the next one
    /// was applied onto, and the first was applied onto
    /// `MIGRATION_HEAD_GENESIS`. The timestamp is the block's.
    /// @param writer The namespace, which is the caller.
    /// @param migration The migration applied.
    event Migrated(address indexed writer, bytes32 indexed migration);

    /// Applies `migration` under the caller's namespace, onto `expectedHead`.
    ///
    /// The implementation MUST revert `ZeroMigration` if `migration` is zero,
    /// `GenesisMigration` if it is `MIGRATION_HEAD_GENESIS`,
    /// `MigrationAlreadyApplied` if the caller has already applied it,
    /// `UnexpectedMigrationHead` if the caller's namespace is not at
    /// `expectedHead`, and `ZeroTimestamp` if `block.timestamp` is zero. It MUST
    /// NOT provide any way to unrecord a migration or to move a head backwards.
    /// On success it MUST record the current block timestamp against
    /// `migration`, make `migration` the caller's new head, and emit `Migrated`.
    ///
    /// Nothing is returned: the new head is the `migration` just passed in and
    /// the timestamp is the block's, so both are already in the caller's hand.
    ///
    /// A caller SHOULD call this in the same atomic unit as the migration
    /// itself where it can — a Safe appends this call to the bundle it is
    /// already executing — so that the record and the change it describes
    /// cannot land apart. Where they cannot be atomic, call it LAST: a record
    /// that never landed leaves a reader asserting the pre-migration state,
    /// which the verification layer then catches loudly, and leaves a re-run
    /// possible. A record that landed for a migration that did not is the
    /// harder state to get out of.
    /// @param expectedHead The head the caller believes its namespace is at:
    /// the migration it is applying onto, or `MIGRATION_HEAD_GENESIS` for the
    /// first migration in a namespace. Never zero, which can never match.
    /// @param migration The migration to apply. Never zero, never
    /// `MIGRATION_HEAD_GENESIS`.
    function applyMigration(bytes32 expectedHead, bytes32 migration) external;

    /// When `writer` applied `migration`, as the timestamp of the block the
    /// record landed in. Zero if it never did.
    ///
    /// The implementation MUST revert `ZeroWriter`, `ZeroMigration` or
    /// `GenesisMigration` rather than answering about any of them, and MUST
    /// answer zero — not revert — for a real writer that has simply not applied
    /// a real migration.
    ///
    /// That zero is the deliberate difference from a registry whose reads revert
    /// on an unknown key. "This migration has not been applied here" is a
    /// legitimate, expected answer that a caller branches on and asserts the
    /// pre-migration state for; it is the ordinary state of every migration
    /// before it runs, and of every migration on a chain that never got it. A
    /// revert there would leave a caller with nothing to say about the state it
    /// is actually looking at, which is the whole failure this registry removes.
    ///
    /// Zero is unambiguous because `applyMigration` refuses to write a zero
    /// timestamp, so no applied migration can present as an unapplied one.
    /// @param writer The namespace to read. Never the zero address.
    /// @param migration The migration to ask about. Never zero, never
    /// `MIGRATION_HEAD_GENESIS`.
    /// @return The block timestamp `writer` applied `migration` at, or zero if
    /// it has not.
    function applied(address writer, bytes32 migration) external view returns (uint256);

    /// Where `writer`'s namespace currently is: the migration it applied most
    /// recently, or `MIGRATION_HEAD_GENESIS` if it has never applied one.
    ///
    /// The implementation MUST revert `ZeroWriter` rather than answering about
    /// the zero namespace, and MUST NEVER answer zero — an empty namespace is
    /// genesis, and a nonempty one is a nonzero migration id, so a zero answer
    /// could only mean the reader had reached something that is not this
    /// registry.
    ///
    /// This is a read for authoring and for diagnosis: which migration a chain
    /// is at, and therefore what the next script must name. It is NOT how a
    /// script decides that its predecessor ran — that is `applied`, per
    /// migration, because a head says only what was last, not what was ever.
    /// @param writer The namespace to read. Never the zero address.
    /// @return The head of `writer`'s namespace. Never zero.
    function head(address writer) external view returns (bytes32);
}
