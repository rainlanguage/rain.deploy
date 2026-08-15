// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, Vm} from "forge-std-1.16.1/src/Test.sol";

import {IMigrationRegistryV1, MIGRATION_HEAD_GENESIS} from "../../../src/interface/IMigrationRegistryV1.sol";
import {MigrationRegistry} from "../../../src/concrete/MigrationRegistry.sol";

/// @title MigrationRegistryRecordTest
/// @notice A test suite for `MigrationRegistry.record`: who a record belongs
/// to, that a migration is recorded at most once and only onto the head its
/// caller named, what a record carries, and what it may never become.
contract MigrationRegistryRecordTest is Test {
    /// The registry under test. Stateful, so a fresh one per test.
    MigrationRegistry internal sRegistry;

    function setUp() external {
        sRegistry = new MigrationRegistry();
    }

    /// A migration id that is neither of the two values the head space reserves,
    /// which is what every test that is not about those values wants.
    /// @param migration The fuzzed candidate.
    function assumeMigration(bytes32 migration) internal pure {
        vm.assume(migration != bytes32(0));
        vm.assume(migration != MIGRATION_HEAD_GENESIS);
    }

    /// Anyone may record, and the record lands under the caller. There is no
    /// authority to be refused by, which is the whole access-control design:
    /// the namespace IS the caller.
    function testRecordAnyCallerRecordsUnderItself(address writer, bytes32 migration) external {
        vm.assume(writer != address(0));
        assumeMigration(migration);

        vm.prank(writer);
        sRegistry.record(MIGRATION_HEAD_GENESIS, migration);

        assertEq(sRegistry.applied(writer, migration), block.timestamp);
    }

    /// A record IS the block timestamp it landed in, which is the whole
    /// difference from a flag: a consumer whose invariant starts AT the
    /// migration — a cliff, a rate change, a grace period — reads the moment
    /// from the chain rather than from a constant somebody guessed.
    function testRecordStoresTheBlockTimestamp(address writer, bytes32 migration, uint32 timestamp) external {
        vm.assume(writer != address(0));
        assumeMigration(migration);
        vm.assume(timestamp != 0);
        vm.warp(timestamp);

        vm.prank(writer);
        sRegistry.record(MIGRATION_HEAD_GENESIS, migration);

        assertEq(sRegistry.applied(writer, migration), timestamp);
    }

    /// Two migrations recorded in different blocks carry different timestamps,
    /// and the earlier one does not move when the later one lands. A record is
    /// of the moment it happened, not of the last time anything happened.
    function testRecordTimestampsAreIndependent(address writer, bytes32 migrationA, bytes32 migrationB) external {
        vm.assume(writer != address(0));
        assumeMigration(migrationA);
        assumeMigration(migrationB);
        vm.assume(migrationA != migrationB);

        vm.warp(1000);
        vm.prank(writer);
        sRegistry.record(MIGRATION_HEAD_GENESIS, migrationA);

        vm.warp(2000);
        vm.prank(writer);
        sRegistry.record(migrationA, migrationB);

        assertEq(sRegistry.applied(writer, migrationA), 1000);
        assertEq(sRegistry.applied(writer, migrationB), 2000);
    }

    /// A record refuses to be written at all in a block whose timestamp is zero,
    /// rather than write one that `applied` would read back as no record. The
    /// head does not move and the migration stays recordable, which is the only
    /// outcome that leaves the namespace describing something true.
    function testRecordZeroTimestampReverts(address writer, bytes32 migration) external {
        vm.assume(writer != address(0));
        assumeMigration(migration);
        vm.warp(0);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.ZeroTimestamp.selector));
        vm.prank(writer);
        sRegistry.record(MIGRATION_HEAD_GENESIS, migration);

        assertEq(sRegistry.applied(writer, migration), 0);
        assertEq(sRegistry.head(writer), MIGRATION_HEAD_GENESIS);

        vm.warp(1);
        vm.prank(writer);
        sRegistry.record(MIGRATION_HEAD_GENESIS, migration);
        assertEq(sRegistry.applied(writer, migration), 1);
    }

    /// A record is confined to the caller's namespace. Recording under one
    /// writer says nothing about any other, which is what makes a reader's
    /// choice of namespace the whole of who it trusts — a hostile caller can
    /// record whatever it likes and reach nobody.
    function testRecordDoesNotReachAnotherNamespace(address writer, address other, bytes32 migration) external {
        vm.assume(writer != address(0));
        vm.assume(other != address(0));
        vm.assume(writer != other);
        assumeMigration(migration);

        vm.prank(writer);
        sRegistry.record(MIGRATION_HEAD_GENESIS, migration);

        assertEq(sRegistry.applied(writer, migration), block.timestamp);
        assertEq(sRegistry.applied(other, migration), 0);
    }

    /// Two writers may record the same migration id independently, and each
    /// answers only for itself. Ids are opaque and namespaces are unrelated, so
    /// a shared id is not a collision — including for the head, which each
    /// writer advances from its own genesis.
    function testRecordSameMigrationUnderTwoWriters(address writer, address other, bytes32 migration) external {
        vm.assume(writer != address(0));
        vm.assume(other != address(0));
        vm.assume(writer != other);
        assumeMigration(migration);

        vm.prank(writer);
        sRegistry.record(MIGRATION_HEAD_GENESIS, migration);
        vm.prank(other);
        sRegistry.record(MIGRATION_HEAD_GENESIS, migration);

        assertEq(sRegistry.applied(writer, migration), block.timestamp);
        assertEq(sRegistry.applied(other, migration), block.timestamp);
    }

    /// Migrations are independent within one namespace: recording one says
    /// nothing about any other. This is what a set buys over a high-water mark
    /// — a reader asks about the migration its assertion actually depends on
    /// rather than about a number that stands in for all of them.
    function testRecordDistinctMigrations(address writer, bytes32 migrationA, bytes32 migrationB) external {
        vm.assume(writer != address(0));
        assumeMigration(migrationA);
        assumeMigration(migrationB);
        vm.assume(migrationA != migrationB);

        vm.prank(writer);
        sRegistry.record(MIGRATION_HEAD_GENESIS, migrationA);

        assertEq(sRegistry.applied(writer, migrationA), block.timestamp);
        assertEq(sRegistry.applied(writer, migrationB), 0);

        vm.prank(writer);
        sRegistry.record(migrationA, migrationB);

        assertEq(sRegistry.applied(writer, migrationA), block.timestamp);
        assertEq(sRegistry.applied(writer, migrationB), block.timestamp);
    }

    /// A successful record makes its migration the namespace's new head, which
    /// is what the next one has to name.
    function testRecordAdvancesTheHead(address writer, bytes32 migrationA, bytes32 migrationB) external {
        vm.assume(writer != address(0));
        assumeMigration(migrationA);
        assumeMigration(migrationB);
        vm.assume(migrationA != migrationB);

        assertEq(sRegistry.head(writer), MIGRATION_HEAD_GENESIS);

        vm.prank(writer);
        sRegistry.record(MIGRATION_HEAD_GENESIS, migrationA);
        assertEq(sRegistry.head(writer), migrationA);

        vm.prank(writer);
        sRegistry.record(migrationA, migrationB);
        assertEq(sRegistry.head(writer), migrationB);
    }

    /// A record onto a head the namespace is not at is refused. This is what
    /// blocks a SKIPPED step: a script names its predecessor, so a chain that
    /// never got that predecessor fails at the moment of applying rather than
    /// diverging silently from every chain that did.
    function testRecordSkippedPredecessorReverts(
        address writer,
        bytes32 migrationA,
        bytes32 migrationB,
        bytes32 skipped
    ) external {
        vm.assume(writer != address(0));
        assumeMigration(migrationA);
        assumeMigration(migrationB);
        assumeMigration(skipped);
        vm.assume(migrationA != migrationB);
        vm.assume(skipped != migrationA);
        vm.assume(skipped != migrationB);

        vm.prank(writer);
        sRegistry.record(MIGRATION_HEAD_GENESIS, migrationA);

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV1.UnexpectedMigrationHead.selector, writer, skipped, migrationA)
        );
        vm.prank(writer);
        sRegistry.record(skipped, migrationB);

        assertEq(sRegistry.applied(writer, migrationB), 0);
        assertEq(sRegistry.head(writer), migrationA);
    }

    /// Genesis stops being an acceptable head the moment anything is recorded,
    /// so a first-migration script re-run against a namespace that has moved on
    /// fails rather than restarting the sequence.
    function testRecordOntoGenesisAfterFirstReverts(address writer, bytes32 migrationA, bytes32 migrationB) external {
        vm.assume(writer != address(0));
        assumeMigration(migrationA);
        assumeMigration(migrationB);
        vm.assume(migrationA != migrationB);

        vm.prank(writer);
        sRegistry.record(MIGRATION_HEAD_GENESIS, migrationA);

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV1.UnexpectedMigrationHead.selector, writer, MIGRATION_HEAD_GENESIS, migrationA
            )
        );
        vm.prank(writer);
        sRegistry.record(MIGRATION_HEAD_GENESIS, migrationB);
    }

    /// A head belongs to one namespace. One writer advancing its head leaves
    /// every other writer's exactly where it was, so a second consumer's
    /// migrations are not blocked or unblocked by the first's.
    function testRecordHeadIsPerWriter(address writer, address other, bytes32 migrationA, bytes32 migrationB) external {
        vm.assume(writer != address(0));
        vm.assume(other != address(0));
        vm.assume(writer != other);
        assumeMigration(migrationA);
        assumeMigration(migrationB);
        vm.assume(migrationA != migrationB);

        vm.prank(writer);
        sRegistry.record(MIGRATION_HEAD_GENESIS, migrationA);

        assertEq(sRegistry.head(other), MIGRATION_HEAD_GENESIS);

        // The other namespace is still at genesis, so `migrationA` is not the
        // head there and naming it is refused.
        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV1.UnexpectedMigrationHead.selector, other, migrationA, MIGRATION_HEAD_GENESIS
            )
        );
        vm.prank(other);
        sRegistry.record(migrationA, migrationB);

        vm.prank(other);
        sRegistry.record(MIGRATION_HEAD_GENESIS, migrationB);
        assertEq(sRegistry.head(other), migrationB);
        assertEq(sRegistry.head(writer), migrationA);
    }

    /// A zero head never matches anything, including on a namespace that has
    /// recorded nothing — which is the whole reason genesis is not zero. An
    /// uninitialised predecessor constant is a revert in every namespace state,
    /// rather than a successful first record on every chain that happens to be
    /// empty.
    function testRecordZeroHeadRevertsOnEmptyNamespace(address writer, bytes32 migration) external {
        vm.assume(writer != address(0));
        assumeMigration(migration);

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV1.UnexpectedMigrationHead.selector, writer, bytes32(0), MIGRATION_HEAD_GENESIS
            )
        );
        vm.prank(writer);
        sRegistry.record(bytes32(0), migration);

        assertEq(sRegistry.applied(writer, migration), 0);
    }

    /// And on a namespace that has recorded something.
    function testRecordZeroHeadRevertsOnUsedNamespace(address writer, bytes32 migrationA, bytes32 migrationB) external {
        vm.assume(writer != address(0));
        assumeMigration(migrationA);
        assumeMigration(migrationB);
        vm.assume(migrationA != migrationB);

        vm.prank(writer);
        sRegistry.record(MIGRATION_HEAD_GENESIS, migrationA);

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV1.UnexpectedMigrationHead.selector, writer, bytes32(0), migrationA
            )
        );
        vm.prank(writer);
        sRegistry.record(bytes32(0), migrationB);
    }

    /// Recording twice is refused. This is what makes running a migration twice
    /// fail rather than repeat: a re-dispatched script cannot quietly record
    /// its way to looking like a first run.
    function testRecordTwiceReverts(address writer, bytes32 migration) external {
        vm.assume(writer != address(0));
        assumeMigration(migration);

        vm.prank(writer);
        sRegistry.record(MIGRATION_HEAD_GENESIS, migration);

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV1.MigrationAlreadyRecorded.selector, writer, migration)
        );
        vm.prank(writer);
        sRegistry.record(MIGRATION_HEAD_GENESIS, migration);

        assertEq(sRegistry.applied(writer, migration), block.timestamp);
    }

    /// The head does NOT subsume the already-recorded refusal. Re-recording a
    /// migration whose successor has since landed presents a head that matches
    /// perfectly, and is still refused — otherwise the head would move BACKWARDS
    /// and the original timestamp would be overwritten, which is a record
    /// un-happening.
    function testRecordAgainOnMatchingHeadReverts(address writer, bytes32 migrationA, bytes32 migrationB) external {
        vm.assume(writer != address(0));
        assumeMigration(migrationA);
        assumeMigration(migrationB);
        vm.assume(migrationA != migrationB);

        vm.warp(1000);
        vm.prank(writer);
        sRegistry.record(MIGRATION_HEAD_GENESIS, migrationA);
        vm.prank(writer);
        sRegistry.record(migrationA, migrationB);

        // The namespace really is at `migrationB`, so the head this names is
        // correct and only the already-recorded refusal can stop it.
        assertEq(sRegistry.head(writer), migrationB);
        vm.warp(2000);
        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV1.MigrationAlreadyRecorded.selector, writer, migrationA)
        );
        vm.prank(writer);
        sRegistry.record(migrationB, migrationA);

        assertEq(sRegistry.head(writer), migrationB);
        assertEq(sRegistry.applied(writer, migrationA), 1000);
    }

    /// The already-recorded refusal is checked BEFORE the head, so a
    /// re-dispatched script — which names the same head it named the first time,
    /// long since moved on — is told that its migration already ran rather than
    /// told the namespace is somewhere else and left to work out why.
    function testRecordAlreadyRecordedCheckedBeforeHead(address writer, bytes32 migrationA, bytes32 migrationB)
        external
    {
        vm.assume(writer != address(0));
        assumeMigration(migrationA);
        assumeMigration(migrationB);
        vm.assume(migrationA != migrationB);

        vm.prank(writer);
        sRegistry.record(MIGRATION_HEAD_GENESIS, migrationA);
        vm.prank(writer);
        sRegistry.record(migrationA, migrationB);

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV1.MigrationAlreadyRecorded.selector, writer, migrationA)
        );
        vm.prank(writer);
        sRegistry.record(MIGRATION_HEAD_GENESIS, migrationA);
    }

    /// A migration another writer has already recorded is still a FIRST record
    /// for this one. The refusal is per namespace, not global, or one consumer
    /// choosing a common id would lock every other consumer out of it.
    function testRecordTwiceIsPerWriter(address writer, address other, bytes32 migration) external {
        vm.assume(writer != address(0));
        vm.assume(other != address(0));
        vm.assume(writer != other);
        assumeMigration(migration);

        vm.prank(writer);
        sRegistry.record(MIGRATION_HEAD_GENESIS, migration);

        vm.prank(other);
        sRegistry.record(MIGRATION_HEAD_GENESIS, migration);

        assertEq(sRegistry.applied(other, migration), block.timestamp);
    }

    /// The zero migration id is refused. It is what an uninitialised `bytes32`
    /// constant reads as, and there is deliberately no way to record one, which
    /// is what lets `applied` refuse it as a mistake rather than have to answer
    /// about it.
    function testRecordZeroMigrationReverts(address writer) external {
        vm.assume(writer != address(0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.ZeroMigration.selector));
        vm.prank(writer);
        sRegistry.record(MIGRATION_HEAD_GENESIS, bytes32(0));
    }

    /// The zero id is refused BEFORE the already-recorded read and before the
    /// head, so it is always reported as `ZeroMigration` and never as anything
    /// about where the namespace is.
    function testRecordZeroMigrationCheckedFirst(address writer, bytes32 anyHead) external {
        vm.assume(writer != address(0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.ZeroMigration.selector));
        vm.prank(writer);
        sRegistry.record(anyHead, bytes32(0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.ZeroMigration.selector));
        vm.prank(writer);
        sRegistry.record(anyHead, bytes32(0));
    }

    /// Genesis is a head, not a migration, and recording it is refused. It would
    /// otherwise leave the namespace's head holding the exact value an empty
    /// namespace reads as, so a namespace that had recorded something would be
    /// indistinguishable from one that had not — and the next first-migration
    /// script would be accepted against it.
    function testRecordGenesisMigrationReverts(address writer) external {
        vm.assume(writer != address(0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.GenesisMigration.selector));
        vm.prank(writer);
        sRegistry.record(MIGRATION_HEAD_GENESIS, MIGRATION_HEAD_GENESIS);

        assertEq(sRegistry.head(writer), MIGRATION_HEAD_GENESIS);
    }

    /// Refused whatever head it is applied onto, so it is a fact about the id
    /// rather than about where the namespace happens to be.
    function testRecordGenesisMigrationRevertsOnAnyHead(address writer, bytes32 migration) external {
        vm.assume(writer != address(0));
        assumeMigration(migration);

        vm.prank(writer);
        sRegistry.record(MIGRATION_HEAD_GENESIS, migration);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.GenesisMigration.selector));
        vm.prank(writer);
        sRegistry.record(migration, MIGRATION_HEAD_GENESIS);

        assertEq(sRegistry.head(writer), migration);
    }

    /// Ids are opaque: nothing about a migration's bytes changes how it is
    /// stored or read, including ids no hashing convention would produce.
    function testRecordOpaqueMigrationIds(address writer) external {
        vm.assume(writer != address(0));

        bytes32[2] memory migrations = [bytes32(uint256(1)), bytes32(type(uint256).max)];
        for (uint256 i = 0; i < migrations.length; i++) {
            MigrationRegistry registry = new MigrationRegistry();
            vm.prank(writer);
            registry.record(MIGRATION_HEAD_GENESIS, migrations[i]);
            assertEq(registry.applied(writer, migrations[i]), block.timestamp);
            assertEq(registry.head(writer), migrations[i]);
        }
    }

    /// `Migrated` is emitted with the writer and migration both indexed, so the
    /// log can be filtered by either. The log is the only enumeration of the
    /// registry, so a record that does not emit is a record nobody can find.
    ///
    /// It carries no head and no timestamp because the log already holds both:
    /// one writer's entries in order ARE its chain of heads, and the timestamp
    /// is the block's.
    function testRecordEvent(address writer, bytes32 migration) external {
        vm.assume(writer != address(0));
        assumeMigration(migration);

        vm.recordLogs();
        vm.prank(writer);
        sRegistry.record(MIGRATION_HEAD_GENESIS, migration);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        assertEq(entries.length, 1);
        assertEq(entries[0].emitter, address(sRegistry));
        assertEq(entries[0].topics.length, 3);
        assertEq(entries[0].topics[0], keccak256("Migrated(address,bytes32)"));
        assertEq(entries[0].topics[1], bytes32(uint256(uint160(writer))));
        assertEq(entries[0].topics[2], migration);
        assertEq(entries[0].data.length, 0);
    }

    /// A refused `record` emits nothing, so a failed record can never be
    /// mistaken for a record by anything reading the logs — which for a
    /// re-dispatched migration is exactly the mistake that matters.
    function testRecordNoEventOnRevert(address writer, bytes32 migration) external {
        vm.assume(writer != address(0));
        assumeMigration(migration);

        vm.prank(writer);
        sRegistry.record(MIGRATION_HEAD_GENESIS, migration);

        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV1.MigrationAlreadyRecorded.selector, writer, migration)
        );
        vm.prank(writer);
        sRegistry.record(MIGRATION_HEAD_GENESIS, migration);
        assertEq(vm.getRecordedLogs().length, 0);

        vm.recordLogs();
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.ZeroMigration.selector));
        vm.prank(writer);
        sRegistry.record(migration, bytes32(0));
        assertEq(vm.getRecordedLogs().length, 0);

        vm.recordLogs();
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.GenesisMigration.selector));
        vm.prank(writer);
        sRegistry.record(migration, MIGRATION_HEAD_GENESIS);
        assertEq(vm.getRecordedLogs().length, 0);

        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV1.UnexpectedMigrationHead.selector, writer, MIGRATION_HEAD_GENESIS, migration
            )
        );
        vm.prank(writer);
        sRegistry.record(MIGRATION_HEAD_GENESIS, keccak256(abi.encode(migration)));
        assertEq(vm.getRecordedLogs().length, 0);
    }
}
