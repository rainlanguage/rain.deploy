// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";

import {IMigrationRegistryV1, Prerequisite} from "../../../src/interface/IMigrationRegistryV1.sol";
import {MigrationRegistry} from "../../../src/concrete/MigrationRegistry.sol";
import {LibMigrationFuzz} from "../../lib/LibMigrationFuzz.sol";

/// @title MigrationRegistryAppliedTest
/// @notice `MigrationRegistry.applied`: the recorded moment for an applied
/// migration, zero for an unapplied one, a refusal for the two keys that can
/// only be mistakes, and the only reader there is.
contract MigrationRegistryAppliedTest is Test {
    MigrationRegistry internal sRegistry;

    function setUp() external {
        sRegistry = new MigrationRegistry();
    }

    function testAppliedUnappliedIsZero(address writer, bytes32 migration) external view {
        LibMigrationFuzz.assumeKey(vm, writer, migration);

        assertEq(sRegistry.applied(writer, migration), 0);
    }

    /// The answer is when the migration ran, not when the record was written
    /// and not when it was read.
    function testAppliedIsTheRecordedMoment(
        address writer,
        bytes32 migration,
        uint32 appliedAt,
        uint32 writtenAt,
        uint32 readAt
    ) external {
        LibMigrationFuzz.assumeKey(vm, writer, migration);
        vm.assume(appliedAt != 0);
        vm.assume(writtenAt >= appliedAt);
        vm.assume(readAt >= writtenAt);

        vm.warp(writtenAt);
        vm.prank(writer);
        sRegistry.applyMigrationHistory(migration, appliedAt, new Prerequisite[](0));

        vm.warp(readAt);
        assertEq(sRegistry.applied(writer, migration), appliedAt);
        assertLe(sRegistry.applied(writer, migration), block.timestamp);
    }

    function testAppliedIsIdempotent(address writer, bytes32 migration) external {
        LibMigrationFuzz.assumeKey(vm, writer, migration);

        vm.prank(writer);
        sRegistry.applyMigration(migration, new Prerequisite[](0));

        assertEq(sRegistry.applied(writer, migration), block.timestamp);
        assertEq(sRegistry.applied(writer, migration), block.timestamp);
    }

    function testAppliedIsPerWriter(address writer, address other, bytes32 migration) external {
        LibMigrationFuzz.assumeKey(vm, writer, migration);
        vm.assume(other != address(0));
        vm.assume(other != writer);

        vm.prank(writer);
        sRegistry.applyMigration(migration, new Prerequisite[](0));

        assertEq(sRegistry.applied(writer, migration), block.timestamp);
        assertEq(sRegistry.applied(other, migration), 0);
    }

    function testAppliedZeroWriterReverts(bytes32 migration) external {
        LibMigrationFuzz.assumeMigration(vm, migration);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.ZeroWriter.selector));
        sRegistry.applied(address(0), migration);
    }

    function testAppliedZeroMigrationReverts(address writer) external {
        vm.assume(writer != address(0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.ZeroMigration.selector));
        sRegistry.applied(writer, bytes32(0));
    }

    /// Both zero trips both refusals; the writer's is the one reported.
    function testAppliedZeroWriterCheckedFirst() external {
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.ZeroWriter.selector));
        sRegistry.applied(address(0), bytes32(0));
    }

    function testAppliedRefusalLeavesRecordsIntact(address writer, bytes32 migration) external {
        LibMigrationFuzz.assumeKey(vm, writer, migration);

        vm.prank(writer);
        sRegistry.applyMigration(migration, new Prerequisite[](0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.ZeroWriter.selector));
        sRegistry.applied(address(0), migration);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.ZeroMigration.selector));
        sRegistry.applied(writer, bytes32(0));

        assertEq(sRegistry.applied(writer, migration), block.timestamp);
    }

    /// The mapping is not `public`: a generated getter would answer the zero
    /// writer and the zero migration with zero.
    function testAppliedNoGeneratedMappingGetter(address writer, bytes32 migration) external {
        (bool success,) =
            address(sRegistry).call(abi.encodeWithSignature("sApplied(address,bytes32)", writer, migration));
        assertFalse(success);
    }

    /// No fallback, no receive, nothing beyond the three interface functions.
    function testAppliedNoOtherEntryPoint(bytes4 selector, bytes32 migration) external {
        vm.assume(selector != IMigrationRegistryV1.applied.selector);
        vm.assume(selector != IMigrationRegistryV1.applyMigration.selector);
        vm.assume(selector != IMigrationRegistryV1.applyMigrationHistory.selector);

        (bool success,) = address(sRegistry).call(abi.encodeWithSelector(selector, address(this), migration));
        assertFalse(success);
    }
}
