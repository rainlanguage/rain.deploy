// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {MIGRATION_HEAD_GENESIS} from "./IMigrationRegistryV1.sol";

/// @title IMigrationRegistryV2
/// @notice A per-writer record of which migrations have been applied and when,
/// with exactly three operations: a writer applies one of its own migrations
/// onto the head it believes its namespace is at, at the moment it says the
/// migration ran (`applyMigration`), anyone reads when a given writer applied a
/// given migration (`applied`), and anyone reads where a given writer's
/// namespace currently is (`head`). There is no removal, no upgrade and no
/// authority beyond the writer over its own namespace, and an implementation
/// MUST NOT add any.
///
/// It exists so that a test can decide what to assert by reading what happened
/// on chain rather than by reading the clock. Without it, a test that spans a
/// migration accepts EITHER the pre-migration or the post-migration value until
/// a hardcoded deadline, which asserts nothing at all during the one window
/// where it matters most, and red-lines on a date rather than on a fact once
/// the deadline passes. With it, a test asserts EXACTLY the value implied by
/// the migrations that have run, in both branches.
///
/// ## The caller says when, within a window the implementation enforces
///
/// `appliedAt` is a parameter because the fact being recorded is that a
/// migration RAN, and the moment it ran is not in general the moment anybody
/// gets to write it down. A migration that ran before this registry reached the
/// chain, or before its writer started recording at all, has a real moment that
/// is already in the past by the time there is anywhere to put it. An
/// implementation that could only stamp its own block would offer such a writer
/// two options and no third: record a time that is false for every historical
/// migration, or record nothing — and recording nothing strands the namespace,
/// because `applyMigration` refuses anything not applied onto the current head,
/// so a writer that skipped its past migrations cannot record its next one
/// either.
///
/// What a reader gives up is NOT authenticity. A record is namespaced by the
/// account that wrote it and no authority checks it, so every entry is already
/// exactly as trustworthy as the writer that wrote it and no more — a writer
/// free to invent a migration id was always free to invent the fact. What a
/// reader gives up is precisely this: `appliedAt` is no longer the block the
/// record landed in.
///
/// Everything else a reader relied on is kept, by an implementation that MUST
/// refuse a supplied `appliedAt` outside the window a true record can occupy:
///
/// - NEVER ZERO. Zero is what `applied` answers for a migration nobody applied,
///   so a record carrying it would read back as no record while the head had
///   moved and the migration could never be applied again.
/// - NEVER AFTER THE BLOCK IT IS WRITTEN IN. A migration that has run has run,
///   so a moment still in the future is not a late record of anything — it is a
///   claim that cannot be true when it is made. `applied` therefore never
///   answers a moment that had not arrived, and a consumer whose invariant is
///   an interval since the migration — a cliff, a grace period, a rate that
///   changes a week later — can subtract it from the current block without
///   underflowing.
/// - NEVER BEFORE THE RECORD IT IS APPLIED ONTO. The head chain is the order
///   the migrations ran in, so a namespace's records read in head order are
///   non-decreasing, and "this migration ran before that one" agrees with the
///   sequence rather than contradicting it.
///
/// Equal is allowed at both ends. Two migrations applied in one transaction
/// share a block, and two backfilled migrations known only to the same day
/// share a moment; the head chain is what orders them, and forcing the
/// timestamps apart would make them carry an ordering they do not have.
///
/// So a reader still has: nonzero means applied, the value never exceeds the
/// block that wrote it, and the values along a namespace's head chain never go
/// backwards.
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
/// `appliedAt` is a fact about the RECORD, not about the state: it says when a
/// migration ran and nothing whatsoever about what it did. Reading it back does
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
/// That distinction is only sound while a real record can never BE zero, which
/// is what `ZeroTimestamp` is for.
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
/// It is also what carries the ORDER, which is why `appliedAt` is not asked to.
/// The times a writer supplies are bounded by the head chain rather than the
/// other way around: a record may not predate the one it is applied onto, so
/// the sequence the heads describe and the moments the records carry cannot
/// contradict each other.
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
///
/// `MIGRATION_HEAD_GENESIS` is one value shared with `IMigrationRegistryV1`
/// rather than a second constant of its own. It is the value that means "this
/// namespace has applied nothing", it configures nothing and names nobody, and
/// two spellings of it would be two things to keep equal.
///
/// ## Records live in the implementation that holds them
///
/// An implementation of this interface answers about its own storage and
/// nothing else, so a writer's namespace under one deployment is a different
/// namespace from its namespace under any other, and both `applied` and `head`
/// answer per deployment. A consumer reads the registry it pins.
interface IMigrationRegistryV2 {
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

