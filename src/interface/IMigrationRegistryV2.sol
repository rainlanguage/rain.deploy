// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @dev The head of a line that has never applied a migration. The first
/// migration a writer applies in a namespace names this, and every later one
/// names the migration before it.
///
/// It is deliberately NOT zero. Zero is what an uninitialised `bytes32` constant
/// reads as, and a genesis of zero would make an uninitialised predecessor
/// constant a SUCCESSFUL first application on any line that happens to be
/// empty — which is the state of every line on every chain the consumer has
/// not migrated yet, i.e. exactly where a mis-set constant is most likely and
/// most expensive. Under a nonzero genesis that same constant is a revert in
/// every line state, empty or not, for the same reason `ZeroMigration`,
/// `ZeroWriter` and `ZeroNamespace` exist: an uninitialised value is a mistake
/// to be reported, never a question to be answered.
///
/// It is one shared value rather than anything derived per writer, per
/// namespace or per consumer, so it configures nothing and cannot fragment the
/// implementation's deterministic address.
///
/// It is not a migration, and an implementation MUST refuse it as one. A head
/// holds exactly two kinds of value: an applied migration, or this. Letting a
/// migration BE this would put a line that has applied something at a head
/// indistinguishable from one that has applied nothing, which is the same
/// collapse of two distinct facts into one value that `ZeroMigration` exists to
/// refuse — the two values a head can hold that are not migrations are exactly
/// the two values a migration id may not be.
bytes32 constant MIGRATION_HEAD_GENESIS = keccak256("rain.migration-registry.head.genesis");

/// @dev One entry in the list a record was applied after. A write takes the
/// list and `appliedAfter` answers it, and they are the same list: the first
/// entry is the head the record is applied onto, under the writer in the
/// namespace it is writing, and every later entry is a record in some other
/// line the write waited on. A later entry is the key `applied` takes, so
/// anything `applied` refuses to answer about is refused as a prerequisite.
struct Prerequisite {
    /// The writer. Never the zero address; in the first entry, the caller.
    address writer;
    /// The namespace under the writer. Never zero; in the first entry, the
    /// namespace the write names.
    bytes32 namespace;
    /// The migration under them. In the first entry, the head the record is
    /// applied onto, which is `MIGRATION_HEAD_GENESIS` for the first migration
    /// in a line. In every later entry, one that must have been applied:
    /// never zero, never `MIGRATION_HEAD_GENESIS`.
    bytes32 migration;
}

