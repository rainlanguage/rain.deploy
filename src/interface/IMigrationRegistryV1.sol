// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @dev A migration in some writer's namespace that must already be applied
/// on this registry for a write naming it to land. It is the key `applied`
/// takes, so anything `applied` refuses to answer about is refused here.
struct Prerequisite {
    /// The namespace to read. Never the zero address.
    address writer;
    /// The migration that must have been applied under it. Never zero.
    bytes32 migration;
}

/// @title IMigrationRegistryV1
/// @notice A per-writer record of which migrations have been applied and when.
/// A writer applies one of its own migrations, naming the migrations it comes
/// after, either as applied now (`applyMigration`) or as already applied at a
/// moment it supplies (`applyMigrationHistory`); anyone reads when a given
/// writer applied a given migration (`applied`). There is no removal, no
/// upgrade and no authority beyond the writer over its own namespace, and an
/// implementation MUST NOT add any.
///
/// The two writes differ only in where the recorded moment comes from.
/// `applyMigration` records the block it lands in, for a script applying its
/// own migration in the same atomic unit as the migration. `applyMigrationHistory`
/// takes the moment as an argument, for a migration that already ran — before
/// this registry reached the chain, or before its writer started recording.
///
/// It exists so that a test can decide what to assert by reading what happened
/// on chain rather than by reading the clock: a test asserts EXACTLY the value
/// implied by the migrations that have run, in both branches, instead of
/// accepting either value until a hardcoded deadline.
///
/// ## An index, not proof
///
/// This registry says which invariant applies. It does NOT say that the
/// invariant holds: a multisig can act out of band and nothing here moves. A
/// consumer keeps both layers — this registry SELECTS which invariant applies,
/// and codehash or bytecode pins VERIFY that it holds — and an implementation
/// MUST NOT record anything about the state a migration produced, only that
/// it was applied and when.
///
/// ## A moment is data, and it is bounded
///
/// A record is namespaced by the account that wrote it and no authority checks
/// it, so every entry is exactly as trustworthy as its writer; a writer free to
/// invent a migration id is free to invent the moment. An implementation MUST
/// bound it anyway: never zero (`ZeroTimestamp`), because zero is what
/// `applied` answers for a migration nobody applied; never after the block it
/// is written in (`FutureTimestamp`), because a record says a migration HAS
/// run, and a consumer measuring an interval since it subtracts the moment
/// from the current block. Equal to the block is accepted, and two records may
/// carry the same moment.
///
/// ## Ordering is a prerequisite
///
/// Every write names the migrations it comes after, as a list of
/// `Prerequisite`s, and is refused with `PrerequisiteNotApplied` naming the
/// first one, in list order, that has not been applied on this registry. A
/// migration in the writer's own namespace — its own predecessor — is a
/// prerequisite like any other, so a chain that never got the predecessor is a
/// loud revert at the moment of applying rather than a namespace that silently
/// diverges. A migration in another writer's namespace — a cutover after a
/// fleet upgrade from a different Safe — is the same check read across
/// namespaces. An empty list is a root, and is fine.
///
/// The check reads records that already exist and stores nothing: the
/// prerequisites go to the log in `Migrated`, so an indexer can reconstruct
/// the order without the registry recording it. A prerequisite bounds no
/// moment; another namespace's moments are that writer's data, and what is
/// checked is that the record exists when this write lands.
///
/// A prerequisite is a record key and is refused as `applied` refuses one,
/// `ZeroWriter` or `ZeroMigration`: neither can name a record, and each is a
/// constant nobody set. Refused as an argument before any record is read.
///
/// ## `applied` answers WHEN, and zero still means not applied
///
/// A migration nobody applied answers zero, and that is an ANSWER rather than a
/// revert: it is the ordinary state of every migration before it runs and of
/// every migration on a chain that never got it, and it is the branch a caller
/// asserts the pre-migration state in. Nonzero says more than a flag would —
/// a cliff, a rate change or a grace period is measured from it.
///
/// ## The namespace is the writer, and that is the whole access control
///
/// A record is keyed by the account that wrote it. Anyone may write, but only
/// to their own namespace, so a reader that reads the namespace of an authority
/// it already trusts is reading something only that authority could have
/// written. A root authority would have to be welded into creation code and
/// would give every consumer a different address; keying by `msg.sender` is
/// what lets one implementation live at one deterministic address on every
/// chain. A compromised writer can lie only about its own migrations, and
/// cannot unrecord any.
///
/// ## Identity is opaque
///
/// A migration is an opaque nonzero 32-byte value. An implementation MUST NOT
/// constrain it further. The convention that suits scripts-as-migrations is
/// the hash of the script's identity, kept in a named constant beside the
/// script so a rename does not change the id it was applied under; a
/// prerequisite is that constant, imported from wherever the other script
/// keeps it.
interface IMigrationRegistryV1 {
    /// Thrown when a write is given the zero migration id, or a prerequisite
    /// naming it, and by `applied` when asked about it. The zero id is what an
    /// uninitialised `bytes32` constant reads as, and a read answering zero
    /// for it would silently send a caller down its pre-migration branch.
    error ZeroMigration();