    /// Thrown when `applyMigration` is given a zero `appliedAt`. A record IS
    /// its timestamp, so a zero one would read back through `applied` as no
    /// record at all, while the head moved and the migration cannot be
    /// re-applied — the worst of every branch at once. It is what an
    /// uninitialised `uint256` holds, so it is refused for the same reason
    /// `ZeroMigration` is, and refusing to write is the only outcome that
    /// leaves the namespace describing something true.
    error ZeroTimestamp();

    /// Thrown when `applyMigration` is given an `appliedAt` earlier than the
    /// record of the head it is applied onto. The head chain is the order the
    /// migrations ran in, so a record that predates the one before it in that
    /// chain contradicts the sequence it is being appended to — and a reader
    /// comparing two of a namespace's records would get an answer that
    /// disagrees with the heads.
    /// @param writer The namespace, which is the caller.
    /// @param head The head being applied onto, whose record is the floor.
    /// @param appliedAt The moment supplied.
    /// @param headAppliedAt The moment the head was applied at.
    error TimestampBeforeHead(address writer, bytes32 head, uint256 appliedAt, uint256 headAppliedAt);

    /// Thrown when `applyMigration` is given an `appliedAt` after the timestamp
    /// of the block it is called in. A record says a migration HAS run, so a
    /// moment that has not arrived is not a record of anything — and a consumer
    /// measuring an interval since the migration would be subtracting a future
    /// moment from the present one.
    /// @param appliedAt The moment supplied.
    /// @param blockTimestamp The timestamp of the block the call landed in.
    error FutureTimestamp(uint256 appliedAt, uint256 blockTimestamp);

    /// Emitted every time a migration is applied. A migration is applied at
    /// most once per writer, so the log is the complete history of the registry
    /// and the only way to discover a record without already knowing the id.
    ///
    /// It carries no head, because the log is ordered and one writer's entries
    /// in order ARE that writer's chain of heads — each entry's migration is the
    /// head the next one was applied onto, and the first was applied onto
    /// `MIGRATION_HEAD_GENESIS`.
    ///
    /// It does carry `appliedAt`, because that is the one part of a record the
    /// log does not otherwise hold: it is supplied by the caller rather than
    /// taken from the block, so the block a log entry sits in says only when the
    /// record was written and not when the migration ran.
    /// @param writer The namespace, which is the caller.
    /// @param migration The migration applied.
    /// @param appliedAt The moment recorded against it.
    event Migrated(address indexed writer, bytes32 indexed migration, uint256 appliedAt);

    /// Applies `migration` under the caller's namespace, onto `expectedHead`,
    /// as having been applied at `appliedAt`.
    ///
    /// The implementation MUST revert `ZeroMigration` if `migration` is zero,
    /// `GenesisMigration` if it is `MIGRATION_HEAD_GENESIS`, `ZeroTimestamp` if
    /// `appliedAt` is zero, `MigrationAlreadyApplied` if the caller has already
    /// applied it, `UnexpectedMigrationHead` if the caller's namespace is not at
    /// `expectedHead`, `TimestampBeforeHead` if `appliedAt` is before the record
    /// of `expectedHead`, and `FutureTimestamp` if `appliedAt` is after
    /// `block.timestamp`. It MUST NOT provide any way to unrecord a migration,
    /// to move a head backwards, or to move a record's timestamp once written.
    /// On success it MUST record `appliedAt` against `migration`, make
    /// `migration` the caller's new head, and emit `Migrated`.
    ///
    /// Nothing is returned: the new head is the `migration` just passed in and
    /// the timestamp is the `appliedAt` just passed in, so both are already in
    /// the caller's hand.
    ///
    /// There is exactly one way to write a record. A caller recording a
    /// migration as it runs passes `block.timestamp`, which is the same
    /// statement as any other `appliedAt` and gets the same three refusals; a
    /// second entry point that supplied it would be a second way to write one
    /// record, and the one thing it could express is what its argument already
    /// spells.
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
    /// @param appliedAt The moment `migration` was applied. Never zero, never
    /// after this block, never before the record of `expectedHead`.
    function applyMigration(bytes32 expectedHead, bytes32 migration, uint256 appliedAt) external;

    /// When `writer` applied `migration`, as the moment supplied with the
    /// record. Zero if it never did.
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
    /// @return The moment `writer` applied `migration` at, or zero if it has
    /// not.
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
