// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";

import {IMigrationRegistryV1, MIGRATION_HEAD_GENESIS} from "../../../src/interface/IMigrationRegistryV1.sol";
import {MigrationRegistry} from "../../../src/concrete/MigrationRegistry.sol";
import {LibMigrationFuzz} from "../../lib/LibMigrationFuzz.sol";

/// @title MigrationRegistryAppliedOntoTest
/// @notice A test suite for `MigrationRegistry.appliedOnto`: it answers an
/// applied migration with the head it was applied onto, an unapplied one with
/// zero, refuses the three inputs that can only be mistakes, and is the step
/// that walks a namespace back to genesis.
contract MigrationRegistryAppliedOntoTest is Test {
    /// The registry under test. Stateful, so a fresh one per test.
    MigrationRegistry internal sRegistry;

    function setUp() external {
        sRegistry = new MigrationRegistry();
    }

    /// An unapplied migration answers zero rather than reverting, exactly as
    /// `applied` does. Zero is not a head — a head is genesis or an applied id,
    /// both nonzero — so it says "no record" and nothing else.
    function testAppliedOntoUnappliedIsZero(address writer, bytes32 migration) external view {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeMigration(vm, migration);

        assertEq(sRegistry.appliedOnto(writer, migration), bytes32(0));
    }

    /// The first migration in a namespace answers `MIGRATION_HEAD_GENESIS`, so
    /// the walk back has a terminator that is not the "no record" zero.
    function testAppliedOntoFirstRecordIsGenesis(address writer, bytes32 migration) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeMigration(vm, migration);

        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migration);

        assertEq(sRegistry.appliedOnto(writer, migration), MIGRATION_HEAD_GENESIS);
    }

    /// A later migration answers the migration before it, which is the head the
    /// registry itself checked rather than a value the caller was free to
    /// choose: a caller that names anything else is refused, so the record can
    /// only ever hold where the namespace actually was.
    function testAppliedOntoIsTheCheckedHead(address writer, bytes32 migrationA, bytes32 migrationB, bytes32 wrongHead)
        external
    {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        LibMigrationFuzz.assumeMigration(vm, wrongHead);
        vm.assume(migrationA != migrationB);
        vm.assume(wrongHead != migrationA);

        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migrationA);

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV1.UnexpectedMigrationHead.selector, writer, wrongHead, migrationA)
        );
        vm.prank(writer);
        sRegistry.applyMigration(wrongHead, migrationB);

        vm.prank(writer);
        sRegistry.applyMigration(migrationA, migrationB);

        assertEq(sRegistry.appliedOnto(writer, migrationB), migrationA);
    }

    /// A record never moves. The answer for an earlier migration is the same
    /// after a later one lands, so a chain read at any moment describes the same
    /// history.
    function testAppliedOntoRecordsAreImmutable(address writer, bytes32 migrationA, bytes32 migrationB) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.assume(migrationA != migrationB);

        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migrationA);
        assertEq(sRegistry.appliedOnto(writer, migrationA), MIGRATION_HEAD_GENESIS);

        vm.prank(writer);
        sRegistry.applyMigration(migrationA, migrationB);

        assertEq(sRegistry.appliedOnto(writer, migrationA), MIGRATION_HEAD_GENESIS);
        assertEq(sRegistry.appliedOnto(writer, migrationB), migrationA);
    }

    /// Reading twice answers the same way.
    function testAppliedOntoIsIdempotent(address writer, bytes32 migration) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeMigration(vm, migration);

        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migration);

        assertEq(sRegistry.appliedOnto(writer, migration), MIGRATION_HEAD_GENESIS);
        assertEq(sRegistry.appliedOnto(writer, migration), MIGRATION_HEAD_GENESIS);
    }

    /// A record is confined to the caller's namespace here as everywhere else:
    /// one writer's chain says nothing about another's.
    function testAppliedOntoIsPerWriter(address writer, address other, bytes32 migration) external {
        vm.assume(writer != address(0));
        vm.assume(other != address(0));
        vm.assume(writer != other);
        LibMigrationFuzz.assumeMigration(vm, migration);

        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migration);

        assertEq(sRegistry.appliedOnto(writer, migration), MIGRATION_HEAD_GENESIS);
        assertEq(sRegistry.appliedOnto(other, migration), bytes32(0));
    }

    /// The zero writer is refused rather than answered, for the reason `applied`
    /// refuses it: the zero namespace is provably empty, so an unresolved writer
    /// constant would read as "nothing has been applied" rather than as the
    /// mistake it is.
    function testAppliedOntoZeroWriterReverts(bytes32 migration) external {
        LibMigrationFuzz.assumeMigration(vm, migration);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.ZeroWriter.selector));
        sRegistry.appliedOnto(address(0), migration);
    }

    /// The zero migration id is refused: neither write records it, so it can
    /// never be a real record.
    function testAppliedOntoZeroMigrationReverts(address writer) external {
        vm.assume(writer != address(0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.ZeroMigration.selector));
        sRegistry.appliedOnto(writer, bytes32(0));
    }

    /// The genesis head is refused as a migration. It is where a walk ENDS, so a
    /// caller that carried on asking about it has confused the terminator for a
    /// record and would read zero as one.
    function testAppliedOntoGenesisMigrationReverts(address writer) external {
        vm.assume(writer != address(0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.GenesisMigration.selector));
        sRegistry.appliedOnto(writer, MIGRATION_HEAD_GENESIS);
    }

    /// The writer is checked before the migration, so a caller that has zeroed
    /// both gets one stable answer rather than one that depends on which check
    /// happens to run — the same order `applied` uses, from the same check.
    function testAppliedOntoZeroWriterCheckedFirst() external {
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.ZeroWriter.selector));
        sRegistry.appliedOnto(address(0), bytes32(0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.ZeroWriter.selector));
        sRegistry.appliedOnto(address(0), MIGRATION_HEAD_GENESIS);
    }

    /// A refusal is not a state change: the refused cases revert on a registry
    /// that holds records exactly as they do on an empty one, and leave those
    /// records intact.
    function testAppliedOntoRefusalLeavesRecordsIntact(address writer, bytes32 migration) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeMigration(vm, migration);

        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migration);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.ZeroWriter.selector));
        sRegistry.appliedOnto(address(0), migration);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.ZeroMigration.selector));
        sRegistry.appliedOnto(writer, bytes32(0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.GenesisMigration.selector));
        sRegistry.appliedOnto(writer, MIGRATION_HEAD_GENESIS);

        assertEq(sRegistry.appliedOnto(writer, migration), MIGRATION_HEAD_GENESIS);
        assertEq(sRegistry.head(writer), migration);
    }

    /// The two readers of a record agree about whether it exists. `applied`
    /// answering zero and `appliedOnto` answering zero are the same fact, and a
    /// nonzero answer from either comes with a nonzero answer from the other —
    /// which is what a single whole-struct write buys.
    function testAppliedOntoAgreesWithApplied(address writer, bytes32 migrationA, bytes32 migrationB) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.assume(migrationA != migrationB);

        assertEq(sRegistry.applied(writer, migrationA), 0);
        assertEq(sRegistry.appliedOnto(writer, migrationA), bytes32(0));

        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migrationA);

        assertTrue(sRegistry.applied(writer, migrationA) != 0);
        assertTrue(sRegistry.appliedOnto(writer, migrationA) != bytes32(0));

        assertEq(sRegistry.applied(writer, migrationB), 0);
        assertEq(sRegistry.appliedOnto(writer, migrationB), bytes32(0));
    }
}
