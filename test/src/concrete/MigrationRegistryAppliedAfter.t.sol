// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";

import {
    IMigrationRegistryV1,
    Prerequisite,
    MIGRATION_HEAD_GENESIS
} from "../../../src/interface/IMigrationRegistryV1.sol";
import {MigrationRegistry} from "../../../src/concrete/MigrationRegistry.sol";
import {LibMigrationFuzz} from "../../lib/LibMigrationFuzz.sol";

/// @title MigrationRegistryAppliedAfterTest
/// @notice A test suite for `MigrationRegistry.prerequisites`: it answers an
/// applied migration with the list it was applied after, as listed, an
/// unapplied one with an empty list, refuses the three inputs that can only be
/// mistakes, and is the step that walks from a record across namespaces.
contract MigrationRegistryAppliedAfterTest is Test {
    /// The registry under test. Stateful, so a fresh one per test.
    MigrationRegistry internal sRegistry;

    function setUp() external {
        sRegistry = new MigrationRegistry();
    }

    /// One prerequisite, as a list.
    /// @param writer The prerequisite's namespace.
    /// @param migration The prerequisite's migration.
    /// @return prerequisites The one-entry list.
    function one(address writer, bytes32 migration) internal pure returns (Prerequisite[] memory prerequisites) {
        prerequisites = new Prerequisite[](1);
        prerequisites[0] = Prerequisite({writer: writer, migration: migration});
    }

    /// The empty list, so a test says what it expects rather than a length.
    /// @return The empty list.
    function none() internal pure returns (Prerequisite[] memory) {
        return new Prerequisite[](0);
    }

    /// Applies `migration` under `writer` onto wherever that namespace is,
    /// waiting on nothing.
    /// @param writer The namespace to apply under.
    /// @param migration The migration to apply.
    function applyUnder(address writer, bytes32 migration) internal {
        // The head is read before the prank: the read is an external call
        // of its own and would consume the prank meant for the write.
        bytes32 head = sRegistry.head(writer);
        vm.prank(writer);
        sRegistry.applyMigration(head, migration, none());
    }

    /// An unapplied migration answers an empty list rather than reverting,
    /// exactly as `applied` answers zero. An empty list is what a record that
    /// waited on nothing holds too, so it says "no list" and nothing else;
    /// `applied` is what says whether there is a record.
    function testAppliedAfterUnappliedIsEmpty(address writer, bytes32 migration) external view {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeMigration(vm, migration);

        assertEq(abi.encode(sRegistry.appliedAfter(writer, migration)), abi.encode(none()));
    }

    /// A migration applied after nothing answers an empty list, on both
    /// writes, whatever else the namespace holds.
    function testAppliedAfterRecordWithoutPrerequisitesIsEmpty(
        address writer,
        bytes32 migrationA,
        bytes32 migrationB,
        uint32 now_
    ) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.assume(migrationA != migrationB);
        vm.assume(now_ != 0);
        vm.warp(now_);

        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migrationA, none());
        vm.prank(writer);
        sRegistry.applyMigrationHistory(migrationA, migrationB, now_, none());

        assertEq(abi.encode(sRegistry.appliedAfter(writer, migrationA)), abi.encode(none()));
        assertEq(abi.encode(sRegistry.appliedAfter(writer, migrationB)), abi.encode(none()));
        assertEq(sRegistry.applied(writer, migrationA), now_);
        assertEq(sRegistry.applied(writer, migrationB), now_);
    }

    /// An applied migration answers the list it was applied after, which is
    /// the list the registry itself checked rather than one the caller was
    /// free to assert: a caller that names an unapplied entry is refused, so
    /// the record can only ever hold a list every entry of which existed.
    function testAppliedAfterIsTheCheckedList(
        address writer,
        address other,
        bytes32 migration,
        bytes32 prerequisite,
        bytes32 unapplied
    ) external {
        vm.assume(writer != address(0));
        vm.assume(other != address(0));
        vm.assume(writer != other);
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, prerequisite);
        LibMigrationFuzz.assumeMigration(vm, unapplied);
        vm.assume(prerequisite != unapplied);
        applyUnder(other, prerequisite);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.PrerequisiteNotApplied.selector, other, unapplied));
        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migration, one(other, unapplied));
        assertEq(abi.encode(sRegistry.appliedAfter(writer, migration)), abi.encode(none()));

        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migration, one(other, prerequisite));

        assertEq(abi.encode(sRegistry.appliedAfter(writer, migration)), abi.encode(one(other, prerequisite)));
    }

    /// Every entry answered names a record that exists, and each is readable
    /// the ordinary way: the walk across namespaces lands on records.
    function testAppliedAfterEveryEntryIsARecord(
        address writer,
        address otherA,
        address otherB,
        bytes32 migration,
        bytes32 prerequisiteA,
        bytes32 prerequisiteB
    ) external {
        vm.assume(writer != address(0));
        vm.assume(otherA != address(0));
        vm.assume(otherB != address(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, prerequisiteA);
        LibMigrationFuzz.assumeMigration(vm, prerequisiteB);
        vm.assume(migration != prerequisiteA);
        vm.assume(migration != prerequisiteB);
        applyUnder(otherA, prerequisiteA);
        if (sRegistry.applied(otherB, prerequisiteB) == 0) {
            applyUnder(otherB, prerequisiteB);
        }
        Prerequisite[] memory prerequisites = new Prerequisite[](2);
        prerequisites[0] = Prerequisite({writer: otherA, migration: prerequisiteA});
        prerequisites[1] = Prerequisite({writer: otherB, migration: prerequisiteB});

        bytes32 head = sRegistry.head(writer);
        vm.prank(writer);
        sRegistry.applyMigration(head, migration, prerequisites);

        Prerequisite[] memory recorded = sRegistry.appliedAfter(writer, migration);
        assertEq(recorded.length, 2);
        for (uint256 i = 0; i < recorded.length; i++) {
            assertEq(recorded[i].writer, prerequisites[i].writer);
            assertEq(recorded[i].migration, prerequisites[i].migration);
            assertTrue(sRegistry.applied(recorded[i].writer, recorded[i].migration) != 0);
        }
    }

    /// A duplicate is kept: the list is what the caller listed, not a set.
    function testAppliedAfterDuplicatesAreKept(address writer, address other, bytes32 migration, bytes32 prerequisite)
        external
    {
        vm.assume(writer != address(0));
        vm.assume(other != address(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, prerequisite);
        vm.assume(migration != prerequisite);
        applyUnder(other, prerequisite);
        Prerequisite[] memory prerequisites = new Prerequisite[](2);
        prerequisites[0] = Prerequisite({writer: other, migration: prerequisite});
        prerequisites[1] = Prerequisite({writer: other, migration: prerequisite});

        bytes32 head = sRegistry.head(writer);
        vm.prank(writer);
        sRegistry.applyMigration(head, migration, prerequisites);

        assertEq(sRegistry.appliedAfter(writer, migration).length, 2);
        assertEq(abi.encode(sRegistry.appliedAfter(writer, migration)), abi.encode(prerequisites));
    }

    /// A record never moves. The answer for an earlier migration is the same
    /// after a later one lands with a different list, so a walk read at any
    /// moment describes the same history.
    function testAppliedAfterRecordsAreImmutable(
        address writer,
        address other,
        bytes32 migrationA,
        bytes32 migrationB,
        bytes32 prerequisite
    ) external {
        vm.assume(writer != address(0));
        vm.assume(other != address(0));
        vm.assume(writer != other);
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        LibMigrationFuzz.assumeMigration(vm, prerequisite);
        vm.assume(migrationA != migrationB);
        applyUnder(other, prerequisite);

        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migrationA, one(other, prerequisite));
        assertEq(abi.encode(sRegistry.appliedAfter(writer, migrationA)), abi.encode(one(other, prerequisite)));

        vm.prank(writer);
        sRegistry.applyMigration(migrationA, migrationB, one(writer, migrationA));

        assertEq(abi.encode(sRegistry.appliedAfter(writer, migrationA)), abi.encode(one(other, prerequisite)));
        assertEq(abi.encode(sRegistry.appliedAfter(writer, migrationB)), abi.encode(one(writer, migrationA)));
    }

    /// Reading twice answers the same way.
    function testAppliedAfterIsIdempotent(address writer, address other, bytes32 migration, bytes32 prerequisite)
        external
    {
        vm.assume(writer != address(0));
        vm.assume(other != address(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, prerequisite);
        vm.assume(migration != prerequisite);
        applyUnder(other, prerequisite);

        bytes32 head = sRegistry.head(writer);
        vm.prank(writer);
        sRegistry.applyMigration(head, migration, one(other, prerequisite));

        assertEq(abi.encode(sRegistry.appliedAfter(writer, migration)), abi.encode(one(other, prerequisite)));
        assertEq(abi.encode(sRegistry.appliedAfter(writer, migration)), abi.encode(one(other, prerequisite)));
    }

    /// A record is confined to the caller's namespace here as everywhere else:
    /// one writer's list says nothing about another's, including the
    /// namespace the list names.
    function testAppliedAfterIsPerWriter(address writer, address other, bytes32 migration, bytes32 prerequisite)
        external
    {
        vm.assume(writer != address(0));
        vm.assume(other != address(0));
        vm.assume(writer != other);
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, prerequisite);
        applyUnder(other, prerequisite);

        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migration, one(other, prerequisite));

        assertEq(abi.encode(sRegistry.appliedAfter(writer, migration)), abi.encode(one(other, prerequisite)));
        assertEq(abi.encode(sRegistry.appliedAfter(other, migration)), abi.encode(none()));
        assertEq(abi.encode(sRegistry.appliedAfter(other, prerequisite)), abi.encode(none()));
    }

    /// The zero writer is refused rather than answered, for the reason `applied`
    /// refuses it: the zero namespace is provably empty, so an unresolved writer
    /// constant would read as "waited on nothing" rather than as the mistake
    /// it is.
    function testAppliedAfterZeroWriterReverts(bytes32 migration) external {
        LibMigrationFuzz.assumeMigration(vm, migration);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.ZeroWriter.selector));
        sRegistry.appliedAfter(address(0), migration);
    }

    /// The zero migration id is refused: neither write records it, so it can
    /// never be a real record.
    function testAppliedAfterZeroMigrationReverts(address writer) external {
        vm.assume(writer != address(0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.ZeroMigration.selector));
        sRegistry.appliedAfter(writer, bytes32(0));
    }

    /// The genesis head is refused as a migration: it is a head, no namespace
    /// ever applies it, and a caller asking what it waited on has confused a
    /// head for a record.
    function testAppliedAfterGenesisMigrationReverts(address writer) external {
        vm.assume(writer != address(0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.GenesisMigration.selector));
        sRegistry.appliedAfter(writer, MIGRATION_HEAD_GENESIS);
    }

    /// The writer is checked before the migration, so a caller that has zeroed
    /// both gets one stable answer rather than one that depends on which check
    /// happens to run — the same order `applied` uses, from the same check.
    function testAppliedAfterZeroWriterCheckedFirst() external {
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.ZeroWriter.selector));
        sRegistry.appliedAfter(address(0), bytes32(0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.ZeroWriter.selector));
        sRegistry.appliedAfter(address(0), MIGRATION_HEAD_GENESIS);
    }

    /// A refusal is not a state change: the refused cases revert on a registry
    /// that holds records exactly as they do on an empty one, and leave those
    /// records intact.
    function testAppliedAfterRefusalLeavesRecordsIntact(
        address writer,
        address other,
        bytes32 migration,
        bytes32 prerequisite
    ) external {
        vm.assume(writer != address(0));
        vm.assume(other != address(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, prerequisite);
        vm.assume(migration != prerequisite);
        applyUnder(other, prerequisite);

        bytes32 head = sRegistry.head(writer);
        vm.prank(writer);
        sRegistry.applyMigration(head, migration, one(other, prerequisite));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.ZeroWriter.selector));
        sRegistry.appliedAfter(address(0), migration);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.ZeroMigration.selector));
        sRegistry.appliedAfter(writer, bytes32(0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.GenesisMigration.selector));
        sRegistry.appliedAfter(writer, MIGRATION_HEAD_GENESIS);

        assertEq(abi.encode(sRegistry.appliedAfter(writer, migration)), abi.encode(one(other, prerequisite)));
        assertEq(sRegistry.head(writer), migration);
    }

    /// The readers of a record agree about whether it exists: a nonempty list
    /// comes only with a nonzero `applied`, and a zero `applied` comes only
    /// with an empty list — which is what a single whole-record write buys.
    /// The converse does not hold, because a record may wait on nothing, and
    /// that is why `applied` and not this is what says whether there is a
    /// record.
    function testAppliedAfterAgreesWithApplied(
        address writer,
        address other,
        bytes32 migrationA,
        bytes32 migrationB,
        bytes32 prerequisite
    ) external {
        vm.assume(writer != address(0));
        vm.assume(other != address(0));
        vm.assume(writer != other);
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        LibMigrationFuzz.assumeMigration(vm, prerequisite);
        vm.assume(migrationA != migrationB);
        applyUnder(other, prerequisite);

        assertEq(sRegistry.applied(writer, migrationA), 0);
        assertEq(sRegistry.appliedAfter(writer, migrationA).length, 0);

        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migrationA, one(other, prerequisite));

        assertTrue(sRegistry.applied(writer, migrationA) != 0);
        assertEq(sRegistry.appliedAfter(writer, migrationA).length, 1);

        assertEq(sRegistry.applied(writer, migrationB), 0);
        assertEq(sRegistry.appliedAfter(writer, migrationB).length, 0);

        vm.prank(writer);
        sRegistry.applyMigration(migrationA, migrationB, none());

        assertTrue(sRegistry.applied(writer, migrationB) != 0);
        assertEq(sRegistry.appliedAfter(writer, migrationB).length, 0);
    }
}
