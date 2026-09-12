// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";

import {
    IMigrationRegistryV2,
    Prerequisite,
    MIGRATION_HEAD_GENESIS
} from "../../../src/interface/IMigrationRegistryV2.sol";
import {MigrationRegistry} from "../../../src/concrete/MigrationRegistry.sol";
import {LibMigrationFuzz} from "../../lib/LibMigrationFuzz.sol";

/// @title MigrationRegistryAppliedOntoTest
/// @notice A test suite for `MigrationRegistry.appliedOnto`: it answers an
/// applied migration with the head it was applied onto, an unapplied one with
/// zero, refuses the four inputs that can only be mistakes, and is the step
/// that walks a line back to genesis.
contract MigrationRegistryAppliedOntoTest is Test {
    /// The registry under test. Stateful, so a fresh one per test.
    MigrationRegistry internal sRegistry;

    function setUp() external {
        sRegistry = new MigrationRegistry();
    }

    /// The list a write under `writer` in `namespace` onto `head` after
    /// nothing else passes.
    /// @param writer The writer the record is under.
    /// @param namespace The line under the writer.
    /// @param head The head it is applied onto.
    /// @return prerequisites The one-entry list.
    function onto(address writer, bytes32 namespace, bytes32 head)
        internal
        pure
        returns (Prerequisite[] memory prerequisites)
    {
        prerequisites = new Prerequisite[](1);
        prerequisites[0] = Prerequisite({writer: writer, namespace: namespace, migration: head});
    }

    /// An unapplied migration answers zero rather than reverting, exactly as
    /// `applied` does. Zero is not a head — a head is genesis or an applied id,
    /// both nonzero — so it says "no record" and nothing else.
    function testAppliedOntoUnappliedIsZero(address writer, bytes32 namespace, bytes32 migration) external view {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migration);

        assertEq(sRegistry.appliedOnto(writer, namespace, migration), bytes32(0));
    }

    /// The first migration in a line answers `MIGRATION_HEAD_GENESIS`, so
    /// the walk back has a terminator that is not the "no record" zero.
    function testAppliedOntoFirstRecordIsGenesis(address writer, bytes32 namespace, bytes32 migration) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migration);

        vm.prank(writer);
        sRegistry.applyMigration(namespace, migration, onto(writer, namespace, MIGRATION_HEAD_GENESIS));

        assertEq(sRegistry.appliedOnto(writer, namespace, migration), MIGRATION_HEAD_GENESIS);
    }

    /// A later migration answers the migration before it, which is the head the
    /// registry itself checked rather than a value the caller was free to
    /// choose: a caller whose first entry names anything else is refused, so
    /// the record can only ever hold where the line actually was.
    function testAppliedOntoIsTheCheckedHead(
        address writer,
        bytes32 namespace,
        bytes32 migrationA,
        bytes32 migrationB,
        bytes32 wrongHead
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        LibMigrationFuzz.assumeMigration(vm, wrongHead);
        vm.assume(migrationA != migrationB);
        vm.assume(wrongHead != migrationA);

        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationA, onto(writer, namespace, MIGRATION_HEAD_GENESIS));

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.UnexpectedMigrationHead.selector, writer, namespace, wrongHead, migrationA
            )
        );
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationB, onto(writer, namespace, wrongHead));

        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationB, onto(writer, namespace, migrationA));

        assertEq(sRegistry.appliedOnto(writer, namespace, migrationB), migrationA);
    }

    /// The first entry is the caller at its head, not merely the head: the
    /// right migration under another writer is refused as the wrong head, so
    /// what this answers is always a head of the writer's own line.
    function testAppliedOntoFirstEntryUnderAnotherWriterReverts(
        address writer,
        bytes32 namespace,
        address other,
        bytes32 migrationA,
        bytes32 migrationB
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        vm.assume(other != address(0));
        vm.assume(writer != other);
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.assume(migrationA != migrationB);

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.UnexpectedMigrationHead.selector,
                writer,
                namespace,
                MIGRATION_HEAD_GENESIS,
                MIGRATION_HEAD_GENESIS
            )
        );
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationA, onto(other, namespace, MIGRATION_HEAD_GENESIS));
        assertEq(sRegistry.appliedOnto(writer, namespace, migrationA), bytes32(0));

        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationA, onto(writer, namespace, MIGRATION_HEAD_GENESIS));

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.UnexpectedMigrationHead.selector, writer, namespace, migrationA, migrationA
            )
        );
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationB, onto(other, namespace, migrationA));
        assertEq(sRegistry.appliedOnto(writer, namespace, migrationB), bytes32(0));
    }

    /// The first entry is the caller in the namespace being written, not
    /// merely the caller: the caller at the head of one of its OTHER lines is
    /// refused as the wrong head, and nothing is recorded in either line.
    function testAppliedOntoFirstEntryInAnotherNamespaceReverts(
        address writer,
        bytes32 namespace,
        bytes32 otherNamespace,
        bytes32 migrationA,
        bytes32 migrationB
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        vm.assume(otherNamespace != bytes32(0));
        vm.assume(namespace != otherNamespace);
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.assume(migrationA != migrationB);

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.UnexpectedMigrationHead.selector,
                writer,
                namespace,
                MIGRATION_HEAD_GENESIS,
                MIGRATION_HEAD_GENESIS
            )
        );
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationA, onto(writer, otherNamespace, MIGRATION_HEAD_GENESIS));
        assertEq(sRegistry.appliedOnto(writer, namespace, migrationA), bytes32(0));
        assertEq(sRegistry.appliedOnto(writer, otherNamespace, migrationA), bytes32(0));

        vm.prank(writer);
        sRegistry.applyMigration(otherNamespace, migrationA, onto(writer, otherNamespace, MIGRATION_HEAD_GENESIS));

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.UnexpectedMigrationHead.selector,
                writer,
                namespace,
                migrationA,
                MIGRATION_HEAD_GENESIS
            )
        );
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationB, onto(writer, otherNamespace, migrationA));
        assertEq(sRegistry.appliedOnto(writer, namespace, migrationB), bytes32(0));
        assertEq(sRegistry.appliedOnto(writer, otherNamespace, migrationB), bytes32(0));
        assertEq(sRegistry.head(writer, namespace), MIGRATION_HEAD_GENESIS);
        assertEq(sRegistry.head(writer, otherNamespace), migrationA);
    }

    /// The answer is the first entry of `appliedAfter`, whatever the rest of
    /// the list holds: one record, read two ways.
    function testAppliedOntoIsTheFirstEntryOfAppliedAfter(
        address writer,
        bytes32 namespace,
        address other,
        bytes32 migrationA,
        bytes32 migrationB,
        bytes32 prerequisite
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        vm.assume(other != address(0));
        vm.assume(writer != other);
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        LibMigrationFuzz.assumeMigration(vm, prerequisite);
        vm.assume(migrationA != migrationB);

        vm.prank(other);
        sRegistry.applyMigration(namespace, prerequisite, onto(other, namespace, MIGRATION_HEAD_GENESIS));
        assertEq(
            sRegistry.appliedOnto(other, namespace, prerequisite),
            sRegistry.appliedAfter(other, namespace, prerequisite)[0].migration
        );

        Prerequisite[] memory prerequisites = new Prerequisite[](2);
        prerequisites[0] = Prerequisite({writer: writer, namespace: namespace, migration: MIGRATION_HEAD_GENESIS});
        prerequisites[1] = Prerequisite({writer: other, namespace: namespace, migration: prerequisite});
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationA, prerequisites);
        assertEq(sRegistry.appliedOnto(writer, namespace, migrationA), MIGRATION_HEAD_GENESIS);
        assertEq(
            sRegistry.appliedOnto(writer, namespace, migrationA),
            sRegistry.appliedAfter(writer, namespace, migrationA)[0].migration
        );

        prerequisites[0] = Prerequisite({writer: writer, namespace: namespace, migration: migrationA});
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationB, prerequisites);
        assertEq(sRegistry.appliedOnto(writer, namespace, migrationB), migrationA);
        assertEq(
            sRegistry.appliedOnto(writer, namespace, migrationB),
            sRegistry.appliedAfter(writer, namespace, migrationB)[0].migration
        );
    }

    /// A record never moves. The answer for an earlier migration is the same
    /// after a later one lands, so a chain read at any moment describes the same
    /// history.
    function testAppliedOntoRecordsAreImmutable(
        address writer,
        bytes32 namespace,
        bytes32 migrationA,
        bytes32 migrationB
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.assume(migrationA != migrationB);

        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationA, onto(writer, namespace, MIGRATION_HEAD_GENESIS));
        assertEq(sRegistry.appliedOnto(writer, namespace, migrationA), MIGRATION_HEAD_GENESIS);

        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationB, onto(writer, namespace, migrationA));

        assertEq(sRegistry.appliedOnto(writer, namespace, migrationA), MIGRATION_HEAD_GENESIS);
        assertEq(sRegistry.appliedOnto(writer, namespace, migrationB), migrationA);
    }

    /// Reading twice answers the same way.
    function testAppliedOntoIsIdempotent(address writer, bytes32 namespace, bytes32 migration) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migration);

        vm.prank(writer);
        sRegistry.applyMigration(namespace, migration, onto(writer, namespace, MIGRATION_HEAD_GENESIS));

        assertEq(sRegistry.appliedOnto(writer, namespace, migration), MIGRATION_HEAD_GENESIS);
        assertEq(sRegistry.appliedOnto(writer, namespace, migration), MIGRATION_HEAD_GENESIS);
    }

    /// A record is confined to the caller's line here as everywhere else:
    /// one writer's chain says nothing about another's.
    function testAppliedOntoIsPerWriter(address writer, bytes32 namespace, address other, bytes32 migration) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        vm.assume(other != address(0));
        vm.assume(writer != other);
        LibMigrationFuzz.assumeMigration(vm, migration);

        vm.prank(writer);
        sRegistry.applyMigration(namespace, migration, onto(writer, namespace, MIGRATION_HEAD_GENESIS));

        assertEq(sRegistry.appliedOnto(writer, namespace, migration), MIGRATION_HEAD_GENESIS);
        assertEq(sRegistry.appliedOnto(other, namespace, migration), bytes32(0));
    }

    /// One writer's lines are as separate as two writers': a record in one
    /// namespace says nothing in another, and the first migration in the
    /// other line is onto genesis rather than onto the first line's head.
    function testAppliedOntoIsPerNamespace(
        address writer,
        bytes32 namespace,
        bytes32 otherNamespace,
        bytes32 migrationA,
        bytes32 migrationB
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        vm.assume(otherNamespace != bytes32(0));
        vm.assume(namespace != otherNamespace);
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.assume(migrationA != migrationB);

        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationA, onto(writer, namespace, MIGRATION_HEAD_GENESIS));

        assertEq(sRegistry.appliedOnto(writer, namespace, migrationA), MIGRATION_HEAD_GENESIS);
        assertEq(sRegistry.appliedOnto(writer, otherNamespace, migrationA), bytes32(0));

        vm.prank(writer);
        sRegistry.applyMigration(otherNamespace, migrationB, onto(writer, otherNamespace, MIGRATION_HEAD_GENESIS));

        assertEq(sRegistry.appliedOnto(writer, otherNamespace, migrationB), MIGRATION_HEAD_GENESIS);
        assertEq(sRegistry.appliedOnto(writer, namespace, migrationB), bytes32(0));
        assertEq(sRegistry.appliedOnto(writer, namespace, migrationA), MIGRATION_HEAD_GENESIS);
    }

    /// The zero writer is refused rather than answered, for the reason `applied`
    /// refuses it: every line under it is provably empty, so an unresolved
    /// writer constant would read as "nothing has been applied" rather than as
    /// the mistake it is.
    function testAppliedOntoZeroWriterReverts(bytes32 namespace, bytes32 migration) external {
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migration);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroWriter.selector));
        sRegistry.appliedOnto(address(0), namespace, migration);
    }

    /// The zero namespace is refused for the same reason: no write names it,
    /// so an unset namespace constant would read as an empty line rather than
    /// as the mistake it is.
    function testAppliedOntoZeroNamespaceReverts(address writer, bytes32 migration) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeMigration(vm, migration);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroNamespace.selector));
        sRegistry.appliedOnto(writer, bytes32(0), migration);
    }

    /// The zero migration id is refused: neither write records it, so it can
    /// never be a real record.
    function testAppliedOntoZeroMigrationReverts(address writer, bytes32 namespace) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroMigration.selector));
        sRegistry.appliedOnto(writer, namespace, bytes32(0));
    }

    /// The genesis head is refused as a migration. It is where a walk ENDS, so a
    /// caller that carried on asking about it has confused the terminator for a
    /// record and would read zero as one.
    function testAppliedOntoGenesisMigrationReverts(address writer, bytes32 namespace) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.GenesisMigration.selector));
        sRegistry.appliedOnto(writer, namespace, MIGRATION_HEAD_GENESIS);
    }

    /// The writer is checked before the migration, so a caller that has zeroed
    /// both gets one stable answer rather than one that depends on which check
    /// happens to run — the same order `applied` uses, from the same check.
    function testAppliedOntoZeroWriterCheckedFirst(bytes32 namespace) external {
        vm.assume(namespace != bytes32(0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroWriter.selector));
        sRegistry.appliedOnto(address(0), namespace, bytes32(0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroWriter.selector));
        sRegistry.appliedOnto(address(0), namespace, MIGRATION_HEAD_GENESIS);
    }

    /// The namespace sits between the writer and the migration in the order
    /// the key is checked: after the writer, before the migration.
    function testAppliedOntoZeroNamespaceCheckedAfterWriterBeforeMigration(address writer) external {
        vm.assume(writer != address(0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroWriter.selector));
        sRegistry.appliedOnto(address(0), bytes32(0), bytes32(0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroWriter.selector));
        sRegistry.appliedOnto(address(0), bytes32(0), MIGRATION_HEAD_GENESIS);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroNamespace.selector));
        sRegistry.appliedOnto(writer, bytes32(0), bytes32(0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroNamespace.selector));
        sRegistry.appliedOnto(writer, bytes32(0), MIGRATION_HEAD_GENESIS);
    }

    /// A refusal is not a state change: the refused cases revert on a registry
    /// that holds records exactly as they do on an empty one, and leave those
    /// records intact.
    function testAppliedOntoRefusalLeavesRecordsIntact(address writer, bytes32 namespace, bytes32 migration) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migration);

        vm.prank(writer);
        sRegistry.applyMigration(namespace, migration, onto(writer, namespace, MIGRATION_HEAD_GENESIS));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroWriter.selector));
        sRegistry.appliedOnto(address(0), namespace, migration);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroNamespace.selector));
        sRegistry.appliedOnto(writer, bytes32(0), migration);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroMigration.selector));
        sRegistry.appliedOnto(writer, namespace, bytes32(0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.GenesisMigration.selector));
        sRegistry.appliedOnto(writer, namespace, MIGRATION_HEAD_GENESIS);

        assertEq(sRegistry.appliedOnto(writer, namespace, migration), MIGRATION_HEAD_GENESIS);
        assertEq(sRegistry.head(writer, namespace), migration);
    }

    /// The two readers of a record agree about whether it exists. `applied`
    /// answering zero and `appliedOnto` answering zero are the same fact, and a
    /// nonzero answer from either comes with a nonzero answer from the other —
    /// which is what a single whole-struct write buys.
    function testAppliedOntoAgreesWithApplied(address writer, bytes32 namespace, bytes32 migrationA, bytes32 migrationB)
        external
    {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.assume(migrationA != migrationB);

        assertEq(sRegistry.applied(writer, namespace, migrationA), 0);
        assertEq(sRegistry.appliedOnto(writer, namespace, migrationA), bytes32(0));

        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationA, onto(writer, namespace, MIGRATION_HEAD_GENESIS));

        assertTrue(sRegistry.applied(writer, namespace, migrationA) != 0);
        assertTrue(sRegistry.appliedOnto(writer, namespace, migrationA) != bytes32(0));

        assertEq(sRegistry.applied(writer, namespace, migrationB), 0);
        assertEq(sRegistry.appliedOnto(writer, namespace, migrationB), bytes32(0));
    }
}