/// @title IMigrationRegistryV2
/// @notice `IMigrationRegistryV1` with prerequisites and namespaces: every
/// write names the records in any line it waits on, a record answers what it
/// was applied after, and one writer keeps one line per namespace.
///
/// A record of which migrations have been applied, when and after what, keyed
/// by writer, namespace and migration, with exactly six operations: a writer
/// applies one of its own migrations in a namespace it names, after one list
/// — the head it believes that line is at, then the migrations in any line it
/// waits on — either as applied now (`applyMigration`) or as already applied
/// at a moment it supplies (`applyMigrationHistory`); anyone reads when a
/// given writer applied a given migration in a given namespace (`applied`),
/// what it applied it onto (`appliedOnto`), what it applied it after
/// (`appliedAfter`), and where a given writer's line in a given namespace
/// currently is (`head`). There is no removal, no upgrade and no authority
/// beyond the writer over its own lines, and an implementation MUST NOT add
/// any.
///
/// The two writes differ only in where the recorded moment comes from.
/// `applyMigration` records the block it lands in, for a script applying its
/// own migration in the same atomic unit as the migration.
/// `applyMigrationHistory` takes the moment as an argument, for a migration
/// that already ran — one that ran before this registry reached the chain, or
/// before its writer started recording at all.
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
/// when, and after which other records.
///
/// The timestamp is a fact about the RECORD, not about the state: it says when
/// a migration ran and nothing whatsoever about what it did. Reading it back
/// does not become proof of anything, for the same reason reading the record
/// back does not.
///
/// ## A moment is data, and it is bounded
///
/// A moment supplied by the caller is not authenticated, and nothing else in a
/// record is either. A record is keyed by the account that wrote it and no
/// authority checks it, so every entry is exactly as trustworthy as the writer
/// that wrote it: a writer free to invent a migration id is free to invent the
/// moment. An implementation MUST bound it anyway, however it arrived:
///
/// - NEVER ZERO (`ZeroTimestamp`). Zero is what `applied` answers for a
///   migration nobody applied, so a record carrying it would read back as no
///   record while the head had moved and the migration could never be applied
///   again.
/// - NEVER AFTER THE BLOCK IT IS WRITTEN IN (`FutureTimestamp`). A record says
///   a migration HAS run. `applied` therefore never answers a moment later than
///   the block asking, and a consumer whose invariant is an interval since the
///   migration — a cliff, a grace period, a rate that changes a week later —
///   subtracts it from the current block without underflowing.
/// - NEVER BEFORE THE RECORD IT IS APPLIED ONTO (`TimestampBeforeHead`). A
///   line's moments therefore never go backwards along its chain, so a
///   consumer measuring the gap between two of its migrations subtracts them
///   in chain order without underflowing either. The first migration in a
///   line is applied onto `MIGRATION_HEAD_GENESIS`, which holds no record and
///   so bounds nothing.
///
/// Nothing else constrains it, and EQUAL is accepted at both of the bounds that
/// have a neighbour: a moment may be exactly the block it is written in, and
/// two records may carry the same moment. Two migrations applied in one
/// transaction share a block and two backfilled to the same day share a
/// moment, so forcing them apart would demand a precision the moments do not
/// have. Which of them ran first is the chain, not the moments.
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
/// is what `ZeroTimestamp` is for. It refuses a caller that supplies zero, and
/// it refuses `applyMigration` in a block whose timestamp is zero — neither
/// hypothetical, because a test can `vm.warp(0)` and a chain can be configured
/// from a zero genesis.
///
/// ## The head is what makes an ordered sequence ordered
///
/// A LINE is one writer's records in one namespace, and it has a HEAD: the
/// migration most recently applied in it, or `MIGRATION_HEAD_GENESIS` if it
/// has never applied one. Every write names, as the first entry of its list,
/// the head the caller believes its line is at, and refuses to write unless
/// that is where the line actually is; on success the applied migration
/// becomes the new head.
///
/// Each record keeps that first entry with the rest of its list, and
/// `appliedOnto` reads it back. A line's records are therefore a chain in
/// storage: from `head`, each `appliedOnto` names the record before it, down
/// to `MIGRATION_HEAD_GENESIS`. That chain IS the order the migrations ran
/// in, and it is exact whatever moments the records carry.
///
/// This is what blocks a SKIPPED step. A migration script names its predecessor,
/// so a chain that never got the predecessor is a loud revert at the moment of
/// applying rather than a line that silently diverges from every other
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
/// One line on one chain is therefore ONE linear sequence, and that is a
/// consequence to design around rather than an implementation detail. Two
/// unrelated sets of migrations applied from the same account into the same
/// namespace interleave into one chain of heads, so each script's expected
/// head is whatever that account last applied there rather than whatever that
/// script's own author had in mind.
///
/// ## A namespace is a line within a writer
///
/// One key writes for several repos: a CI deploy key and a token-owner Safe
/// each broadcast migrations for more than one, and every repo keeps its own
/// migration history. Under one writer alone all of those histories would
/// land in a single line with a single head, so a migration in one repo would
/// have to name, as its head, whatever the last migration in some other repo
/// was — an ordering that means nothing — and a stalled line in one repo would
/// hold the head for all of them.
///
/// So a writer's records are keyed by a NAMESPACE as well: an opaque
/// `bytes32` the writer names on every write, with one head per writer per
/// namespace. The same key keeps one line per repo, a script's expected head
/// is the last migration in ITS line, and two repos dispatching under one key
/// contend on nothing. What a namespace is — the hash of a repo's name, a
/// fixed constant beside the migration ids — is the writer's business, exactly
/// as a migration id is, and an implementation MUST NOT constrain it beyond
/// refusing zero (`ZeroNamespace`), which is what an uninitialised constant
/// reads as and never a namespace anybody meant to name. There is no plain
/// line outside the namespaces: every write names one.
///
/// A namespace is not an authority. It is the writer's to name, and a record
/// in any namespace under a writer is that writer's claim and nobody else's,
/// exactly as trustworthy as the writer and no more. A reader that trusts a
/// writer for one namespace has said nothing about another, and asks about
/// the one it means.
///
/// ## A prerequisite is the same index, read across lines
///
/// The head orders migrations within ONE line and says nothing about any
/// other. A migration that must not run until a migration in another line has
/// — a cutover bundle from one Safe after a fleet upgrade from another, a
/// timelock's migration after a deployer EOA's, one repo's migration after
/// another repo's under the same key — is otherwise held back by the applying
/// script re-reading the other migration's post-state, or by a runbook.
///
/// Every write takes a list of `Prerequisite`s whose first entry is the head
/// under the caller in the namespace it names, and reverts
/// `PrerequisiteNotApplied` for the first entry after it whose `applied` is
/// zero. A list of the head alone is a migration that waits on nothing but its
/// own predecessor.
///
/// A prerequisite is still an index, not proof. It says the other writer
/// RECORDED its migration, not that the state that migration produced holds,
/// and it is exactly as trustworthy as that writer and no more. A consumer
/// keeps its pins. What the prerequisite removes is the dependent script
/// carrying a hand-written copy of its prerequisite's post-state read.
///
/// The list is the record, and `appliedAfter` reads it back exactly as the
/// write gave it: the head under the writer's own line first, then what it
/// waited on, as listed. Within one line `appliedOnto` walks the chain back
/// to genesis; `appliedAfter` walks from any record to every record it waited
/// on, its predecessor included, so the order across lines is on chain and
/// not only in the log. It says which records EXISTED when this one was
/// written, which is a fact about the record and nothing about the state
/// around it.
///
/// A prerequisite bounds no moment. The moments in another line are that
/// writer's data, and a bound against them would let one writer's invented
/// moment refuse another writer's record. What is checked is that the record
/// EXISTS when this write lands, which is the chain's order and not the
/// moments'; a moment supplied to `applyMigrationHistory` is bounded by the
/// caller's own line and the block, and by nothing else.
///
/// Every entry after the first is a record key in another line, and is
/// refused as `applied` refuses one: `ZeroWriter`, `ZeroNamespace`,
/// `ZeroMigration` or `GenesisMigration`, none of which can name a record and
/// each of which is a constant nobody set or set to the wrong one. One in the
/// caller's own line — the caller's own writer AND the namespace it is
/// writing — is `OwnPrerequisite`: the first entry already says everything
/// about the caller's own line, so a later own entry is redundant if applied
/// and unsatisfiable if not. The caller's other namespaces are other lines,
/// and a record in one of them is a prerequisite like any other writer's. A
/// prerequisite listed twice is checked twice and recorded twice. The first
/// entry is not a key: it is the head, which may be `MIGRATION_HEAD_GENESIS`,
/// and it is checked against the line rather than read as a record.
///
/// ## The writer is `msg.sender`, and that is the whole access control
///
/// A record is keyed by the account that wrote it. Anyone may write, but only
/// under themselves, so a reader that reads the lines of an authority it
/// already trusts is reading something only that authority could have
/// written. Records under any other writer are unforgeable garbage that no
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
/// reserves: zero, which is what an empty line holds before it is read as
/// genesis, and `MIGRATION_HEAD_GENESIS`, which is what it reads as. Neither can
/// be a migration without a head losing the ability to say whether a line
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
/// predecessor's named constant, imported, not a second spelling of it. So is
/// a prerequisite's migration: the other script's named constant, imported
/// from wherever that script keeps it. A namespace is the same kind of value
/// and follows the same convention: one named constant per repo, beside its
/// migration ids, named by every write in that repo and by every reader of
/// its line.
interface IMigrationRegistryV2 {
    /// Thrown when a write is called with the zero migration id or given a
    /// prerequisite naming it, and by `applied`, `appliedOnto` and
    /// `appliedAfter` when asked about one. The zero id is what an
    /// uninitialised `bytes32` constant reads as, and an uninitialised id is
    /// never a migration anybody meant to name. Rejected in every direction
    /// because the read is the dangerous one: answering zero would silently
    /// send a caller down its pre-migration branch, and a prerequisite answered
    /// zero would be refused as unapplied forever rather than as the mistake it
    /// is.
    ///
    /// There is no matching refusal for a zero HEAD in the first entry, and
    /// adding one would be a guard on something already impossible: a head is
    /// either `MIGRATION_HEAD_GENESIS` or an applied id, both nonzero, so a
    /// zero head can never match and is already refused by
    /// `UnexpectedMigrationHead` — which names the zero it was handed, so
    /// nothing about the mistake is lost.
    error ZeroMigration();

