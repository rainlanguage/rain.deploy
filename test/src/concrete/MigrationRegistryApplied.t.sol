// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";

import {IMigrationRegistryV1, MIGRATION_HEAD_GENESIS} from "../../../src/interface/IMigrationRegistryV1.sol";
import {MigrationRegistry} from "../../../src/concrete/MigrationRegistry.sol";

/// @title MigrationRegistryAppliedTest
/// @notice A test suite for `MigrationRegistry.applied`: it answers an applied
/// migration with the moment it was applied, an unapplied one with zero,
/// refuses the three inputs that can only be mistakes, and is the only reader of
/// the records.
contract MigrationRegistryAppliedTest is Test {
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

    /// An unapplied migration answers zero rather than reverting. This is
    /// the deliberate difference from a registry whose reads revert on an
    /// unknown key: "not applied here" is the ordinary state of every migration
    /// before it runs and of every migration on a chain that never got it, and
    /// it is the answer a caller branches on to assert the pre-migration state
    /// exactly. A revert would leave the caller with nothing to say about the
    /// state it is actually looking at.
    function testAppliedUnappliedIsZero(address writer, bytes32 migration) external view {
        vm.assume(writer != address(0));
        assumeMigration(migration);

        assertEq(sRegistry.applied(writer, migration), 0);
    }

    /// An applied migration answers the timestamp of the block it was applied
    /// in, and keeps answering it as time moves on. The value is when the
    /// migration was applied, not how long ago or how recently anything was
    /// asked.
    function testAppliedIsTheApplicationTimestamp(address writer, bytes32 migration, uint32 appliedAt, uint32 readAt)
        external
    {
        vm.assume(writer != address(0));
        assumeMigration(migration);
        vm.assume(appliedAt != 0);
        vm.assume(readAt >= appliedAt);

        vm.warp(appliedAt);
        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migration);

        vm.warp(readAt);
        assertEq(sRegistry.applied(writer, migration), appliedAt);
    }

    /// Reading does not consume or alter a record, so the same question asked
    /// twice answers the same way.
    function testAppliedIsIdempotent(address writer, bytes32 migration) external {
        vm.assume(writer != address(0));
        assumeMigration(migration);

        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migration);

        assertEq(sRegistry.applied(writer, migration), block.timestamp);
        assertEq(sRegistry.applied(writer, migration), block.timestamp);
    }

    /// The zero writer is refused rather than answered. No transaction
    /// originates from the zero address, so that namespace is provably empty
    /// and zero would be the answer forever — an unresolved writer constant
    /// would read as "nothing has been applied" instead of as the mistake it
    /// is, and send its caller down the pre-migration branch on every chain.
    function testAppliedZeroWriterReverts(bytes32 migration) external {
        assumeMigration(migration);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.ZeroWriter.selector));
        sRegistry.applied(address(0), migration);
    }

    /// The zero migration id is refused for the same reason in the other
    /// direction: `applyMigration` will not write it, so it can never be a real
    /// record.
    function testAppliedZeroMigrationReverts(address writer) external {
        vm.assume(writer != address(0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.ZeroMigration.selector));
        sRegistry.applied(writer, bytes32(0));
    }

    /// The genesis head is refused as a migration for the same reason again:
    /// `applyMigration` will not write it either, so asking about it would
    /// answer zero forever to a caller that has confused a head for a migration
    /// — and that
    /// caller reads zero as its pre-migration branch.
    function testAppliedGenesisMigrationReverts(address writer) external {
        vm.assume(writer != address(0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.GenesisMigration.selector));
        sRegistry.applied(writer, MIGRATION_HEAD_GENESIS);
    }

    /// The writer is checked before the migration, so a caller that has zeroed
    /// both is told about the namespace first and gets one stable answer rather
    /// than one that depends on which check happens to run.
    function testAppliedZeroWriterCheckedFirst() external {
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.ZeroWriter.selector));
        sRegistry.applied(address(0), bytes32(0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.ZeroWriter.selector));
        sRegistry.applied(address(0), MIGRATION_HEAD_GENESIS);
    }

    /// A refusal is not a state change: the refused cases revert on a registry
    /// that holds records exactly as they do on an empty one, and leave those
    /// records intact.
    function testAppliedRefusalLeavesRecordsIntact(address writer, bytes32 migration) external {
        vm.assume(writer != address(0));
        assumeMigration(migration);

        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migration);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.ZeroWriter.selector));
        sRegistry.applied(address(0), migration);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.ZeroMigration.selector));
        sRegistry.applied(writer, bytes32(0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.GenesisMigration.selector));
        sRegistry.applied(writer, MIGRATION_HEAD_GENESIS);

        assertEq(sRegistry.applied(writer, migration), block.timestamp);
        assertEq(sRegistry.head(writer), migration);
    }

    /// `applied` is the only reader of the records. The records mapping is not
    /// `public`, so the getter a `public` mapping would generate — which answers
    /// the zero writer and both refused ids with zero, the exact silent
    /// wrong-branch these refusals exist to prevent — does not exist.
    function testAppliedNoGeneratedMappingGetter(address writer, bytes32 migration) external {
        (bool success,) =
            address(sRegistry).call(abi.encodeWithSignature("sApplied(address,bytes32)", writer, migration));
        assertFalse(success);
    }

    /// Nor for the heads, where a generated getter would be worse still: it
    /// answers an empty namespace with zero, and zero is a value no head can
    /// ever hold.
    function testAppliedNoGeneratedHeadGetter(address writer) external {
        (bool success,) = address(sRegistry).call(abi.encodeWithSignature("sHead(address)", writer));
        assertFalse(success);
    }

    /// There is no other entry point at all: no fallback, no receive, and
    /// nothing beyond the three `IMigrationRegistryV1` functions, so an unknown
    /// selector reverts instead of being silently absorbed.
    function testAppliedNoOtherEntryPoint(bytes4 selector, bytes32 migration) external {
        vm.assume(selector != IMigrationRegistryV1.applied.selector);
        vm.assume(selector != IMigrationRegistryV1.applyMigration.selector);
        vm.assume(selector != IMigrationRegistryV1.head.selector);

        (bool success,) = address(sRegistry).call(abi.encodeWithSelector(selector, address(this), migration));
        assertFalse(success);
    }
}
