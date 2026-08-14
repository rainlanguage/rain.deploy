// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, Vm} from "forge-std-1.16.1/src/Test.sol";

import {IMigrationRegistryV1} from "../../../src/interface/IMigrationRegistryV1.sol";
import {MigrationRegistry} from "../../../src/concrete/MigrationRegistry.sol";

/// @title MigrationRegistryRecordTest
/// @notice A test suite for `MigrationRegistry.record`: who a record belongs
/// to, that a migration is recorded at most once, and what a record may never
/// become.
contract MigrationRegistryRecordTest is Test {
    /// The registry under test. Stateful, so a fresh one per test.
    MigrationRegistry internal sRegistry;

    function setUp() external {
        sRegistry = new MigrationRegistry();
    }

    /// Anyone may record, and the record lands under the caller. There is no
    /// authority to be refused by, which is the whole access-control design:
    /// the namespace IS the caller.
    function testRecordAnyCallerRecordsUnderItself(address writer, bytes32 migration) external {
        vm.assume(writer != address(0));
        vm.assume(migration != bytes32(0));

        vm.prank(writer);
        sRegistry.record(migration);

        assertTrue(sRegistry.applied(writer, migration));
    }

    /// A record is confined to the caller's namespace. Recording under one
    /// writer says nothing about any other, which is what makes a reader's
    /// choice of namespace the whole of who it trusts — a hostile caller can
    /// record whatever it likes and reach nobody.
    function testRecordDoesNotReachAnotherNamespace(address writer, address other, bytes32 migration) external {
        vm.assume(writer != address(0));
        vm.assume(other != address(0));
        vm.assume(writer != other);
        vm.assume(migration != bytes32(0));

        vm.prank(writer);
        sRegistry.record(migration);

        assertTrue(sRegistry.applied(writer, migration));
        assertFalse(sRegistry.applied(other, migration));
    }

    /// Two writers may record the same migration id independently, and each
    /// answers only for itself. Ids are opaque and namespaces are unrelated, so
    /// a shared id is not a collision.
    function testRecordSameMigrationUnderTwoWriters(address writer, address other, bytes32 migration) external {
        vm.assume(writer != address(0));
        vm.assume(other != address(0));
        vm.assume(writer != other);
        vm.assume(migration != bytes32(0));

        vm.prank(writer);
        sRegistry.record(migration);
        vm.prank(other);
        sRegistry.record(migration);

        assertTrue(sRegistry.applied(writer, migration));
        assertTrue(sRegistry.applied(other, migration));
    }

    /// Migrations are independent within one namespace: recording one says
    /// nothing about any other. This is what a set buys over a high-water mark
    /// — migrations applied out of order, or one applied and its predecessor
    /// not, are representable exactly rather than papered over by a single
    /// comparable value.
    function testRecordDistinctMigrations(address writer, bytes32 migrationA, bytes32 migrationB) external {
        vm.assume(writer != address(0));
        vm.assume(migrationA != bytes32(0));
        vm.assume(migrationB != bytes32(0));
        vm.assume(migrationA != migrationB);

        vm.prank(writer);
        sRegistry.record(migrationA);

        assertTrue(sRegistry.applied(writer, migrationA));
        assertFalse(sRegistry.applied(writer, migrationB));

        vm.prank(writer);
        sRegistry.record(migrationB);

        assertTrue(sRegistry.applied(writer, migrationA));
        assertTrue(sRegistry.applied(writer, migrationB));
    }

    /// Recording twice is refused. This is what makes running a migration twice
    /// fail rather than repeat: a re-dispatched script cannot quietly record
    /// its way to looking like a first run.
    function testRecordTwiceReverts(address writer, bytes32 migration) external {
        vm.assume(writer != address(0));
        vm.assume(migration != bytes32(0));

        vm.prank(writer);
        sRegistry.record(migration);

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV1.MigrationAlreadyRecorded.selector, writer, migration)
        );
        vm.prank(writer);
        sRegistry.record(migration);

        assertTrue(sRegistry.applied(writer, migration));
    }

    /// A migration another writer has already recorded is still a FIRST record
    /// for this one. The refusal is per namespace, not global, or one consumer
    /// choosing a common id would lock every other consumer out of it.
    function testRecordTwiceIsPerWriter(address writer, address other, bytes32 migration) external {
        vm.assume(writer != address(0));
        vm.assume(other != address(0));
        vm.assume(writer != other);
        vm.assume(migration != bytes32(0));

        vm.prank(writer);
        sRegistry.record(migration);

        vm.prank(other);
        sRegistry.record(migration);

        assertTrue(sRegistry.applied(other, migration));
    }

    /// The zero migration id is refused. It is what an uninitialised `bytes32`
    /// constant reads as, and there is deliberately no way to record one, which
    /// is what lets `applied` refuse it as a mistake rather than have to answer
    /// about it.
    function testRecordZeroMigrationReverts(address writer) external {
        vm.assume(writer != address(0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.ZeroMigration.selector));
        vm.prank(writer);
        sRegistry.record(bytes32(0));
    }

    /// The zero id is refused BEFORE the already-recorded read, so it is always
    /// reported as `ZeroMigration` and never as a first record that later
    /// collides.
    function testRecordZeroMigrationCheckedFirst(address writer) external {
        vm.assume(writer != address(0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.ZeroMigration.selector));
        vm.prank(writer);
        sRegistry.record(bytes32(0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.ZeroMigration.selector));
        vm.prank(writer);
        sRegistry.record(bytes32(0));
    }

    /// Ids are opaque: nothing about a migration's bytes changes how it is
    /// stored or read, including ids no hashing convention would produce.
    function testRecordOpaqueMigrationIds(address writer) external {
        vm.assume(writer != address(0));

        bytes32[2] memory migrations = [bytes32(uint256(1)), bytes32(type(uint256).max)];
        for (uint256 i = 0; i < migrations.length; i++) {
            MigrationRegistry registry = new MigrationRegistry();
            vm.prank(writer);
            registry.record(migrations[i]);
            assertTrue(registry.applied(writer, migrations[i]));
        }
    }

    /// `Migrated` is emitted with the writer and migration both indexed, so the
    /// log can be filtered by either. The log is the only enumeration of the
    /// registry, so a record that does not emit is a record nobody can find.
    function testRecordEvent(address writer, bytes32 migration) external {
        vm.assume(writer != address(0));
        vm.assume(migration != bytes32(0));

        vm.recordLogs();
        vm.prank(writer);
        sRegistry.record(migration);
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
        vm.assume(migration != bytes32(0));

        vm.prank(writer);
        sRegistry.record(migration);

        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV1.MigrationAlreadyRecorded.selector, writer, migration)
        );
        vm.prank(writer);
        sRegistry.record(migration);
        assertEq(vm.getRecordedLogs().length, 0);

        vm.recordLogs();
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.ZeroMigration.selector));
        vm.prank(writer);
        sRegistry.record(bytes32(0));
        assertEq(vm.getRecordedLogs().length, 0);
    }
}
