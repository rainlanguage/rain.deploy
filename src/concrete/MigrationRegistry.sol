// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {IMigrationRegistryV3, Prerequisite, MIGRATION_HEAD_GENESIS} from "../interface/IMigrationRegistryV3.sol";

/// @dev One line's record of one migration. Written in one call, so a record
/// can never hold one half of itself.
struct MigrationRecord {
    /// The moment recorded against the migration. Zero means never applied,
    /// which no write records.
    uint256 appliedAt;
    /// The list the write gave, as given: the head it was applied onto in
    /// the line, then the prerequisites. Empty only for a migration never
    /// applied.
    Prerequisite[] appliedAfter;
    /// The account that made the write: the writer or a delegate it approved.
    /// Zero only for a migration never applied.
    address writtenBy;
}

/// @title MigrationRegistry
/// @notice The whole of `IMigrationRegistryV3`: a write applies one migration
/// into `writer`'s line, by `writer` or a delegate it approved, in a namespace
/// it names, after one list — the head it believes that line is at, then the
/// migrations in any line it names — at the moment it says the migration ran,
/// and anyone reads when a given writer's line in a given namespace applied a
/// given migration, what it applied it onto, what it applied it after, which
/// account wrote it, or where that line has got to.
///
/// There is deliberately nothing else. No removal, no upgrade, no pause, and no
/// authority but each writer's over its own lines — the reason nothing here is
/// CONFIGURED at compile time. `MIGRATION_HEAD_GENESIS` is a compile-time
/// constant, but it is the same value for every consumer on every chain and
/// names nobody, so it is part of what this contract IS rather than a choice
/// welded into it.
///
/// A root would have to be welded into the creation code so it cannot be
/// rotated, which puts it in the deterministic address. The account that
/// applies a migration is a different Safe, deployer or timelock for every
/// consumer and every chain, so one root would have to be all of them at once,
/// and baking each consumer's authority into the creation code would give each
/// a different address for what is meant to be one shared registry.
///
/// Keying by the writer removes the authority instead of choosing one. Anyone
/// may write, but only under themselves or a writer that approved them, so a
/// reader asking about the lines of an authority it already trusts is reading
/// something only that authority or its delegates could have written. Every
/// other writer's lines hold unforgeable claims that no reader asks about.
/// The namespace under the writer is the writer's to name: one key writes for
/// several repos, and each keeps its own line. With nothing to configure there
/// is also no rollout state in which this contract is inert: it does its whole
/// job the moment it exists on a chain.
///
/// A writer may approve delegates to write one of its lines (`approveV3`), so
/// several executors share one line. The line is still the writer's: only it
/// approves, and the approval lets a delegate write no other line.
///
/// A record is append-only per line, and a head only ever moves forward onto
/// something new. Both writes refuse a migration already applied in the line,
/// which is what makes re-running a migration fail rather than repeat, and
/// refuse one applied onto anything but the line's current head, which is
/// what makes a skipped or out-of-order migration fail rather than diverge.
/// There is no way to unrecord one, and no way to rewrite one — a record
/// describes something that happened, and nothing that happened stops having
/// happened.
///
/// The moment is the CALLER's on `applyMigrationHistoryV3`, so a migration that
/// ran before this contract reached the chain is recordable with the time it
/// actually ran. The order is not the caller's: each record keeps the head it
/// was applied onto, so a line's records are a chain from `headV3` back to
/// `MIGRATION_HEAD_GENESIS` whatever moments they carry. The moments run with
/// that chain rather than against it — a record is never earlier than the one
/// it was applied onto, though it may be equal to it.
///
/// Both writes take one list: the head under the writer in its namespace
/// first, then a record in any other line that must already exist, and refuse
/// the write naming the first of those that does not. The list is the record,
/// so everything a record was applied after is read back exactly as it was
/// written.
///
/// No storage mapping is `public`. `appliedV3`, `appliedOntoV3`,
/// `appliedAfterV3`, `appliedByV3` and `headV3` refuse the zero writer and the
/// zero namespace, `approvedV3` refuses those and the zero delegate, the four
/// record readers refuse the two ids a migration can never be, and a public
/// mapping's generated getter would answer all of them with zero — which for a
/// record is "not applied" and for `headV3` is a value no head can ever hold,
/// i.e. exactly the silent wrong-branch this contract reverts to prevent.
contract MigrationRegistry is IMigrationRegistryV3 {
    /// Every record, keyed by writer, namespace and migration. A zero
    /// `appliedAt` means never applied. Not `public`: the only external readers are
    /// `appliedV3`, `appliedOntoV3`, `appliedAfterV3` and `appliedByV3`, which
    /// refuse the inputs that can only be mistakes.
    mapping(address writer => mapping(bytes32 namespace => mapping(bytes32 migration => MigrationRecord record)))
        internal sRecords;

    /// The most recent migration applied in each line. Zero means the line is
    /// empty, which reads out as `MIGRATION_HEAD_GENESIS` — the only place
    /// that translation happens is `headV3`, so no reader and no writer can
    /// disagree about where an empty line is. Not `public`, for the same
    /// reason as the records: the untranslated zero is not a head.
    mapping(address writer => mapping(bytes32 namespace => bytes32 head)) internal sHead;

    /// The delegates each writer has approved for each of its lines. Not
    /// `public`: the only external reader is `approvedV3`, which refuses the zero inputs.
    mapping(address writer => mapping(bytes32 namespace => mapping(address delegate => bool))) internal sApproved;

    /// @inheritdoc IMigrationRegistryV3
    /// @dev The block is the moment, so a caller that has nothing to say about
    /// when its migration ran does not have to say it.
    // slither-disable-next-line timestamp
    // forge-lint: disable-next-line(block-timestamp)
    function applyMigrationV3(
        address writer,
        bytes32 namespace,
        bytes32 migration,
        Prerequisite[] calldata prerequisites
    ) external {
        applyMigrationRecord(writer, namespace, migration, block.timestamp, prerequisites);
    }

    /// @inheritdoc IMigrationRegistryV3
    function applyMigrationHistoryV3(
        address writer,
        bytes32 namespace,
        bytes32 migration,
        uint256 appliedAt,
        Prerequisite[] calldata prerequisites
    ) external {
        applyMigrationRecord(writer, namespace, migration, appliedAt, prerequisites);
    }

    /// @inheritdoc IMigrationRegistryV3
    function approveV3(bytes32 namespace, address delegate) external {
        checkApprovalKey(msg.sender, namespace, delegate);
        sApproved[msg.sender][namespace][delegate] = true;
        emit Approved(msg.sender, namespace, delegate);
    }

    /// @inheritdoc IMigrationRegistryV3
    function revokeV3(bytes32 namespace, address delegate) external {
        checkApprovalKey(msg.sender, namespace, delegate);
        sApproved[msg.sender][namespace][delegate] = false;
        emit Revoked(msg.sender, namespace, delegate);
    }

    /// @inheritdoc IMigrationRegistryV3
    function approvedV3(address writer, bytes32 namespace, address delegate) external view returns (bool) {
        checkApprovalKey(writer, namespace, delegate);
        return sApproved[writer][namespace][delegate];
    }

    /// Refuses the zero writer, namespace and delegate: none names an approval
    /// anybody can hold.
    /// @param writer The approving writer.
    /// @param namespace The line under the writer.
    /// @param delegate The delegate.
    function checkApprovalKey(address writer, bytes32 namespace, address delegate) internal pure {
        checkLineKey(writer, namespace);
        if (delegate == address(0)) {
            revert ZeroDelegate();
        }
    }

    /// Refuses a write whose caller is neither `writer` nor approved by it for
    /// `namespace`. The zero writer is refused first: nothing can call as it or
    /// be approved by it.
    /// @param writer The line's writer.
    /// @param namespace The line under the writer.
    function checkDelegate(address writer, bytes32 namespace) internal view {
        checkWriter(writer);
        if (msg.sender != writer && !sApproved[writer][namespace][msg.sender]) {
            revert NotApproved(writer, namespace, msg.sender);
        }
    }

    /// Reached by every write, so both share one refusal order.
    /// @param writer The line's writer: the caller, or one that approved it.
    /// @param namespace The line under the writer to apply in.
    /// @param migration The migration to apply.
    /// @param appliedAt The moment to record against it.
    /// @param prerequisites The head, then the records that must exist for it
    /// to be written.
    function applyMigrationRecord(
        address writer,
        bytes32 namespace,
        bytes32 migration,
        uint256 appliedAt,
        Prerequisite[] calldata prerequisites
    ) internal {
        checkDelegate(writer, namespace);
        checkMigrationArguments(namespace, migration, appliedAt);
        checkPrerequisites(writer, namespace, prerequisites);
        writeMigrationRecord(writer, namespace, migration, appliedAt, prerequisites);
    }

    /// The whole list, in order. The first entry is the writer's head, which
    /// may be genesis, checked against the line. Every later entry is a
    /// record key in another line: refused as `appliedV3` refuses the same key,
    /// refused if it is the writer's own line, and then, in a second pass so
    /// no record is read until every entry has been checked, refused if nobody
    /// has written it.
    /// @param writer The line's writer.
    /// @param namespace The line under the writer being written.
    /// @param prerequisites The head, then the records that must exist.
    function checkPrerequisites(address writer, bytes32 namespace, Prerequisite[] calldata prerequisites)
        internal
        view
    {
        // The first entry is the writer at the head the caller believes it is
        // at. An empty list names no head at all, so it is refused as a zero head,
        // which no line can be at; a first entry under anyone but the writer,
        // or in any namespace but the one being written, is not this line's
        // head whatever migration it names.
        bytes32 actualHead = headV3(writer, namespace);
        if (
            prerequisites.length == 0 || prerequisites[0].writer != writer || prerequisites[0].namespace != namespace
                || prerequisites[0].migration != actualHead
        ) {
            revert UnexpectedMigrationHead(
                writer,
                namespace,
                prerequisites.length == 0 ? address(0) : prerequisites[0].writer,
                prerequisites.length == 0 ? bytes32(0) : prerequisites[0].namespace,
                prerequisites.length == 0 ? bytes32(0) : prerequisites[0].migration,
                actualHead
            );
        }
        for (uint256 i = 1; i < prerequisites.length; i++) {
            checkRecordKey(prerequisites[i].writer, prerequisites[i].namespace, prerequisites[i].migration);
            if (prerequisites[i].writer == writer && prerequisites[i].namespace == namespace) {
                revert OwnPrerequisite(prerequisites[i].migration);
            }
        }
        // Zero is the one moment no write records, so equality is the exact
        // test for an absent record; slither reads it as a timestamp compare.
        // slither-disable-start timestamp
        for (uint256 i = 1; i < prerequisites.length; i++) {
            // slither-disable-next-line incorrect-equality
            if (
                sRecords[prerequisites[i].writer][prerequisites[i].namespace][prerequisites[i].migration].appliedAt == 0
            ) {
                revert PrerequisiteNotApplied(
                    prerequisites[i].writer, prerequisites[i].namespace, prerequisites[i].migration
                );
            }
        }
        // slither-disable-end timestamp
    }

    /// The refusals that describe the call alone: the zero namespace, the two
    /// ids a migration can never be, and the one moment a record can never
    /// carry. Reached by every write straight after the caller is checked,
    /// so a malformed argument is reported before a prerequisite or the line
    /// is read.
    /// @param namespace The line under `writer` to apply in.
    /// @param migration The migration to apply.
    /// @param appliedAt The moment to record against it.
    function checkMigrationArguments(bytes32 namespace, bytes32 migration, uint256 appliedAt) internal pure {
        if (namespace == bytes32(0)) {
            revert ZeroNamespace();
        }
        if (migration == bytes32(0)) {
            revert ZeroMigration();
        }
        if (migration == MIGRATION_HEAD_GENESIS) {
            revert GenesisMigration();
        }
        // Zero is the only value refused, so no clock nudge crosses it.
        // slither-disable-start timestamp
        // slither-disable-next-line incorrect-equality
        if (appliedAt == 0) {
            revert ZeroTimestamp();
        }
        // slither-disable-end timestamp
    }

    /// The refusals that describe the line the call arrives at and the block
    /// it lands in, then the record, then `Migrated`. Reached by every write
    /// after `checkMigrationArguments` and `checkPrerequisites`, so there is
    /// one record and one set of refusals whichever entry point supplied the
    /// moment.
    ///
    /// The refusals run from the one that describes the line, to the one
    /// that describes the record at its head, to the one that describes the
    /// block — which is the order in which a caller can do something about
    /// them.
    /// @param writer The line's writer, which `checkDelegate` has already
    /// refused as zero.
    /// @param namespace The line under `writer` to apply in.
    /// @param migration The migration to apply.
    /// @param appliedAt The moment to record against it.
    /// @param prerequisites The head the caller believes `writer`'s line is at,
    /// then the records it was applied after, every one of which
    /// `checkPrerequisites` has found to exist.
    function writeMigrationRecord(
        address writer,
        bytes32 namespace,
        bytes32 migration,
        uint256 appliedAt,
        Prerequisite[] calldata prerequisites
    ) internal {
        MigrationRecord storage record = sRecords[writer][namespace][migration];
        if (record.appliedAt != 0) {
            revert MigrationAlreadyApplied(writer, namespace, migration);
        }
        bytes32 actualHead = prerequisites[0].migration;
        // Genesis is never applied, so its record reads zero and this passes.
        uint256 headAppliedAt = sRecords[writer][namespace][actualHead].appliedAt;
        if (appliedAt < headAppliedAt) {
            revert TimestampBeforeHead(appliedAt, headAppliedAt);
        }
        // A forward clock nudge only admits a migration that ran either way.
        // slither-disable-start timestamp
        // forge-lint: disable-next-line(block-timestamp)
        if (appliedAt > block.timestamp) {
            revert FutureTimestamp(appliedAt, block.timestamp);
        }
        // slither-disable-end timestamp
        record.appliedAt = appliedAt;
        record.writtenBy = msg.sender;
        // Pushed one at a time: solc does not copy a calldata array of structs
        // into storage. The record was empty, so this is the whole list.
        for (uint256 i = 0; i < prerequisites.length; i++) {
            record.appliedAfter.push(prerequisites[i]);
        }
        sHead[writer][namespace] = migration;
        emit Migrated(msg.sender, writer, namespace, migration, appliedAt);
    }

    /// @inheritdoc IMigrationRegistryV3
    /// @dev All four refusals are about a caller that has not supplied what it
    /// thinks it has. None can ever be a real record: nothing originates from
    /// the zero address, no write names the zero namespace, and neither write
    /// records the zero id or the genesis one — so answering zero for any of
    /// them would be answering a question the caller did not mean to ask, and
    /// answering it with the value that sends it down its pre-migration
    /// branch.
    function appliedV3(address writer, bytes32 namespace, bytes32 migration) external view returns (uint256) {
        checkRecordKey(writer, namespace, migration);
        return sRecords[writer][namespace][migration].appliedAt;
    }

    /// @inheritdoc IMigrationRegistryV3
    /// @dev The same four refusals as `appliedV3`, for the same reason and on
    /// the same key: a zero answer here reads as "never applied" exactly as a
    /// zero moment does. The head is the first entry of the stored list, and
    /// the list is empty exactly when the record is.
    function appliedOntoV3(address writer, bytes32 namespace, bytes32 migration) external view returns (bytes32) {
        checkRecordKey(writer, namespace, migration);
        Prerequisite[] storage appliedAfterList = sRecords[writer][namespace][migration].appliedAfter;
        return appliedAfterList.length == 0 ? bytes32(0) : appliedAfterList[0].migration;
    }

    /// @inheritdoc IMigrationRegistryV3
    /// @dev The same four refusals again: an empty answer for a key that can
    /// never hold a record would read as "never applied" about a record the
    /// caller did not mean to ask for.
    function appliedAfterV3(address writer, bytes32 namespace, bytes32 migration)
        external
        view
        returns (Prerequisite[] memory)
    {
        checkRecordKey(writer, namespace, migration);
        return sRecords[writer][namespace][migration].appliedAfter;
    }

    /// @inheritdoc IMigrationRegistryV3
    /// @dev The same four refusals as `appliedV3`: a zero answer here reads as
    /// "never applied" exactly as a zero moment does.
    function appliedByV3(address writer, bytes32 namespace, bytes32 migration) external view returns (address) {
        checkRecordKey(writer, namespace, migration);
        return sRecords[writer][namespace][migration].writtenBy;
    }

    /// Refuses the zero writer. The one copy of that refusal, reached by
    /// `checkLineKey` and by `checkDelegate`, which must refuse it before
    /// `NotApproved` and before the namespace.
    /// @param writer The line's writer.
    function checkWriter(address writer) internal pure {
        if (writer == address(0)) {
            revert ZeroWriter();
        }
    }

    /// Refuses the zero writer, then the zero namespace: neither names a line.
    /// One function, so every key naming a line refuses the same two things in
    /// the same order.
    /// @param writer The line's writer.
    /// @param namespace The line under the writer.
    function checkLineKey(address writer, bytes32 namespace) internal pure {
        checkWriter(writer);
        if (namespace == bytes32(0)) {
            revert ZeroNamespace();
        }
    }

    /// Refuses the four inputs that can only be a mistake in the caller rather
    /// than a record to read. One function, so the four readers of a record
    /// and the check on every entry after the head cannot drift into refusing
    /// different things.
    /// @param writer The writer being read.
    /// @param namespace The line under the writer being read.
    /// @param migration The migration being asked about.
    function checkRecordKey(address writer, bytes32 namespace, bytes32 migration) internal pure {
        checkLineKey(writer, namespace);
        if (migration == bytes32(0)) {
            revert ZeroMigration();
        }
        if (migration == MIGRATION_HEAD_GENESIS) {
            revert GenesisMigration();
        }
    }

    /// @inheritdoc IMigrationRegistryV3
    /// @dev The zero writer and the zero namespace are refused rather than
    /// answered `genesis`: every line under the zero writer is provably empty
    /// forever, and the zero namespace is a constant nobody set, so "a line
    /// nothing has been applied to" is a true statement about either and a
    /// false one about what the caller meant to ask, which would send a first
    /// migration at it.
    ///
    /// The empty-line zero is translated to genesis here and nowhere else,
    /// which is why this is one `public` function rather than a reader beside an
    /// internal helper: a write compares against exactly what a caller reads, so
    /// the two cannot drift into different ideas of where a line that has
    /// applied nothing is.
    ///
    /// A write reaches it as `headV3(writer, namespace)`, whose writer is never
    /// the zero address (`checkDelegate` refuses it) and whose namespace
    /// `checkMigrationArguments` has already refused as zero, so both refusals
    /// are redundant on that path.
    /// It is one function, so it is one pair of refusals, and the reachable
    /// path is the one they are there for.
    function headV3(address writer, bytes32 namespace) public view returns (bytes32) {
        checkLineKey(writer, namespace);
        bytes32 storedHead = sHead[writer][namespace];
        return storedHead == bytes32(0) ? MIGRATION_HEAD_GENESIS : storedHead;
    }
}
