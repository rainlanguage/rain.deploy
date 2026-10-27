// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";

import {
    IMigrationRegistryV4,
    Prerequisite,
    MIGRATION_HEAD_GENESIS
} from "../../../src/interface/IMigrationRegistryV4.sol";
import {MigrationRegistry} from "../../../src/concrete/MigrationRegistry.sol";
import {LibMigrationFuzz} from "../../lib/LibMigrationFuzz.sol";

/// @title MigrationRegistryHeadTest
/// @notice A test suite for `MigrationRegistry.headV4`: where a line is, what
/// an empty one answers, that the answer is never a value that is not a head,
/// and that it is the same answer a write checks against.
contract MigrationRegistryHeadTest is Test {
    /// The registry under test. Stateful, so a fresh one per test.
    MigrationRegistry internal sRegistry;

    function setUp() external {
        sRegistry = new MigrationRegistry();
    }

    /// The list a write under `writer` in `namespaceHash` onto `head` after
    /// nothing else passes.
    /// @param writer The writer the record is under.
    /// @param namespaceHash The line under the writer the record is in.
    /// @param head The head it is applied onto.
    /// @return The one-entry list.
    function onto(address writer, bytes32 namespaceHash, bytes32 head) internal pure returns (Prerequisite[] memory) {
        Prerequisite[] memory prerequisites = new Prerequisite[](1);
        prerequisites[0] = Prerequisite({writer: writer, namespace: namespaceHash, migration: head});
        return prerequisites;
    }

    /// A line that has applied nothing is at genesis, which is an ANSWER
    /// rather than a revert for the same reason an unapplied migration answers
    /// zero: it is the ordinary state of every line before its first
    /// migration, and of every line on a chain that never got one.
    function testHeadEmptyLineIsGenesis(address writer, bytes32 namespaceHash) external view {
        vm.assume(writer != address(0));
        vm.assume(namespaceHash != bytes32(0));

        assertEq(sRegistry.headV4(writer, namespaceHash), MIGRATION_HEAD_GENESIS);
    }

    /// Genesis is deliberately not zero, so an uninitialised predecessor
    /// constant can never be mistaken for "the start of the sequence" — which
    /// is the mistake that would otherwise pass on every chain that has not been
    /// migrated yet.
    function testHeadGenesisIsNotZero() external pure {
        assertTrue(MIGRATION_HEAD_GENESIS != bytes32(0));
    }

    /// Genesis is one fixed shared value — the hash of one string, identical
    /// for every writer, every namespace, every consumer and every chain —
    /// rather than anything derived, which is what lets an empty line on a
    /// chain nobody has migrated answer the same head a script written
    /// anywhere else names. Pinned to the preimage rather than to whatever the
    /// constant happens to hold, because a changed one is not a new value: it
    /// orphans every record already applied onto the old one and puts every
    /// empty line at a head no deployed script names.
    function testHeadGenesisIsTheSharedValue(address writer, bytes32 namespaceHash) external view {
        vm.assume(writer != address(0));
        vm.assume(namespaceHash != bytes32(0));

        assertEq(MIGRATION_HEAD_GENESIS, keccak256("rain.migration-registry.head.genesis"));
        assertEq(sRegistry.headV4(writer, namespaceHash), keccak256("rain.migration-registry.head.genesis"));
    }

    /// The head is the migration applied most recently, and it moves with each
    /// one.
    function testHeadFollowsTheRecords(
        address writer,
        string memory namespace,
        string memory migrationA,
        string memory migrationB
    ) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeNamespace(vm, namespace);
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        bytes32 namespaceHash = keccak256(bytes(namespace));
        bytes32 migrationAHash = keccak256(bytes(migrationA));
        bytes32 migrationBHash = keccak256(bytes(migrationB));
        vm.assume(migrationAHash != migrationBHash);

        vm.prank(writer);
        sRegistry.applyMigrationV4(writer, namespace, migrationA, onto(writer, namespaceHash, MIGRATION_HEAD_GENESIS));
        assertEq(sRegistry.headV4(writer, namespaceHash), migrationAHash);

        vm.prank(writer);
        sRegistry.applyMigrationV4(writer, namespace, migrationB, onto(writer, namespaceHash, migrationAHash));
        assertEq(sRegistry.headV4(writer, namespaceHash), migrationBHash);
    }

    /// Every writer has its own head, and one writer's records leave every
    /// other writer's line exactly where it was.
    function testHeadIsPerWriter(address writer, string memory namespace, address other, string memory migration)
        external
    {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeNamespace(vm, namespace);
        vm.assume(other != address(0));
        vm.assume(writer != other);
        LibMigrationFuzz.assumeMigration(vm, migration);
        bytes32 namespaceHash = keccak256(bytes(namespace));

        vm.prank(writer);
        sRegistry.applyMigrationV4(writer, namespace, migration, onto(writer, namespaceHash, MIGRATION_HEAD_GENESIS));

        assertEq(sRegistry.headV4(writer, namespaceHash), keccak256(bytes(migration)));
        assertEq(sRegistry.headV4(other, namespaceHash), MIGRATION_HEAD_GENESIS);
    }

    /// The head `headV4` reports is exactly the head a write demands: whatever
    /// this answers is accepted, and it is the only value that is. The
    /// two go through one translation of an empty line, so they cannot
    /// disagree about where one is.
    function testHeadIsWhatApplyMigrationAccepts(
        address writer,
        string memory namespace,
        string memory migrationA,
        string memory migrationB
    ) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeNamespace(vm, namespace);
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        bytes32 namespaceHash = keccak256(bytes(namespace));
        vm.assume(keccak256(bytes(migrationA)) != keccak256(bytes(migrationB)));

        // Hoisted, because `vm.prank` applies to the next call and reading the
        // head is a call.
        bytes32 headBeforeA = sRegistry.headV4(writer, namespaceHash);
        vm.prank(writer);
        sRegistry.applyMigrationV4(writer, namespace, migrationA, onto(writer, namespaceHash, headBeforeA));

        bytes32 headBeforeB = sRegistry.headV4(writer, namespaceHash);
        vm.prank(writer);
        sRegistry.applyMigrationV4(writer, namespace, migrationB, onto(writer, namespaceHash, headBeforeB));

        assertEq(sRegistry.headV4(writer, namespaceHash), keccak256(bytes(migrationB)));
        assertEq(sRegistry.appliedV4(writer, namespaceHash, keccak256(bytes(migrationA))), block.timestamp);
        assertEq(sRegistry.appliedV4(writer, namespaceHash, keccak256(bytes(migrationB))), block.timestamp);
    }

    /// The zero writer is refused rather than answered genesis. Every line
    /// under it is provably empty forever, so "nothing has been applied here"
    /// is true of it and false of whatever the caller meant to ask about —
    /// and a caller that believed it would send a first migration at it.
    function testHeadZeroWriterReverts(bytes32 namespaceHash) external {
        vm.assume(namespaceHash != bytes32(0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.ZeroWriter.selector));
        sRegistry.headV4(address(0), namespaceHash);
    }

    /// The zero namespace hash is refused for the same reason: it is what an
    /// uninitialised constant reads as, never a line anybody meant to name.
    function testHeadZeroNamespaceReverts(address writer) external {
        vm.assume(writer != address(0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.ZeroNamespace.selector));
        sRegistry.headV4(writer, bytes32(0));
    }

    /// The writer is checked before the namespace, so a caller that has zeroed
    /// both gets one stable answer.
    function testHeadZeroWriterCheckedBeforeZeroNamespace() external {
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.ZeroWriter.selector));
        sRegistry.headV4(address(0), bytes32(0));
    }

    /// Refused on a registry holding records exactly as on an empty one, and
    /// the refusal changes nothing.
    function testHeadZeroWriterRevertsWithRecordsPresent(
        address writer,
        string memory namespace,
        string memory migration
    ) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeNamespace(vm, namespace);
        LibMigrationFuzz.assumeMigration(vm, migration);
        bytes32 namespaceHash = keccak256(bytes(namespace));

        vm.prank(writer);
        sRegistry.applyMigrationV4(writer, namespace, migration, onto(writer, namespaceHash, MIGRATION_HEAD_GENESIS));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.ZeroWriter.selector));
        sRegistry.headV4(address(0), namespaceHash);

        assertEq(sRegistry.headV4(writer, namespaceHash), keccak256(bytes(migration)));
    }

    /// The zero namespace hash is refused under a writer that holds records
    /// exactly as under one that holds none, and the line is left where it was.
    function testHeadZeroNamespaceRevertsWithRecordsPresent(
        address writer,
        string memory namespace,
        string memory migration
    ) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeNamespace(vm, namespace);
        LibMigrationFuzz.assumeMigration(vm, migration);
        bytes32 namespaceHash = keccak256(bytes(namespace));

        vm.prank(writer);
        sRegistry.applyMigrationV4(writer, namespace, migration, onto(writer, namespaceHash, MIGRATION_HEAD_GENESIS));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.ZeroNamespace.selector));
        sRegistry.headV4(writer, bytes32(0));

        assertEq(sRegistry.headV4(writer, namespaceHash), keccak256(bytes(migration)));
    }

    /// A head is never zero, in any line state, which is what lets a
    /// consumer treat a zero answer as "this is not the registry" rather than as
    /// a line.
    function testHeadIsNeverZero(address writer, string memory namespace, string memory migration) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeNamespace(vm, namespace);
        LibMigrationFuzz.assumeMigration(vm, migration);
        bytes32 namespaceHash = keccak256(bytes(namespace));

        assertTrue(sRegistry.headV4(writer, namespaceHash) != bytes32(0));

        vm.prank(writer);
        sRegistry.applyMigrationV4(writer, namespace, migration, onto(writer, namespaceHash, MIGRATION_HEAD_GENESIS));

        assertTrue(sRegistry.headV4(writer, namespaceHash) != bytes32(0));
    }

    /// A refused apply leaves the head where it was. The head moves only for a
    /// migration that was actually applied, so it can never describe a step
    /// that did not happen.
    function testHeadUnmovedByRefusedApplyMigration(
        address writer,
        string memory namespace,
        string memory migration,
        bytes32 wrongHead
    ) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeNamespace(vm, namespace);
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, wrongHead);
        vm.assume(wrongHead != keccak256(bytes(migration)));
        bytes32 namespaceHash = keccak256(bytes(namespace));

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV4.UnexpectedMigrationHead.selector,
                writer,
                namespaceHash,
                writer,
                namespaceHash,
                wrongHead,
                MIGRATION_HEAD_GENESIS
            )
        );
        vm.prank(writer);
        sRegistry.applyMigrationV4(writer, namespace, migration, onto(writer, namespaceHash, wrongHead));

        assertEq(sRegistry.headV4(writer, namespaceHash), MIGRATION_HEAD_GENESIS);
    }

    /// A first entry in another of the writer's own namespaces is not this
    /// line's head, whatever migration it names, and neither line moves.
    function testHeadUnmovedByFirstEntryInAnotherNamespace(
        address writer,
        string memory namespace,
        bytes32 otherNamespaceHash,
        string memory migration
    ) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeNamespace(vm, namespace);
        bytes32 namespaceHash = keccak256(bytes(namespace));
        vm.assume(otherNamespaceHash != bytes32(0));
        vm.assume(namespaceHash != otherNamespaceHash);
        LibMigrationFuzz.assumeMigration(vm, migration);

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV4.UnexpectedMigrationHead.selector,
                writer,
                namespaceHash,
                writer,
                otherNamespaceHash,
                MIGRATION_HEAD_GENESIS,
                MIGRATION_HEAD_GENESIS
            )
        );
        vm.prank(writer);
        sRegistry.applyMigrationV4(
            writer, namespace, migration, onto(writer, otherNamespaceHash, MIGRATION_HEAD_GENESIS)
        );

        assertEq(sRegistry.headV4(writer, namespaceHash), MIGRATION_HEAD_GENESIS);
        assertEq(sRegistry.headV4(writer, otherNamespaceHash), MIGRATION_HEAD_GENESIS);
    }

    /// An empty list names no head at all, so it is refused as a zero head on
    /// an empty line and on a used one, and the head stays where it was.
    function testHeadUnmovedByEmptyList(
        address writer,
        string memory namespace,
        string memory migration,
        string memory next
    ) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeNamespace(vm, namespace);
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, next);
        bytes32 namespaceHash = keccak256(bytes(namespace));
        bytes32 migrationHash = keccak256(bytes(migration));
        vm.assume(migrationHash != keccak256(bytes(next)));

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV4.UnexpectedMigrationHead.selector,
                writer,
                namespaceHash,
                address(0),
                bytes32(0),
                bytes32(0),
                MIGRATION_HEAD_GENESIS
            )
        );
        vm.prank(writer);
        sRegistry.applyMigrationV4(writer, namespace, migration, new Prerequisite[](0));
        assertEq(sRegistry.headV4(writer, namespaceHash), MIGRATION_HEAD_GENESIS);

        vm.prank(writer);
        sRegistry.applyMigrationV4(writer, namespace, migration, onto(writer, namespaceHash, MIGRATION_HEAD_GENESIS));

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV4.UnexpectedMigrationHead.selector,
                writer,
                namespaceHash,
                address(0),
                bytes32(0),
                bytes32(0),
                migrationHash
            )
        );
        vm.prank(writer);
        sRegistry.applyMigrationV4(writer, namespace, next, new Prerequisite[](0));
        assertEq(sRegistry.headV4(writer, namespaceHash), migrationHash);
    }
}
