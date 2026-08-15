// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {IMigrationRegistryV1, MIGRATION_HEAD_GENESIS} from "../interface/IMigrationRegistryV1.sol";

/// @title MigrationRegistry
/// @notice The whole of `IMigrationRegistryV1`: a writer records one of its own
/// migrations onto the head it believes its namespace is at, and anyone reads
/// when a given writer recorded a given migration, or where that writer's
/// namespace has got to.
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
/// something new. `record` refuses a migration the caller has already recorded,
/// which is what makes re-running a migration fail rather than repeat, and
/// refuses one applied onto anything but the namespace's current head, which is
/// what makes a skipped or out-of-order migration fail rather than diverge.
/// There is no way to unrecord one — a record describes something that happened,
/// and nothing that happened stops having happened.
///
/// Neither storage mapping is `public`. `applied` and `head` refuse the zero
/// writer, `applied` refuses the two ids a migration can never be, and a public
/// mapping's generated getter would answer all of them with zero — which for
/// `applied` is "not recorded" and for `head` is a value no head can ever hold,
/// i.e. exactly the silent wrong-branch this contract reverts to prevent.
contract MigrationRegistry is IMigrationRegistryV1 {
    /// When each record landed, namespaced by writer. Zero means never. Not
    /// `public`: the only reader is `applied`, which refuses the two inputs that
    /// can only be mistakes.
    mapping(address writer => mapping(bytes32 migration => uint256 appliedAt)) internal sApplied;

    /// The most recent migration recorded under each writer. Zero means the
    /// namespace is empty, which reads out as `MIGRATION_HEAD_GENESIS` — the
    /// only place that translation happens is `readHead`, so no reader and no
    /// writer can disagree about where an empty namespace is. Not `public`, for
    /// the same reason as the records: the untranslated zero is not a head.
    mapping(address writer => bytes32 head) internal sHead;

    /// The head of `writer`'s namespace, with an empty namespace translated to
    /// genesis. One function, because `record` compares against it and `head`
    /// returns it, and the two cannot be allowed to drift into different ideas
    /// of where a namespace that has recorded nothing is.
    /// @param writer The namespace to read.
    /// @return The head. Never zero.
    function readHead(address writer) internal view returns (bytes32) {
        bytes32 recordedHead = sHead[writer];
        return recordedHead == bytes32(0) ? MIGRATION_HEAD_GENESIS : recordedHead;
    }

    /// @inheritdoc IMigrationRegistryV1
    /// @dev The refusals run caller-input first and environment last: the two
    /// that describe a mistake in the call are true whatever block this lands
    /// in, so they are what a caller is told about first.
    function record(bytes32 expectedHead, bytes32 migration) external {
        // Checked before everything else, so an uninitialised id is reported as
        // the mistake it is rather than as a first record of zero.
        if (migration == bytes32(0)) {
            revert ZeroMigration();
        }
        // Genesis is a head, not a migration. Recording it would leave `sHead`
        // holding the value an empty namespace reads as, so a namespace that had
        // recorded something would be at a head indistinguishable from one that
        // had recorded nothing — and the next first-migration script would be
        // accepted against it.
        if (migration == MIGRATION_HEAD_GENESIS) {
            revert GenesisMigration();
        }
        // There is deliberately no zero-writer case here. `msg.sender` cannot
        // be the zero address, so the zero namespace is unreachable for writes
        // and a guard on it would be unreachable code pretending to be a check.
        // Nor is there a zero-head case: a head is either genesis or a recorded
        // id, both nonzero, so a zero `expectedHead` can never match and is
        // already refused below, by an error that names the zero it was handed.

        // Checked before the head, because a migration that has already run has
        // already run whatever the head is, and that is the more useful thing to
        // say to a re-dispatched script. It is also not implied by the head
        // check: re-recording a migration whose successor has landed presents a
        // matching head, and would drag the head backwards and overwrite the
        // original timestamp.
        if (sApplied[msg.sender][migration] != 0) {
            revert MigrationAlreadyRecorded(msg.sender, migration);
        }
        bytes32 actualHead = readHead(msg.sender);
        if (expectedHead != actualHead) {
            revert UnexpectedMigrationHead(msg.sender, expectedHead, actualHead);
        }
        // A zero timestamp is the one value a record cannot carry: `applied`
        // would answer it as "never recorded" while the head had moved and the
        // migration could never be recorded again. Not unreachable — a test can
        // warp to zero and a chain can be configured from a zero genesis — so
        // this is a real check rather than a decorative one.
        //
        // The usual hazard behind a `block.timestamp` comparison — the one both
        // the static analysers flag here — is a validator nudging the clock
        // across a threshold. There is no threshold here and no nudge
        // available: zero is not a value a validator on a live chain can
        // produce at all, which is why this is an equality against it rather
        // than a window around it, and why the two warnings are suppressed on
        // this line alone rather than turned off for the repo.
        // slither-disable-next-line incorrect-equality,timestamp
        if (block.timestamp == 0) { // forge-lint: disable-line(block-timestamp)
            revert ZeroTimestamp();
        }
        sApplied[msg.sender][migration] = block.timestamp;
        sHead[msg.sender] = migration;
        emit Migrated(msg.sender, migration);
    }

    /// @inheritdoc IMigrationRegistryV1
    /// @dev All three refusals are about a caller that has not supplied what it
    /// thinks it has. None can ever be a real record: nothing originates from
    /// the zero address, and `record` will write neither the zero id nor the
    /// genesis one — so answering zero for any of them would be answering a
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

    /// @inheritdoc IMigrationRegistryV1
    /// @dev The zero namespace is refused rather than answered `genesis`: it is
    /// provably empty forever, so "a namespace nothing has been applied to" is a
    /// true statement about it and a false one about what the caller meant to
    /// ask, which would send a first migration at it.
    function head(address writer) external view returns (bytes32) {
        if (writer == address(0)) {
            revert ZeroWriter();
        }
        return readHead(writer);
    }
}
