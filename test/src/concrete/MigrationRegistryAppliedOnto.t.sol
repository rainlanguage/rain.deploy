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

/// @title MigrationRegistryAppliedOntoTest
/// @notice A test suite for `MigrationRegistry.appliedOntoV4`: it answers an
/// applied migration with the head it was applied onto, an unapplied one with
/// zero, refuses the four inputs that can only be mistakes, and is the step
/// that walks a line back to genesis.
contract MigrationRegistryAppliedOntoTest is Test {
    /// The registry under test. Stateful, so a fresh one per test.
    MigrationRegistry internal sRegistry;

    function setUp() external {
        sRegistry = new MigrationRegistry();
    }

    /// The list a write under `writer` in `namespaceHash` onto `head` after
    /// nothing else passes.
    /// @param writer The writer the record is under.
    /// @param namespaceHash The line under the writer.
    /// @param head The head it is applied onto.
    /// @return The one-entry list.
    function onto(address writer, bytes32 namespaceHash, bytes32 head) internal pure returns (Prerequisite[] memory) {
        Prerequisite[] memory prerequisites = new Prerequisite[](1);
        prerequisites[0] = Prerequisite({writer: writer, namespace: namespaceHash, migration: head});
        return prerequisites;
    }

    /// An unapplied migration answers zero rather than reverting, exactly as
    /// `appliedV4` does. Zero is not a head — a head is genesis or an applied
    /// hash, both nonzero — so it says "no record" and nothing else.
    function testAppliedOntoUnappliedIsZero(address writer, bytes32 namespaceHash, bytes32 migrationHash)
        external
        view
    {
        vm.assume(writer != address(0));
        vm.assume(namespaceHash != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migrationHash);

        assertEq(sRegistry.appliedOntoV4(writer, namespaceHash, migrationHash), bytes32(0));
    }

    /// The first migration in a line answers `MIGRATION_HEAD_GENESIS`, so
    /// the walk back has a terminator that is not the "no record" zero.
    function testAppliedOntoFirstRecordIsGenesis(address writer, string memory namespace, string memory migration)
        external
    {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeNamespace(vm, namespace);
        LibMigrationFuzz.assumeMigration(vm, migration);
        bytes32 namespaceHash = keccak256(bytes(namespace));

        vm.prank(writer);
        sRegistry.applyMigrationV4(writer, namespace, migration, onto(writer, namespaceHash, MIGRATION_HEAD_GENESIS));

        assertEq(sRegistry.appliedOntoV4(writer, namespaceHash, keccak256(bytes(migration))), MIGRATION_HEAD_GENESIS);
    }

    /// A later migration answers the migration before it, which is the head the
    /// registry itself checked rather than a value the caller was free to
    /// choose: a caller whose first entry names anything else is refused, so
    /// the record can only ever hold where the line actually was.
    function testAppliedOntoIsTheCheckedHead(
        address writer,
        string memory namespace,
        string memory migrationA,
        string memory migrationB,
        bytes32 wrongHead
    ) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeNamespace(vm, namespace);
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        LibMigrationFuzz.assumeMigration(vm, wrongHead);
        bytes32 namespaceHash = keccak256(bytes(namespace));
        bytes32 migrationAHash = keccak256(bytes(migrationA));
        vm.assume(migrationAHash != keccak256(bytes(migrationB)));
        vm.assume(wrongHead != migrationAHash);

        vm.prank(writer);
        sRegistry.applyMigrationV4(writer, namespace, migrationA, onto(writer, namespaceHash, MIGRATION_HEAD_GENESIS));

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV4.UnexpectedMigrationHead.selector,
                writer,
                namespaceHash,
                writer,
                namespaceHash,
                wrongHead,
                migrationAHash
            )
        );
        vm.prank(writer);
        sRegistry.applyMigrationV4(writer, namespace, migrationB, onto(writer, namespaceHash, wrongHead));

        vm.prank(writer);
        sRegistry.applyMigrationV4(writer, namespace, migrationB, onto(writer, namespaceHash, migrationAHash));

        assertEq(sRegistry.appliedOntoV4(writer, namespaceHash, keccak256(bytes(migrationB))), migrationAHash);
    }

    /// The first entry is the writer at its head, not merely the head: the
    /// right migration under another writer is refused as the wrong head, so
    /// what this answers is always a head of the writer's own line.
    function testAppliedOntoFirstEntryUnderAnotherWriterReverts(
        address writer,
        string memory namespace,
        address other,
        string memory migrationA,
        string memory migrationB
    ) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeNamespace(vm, namespace);
        vm.assume(other != address(0));
        vm.assume(writer != other);
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        bytes32 namespaceHash = keccak256(bytes(namespace));
        bytes32 migrationAHash = keccak256(bytes(migrationA));
        vm.assume(migrationAHash != keccak256(bytes(migrationB)));

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV4.UnexpectedMigrationHead.selector,
                writer,
                namespaceHash,
                other,
                namespaceHash,
                MIGRATION_HEAD_GENESIS,
                MIGRATION_HEAD_GENESIS
            )
        );
        vm.prank(writer);
        sRegistry.applyMigrationV4(writer, namespace, migrationA, onto(other, namespaceHash, MIGRATION_HEAD_GENESIS));
        assertEq(sRegistry.appliedOntoV4(writer, namespaceHash, migrationAHash), bytes32(0));

        vm.prank(writer);
        sRegistry.applyMigrationV4(writer, namespace, migrationA, onto(writer, namespaceHash, MIGRATION_HEAD_GENESIS));

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV4.UnexpectedMigrationHead.selector,
                writer,
                namespaceHash,
                other,
                namespaceHash,
                migrationAHash,
                migrationAHash
            )
        );
        vm.prank(writer);
        sRegistry.applyMigrationV4(writer, namespace, migrationB, onto(other, namespaceHash, migrationAHash));
        assertEq(sRegistry.appliedOntoV4(writer, namespaceHash, keccak256(bytes(migrationB))), bytes32(0));
    }

    /// The first entry is the writer in the namespace being written, not
    /// merely the writer: the writer at the head of one of its OTHER lines is
    /// refused as the wrong head, and nothing is recorded in either line.
    function testAppliedOntoFirstEntryInAnotherNamespaceReverts(
        address writer,
        string memory namespace,
        string memory otherNamespace,
        string memory migrationA,
        string memory migrationB
    ) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeNamespace(vm, namespace);
        LibMigrationFuzz.assumeNamespace(vm, otherNamespace);
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        bytes32 namespaceHash = keccak256(bytes(namespace));
        bytes32 otherNamespaceHash = keccak256(bytes(otherNamespace));
        vm.assume(namespaceHash != otherNamespaceHash);
        bytes32 migrationAHash = keccak256(bytes(migrationA));
        bytes32 migrationBHash = keccak256(bytes(migrationB));
        vm.assume(migrationAHash != migrationBHash);

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
            writer, namespace, migrationA, onto(writer, otherNamespaceHash, MIGRATION_HEAD_GENESIS)
        );
        assertEq(sRegistry.appliedOntoV4(writer, namespaceHash, migrationAHash), bytes32(0));
        assertEq(sRegistry.appliedOntoV4(writer, otherNamespaceHash, migrationAHash), bytes32(0));

        vm.prank(writer);
        sRegistry.applyMigrationV4(
            writer, otherNamespace, migrationA, onto(writer, otherNamespaceHash, MIGRATION_HEAD_GENESIS)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV4.UnexpectedMigrationHead.selector,
                writer,
                namespaceHash,
                writer,
                otherNamespaceHash,
                migrationAHash,
                MIGRATION_HEAD_GENESIS
            )
        );
        vm.prank(writer);
        sRegistry.applyMigrationV4(writer, namespace, migrationB, onto(writer, otherNamespaceHash, migrationAHash));
        assertEq(sRegistry.appliedOntoV4(writer, namespaceHash, migrationBHash), bytes32(0));
        assertEq(sRegistry.appliedOntoV4(writer, otherNamespaceHash, migrationBHash), bytes32(0));
        assertEq(sRegistry.headV4(writer, namespaceHash), MIGRATION_HEAD_GENESIS);
        assertEq(sRegistry.headV4(writer, otherNamespaceHash), migrationAHash);
    }

    /// The answer is the first entry of `appliedAfterV4`, whatever the rest of
    /// the list holds: one record, read two ways.
    function testAppliedOntoIsTheFirstEntryOfAppliedAfter(
        address writer,
        string memory namespace,
        address other,
        string memory migrationA,
        string memory migrationB,
        string memory prerequisite
    ) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeNamespace(vm, namespace);
        vm.assume(other != address(0));
        vm.assume(writer != other);
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        LibMigrationFuzz.assumeMigration(vm, prerequisite);
        bytes32 namespaceHash = keccak256(bytes(namespace));
        bytes32 migrationAHash = keccak256(bytes(migrationA));
        vm.assume(migrationAHash != keccak256(bytes(migrationB)));

        vm.prank(other);
        sRegistry.applyMigrationV4(other, namespace, prerequisite, onto(other, namespaceHash, MIGRATION_HEAD_GENESIS));
        assertEq(
            sRegistry.appliedOntoV4(other, namespaceHash, keccak256(bytes(prerequisite))),
            sRegistry.appliedAfterV4(other, namespaceHash, keccak256(bytes(prerequisite)))[0].migration
        );

        Prerequisite[] memory prerequisites = new Prerequisite[](2);
        prerequisites[0] = Prerequisite({writer: writer, namespace: namespaceHash, migration: MIGRATION_HEAD_GENESIS});
        prerequisites[1] =
            Prerequisite({writer: other, namespace: namespaceHash, migration: keccak256(bytes(prerequisite))});
        vm.prank(writer);
        sRegistry.applyMigrationV4(writer, namespace, migrationA, prerequisites);
        assertEq(sRegistry.appliedOntoV4(writer, namespaceHash, migrationAHash), MIGRATION_HEAD_GENESIS);
        assertEq(
            sRegistry.appliedOntoV4(writer, namespaceHash, migrationAHash),
            sRegistry.appliedAfterV4(writer, namespaceHash, migrationAHash)[0].migration
        );

        prerequisites[0] = Prerequisite({writer: writer, namespace: namespaceHash, migration: migrationAHash});
        vm.prank(writer);
        sRegistry.applyMigrationV4(writer, namespace, migrationB, prerequisites);
        assertEq(sRegistry.appliedOntoV4(writer, namespaceHash, keccak256(bytes(migrationB))), migrationAHash);
        assertEq(
            sRegistry.appliedOntoV4(writer, namespaceHash, keccak256(bytes(migrationB))),
            sRegistry.appliedAfterV4(writer, namespaceHash, keccak256(bytes(migrationB)))[0].migration
        );
    }

    /// A record never moves. The answer for an earlier migration is the same
    /// after a later one lands, so a chain read at any moment describes the same
    /// history.
    function testAppliedOntoRecordsAreImmutable(
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
        vm.assume(migrationAHash != keccak256(bytes(migrationB)));

        vm.prank(writer);
        sRegistry.applyMigrationV4(writer, namespace, migrationA, onto(writer, namespaceHash, MIGRATION_HEAD_GENESIS));
        assertEq(sRegistry.appliedOntoV4(writer, namespaceHash, migrationAHash), MIGRATION_HEAD_GENESIS);

        vm.prank(writer);
        sRegistry.applyMigrationV4(writer, namespace, migrationB, onto(writer, namespaceHash, migrationAHash));

        assertEq(sRegistry.appliedOntoV4(writer, namespaceHash, migrationAHash), MIGRATION_HEAD_GENESIS);
        assertEq(sRegistry.appliedOntoV4(writer, namespaceHash, keccak256(bytes(migrationB))), migrationAHash);
    }

    /// Reading twice answers the same way.
    function testAppliedOntoIsIdempotent(address writer, string memory namespace, string memory migration) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeNamespace(vm, namespace);
        LibMigrationFuzz.assumeMigration(vm, migration);
        bytes32 namespaceHash = keccak256(bytes(namespace));
        bytes32 migrationHash = keccak256(bytes(migration));

        vm.prank(writer);
        sRegistry.applyMigrationV4(writer, namespace, migration, onto(writer, namespaceHash, MIGRATION_HEAD_GENESIS));

        assertEq(sRegistry.appliedOntoV4(writer, namespaceHash, migrationHash), MIGRATION_HEAD_GENESIS);
        assertEq(sRegistry.appliedOntoV4(writer, namespaceHash, migrationHash), MIGRATION_HEAD_GENESIS);
    }

    /// A record is confined to the writer's line here as everywhere else:
    /// one writer's chain says nothing about another's.
    function testAppliedOntoIsPerWriter(address writer, string memory namespace, address other, string memory migration)
        external
    {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeNamespace(vm, namespace);
        vm.assume(other != address(0));
        vm.assume(writer != other);
        LibMigrationFuzz.assumeMigration(vm, migration);
        bytes32 namespaceHash = keccak256(bytes(namespace));
        bytes32 migrationHash = keccak256(bytes(migration));

        vm.prank(writer);
        sRegistry.applyMigrationV4(writer, namespace, migration, onto(writer, namespaceHash, MIGRATION_HEAD_GENESIS));

        assertEq(sRegistry.appliedOntoV4(writer, namespaceHash, migrationHash), MIGRATION_HEAD_GENESIS);
        assertEq(sRegistry.appliedOntoV4(other, namespaceHash, migrationHash), bytes32(0));
    }

    /// One writer's lines are as separate as two writers': a record in one
    /// namespace says nothing in another, and the first migration in the
    /// other line is onto genesis rather than onto the first line's head.
    function testAppliedOntoIsPerNamespace(
        address writer,
        string memory namespace,
        string memory otherNamespace,
        string memory migrationA,
        string memory migrationB
    ) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeNamespace(vm, namespace);
        LibMigrationFuzz.assumeNamespace(vm, otherNamespace);
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        bytes32 namespaceHash = keccak256(bytes(namespace));
        bytes32 otherNamespaceHash = keccak256(bytes(otherNamespace));
        vm.assume(namespaceHash != otherNamespaceHash);
        bytes32 migrationAHash = keccak256(bytes(migrationA));
        bytes32 migrationBHash = keccak256(bytes(migrationB));
        vm.assume(migrationAHash != migrationBHash);

        vm.prank(writer);
        sRegistry.applyMigrationV4(writer, namespace, migrationA, onto(writer, namespaceHash, MIGRATION_HEAD_GENESIS));

        assertEq(sRegistry.appliedOntoV4(writer, namespaceHash, migrationAHash), MIGRATION_HEAD_GENESIS);
        assertEq(sRegistry.appliedOntoV4(writer, otherNamespaceHash, migrationAHash), bytes32(0));

        vm.prank(writer);
        sRegistry.applyMigrationV4(
            writer, otherNamespace, migrationB, onto(writer, otherNamespaceHash, MIGRATION_HEAD_GENESIS)
        );

        assertEq(sRegistry.appliedOntoV4(writer, otherNamespaceHash, migrationBHash), MIGRATION_HEAD_GENESIS);
        assertEq(sRegistry.appliedOntoV4(writer, namespaceHash, migrationBHash), bytes32(0));
        assertEq(sRegistry.appliedOntoV4(writer, namespaceHash, migrationAHash), MIGRATION_HEAD_GENESIS);
    }

    /// The zero writer is refused rather than answered, for the reason `appliedV4`
    /// refuses it: every line under it is provably empty, so an unresolved
    /// writer constant would read as "nothing has been applied" rather than as
    /// the mistake it is.
    function testAppliedOntoZeroWriterReverts(bytes32 namespaceHash, bytes32 migrationHash) external {
        vm.assume(namespaceHash != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migrationHash);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.ZeroWriter.selector));
        sRegistry.appliedOntoV4(address(0), namespaceHash, migrationHash);
    }

    /// The zero namespace hash is refused for the same reason: no write can
    /// produce it, so an unset namespace hash constant would read as an empty
    /// line rather than as the mistake it is.
    function testAppliedOntoZeroNamespaceReverts(address writer, bytes32 migrationHash) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeMigration(vm, migrationHash);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.ZeroNamespace.selector));
        sRegistry.appliedOntoV4(writer, bytes32(0), migrationHash);
    }

    /// The zero migration hash is refused: no write can produce it, so it can
    /// never be a real record.
    function testAppliedOntoZeroMigrationReverts(address writer, bytes32 namespaceHash) external {
        vm.assume(writer != address(0));
        vm.assume(namespaceHash != bytes32(0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.ZeroMigration.selector));
        sRegistry.appliedOntoV4(writer, namespaceHash, bytes32(0));
    }

    /// The genesis head is refused as a migration. It is where a walk ENDS, so a
    /// caller that carried on asking about it has confused the terminator for a
    /// record and would read zero as one.
    function testAppliedOntoGenesisMigrationReverts(address writer, bytes32 namespaceHash) external {
        vm.assume(writer != address(0));
        vm.assume(namespaceHash != bytes32(0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.GenesisMigration.selector));
        sRegistry.appliedOntoV4(writer, namespaceHash, MIGRATION_HEAD_GENESIS);
    }

    /// The writer is checked before the migration, so a caller that has zeroed
    /// both gets one stable answer rather than one that depends on which check
    /// happens to run — the same order `appliedV4` uses, from the same check.
    function testAppliedOntoZeroWriterCheckedFirst(bytes32 namespaceHash) external {
        vm.assume(namespaceHash != bytes32(0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.ZeroWriter.selector));
        sRegistry.appliedOntoV4(address(0), namespaceHash, bytes32(0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.ZeroWriter.selector));
        sRegistry.appliedOntoV4(address(0), namespaceHash, MIGRATION_HEAD_GENESIS);
    }

    /// The namespace sits between the writer and the migration in the order
    /// the key is checked: after the writer, before the migration.
    function testAppliedOntoZeroNamespaceCheckedAfterWriterBeforeMigration(address writer) external {
        vm.assume(writer != address(0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.ZeroWriter.selector));
        sRegistry.appliedOntoV4(address(0), bytes32(0), bytes32(0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.ZeroWriter.selector));
        sRegistry.appliedOntoV4(address(0), bytes32(0), MIGRATION_HEAD_GENESIS);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.ZeroNamespace.selector));
        sRegistry.appliedOntoV4(writer, bytes32(0), bytes32(0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.ZeroNamespace.selector));
        sRegistry.appliedOntoV4(writer, bytes32(0), MIGRATION_HEAD_GENESIS);
    }

    /// A refusal is not a state change: the refused cases revert on a registry
    /// that holds records exactly as they do on an empty one, and leave those
    /// records intact.
    function testAppliedOntoRefusalLeavesRecordsIntact(address writer, string memory namespace, string memory migration)
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
        sRegistry.appliedOntoV4(address(0), namespaceHash, migrationHash);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.ZeroNamespace.selector));
        sRegistry.appliedOntoV4(writer, bytes32(0), migrationHash);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.ZeroMigration.selector));
        sRegistry.appliedOntoV4(writer, namespaceHash, bytes32(0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.GenesisMigration.selector));
        sRegistry.appliedOntoV4(writer, namespaceHash, MIGRATION_HEAD_GENESIS);

        assertEq(sRegistry.appliedOntoV4(writer, namespaceHash, migrationHash), MIGRATION_HEAD_GENESIS);
        assertEq(sRegistry.headV4(writer, namespaceHash), migrationHash);
    }

    /// The two readers of a record agree about whether it exists. `appliedV4`
    /// answering zero and `appliedOntoV4` answering zero are the same fact, and a
    /// nonzero answer from either comes with a nonzero answer from the other —
    /// which is what a single whole-struct write buys.
    function testAppliedOntoAgreesWithApplied(
        address writer,
        string memory namespace,
        string memory migrationA,
        bytes32 migrationBHash
    ) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeNamespace(vm, namespace);
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationBHash);
        bytes32 namespaceHash = keccak256(bytes(namespace));
        bytes32 migrationAHash = keccak256(bytes(migrationA));
        vm.assume(migrationAHash != migrationBHash);

        assertEq(sRegistry.appliedV4(writer, namespaceHash, migrationAHash), 0);
        assertEq(sRegistry.appliedOntoV4(writer, namespaceHash, migrationAHash), bytes32(0));

        vm.prank(writer);
        sRegistry.applyMigrationV4(writer, namespace, migrationA, onto(writer, namespaceHash, MIGRATION_HEAD_GENESIS));

        assertTrue(sRegistry.appliedV4(writer, namespaceHash, migrationAHash) != 0);
        assertTrue(sRegistry.appliedOntoV4(writer, namespaceHash, migrationAHash) != bytes32(0));

        assertEq(sRegistry.appliedV4(writer, namespaceHash, migrationBHash), 0);
        assertEq(sRegistry.appliedOntoV4(writer, namespaceHash, migrationBHash), bytes32(0));
    }
}