    /// Thrown when a write is called with `MIGRATION_HEAD_GENESIS` as the
    /// migration or given a prerequisite naming it, and by `applied`,
    /// `appliedOnto` and `appliedAfter` when asked about it. Genesis is a
    /// head, not a migration: applying it would leave a line that has
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

    /// Thrown by every read when asked about the zero writer, and by a write
    /// given a prerequisite naming it. No transaction can originate from the
    /// zero address, so every line under it is provably empty and the answer
    /// would always be "nothing applied, at genesis" — an unresolved or unset
    /// writer constant would therefore read as a pristine line rather than
    /// as the mistake it is, and as a prerequisite it would be refused as
    /// unapplied forever rather than as that mistake.
    ///
    /// There is no matching case on the writer of any write: `msg.sender` is
    /// never zero, so no line under the zero writer can be written to in the
    /// first place. A prerequisite's writer is an argument, not `msg.sender`,
    /// which is why it is checked. The first entry's writer must BE
    /// `msg.sender`, so a zero there is `UnexpectedMigrationHead` rather than
    /// this.
    error ZeroWriter();

    /// Thrown by every write when called with the zero namespace or given a
    /// prerequisite naming it, and by every read when asked about it. Zero is
    /// what an uninitialised `bytes32` constant reads as, so it is never a
    /// namespace anybody meant to name: a write into it would put a record
    /// where no reader that set its constant will look, a read of it would
    /// answer a pristine line about whatever the caller meant to ask, and a
    /// prerequisite in it would be refused as unapplied forever rather than as
    /// the mistake it is. The zero namespace is refused on the write's own
    /// argument, unlike the zero writer, because the namespace IS an argument
    /// where the writer is `msg.sender`.
    error ZeroNamespace();

