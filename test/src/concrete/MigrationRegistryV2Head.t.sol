// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";

import {IMigrationRegistryV2, MIGRATION_HEAD_GENESIS} from "../../../src/interface/IMigrationRegistryV2.sol";
import {MigrationRegistryV2} from "../../../src/concrete/MigrationRegistryV2.sol";

/// @title MigrationRegistryV2HeadTest
/// @notice A test suite for `MigrationRegistryV2.head`: where a namespace is,
/// what an empty one answers, that the answer is never a value that is not a
/// head, and that it is the same answer `applyMigration` checks against.
contract MigrationRegistryV2HeadTest is Test {
    /// The registry under test. Stateful, so a fresh one per test.
    MigrationRegistryV2 internal sRegistry;

    function setUp() external {
        sRegistry = new MigrationRegistryV2();
    }

    /// A migration id that is neither of the two values the head space reserves.
    /// @param migration The fuzzed candidate.
    function assumeMigration(bytes32 migration) internal pure {
        vm.assume(migration != bytes32(0));
        vm.assume(migration != MIGRATION_HEAD_GENESIS);
    }

    /// A namespace that has applied nothing is at genesis, which is an ANSWER
    /// rather than a revert for the same reason an unapplied migration answers
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

    /// Genesis holds no record, which is what makes an empty namespace's floor
    /// zero: `applyMigration` reads the record of whatever head it is applying
    /// onto, and for a namespace that has applied nothing that read is of a key
    /// nothing can ever be written against.
    function testHeadGenesisHoldsNoRecord(address writer, bytes32 migration, uint32 appliedAt) external {
        vm.assume(writer != address(0));
        assumeMigration(migration);
        vm.assume(appliedAt != 0);
        vm.warp(appliedAt);

        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migration, appliedAt);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.GenesisMigration.selector));
        sRegistry.applied(writer, MIGRATION_HEAD_GENESIS);
    }

    /// The head is the migration applied most recently, and it moves with each
    /// one.
    function testHeadFollowsTheRecords(address writer, bytes32 migrationA, bytes32 migrationB) external {
        vm.assume(writer != address(0));
        assumeMigration(migrationA);
        assumeMigration(migrationB);
        vm.assume(migrationA != migrationB);

        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migrationA, block.timestamp);
        assertEq(sRegistry.head(writer), migrationA);

        vm.prank(writer);
        sRegistry.applyMigration(migrationA, migrationB, block.timestamp);
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
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migration, block.timestamp);

        assertEq(sRegistry.head(writer), migration);
        assertEq(sRegistry.head(other), MIGRATION_HEAD_GENESIS);
    }

    /// The head `head` reports is exactly the head `applyMigration` demands:
    /// whatever this answers is accepted, and it is the only value that is. The
    /// two go through one translation of an empty namespace, so they cannot
    /// disagree about where one is.
    function testHeadIsWhatApplyMigrationAccepts(address writer, bytes32 migrationA, bytes32 migrationB) external {
        vm.assume(writer != address(0));
        assumeMigration(migrationA);
        assumeMigration(migrationB);
        vm.assume(migrationA != migrationB);

        // Hoisted, because `vm.prank` applies to the next call and reading the
        // head is a call.
        bytes32 headBeforeA = sRegistry.head(writer);
        vm.prank(writer);
        sRegistry.applyMigration(headBeforeA, migrationA, block.timestamp);

        bytes32 headBeforeB = sRegistry.head(writer);
        vm.prank(writer);
        sRegistry.applyMigration(headBeforeB, migrationB, block.timestamp);

        assertEq(sRegistry.head(writer), migrationB);
        assertEq(sRegistry.applied(writer, migrationA), block.timestamp);
        assertEq(sRegistry.applied(writer, migrationB), block.timestamp);
    }

    /// The zero namespace is refused rather than answered genesis. It is
    /// provably empty forever, so "nothing has been applied here" is true of it
    /// and false of whatever the caller meant to ask about — and a caller that
    /// believed it would send a first migration at it.
    function testHeadZeroWriterReverts() external {
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroWriter.selector));
        sRegistry.head(address(0));
    }

    /// Refused on a registry holding records exactly as on an empty one, and
    /// the refusal changes nothing.
    function testHeadZeroWriterRevertsWithRecordsPresent(address writer, bytes32 migration) external {
        vm.assume(writer != address(0));
        assumeMigration(migration);

        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migration, block.timestamp);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroWriter.selector));
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
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migration, block.timestamp);

        assertTrue(sRegistry.head(writer) != bytes32(0));
    }

    /// A refused apply leaves the head where it was. The head moves only for a
    /// migration that was actually applied, so it can never describe a step
    /// that did not happen.
    function testHeadUnmovedByRefusedApplyMigration(address writer, bytes32 migration, bytes32 wrongHead) external {
        vm.assume(writer != address(0));
        assumeMigration(migration);
        assumeMigration(wrongHead);
        vm.assume(wrongHead != migration);

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.UnexpectedMigrationHead.selector, writer, wrongHead, MIGRATION_HEAD_GENESIS
            )
        );
        vm.prank(writer);
        sRegistry.applyMigration(wrongHead, migration, block.timestamp);

        assertEq(sRegistry.head(writer), MIGRATION_HEAD_GENESIS);
    }
}