    /// Thrown by `applied` when asked about the zero writer, and by a write
    /// given a prerequisite naming it. No transaction originates from the zero
    /// address, so its namespace is provably empty and an unset writer
    /// constant would read as pristine rather than as the mistake it is.
    error ZeroWriter();

    /// Thrown when a write would record a zero moment: `applyMigrationHistory`
    /// given zero, or `applyMigration` in a block whose timestamp is zero. A
    /// zero moment reads back through `applied` as no record at all.
    error ZeroTimestamp();

    /// Thrown when `applyMigrationHistory` is given an `appliedAt` after the
    /// timestamp of the block it is called in. A record says a migration HAS
    /// run.
    /// @param appliedAt The moment supplied.
    /// @param blockTimestamp The timestamp of the block the call landed in.
    error FutureTimestamp(uint256 appliedAt, uint256 blockTimestamp);

    /// Thrown when a writer applies a migration it has already applied, which
    /// is what makes running a migration twice structurally impossible.
    /// Checked after the prerequisites: a record that exists while the
    /// prerequisites its script now names do not is the more alarming fact.
    /// @param writer The namespace, which is the caller.
    /// @param migration The migration already applied under it.
    error MigrationAlreadyApplied(address writer, bytes32 migration);

    /// Thrown when a write names a prerequisite that has not been applied on
    /// this registry. The first such entry in list order is the one named, so
    /// a caller waiting on several is told the one it has to wait for first.
    /// It says the record does not exist, and nothing about the state the
    /// migration produced.
    /// @param writer The namespace the prerequisite named.
    /// @param migration The migration under it that has not been applied.
    error PrerequisiteNotApplied(address writer, bytes32 migration);

    /// Emitted once per record, by both writes. A migration is applied at most
    /// once per writer, so the log is the complete history of the registry.
    /// `appliedAt` is when the migration ran, which the block the entry sits
    /// in does not say; `prerequisites` is what the record was applied after,
    /// as listed, duplicates and all, which storage does not hold.
    /// @param writer The namespace, which is the caller.
    /// @param migration The migration applied.
    /// @param appliedAt The moment recorded against it.
    /// @param prerequisites The migrations it was applied after.
    event Migrated(address indexed writer, bytes32 indexed migration, uint256 appliedAt, Prerequisite[] prerequisites);

    /// Applies `migration` under the caller's namespace as having been applied
    /// in the block this call lands in, once every prerequisite is applied.
    ///
    /// For a script applying its own migration, so the record lands in the same
    /// atomic unit as the change it describes. Where they cannot be atomic,
    /// call it LAST: a record that never landed leaves a re-run possible, and a
    /// record for a migration that did not land is the harder state to get out
    /// of.
    ///
    /// Identical to `applyMigrationHistory` with `block.timestamp` as the
    /// moment: the same refusals in the same order, the same record, the same
    /// event.
    /// @param migration The migration to apply. Never zero.
    /// @param prerequisites The migrations, each under its writer, that MUST
    /// already be applied. Empty for a root.
    function applyMigration(bytes32 migration, Prerequisite[] calldata prerequisites) external;

    /// Applies `migration` under the caller's namespace as having been applied
    /// at `appliedAt`, once every prerequisite is applied.
    ///
    /// For a migration that ALREADY ran, so the record carries the moment it
    /// ran rather than the moment it was written down.
    ///
    /// The implementation MUST revert `ZeroMigration` if `migration` is zero;
    /// `ZeroTimestamp` if `appliedAt` is zero and `FutureTimestamp` if it is
    /// after `block.timestamp`; then, in list order, `ZeroWriter` or
    /// `ZeroMigration` for an entry that is not a record key and
    /// `PrerequisiteNotApplied` for one that names no record; then
    /// `MigrationAlreadyApplied` if the caller has already applied
    /// `migration`. On success it MUST record `appliedAt` against `migration`
    /// under the caller and emit `Migrated`. It MUST NOT provide any way to
    /// unrecord or move a record once written.
    /// @param migration The migration to apply. Never zero.
    /// @param appliedAt The moment `migration` was applied. Never zero, never
    /// after the block this call lands in. Not bounded by any prerequisite's
    /// moment.
    /// @param prerequisites The migrations, each under its writer, that MUST
    /// already be applied. Empty for a root.
    function applyMigrationHistory(bytes32 migration, uint256 appliedAt, Prerequisite[] calldata prerequisites) external;

    /// When `writer` applied `migration`, or zero if it never did.
    ///
    /// The implementation MUST revert `ZeroWriter` or `ZeroMigration` rather
    /// than answering about either, and MUST answer zero — not revert — for a
    /// real writer that has not applied a real migration. Zero is unambiguous
    /// because no write records a zero moment.
    /// @param writer The namespace to read. Never the zero address.
    /// @param migration The migration to ask about. Never zero.
    /// @return The moment `writer` applied `migration` at, or zero.
    function applied(address writer, bytes32 migration) external view returns (uint256);
}