    /// Thrown when a writer applies a migration it has already applied in the
    /// same namespace. This is what makes running a migration twice
    /// structurally impossible rather than a warning in a workflow dropdown
    /// asking a human not to re-dispatch it: a script consults `applied`
    /// before it acts, and this is the backstop under that consultation.
    ///
    /// Checked AFTER the head and the entries after it, so it is reached only
    /// by a write whose list holds. A re-dispatched script names the head it
    /// named the first time, which the line has since moved past, and is
    /// told so; one naming the current head is told the migration already ran.
    /// @param writer The writer, which is the caller.
    /// @param namespace The namespace the write named.
    /// @param migration The migration already applied in that line.
    error MigrationAlreadyApplied(address writer, bytes32 namespace, bytes32 migration);

    /// Thrown when the first entry of a write's list is not the head the
    /// caller's line is at, under the caller in the namespace it named: the
    /// list is empty, the entry's writer is not the caller, its namespace is
    /// not the one the write named, or its migration is not the head. Either
    /// something the caller believed had been applied has not been, or
    /// something it did not know about has been — a skipped predecessor, a
    /// concurrent dispatch that landed first, or a chain that is simply
    /// further behind than the script assumed.
    ///
    /// Checked first of everything about the list, before any entry after the
    /// head and before `MigrationAlreadyApplied`: the list is checked in the
    /// order it is written, and a script at the wrong place in its sequence is
    /// told so before anything else about it is.
    /// @param writer The writer, which is the caller.
    /// @param namespace The namespace the write named.
    /// @param expectedHead The first entry's migration, or zero for an empty
    /// list.
    /// @param actualHead The head the line is actually at.
    error UnexpectedMigrationHead(address writer, bytes32 namespace, bytes32 expectedHead, bytes32 actualHead);

