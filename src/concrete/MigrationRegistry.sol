// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {IMigrationRegistryV1, Prerequisite, MIGRATION_HEAD_GENESIS} from "../interface/IMigrationRegistryV1.sol";

/// @dev One writer's record of one migration. Written in one call, so a record
/// can never hold one half of itself.
struct MigrationRecord {
    /// The moment recorded against the migration. Zero means never applied,
    /// which no write records.
    uint256 appliedAt;
    /// The head the namespace was at when the record was written. Zero means
    /// never applied: a head is genesis or an applied id, both nonzero.
    bytes32 appliedOnto;
    /// The prerequisites the write listed, as listed. Empty for a migration
    /// that waited on nothing and for one never applied.
    Prerequisite[] prerequisites;
}

/// @title MigrationRegistry
/// @notice The whole of `IMigrationRegistryV1`: a writer applies one of its own
/// migrations onto the head it believes its namespace is at, at the moment it
/// says the migration ran, after the migrations in any namespace it names —
/// and anyone reads when a given writer applied a given migration, what it
/// applied it onto, what it applied it after, or where that writer's namespace
/// has got to.
///
/// There is deliberately nothing else. No removal, no upgrade, no pause, and no
/// authority at all — which is the difference from `AddressRegistry`, and the
/// reason nothing here is CONFIGURED at compile time. `MIGRATION_HEAD_GENESIS`
/// is a compile-time constant, but it is the same value for every consumer on
/// every chain and names nobody, so it is part of what this contract IS rather
/// than a choice welded into it.
///
/// `AddressRegistry` has a root, and a root has to be welded into the creation
/// code so it cannot be rotated, which puts it in the deterministic address.
/// That is workable there because there is one registry of names for the whole
/// organisation. It is not workable here: the account that applies a migration
/// is a different Safe, deployer or timelock for every consumer and every
/// chain, so one root would have to be all of them at once, and baking each
/// consumer's authority into the creation code would give each a different
/// address for what is meant to be one shared registry.
///
/// Keying by `msg.sender` removes the authority instead of choosing one. Anyone
/// may write, but only under themselves, so a reader asking about the namespace
/// of an authority it already trusts is reading something only that authority
/// could have written. Every other namespace holds unforgeable claims that no
/// reader asks about. With nothing to configure there is also no rollout state
/// in which this contract is inert: it does its whole job the moment it exists
/// on a chain.
///
/// A record is append-only per writer, and a head only ever moves forward onto
/// something new. Both writes refuse a migration the caller has already applied,
/// which is what makes re-running a migration fail rather than repeat, and
/// refuse one applied onto anything but the namespace's current head, which is
/// what makes a skipped or out-of-order migration fail rather than diverge.
/// There is no way to unrecord one, and no way to rewrite one — a record
/// describes something that happened, and nothing that happened stops having
/// happened.
///
/// The moment is the CALLER's on `applyMigrationHistory`, so a migration that
/// ran before this contract reached the chain is recordable with the time it
/// actually ran. The order is not the caller's: each record keeps the head it
/// was applied onto, so a namespace's records are a chain from `head` back to
/// `MIGRATION_HEAD_GENESIS` whatever moments they carry. The moments run with
/// that chain rather than against it — a record is never earlier than the one
/// it was applied onto, though it may be equal to it.
///
/// Both writes take a list of prerequisites, each a record in any namespace
/// that must already exist, and refuse the write naming the first that does
/// not. The list is kept on the record, so what a record waited on is read
/// back from it exactly as what it was applied onto is.
///
/// Neither storage mapping is `public`. `applied`, `appliedOnto`,
/// `appliedAfter` and `head` refuse the zero writer, the three record readers
/// refuse the two ids a migration can never be, and a public mapping's
/// generated getter would answer all of them with zero — which for a record is
/// "not applied" and for `head` is a value no head can ever hold, i.e. exactly
/// the silent wrong-branch this contract reverts to prevent.
contract MigrationRegistry is IMigrationRegistryV1 {
    /// Every record, namespaced by writer. A zero `appliedAt` means never
    /// applied. Not `public`: the only readers are `applied`, `appliedOnto`
    /// and `appliedAfter`, which refuse the inputs that can only be mistakes.
    mapping(address writer => mapping(bytes32 migration => MigrationRecord record)) internal sRecords;

    /// The most recent migration applied under each writer. Zero means the
    /// namespace is empty, which reads out as `MIGRATION_HEAD_GENESIS` — the
    /// only place that translation happens is `head`, so no reader and no
    /// writer can disagree about where an empty namespace is. Not `public`, for
    /// the same reason as the records: the untranslated zero is not a head.
    mapping(address writer => bytes32 head) internal sHead;

    /// @inheritdoc IMigrationRegistryV1
    /// @dev The block is the moment, so a caller that has nothing to say about
    /// when its migration ran does not have to say it.
    // slither-disable-next-line timestamp
    // forge-lint: disable-next-line(block-timestamp)
    function applyMigration(bytes32 expectedHead, bytes32 migration, Prerequisite[] calldata prerequisites) external {
        applyMigrationRecord(expectedHead, migration, block.timestamp, prerequisites);
    }

    /// @inheritdoc IMigrationRegistryV1
    function applyMigrationHistory(
        bytes32 expectedHead,
        bytes32 migration,
        uint256 appliedAt,
        Prerequisite[] calldata prerequisites
    ) external {
        applyMigrationRecord(expectedHead, migration, appliedAt, prerequisites);
    }

    /// Reached by both writes, so there is one order whichever of them
    /// supplied the moment: the caller's own arguments, then every
    /// prerequisite, then the namespace, then the record.
    ///
    /// The prerequisites sit between the arguments and the namespace because
    /// they are the caller's statement of the world its migration requires.
    /// Until that holds the record must not be written whatever the caller's
    /// head is and whether or not the caller has recorded this migration
    /// already — a record that exists while the prerequisites its script now
    /// names do not is the more alarming fact, not one to hide behind
    /// "already applied".
    /// @param expectedHead The head the caller believes its namespace is at.
    /// @param migration The migration to apply.
    /// @param appliedAt The moment to record against it.
    /// @param prerequisites The records that must exist for it to be written.
    function applyMigrationRecord(
        bytes32 expectedHead,
        bytes32 migration,
        uint256 appliedAt,
        Prerequisite[] calldata prerequisites
    ) internal {
        checkMigrationArguments(migration, appliedAt);
        checkPrerequisites(prerequisites);
        writeMigrationRecord(expectedHead, migration, appliedAt, prerequisites);
    }

    /// Refuses every prerequisite that is not a record key, in list order,
    /// before reading any of them; then refuses the first, in list order, that
    /// names a record nobody has written.
    ///
    /// Two passes rather than one, so that every malformed argument is
    /// reported before any state is read: a zero writer in the last entry is
    /// the caller's mistake to fix now, and it is reported ahead of an
    /// unapplied prerequisite in the first entry, which is a fact about the
    /// world the caller may only be able to wait for. The key check is
    /// `checkRecordKey`, so a prerequisite is refused exactly as `applied` is
    /// refused the same key.
    /// @param prerequisites The records that must exist.
    function checkPrerequisites(Prerequisite[] calldata prerequisites) internal view {
        for (uint256 i = 0; i < prerequisites.length; i++) {
            checkRecordKey(prerequisites[i].writer, prerequisites[i].migration);
        }
        // Zero is the one moment no write records, so equality is the exact
        // test for an absent record; slither reads it as a timestamp compare.
        // slither-disable-start timestamp
        for (uint256 i = 0; i < prerequisites.length; i++) {
            // slither-disable-next-line incorrect-equality
            if (sRecords[prerequisites[i].writer][prerequisites[i].migration].appliedAt == 0) {
                revert PrerequisiteNotApplied(prerequisites[i].writer, prerequisites[i].migration);
            }
        }
        // slither-disable-end timestamp
    }

    /// The refusals that describe the call alone: the two ids a migration can
    /// never be, and the one moment a record can never carry. Reached first by
    /// every write, so a malformed argument is reported before anything is
    /// read — before a prerequisite, before the namespace.
    /// @param migration The migration to apply.
    /// @param appliedAt The moment to record against it.
    function checkMigrationArguments(bytes32 migration, uint256 appliedAt) internal pure {
        // Checked before everything else, so an uninitialised id is reported as
        // the mistake it is rather than as a first record of zero.
        if (migration == bytes32(0)) {
            revert ZeroMigration();
        }
        // Genesis is a head, not a migration. Applying it would leave `sHead`
        // holding the value an empty namespace reads as, so a namespace that had
        // applied something would be at a head indistinguishable from one that
        // had applied nothing — and the next first-migration script would be
        // accepted against it.
        if (migration == MIGRATION_HEAD_GENESIS) {
            revert GenesisMigration();
        }
        // Beside the two id refusals because it is the same kind of mistake in
        // the same kind of value: an uninitialised `uint256`, refused whatever
        // namespace it arrives at and whatever block it lands in. Zero is the
        // one moment a record cannot carry — `applied` would answer it as
        // "never applied" while the head had moved and the migration could
        // never be applied again. Reached by `applyMigration` as well, in a
        // block whose timestamp is zero: a test can warp to zero and a chain
        // can be configured from a zero genesis.
        //
        // Slither flags a strict equality on anything reaching it from
        // `block.timestamp`, which `applyMigration` does. Zero is the only
        // value this refuses and the only one it can refuse, so there is no
        // window for a validator to nudge the clock across. Suppressed on this
        // comparison rather than turned off for the repo. The timestamp detector
        // flags the same comparison now that it sits in its own function with
        // nothing else for it to attach to, hence the start/end pair: only one
        // comment fits immediately above the `if`, and `forge fmt` moves a
        // trailing one inside the braces.
        // slither-disable-start timestamp
        // slither-disable-next-line incorrect-equality
        if (appliedAt == 0) {
            revert ZeroTimestamp();
        }
        // slither-disable-end timestamp
    }

    /// The refusals that describe the namespace the call arrives at and the
    /// block it lands in, then the record, then `Migrated`. Reached by every
    /// write after `checkMigrationArguments` and `checkPrerequisites`, so
    /// there is one record and one set of refusals whichever entry point
    /// supplied the moment.
    ///
    /// The refusals run from the one that describes the namespace, to the one
    /// that describes the record at its head, to the one that describes the
    /// block — which is the order in which a caller can do something about
    /// them.
    /// @param expectedHead The head the caller believes its namespace is at.
    /// @param migration The migration to apply.
    /// @param appliedAt The moment to record against it.
    /// @param prerequisites The records it was applied after, every one of
    /// which `checkPrerequisites` has found to exist.
    function writeMigrationRecord(
        bytes32 expectedHead,
        bytes32 migration,
        uint256 appliedAt,
        Prerequisite[] calldata prerequisites
    ) internal {
        // There is deliberately no zero-writer case here. `msg.sender` cannot
        // be the zero address, so the zero namespace is unreachable for writes
        // and a guard on it would be unreachable code pretending to be a check.
        // Nor is there a zero-head case: a head is either genesis or an applied
        // id, both nonzero, so a zero `expectedHead` can never match and is
        // already refused below, by an error that names the zero it was handed.

        // Checked before the head, because a migration that has already run has
        // already run whatever the head is, and that is the more useful thing to
        // say to a re-dispatched script. It is also not implied by the head
        // check: re-applying a migration whose successor has landed presents a
        // matching head, and would drag the head backwards and overwrite the
        // original record.
        MigrationRecord storage record = sRecords[msg.sender][migration];
        if (record.appliedAt != 0) {
            revert MigrationAlreadyApplied(msg.sender, migration);
        }
        bytes32 actualHead = head(msg.sender);
        if (expectedHead != actualHead) {
            revert UnexpectedMigrationHead(msg.sender, expectedHead, actualHead);
        }
        // Last of the refusals about the namespace, because it is the only one
        // that reads a RECORD rather than a key, and the record it reads is the
        // one at the head the check above has just confirmed.
        //
        // At genesis there is nothing to be before. Genesis can never be
        // applied, so the record at it is empty in every namespace forever and
        // this comparison against zero can only pass — which is the same
        // statement a genesis branch would make, made by the value itself.
        //
        // Neither the head nor its own moment is restated in the error: the
        // caller named the head, and was told above if it named the wrong one.
        uint256 headAppliedAt = sRecords[msg.sender][actualHead].appliedAt;
        if (appliedAt < headAppliedAt) {
            revert TimestampBeforeHead(appliedAt, headAppliedAt);
        }
        // Last, because it is the only refusal here that time itself resolves:
        // every other one describes something wrong with the call or with where
        // the namespace is, and this one describes a moment that has not
        // arrived yet.
        //
        // The usual hazard behind a `block.timestamp` comparison — the one the
        // static analysers flag here — is a validator nudging the clock across a
        // threshold. The nudge is available and it is harmless: a validator that
        // moves the clock forward admits a record a second earlier than it would
        // otherwise have been admitted, of a migration that has run either way,
        // and moving it backwards is not something a chain lets a proposer do.
        // So the warnings are suppressed on this one comparison rather than
        // turned off for the repo.
        //
        // Slither's is a start/end pair rather than a next-line because only one
        // comment fits immediately above the `if`, `forge fmt` moves a trailing
        // one inside the braces, and forge-lint has no pair form.
        // slither-disable-start timestamp
        // forge-lint: disable-next-line(block-timestamp)
        if (appliedAt > block.timestamp) {
            revert FutureTimestamp(appliedAt, block.timestamp);
        }
        // slither-disable-end timestamp
        record.appliedAt = appliedAt;
        record.appliedOnto = actualHead;
        // Pushed one at a time: solc does not copy a calldata array of structs
        // into storage. The record was empty, so this is the whole list.
        for (uint256 i = 0; i < prerequisites.length; i++) {
            record.prerequisites.push(prerequisites[i]);
        }
        sHead[msg.sender] = migration;
        emit Migrated(msg.sender, migration, appliedAt);
    }

    /// @inheritdoc IMigrationRegistryV1
    /// @dev All three refusals are about a caller that has not supplied what it
    /// thinks it has. None can ever be a real record: nothing originates from
    /// the zero address, and neither write records the zero id or the genesis
    /// one — so answering zero for any of them would be answering a
    /// question the caller did not mean to ask, and answering it with the value
    /// that sends it down its pre-migration branch.
    function applied(address writer, bytes32 migration) external view returns (uint256) {
        checkRecordKey(writer, migration);
        return sRecords[writer][migration].appliedAt;
    }

    /// @inheritdoc IMigrationRegistryV1
    /// @dev The same three refusals as `applied`, for the same reason and on
    /// the same key: a zero answer here reads as "never applied" exactly as a
    /// zero moment does.
    function appliedOnto(address writer, bytes32 migration) external view returns (bytes32) {
        checkRecordKey(writer, migration);
        return sRecords[writer][migration].appliedOnto;
    }

    /// @inheritdoc IMigrationRegistryV1
    /// @dev The same three refusals again: an empty answer for a key that can
    /// never hold a record would read as "waited on nothing" about a record
    /// the caller did not mean to ask for.
    function appliedAfter(address writer, bytes32 migration) external view returns (Prerequisite[] memory) {
        checkRecordKey(writer, migration);
        return sRecords[writer][migration].prerequisites;
    }

    /// Refuses the three inputs that can only be a mistake in the caller rather
    /// than a record to read. One function, so the three readers of a record
    /// and the prerequisite check cannot drift into refusing different things.
    /// @param writer The namespace being read.
    /// @param migration The migration being asked about.
    function checkRecordKey(address writer, bytes32 migration) internal pure {
        if (writer == address(0)) {
            revert ZeroWriter();
        }
        if (migration == bytes32(0)) {
            revert ZeroMigration();
        }
        if (migration == MIGRATION_HEAD_GENESIS) {
            revert GenesisMigration();
        }
    }

    /// @inheritdoc IMigrationRegistryV1
    /// @dev The zero namespace is refused rather than answered `genesis`: it is
    /// provably empty forever, so "a namespace nothing has been applied to" is a
    /// true statement about it and a false one about what the caller meant to
    /// ask, which would send a first migration at it.
    ///
    /// The empty-namespace zero is translated to genesis here and nowhere else,
    /// which is why this is one `public` function rather than a reader beside an
    /// internal helper: a write compares against exactly what a caller reads, so
    /// the two cannot drift into different ideas of where a namespace that has
    /// applied nothing is.
    ///
    /// A write reaches it as `head(msg.sender)`, which can never be the zero
    /// address, so the refusal is redundant on that path. It is one
    /// function, so it is one refusal, and the reachable path is the one it is
    /// there for.
    function head(address writer) public view returns (bytes32) {
        if (writer == address(0)) {
            revert ZeroWriter();
        }
        bytes32 storedHead = sHead[writer];
        return storedHead == bytes32(0) ? MIGRATION_HEAD_GENESIS : storedHead;
    }
}
