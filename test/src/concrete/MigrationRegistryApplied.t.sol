// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";

import {
    IMigrationRegistryV4,
    Prerequisite,
    MIGRATION_HEAD_GENESIS
} from "../../../src/interface/IMigrationRegistryV4.sol";
import {IRegistryDelegatesV1} from "../../../src/interface/IRegistryDelegatesV1.sol";
import {MigrationRegistry} from "../../../src/concrete/MigrationRegistry.sol";
import {LibMigrationFuzz} from "../../lib/LibMigrationFuzz.sol";

/// @title MigrationRegistryAppliedTest
/// @notice A test suite for `MigrationRegistry.appliedV4`: it answers an applied
/// migration with the moment recorded against it, an unapplied one with zero,
/// refuses the four inputs that can only be mistakes, and is the only reader of
/// a record's moment.
contract MigrationRegistryAppliedTest is Test {
    /// The registry under test. Stateful, so a fresh one per test.
    MigrationRegistry internal sRegistry;

    function setUp() external {
        sRegistry = new MigrationRegistry();
    }

    /// The list a write under `writer` in `namespaceHash` onto `head` after
    /// nothing else passes.
    /// @param writer The writer the record is under.
    /// @param namespaceHash The line the record is in.
    /// @param head The head it is applied onto.
    /// @return The one-entry list.
    function onto(address writer, bytes32 namespaceHash, bytes32 head) internal pure returns (Prerequisite[] memory) {
        Prerequisite[] memory prerequisites = new Prerequisite[](1);
        prerequisites[0] = Prerequisite({writer: writer, namespace: namespaceHash, migration: head});
        return prerequisites;
    }

    /// An unapplied migration answers zero rather than reverting. This is
    /// the deliberate difference from a registry whose reads revert on an
    /// unknown key: "not applied here" is the ordinary state of every migration
    /// before it runs and of every migration on a chain that never got it, and
    /// it is the answer a caller branches on to assert the pre-migration state
    /// exactly. A revert would leave the caller with nothing to say about the
    /// state it is actually looking at.
    function testAppliedUnappliedIsZero(address writer, bytes32 namespaceHash, bytes32 migrationHash) external view {
        vm.assume(writer != address(0));
        vm.assume(namespaceHash != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migrationHash);

        assertEq(sRegistry.appliedV4(writer, namespaceHash, migrationHash), 0);
    }

    /// An applied migration answers the moment recorded against it, and keeps
    /// answering it as time moves on. The value is when the migration was
    /// applied, not when the record was written and not how long ago or how
    /// recently anything was asked.
    function testAppliedIsTheRecordedMoment(
        address writer,
        string memory namespace,
        string memory migration,
        uint32 appliedAt,
        uint32 writtenAt,
        uint32 readAt
    ) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeNamespace(vm, namespace);
        LibMigrationFuzz.assumeMigration(vm, migration);
        vm.assume(appliedAt != 0);
        vm.assume(writtenAt >= appliedAt);
        vm.assume(readAt >= writtenAt);
        bytes32 namespaceHash = keccak256(bytes(namespace));

        vm.warp(writtenAt);
        vm.prank(writer);
        sRegistry.applyMigrationHistoryV4(
            writer, namespace, migration, appliedAt, onto(writer, namespaceHash, MIGRATION_HEAD_GENESIS)
        );

        vm.warp(readAt);
        assertEq(sRegistry.appliedV4(writer, namespaceHash, keccak256(bytes(migration))), appliedAt);
    }

    /// The moment `appliedV4` answers never exceeds the block that asks, whichever
    /// form wrote it. That is what lets a consumer measuring an interval since a
    /// migration subtract the answer from the current block without
    /// underflowing.
    function testAppliedNeverExceedsTheReadingBlock(
        address writer,
        string memory namespace,
        string memory migration,
        uint32 appliedAt,
        uint32 writtenAt,
        uint32 readAt
    ) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeNamespace(vm, namespace);
        LibMigrationFuzz.assumeMigration(vm, migration);
        vm.assume(appliedAt != 0);
        vm.assume(writtenAt >= appliedAt);
        vm.assume(readAt >= writtenAt);
        bytes32 namespaceHash = keccak256(bytes(namespace));

        vm.warp(writtenAt);
        vm.prank(writer);
        sRegistry.applyMigrationHistoryV4(
            writer, namespace, migration, appliedAt, onto(writer, namespaceHash, MIGRATION_HEAD_GENESIS)
        );

        vm.warp(readAt);
        assertLe(sRegistry.appliedV4(writer, namespaceHash, keccak256(bytes(migration))), block.timestamp);
    }

    /// Reading does not consume or alter a record, so the same question asked
    /// twice answers the same way.
    function testAppliedIsIdempotent(address writer, string memory namespace, string memory migration) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeNamespace(vm, namespace);
        LibMigrationFuzz.assumeMigration(vm, migration);
        bytes32 namespaceHash = keccak256(bytes(namespace));
        bytes32 migrationHash = keccak256(bytes(migration));

        vm.prank(writer);
        sRegistry.applyMigrationV4(writer, namespace, migration, onto(writer, namespaceHash, MIGRATION_HEAD_GENESIS));

        assertEq(sRegistry.appliedV4(writer, namespaceHash, migrationHash), block.timestamp);
        assertEq(sRegistry.appliedV4(writer, namespaceHash, migrationHash), block.timestamp);
    }

    /// A record is keyed by its line. A migration applied in one namespace is
    /// not applied in another namespace under the same writer, nor in the
    /// same namespace under another writer: each of those reads zero while
    /// the line written reads the moment.
    function testAppliedIsPerNamespace(
        address writer,
        string memory namespace,
        address other,
        bytes32 otherNamespaceHash,
        string memory migration
    ) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeNamespace(vm, namespace);
        bytes32 namespaceHash = keccak256(bytes(namespace));
        vm.assume(other != address(0));
        vm.assume(other != writer);
        vm.assume(otherNamespaceHash != bytes32(0));
        vm.assume(otherNamespaceHash != namespaceHash);
        LibMigrationFuzz.assumeMigration(vm, migration);
        bytes32 migrationHash = keccak256(bytes(migration));

        vm.prank(writer);
        sRegistry.applyMigrationV4(writer, namespace, migration, onto(writer, namespaceHash, MIGRATION_HEAD_GENESIS));

        assertEq(sRegistry.appliedV4(writer, namespaceHash, migrationHash), block.timestamp);
        assertEq(sRegistry.appliedV4(writer, otherNamespaceHash, migrationHash), 0);
        assertEq(sRegistry.appliedV4(other, namespaceHash, migrationHash), 0);
    }

    /// The zero writer is refused rather than answered. No transaction
    /// originates from the zero address, so every line under it is provably
    /// empty and zero would be the answer forever — an unresolved writer
    /// constant would read as "nothing has been applied" instead of as the
    /// mistake it is, and send its caller down the pre-migration branch on
    /// every chain.
    function testAppliedZeroWriterReverts(bytes32 namespaceHash, bytes32 migrationHash) external {
        vm.assume(namespaceHash != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migrationHash);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.ZeroWriter.selector));
        sRegistry.appliedV4(address(0), namespaceHash, migrationHash);
    }

    /// The zero namespace hash is refused for the same reason: no write can
    /// produce it, so the line is provably empty and an unset namespace hash
    /// constant would read as a pristine line rather than as the mistake it is.
    /// Refused on an empty registry and on one holding a record in a real
    /// namespace under the same writer, which the refusal leaves intact.
    function testAppliedZeroNamespaceReverts(address writer, string memory namespace, string memory migration)
        external
    {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeNamespace(vm, namespace);
        LibMigrationFuzz.assumeMigration(vm, migration);
        bytes32 namespaceHash = keccak256(bytes(namespace));
        bytes32 migrationHash = keccak256(bytes(migration));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.ZeroNamespace.selector));
        sRegistry.appliedV4(writer, bytes32(0), migrationHash);

        vm.prank(writer);
        sRegistry.applyMigrationV4(writer, namespace, migration, onto(writer, namespaceHash, MIGRATION_HEAD_GENESIS));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.ZeroNamespace.selector));
        sRegistry.appliedV4(writer, bytes32(0), migrationHash);

        assertEq(sRegistry.appliedV4(writer, namespaceHash, migrationHash), block.timestamp);
    }

    /// The zero migration hash is refused for the same reason in the other
    /// direction: no write can produce it, so it can never be a real record.
    function testAppliedZeroMigrationReverts(address writer, bytes32 namespaceHash) external {
        vm.assume(writer != address(0));
        vm.assume(namespaceHash != bytes32(0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.ZeroMigration.selector));
        sRegistry.appliedV4(writer, namespaceHash, bytes32(0));
    }

    /// The genesis head is refused as a migration for the same reason again:
    /// neither write records it either, so asking about it would
    /// answer zero forever to a caller that has confused a head for a migration
    /// — and that caller reads zero as its pre-migration branch.
    function testAppliedGenesisMigrationReverts(address writer, bytes32 namespaceHash) external {
        vm.assume(writer != address(0));
        vm.assume(namespaceHash != bytes32(0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.GenesisMigration.selector));
        sRegistry.appliedV4(writer, namespaceHash, MIGRATION_HEAD_GENESIS);
    }

    /// The writer is checked before the namespace and the migration, so a
    /// caller that has zeroed all of them is told about the writer first and
    /// gets one stable answer rather than one that depends on which check
    /// happens to run.
    function testAppliedZeroWriterCheckedFirst() external {
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.ZeroWriter.selector));
        sRegistry.appliedV4(address(0), bytes32(0), bytes32(0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.ZeroWriter.selector));
        sRegistry.appliedV4(address(0), bytes32(0), MIGRATION_HEAD_GENESIS);
    }

    /// The namespace is checked after the writer and before the migration:
    /// a zero writer wins over a zero namespace, and a zero namespace wins
    /// over either refused migration hash.
    function testAppliedZeroNamespaceCheckedAfterWriterBeforeMigration(address writer, bytes32 migrationHash) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeMigration(vm, migrationHash);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.ZeroWriter.selector));
        sRegistry.appliedV4(address(0), bytes32(0), migrationHash);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.ZeroNamespace.selector));
        sRegistry.appliedV4(writer, bytes32(0), bytes32(0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.ZeroNamespace.selector));
        sRegistry.appliedV4(writer, bytes32(0), MIGRATION_HEAD_GENESIS);
    }

    /// A refusal is not a state change: the refused cases revert on a registry
    /// that holds records exactly as they do on an empty one, and leave those
    /// records intact.
    function testAppliedRefusalLeavesRecordsIntact(address writer, string memory namespace, string memory migration)
        external
    {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeNamespace(vm, namespace);
        LibMigrationFuzz.assumeMigration(vm, migration);
        bytes32 namespaceHash = keccak256(bytes(namespace));
        bytes32 migrationHash = keccak256(bytes(migration));

        vm.prank(writer);
        sRegistry.applyMigrationV4(writer, namespace, migration, onto(writer, namespaceHash, MIGRATION_HEAD_GENESIS));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.ZeroWriter.selector));
        sRegistry.appliedV4(address(0), namespaceHash, migrationHash);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.ZeroNamespace.selector));
        sRegistry.appliedV4(writer, bytes32(0), migrationHash);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.ZeroMigration.selector));
        sRegistry.appliedV4(writer, namespaceHash, bytes32(0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.GenesisMigration.selector));
        sRegistry.appliedV4(writer, namespaceHash, MIGRATION_HEAD_GENESIS);

        assertEq(sRegistry.appliedV4(writer, namespaceHash, migrationHash), block.timestamp);
        assertEq(sRegistry.headV4(writer, namespaceHash), migrationHash);
    }

    /// `appliedV4`, `appliedOntoV4`, `appliedAfterV4` and `appliedByV4` are the only readers of the
    /// records. The records mapping is not `public`, so the getter a `public`
    /// mapping would generate — which answers the zero writer, the zero
    /// namespace and both refused hashes with zero, the exact silent
    /// wrong-branch these refusals exist to prevent — does not exist.
    function testAppliedNoGeneratedMappingGetter(address writer, bytes32 namespaceHash, bytes32 migrationHash)
        external
    {
        (bool success,) = address(sRegistry)
            .call(abi.encodeWithSignature("sRecords(address,bytes32,bytes32)", writer, namespaceHash, migrationHash));
        assertFalse(success);
    }

    /// Nor for the heads, where a generated getter would be worse still: it
    /// answers an empty line with zero, and zero is a value no head can
    /// ever hold.
    function testAppliedNoGeneratedHeadGetter(address writer, bytes32 namespaceHash) external {
        (bool success,) =
            address(sRegistry).call(abi.encodeWithSignature("sHead(address,bytes32)", writer, namespaceHash));
        assertFalse(success);
    }

    /// There is no other entry point at all: no fallback, no receive, and
    /// nothing beyond the `IMigrationRegistryV4` functions, so an unknown
    /// selector reverts instead of being silently absorbed.
    function testAppliedNoOtherEntryPoint(bytes4 selector, bytes32 namespaceHash, bytes32 migrationHash) external {
        vm.assume(selector != IMigrationRegistryV4.appliedV4.selector);
        vm.assume(selector != IMigrationRegistryV4.appliedOntoV4.selector);
        vm.assume(selector != IMigrationRegistryV4.appliedAfterV4.selector);
        vm.assume(selector != IMigrationRegistryV4.appliedByV4.selector);
        vm.assume(selector != IMigrationRegistryV4.applyMigrationV4.selector);
        vm.assume(selector != IMigrationRegistryV4.applyMigrationHistoryV4.selector);
        vm.assume(selector != IMigrationRegistryV4.headV4.selector);
        vm.assume(selector != IRegistryDelegatesV1.approveV3.selector);
        vm.assume(selector != IRegistryDelegatesV1.revokeV3.selector);
        vm.assume(selector != IRegistryDelegatesV1.approvedV3.selector);

        (bool success,) =
            address(sRegistry).call(abi.encodeWithSelector(selector, address(this), namespaceHash, migrationHash));
        assertFalse(success);
    }
}