    /// Thrown when a write would record a zero moment: `applyMigrationHistory`
    /// given zero, or `applyMigration` in a block whose timestamp is zero. A
    /// record IS its moment, so a zero one would read back through `applied`
    /// as no record at all, while the head moved and the migration cannot be
    /// re-applied — the worst of every branch at once. Zero is also what an
    /// uninitialised `uint256` holds, so it is refused for the same reason
    /// `ZeroMigration` is.
    error ZeroTimestamp();

    /// Thrown when `applyMigrationHistory` is given an `appliedAt` after the
    /// timestamp of the block it is called in. A record says a migration HAS
    /// run, so a moment that has not arrived is not a record of anything — and
    /// a consumer measuring an interval since the migration would be
    /// subtracting a future moment from the present one.
    /// @param appliedAt The moment supplied.
    /// @param blockTimestamp The timestamp of the block the call landed in.
    error FutureTimestamp(uint256 appliedAt, uint256 blockTimestamp);

    /// Thrown when `applyMigrationHistory` is given an `appliedAt` before the
    /// moment recorded against the head it is being applied onto. A record
    /// says its migration ran after the one before it in the chain, so an
    /// earlier moment contradicts the sequence the same call just named, and a
    /// consumer measuring the gap between two migrations would be subtracting
    /// the later moment from the earlier one.
    ///
    /// Equal is accepted. Two migrations applied in one transaction share a
    /// block, and two backfilled migrations known only to the same day share a
    /// moment; the chain is what tells those apart, so refusing them would
    /// demand a precision the moments do not have.
    ///
    /// The first migration in a line is never refused this way: it is
    /// applied onto `MIGRATION_HEAD_GENESIS`, which is a head rather than a
    /// migration and so holds no record and no moment to be before.
    ///
    /// Neither the head nor the caller is named, because both are values the
    /// caller handed in and was told about first: `msg.sender` is the
    /// writer, and a wrong head is `UnexpectedMigrationHead`.
    /// @param appliedAt The moment supplied.
    /// @param headAppliedAt The moment recorded against the head it is being
    /// applied onto.
    error TimestampBeforeHead(uint256 appliedAt, uint256 headAppliedAt);

    /// Thrown when an entry after the first of a write's list has not been
    /// applied: `applied(writer, namespace, migration)` is zero. The first
    /// such entry in list order is the one named, and nothing after it has
    /// been read, so a caller waiting on several is told about one at a time
    /// — the one it has to wait for first.
    ///
    /// Named in full because the list is the caller's and can be long: which
    /// writer's which migration in which namespace is the whole of what a
    /// caller needs to know to go and find out why it has not landed. The
    /// caller's own writer, namespace and migration are not restated: nothing
    /// about them is what refused the write.
    ///
    /// It says the record does not exist, and nothing else. A prerequisite in
    /// a line the caller does not trust, or one whose migration produced a
    /// state that has since been undone by hand, is applied all the same:
    /// this is the index, and the pins are the proof.
    /// @param writer The writer the prerequisite named.
    /// @param namespace The namespace the prerequisite named.
    /// @param migration The migration under them that has not been applied.
    error PrerequisiteNotApplied(address writer, bytes32 namespace, bytes32 migration);

