// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";

import {Prerequisite, MIGRATION_HEAD_GENESIS} from "../../../src/interface/IMigrationRegistryV2.sol";
import {IMigrationRegistryV3} from "../../../src/interface/IMigrationRegistryV3.sol";
import {MigrationRegistry} from "../../../src/concrete/MigrationRegistry.sol";

/// @title MigrationRegistryDelegateTest
/// @notice A test suite for delegated writes: a writer approves a delegate per
/// namespace, the delegate writes the writer's line and nothing else, and a
/// revoked or unapproved caller is refused.
contract MigrationRegistryDelegateTest is Test {
    /// The registry under test. Stateful, so a fresh one per test.
    MigrationRegistry internal sRegistry;

    address internal constant WRITER = address(0x1111);
    address internal constant DELEGATE = address(0x2222);
    bytes32 internal constant NAMESPACE = keccak256("namespace");
    bytes32 internal constant MIGRATION = keccak256("migration");
    bytes32 internal constant SECOND = keccak256("second");

    function setUp() external {
        sRegistry = new MigrationRegistry();
    }

    function onto(address writer, bytes32 namespace, bytes32 head) internal pure returns (Prerequisite[] memory) {
        Prerequisite[] memory prerequisites = new Prerequisite[](1);
        prerequisites[0] = Prerequisite({writer: writer, namespace: namespace, migration: head});
        return prerequisites;
    }

    function approveDelegate() internal {
        vm.prank(WRITER);
        sRegistry.approveV3(NAMESPACE, DELEGATE);
    }

    /// Nothing is approved until the writer approves it.
    function testApprovedIsFalseUntilApproved(address writer, bytes32 namespace, address delegate) external view {
        vm.assume(writer != address(0) && namespace != bytes32(0) && delegate != address(0));
        assertFalse(sRegistry.approvedV3(writer, namespace, delegate));
    }

    /// An approval is the caller's, for one namespace, and is emitted.
    function testApproveIsPerWriterAndNamespace(bytes32 otherNamespace, address otherWriter) external {
        vm.assume(otherNamespace != NAMESPACE && otherNamespace != bytes32(0));
        vm.assume(otherWriter != WRITER && otherWriter != address(0));
        vm.expectEmit(address(sRegistry));
        emit IMigrationRegistryV3.Approved(WRITER, NAMESPACE, DELEGATE);
        approveDelegate();
        assertTrue(sRegistry.approvedV3(WRITER, NAMESPACE, DELEGATE));
        assertFalse(sRegistry.approvedV3(WRITER, otherNamespace, DELEGATE));
        assertFalse(sRegistry.approvedV3(otherWriter, NAMESPACE, DELEGATE));
    }

    /// Approving twice leaves it approved; revoking removes it and is emitted;
    /// revoking twice leaves it revoked.
    function testRevokeRemovesTheApproval() external {
        approveDelegate();
        approveDelegate();
        assertTrue(sRegistry.approvedV3(WRITER, NAMESPACE, DELEGATE));
        vm.expectEmit(address(sRegistry));
        emit IMigrationRegistryV3.Revoked(WRITER, NAMESPACE, DELEGATE);
        vm.prank(WRITER);
        sRegistry.revokeV3(NAMESPACE, DELEGATE);
        assertFalse(sRegistry.approvedV3(WRITER, NAMESPACE, DELEGATE));
        vm.prank(WRITER);
        sRegistry.revokeV3(NAMESPACE, DELEGATE);
        assertFalse(sRegistry.approvedV3(WRITER, NAMESPACE, DELEGATE));
    }

    /// The zero namespace and the zero delegate name no approval.
    function testApproveAndRevokeRefuseZeroes() external {
        vm.startPrank(WRITER);
        vm.expectRevert(IMigrationRegistryV3.ZeroNamespace.selector);
        sRegistry.approveV3(bytes32(0), DELEGATE);
        vm.expectRevert(IMigrationRegistryV3.ZeroDelegate.selector);
        sRegistry.approveV3(NAMESPACE, address(0));
        vm.expectRevert(IMigrationRegistryV3.ZeroNamespace.selector);
        sRegistry.revokeV3(bytes32(0), DELEGATE);
        vm.expectRevert(IMigrationRegistryV3.ZeroDelegate.selector);
        sRegistry.revokeV3(NAMESPACE, address(0));
        vm.stopPrank();
    }

    /// `approvedV3` refuses the zero writer, namespace and delegate.
    function testApprovedRefusesZeroes() external {
        vm.expectRevert(IMigrationRegistryV3.ZeroWriter.selector);
        sRegistry.approvedV3(address(0), NAMESPACE, DELEGATE);
        vm.expectRevert(IMigrationRegistryV3.ZeroNamespace.selector);
        sRegistry.approvedV3(WRITER, bytes32(0), DELEGATE);
        vm.expectRevert(IMigrationRegistryV3.ZeroDelegate.selector);
        sRegistry.approvedV3(WRITER, NAMESPACE, address(0));
    }

    /// An approved delegate writes the writer's line: the record and the head
    /// are the writer's, stamped with the block, and none is the delegate's.
    function testApprovedDelegateWritesTheWritersLine(uint256 moment) external {
        moment = bound(moment, 1, type(uint64).max);
        vm.warp(moment);
        approveDelegate();
        vm.expectEmit(address(sRegistry));
        emit IMigrationRegistryV3.Migrated(WRITER, NAMESPACE, MIGRATION, moment);
        vm.prank(DELEGATE);
        sRegistry.applyMigrationV3(WRITER, NAMESPACE, MIGRATION, onto(WRITER, NAMESPACE, MIGRATION_HEAD_GENESIS));
        assertEq(sRegistry.appliedV3(WRITER, NAMESPACE, MIGRATION), moment);
        assertEq(sRegistry.headV3(WRITER, NAMESPACE), MIGRATION);
        assertEq(sRegistry.appliedV3(DELEGATE, NAMESPACE, MIGRATION), 0);
    }

    /// The history write takes its moment, into the writer's line.
    function testApprovedDelegateWritesHistory(uint256 moment, uint256 appliedAt) external {
        moment = bound(moment, 1, type(uint64).max);
        appliedAt = bound(appliedAt, 1, moment);
        vm.warp(moment);
        approveDelegate();
        vm.prank(DELEGATE);
        sRegistry.applyMigrationHistoryV3(
            WRITER, NAMESPACE, MIGRATION, appliedAt, onto(WRITER, NAMESPACE, MIGRATION_HEAD_GENESIS)
        );
        assertEq(sRegistry.appliedV3(WRITER, NAMESPACE, MIGRATION), appliedAt);
        assertEq(sRegistry.headV3(WRITER, NAMESPACE), MIGRATION);
    }

    /// Two delegates share one line, each onto the other's record.
    function testTwoDelegatesShareOneLine(address other) external {
        vm.assume(other != address(0) && other != DELEGATE && other != WRITER);
        approveDelegate();
        vm.prank(WRITER);
        sRegistry.approveV3(NAMESPACE, other);
        vm.prank(DELEGATE);
        sRegistry.applyMigrationV3(WRITER, NAMESPACE, MIGRATION, onto(WRITER, NAMESPACE, MIGRATION_HEAD_GENESIS));
        vm.prank(other);
        sRegistry.applyMigrationV3(WRITER, NAMESPACE, SECOND, onto(WRITER, NAMESPACE, MIGRATION));
        assertEq(sRegistry.headV3(WRITER, NAMESPACE), SECOND);
        assertEq(sRegistry.appliedOntoV3(WRITER, NAMESPACE, SECOND), MIGRATION);
    }

    /// The writer writes its own line through the delegated entry points
    /// without approving itself.
    function testTheWriterNeedsNoApproval() external {
        vm.startPrank(WRITER);
        sRegistry.applyMigrationV3(WRITER, NAMESPACE, MIGRATION, onto(WRITER, NAMESPACE, MIGRATION_HEAD_GENESIS));
        sRegistry.applyMigrationHistoryV3(
            WRITER, NAMESPACE, SECOND, block.timestamp, onto(WRITER, NAMESPACE, MIGRATION)
        );
        vm.stopPrank();
        assertEq(sRegistry.headV3(WRITER, NAMESPACE), SECOND);
    }

    /// An unapproved caller is refused on both writes, naming the line and
    /// itself.
    function testUnapprovedCallerIsRefused(address caller) external {
        vm.assume(caller != WRITER);
        Prerequisite[] memory prerequisites = onto(WRITER, NAMESPACE, MIGRATION_HEAD_GENESIS);
        vm.startPrank(caller);
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV3.NotApproved.selector, WRITER, NAMESPACE, caller));
        sRegistry.applyMigrationV3(WRITER, NAMESPACE, MIGRATION, prerequisites);
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV3.NotApproved.selector, WRITER, NAMESPACE, caller));
        sRegistry.applyMigrationHistoryV3(WRITER, NAMESPACE, MIGRATION, 1, prerequisites);
        vm.stopPrank();
    }

    /// An approval for one namespace writes no other.
    function testApprovalWritesNoOtherNamespace(bytes32 otherNamespace) external {
        vm.assume(otherNamespace != NAMESPACE && otherNamespace != bytes32(0));
        approveDelegate();
        Prerequisite[] memory prerequisites = onto(WRITER, otherNamespace, MIGRATION_HEAD_GENESIS);
        vm.prank(DELEGATE);
        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV3.NotApproved.selector, WRITER, otherNamespace, DELEGATE)
        );
        sRegistry.applyMigrationV3(WRITER, otherNamespace, MIGRATION, prerequisites);
    }

    /// A revoked delegate is refused, and the record it wrote while approved
    /// stays.
    function testRevokedDelegateIsRefused() external {
        approveDelegate();
        vm.prank(DELEGATE);
        sRegistry.applyMigrationV3(WRITER, NAMESPACE, MIGRATION, onto(WRITER, NAMESPACE, MIGRATION_HEAD_GENESIS));
        vm.prank(WRITER);
        sRegistry.revokeV3(NAMESPACE, DELEGATE);
        vm.prank(DELEGATE);
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV3.NotApproved.selector, WRITER, NAMESPACE, DELEGATE));
        sRegistry.applyMigrationV3(WRITER, NAMESPACE, SECOND, onto(WRITER, NAMESPACE, MIGRATION));
        assertTrue(sRegistry.appliedV3(WRITER, NAMESPACE, MIGRATION) != 0);
    }

    /// A delegated write is refused on the zero writer before any approval
    /// is read.
    function testDelegatedWriteRefusesTheZeroWriter() external {
        Prerequisite[] memory prerequisites = onto(address(0), NAMESPACE, bytes32(0));
        vm.prank(DELEGATE);
        vm.expectRevert(IMigrationRegistryV3.ZeroWriter.selector);
        sRegistry.applyMigrationV3(address(0), NAMESPACE, MIGRATION, prerequisites);
        vm.prank(DELEGATE);
        vm.expectRevert(IMigrationRegistryV3.ZeroWriter.selector);
        sRegistry.applyMigrationHistoryV3(address(0), NAMESPACE, MIGRATION, 1, prerequisites);
    }

    /// A delegate's head entry must name the writer, not itself: the line is
    /// the writer's.
    function testDelegateHeadMustNameTheWriter() external {
        approveDelegate();
        bytes32 genesis = MIGRATION_HEAD_GENESIS;
        vm.prank(DELEGATE);
        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV3.UnexpectedMigrationHead.selector, WRITER, NAMESPACE, NAMESPACE, genesis, genesis
            )
        );
        sRegistry.applyMigrationV3(WRITER, NAMESPACE, MIGRATION, onto(DELEGATE, NAMESPACE, genesis));
    }

    /// A later entry in the writer's own line is the writer's own
    /// prerequisite, refused for a delegate exactly as for the writer.
    function testDelegateRefusesTheWritersOwnLineAsAPrerequisite() external {
        approveDelegate();
        vm.prank(DELEGATE);
        sRegistry.applyMigrationV3(WRITER, NAMESPACE, MIGRATION, onto(WRITER, NAMESPACE, MIGRATION_HEAD_GENESIS));
        Prerequisite[] memory prerequisites = new Prerequisite[](2);
        prerequisites[0] = Prerequisite({writer: WRITER, namespace: NAMESPACE, migration: MIGRATION});
        prerequisites[1] = Prerequisite({writer: WRITER, namespace: NAMESPACE, migration: MIGRATION});
        vm.prank(DELEGATE);
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV3.OwnPrerequisite.selector, MIGRATION));
        sRegistry.applyMigrationV3(WRITER, NAMESPACE, SECOND, prerequisites);
    }

    /// The writer's own V2 writes are unchanged by delegation and land in
    /// the same line.
    function testTheWritersOwnWritesShareTheLine() external {
        approveDelegate();
        vm.prank(DELEGATE);
        sRegistry.applyMigrationV3(WRITER, NAMESPACE, MIGRATION, onto(WRITER, NAMESPACE, MIGRATION_HEAD_GENESIS));
        vm.prank(WRITER);
        sRegistry.applyMigrationV3(WRITER, NAMESPACE, SECOND, onto(WRITER, NAMESPACE, MIGRATION));
        assertEq(sRegistry.headV3(WRITER, NAMESPACE), SECOND);
    }
}
