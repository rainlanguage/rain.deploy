// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {IRegistryDelegatesV1} from "../../../src/interface/IRegistryDelegatesV1.sol";
import {Test} from "forge-std-1.17.0/src/Test.sol";

import {
    IMigrationRegistryV4,
    Prerequisite,
    MIGRATION_HEAD_GENESIS
} from "../../../src/interface/IMigrationRegistryV4.sol";
import {MigrationRegistry} from "../../../src/concrete/MigrationRegistry.sol";
import {LibMigrationRegistry} from "../../../src/lib/LibMigrationRegistry.sol";
import {LibMigrationFuzz} from "../../lib/LibMigrationFuzz.sol";

/// @title MigrationRegistryDelegateTest
/// @notice A test suite for delegated writes: a writer approves a delegate per
/// namespace, the delegate writes the writer's line and nothing else, and a
/// revoked or unapproved caller is refused.
contract MigrationRegistryDelegateTest is Test {
    /// The registry under test. Stateful, so a fresh one per test.
    MigrationRegistry internal sRegistry;

    address internal constant WRITER = address(0x1111);
    address internal constant DELEGATE = address(0x2222);
    string internal constant NAMESPACE = "namespace";
    bytes32 internal constant NAMESPACE_HASH = keccak256(bytes(NAMESPACE));
    string internal constant MIGRATION = "migration";
    bytes32 internal constant MIGRATION_HASH = keccak256(bytes(MIGRATION));
    string internal constant SECOND = "second";
    bytes32 internal constant SECOND_HASH = keccak256(bytes(SECOND));

    function setUp() external {
        sRegistry = new MigrationRegistry();
    }

    function approveDelegate() internal {
        vm.prank(WRITER);
        sRegistry.approveV3(NAMESPACE_HASH, DELEGATE);
    }

    /// Nothing is approved until the writer approves it.
    function testApprovedIsFalseUntilApproved(address writer, bytes32 namespaceHash, address delegate) external view {
        vm.assume(writer != address(0) && namespaceHash != bytes32(0) && delegate != address(0));
        assertFalse(sRegistry.approvedV3(writer, namespaceHash, delegate));
    }

    /// An approval is the caller's, for one namespace, and is emitted.
    function testApproveIsPerWriterAndNamespace(bytes32 otherNamespaceHash, address otherWriter) external {
        vm.assume(otherNamespaceHash != NAMESPACE_HASH && otherNamespaceHash != bytes32(0));
        vm.assume(otherWriter != WRITER && otherWriter != address(0));
        vm.expectEmit(address(sRegistry));
        emit IRegistryDelegatesV1.Approved(WRITER, NAMESPACE_HASH, DELEGATE);
        approveDelegate();
        assertTrue(sRegistry.approvedV3(WRITER, NAMESPACE_HASH, DELEGATE));
        assertFalse(sRegistry.approvedV3(WRITER, otherNamespaceHash, DELEGATE));
        assertFalse(sRegistry.approvedV3(otherWriter, NAMESPACE_HASH, DELEGATE));
    }

    /// Revoking an unapproved delegate, approving twice and revoking twice
    /// each emit and leave the approval as named.
    function testRevokeRemovesTheApproval() external {
        vm.expectEmit(address(sRegistry));
        emit IRegistryDelegatesV1.Revoked(WRITER, NAMESPACE_HASH, DELEGATE);
        vm.prank(WRITER);
        sRegistry.revokeV3(NAMESPACE_HASH, DELEGATE);
        assertFalse(sRegistry.approvedV3(WRITER, NAMESPACE_HASH, DELEGATE));
        for (uint256 i = 0; i < 2; i++) {
            vm.expectEmit(address(sRegistry));
            emit IRegistryDelegatesV1.Approved(WRITER, NAMESPACE_HASH, DELEGATE);
            approveDelegate();
            assertTrue(sRegistry.approvedV3(WRITER, NAMESPACE_HASH, DELEGATE));
        }
        for (uint256 i = 0; i < 2; i++) {
            vm.expectEmit(address(sRegistry));
            emit IRegistryDelegatesV1.Revoked(WRITER, NAMESPACE_HASH, DELEGATE);
            vm.prank(WRITER);
            sRegistry.revokeV3(NAMESPACE_HASH, DELEGATE);
            assertFalse(sRegistry.approvedV3(WRITER, NAMESPACE_HASH, DELEGATE));
        }
    }

    /// A revoke in one namespace leaves the writer's approval in another, and
    /// the revoked namespace refuses history writes too.
    function testRevokeIsPerNamespaceAndStopsHistoryWrites(string memory otherNamespace) external {
        LibMigrationFuzz.assumeNamespace(vm, otherNamespace);
        bytes32 otherNamespaceHash = keccak256(bytes(otherNamespace));
        vm.assume(otherNamespaceHash != NAMESPACE_HASH);
        approveDelegate();
        vm.prank(WRITER);
        sRegistry.approveV3(otherNamespaceHash, DELEGATE);
        vm.prank(WRITER);
        sRegistry.revokeV3(NAMESPACE_HASH, DELEGATE);
        assertTrue(sRegistry.approvedV3(WRITER, otherNamespaceHash, DELEGATE));
        Prerequisite[] memory prerequisites = LibMigrationRegistry.onto(WRITER, NAMESPACE_HASH, MIGRATION_HEAD_GENESIS);
        vm.prank(DELEGATE);
        vm.expectRevert(
            abi.encodeWithSelector(IRegistryDelegatesV1.NotApproved.selector, WRITER, NAMESPACE_HASH, DELEGATE)
        );
        sRegistry.applyMigrationHistoryV4(WRITER, NAMESPACE, MIGRATION, 1, prerequisites);
        vm.prank(DELEGATE);
        sRegistry.applyMigrationHistoryV4(
            WRITER,
            otherNamespace,
            MIGRATION,
            1,
            LibMigrationRegistry.onto(WRITER, otherNamespaceHash, MIGRATION_HEAD_GENESIS)
        );
        assertEq(sRegistry.headV4(WRITER, otherNamespaceHash), MIGRATION_HASH);
        assertEq(sRegistry.headV4(WRITER, NAMESPACE_HASH), MIGRATION_HEAD_GENESIS);
    }

    /// Any caller but the writer, approved elsewhere or not, is `NotApproved`
    /// on the empty namespace, under the hash of the empty string; the writer
    /// itself, and a caller the writer approved under that hash, is
    /// `EmptyNamespace`.
    function testEmptyNamespaceFromAnotherCallerIsNotApproved(address caller, address unapproved, address emptyApproved)
        external
    {
        vm.assume(caller != WRITER && caller != address(0));
        vm.assume(unapproved != WRITER && unapproved != caller);
        vm.assume(emptyApproved != WRITER && emptyApproved != address(0));
        vm.assume(emptyApproved != caller && emptyApproved != unapproved);
        bytes32 emptyHash = keccak256("");
        vm.startPrank(WRITER);
        sRegistry.approveV3(NAMESPACE_HASH, caller);
        sRegistry.approveV3(emptyHash, emptyApproved);
        vm.stopPrank();
        Prerequisite[] memory prerequisites = LibMigrationRegistry.onto(WRITER, emptyHash, MIGRATION_HEAD_GENESIS);
        vm.startPrank(caller);
        vm.expectRevert(abi.encodeWithSelector(IRegistryDelegatesV1.NotApproved.selector, WRITER, emptyHash, caller));
        sRegistry.applyMigrationV4(WRITER, "", MIGRATION, prerequisites);
        vm.expectRevert(abi.encodeWithSelector(IRegistryDelegatesV1.NotApproved.selector, WRITER, emptyHash, caller));
        sRegistry.applyMigrationHistoryV4(WRITER, "", MIGRATION, 1, prerequisites);
        vm.stopPrank();
        vm.startPrank(unapproved);
        vm.expectRevert(
            abi.encodeWithSelector(IRegistryDelegatesV1.NotApproved.selector, WRITER, emptyHash, unapproved)
        );
        sRegistry.applyMigrationV4(WRITER, "", MIGRATION, prerequisites);
        vm.expectRevert(
            abi.encodeWithSelector(IRegistryDelegatesV1.NotApproved.selector, WRITER, emptyHash, unapproved)
        );
        sRegistry.applyMigrationHistoryV4(WRITER, "", MIGRATION, 1, prerequisites);
        vm.stopPrank();
        vm.startPrank(emptyApproved);
        vm.expectRevert(IMigrationRegistryV4.EmptyNamespace.selector);
        sRegistry.applyMigrationV4(WRITER, "", MIGRATION, prerequisites);
        vm.expectRevert(IMigrationRegistryV4.EmptyNamespace.selector);
        sRegistry.applyMigrationHistoryV4(WRITER, "", MIGRATION, 1, prerequisites);
        vm.stopPrank();
        vm.startPrank(WRITER);
        vm.expectRevert(IMigrationRegistryV4.EmptyNamespace.selector);
        sRegistry.applyMigrationV4(WRITER, "", MIGRATION, prerequisites);
        vm.expectRevert(IMigrationRegistryV4.EmptyNamespace.selector);
        sRegistry.applyMigrationHistoryV4(WRITER, "", MIGRATION, 1, prerequisites);
        vm.stopPrank();
    }

    /// The zero namespace hash and the zero delegate name no approval.
    function testApproveAndRevokeRefuseZeroes() external {
        vm.startPrank(WRITER);
        vm.expectRevert(IMigrationRegistryV4.ZeroNamespace.selector);
        sRegistry.approveV3(bytes32(0), DELEGATE);
        vm.expectRevert(IRegistryDelegatesV1.ZeroDelegate.selector);
        sRegistry.approveV3(NAMESPACE_HASH, address(0));
        vm.expectRevert(IMigrationRegistryV4.ZeroNamespace.selector);
        sRegistry.revokeV3(bytes32(0), DELEGATE);
        vm.expectRevert(IRegistryDelegatesV1.ZeroDelegate.selector);
        sRegistry.revokeV3(NAMESPACE_HASH, address(0));
        vm.stopPrank();
    }

    /// `approvedV3` refuses the zero writer, namespace hash and delegate.
    function testApprovedRefusesZeroes() external {
        vm.expectRevert(IMigrationRegistryV4.ZeroWriter.selector);
        sRegistry.approvedV3(address(0), NAMESPACE_HASH, DELEGATE);
        vm.expectRevert(IMigrationRegistryV4.ZeroNamespace.selector);
        sRegistry.approvedV3(WRITER, bytes32(0), DELEGATE);
        vm.expectRevert(IRegistryDelegatesV1.ZeroDelegate.selector);
        sRegistry.approvedV3(WRITER, NAMESPACE_HASH, address(0));
    }

    /// Every approval key refuses the zero writer, then the zero namespace
    /// hash, then the zero delegate, whichever of them are zero together.
    function testApprovalKeyRefusalOrder() external {
        vm.expectRevert(IMigrationRegistryV4.ZeroWriter.selector);
        sRegistry.approvedV3(address(0), bytes32(0), address(0));
        vm.expectRevert(IMigrationRegistryV4.ZeroWriter.selector);
        sRegistry.approvedV3(address(0), NAMESPACE_HASH, address(0));
        vm.expectRevert(IMigrationRegistryV4.ZeroNamespace.selector);
        sRegistry.approvedV3(WRITER, bytes32(0), address(0));
        vm.startPrank(WRITER);
        vm.expectRevert(IMigrationRegistryV4.ZeroNamespace.selector);
        sRegistry.approveV3(bytes32(0), address(0));
        vm.expectRevert(IMigrationRegistryV4.ZeroNamespace.selector);
        sRegistry.revokeV3(bytes32(0), address(0));
        vm.stopPrank();
    }

    /// An approved delegate writes the writer's line: the record and the head
    /// are the writer's, stamped with the block, and none is the delegate's.
    function testApprovedDelegateWritesTheWritersLine(uint256 moment) external {
        moment = bound(moment, 1, type(uint64).max);
        vm.warp(moment);
        approveDelegate();
        vm.expectEmit(address(sRegistry));
        emit IMigrationRegistryV4.Migrated(
            DELEGATE, WRITER, NAMESPACE_HASH, NAMESPACE, MIGRATION_HASH, MIGRATION, moment
        );
        vm.prank(DELEGATE);
        sRegistry.applyMigrationV4(
            WRITER, NAMESPACE, MIGRATION, LibMigrationRegistry.onto(WRITER, NAMESPACE_HASH, MIGRATION_HEAD_GENESIS)
        );
        assertEq(sRegistry.appliedV4(WRITER, NAMESPACE_HASH, MIGRATION_HASH), moment);
        assertEq(sRegistry.headV4(WRITER, NAMESPACE_HASH), MIGRATION_HASH);
        assertEq(sRegistry.appliedV4(DELEGATE, NAMESPACE_HASH, MIGRATION_HASH), 0);
        assertEq(sRegistry.headV4(DELEGATE, NAMESPACE_HASH), MIGRATION_HEAD_GENESIS);
        assertEq(sRegistry.appliedByV4(WRITER, NAMESPACE_HASH, MIGRATION_HASH), DELEGATE);
    }

    /// The history write takes its moment, into the writer's line.
    function testApprovedDelegateWritesHistory(uint256 moment, uint256 appliedAt) external {
        moment = bound(moment, 1, type(uint64).max);
        appliedAt = bound(appliedAt, 1, moment);
        vm.warp(moment);
        approveDelegate();
        vm.expectEmit(address(sRegistry));
        emit IMigrationRegistryV4.Migrated(
            DELEGATE, WRITER, NAMESPACE_HASH, NAMESPACE, MIGRATION_HASH, MIGRATION, appliedAt
        );
        vm.prank(DELEGATE);
        sRegistry.applyMigrationHistoryV4(
            WRITER,
            NAMESPACE,
            MIGRATION,
            appliedAt,
            LibMigrationRegistry.onto(WRITER, NAMESPACE_HASH, MIGRATION_HEAD_GENESIS)
        );
        assertEq(sRegistry.appliedV4(WRITER, NAMESPACE_HASH, MIGRATION_HASH), appliedAt);
        assertEq(sRegistry.headV4(WRITER, NAMESPACE_HASH), MIGRATION_HASH);
    }

    /// Two delegates share one line, each onto the other's record.
    function testTwoDelegatesShareOneLine(address other) external {
        vm.assume(other != address(0) && other != DELEGATE && other != WRITER);
        approveDelegate();
        vm.prank(WRITER);
        sRegistry.approveV3(NAMESPACE_HASH, other);
        vm.prank(DELEGATE);
        sRegistry.applyMigrationV4(
            WRITER, NAMESPACE, MIGRATION, LibMigrationRegistry.onto(WRITER, NAMESPACE_HASH, MIGRATION_HEAD_GENESIS)
        );
        vm.prank(other);
        sRegistry.applyMigrationV4(
            WRITER, NAMESPACE, SECOND, LibMigrationRegistry.onto(WRITER, NAMESPACE_HASH, MIGRATION_HASH)
        );
        assertEq(sRegistry.headV4(WRITER, NAMESPACE_HASH), SECOND_HASH);
        assertEq(sRegistry.appliedOntoV4(WRITER, NAMESPACE_HASH, SECOND_HASH), MIGRATION_HASH);
    }

    /// The writer writes its own line through both writes without approving
    /// itself.
    function testTheWriterNeedsNoApproval() external {
        vm.startPrank(WRITER);
        sRegistry.applyMigrationV4(
            WRITER, NAMESPACE, MIGRATION, LibMigrationRegistry.onto(WRITER, NAMESPACE_HASH, MIGRATION_HEAD_GENESIS)
        );
        sRegistry.applyMigrationHistoryV4(
            WRITER,
            NAMESPACE,
            SECOND,
            block.timestamp,
            LibMigrationRegistry.onto(WRITER, NAMESPACE_HASH, MIGRATION_HASH)
        );
        vm.stopPrank();
        assertEq(sRegistry.headV4(WRITER, NAMESPACE_HASH), SECOND_HASH);
    }

    /// An unapproved caller is refused on both writes, naming the line and
    /// itself.
    function testUnapprovedCallerIsRefused(address caller) external {
        vm.assume(caller != WRITER);
        Prerequisite[] memory prerequisites = LibMigrationRegistry.onto(WRITER, NAMESPACE_HASH, MIGRATION_HEAD_GENESIS);
        vm.startPrank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(IRegistryDelegatesV1.NotApproved.selector, WRITER, NAMESPACE_HASH, caller)
        );
        sRegistry.applyMigrationV4(WRITER, NAMESPACE, MIGRATION, prerequisites);
        vm.expectRevert(
            abi.encodeWithSelector(IRegistryDelegatesV1.NotApproved.selector, WRITER, NAMESPACE_HASH, caller)
        );
        sRegistry.applyMigrationHistoryV4(WRITER, NAMESPACE, MIGRATION, 1, prerequisites);
        vm.stopPrank();
    }

    /// The caller is refused before any argument but `writer` and the
    /// `namespace` its approval is read under: an unapproved caller with an
    /// empty migration, a zero moment and no head is `NotApproved`, not any
    /// argument refusal.
    function testUnapprovedCallerIsRefusedBeforeItsArguments(address caller) external {
        vm.assume(caller != WRITER);
        Prerequisite[] memory none = new Prerequisite[](0);
        vm.startPrank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(IRegistryDelegatesV1.NotApproved.selector, WRITER, NAMESPACE_HASH, caller)
        );
        sRegistry.applyMigrationV4(WRITER, NAMESPACE, "", none);
        vm.expectRevert(
            abi.encodeWithSelector(IRegistryDelegatesV1.NotApproved.selector, WRITER, NAMESPACE_HASH, caller)
        );
        sRegistry.applyMigrationHistoryV4(WRITER, NAMESPACE, "", 0, none);
        vm.stopPrank();
    }

    /// An approval from one writer writes no other writer's line, even in the
    /// same namespace.
    function testApprovalWritesNoOtherWriter(address other) external {
        vm.assume(other != WRITER && other != DELEGATE && other != address(0));
        vm.prank(other);
        sRegistry.approveV3(NAMESPACE_HASH, DELEGATE);
        Prerequisite[] memory prerequisites = LibMigrationRegistry.onto(WRITER, NAMESPACE_HASH, MIGRATION_HEAD_GENESIS);
        vm.startPrank(DELEGATE);
        vm.expectRevert(
            abi.encodeWithSelector(IRegistryDelegatesV1.NotApproved.selector, WRITER, NAMESPACE_HASH, DELEGATE)
        );
        sRegistry.applyMigrationV4(WRITER, NAMESPACE, MIGRATION, prerequisites);
        vm.expectRevert(
            abi.encodeWithSelector(IRegistryDelegatesV1.NotApproved.selector, WRITER, NAMESPACE_HASH, DELEGATE)
        );
        sRegistry.applyMigrationHistoryV4(WRITER, NAMESPACE, MIGRATION, 1, prerequisites);
        vm.stopPrank();
        assertEq(sRegistry.headV4(WRITER, NAMESPACE_HASH), MIGRATION_HEAD_GENESIS);
    }

    /// A delegate re-applying a migration in the writer's line is refused,
    /// naming the writer's line.
    function testDelegateReapplyIsRefusedNamingTheWriter() external {
        vm.warp(100);
        approveDelegate();
        vm.prank(DELEGATE);
        sRegistry.applyMigrationV4(
            WRITER, NAMESPACE, MIGRATION, LibMigrationRegistry.onto(WRITER, NAMESPACE_HASH, MIGRATION_HEAD_GENESIS)
        );
        Prerequisite[] memory ontoMigration = LibMigrationRegistry.onto(WRITER, NAMESPACE_HASH, MIGRATION_HASH);
        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV4.MigrationAlreadyApplied.selector, WRITER, NAMESPACE_HASH, MIGRATION_HASH
            )
        );
        vm.prank(DELEGATE);
        sRegistry.applyMigrationV4(WRITER, NAMESPACE, MIGRATION, ontoMigration);
    }

    /// A delegate's history write is bounded by the moment recorded at the
    /// writer's head, not by anything in the delegate's own line.
    function testDelegateHistoryBeforeTheWritersHeadIsRefused() external {
        vm.warp(1000);
        approveDelegate();
        vm.prank(WRITER);
        sRegistry.applyMigrationV4(
            WRITER, NAMESPACE, MIGRATION, LibMigrationRegistry.onto(WRITER, NAMESPACE_HASH, MIGRATION_HEAD_GENESIS)
        );
        vm.warp(2000);
        vm.prank(DELEGATE);
        sRegistry.applyMigrationV4(
            DELEGATE, NAMESPACE, MIGRATION, LibMigrationRegistry.onto(DELEGATE, NAMESPACE_HASH, MIGRATION_HEAD_GENESIS)
        );
        Prerequisite[] memory ontoMigration = LibMigrationRegistry.onto(WRITER, NAMESPACE_HASH, MIGRATION_HASH);
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.TimestampBeforeHead.selector, 999, 1000));
        vm.prank(DELEGATE);
        sRegistry.applyMigrationHistoryV4(WRITER, NAMESPACE, SECOND, 999, ontoMigration);
    }

    /// An approval for one namespace writes no other.
    function testApprovalWritesNoOtherNamespace(string memory otherNamespace) external {
        LibMigrationFuzz.assumeNamespace(vm, otherNamespace);
        bytes32 otherNamespaceHash = keccak256(bytes(otherNamespace));
        vm.assume(otherNamespaceHash != NAMESPACE_HASH);
        approveDelegate();
        Prerequisite[] memory prerequisites =
            LibMigrationRegistry.onto(WRITER, otherNamespaceHash, MIGRATION_HEAD_GENESIS);
        vm.prank(DELEGATE);
        vm.expectRevert(
            abi.encodeWithSelector(IRegistryDelegatesV1.NotApproved.selector, WRITER, otherNamespaceHash, DELEGATE)
        );
        sRegistry.applyMigrationV4(WRITER, otherNamespace, MIGRATION, prerequisites);
    }

    /// A revoked delegate is refused, and the record it wrote while approved
    /// stays.
    function testRevokedDelegateIsRefused() external {
        approveDelegate();
        vm.prank(DELEGATE);
        sRegistry.applyMigrationV4(
            WRITER, NAMESPACE, MIGRATION, LibMigrationRegistry.onto(WRITER, NAMESPACE_HASH, MIGRATION_HEAD_GENESIS)
        );
        vm.prank(WRITER);
        sRegistry.revokeV3(NAMESPACE_HASH, DELEGATE);
        vm.prank(DELEGATE);
        vm.expectRevert(
            abi.encodeWithSelector(IRegistryDelegatesV1.NotApproved.selector, WRITER, NAMESPACE_HASH, DELEGATE)
        );
        sRegistry.applyMigrationV4(
            WRITER, NAMESPACE, SECOND, LibMigrationRegistry.onto(WRITER, NAMESPACE_HASH, MIGRATION_HASH)
        );
        assertTrue(sRegistry.appliedV4(WRITER, NAMESPACE_HASH, MIGRATION_HASH) != 0);
    }

    /// A delegated write is refused on the zero writer before any approval
    /// is read.
    function testDelegatedWriteRefusesTheZeroWriter() external {
        Prerequisite[] memory prerequisites = LibMigrationRegistry.onto(address(0), NAMESPACE_HASH, bytes32(0));
        vm.prank(DELEGATE);
        vm.expectRevert(IMigrationRegistryV4.ZeroWriter.selector);
        sRegistry.applyMigrationV4(address(0), NAMESPACE, MIGRATION, prerequisites);
        vm.prank(DELEGATE);
        vm.expectRevert(IMigrationRegistryV4.ZeroWriter.selector);
        sRegistry.applyMigrationHistoryV4(address(0), NAMESPACE, MIGRATION, 1, prerequisites);
    }

    /// A delegate's head entry must name the writer, not itself: the line is
    /// the writer's.
    function testDelegateHeadMustNameTheWriter() external {
        approveDelegate();
        bytes32 genesis = MIGRATION_HEAD_GENESIS;
        vm.prank(DELEGATE);
        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV4.UnexpectedMigrationHead.selector,
                WRITER,
                NAMESPACE_HASH,
                DELEGATE,
                NAMESPACE_HASH,
                genesis,
                genesis
            )
        );
        sRegistry.applyMigrationV4(
            WRITER, NAMESPACE, MIGRATION, LibMigrationRegistry.onto(DELEGATE, NAMESPACE_HASH, genesis)
        );
    }

    /// A later entry in the writer's own line is the writer's own
    /// prerequisite, refused for a delegate exactly as for the writer.
    function testDelegateRefusesTheWritersOwnLineAsAPrerequisite() external {
        approveDelegate();
        vm.prank(DELEGATE);
        sRegistry.applyMigrationV4(
            WRITER, NAMESPACE, MIGRATION, LibMigrationRegistry.onto(WRITER, NAMESPACE_HASH, MIGRATION_HEAD_GENESIS)
        );
        Prerequisite[] memory prerequisites = new Prerequisite[](2);
        prerequisites[0] = Prerequisite({writer: WRITER, namespace: NAMESPACE_HASH, migration: MIGRATION_HASH});
        prerequisites[1] = Prerequisite({writer: WRITER, namespace: NAMESPACE_HASH, migration: MIGRATION_HASH});
        vm.prank(DELEGATE);
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.OwnPrerequisite.selector, MIGRATION_HASH));
        sRegistry.applyMigrationV4(WRITER, NAMESPACE, SECOND, prerequisites);
    }

    /// A delegate's own line is another line: a delegated write may wait on it.
    function testDelegateMayWaitOnItsOwnLine() external {
        approveDelegate();
        vm.prank(DELEGATE);
        sRegistry.applyMigrationV4(
            DELEGATE, NAMESPACE, MIGRATION, LibMigrationRegistry.onto(DELEGATE, NAMESPACE_HASH, MIGRATION_HEAD_GENESIS)
        );
        Prerequisite[] memory prerequisites = new Prerequisite[](2);
        prerequisites[0] = Prerequisite({writer: WRITER, namespace: NAMESPACE_HASH, migration: MIGRATION_HEAD_GENESIS});
        prerequisites[1] = Prerequisite({writer: DELEGATE, namespace: NAMESPACE_HASH, migration: MIGRATION_HASH});
        vm.prank(DELEGATE);
        sRegistry.applyMigrationV4(WRITER, NAMESPACE, MIGRATION, prerequisites);
        Prerequisite[] memory stored = sRegistry.appliedAfterV4(WRITER, NAMESPACE_HASH, MIGRATION_HASH);
        assertEq(abi.encode(stored), abi.encode(prerequisites));
        assertEq(sRegistry.appliedByV4(WRITER, NAMESPACE_HASH, MIGRATION_HASH), DELEGATE);
        assertEq(sRegistry.headV4(WRITER, NAMESPACE_HASH), MIGRATION_HASH);
    }

    /// The writer's own writes are unchanged by delegation and land in the
    /// same line as its delegate's.
    function testTheWritersOwnWritesShareTheLine() external {
        approveDelegate();
        vm.prank(DELEGATE);
        sRegistry.applyMigrationV4(
            WRITER, NAMESPACE, MIGRATION, LibMigrationRegistry.onto(WRITER, NAMESPACE_HASH, MIGRATION_HEAD_GENESIS)
        );
        vm.prank(WRITER);
        sRegistry.applyMigrationV4(
            WRITER, NAMESPACE, SECOND, LibMigrationRegistry.onto(WRITER, NAMESPACE_HASH, MIGRATION_HASH)
        );
        assertEq(sRegistry.headV4(WRITER, NAMESPACE_HASH), SECOND_HASH);
    }

    /// Each record keeps the account that wrote it, through either write:
    /// the delegate for its writes, the writer for its own, zero for none.
    function testAppliedByIsTheAccountThatWrote() external {
        vm.warp(1000);
        approveDelegate();
        string memory third = "third";
        assertEq(sRegistry.appliedByV4(WRITER, NAMESPACE_HASH, MIGRATION_HASH), address(0));
        vm.prank(DELEGATE);
        sRegistry.applyMigrationV4(
            WRITER, NAMESPACE, MIGRATION, LibMigrationRegistry.onto(WRITER, NAMESPACE_HASH, MIGRATION_HEAD_GENESIS)
        );
        vm.prank(WRITER);
        sRegistry.applyMigrationHistoryV4(
            WRITER, NAMESPACE, SECOND, 1000, LibMigrationRegistry.onto(WRITER, NAMESPACE_HASH, MIGRATION_HASH)
        );
        vm.prank(DELEGATE);
        sRegistry.applyMigrationHistoryV4(
            WRITER, NAMESPACE, third, 1000, LibMigrationRegistry.onto(WRITER, NAMESPACE_HASH, SECOND_HASH)
        );
        assertEq(sRegistry.appliedByV4(WRITER, NAMESPACE_HASH, MIGRATION_HASH), DELEGATE);
        assertEq(sRegistry.appliedByV4(WRITER, NAMESPACE_HASH, SECOND_HASH), WRITER);
        assertEq(sRegistry.appliedByV4(WRITER, NAMESPACE_HASH, keccak256(bytes(third))), DELEGATE);
        assertEq(sRegistry.appliedByV4(DELEGATE, NAMESPACE_HASH, MIGRATION_HASH), address(0));
    }

    /// Revoking a delegate leaves the records it wrote naming it.
    function testAppliedBySurvivesRevocation() external {
        approveDelegate();
        vm.prank(DELEGATE);
        sRegistry.applyMigrationV4(
            WRITER, NAMESPACE, MIGRATION, LibMigrationRegistry.onto(WRITER, NAMESPACE_HASH, MIGRATION_HEAD_GENESIS)
        );
        vm.prank(WRITER);
        sRegistry.revokeV3(NAMESPACE_HASH, DELEGATE);
        assertEq(sRegistry.appliedByV4(WRITER, NAMESPACE_HASH, MIGRATION_HASH), DELEGATE);
    }

    /// `appliedByV4` refuses what `appliedV4` refuses, in the same order.
    function testAppliedByRefusesWhatAppliedRefuses() external {
        vm.expectRevert(IMigrationRegistryV4.ZeroWriter.selector);
        sRegistry.appliedByV4(address(0), bytes32(0), bytes32(0));
        vm.expectRevert(IMigrationRegistryV4.ZeroNamespace.selector);
        sRegistry.appliedByV4(WRITER, bytes32(0), bytes32(0));
        vm.expectRevert(IMigrationRegistryV4.ZeroMigration.selector);
        sRegistry.appliedByV4(WRITER, NAMESPACE_HASH, bytes32(0));
        vm.expectRevert(IMigrationRegistryV4.GenesisMigration.selector);
        sRegistry.appliedByV4(WRITER, NAMESPACE_HASH, MIGRATION_HEAD_GENESIS);
    }

    /// The approvals mapping is not `public`, so there is no generated getter
    /// answering the zero writer, namespace hash or delegate with false.
    function testApprovedNoGeneratedMappingGetter(address writer, bytes32 namespaceHash, address delegate) external {
        (bool success,) = address(sRegistry)
            .call(abi.encodeWithSignature("sApproved(address,bytes32,address)", writer, namespaceHash, delegate));
        assertFalse(success);
    }
}
