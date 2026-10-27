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

/// @title MigrationRegistryAppliedAfterTest
/// @notice A test suite for `MigrationRegistry.appliedAfterV4`: it answers an
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
    /// @param namespaceHash The prerequisite's namespace hash.
    /// @param migrationHash The prerequisite's migration hash.
    /// @return The one-entry list.
    function one(address writer, bytes32 namespaceHash, bytes32 migrationHash)
        internal
        pure
        returns (Prerequisite[] memory)
    {
        Prerequisite[] memory prerequisites = new Prerequisite[](1);
        prerequisites[0] = Prerequisite({writer: writer, namespace: namespaceHash, migration: migrationHash});
        return prerequisites;
    }

    /// The empty list, so a test says what it expects rather than a length.
    /// @return The empty list.
    function none() internal pure returns (Prerequisite[] memory) {
        return new Prerequisite[](0);
    }

    /// The list a write under `writer` in `namespaceHash` onto `head` after
    /// `prerequisites` passes, which is the list its record reads back.
    /// @param writer The writer the record is under.
    /// @param namespaceHash The line the record is in.
    /// @param head The head it is applied onto.
    /// @param prerequisites The records it waits on.
    /// @return The head under the writer in the namespace, then the
    /// prerequisites.
    function headThen(address writer, bytes32 namespaceHash, bytes32 head, Prerequisite[] memory prerequisites)
        internal
        pure
        returns (Prerequisite[] memory)
    {
        Prerequisite[] memory recorded = new Prerequisite[](prerequisites.length + 1);
        recorded[0] = Prerequisite({writer: writer, namespace: namespaceHash, migration: head});
        for (uint256 i = 0; i < prerequisites.length; i++) {
            recorded[i + 1] = prerequisites[i];
        }
        return recorded;
    }

    /// Applies `migration` under `writer` in `namespace` on `registry` onto
    /// wherever that line is, waiting on nothing.
    /// @param registry The registry to apply on.
    /// @param writer The writer to apply under.
    /// @param namespace The line to apply in.
    /// @param migration The migration to apply.
    function applyUnder(MigrationRegistry registry, address writer, string memory namespace, string memory migration)
        internal
    {
        bytes32 namespaceHash = keccak256(bytes(namespace));
        // The head is read before the prank: the read is an external call
        // of its own and would consume the prank meant for the write.
        bytes32 head = registry.headV4(writer, namespaceHash);
        vm.prank(writer);
        registry.applyMigrationV4(writer, namespace, migration, headThen(writer, namespaceHash, head, none()));
    }

    /// The prerequisites `seeds` derive, each under a writer other than
    /// `writer`, with the strings that write each one.
    /// @param seeds One seed per prerequisite.
    /// @param writer The writer no prerequisite may be under.
    /// @return prerequisites The hash-keyed list.
    /// @return namespaces The namespace string of each entry.
    /// @return migrations The migration string of each entry.
    function seededPrerequisites(bytes32[] memory seeds, address writer)
        internal
        pure
        returns (Prerequisite[] memory, string[] memory, string[] memory)
    {
        Prerequisite[] memory prerequisites = new Prerequisite[](seeds.length);
        string[] memory namespaces = new string[](seeds.length);
        string[] memory migrations = new string[](seeds.length);
        for (uint256 i = 0; i < seeds.length; i++) {
            namespaces[i] = string(abi.encode(seeds[i], "namespace"));
            migrations[i] = string(abi.encode(seeds[i], "migration"));
            prerequisites[i] = Prerequisite({
                writer: address(uint160(uint256(keccak256(abi.encode(seeds[i], "writer"))))),
                namespace: keccak256(bytes(namespaces[i])),
                migration: keccak256(bytes(migrations[i]))
            });
            vm.assume(prerequisites[i].writer != address(0));
            vm.assume(prerequisites[i].writer != writer);
            LibMigrationFuzz.assumeMigration(vm, prerequisites[i].migration);
        }
        return (prerequisites, namespaces, migrations);
    }

    /// Applies every entry of `prerequisites` on `registry` that is not
    /// already applied there.
    /// @param registry The registry to apply on.
    /// @param prerequisites The hash-keyed list.
    /// @param namespaces The namespace string of each entry.
    /// @param migrations The migration string of each entry.
    function applyAll(
        MigrationRegistry registry,
        Prerequisite[] memory prerequisites,
        string[] memory namespaces,
        string[] memory migrations
    ) internal {
        for (uint256 i = 0; i < prerequisites.length; i++) {
            if (
                registry.appliedV4(prerequisites[i].writer, prerequisites[i].namespace, prerequisites[i].migration) == 0
            ) {
                applyUnder(registry, prerequisites[i].writer, namespaces[i], migrations[i]);
            }
        }
    }

    /// An unapplied migration answers an empty list rather than reverting,
    /// exactly as `appliedV4` answers zero. No record answers empty: every
    /// record was applied after its head, so an empty answer says there is no
    /// record and nothing else.
    function testAppliedAfterUnappliedIsEmpty(address writer, bytes32 namespaceHash, bytes32 migrationHash)
        external
        view
    {
        vm.assume(writer != address(0));
        vm.assume(namespaceHash != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migrationHash);

        assertEq(abi.encode(sRegistry.appliedAfterV4(writer, namespaceHash, migrationHash)), abi.encode(none()));
    }

    /// A root, applied after nothing, answers exactly its head: genesis, under
    /// the writer in the namespace. On both writes.
    function testAppliedAfterRootWithoutPrerequisitesIsGenesis(
        address writer,
        string memory namespace,
        string memory migrationA,
        string memory migrationB,
        uint32 blockMoment
    ) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeNamespace(vm, namespace);
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.assume(keccak256(bytes(migrationA)) != keccak256(bytes(migrationB)));
        vm.assume(blockMoment != 0);
        vm.warp(blockMoment);
        bytes32 namespaceHash = keccak256(bytes(namespace));

        vm.prank(writer);
        sRegistry.applyMigrationV4(writer, namespace, migrationA, one(writer, namespaceHash, MIGRATION_HEAD_GENESIS));
        assertEq(
            abi.encode(sRegistry.appliedAfterV4(writer, namespaceHash, keccak256(bytes(migrationA)))),
            abi.encode(one(writer, namespaceHash, MIGRATION_HEAD_GENESIS))
        );

        MigrationRegistry history = new MigrationRegistry();
        vm.prank(writer);
        history.applyMigrationHistoryV4(
            writer, namespace, migrationB, blockMoment, one(writer, namespaceHash, MIGRATION_HEAD_GENESIS)
        );
        assertEq(
            abi.encode(history.appliedAfterV4(writer, namespaceHash, keccak256(bytes(migrationB)))),
            abi.encode(one(writer, namespaceHash, MIGRATION_HEAD_GENESIS))
        );
    }

    /// A migration applied onto another, after nothing, answers exactly that
    /// predecessor under the writer in the namespace, which is what
    /// `appliedOntoV4` answers too. On both writes.
    function testAppliedAfterNonRootWithoutPrerequisitesIsTheHead(
        address writer,
        string memory namespace,
        string memory migrationA,
        string memory migrationB,
        string memory migrationC,
        uint32 blockMoment
    ) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeNamespace(vm, namespace);
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        LibMigrationFuzz.assumeMigration(vm, migrationC);
        bytes32 namespaceHash = keccak256(bytes(namespace));
        bytes32 migrationAHash = keccak256(bytes(migrationA));
        bytes32 migrationBHash = keccak256(bytes(migrationB));
        vm.assume(migrationAHash != migrationBHash);
        vm.assume(migrationAHash != keccak256(bytes(migrationC)));
        vm.assume(migrationBHash != keccak256(bytes(migrationC)));
        vm.assume(blockMoment != 0);
        vm.warp(blockMoment);
        vm.prank(writer);
        sRegistry.applyMigrationV4(writer, namespace, migrationA, one(writer, namespaceHash, MIGRATION_HEAD_GENESIS));

        vm.prank(writer);
        sRegistry.applyMigrationV4(writer, namespace, migrationB, one(writer, namespaceHash, migrationAHash));
        assertEq(
            abi.encode(sRegistry.appliedAfterV4(writer, namespaceHash, migrationBHash)),
            abi.encode(one(writer, namespaceHash, migrationAHash))
        );
        assertEq(
            sRegistry.appliedAfterV4(writer, namespaceHash, migrationBHash)[0].migration,
            sRegistry.appliedOntoV4(writer, namespaceHash, migrationBHash)
        );

        vm.prank(writer);
        sRegistry.applyMigrationHistoryV4(
            writer, namespace, migrationC, blockMoment, one(writer, namespaceHash, migrationBHash)
        );
        assertEq(
            abi.encode(sRegistry.appliedAfterV4(writer, namespaceHash, keccak256(bytes(migrationC)))),
            abi.encode(one(writer, namespaceHash, migrationBHash))
        );
        assertEq(
            sRegistry.appliedAfterV4(writer, namespaceHash, keccak256(bytes(migrationC)))[0].migration,
            sRegistry.appliedOntoV4(writer, namespaceHash, keccak256(bytes(migrationC)))
        );
    }

    /// A root with prerequisites answers genesis and then them; a non-root
    /// with prerequisites answers its predecessor and then them. Each is the
    /// list the write passed. On both writes, in both orders.
    function testAppliedAfterWithPrerequisitesIsTheListAsGiven(
        address writer,
        string memory namespace,
        address other,
        string memory migrationA,
        string memory migrationB,
        string memory prerequisite,
        uint32 blockMoment
    ) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeNamespace(vm, namespace);
        vm.assume(other != address(0));
        vm.assume(writer != other);
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        LibMigrationFuzz.assumeMigration(vm, prerequisite);
        vm.assume(keccak256(bytes(migrationA)) != keccak256(bytes(migrationB)));
        vm.assume(blockMoment != 0);
        vm.warp(blockMoment);
        applyUnder(sRegistry, other, namespace, prerequisite);

        Prerequisite[] memory rootList = headThen(
            writer,
            keccak256(bytes(namespace)),
            MIGRATION_HEAD_GENESIS,
            one(other, keccak256(bytes(namespace)), keccak256(bytes(prerequisite)))
        );
        Prerequisite[] memory nonRootList = headThen(
            writer,
            keccak256(bytes(namespace)),
            keccak256(bytes(migrationA)),
            one(other, keccak256(bytes(namespace)), keccak256(bytes(prerequisite)))
        );

        vm.prank(writer);
        sRegistry.applyMigrationV4(writer, namespace, migrationA, rootList);
        assertEq(
            abi.encode(sRegistry.appliedAfterV4(writer, keccak256(bytes(namespace)), keccak256(bytes(migrationA)))),
            abi.encode(rootList)
        );

        vm.prank(writer);
        sRegistry.applyMigrationHistoryV4(writer, namespace, migrationB, blockMoment, nonRootList);
        assertEq(
            abi.encode(sRegistry.appliedAfterV4(writer, keccak256(bytes(namespace)), keccak256(bytes(migrationB)))),
            abi.encode(nonRootList)
        );

        MigrationRegistry history = new MigrationRegistry();
        applyUnder(history, other, namespace, prerequisite);
        vm.prank(writer);
        history.applyMigrationHistoryV4(writer, namespace, migrationA, blockMoment, rootList);
        assertEq(
            abi.encode(history.appliedAfterV4(writer, keccak256(bytes(namespace)), keccak256(bytes(migrationA)))),
            abi.encode(rootList)
        );
        vm.prank(writer);
        history.applyMigrationV4(writer, namespace, migrationB, nonRootList);
        assertEq(
            abi.encode(history.appliedAfterV4(writer, keccak256(bytes(namespace)), keccak256(bytes(migrationB)))),
            abi.encode(nonRootList)
        );
    }

    /// The answer is byte for byte the list the write passed, for a root and
    /// a non-root, on both writes, whatever the prerequisites are: the record
    /// is the list, with nothing added in front and nothing rearranged.
    function testAppliedAfterIsExactlyThePassedList(
        address writer,
        string memory namespace,
        string memory migrationA,
        string memory migrationB,
        bytes32[] memory seeds,
        uint32 blockMoment
    ) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeNamespace(vm, namespace);
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        bytes32 namespaceHash = keccak256(bytes(namespace));
        vm.assume(keccak256(bytes(migrationA)) != keccak256(bytes(migrationB)));
        vm.assume(blockMoment != 0);
        vm.warp(blockMoment);
        (Prerequisite[] memory prerequisites, string[] memory namespaces, string[] memory migrations) =
            seededPrerequisites(seeds, writer);
        applyAll(sRegistry, prerequisites, namespaces, migrations);
        Prerequisite[] memory rootList = headThen(writer, namespaceHash, MIGRATION_HEAD_GENESIS, prerequisites);
        Prerequisite[] memory nonRootList = headThen(writer, namespaceHash, keccak256(bytes(migrationA)), prerequisites);

        vm.prank(writer);
        sRegistry.applyMigrationV4(writer, namespace, migrationA, rootList);
        assertEq(
            abi.encode(sRegistry.appliedAfterV4(writer, namespaceHash, keccak256(bytes(migrationA)))),
            abi.encode(rootList)
        );
        vm.prank(writer);
        sRegistry.applyMigrationHistoryV4(writer, namespace, migrationB, blockMoment, nonRootList);
        assertEq(
            abi.encode(sRegistry.appliedAfterV4(writer, namespaceHash, keccak256(bytes(migrationB)))),
            abi.encode(nonRootList)
        );

        MigrationRegistry history = new MigrationRegistry();
        applyAll(history, prerequisites, namespaces, migrations);
        vm.prank(writer);
        history.applyMigrationHistoryV4(writer, namespace, migrationA, blockMoment, rootList);
        assertEq(
            abi.encode(history.appliedAfterV4(writer, namespaceHash, keccak256(bytes(migrationA)))),
            abi.encode(rootList)
        );
        vm.prank(writer);
        history.applyMigrationV4(writer, namespace, migrationB, nonRootList);
        assertEq(
            abi.encode(history.appliedAfterV4(writer, namespaceHash, keccak256(bytes(migrationB)))),
            abi.encode(nonRootList)
        );
    }

    /// The list answered is the list the registry itself checked rather than
    /// one the caller was free to assert: a caller that names an unapplied
    /// entry is refused and nothing is recorded, so a record can only ever
    /// hold a list every entry of which existed.
    function testAppliedAfterIsTheCheckedList(
        address writer,
        string memory namespace,
        address other,
        string memory migration,
        string memory prerequisite,
        bytes32 unapplied
    ) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeNamespace(vm, namespace);
        vm.assume(other != address(0));
        vm.assume(writer != other);
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, prerequisite);
        LibMigrationFuzz.assumeMigration(vm, unapplied);
        bytes32 namespaceHash = keccak256(bytes(namespace));
        bytes32 prerequisiteHash = keccak256(bytes(prerequisite));
        vm.assume(prerequisiteHash != unapplied);
        applyUnder(sRegistry, other, namespace, prerequisite);

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV4.PrerequisiteNotApplied.selector, other, namespaceHash, unapplied
            )
        );
        vm.prank(writer);
        sRegistry.applyMigrationV4(
            writer,
            namespace,
            migration,
            headThen(writer, namespaceHash, MIGRATION_HEAD_GENESIS, one(other, namespaceHash, unapplied))
        );
        assertEq(
            abi.encode(sRegistry.appliedAfterV4(writer, namespaceHash, keccak256(bytes(migration)))), abi.encode(none())
        );

        vm.prank(writer);
        sRegistry.applyMigrationV4(
            writer,
            namespace,
            migration,
            headThen(writer, namespaceHash, MIGRATION_HEAD_GENESIS, one(other, namespaceHash, prerequisiteHash))
        );

        assertEq(
            abi.encode(sRegistry.appliedAfterV4(writer, namespaceHash, keccak256(bytes(migration)))),
            abi.encode(
                headThen(writer, namespaceHash, MIGRATION_HEAD_GENESIS, one(other, namespaceHash, prerequisiteHash))
            )
        );
    }

    /// Every entry after the head names a record that exists, and each is
    /// readable the ordinary way; so does the head, once the line has a
    /// predecessor. The walk lands on records.
    function testAppliedAfterEveryEntryIsARecord(
        address writer,
        string memory namespace,
        address otherA,
        address otherB,
        string memory migration,
        string memory prerequisiteA,
        string memory prerequisiteB
    ) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeNamespace(vm, namespace);
        vm.assume(otherA != address(0));
        vm.assume(otherB != address(0));
        vm.assume(writer != otherA);
        vm.assume(writer != otherB);
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, prerequisiteA);
        LibMigrationFuzz.assumeMigration(vm, prerequisiteB);
        vm.assume(keccak256(bytes(migration)) != keccak256(bytes(prerequisiteA)));
        vm.assume(keccak256(bytes(migration)) != keccak256(bytes(prerequisiteB)));
        bytes32 namespaceHash = keccak256(bytes(namespace));
        applyUnder(sRegistry, otherA, namespace, prerequisiteA);
        if (sRegistry.appliedV4(otherB, namespaceHash, keccak256(bytes(prerequisiteB))) == 0) {
            applyUnder(sRegistry, otherB, namespace, prerequisiteB);
        }
        Prerequisite[] memory prerequisites = new Prerequisite[](2);
        prerequisites[0] =
            Prerequisite({writer: otherA, namespace: namespaceHash, migration: keccak256(bytes(prerequisiteA))});
        prerequisites[1] =
            Prerequisite({writer: otherB, namespace: namespaceHash, migration: keccak256(bytes(prerequisiteB))});

        bytes32 head = sRegistry.headV4(writer, namespaceHash);
        vm.prank(writer);
        sRegistry.applyMigrationV4(writer, namespace, migration, headThen(writer, namespaceHash, head, prerequisites));

        Prerequisite[] memory recorded = sRegistry.appliedAfterV4(writer, namespaceHash, keccak256(bytes(migration)));
        assertEq(recorded.length, 3);
        assertEq(recorded[0].writer, writer);
        assertEq(recorded[0].namespace, namespaceHash);
        assertEq(recorded[0].migration, head);
        if (head != MIGRATION_HEAD_GENESIS) {
            assertTrue(sRegistry.appliedV4(recorded[0].writer, recorded[0].namespace, recorded[0].migration) != 0);
        }
        for (uint256 i = 0; i < prerequisites.length; i++) {
            assertEq(recorded[i + 1].writer, prerequisites[i].writer);
            assertEq(recorded[i + 1].namespace, prerequisites[i].namespace);
            assertEq(recorded[i + 1].migration, prerequisites[i].migration);
            assertTrue(
                sRegistry.appliedV4(recorded[i + 1].writer, recorded[i + 1].namespace, recorded[i + 1].migration) != 0
            );
        }
    }

    /// A duplicate is kept: the list is what the caller listed, not a set.
    function testAppliedAfterDuplicatesAreKept(
        address writer,
        string memory namespace,
        address other,
        string memory migration,
        string memory prerequisite
    ) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeNamespace(vm, namespace);
        vm.assume(other != address(0));
        vm.assume(writer != other);
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, prerequisite);
        bytes32 namespaceHash = keccak256(bytes(namespace));
        bytes32 migrationHash = keccak256(bytes(migration));
        bytes32 prerequisiteHash = keccak256(bytes(prerequisite));
        vm.assume(migrationHash != prerequisiteHash);
        applyUnder(sRegistry, other, namespace, prerequisite);
        Prerequisite[] memory prerequisites = new Prerequisite[](2);
        prerequisites[0] = Prerequisite({writer: other, namespace: namespaceHash, migration: prerequisiteHash});
        prerequisites[1] = Prerequisite({writer: other, namespace: namespaceHash, migration: prerequisiteHash});

        bytes32 head = sRegistry.headV4(writer, namespaceHash);
        vm.prank(writer);
        sRegistry.applyMigrationV4(writer, namespace, migration, headThen(writer, namespaceHash, head, prerequisites));

        assertEq(sRegistry.appliedAfterV4(writer, namespaceHash, migrationHash).length, 3);
        assertEq(
            abi.encode(sRegistry.appliedAfterV4(writer, namespaceHash, migrationHash)),
            abi.encode(headThen(writer, namespaceHash, head, prerequisites))
        );
    }

    /// A record never moves. The answer for an earlier migration is the same
    /// after a later one lands with a different list, so a walk read at any
    /// moment describes the same history.
    function testAppliedAfterRecordsAreImmutable(
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
        applyUnder(sRegistry, other, namespace, prerequisite);
        Prerequisite[] memory listA = headThen(
            writer, namespaceHash, MIGRATION_HEAD_GENESIS, one(other, namespaceHash, keccak256(bytes(prerequisite)))
        );

        vm.prank(writer);
        sRegistry.applyMigrationV4(writer, namespace, migrationA, listA);
        assertEq(abi.encode(sRegistry.appliedAfterV4(writer, namespaceHash, migrationAHash)), abi.encode(listA));

        Prerequisite[] memory listB =
            headThen(writer, namespaceHash, migrationAHash, one(other, namespaceHash, keccak256(bytes(prerequisite))));
        vm.prank(writer);
        sRegistry.applyMigrationV4(writer, namespace, migrationB, listB);

        assertEq(abi.encode(sRegistry.appliedAfterV4(writer, namespaceHash, migrationAHash)), abi.encode(listA));
        assertEq(
            abi.encode(sRegistry.appliedAfterV4(writer, namespaceHash, keccak256(bytes(migrationB)))), abi.encode(listB)
        );
    }

    /// Reading twice answers the same way.
    function testAppliedAfterIsIdempotent(
        address writer,
        string memory namespace,
        address other,
        string memory migration,
        string memory prerequisite
    ) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeNamespace(vm, namespace);
        vm.assume(other != address(0));
        vm.assume(writer != other);
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, prerequisite);
        bytes32 namespaceHash = keccak256(bytes(namespace));
        bytes32 migrationHash = keccak256(bytes(migration));
        vm.assume(migrationHash != keccak256(bytes(prerequisite)));
        applyUnder(sRegistry, other, namespace, prerequisite);

        bytes32 head = sRegistry.headV4(writer, namespaceHash);
        Prerequisite[] memory expected =
            headThen(writer, namespaceHash, head, one(other, namespaceHash, keccak256(bytes(prerequisite))));
        vm.prank(writer);
        sRegistry.applyMigrationV4(writer, namespace, migration, expected);

        assertEq(abi.encode(sRegistry.appliedAfterV4(writer, namespaceHash, migrationHash)), abi.encode(expected));
        assertEq(abi.encode(sRegistry.appliedAfterV4(writer, namespaceHash, migrationHash)), abi.encode(expected));
    }

    /// A record is confined to the writer's line here as everywhere else:
    /// one writer's list says nothing about another's, including the
    /// writer the list names, whose own record answers only its own head.
    function testAppliedAfterIsPerWriter(
        address writer,
        string memory namespace,
        address other,
        string memory migration,
        string memory prerequisite
    ) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeNamespace(vm, namespace);
        vm.assume(other != address(0));
        vm.assume(writer != other);
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, prerequisite);
        bytes32 namespaceHash = keccak256(bytes(namespace));
        bytes32 migrationHash = keccak256(bytes(migration));
        bytes32 prerequisiteHash = keccak256(bytes(prerequisite));
        vm.assume(migrationHash != prerequisiteHash);
        applyUnder(sRegistry, other, namespace, prerequisite);

        vm.prank(writer);
        sRegistry.applyMigrationV4(
            writer,
            namespace,
            migration,
            headThen(writer, namespaceHash, MIGRATION_HEAD_GENESIS, one(other, namespaceHash, prerequisiteHash))
        );

        assertEq(
            abi.encode(sRegistry.appliedAfterV4(writer, namespaceHash, migrationHash)),
            abi.encode(
                headThen(writer, namespaceHash, MIGRATION_HEAD_GENESIS, one(other, namespaceHash, prerequisiteHash))
            )
        );
        assertEq(
            abi.encode(sRegistry.appliedAfterV4(other, namespaceHash, prerequisiteHash)),
            abi.encode(one(other, namespaceHash, MIGRATION_HEAD_GENESIS))
        );
        assertEq(abi.encode(sRegistry.appliedAfterV4(other, namespaceHash, migrationHash)), abi.encode(none()));
        assertEq(abi.encode(sRegistry.appliedAfterV4(writer, namespaceHash, prerequisiteHash)), abi.encode(none()));
    }

    /// A record is confined to its namespace within the writer too: a list
    /// written in one namespace answers there and nowhere else under the same
    /// writer.
    function testAppliedAfterIsPerNamespace(
        address writer,
        string memory namespace,
        bytes32 otherNamespaceHash,
        address other,
        string memory migration,
        string memory prerequisite
    ) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeNamespace(vm, namespace);
        bytes32 namespaceHash = keccak256(bytes(namespace));
        vm.assume(otherNamespaceHash != bytes32(0));
        vm.assume(namespaceHash != otherNamespaceHash);
        vm.assume(other != address(0));
        vm.assume(writer != other);
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, prerequisite);
        vm.assume(keccak256(bytes(migration)) != keccak256(bytes(prerequisite)));
        applyUnder(sRegistry, other, namespace, prerequisite);

        Prerequisite[] memory expected = headThen(
            writer, namespaceHash, MIGRATION_HEAD_GENESIS, one(other, namespaceHash, keccak256(bytes(prerequisite)))
        );
        vm.prank(writer);
        sRegistry.applyMigrationV4(writer, namespace, migration, expected);

        assertEq(
            abi.encode(sRegistry.appliedAfterV4(writer, namespaceHash, keccak256(bytes(migration)))),
            abi.encode(expected)
        );
        assertEq(
            abi.encode(sRegistry.appliedAfterV4(writer, otherNamespaceHash, keccak256(bytes(migration)))),
            abi.encode(none())
        );
        assertEq(
            abi.encode(sRegistry.appliedAfterV4(other, otherNamespaceHash, keccak256(bytes(prerequisite)))),
            abi.encode(none())
        );
    }

    /// The zero writer is refused rather than answered, for the reason `appliedV4`
    /// refuses it: every line under the zero writer is provably empty, so an
    /// unresolved writer constant would read as "never applied" rather than
    /// as the mistake it is.
    function testAppliedAfterZeroWriterReverts(bytes32 namespaceHash, bytes32 migrationHash) external {
        vm.assume(namespaceHash != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migrationHash);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.ZeroWriter.selector));
        sRegistry.appliedAfterV4(address(0), namespaceHash, migrationHash);
    }

    /// The zero namespace hash is refused: no write can produce it, so no line
    /// is ever there and an unset namespace hash constant would read as
    /// "never applied".
    function testAppliedAfterZeroNamespaceReverts(address writer, bytes32 migrationHash) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeMigration(vm, migrationHash);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.ZeroNamespace.selector));
        sRegistry.appliedAfterV4(writer, bytes32(0), migrationHash);
    }

    /// The zero migration hash is refused: no write can produce it, so it can
    /// never be a real record.
    function testAppliedAfterZeroMigrationReverts(address writer, bytes32 namespaceHash) external {
        vm.assume(writer != address(0));
        vm.assume(namespaceHash != bytes32(0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.ZeroMigration.selector));
        sRegistry.appliedAfterV4(writer, namespaceHash, bytes32(0));
    }

    /// The genesis head is refused as a migration: it is a head, no line
    /// ever applies it, and a caller asking what it was applied after has
    /// confused a head for a record.
    function testAppliedAfterGenesisMigrationReverts(address writer, bytes32 namespaceHash) external {
        vm.assume(writer != address(0));
        vm.assume(namespaceHash != bytes32(0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.GenesisMigration.selector));
        sRegistry.appliedAfterV4(writer, namespaceHash, MIGRATION_HEAD_GENESIS);
    }

    /// The writer is checked before the namespace and the migration, so a
    /// caller that has zeroed everything gets one stable answer rather than
    /// one that depends on which check happens to run — the same order
    /// `appliedV4` uses, from the same check.
    function testAppliedAfterZeroWriterCheckedFirst() external {
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.ZeroWriter.selector));
        sRegistry.appliedAfterV4(address(0), bytes32(0), bytes32(0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.ZeroWriter.selector));
        sRegistry.appliedAfterV4(address(0), bytes32(0), MIGRATION_HEAD_GENESIS);
    }

    /// The namespace is checked after the writer and before the migration.
    function testAppliedAfterZeroNamespaceCheckedAfterWriterBeforeMigration(address writer, bytes32 namespaceHash)
        external
    {
        vm.assume(writer != address(0));
        vm.assume(namespaceHash != bytes32(0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.ZeroWriter.selector));
        sRegistry.appliedAfterV4(address(0), bytes32(0), bytes32(0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.ZeroNamespace.selector));
        sRegistry.appliedAfterV4(writer, bytes32(0), bytes32(0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.ZeroNamespace.selector));
        sRegistry.appliedAfterV4(writer, bytes32(0), MIGRATION_HEAD_GENESIS);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.ZeroMigration.selector));
        sRegistry.appliedAfterV4(writer, namespaceHash, bytes32(0));
    }

    /// A refusal is not a state change: the refused cases revert on a registry
    /// that holds records exactly as they do on an empty one, and leave those
    /// records intact.
    function testAppliedAfterRefusalLeavesRecordsIntact(
        address writer,
        string memory namespace,
        address other,
        string memory migration,
        string memory prerequisite
    ) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeNamespace(vm, namespace);
        vm.assume(other != address(0));
        vm.assume(writer != other);
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, prerequisite);
        bytes32 namespaceHash = keccak256(bytes(namespace));
        bytes32 migrationHash = keccak256(bytes(migration));
        vm.assume(migrationHash != keccak256(bytes(prerequisite)));
        applyUnder(sRegistry, other, namespace, prerequisite);

        bytes32 head = sRegistry.headV4(writer, namespaceHash);
        Prerequisite[] memory expected =
            headThen(writer, namespaceHash, head, one(other, namespaceHash, keccak256(bytes(prerequisite))));
        vm.prank(writer);
        sRegistry.applyMigrationV4(writer, namespace, migration, expected);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.ZeroWriter.selector));
        sRegistry.appliedAfterV4(address(0), namespaceHash, migrationHash);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.ZeroNamespace.selector));
        sRegistry.appliedAfterV4(writer, bytes32(0), migrationHash);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.ZeroMigration.selector));
        sRegistry.appliedAfterV4(writer, namespaceHash, bytes32(0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.GenesisMigration.selector));
        sRegistry.appliedAfterV4(writer, namespaceHash, MIGRATION_HEAD_GENESIS);

        assertEq(abi.encode(sRegistry.appliedAfterV4(writer, namespaceHash, migrationHash)), abi.encode(expected));
        assertEq(sRegistry.headV4(writer, namespaceHash), migrationHash);
    }

    /// The readers of a record agree about whether it exists: a nonempty list
    /// comes with a nonzero `appliedV4` and an empty one with a zero `appliedV4`,
    /// in both directions, because every record was applied after its head
    /// and the whole record is written in one call.
    function testAppliedAfterAgreesWithApplied(
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
        applyUnder(sRegistry, other, namespace, prerequisite);

        assertEq(sRegistry.appliedV4(writer, namespaceHash, migrationAHash), 0);
        assertEq(sRegistry.appliedAfterV4(writer, namespaceHash, migrationAHash).length, 0);

        vm.prank(writer);
        sRegistry.applyMigrationV4(
            writer,
            namespace,
            migrationA,
            headThen(
                writer, namespaceHash, MIGRATION_HEAD_GENESIS, one(other, namespaceHash, keccak256(bytes(prerequisite)))
            )
        );

        assertTrue(sRegistry.appliedV4(writer, namespaceHash, migrationAHash) != 0);
        assertEq(sRegistry.appliedAfterV4(writer, namespaceHash, migrationAHash).length, 2);

        assertEq(sRegistry.appliedV4(writer, namespaceHash, keccak256(bytes(migrationB))), 0);
        assertEq(sRegistry.appliedAfterV4(writer, namespaceHash, keccak256(bytes(migrationB))).length, 0);

        vm.prank(writer);
        sRegistry.applyMigrationV4(writer, namespace, migrationB, one(writer, namespaceHash, migrationAHash));

        assertTrue(sRegistry.appliedV4(writer, namespaceHash, keccak256(bytes(migrationB))) != 0);
        assertEq(sRegistry.appliedAfterV4(writer, namespaceHash, keccak256(bytes(migrationB))).length, 1);
    }
}
