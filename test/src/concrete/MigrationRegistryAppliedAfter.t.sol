// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";

import {
    IMigrationRegistryV2,
    Prerequisite,
    MIGRATION_HEAD_GENESIS
} from "../../../src/interface/IMigrationRegistryV2.sol";
import {MigrationRegistry} from "../../../src/concrete/MigrationRegistry.sol";
import {LibMigrationFuzz} from "../../lib/LibMigrationFuzz.sol";

/// @title MigrationRegistryAppliedAfterTest
/// @notice A test suite for `MigrationRegistry.appliedAfter`: it answers an
/// applied migration with the list the write gave, as given — the head under
/// the writer in its namespace, then the prerequisites; an unapplied one with
/// an empty list; refuses the four inputs that can only be mistakes; and is
/// the step that walks from a record to everything it waited on.
contract MigrationRegistryAppliedAfterTest is Test {
    /// The registry under test. Stateful, so a fresh one per test.
    MigrationRegistry internal sRegistry;

    function setUp() external {
        sRegistry = new MigrationRegistry();
    }

    /// One prerequisite, as a list.
    /// @param writer The prerequisite's writer.
    /// @param namespace The prerequisite's namespace.
    /// @param migration The prerequisite's migration.
    /// @return prerequisites The one-entry list.
    function one(address writer, bytes32 namespace, bytes32 migration)
        internal
        pure
        returns (Prerequisite[] memory prerequisites)
    {
        prerequisites = new Prerequisite[](1);
        prerequisites[0] = Prerequisite({writer: writer, namespace: namespace, migration: migration});
    }

    /// The empty list, so a test says what it expects rather than a length.
    /// @return The empty list.
    function none() internal pure returns (Prerequisite[] memory) {
        return new Prerequisite[](0);
    }

    /// The list a write under `writer` in `namespace` onto `head` after
    /// `prerequisites` passes, which is the list its record reads back.
    /// @param writer The writer the record is under.
    /// @param namespace The line the record is in.
    /// @param head The head it is applied onto.
    /// @param prerequisites The records it waits on.
    /// @return recorded The head under the writer in the namespace, then the
    /// prerequisites.
    function headThen(address writer, bytes32 namespace, bytes32 head, Prerequisite[] memory prerequisites)
        internal
        pure
        returns (Prerequisite[] memory recorded)
    {
        recorded = new Prerequisite[](prerequisites.length + 1);
        recorded[0] = Prerequisite({writer: writer, namespace: namespace, migration: head});
        for (uint256 i = 0; i < prerequisites.length; i++) {
            recorded[i + 1] = prerequisites[i];
        }
    }

    /// Applies `migration` under `writer` in `namespace` onto wherever that
    /// line is, waiting on nothing.
    /// @param writer The writer to apply under.
    /// @param namespace The line to apply in.
    /// @param migration The migration to apply.
    function applyUnder(address writer, bytes32 namespace, bytes32 migration) internal {
        // The head is read before the prank: the read is an external call
        // of its own and would consume the prank meant for the write.
        bytes32 head = sRegistry.head(writer, namespace);
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migration, headThen(writer, namespace, head, none()));
    }

    /// An unapplied migration answers an empty list rather than reverting,
    /// exactly as `applied` answers zero. No record answers empty: every
    /// record was applied after its head, so an empty answer says there is no
    /// record and nothing else.
    function testAppliedAfterUnappliedIsEmpty(address writer, bytes32 namespace, bytes32 migration) external view {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migration);

        assertEq(abi.encode(sRegistry.appliedAfter(writer, namespace, migration)), abi.encode(none()));
    }

    /// A root, applied after nothing, answers exactly its head: genesis, under
    /// the writer in the namespace. On both writes.
    function testAppliedAfterRootWithoutPrerequisitesIsGenesis(
        address writer,
        bytes32 namespace,
        bytes32 migrationA,
        bytes32 migrationB,
        uint32 now_
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.assume(migrationA != migrationB);
        vm.assume(now_ != 0);
        vm.warp(now_);

        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationA, one(writer, namespace, MIGRATION_HEAD_GENESIS));
        assertEq(
            abi.encode(sRegistry.appliedAfter(writer, namespace, migrationA)),
            abi.encode(one(writer, namespace, MIGRATION_HEAD_GENESIS))
        );

        MigrationRegistry history = new MigrationRegistry();
        vm.prank(writer);
        history.applyMigrationHistory(namespace, migrationB, now_, one(writer, namespace, MIGRATION_HEAD_GENESIS));
        assertEq(
            abi.encode(history.appliedAfter(writer, namespace, migrationB)),
            abi.encode(one(writer, namespace, MIGRATION_HEAD_GENESIS))
        );
    }

    /// A migration applied onto another, after nothing, answers exactly that
    /// predecessor under the writer in the namespace, which is what
    /// `appliedOnto` answers too. On both writes.
    function testAppliedAfterNonRootWithoutPrerequisitesIsTheHead(
        address writer,
        bytes32 namespace,
        bytes32 migrationA,
        bytes32 migrationB,
        bytes32 migrationC,
        uint32 now_
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        LibMigrationFuzz.assumeMigration(vm, migrationC);
        vm.assume(migrationA != migrationB);
        vm.assume(migrationA != migrationC);
        vm.assume(migrationB != migrationC);
        vm.assume(now_ != 0);
        vm.warp(now_);
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationA, one(writer, namespace, MIGRATION_HEAD_GENESIS));

        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationB, one(writer, namespace, migrationA));
        assertEq(
            abi.encode(sRegistry.appliedAfter(writer, namespace, migrationB)),
            abi.encode(one(writer, namespace, migrationA))
        );
        assertEq(
            sRegistry.appliedAfter(writer, namespace, migrationB)[0].migration,
            sRegistry.appliedOnto(writer, namespace, migrationB)
        );

        vm.prank(writer);
        sRegistry.applyMigrationHistory(namespace, migrationC, now_, one(writer, namespace, migrationB));
        assertEq(
            abi.encode(sRegistry.appliedAfter(writer, namespace, migrationC)),
            abi.encode(one(writer, namespace, migrationB))
        );
        assertEq(
            sRegistry.appliedAfter(writer, namespace, migrationC)[0].migration,
            sRegistry.appliedOnto(writer, namespace, migrationC)
        );
    }

    /// A root with prerequisites answers genesis and then them; a non-root
    /// with prerequisites answers its predecessor and then them. Each is the
    /// list the write passed. On both writes, in both orders.
    function testAppliedAfterWithPrerequisitesIsTheListAsGiven(
        address writer,
        bytes32 namespace,
        address other,
        bytes32 migrationA,
        bytes32 migrationB,
        bytes32 prerequisite,
        uint32 now_
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        vm.assume(other != address(0));
        vm.assume(writer != other);
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        LibMigrationFuzz.assumeMigration(vm, prerequisite);
        vm.assume(migrationA != migrationB);
        vm.assume(now_ != 0);
        vm.warp(now_);
        applyUnder(other, namespace, prerequisite);

        Prerequisite[] memory rootList =
            headThen(writer, namespace, MIGRATION_HEAD_GENESIS, one(other, namespace, prerequisite));
        Prerequisite[] memory nonRootList = headThen(writer, namespace, migrationA, one(other, namespace, prerequisite));

        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationA, rootList);
        assertEq(abi.encode(sRegistry.appliedAfter(writer, namespace, migrationA)), abi.encode(rootList));

        vm.prank(writer);
        sRegistry.applyMigrationHistory(namespace, migrationB, now_, nonRootList);
        assertEq(abi.encode(sRegistry.appliedAfter(writer, namespace, migrationB)), abi.encode(nonRootList));

        MigrationRegistry history = new MigrationRegistry();
        vm.prank(other);
        history.applyMigration(namespace, prerequisite, one(other, namespace, MIGRATION_HEAD_GENESIS));
        vm.prank(writer);
        history.applyMigrationHistory(namespace, migrationA, now_, rootList);
        assertEq(abi.encode(history.appliedAfter(writer, namespace, migrationA)), abi.encode(rootList));
        vm.prank(writer);
        history.applyMigration(namespace, migrationB, nonRootList);
        assertEq(abi.encode(history.appliedAfter(writer, namespace, migrationB)), abi.encode(nonRootList));
    }

    /// The answer is byte for byte the list the write passed, for a root and
    /// a non-root, on both writes, whatever the prerequisites are: the record
    /// is the list, with nothing added in front and nothing rearranged.
    function testAppliedAfterIsExactlyThePassedList(
        address writer,
        bytes32 namespace,
        bytes32 migrationA,
        bytes32 migrationB,
        bytes32[] memory seeds,
        uint32 now_
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.assume(migrationA != migrationB);
        vm.assume(now_ != 0);
        vm.warp(now_);
        Prerequisite[] memory prerequisites = new Prerequisite[](seeds.length);
        for (uint256 i = 0; i < seeds.length; i++) {
            prerequisites[i] = Prerequisite({
                writer: address(uint160(uint256(keccak256(abi.encode(seeds[i], "writer"))))),
                namespace: keccak256(abi.encode(seeds[i], "namespace")),
                migration: keccak256(abi.encode(seeds[i], "migration"))
            });
            vm.assume(prerequisites[i].writer != address(0));
            vm.assume(prerequisites[i].writer != writer);
            vm.assume(prerequisites[i].namespace != bytes32(0));
            LibMigrationFuzz.assumeMigration(vm, prerequisites[i].migration);
            if (sRegistry.applied(prerequisites[i].writer, prerequisites[i].namespace, prerequisites[i].migration) == 0)
            {
                applyUnder(prerequisites[i].writer, prerequisites[i].namespace, prerequisites[i].migration);
            }
        }
        Prerequisite[] memory rootList = headThen(writer, namespace, MIGRATION_HEAD_GENESIS, prerequisites);
        Prerequisite[] memory nonRootList = headThen(writer, namespace, migrationA, prerequisites);

        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationA, rootList);
        assertEq(abi.encode(sRegistry.appliedAfter(writer, namespace, migrationA)), abi.encode(rootList));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(namespace, migrationB, now_, nonRootList);
        assertEq(abi.encode(sRegistry.appliedAfter(writer, namespace, migrationB)), abi.encode(nonRootList));

        MigrationRegistry history = new MigrationRegistry();
        for (uint256 i = 0; i < prerequisites.length; i++) {
            if (history.applied(prerequisites[i].writer, prerequisites[i].namespace, prerequisites[i].migration) == 0) {
                bytes32 head = history.head(prerequisites[i].writer, prerequisites[i].namespace);
                vm.prank(prerequisites[i].writer);
                history.applyMigration(
                    prerequisites[i].namespace,
                    prerequisites[i].migration,
                    headThen(prerequisites[i].writer, prerequisites[i].namespace, head, none())
                );
            }
        }
        vm.prank(writer);
        history.applyMigrationHistory(namespace, migrationA, now_, rootList);
        assertEq(abi.encode(history.appliedAfter(writer, namespace, migrationA)), abi.encode(rootList));
        vm.prank(writer);
        history.applyMigration(namespace, migrationB, nonRootList);
        assertEq(abi.encode(history.appliedAfter(writer, namespace, migrationB)), abi.encode(nonRootList));
    }

    /// The list answered is the list the registry itself checked rather than
    /// one the caller was free to assert: a caller that names an unapplied
    /// entry is refused and nothing is recorded, so a record can only ever
    /// hold a list every entry of which existed.
    function testAppliedAfterIsTheCheckedList(
        address writer,
        bytes32 namespace,
        address other,
        bytes32 migration,
        bytes32 prerequisite,
        bytes32 unapplied
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        vm.assume(other != address(0));
        vm.assume(writer != other);
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, prerequisite);
        LibMigrationFuzz.assumeMigration(vm, unapplied);
        vm.assume(prerequisite != unapplied);
        applyUnder(other, namespace, prerequisite);

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.PrerequisiteNotApplied.selector, other, namespace, unapplied)
        );
        vm.prank(writer);
        sRegistry.applyMigration(
            namespace, migration, headThen(writer, namespace, MIGRATION_HEAD_GENESIS, one(other, namespace, unapplied))
        );
        assertEq(abi.encode(sRegistry.appliedAfter(writer, namespace, migration)), abi.encode(none()));

        vm.prank(writer);
        sRegistry.applyMigration(
            namespace,
            migration,
            headThen(writer, namespace, MIGRATION_HEAD_GENESIS, one(other, namespace, prerequisite))
        );

        assertEq(
            abi.encode(sRegistry.appliedAfter(writer, namespace, migration)),
            abi.encode(headThen(writer, namespace, MIGRATION_HEAD_GENESIS, one(other, namespace, prerequisite)))
        );
    }

    /// Every entry after the head names a record that exists, and each is
    /// readable the ordinary way; so does the head, once the line has a
    /// predecessor. The walk lands on records.
    function testAppliedAfterEveryEntryIsARecord(
        address writer,
        bytes32 namespace,
        address otherA,
        address otherB,
        bytes32 migration,
        bytes32 prerequisiteA,
        bytes32 prerequisiteB
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        vm.assume(otherA != address(0));
        vm.assume(otherB != address(0));
        vm.assume(writer != otherA);
        vm.assume(writer != otherB);
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, prerequisiteA);
        LibMigrationFuzz.assumeMigration(vm, prerequisiteB);
        vm.assume(migration != prerequisiteA);
        vm.assume(migration != prerequisiteB);
        applyUnder(otherA, namespace, prerequisiteA);
        if (sRegistry.applied(otherB, namespace, prerequisiteB) == 0) {
            applyUnder(otherB, namespace, prerequisiteB);
        }
        Prerequisite[] memory prerequisites = new Prerequisite[](2);
        prerequisites[0] = Prerequisite({writer: otherA, namespace: namespace, migration: prerequisiteA});
        prerequisites[1] = Prerequisite({writer: otherB, namespace: namespace, migration: prerequisiteB});

        bytes32 head = sRegistry.head(writer, namespace);
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migration, headThen(writer, namespace, head, prerequisites));

        Prerequisite[] memory recorded = sRegistry.appliedAfter(writer, namespace, migration);
        assertEq(recorded.length, 3);
        assertEq(recorded[0].writer, writer);
        assertEq(recorded[0].namespace, namespace);
        assertEq(recorded[0].migration, head);
        if (head != MIGRATION_HEAD_GENESIS) {
            assertTrue(sRegistry.applied(recorded[0].writer, recorded[0].namespace, recorded[0].migration) != 0);
        }
        for (uint256 i = 0; i < prerequisites.length; i++) {
            assertEq(recorded[i + 1].writer, prerequisites[i].writer);
            assertEq(recorded[i + 1].namespace, prerequisites[i].namespace);
            assertEq(recorded[i + 1].migration, prerequisites[i].migration);
            assertTrue(
                sRegistry.applied(recorded[i + 1].writer, recorded[i + 1].namespace, recorded[i + 1].migration) != 0
            );
        }
    }

    /// A duplicate is kept: the list is what the caller listed, not a set.
    function testAppliedAfterDuplicatesAreKept(
        address writer,
        bytes32 namespace,
        address other,
        bytes32 migration,
        bytes32 prerequisite
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        vm.assume(other != address(0));
        vm.assume(writer != other);
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, prerequisite);
        vm.assume(migration != prerequisite);
        applyUnder(other, namespace, prerequisite);
        Prerequisite[] memory prerequisites = new Prerequisite[](2);
        prerequisites[0] = Prerequisite({writer: other, namespace: namespace, migration: prerequisite});
        prerequisites[1] = Prerequisite({writer: other, namespace: namespace, migration: prerequisite});

        bytes32 head = sRegistry.head(writer, namespace);
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migration, headThen(writer, namespace, head, prerequisites));

        assertEq(sRegistry.appliedAfter(writer, namespace, migration).length, 3);
        assertEq(
            abi.encode(sRegistry.appliedAfter(writer, namespace, migration)),
            abi.encode(headThen(writer, namespace, head, prerequisites))
        );
    }

    /// A record never moves. The answer for an earlier migration is the same
    /// after a later one lands with a different list, so a walk read at any
    /// moment describes the same history.
    function testAppliedAfterRecordsAreImmutable(
        address writer,
        bytes32 namespace,
        address other,
        bytes32 migrationA,
        bytes32 migrationB,
        bytes32 prerequisite
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        vm.assume(other != address(0));
        vm.assume(writer != other);
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        LibMigrationFuzz.assumeMigration(vm, prerequisite);
        vm.assume(migrationA != migrationB);
        applyUnder(other, namespace, prerequisite);
        Prerequisite[] memory listA =
            headThen(writer, namespace, MIGRATION_HEAD_GENESIS, one(other, namespace, prerequisite));

        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationA, listA);
        assertEq(abi.encode(sRegistry.appliedAfter(writer, namespace, migrationA)), abi.encode(listA));

        Prerequisite[] memory listB = headThen(writer, namespace, migrationA, one(other, namespace, prerequisite));
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationB, listB);

        assertEq(abi.encode(sRegistry.appliedAfter(writer, namespace, migrationA)), abi.encode(listA));
        assertEq(abi.encode(sRegistry.appliedAfter(writer, namespace, migrationB)), abi.encode(listB));
    }

    /// Reading twice answers the same way.
    function testAppliedAfterIsIdempotent(
        address writer,
        bytes32 namespace,
        address other,
        bytes32 migration,
        bytes32 prerequisite
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        vm.assume(other != address(0));
        vm.assume(writer != other);
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, prerequisite);
        vm.assume(migration != prerequisite);
        applyUnder(other, namespace, prerequisite);

        bytes32 head = sRegistry.head(writer, namespace);
        Prerequisite[] memory expected = headThen(writer, namespace, head, one(other, namespace, prerequisite));
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migration, expected);

        assertEq(abi.encode(sRegistry.appliedAfter(writer, namespace, migration)), abi.encode(expected));
        assertEq(abi.encode(sRegistry.appliedAfter(writer, namespace, migration)), abi.encode(expected));
    }

    /// A record is confined to the caller's line here as everywhere else:
    /// one writer's list says nothing about another's, including the
    /// writer the list names, whose own record answers only its own head.
    function testAppliedAfterIsPerWriter(
        address writer,
        bytes32 namespace,
        address other,
        bytes32 migration,
        bytes32 prerequisite
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        vm.assume(other != address(0));
        vm.assume(writer != other);
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, prerequisite);
        vm.assume(migration != prerequisite);
        applyUnder(other, namespace, prerequisite);

        vm.prank(writer);
        sRegistry.applyMigration(
            namespace,
            migration,
            headThen(writer, namespace, MIGRATION_HEAD_GENESIS, one(other, namespace, prerequisite))
        );

        assertEq(
            abi.encode(sRegistry.appliedAfter(writer, namespace, migration)),
            abi.encode(headThen(writer, namespace, MIGRATION_HEAD_GENESIS, one(other, namespace, prerequisite)))
        );
        assertEq(
            abi.encode(sRegistry.appliedAfter(other, namespace, prerequisite)),
            abi.encode(one(other, namespace, MIGRATION_HEAD_GENESIS))
        );
        assertEq(abi.encode(sRegistry.appliedAfter(other, namespace, migration)), abi.encode(none()));
        assertEq(abi.encode(sRegistry.appliedAfter(writer, namespace, prerequisite)), abi.encode(none()));
    }

    /// A record is confined to its namespace within the writer too: a list
    /// written in one namespace answers there and nowhere else under the same
    /// writer.
    function testAppliedAfterIsPerNamespace(
        address writer,
        bytes32 namespace,
        bytes32 otherNamespace,
        address other,
        bytes32 migration,
        bytes32 prerequisite
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        vm.assume(otherNamespace != bytes32(0));
        vm.assume(namespace != otherNamespace);
        vm.assume(other != address(0));
        vm.assume(writer != other);
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, prerequisite);
        vm.assume(migration != prerequisite);
        applyUnder(other, namespace, prerequisite);

        Prerequisite[] memory expected =
            headThen(writer, namespace, MIGRATION_HEAD_GENESIS, one(other, namespace, prerequisite));
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migration, expected);

        assertEq(abi.encode(sRegistry.appliedAfter(writer, namespace, migration)), abi.encode(expected));
        assertEq(abi.encode(sRegistry.appliedAfter(writer, otherNamespace, migration)), abi.encode(none()));
        assertEq(abi.encode(sRegistry.appliedAfter(other, otherNamespace, prerequisite)), abi.encode(none()));
    }

    /// The zero writer is refused rather than answered, for the reason `applied`
    /// refuses it: every line under the zero writer is provably empty, so an
    /// unresolved writer constant would read as "never applied" rather than
    /// as the mistake it is.
    function testAppliedAfterZeroWriterReverts(bytes32 namespace, bytes32 migration) external {
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migration);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroWriter.selector));
        sRegistry.appliedAfter(address(0), namespace, migration);
    }

    /// The zero namespace is refused: no write names it, so no line is ever
    /// there and an unset namespace constant would read as "never applied".
    function testAppliedAfterZeroNamespaceReverts(address writer, bytes32 migration) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeMigration(vm, migration);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroNamespace.selector));
        sRegistry.appliedAfter(writer, bytes32(0), migration);
    }

    /// The zero migration id is refused: neither write records it, so it can
    /// never be a real record.
    function testAppliedAfterZeroMigrationReverts(address writer, bytes32 namespace) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroMigration.selector));
        sRegistry.appliedAfter(writer, namespace, bytes32(0));
    }

    /// The genesis head is refused as a migration: it is a head, no line
    /// ever applies it, and a caller asking what it was applied after has
    /// confused a head for a record.
    function testAppliedAfterGenesisMigrationReverts(address writer, bytes32 namespace) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.GenesisMigration.selector));
        sRegistry.appliedAfter(writer, namespace, MIGRATION_HEAD_GENESIS);
    }

    /// The writer is checked before the namespace and the migration, so a
    /// caller that has zeroed everything gets one stable answer rather than
    /// one that depends on which check happens to run — the same order
    /// `applied` uses, from the same check.
    function testAppliedAfterZeroWriterCheckedFirst() external {
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroWriter.selector));
        sRegistry.appliedAfter(address(0), bytes32(0), bytes32(0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroWriter.selector));
        sRegistry.appliedAfter(address(0), bytes32(0), MIGRATION_HEAD_GENESIS);
    }

    /// The namespace is checked after the writer and before the migration.
    function testAppliedAfterZeroNamespaceCheckedAfterWriterBeforeMigration(address writer, bytes32 namespace)
        external
    {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroWriter.selector));
        sRegistry.appliedAfter(address(0), bytes32(0), bytes32(0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroNamespace.selector));
        sRegistry.appliedAfter(writer, bytes32(0), bytes32(0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroNamespace.selector));
        sRegistry.appliedAfter(writer, bytes32(0), MIGRATION_HEAD_GENESIS);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroMigration.selector));
        sRegistry.appliedAfter(writer, namespace, bytes32(0));
    }

    /// A refusal is not a state change: the refused cases revert on a registry
    /// that holds records exactly as they do on an empty one, and leave those
    /// records intact.
    function testAppliedAfterRefusalLeavesRecordsIntact(
        address writer,
        bytes32 namespace,
        address other,
        bytes32 migration,
        bytes32 prerequisite
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        vm.assume(other != address(0));
        vm.assume(writer != other);
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, prerequisite);
        vm.assume(migration != prerequisite);
        applyUnder(other, namespace, prerequisite);

        bytes32 head = sRegistry.head(writer, namespace);
        vm.prank(writer);
        sRegistry.applyMigration(
            namespace, migration, headThen(writer, namespace, head, one(other, namespace, prerequisite))
        );

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroWriter.selector));
        sRegistry.appliedAfter(address(0), namespace, migration);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroNamespace.selector));
        sRegistry.appliedAfter(writer, bytes32(0), migration);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroMigration.selector));
        sRegistry.appliedAfter(writer, namespace, bytes32(0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.GenesisMigration.selector));
        sRegistry.appliedAfter(writer, namespace, MIGRATION_HEAD_GENESIS);

        assertEq(
            abi.encode(sRegistry.appliedAfter(writer, namespace, migration)),
            abi.encode(headThen(writer, namespace, head, one(other, namespace, prerequisite)))
        );
        assertEq(sRegistry.head(writer, namespace), migration);
    }

    /// The readers of a record agree about whether it exists: a nonempty list
    /// comes with a nonzero `applied` and an empty one with a zero `applied`,
    /// in both directions, because every record was applied after its head
    /// and the whole record is written in one call.
    function testAppliedAfterAgreesWithApplied(
        address writer,
        bytes32 namespace,
        address other,
        bytes32 migrationA,
        bytes32 migrationB,
        bytes32 prerequisite
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        vm.assume(other != address(0));
        vm.assume(writer != other);
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        LibMigrationFuzz.assumeMigration(vm, prerequisite);
        vm.assume(migrationA != migrationB);
        applyUnder(other, namespace, prerequisite);

        assertEq(sRegistry.applied(writer, namespace, migrationA), 0);
        assertEq(sRegistry.appliedAfter(writer, namespace, migrationA).length, 0);

        vm.prank(writer);
        sRegistry.applyMigration(
            namespace,
            migrationA,
            headThen(writer, namespace, MIGRATION_HEAD_GENESIS, one(other, namespace, prerequisite))
        );

        assertTrue(sRegistry.applied(writer, namespace, migrationA) != 0);
        assertEq(sRegistry.appliedAfter(writer, namespace, migrationA).length, 2);

        assertEq(sRegistry.applied(writer, namespace, migrationB), 0);
        assertEq(sRegistry.appliedAfter(writer, namespace, migrationB).length, 0);

        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationB, one(writer, namespace, migrationA));

        assertTrue(sRegistry.applied(writer, namespace, migrationB) != 0);
        assertEq(sRegistry.appliedAfter(writer, namespace, migrationB).length, 1);
    }
}
