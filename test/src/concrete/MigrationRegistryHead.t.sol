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

/// @title MigrationRegistryHeadTest
/// @notice A test suite for `MigrationRegistry.head`: where a line is, what
/// an empty one answers, that the answer is never a value that is not a head,
/// and that it is the same answer a write checks against.
contract MigrationRegistryHeadTest is Test {
    /// The registry under test. Stateful, so a fresh one per test.
    MigrationRegistry internal sRegistry;

    function setUp() external {
        sRegistry = new MigrationRegistry();
    }

    /// The list a write under `writer` in `namespace` onto `head` after
    /// nothing else passes.
    /// @param writer The writer the record is under.
    /// @param namespace The line under the writer the record is in.
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

    /// A line that has applied nothing is at genesis, which is an ANSWER
    /// rather than a revert for the same reason an unapplied migration answers
    /// zero: it is the ordinary state of every line before its first
    /// migration, and of every line on a chain that never got one.
    function testHeadEmptyNamespaceIsGenesis(address writer, bytes32 namespace) external view {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));

        assertEq(sRegistry.head(writer, namespace), MIGRATION_HEAD_GENESIS);
    }

    /// Genesis is deliberately not zero, so an uninitialised predecessor
    /// constant can never be mistaken for "the start of the sequence" — which
    /// is the mistake that would otherwise pass on every chain that has not been
    /// migrated yet.
    function testHeadGenesisIsNotZero() external pure {
        assertTrue(MIGRATION_HEAD_GENESIS != bytes32(0));
    }

    /// The head is the migration applied most recently, and it moves with each
    /// one.
    function testHeadFollowsTheRecords(address writer, bytes32 namespace, bytes32 migrationA, bytes32 migrationB)
        external
    {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.assume(migrationA != migrationB);

        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationA, onto(writer, namespace, MIGRATION_HEAD_GENESIS));
        assertEq(sRegistry.head(writer, namespace), migrationA);

        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationB, onto(writer, namespace, migrationA));
        assertEq(sRegistry.head(writer, namespace), migrationB);
    }

    /// Every writer has its own head, and one writer's records leave every
    /// other writer's line exactly where it was.
    function testHeadIsPerWriter(address writer, bytes32 namespace, address other, bytes32 migration) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        vm.assume(other != address(0));
        vm.assume(writer != other);
        LibMigrationFuzz.assumeMigration(vm, migration);

        vm.prank(writer);
        sRegistry.applyMigration(namespace, migration, onto(writer, namespace, MIGRATION_HEAD_GENESIS));

        assertEq(sRegistry.head(writer, namespace), migration);
        assertEq(sRegistry.head(other, namespace), MIGRATION_HEAD_GENESIS);
    }

    /// Every namespace under a writer is its own line with its own head: a
    /// record in one leaves the other at genesis, and the other's first
    /// migration then lands onto genesis without moving the first.
    function testHeadIsPerNamespace(
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

        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationA, onto(writer, namespace, MIGRATION_HEAD_GENESIS));

        assertEq(sRegistry.head(writer, namespace), migrationA);
        assertEq(sRegistry.head(writer, otherNamespace), MIGRATION_HEAD_GENESIS);

        vm.prank(writer);
        sRegistry.applyMigration(otherNamespace, migrationB, onto(writer, otherNamespace, MIGRATION_HEAD_GENESIS));

        assertEq(sRegistry.head(writer, otherNamespace), migrationB);
        assertEq(sRegistry.head(writer, namespace), migrationA);
    }

    /// The head `head` reports is exactly the head a write demands: whatever
    /// this answers is accepted, and it is the only value that is. The
    /// two go through one translation of an empty line, so they cannot
    /// disagree about where one is.
    function testHeadIsWhatApplyMigrationAccepts(
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

        // Hoisted, because `vm.prank` applies to the next call and reading the
        // head is a call.
        bytes32 headBeforeA = sRegistry.head(writer, namespace);
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationA, onto(writer, namespace, headBeforeA));

        bytes32 headBeforeB = sRegistry.head(writer, namespace);
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationB, onto(writer, namespace, headBeforeB));

        assertEq(sRegistry.head(writer, namespace), migrationB);
        assertEq(sRegistry.applied(writer, namespace, migrationA), block.timestamp);
        assertEq(sRegistry.applied(writer, namespace, migrationB), block.timestamp);
    }

    /// The zero writer is refused rather than answered genesis. Every line
    /// under it is provably empty forever, so "nothing has been applied here"
    /// is true of it and false of whatever the caller meant to ask about —
    /// and a caller that believed it would send a first migration at it.
    function testHeadZeroWriterReverts(bytes32 namespace) external {
        vm.assume(namespace != bytes32(0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroWriter.selector));
        sRegistry.head(address(0), namespace);
    }

    /// The zero namespace is refused for the same reason: it is what an
    /// uninitialised constant reads as, never a line anybody meant to name.
    function testHeadZeroNamespaceReverts(address writer) external {
        vm.assume(writer != address(0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroNamespace.selector));
        sRegistry.head(writer, bytes32(0));
    }

    /// The writer is checked before the namespace, so a caller that has zeroed
    /// both gets one stable answer.
    function testHeadZeroWriterCheckedBeforeZeroNamespace() external {
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroWriter.selector));
        sRegistry.head(address(0), bytes32(0));
    }

    /// Refused on a registry holding records exactly as on an empty one, and
    /// the refusal changes nothing.
    function testHeadZeroWriterRevertsWithRecordsPresent(address writer, bytes32 namespace, bytes32 migration)
        external
    {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migration);

        vm.prank(writer);
        sRegistry.applyMigration(namespace, migration, onto(writer, namespace, MIGRATION_HEAD_GENESIS));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroWriter.selector));
        sRegistry.head(address(0), namespace);

        assertEq(sRegistry.head(writer, namespace), migration);
    }

    /// The zero namespace is refused under a writer that holds records exactly
    /// as under one that holds none, and the line is left where it was.
    function testHeadZeroNamespaceRevertsWithRecordsPresent(address writer, bytes32 namespace, bytes32 migration)
        external
    {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migration);

        vm.prank(writer);
        sRegistry.applyMigration(namespace, migration, onto(writer, namespace, MIGRATION_HEAD_GENESIS));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroNamespace.selector));
        sRegistry.head(writer, bytes32(0));

        assertEq(sRegistry.head(writer, namespace), migration);
    }

    /// A head is never zero, in any line state, which is what lets a
    /// consumer treat a zero answer as "this is not the registry" rather than as
    /// a line.
    function testHeadIsNeverZero(address writer, bytes32 namespace, bytes32 migration) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migration);

        assertTrue(sRegistry.head(writer, namespace) != bytes32(0));

        vm.prank(writer);
        sRegistry.applyMigration(namespace, migration, onto(writer, namespace, MIGRATION_HEAD_GENESIS));

        assertTrue(sRegistry.head(writer, namespace) != bytes32(0));
    }

    /// A refused apply leaves the head where it was. The head moves only for a
    /// migration that was actually applied, so it can never describe a step
    /// that did not happen.
    function testHeadUnmovedByRefusedApplyMigration(
        address writer,
        bytes32 namespace,
        bytes32 migration,
        bytes32 wrongHead
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, wrongHead);
        vm.assume(wrongHead != migration);

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.UnexpectedMigrationHead.selector,
                writer,
                namespace,
                wrongHead,
                MIGRATION_HEAD_GENESIS
            )
        );
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migration, onto(writer, namespace, wrongHead));

        assertEq(sRegistry.head(writer, namespace), MIGRATION_HEAD_GENESIS);
    }

    /// A first entry in another of the caller's own namespaces is not this
    /// line's head, whatever migration it names, and neither line moves.
    function testHeadUnmovedByFirstEntryInAnotherNamespace(
        address writer,
        bytes32 namespace,
        bytes32 otherNamespace,
        bytes32 migration
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        vm.assume(otherNamespace != bytes32(0));
        vm.assume(namespace != otherNamespace);
        LibMigrationFuzz.assumeMigration(vm, migration);

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
        sRegistry.applyMigration(namespace, migration, onto(writer, otherNamespace, MIGRATION_HEAD_GENESIS));

        assertEq(sRegistry.head(writer, namespace), MIGRATION_HEAD_GENESIS);
        assertEq(sRegistry.head(writer, otherNamespace), MIGRATION_HEAD_GENESIS);
    }

    /// An empty list names no head at all, so it is refused as a zero head on
    /// an empty line and on a used one, and the head stays where it was.
    function testHeadUnmovedByEmptyList(address writer, bytes32 namespace, bytes32 migration, bytes32 next) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, next);
        vm.assume(migration != next);

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.UnexpectedMigrationHead.selector,
                writer,
                namespace,
                bytes32(0),
                MIGRATION_HEAD_GENESIS
            )
        );
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migration, new Prerequisite[](0));
        assertEq(sRegistry.head(writer, namespace), MIGRATION_HEAD_GENESIS);

        vm.prank(writer);
        sRegistry.applyMigration(namespace, migration, onto(writer, namespace, MIGRATION_HEAD_GENESIS));

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.UnexpectedMigrationHead.selector, writer, namespace, bytes32(0), migration
            )
        );
        vm.prank(writer);
        sRegistry.applyMigration(namespace, next, new Prerequisite[](0));
        assertEq(sRegistry.head(writer, namespace), migration);
    }
}