    /// Thrown when an entry after the first names the caller's own line: the
    /// caller as writer, in the namespace the write named. The first entry is
    /// the caller's head and says everything about its own line; a later own
    /// entry is redundant if applied and unsatisfiable if not, so the shape is
    /// one own entry then records in other lines. The caller's other
    /// namespaces are other lines and are not refused here.
    /// @param migration The own migration named after the head.
    error OwnPrerequisite(bytes32 migration);

    /// Emitted every time a migration is applied, by both writes. A migration
    /// is applied at most once per line, so the log is the complete history
    /// of the registry and the only way to discover a record without already
    /// knowing the id.
    ///
    /// It carries no head, because the log is ordered and one line's entries
    /// in order ARE that line's chain of heads — each entry's migration is the
    /// head the next one was applied onto, and the first was applied onto
    /// `MIGRATION_HEAD_GENESIS`. It carries no list either: the list is the
    /// record, read back by `appliedAfter`.
    ///
    /// It does carry `appliedAt`, which the log does not otherwise hold: the
    /// block a log entry sits in says when the record was written, and
    /// `appliedAt` says when the migration ran.
    /// @param writer The writer, which is the caller.
    /// @param namespace The namespace the write named.
    /// @param migration The migration applied.
    /// @param appliedAt The moment recorded against it.
    event Migrated(address indexed writer, bytes32 indexed namespace, bytes32 indexed migration, uint256 appliedAt);

    /// Applies `migration` under the caller in `namespace`, after
    /// `prerequisites`, as having been applied in the block this call lands
    /// in.
    ///
    /// This is for a script applying its own migration, so the record lands in
    /// the same atomic unit as the change it describes — a Safe
    /// appends this call to the bundle it is already executing — and the two
    /// cannot land apart. Where they cannot be atomic, call it LAST: a record
    /// that never landed leaves a reader asserting the pre-migration state,
    /// which the verification layer then catches loudly, and leaves a re-run
    /// possible. A record that landed for a migration that did not is the
    /// harder state to get out of.
    ///
    /// It records the same record as `applyMigrationHistory` and makes the same
    /// refusals in the same order, against `block.timestamp` as the moment —
    /// so a block whose timestamp is zero is `ZeroTimestamp`, and the moment
    /// can never be in the future.
    /// @param namespace The line under the caller to apply in. Never zero.
    /// @param migration The migration to apply. Never zero, never
    /// `MIGRATION_HEAD_GENESIS`.
    /// @param prerequisites What `migration` is applied after, which is what
    /// `appliedAfter` will answer for it. The first entry is the caller, in
    /// `namespace`, at the head the caller believes that line is at: the
    /// migration it is applying onto, or `MIGRATION_HEAD_GENESIS` for the
    /// first migration in the line. Every later entry is a migration, under
    /// its writer in its namespace, that MUST have been applied for this
    /// write to land: none naming the zero writer, the zero namespace, the
    /// zero migration or `MIGRATION_HEAD_GENESIS`, and none in the caller's
    /// own line. The head alone for a migration that waits on nothing else.
    function applyMigration(bytes32 namespace, bytes32 migration, Prerequisite[] calldata prerequisites) external;

