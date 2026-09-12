// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, Vm} from "forge-std-1.16.2/src/Test.sol";

import {IMigrationRegistryV1, Prerequisite} from "../../../src/interface/IMigrationRegistryV1.sol";
import {MigrationRegistry} from "../../../src/concrete/MigrationRegistry.sol";
import {LibMigrationFuzz} from "../../lib/LibMigrationFuzz.sol";

/// @title MigrationRegistryApplyMigrationHistoryTest
/// @notice `MigrationRegistry.applyMigrationHistory`: the supplied moment and
/// its two bounds, where those bounds sit among the other refusals, and that it
/// is otherwise `applyMigration`.
contract MigrationRegistryApplyMigrationHistoryTest is Test {
    MigrationRegistry internal sRegistry;

    function setUp() external {
        sRegistry = new MigrationRegistry();
    }

    /// The caller's moment is recorded, not the block the record landed in.
    function testApplyMigrationHistoryRecordsTheSuppliedMoment(
        address writer,
        bytes32 migration,
        uint32 appliedAt,
        uint32 writtenAt
    ) external {
        LibMigrationFuzz.assumeKey(vm, writer, migration);
        vm.assume(appliedAt != 0);
        vm.assume(writtenAt > appliedAt);
        vm.warp(writtenAt);

        vm.prank(writer);
        sRegistry.applyMigrationHistory(migration, appliedAt, new Prerequisite[](0));

        assertEq(sRegistry.applied(writer, migration), appliedAt);
        assertTrue(sRegistry.applied(writer, migration) != block.timestamp);
    }

    function testApplyMigrationHistoryCurrentBlockIsAccepted(address writer, bytes32 migration, uint32 now_) external {
        LibMigrationFuzz.assumeKey(vm, writer, migration);
        vm.assume(now_ != 0);
        vm.warp(now_);

        vm.prank(writer);
        sRegistry.applyMigrationHistory(migration, block.timestamp, new Prerequisite[](0));

        assertEq(sRegistry.applied(writer, migration), now_);
    }

    /// The two writes make the same record when the moment is this block, slot
    /// for slot.
    function testApplyMigrationAndHistoryWriteTheSameRecord(
        address writer,
        address other,
        bytes32 migration,
        bytes32 prerequisite,
        uint32 now_
    ) external {
        LibMigrationFuzz.assumeKey(vm, writer, migration);
        LibMigrationFuzz.assumeKey(vm, other, prerequisite);
        vm.assume(migration != prerequisite);
        vm.assume(now_ != 0);
        vm.warp(now_);
        Prerequisite[] memory prerequisites = LibMigrationFuzz.one(other, prerequisite);

        MigrationRegistry stamping = new MigrationRegistry();
        MigrationRegistry supplied = new MigrationRegistry();
        vm.prank(other);
        stamping.applyMigration(prerequisite, new Prerequisite[](0));
        vm.prank(other);
        supplied.applyMigration(prerequisite, new Prerequisite[](0));

        vm.record();
        vm.prank(writer);
        stamping.applyMigration(migration, prerequisites);
        (, bytes32[] memory stampingWrites) = vm.accesses(address(stamping));
        vm.prank(writer);
        supplied.applyMigrationHistory(migration, block.timestamp, prerequisites);
        (, bytes32[] memory suppliedWrites) = vm.accesses(address(supplied));

        assertEq(suppliedWrites, stampingWrites);
        assertEq(stamping.applied(writer, migration), supplied.applied(writer, migration));
        assertEq(supplied.applied(writer, migration), now_);
    }

    function testApplyMigrationHistoryFutureTimestampReverts(
        address writer,
        bytes32 migration,
        uint32 now_,
        uint256 appliedAt
    ) external {
        LibMigrationFuzz.assumeKey(vm, writer, migration);
        vm.warp(now_);
        appliedAt = bound(appliedAt, uint256(now_) + 1, type(uint256).max);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.FutureTimestamp.selector, appliedAt, now_));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(migration, appliedAt, new Prerequisite[](0));

        assertEq(sRegistry.applied(writer, migration), 0);
    }

    /// One second after the block is refused; the block itself is accepted.
    function testApplyMigrationHistoryFutureBoundary(address writer, bytes32 migration, uint32 now_) external {
        LibMigrationFuzz.assumeKey(vm, writer, migration);
        vm.assume(now_ != 0);
        vm.warp(now_);

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV1.FutureTimestamp.selector, uint256(now_) + 1, uint256(now_))
        );
        vm.prank(writer);
        sRegistry.applyMigrationHistory(migration, uint256(now_) + 1, new Prerequisite[](0));

        vm.prank(writer);
        sRegistry.applyMigrationHistory(migration, now_, new Prerequisite[](0));
        assertEq(sRegistry.applied(writer, migration), now_);
    }

    function testApplyMigrationHistoryZeroTimestampReverts(address writer, bytes32 migration, uint32 now_) external {
        LibMigrationFuzz.assumeKey(vm, writer, migration);
        vm.warp(now_);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.ZeroTimestamp.selector));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(migration, 0, new Prerequisite[](0));

        assertEq(sRegistry.applied(writer, migration), 0);
    }

    /// In a zero block every nonzero moment is in the future, so nothing can
    /// be recorded.
    function testApplyMigrationHistoryZeroBlockRecordsNothing(address writer, bytes32 migration, uint256 appliedAt)
        external
    {
        LibMigrationFuzz.assumeKey(vm, writer, migration);
        vm.warp(0);

        if (appliedAt == 0) {
            vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.ZeroTimestamp.selector));
        } else {
            vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.FutureTimestamp.selector, appliedAt, 0));
        }
        vm.prank(writer);
        sRegistry.applyMigrationHistory(migration, appliedAt, new Prerequisite[](0));

        assertEq(sRegistry.applied(writer, migration), 0);
    }

    /// A zero id with a zero moment and a malformed prerequisite: the id is
    /// reported.
    function testApplyMigrationHistoryIdCheckedBeforeTimestamp(address writer, bytes32 other) external {
        vm.assume(writer != address(0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.ZeroMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(bytes32(0), 0, LibMigrationFuzz.one(address(0), other));
    }

    /// A zero or future moment with a malformed, unapplied prerequisite on an
    /// already applied migration: the moment is reported.
    function testApplyMigrationHistoryTimestampCheckedBeforePrerequisitesAndNamespace(
        address writer,
        bytes32 migration,
        bytes32 other,
        uint32 now_
    ) external {
        LibMigrationFuzz.assumeKey(vm, writer, migration);
        vm.assume(now_ != 0);
        vm.warp(now_);
        vm.prank(writer);
        sRegistry.applyMigration(migration, new Prerequisite[](0));
        Prerequisite[] memory malformed = LibMigrationFuzz.one(address(0), other);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.ZeroTimestamp.selector));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(migration, 0, malformed);

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV1.FutureTimestamp.selector, uint256(now_) + 1, uint256(now_))
        );
        vm.prank(writer);
        sRegistry.applyMigrationHistory(migration, uint256(now_) + 1, malformed);
    }

    /// An unapplied prerequisite on an already applied migration, with a valid
    /// moment: the prerequisite is reported.
    function testApplyMigrationHistoryPrerequisitesCheckedBeforeAlreadyApplied(
        address writer,
        address other,
        bytes32 migration,
        bytes32 prerequisite,
        uint32 now_
    ) external {
        LibMigrationFuzz.assumeKey(vm, writer, migration);
        LibMigrationFuzz.assumeKey(vm, other, prerequisite);
        vm.assume(writer != other || migration != prerequisite);
        vm.assume(now_ != 0);
        vm.warp(now_);
        vm.prank(writer);
        sRegistry.applyMigration(migration, new Prerequisite[](0));

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV1.PrerequisiteNotApplied.selector, other, prerequisite)
        );
        vm.prank(writer);
        sRegistry.applyMigrationHistory(migration, now_, LibMigrationFuzz.one(other, prerequisite));

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV1.MigrationAlreadyApplied.selector, writer, migration)
        );
        vm.prank(writer);
        sRegistry.applyMigrationHistory(migration, now_, new Prerequisite[](0));
    }

    /// Over a list with exactly one unapplied entry, the history write names
    /// it too.
    function testApplyMigrationHistoryNamesTheOneUnapplied(
        address writer,
        bytes32 migration,
        bytes32[] memory seeds,
        uint256 index,
        uint32 appliedAt
    ) external {
        LibMigrationFuzz.assumeKey(vm, writer, migration);
        vm.assume(seeds.length > 0);
        vm.assume(seeds.length <= 16);
        vm.assume(appliedAt != 0);
        vm.warp(appliedAt);
        index = bound(index, 0, seeds.length - 1);
        Prerequisite[] memory prerequisites = LibMigrationFuzz.keysFromSeeds(vm, seeds);
        for (uint256 i = 0; i < prerequisites.length; i++) {
            vm.assume(prerequisites[i].migration != migration);
            if (i != index && sRegistry.applied(prerequisites[i].writer, prerequisites[i].migration) == 0) {
                vm.prank(prerequisites[i].writer);
                sRegistry.applyMigration(prerequisites[i].migration, new Prerequisite[](0));
            }
        }
        vm.assume(sRegistry.applied(prerequisites[index].writer, prerequisites[index].migration) == 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV1.PrerequisiteNotApplied.selector,
                prerequisites[index].writer,
                prerequisites[index].migration
            )
        );
        vm.prank(writer);
        sRegistry.applyMigrationHistory(migration, appliedAt, prerequisites);
        assertEq(sRegistry.applied(writer, migration), 0);
    }

    /// A backfilled record may carry a moment earlier than its prerequisite's:
    /// what is checked is that the record exists, which is chain order.
    function testApplyMigrationHistoryMomentIsNotBoundedByThePrerequisite(
        address writer,
        address other,
        bytes32 migration,
        bytes32 prerequisite,
        uint32 appliedAt,
        uint32 prerequisiteAt
    ) external {
        LibMigrationFuzz.assumeKey(vm, writer, migration);
        LibMigrationFuzz.assumeKey(vm, other, prerequisite);
        vm.assume(writer != other || migration != prerequisite);
        vm.assume(appliedAt != 0);
        vm.assume(prerequisiteAt > appliedAt);
        vm.warp(prerequisiteAt);
        vm.prank(other);
        sRegistry.applyMigration(prerequisite, new Prerequisite[](0));

        vm.prank(writer);
        sRegistry.applyMigrationHistory(migration, appliedAt, LibMigrationFuzz.one(other, prerequisite));

        assertEq(sRegistry.applied(writer, migration), appliedAt);
        assertLt(sRegistry.applied(writer, migration), sRegistry.applied(other, prerequisite));
    }

    /// `Migrated` carries the caller's moment, not the block.
    function testApplyMigrationHistoryEvent(
        address writer,
        address other,
        bytes32 migration,
        bytes32 prerequisite,
        uint32 appliedAt,
        uint32 writtenAt
    ) external {
        LibMigrationFuzz.assumeKey(vm, writer, migration);
        LibMigrationFuzz.assumeKey(vm, other, prerequisite);
        vm.assume(migration != prerequisite);
        vm.assume(appliedAt != 0);
        vm.assume(writtenAt > appliedAt);
        vm.warp(writtenAt);
        vm.prank(other);
        sRegistry.applyMigration(prerequisite, new Prerequisite[](0));
        Prerequisite[] memory prerequisites = LibMigrationFuzz.one(other, prerequisite);

        vm.recordLogs();
        vm.prank(writer);
        sRegistry.applyMigrationHistory(migration, appliedAt, prerequisites);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        assertEq(entries.length, 1);
        assertEq(entries[0].emitter, address(sRegistry));
        assertEq(entries[0].topics.length, 3);
        assertEq(entries[0].topics[0], keccak256("Migrated(address,bytes32,uint256,(address,bytes32)[])"));
        assertEq(entries[0].topics[1], bytes32(uint256(uint160(writer))));
        assertEq(entries[0].topics[2], migration);
        assertEq(entries[0].data, abi.encode(uint256(appliedAt), prerequisites));
    }

    /// The two refusals this write adds emit nothing.
    function testApplyMigrationHistoryNoEventOnRevert(address writer, bytes32 migration) external {
        LibMigrationFuzz.assumeKey(vm, writer, migration);
        vm.warp(1000);

        vm.recordLogs();
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.ZeroTimestamp.selector));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(migration, 0, new Prerequisite[](0));
        assertEq(vm.getRecordedLogs().length, 0);

        vm.recordLogs();
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.FutureTimestamp.selector, 1001, 1000));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(migration, 1001, new Prerequisite[](0));
        assertEq(vm.getRecordedLogs().length, 0);
    }
}
