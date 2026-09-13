// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {IMigrationRegistryV2, Prerequisite, MIGRATION_HEAD_GENESIS} from "../interface/IMigrationRegistryV2.sol";

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
}

/// @title MigrationRegistry
/// @notice The whole of `IMigrationRegistryV2`: a writer applies one of its own
/// migrations in a namespace it names, after one list — the head it believes
/// that line is at, then the migrations in any line it names — at the moment
/// it says the migration ran, and anyone reads when a given writer applied a
/// given migration in a given namespace, what it applied it onto, what it
/// applied it after, or where that line has got to.
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
/// may write, but only under themselves, so a reader asking about the lines
/// of an authority it already trusts is reading something only that authority
/// could have written. Every other writer's lines hold unforgeable claims that
/// no reader asks about. The namespace under the writer is the writer's to
/// name: one key writes for several repos, and each keeps its own line. With
/// nothing to configure there is also no rollout state in which this contract
/// is inert: it does its whole job the moment it exists on a chain.
///
/// A record is append-only per line, and a head only ever moves forward onto
/// something new. Both writes refuse a migration the caller has already applied
/// in the line, which is what makes re-running a migration fail rather than
/// repeat, and refuse one applied onto anything but the line's current head,
/// which is what makes a skipped or out-of-order migration fail rather than
/// diverge. There is no way to unrecord one, and no way to rewrite one — a
/// record describes something that happened, and nothing that happened stops
/// having happened.
///
/// The moment is the CALLER's on `applyMigrationHistory`, so a migration that
/// ran before this contract reached the chain is recordable with the time it
/// actually ran. The order is not the caller's: each record keeps the head it
/// was applied onto, so a line's records are a chain from `head` back to
/// `MIGRATION_HEAD_GENESIS` whatever moments they carry. The moments run with
/// that chain rather than against it — a record is never earlier than the one
/// it was applied onto, though it may be equal to it.
///
/// Both writes take one list: the head under the caller in its namespace
/// first, then a record in any other line that must already exist, and refuse
/// the write naming the first of those that does not. The list is the record,
/// so everything a record was applied after is read back exactly as it was
/// written.
///
/// Neither storage mapping is `public`. `applied`, `appliedOnto`,
/// `appliedAfter` and `head` refuse the zero writer and the zero namespace,
/// the three record readers refuse the two ids a migration can never be, and
/// a public mapping's generated getter would answer all of them with zero —
/// which for a record is "not applied" and for `head` is a value no head can
/// ever hold, i.e. exactly the silent wrong-branch this contract reverts to
/// prevent.
contract MigrationRegistry is IMigrationRegistryV2 {
    /// Every record, keyed by writer, namespace and migration. A zero
    /// `appliedAt` means never applied. Not `public`: the only readers are
    /// `applied`, `appliedOnto` and `appliedAfter`, which refuse the inputs
    /// that can only be mistakes.
    mapping(address writer => mapping(bytes32 namespace => mapping(bytes32 migration => MigrationRecord record)))
        internal sRecords;

    /// The most recent migration applied in each line. Zero means the line is
    /// empty, which reads out as `MIGRATION_HEAD_GENESIS` — the only place
    /// that translation happens is `head`, so no reader and no writer can
    /// disagree about where an empty line is. Not `public`, for the same
    /// reason as the records: the untranslated zero is not a head.
    mapping(address writer => mapping(bytes32 namespace => bytes32 head)) internal sHead;

    /// @inheritdoc IMigrationRegistryV2
    /// @dev The block is the moment, so a caller that has nothing to say about
    /// when its migration ran does not have to say it.
    // slither-disable-next-line timestamp
    // forge-lint: disable-next-line(block-timestamp)
    function applyMigration(bytes32 namespace, bytes32 migration, Prerequisite[] calldata prerequisites) external {
        applyMigrationRecord(namespace, migration, block.timestamp, prerequisites);
    }

    /// @inheritdoc IMigrationRegistryV2
    function applyMigrationHistory(
        bytes32 namespace,
        bytes32 migration,
        uint256 appliedAt,
        Prerequisite[] calldata prerequisites
    ) external {
        applyMigrationRecord(namespace, migration, appliedAt, prerequisites);
    }

    /// Reached by both writes, so there is one order whichever of them
    /// supplied the moment: the caller's own arguments, then the list in
    /// order, then the record.
    /// @param namespace The line under the caller to apply in.
    /// @param migration The migration to apply.
    /// @param appliedAt The moment to record against it.
    /// @param prerequisites The head, then the records that must exist for it
    /// to be written.
    function applyMigrationRecord(
        bytes32 namespace,
        bytes32 migration,
        uint256 appliedAt,
        Prerequisite[] calldata prerequisites
    ) internal {
        checkMigrationArguments(namespace, migration, appliedAt);
        checkPrerequisites(namespace, prerequisites);
        writeMigrationRecord(namespace, migration, appliedAt, prerequisites);
    }

    /// The whole list, in order. The first entry is the caller's head, which
    /// may be genesis, checked against the line. Every later entry is a
    /// record key in another line: refused as `applied` refuses the same key,
    /// refused if it is the caller's own line, and then, in a second pass so
    /// every malformed entry is reported before the records are read, refused
    /// if nobody has written it.
    /// @param namespace The line under the caller being written.
    /// @param prerequisites The head, then the records that must exist.
    function checkPrerequisites(bytes32 namespace, Prerequisite[] calldata prerequisites) internal view {
        // The first entry is the caller at the head it believes it is at. An
        // empty list names no head at all, so it is refused as a zero head,
        // which no line can be at; a first entry under anyone but the caller,
        // or in any namespace but the one being written, is not this line's
        // head whatever migration it names.
        bytes32 actualHead = head(msg.sender, namespace);
        if (
            prerequisites.length == 0 || prerequisites[0].writer != msg.sender
                || prerequisites[0].namespace != namespace || prerequisites[0].migration != actualHead
        ) {
            revert UnexpectedMigrationHead(
                msg.sender,
                namespace,
                prerequisites.length == 0 ? bytes32(0) : prerequisites[0].namespace,
                prerequisites.length == 0 ? bytes32(0) : prerequisites[0].migration,
                actualHead
            );
        }
        for (uint256 i = 1; i < prerequisites.length; i++) {
            checkRecordKey(prerequisites[i].writer, prerequisites[i].namespace, prerequisites[i].migration);
            if (prerequisites[i].writer == msg.sender && prerequisites[i].namespace == namespace) {
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
    /// carry. Reached first by every write, so a malformed argument is
    /// reported before anything is read — before a prerequisite, before the
    /// line.
    /// @param namespace The line under the caller to apply in.
    /// @param migration The migration to apply.
    /// @param appliedAt The moment to record against it.
    function checkMigrationArguments(bytes32 namespace, bytes32 migration, uint256 appliedAt) internal pure {
        // First because it is the first argument: an uninitialised namespace
        // is reported as the mistake it is rather than as a line nobody reads.
        if (namespace == bytes32(0)) {
            revert ZeroNamespace();
        }
        // Checked before the moment, so an uninitialised id is reported as
        // the mistake it is rather than as a first record of zero.
        if (migration == bytes32(0)) {
            revert ZeroMigration();
        }
        // Genesis is a head, not a migration. Applying it would leave `sHead`
        // holding the value an empty line reads as, so a line that had
        // applied something would be at a head indistinguishable from one that
        // had applied nothing — and the next first-migration script would be
        // accepted against it.
        if (migration == MIGRATION_HEAD_GENESIS) {
            revert GenesisMigration();
        }
        // Beside the two id refusals because it is the same kind of mistake in
        // the same kind of value: an uninitialised `uint256`, refused whatever
        // line it arrives at and whatever block it lands in. Zero is the
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
    /// @param namespace The line under the caller to apply in.
    /// @param migration The migration to apply.
    /// @param appliedAt The moment to record against it.
    /// @param prerequisites The head the caller believes its line is at, then
    /// the records it was applied after, every one of which
    /// `checkPrerequisites` has found to exist.
    function writeMigrationRecord(
        bytes32 namespace,
        bytes32 migration,
        uint256 appliedAt,
        Prerequisite[] calldata prerequisites
    ) internal {
        // There is deliberately no zero-writer case here. `msg.sender` cannot
        // be the zero address, so no line under it is reachable for writes
        // and a guard on it would be unreachable code pretending to be a check.
        // Nor is there a zero-head case: a head is either genesis or an applied
        // id, both nonzero, so a zero in the first entry can never match and is
        // already refused below, by an error that names the zero it was handed.

        // A migration that has already run has already run whatever the list
        // says, and the record it would overwrite is the original.
        MigrationRecord storage record = sRecords[msg.sender][namespace][migration];
        if (record.appliedAt != 0) {
            revert MigrationAlreadyApplied(msg.sender, namespace, migration);
        }
        bytes32 actualHead = prerequisites[0].migration;
        // Reads the record at the head the list named first, which
        // checkPrerequisites has already confirmed is this line's head.
        //
        // At genesis there is nothing to be before. Genesis can never be
        // applied, so the record at it is empty in every line forever and
        // this comparison against zero can only pass — which is the same
        // statement a genesis branch would make, made by the value itself.
        //
        uint256 headAppliedAt = sRecords[msg.sender][namespace][actualHead].appliedAt;
        if (appliedAt < headAppliedAt) {
            revert TimestampBeforeHead(appliedAt, headAppliedAt);
        }
        // Last, because it is the only refusal here that time itself resolves:
        // every other one describes something wrong with the call or with where
        // the line is, and this one describes a moment that has not arrived
        // yet.
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
        // Pushed one at a time: solc does not copy a calldata array of structs
        // into storage. The record was empty, so this is the whole list.
        for (uint256 i = 0; i < prerequisites.length; i++) {
            record.appliedAfter.push(prerequisites[i]);
        }
        sHead[msg.sender][namespace] = migration;
        emit Migrated(msg.sender, namespace, migration, appliedAt);
    }

    /// @inheritdoc IMigrationRegistryV2
    /// @dev All four refusals are about a caller that has not supplied what it
    /// thinks it has. None can ever be a real record: nothing originates from
    /// the zero address, no write names the zero namespace, and neither write
    /// records the zero id or the genesis one — so answering zero for any of
    /// them would be answering a question the caller did not mean to ask, and
    /// answering it with the value that sends it down its pre-migration
    /// branch.
    function applied(address writer, bytes32 namespace, bytes32 migration) external view returns (uint256) {
        checkRecordKey(writer, namespace, migration);
        return sRecords[writer][namespace][migration].appliedAt;
    }

    /// @inheritdoc IMigrationRegistryV2
    /// @dev The same four refusals as `applied`, for the same reason and on
    /// the same key: a zero answer here reads as "never applied" exactly as a
    /// zero moment does. The head is the first entry of the stored list, and
    /// the list is empty exactly when the record is.
    function appliedOnto(address writer, bytes32 namespace, bytes32 migration) external view returns (bytes32) {
        checkRecordKey(writer, namespace, migration);
        Prerequisite[] storage appliedAfterList = sRecords[writer][namespace][migration].appliedAfter;
        return appliedAfterList.length == 0 ? bytes32(0) : appliedAfterList[0].migration;
    }

    /// @inheritdoc IMigrationRegistryV2
    /// @dev The same four refusals again: an empty answer for a key that can
    /// never hold a record would read as "never applied" about a record the
    /// caller did not mean to ask for.
    function appliedAfter(address writer, bytes32 namespace, bytes32 migration)
        external
        view
        returns (Prerequisite[] memory)
    {
        checkRecordKey(writer, namespace, migration);
        return sRecords[writer][namespace][migration].appliedAfter;
    }

    /// Refuses the four inputs that can only be a mistake in the caller rather
    /// than a record to read. One function, so the three readers of a record
    /// and the check on every entry after the head cannot drift into refusing
    /// different things.
    /// @param writer The writer being read.
    /// @param namespace The line under the writer being read.
    /// @param migration The migration being asked about.
    function checkRecordKey(address writer, bytes32 namespace, bytes32 migration) internal pure {
        if (writer == address(0)) {
            revert ZeroWriter();
        }
        if (namespace == bytes32(0)) {
            revert ZeroNamespace();
        }
        if (migration == bytes32(0)) {
            revert ZeroMigration();
        }
        if (migration == MIGRATION_HEAD_GENESIS) {
            revert GenesisMigration();
        }
    }

    /// @inheritdoc IMigrationRegistryV2
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
    /// A write reaches it as `head(msg.sender, namespace)`, which can never be
    /// the zero address and whose namespace `checkMigrationArguments` has
    /// already refused as zero, so both refusals are redundant on that path.
    /// It is one function, so it is one pair of refusals, and the reachable
    /// path is the one they are there for.
    function head(address writer, bytes32 namespace) public view returns (bytes32) {
        if (writer == address(0)) {
            revert ZeroWriter();
        }
        if (namespace == bytes32(0)) {
            revert ZeroNamespace();
        }
        bytes32 storedHead = sHead[writer][namespace];
        return storedHead == bytes32(0) ? MIGRATION_HEAD_GENESIS : storedHead;
    }
}
