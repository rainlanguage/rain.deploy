// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";

import {IMigrationRegistryV1} from "../../../src/interface/IMigrationRegistryV1.sol";
import {MigrationRegistry} from "../../../src/concrete/MigrationRegistry.sol";

/// @title MigrationRegistryAppliedTest
/// @notice A test suite for `MigrationRegistry.applied`: it answers a recorded
/// migration `true`, an unrecorded one `false`, refuses the two inputs that can
/// only be mistakes, and is the only reader.
contract MigrationRegistryAppliedTest is Test {
    /// The registry under test. Stateful, so a fresh one per test.
    MigrationRegistry internal sRegistry;

    function setUp() external {
        sRegistry = new MigrationRegistry();
    }

    /// An unrecorded migration answers `false` rather than reverting. This is
    /// the deliberate difference from a registry whose reads revert on an
    /// unknown key: "not applied here" is the ordinary state of every migration
    /// before it runs and of every migration on a chain that never got it, and
    /// it is the answer a caller branches on to assert the pre-migration state
    /// exactly. A revert would leave the caller with nothing to say about the
    /// state it is actually looking at.
    function testAppliedUnrecordedIsFalse(address writer, bytes32 migration) external view {
        vm.assume(writer != address(0));
        vm.assume(migration != bytes32(0));

        assertFalse(sRegistry.applied(writer, migration));
    }

    /// Reading does not consume or alter a record, so the same question asked
    /// twice answers the same way.
    function testAppliedIsIdempotent(address writer, bytes32 migration) external {
        vm.assume(writer != address(0));
        vm.assume(migration != bytes32(0));

        vm.prank(writer);
        sRegistry.record(migration);

        assertTrue(sRegistry.applied(writer, migration));
        assertTrue(sRegistry.applied(writer, migration));
    }

    /// The zero writer is refused rather than answered. No transaction
    /// originates from the zero address, so that namespace is provably empty
    /// and `false` would be the answer forever — an unresolved writer constant
    /// would read as "nothing has been applied" instead of as the mistake it
    /// is, and send its caller down the pre-migration branch on every chain.
    function testAppliedZeroWriterReverts(bytes32 migration) external {
        vm.assume(migration != bytes32(0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.ZeroWriter.selector));
        sRegistry.applied(address(0), migration);
    }

    /// The zero migration id is refused for the same reason in the other
    /// direction: `record` will not write it, so it can never be a real record.
    function testAppliedZeroMigrationReverts(address writer) external {
        vm.assume(writer != address(0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.ZeroMigration.selector));
        sRegistry.applied(writer, bytes32(0));
    }

    /// The writer is checked before the migration, so a caller that has zeroed
    /// both is told about the namespace first and gets one stable answer rather
    /// than one that depends on which check happens to run.
    function testAppliedZeroWriterCheckedFirst() external {
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.ZeroWriter.selector));
        sRegistry.applied(address(0), bytes32(0));
    }

    /// A refusal is not a state change: the zero cases revert on a registry
    /// that holds records exactly as they do on an empty one, and leave those
    /// records intact.
    function testAppliedZeroRefusalLeavesRecordsIntact(address writer, bytes32 migration) external {
        vm.assume(writer != address(0));
        vm.assume(migration != bytes32(0));

        vm.prank(writer);
        sRegistry.record(migration);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.ZeroWriter.selector));
        sRegistry.applied(address(0), migration);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.ZeroMigration.selector));
        sRegistry.applied(writer, bytes32(0));

        assertTrue(sRegistry.applied(writer, migration));
    }

    /// `applied` is the only reader. The records mapping is not `public`, so
    /// the getter a `public` mapping would generate — which answers the zero
    /// writer and the zero migration with `false`, the exact silent
    /// wrong-branch these refusals exist to prevent — does not exist.
    function testAppliedNoGeneratedMappingGetter(address writer, bytes32 migration) external {
        (bool success,) =
            address(sRegistry).call(abi.encodeWithSignature("sApplied(address,bytes32)", writer, migration));
        assertFalse(success);
    }

    /// There is no other entry point at all: no fallback, no receive, and
    /// nothing beyond the two `IMigrationRegistryV1` functions, so an unknown
    /// selector reverts instead of being silently absorbed.
    function testAppliedNoOtherEntryPoint(bytes4 selector, bytes32 migration) external {
        vm.assume(selector != IMigrationRegistryV1.applied.selector);
        vm.assume(selector != IMigrationRegistryV1.record.selector);

        (bool success,) = address(sRegistry).call(abi.encodeWithSelector(selector, address(this), migration));
        assertFalse(success);
    }
}
