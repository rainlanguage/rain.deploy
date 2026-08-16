// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {IMigrationRegistryV2, MIGRATION_HEAD_GENESIS} from "../interface/IMigrationRegistryV2.sol";

/// @title MigrationRegistryV2
/// @notice The whole of `IMigrationRegistryV2`: a writer applies one of its own
/// migrations onto the head it believes its namespace is at, at the moment it
/// says the migration ran, and anyone reads when a given writer applied a given
/// migration, or where that writer's namespace has got to.
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
/// chain, so a root would have to be all of them at once, and baking each
/// consumer's authority into creation code would give each of them a different
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
/// something new. `applyMigration` refuses a migration the caller has already
/// applied, which is what makes re-running a migration fail rather than repeat,
/// and refuses one applied onto anything but the namespace's current head, which
/// is what makes a skipped or out-of-order migration fail rather than diverge.
/// There is no way to unrecord one, and no way to rewrite the moment recorded
/// against one — a record describes something that happened, and nothing that
/// happened stops having happened.
///
/// The moment is the CALLER's, so a migration that ran before this contract
/// reached the chain is recordable with the time it actually ran rather than
/// with the time it was written down. The window it must fall in is what keeps
/// every other property of a record: nonzero, so `applied` never reads a record
/// as no record; not after this block, so a record never describes something
/// that has not happened; and not before the record of the head it is applied
/// onto, so a namespace's records read in head order never go backwards.
///
/// Neither storage mapping is `public`. `applied` and `head` refuse the zero
/// writer, `applied` refuses the two ids a migration can never be, and a public
/// mapping's generated getter would answer all of them with zero — which for
/// `applied` is "not applied" and for `head` is a value no head can ever hold,
/// i.e. exactly the silent wrong-branch this contract reverts to prevent.
contract MigrationRegistryV2 is IMigrationRegistryV2 {
    /// The moment recorded against each migration, namespaced by writer. Zero
    /// means never. Not `public`: the only reader is `applied`, which refuses
    /// the two inputs that can only be mistakes.
    mapping(address writer => mapping(bytes32 migration => uint256 appliedAt)) internal sApplied;

    /// The most recent migration applied under each writer. Zero means the
    /// namespace is empty, which reads out as `MIGRATION_HEAD_GENESIS` — the
    /// only place that translation happens is `head`, so no reader and no
    /// writer can disagree about where an empty namespace is. Not `public`, for
    /// the same reason as the records: the untranslated zero is not a head.
    mapping(address writer => bytes32 head) internal sHead;

    /// @inheritdoc IMigrationRegistryV2
    /// @dev The refusals run from the ones that describe the call alone, through
    /// the ones that describe the namespace it arrives at, to the one that
    /// describes the block it lands in — which is the order in which a caller
    /// can do something about them.
    function applyMigration(bytes32 expectedHead, bytes32 migration, uint256 appliedAt) external {
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
        // never be applied again.
        if (appliedAt == 0) {
            revert ZeroTimestamp();
        }
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
        if (sApplied[msg.sender][migration] != 0) {
            revert MigrationAlreadyApplied(msg.sender, migration);
        }
        bytes32 actualHead = head(msg.sender);
        if (expectedHead != actualHead) {
            revert UnexpectedMigrationHead(msg.sender, expectedHead, actualHead);
        }
        // The head chain is the order the migrations ran in, so the record it is
        // being appended to is the floor for this one. Read unconditionally
        // rather than behind a genesis branch: genesis is refused as a migration
        // so nothing is ever recorded against it, which makes an empty
        // namespace's floor zero and every nonzero `appliedAt` above it. A
        // branch here would be a second spelling of "an empty namespace has no
        // previous record", and the two spellings are what drift.
        //
        // Comparing against the head's record alone is enough for the whole
        // namespace: every record is at or above the one before it in the
        // chain, so the head's is the largest.
        uint256 headAppliedAt = sApplied[msg.sender][actualHead];
        if (appliedAt < headAppliedAt) {
            revert TimestampBeforeHead(msg.sender, actualHead, appliedAt, headAppliedAt);
        }
        // Last, because it is the only refusal here that time itself resolves:
        // every other one describes something wrong with the call or with where
        // the namespace is, and this one describes a moment that has not
        // arrived yet.
        //
        // The usual hazard behind a `block.timestamp` comparison — the one the
        // static analysers flag here — is a validator nudging the clock across
        // a threshold. The nudge is available and it is harmless: a validator
        // that moves the clock forward admits a record a second earlier than it
        // would otherwise have been admitted, which is a record of a migration
        // that has run either way, and moving it backwards is not something a
        // chain lets a proposer do. So the warnings are suppressed on this one
        // comparison rather than turned off for the repo.
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
        sApplied[msg.sender][migration] = appliedAt;
        sHead[msg.sender] = migration;
        emit Migrated(msg.sender, migration, appliedAt);
    }

    /// @inheritdoc IMigrationRegistryV2
    /// @dev All three refusals are about a caller that has not supplied what it
    /// thinks it has. None can ever be a real record: nothing originates from
    /// the zero address, and `applyMigration` will write neither the zero id nor
    /// the genesis one — so answering zero for any of them would be answering a
    /// question the caller did not mean to ask, and answering it with the value
    /// that sends it down its pre-migration branch.
    function applied(address writer, bytes32 migration) external view returns (uint256) {
        if (writer == address(0)) {
            revert ZeroWriter();
        }
        if (migration == bytes32(0)) {
            revert ZeroMigration();
        }
        if (migration == MIGRATION_HEAD_GENESIS) {
            revert GenesisMigration();
        }
        return sApplied[writer][migration];
    }

    /// @inheritdoc IMigrationRegistryV2
    /// @dev The zero namespace is refused rather than answered `genesis`: it is
    /// provably empty forever, so "a namespace nothing has been applied to" is a
    /// true statement about it and a false one about what the caller meant to
    /// ask, which would send a first migration at it.
    ///
    /// The empty-namespace zero is translated to genesis here and nowhere else,
    /// which is why this is one `public` function rather than a reader beside an
    /// internal helper: `applyMigration` compares against exactly what a caller
    /// reads, so the two cannot drift into different ideas of where a namespace
    /// that has applied nothing is.
    ///
    /// `applyMigration` reaches it as `head(msg.sender)`, which can never be the
    /// zero address, so the refusal is redundant on that path. It is one
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
