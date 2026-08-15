// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";

import {IMigrationRegistryV1, MIGRATION_HEAD_GENESIS} from "../../../src/interface/IMigrationRegistryV1.sol";
import {MigrationRegistry} from "../../../src/concrete/MigrationRegistry.sol";

/// @title MigrationRegistryHeadTest
/// @notice A test suite for `MigrationRegistry.head`: where a namespace is, what
/// an empty one answers, that the answer is never a value that is not a head,
/// and that it is the same answer `record` checks against.
contract MigrationRegistryHeadTest is Test {
    /// The registry under test. Stateful, so a fresh one per test.
    MigrationRegistry internal sRegistry;

    function setUp() external {
        sRegistry = new MigrationRegistry();
    }

    /// A migration id that is neither of the two values the head space reserves.
    /// @param migration The fuzzed candidate.
    function assumeMigration(bytes32 migration) internal pure {
        vm.assume(migration != bytes32(0));
        vm.assume(migration != MIGRATION_HEAD_GENESIS);
    }

    /// A namespace that has recorded nothing is at genesis, which is an ANSWER
    /// rather than a revert for the same reason an unrecorded migration answers
    /// zero: it is the ordinary state of every namespace before its first
    /// migration, and of every namespace on a chain that never got one.
    function testHeadEmptyNamespaceIsGenesis(address writer) external view {
        vm.assume(writer != address(0));

        assertEq(sRegistry.head(writer), MIGRATION_HEAD_GENESIS);
    }

    /// Genesis is deliberately not zero, so an uninitialised predecessor
    /// constant can never be mistaken for "the start of the sequence" — which
    /// is the mistake that would otherwise pass on every chain that has not been
    /// migrated yet.
    function testHeadGenesisIsNotZero() external pure {
        assertTrue(MIGRATION_HEAD_GENESIS != bytes32(0));
    }

    /// The head is the migration recorded most recently, and it moves with each
    /// one.
    function testHeadFollowsTheRecords(address writer, bytes32 migrationA, bytes32 migrationB) external {
        vm.assume(writer != address(0));
        assumeMigration(migrationA);
        assumeMigration(migrationB);
        vm.assume(migrationA != migrationB);

        vm.prank(writer);
        sRegistry.record(MIGRATION_HEAD_GENESIS, migrationA);
        assertEq(sRegistry.head(writer), migrationA);

        vm.prank(writer);
        sRegistry.record(migrationA, migrationB);
        assertEq(sRegistry.head(writer), migrationB);
    }

    /// Every writer has its own head, and one namespace's records leave every
    /// other namespace exactly where it was.
    function testHeadIsPerWriter(address writer, address other, bytes32 migration) external {
        vm.assume(writer != address(0));
        vm.assume(other != address(0));
        vm.assume(writer != other);
        assumeMigration(migration);

        vm.prank(writer);
        sRegistry.record(MIGRATION_HEAD_GENESIS, migration);

        assertEq(sRegistry.head(writer), migration);
        assertEq(sRegistry.head(other), MIGRATION_HEAD_GENESIS);
    }

    /// The head `head` reports is exactly the head `record` demands: whatever
    /// this answers is accepted, and it is the only value that is. The two go
    /// through one translation of an empty namespace, so they cannot disagree
    /// about where one is.
    function testHeadIsWhatRecordAccepts(address writer, bytes32 migrationA, bytes32 migrationB) external {
        vm.assume(writer != address(0));
        assumeMigration(migrationA);
        assumeMigration(migrationB);
        vm.assume(migrationA != migrationB);

        // Hoisted, because `vm.prank` applies to the next call and reading the
        // head is a call.
        bytes32 headBeforeA = sRegistry.head(writer);
        vm.prank(writer);
        sRegistry.record(headBeforeA, migrationA);

        bytes32 headBeforeB = sRegistry.head(writer);
        vm.prank(writer);
        sRegistry.record(headBeforeB, migrationB);

        assertEq(sRegistry.head(writer), migrationB);
        assertEq(sRegistry.applied(writer, migrationA), block.timestamp);
        assertEq(sRegistry.applied(writer, migrationB), block.timestamp);
    }

    /// The zero namespace is refused rather than answered genesis. It is
    /// provably empty forever, so "nothing has been applied here" is true of it
    /// and false of whatever the caller meant to ask about — and a caller that
    /// believed it would send a first migration at it.
    function testHeadZeroWriterReverts() external {
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.ZeroWriter.selector));
        sRegistry.head(address(0));
    }

    /// Refused on a registry holding records exactly as on an empty one, and
    /// the refusal changes nothing.
    function testHeadZeroWriterRevertsWithRecordsPresent(address writer, bytes32 migration) external {
        vm.assume(writer != address(0));
        assumeMigration(migration);

        vm.prank(writer);
        sRegistry.record(MIGRATION_HEAD_GENESIS, migration);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.ZeroWriter.selector));
        sRegistry.head(address(0));

        assertEq(sRegistry.head(writer), migration);
    }

    /// A head is never zero, in any namespace state, which is what lets a
    /// consumer treat a zero answer as "this is not the registry" rather than as
    /// a namespace.
    function testHeadIsNeverZero(address writer, bytes32 migration) external {
        vm.assume(writer != address(0));
        assumeMigration(migration);

        assertTrue(sRegistry.head(writer) != bytes32(0));

        vm.prank(writer);
        sRegistry.record(MIGRATION_HEAD_GENESIS, migration);

        assertTrue(sRegistry.head(writer) != bytes32(0));
    }

    /// A refused record leaves the head where it was. The head moves only for a
    /// migration that was actually recorded, so it can never describe a step
    /// that did not happen.
    function testHeadUnmovedByRefusedRecord(address writer, bytes32 migration, bytes32 wrongHead) external {
        vm.assume(writer != address(0));
        assumeMigration(migration);
        assumeMigration(wrongHead);
        vm.assume(wrongHead != migration);

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV1.UnexpectedMigrationHead.selector, writer, wrongHead, MIGRATION_HEAD_GENESIS
            )
        );
        vm.prank(writer);
        sRegistry.record(wrongHead, migration);

        assertEq(sRegistry.head(writer), MIGRATION_HEAD_GENESIS);
    }
}