    /// Applies `migration` under the caller in `namespace`, after
    /// `prerequisites`, as having been applied at `appliedAt`.
    ///
    /// This is for a migration that ALREADY ran, which records the moment it ran
    /// rather than the moment it was written down.
    ///
    /// The implementation MUST make the refusals about the arguments first, in
    /// argument order: `ZeroNamespace` for `namespace`, `ZeroMigration` or
    /// `GenesisMigration` for `migration`, `ZeroTimestamp` for `appliedAt`.
    /// Then it MUST check `prerequisites` in list order:
    /// `UnexpectedMigrationHead` if the list is empty or its first entry is
    /// not the caller in `namespace` at the head that line is at; then
    /// `ZeroWriter`, `ZeroNamespace`, `ZeroMigration`, `GenesisMigration` or
    /// `OwnPrerequisite` for the first entry after the head that is not a
    /// record key in another line; then `PrerequisiteNotApplied` for the
    /// first entry after the head whose `applied` is zero. Only then does it
    /// make the refusals about the caller's record and the moment, in this
    /// order: `MigrationAlreadyApplied` if the caller has already applied
    /// `migration` in `namespace`, `TimestampBeforeHead` if `appliedAt` is
    /// before the moment recorded against the head, and `FutureTimestamp` if
    /// `appliedAt` is after `block.timestamp`. It MUST NOT provide any way to
    /// unrecord a migration, to move a head backwards, or to move a record
    /// once written. On success it MUST record `appliedAt` and
    /// `prerequisites` against `migration` in the caller's line, make
    /// `migration` that line's new head, and emit `Migrated`.
    ///
    /// The caller's own arguments are refused before anything is read, because
    /// a malformed argument is a mistake the caller can fix now and a fact
    /// about the world is not. The list is then read as written: the head says
    /// where the caller is in its own sequence, which is the first thing wrong
    /// with a skipped or re-dispatched script, and the entries after it are
    /// the caller's statement of the world its migration requires, which must
    /// hold before the caller's own record is consulted — a record that exists
    /// while the prerequisites its script now names do not is the more
    /// alarming fact of the two, not the one to hide behind "already applied".
    ///
    /// A prerequisite that has been applied stays applied, because nothing can
    /// be unrecorded. A re-dispatched script therefore passes its list as it
    /// did the first time and is told `UnexpectedMigrationHead`, the line
    /// having moved past the head it names.
    ///
    /// Nothing is returned: every part of the record is an argument the caller
    /// just handed in.
    /// @param namespace The line under the caller to apply in. Never zero.
    /// @param migration The migration to apply. Never zero, never
    /// `MIGRATION_HEAD_GENESIS`.
    /// @param appliedAt The moment `migration` was applied. Never zero, never
    /// after the block this call lands in. Not bounded by any prerequisite's
    /// moment.
    /// @param prerequisites What `migration` is applied after, in the shape
    /// `applyMigration` takes.
    function applyMigrationHistory(
        bytes32 namespace,
        bytes32 migration,
        uint256 appliedAt,
        Prerequisite[] calldata prerequisites
    ) external;

    /// When `writer` applied `migration` in `namespace`, as the moment
    /// recorded with the record. Zero if it never did.
    ///
    /// The implementation MUST revert `ZeroWriter`, `ZeroNamespace`,
    /// `ZeroMigration` or `GenesisMigration` rather than answering about any
    /// of them, and MUST answer zero — not revert — for a real line that has
    /// simply not applied a real migration.
    ///
    /// That zero is the deliberate difference from a registry whose reads revert
    /// on an unknown key. "This migration has not been applied here" is a
    /// legitimate, expected answer that a caller branches on and asserts the
    /// pre-migration state for; it is the ordinary state of every migration
    /// before it runs, and of every migration on a chain that never got it. A
    /// revert there would leave a caller with nothing to say about the state it
    /// is actually looking at, which is the whole failure this registry removes.
    ///
    /// Zero is unambiguous because no write records a zero moment, so no
    /// applied migration can present as an unapplied one. It is the same zero
    /// a write refuses a prerequisite on: a prerequisite is this read, made by
    /// the registry, with the zero answer turned into a revert.
    /// @param writer The writer to read. Never the zero address.
    /// @param namespace The line under `writer` to read. Never zero.
    /// @param migration The migration to ask about. Never zero, never
    /// `MIGRATION_HEAD_GENESIS`.
    /// @return The moment `writer` applied `migration` in `namespace` at, or
    /// zero if it has not.
    function applied(address writer, bytes32 namespace, bytes32 migration) external view returns (uint256);

    /// What `writer` applied `migration` ONTO in `namespace`: the head that
    /// line was at when the record was written, which is the first entry of
    /// `appliedAfter`. Zero if `writer` never applied `migration` there.
    ///
    /// The implementation MUST revert `ZeroWriter`, `ZeroNamespace`,
    /// `ZeroMigration` or `GenesisMigration` rather than answering about any
    /// of them, and MUST answer zero — not revert — for a real line that has
    /// simply not applied a real migration.
    ///
    /// Zero is unambiguous: a head is either `MIGRATION_HEAD_GENESIS` or an
    /// applied id, both nonzero, so zero is never something a record holds.
    ///
    /// This is what makes a line's records a chain rather than a set.
    /// Walked from `head` back, each answer names the record before it and the
    /// walk ends at `MIGRATION_HEAD_GENESIS`, which is the order the migrations
    /// ran in whatever moments they carry.
    /// @param writer The writer to read. Never the zero address.
    /// @param namespace The line under `writer` to read. Never zero.
    /// @param migration The migration to ask about. Never zero, never
    /// `MIGRATION_HEAD_GENESIS`.
    /// @return The head `writer` applied `migration` onto in `namespace`, or
    /// zero if it has not applied it there.
    function appliedOnto(address writer, bytes32 namespace, bytes32 migration) external view returns (bytes32);

    /// What `writer` applied `migration` AFTER in `namespace`: the list the
    /// write gave, exactly as given. The first entry is `writer` in
    /// `namespace` at the head it applied onto, and every later entry is a
    /// record it waited on, in the order listed, duplicates included. Never
    /// empty for an applied migration, and empty if `writer` never applied
    /// `migration` there.
    ///
    /// The implementation MUST revert `ZeroWriter`, `ZeroNamespace`,
    /// `ZeroMigration` or `GenesisMigration` rather than answering about any
    /// of them, and MUST answer empty — not revert — for a real line that has
    /// simply not applied a real migration.
    ///
    /// The head is an entry because it is something the record was applied
    /// after, and the one thing every record was: a walk from any record
    /// reaches everything it waited on through this one read. It is the one
    /// entry that may name `MIGRATION_HEAD_GENESIS`, which the first migration
    /// in a line was applied onto and which holds no record. Every other
    /// entry was applied when the record was written and nothing can be
    /// unrecorded, so every other entry names a record that exists.
    /// @param writer The writer to read. Never the zero address.
    /// @param namespace The line under `writer` to read. Never zero.
    /// @param migration The migration to ask about. Never zero, never
    /// `MIGRATION_HEAD_GENESIS`.
    /// @return The list `writer` applied `migration` after in `namespace`, as
    /// the write gave it.
    function appliedAfter(address writer, bytes32 namespace, bytes32 migration)
        external
        view
        returns (Prerequisite[] memory);

    /// Where `writer`'s line in `namespace` currently is: the migration it
    /// applied there most recently, or `MIGRATION_HEAD_GENESIS` if it has
    /// never applied one there.
    ///
    /// The implementation MUST revert `ZeroWriter` or `ZeroNamespace` rather
    /// than answering about the zero writer or the zero namespace, and MUST
    /// NEVER answer zero — an empty line is genesis, and a nonempty one is a
    /// nonzero migration id, so a zero answer could only mean the reader had
    /// reached something that is not this registry.
    ///
    /// This is a read for authoring and for diagnosis: which migration a chain
    /// is at, and therefore what the next script must name. It is NOT how a
    /// script decides that its predecessor ran — that is `applied`, per
    /// migration, because a head says only what was last, not what was ever.
    /// @param writer The writer to read. Never the zero address.
    /// @param namespace The line under `writer` to read. Never zero.
    /// @return The head of `writer`'s line in `namespace`. Never zero.
    function head(address writer, bytes32 namespace) external view returns (bytes32);
}
