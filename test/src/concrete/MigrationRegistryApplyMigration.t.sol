// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, Vm} from "forge-std-1.16.2/src/Test.sol";

import {
    IMigrationRegistryV2,
    Prerequisite,
    MIGRATION_HEAD_GENESIS
} from "../../../src/interface/IMigrationRegistryV2.sol";
import {MigrationRegistry} from "../../../src/concrete/MigrationRegistry.sol";
import {LibMigrationFuzz} from "../../lib/LibMigrationFuzz.sol";

/// @title MigrationRegistryApplyMigrationTest
/// @notice A test suite for `MigrationRegistry.applyMigration` and
/// `MigrationRegistry.applyMigrationHistory`: who a record belongs to, that a
/// migration is applied at most once and only onto the head its caller named,
/// which moments a record may carry, which prerequisites hold it back and
/// which are refused before any is read, what a record carries, what the two
/// writes put in the log, and what a record may never become.
contract MigrationRegistryApplyMigrationTest is Test {
    /// The registry under test. Stateful, so a fresh one per test.
    MigrationRegistry internal sRegistry;

    function setUp() external {
        sRegistry = new MigrationRegistry();
    }

    /// One prerequisite, as a list. Most cases here that wait on something
    /// wait on exactly one thing and the entry point takes a list, so this is
    /// the list.
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

    /// Two prerequisites, as a list, in the order given.
    /// @param writerA The first prerequisite's writer.
    /// @param namespaceA The first prerequisite's namespace.
    /// @param migrationA The first prerequisite's migration.
    /// @param writerB The second prerequisite's writer.
    /// @param namespaceB The second prerequisite's namespace.
    /// @param migrationB The second prerequisite's migration.
    /// @return prerequisites The two-entry list.
    function two(
        address writerA,
        bytes32 namespaceA,
        bytes32 migrationA,
        address writerB,
        bytes32 namespaceB,
        bytes32 migrationB
    ) internal pure returns (Prerequisite[] memory prerequisites) {
        prerequisites = new Prerequisite[](2);
        prerequisites[0] = Prerequisite({writer: writerA, namespace: namespaceA, migration: migrationA});
        prerequisites[1] = Prerequisite({writer: writerB, namespace: namespaceB, migration: migrationB});
    }

    /// The list a write under `writer` in `namespace` onto `head` after
    /// `prerequisites` takes, which is the list `appliedAfter` answers for it:
    /// the head first, in the line, then the prerequisites.
    /// @param writer The writer the record is under.
    /// @param namespace The namespace the record is in.
    /// @param head The head it is applied onto.
    /// @param prerequisites The records it waits on.
    /// @return list The head-first list.
    function headThen(address writer, bytes32 namespace, bytes32 head, Prerequisite[] memory prerequisites)
        internal
        pure
        returns (Prerequisite[] memory list)
    {
        list = new Prerequisite[](prerequisites.length + 1);
        list[0] = Prerequisite({writer: writer, namespace: namespace, migration: head});
        for (uint256 i = 0; i < prerequisites.length; i++) {
            list[i + 1] = prerequisites[i];
        }
    }

    /// The list of a write under `writer` in `namespace` onto `head` that
    /// waits on nothing else.
    /// @param writer The writer the record is under.
    /// @param namespace The namespace the record is in.
    /// @param head The head it is applied onto.
    /// @return The one-entry list.
    function onto(address writer, bytes32 namespace, bytes32 head) internal pure returns (Prerequisite[] memory) {
        return headThen(writer, namespace, head, new Prerequisite[](0));
    }

    /// A list of record keys derived from fuzzed seeds, one key per seed.
    ///
    /// Derived by hashing rather than fuzzed directly because a fuzzed
    /// `Prerequisite[]` of any length carries a zero writer or a reserved id
    /// in some entry almost every run, and a list is only usable here if every
    /// entry is a key. The reserved values are still refused rather than
    /// mapped around, so nothing here quietly redefines what a key is.
    /// @param seeds The fuzzed seeds.
    /// @return prerequisites One key per seed, in seed order.
    function keysFromSeeds(bytes32[] memory seeds) internal pure returns (Prerequisite[] memory prerequisites) {
        prerequisites = new Prerequisite[](seeds.length);
        for (uint256 i = 0; i < seeds.length; i++) {
            prerequisites[i] = Prerequisite({
                writer: address(uint160(uint256(keccak256(abi.encode(seeds[i], "writer"))))),
                namespace: keccak256(abi.encode(seeds[i], "namespace")),
                migration: keccak256(abi.encode(seeds[i], "migration"))
            });
            vm.assume(prerequisites[i].writer != address(0));
            vm.assume(prerequisites[i].namespace != bytes32(0));
            LibMigrationFuzz.assumeMigration(vm, prerequisites[i].migration);
        }
    }

    /// Applies `migration` under `writer` in `namespace` onto wherever that
    /// line is, so a test can make a prerequisite true without caring what
    /// else the line has applied.
    /// @param writer The writer to apply under.
    /// @param namespace The namespace to apply in.
    /// @param migration The migration to apply.
    function applyUnder(address writer, bytes32 namespace, bytes32 migration) internal {
        // The head is read before the prank: the read is an external call
        // of its own and would consume the prank meant for the write.
        bytes32 head = sRegistry.head(writer, namespace);
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migration, onto(writer, namespace, head));
    }

    /// Anyone may apply, and the record lands under the caller. There is no
    /// authority to be refused by, which is the whole access-control design:
    /// the writer IS the caller.
    function testApplyMigrationAnyCallerAppliesUnderItself(address writer, bytes32 namespace, bytes32 migration)
        external
    {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migration);

        vm.prank(writer);
        sRegistry.applyMigration(namespace, migration, onto(writer, namespace, MIGRATION_HEAD_GENESIS));

        assertEq(sRegistry.applied(writer, namespace, migration), block.timestamp);
    }

    /// `applyMigration` records the block it landed in, which is the whole
    /// difference from a flag: a consumer whose invariant starts AT the
    /// migration — a cliff, a rate change, a grace period — reads the moment
    /// from the chain rather than from a constant somebody guessed.
    function testApplyMigrationStoresTheBlockTimestamp(
        address writer,
        bytes32 namespace,
        bytes32 migration,
        uint32 timestamp
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        vm.assume(timestamp != 0);
        vm.warp(timestamp);

        vm.prank(writer);
        sRegistry.applyMigration(namespace, migration, onto(writer, namespace, MIGRATION_HEAD_GENESIS));

        assertEq(sRegistry.applied(writer, namespace, migration), timestamp);
    }

    /// Two migrations applied in different blocks carry different timestamps,
    /// and the earlier one does not move when the later one lands. A record is
    /// of the moment it happened, not of the last time anything happened.
    function testApplyMigrationTimestampsAreIndependent(
        address writer,
        bytes32 namespace,
        bytes32 migrationA,
        bytes32 migrationB
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.assume(migrationA != migrationB);

        vm.warp(1000);
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationA, onto(writer, namespace, MIGRATION_HEAD_GENESIS));

        vm.warp(2000);
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationB, onto(writer, namespace, migrationA));

        assertEq(sRegistry.applied(writer, namespace, migrationA), 1000);
        assertEq(sRegistry.applied(writer, namespace, migrationB), 2000);
    }

    /// `applyMigration` refuses to write at all in a block whose timestamp is
    /// zero, rather than write a record that `applied` would read back as no
    /// record. The head does not move and the migration can still be applied,
    /// which is the only outcome that leaves the line describing something
    /// true.
    function testApplyMigrationZeroBlockReverts(address writer, bytes32 namespace, bytes32 migration) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        vm.warp(0);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroTimestamp.selector));
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migration, onto(writer, namespace, MIGRATION_HEAD_GENESIS));

        assertEq(sRegistry.applied(writer, namespace, migration), 0);
        assertEq(sRegistry.head(writer, namespace), MIGRATION_HEAD_GENESIS);

        vm.warp(1);
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migration, onto(writer, namespace, MIGRATION_HEAD_GENESIS));
        assertEq(sRegistry.applied(writer, namespace, migration), 1);
    }

    /// The zero moment is checked after the two id refusals and before anything
    /// about the line, on `applyMigration` as on `applyMigrationHistory`. An id is
    /// what a record is ABOUT, so a call with no subject has nothing to say a
    /// moment for; everything after describes a line no writable record
    /// will reach.
    function testApplyMigrationZeroBlockCheckedAfterIdsAndBeforeTheNamespace(
        address writer,
        bytes32 namespace,
        bytes32 migrationA,
        bytes32 migrationB,
        bytes32 anyHead
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.assume(migrationA != migrationB);

        vm.warp(1000);
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationA, onto(writer, namespace, MIGRATION_HEAD_GENESIS));

        vm.warp(0);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(namespace, bytes32(0), onto(writer, namespace, anyHead));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.GenesisMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(namespace, MIGRATION_HEAD_GENESIS, onto(writer, namespace, anyHead));

        // Already applied, in a block that can hold no record: told about the
        // moment, because the record could not be written whatever line it
        // arrived at.
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroTimestamp.selector));
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationA, onto(writer, namespace, MIGRATION_HEAD_GENESIS));

        // A head the line has moved on from, in the same block: told about
        // the moment.
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroTimestamp.selector));
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationB, onto(writer, namespace, MIGRATION_HEAD_GENESIS));
    }

    /// A record is confined to its writer. Applying under one
    /// writer says nothing about any other, which is what makes a reader's
    /// choice of writer the whole of who it trusts — a hostile caller can
    /// apply whatever it likes and reach nobody.
    function testApplyMigrationDoesNotReachAnotherNamespace(
        address writer,
        bytes32 namespace,
        address other,
        bytes32 migration
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        vm.assume(other != address(0));
        vm.assume(writer != other);
        LibMigrationFuzz.assumeMigration(vm, migration);

        vm.prank(writer);
        sRegistry.applyMigration(namespace, migration, onto(writer, namespace, MIGRATION_HEAD_GENESIS));

        assertEq(sRegistry.applied(writer, namespace, migration), block.timestamp);
        assertEq(sRegistry.applied(other, namespace, migration), 0);
    }

    /// Two writers may apply the same migration id independently, and each
    /// answers only for itself. Ids are opaque and writers are unrelated, so
    /// a shared id is not a collision — including for the head, which each
    /// writer advances from its own genesis.
    function testApplyMigrationSameMigrationUnderTwoWriters(
        address writer,
        bytes32 namespace,
        address other,
        bytes32 migration
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        vm.assume(other != address(0));
        vm.assume(writer != other);
        LibMigrationFuzz.assumeMigration(vm, migration);

        vm.prank(writer);
        sRegistry.applyMigration(namespace, migration, onto(writer, namespace, MIGRATION_HEAD_GENESIS));
        vm.prank(other);
        sRegistry.applyMigration(namespace, migration, onto(other, namespace, MIGRATION_HEAD_GENESIS));

        assertEq(sRegistry.applied(writer, namespace, migration), block.timestamp);
        assertEq(sRegistry.applied(other, namespace, migration), block.timestamp);
    }

    /// Migrations are independent within one line: applying one says
    /// nothing about any other. This is what a set buys over a high-water mark
    /// — a reader asks about the migration its assertion actually depends on
    /// rather than about a number that stands in for all of them.
    function testApplyMigrationDistinctMigrations(
        address writer,
        bytes32 namespace,
        bytes32 migrationA,
        bytes32 migrationB
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.assume(migrationA != migrationB);

        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationA, onto(writer, namespace, MIGRATION_HEAD_GENESIS));

        assertEq(sRegistry.applied(writer, namespace, migrationA), block.timestamp);
        assertEq(sRegistry.applied(writer, namespace, migrationB), 0);

        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationB, onto(writer, namespace, migrationA));

        assertEq(sRegistry.applied(writer, namespace, migrationA), block.timestamp);
        assertEq(sRegistry.applied(writer, namespace, migrationB), block.timestamp);
    }

    /// A successful application makes its migration the line's new head,
    /// which is what the next one has to name.
    function testApplyMigrationAdvancesTheHead(
        address writer,
        bytes32 namespace,
        bytes32 migrationA,
        bytes32 migrationB
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.assume(migrationA != migrationB);

        assertEq(sRegistry.head(writer, namespace), MIGRATION_HEAD_GENESIS);

        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationA, onto(writer, namespace, MIGRATION_HEAD_GENESIS));
        assertEq(sRegistry.head(writer, namespace), migrationA);

        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationB, onto(writer, namespace, migrationA));
        assertEq(sRegistry.head(writer, namespace), migrationB);
    }

    /// Applying onto a head the line is not at is refused. This is what
    /// blocks a SKIPPED step: a script names its predecessor, so a chain that
    /// never got that predecessor fails at the moment of applying rather than
    /// diverging silently from every chain that did.
    function testApplyMigrationSkippedPredecessorReverts(
        address writer,
        bytes32 namespace,
        bytes32 migrationA,
        bytes32 migrationB,
        bytes32 skipped
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        LibMigrationFuzz.assumeMigration(vm, skipped);
        vm.assume(migrationA != migrationB);
        vm.assume(skipped != migrationA);
        vm.assume(skipped != migrationB);

        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationA, onto(writer, namespace, MIGRATION_HEAD_GENESIS));

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.UnexpectedMigrationHead.selector, writer, namespace, skipped, migrationA
            )
        );
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationB, onto(writer, namespace, skipped));

        assertEq(sRegistry.applied(writer, namespace, migrationB), 0);
        assertEq(sRegistry.head(writer, namespace), migrationA);
    }

    /// Genesis stops being an acceptable head the moment anything is applied,
    /// so a first-migration script re-run against a line that has moved on
    /// fails rather than restarting the sequence.
    function testApplyMigrationOntoGenesisAfterFirstReverts(
        address writer,
        bytes32 namespace,
        bytes32 migrationA,
        bytes32 migrationB
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.assume(migrationA != migrationB);

        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationA, onto(writer, namespace, MIGRATION_HEAD_GENESIS));

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.UnexpectedMigrationHead.selector,
                writer,
                namespace,
                MIGRATION_HEAD_GENESIS,
                migrationA
            )
        );
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationB, onto(writer, namespace, MIGRATION_HEAD_GENESIS));
    }

    /// A head belongs to one line. One writer advancing its head leaves
    /// every other writer's exactly where it was, so a second consumer's
    /// migrations are not blocked or unblocked by the first's.
    function testApplyMigrationHeadIsPerWriter(
        address writer,
        bytes32 namespace,
        address other,
        bytes32 migrationA,
        bytes32 migrationB
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        vm.assume(other != address(0));
        vm.assume(writer != other);
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.assume(migrationA != migrationB);

        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationA, onto(writer, namespace, MIGRATION_HEAD_GENESIS));

        assertEq(sRegistry.head(other, namespace), MIGRATION_HEAD_GENESIS);

        // The other writer's line is still at genesis, so `migrationA` is not the
        // head there and naming it is refused.
        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.UnexpectedMigrationHead.selector,
                other,
                namespace,
                migrationA,
                MIGRATION_HEAD_GENESIS
            )
        );
        vm.prank(other);
        sRegistry.applyMigration(namespace, migrationB, onto(other, namespace, migrationA));

        vm.prank(other);
        sRegistry.applyMigration(namespace, migrationB, onto(other, namespace, MIGRATION_HEAD_GENESIS));
        assertEq(sRegistry.head(other, namespace), migrationB);
        assertEq(sRegistry.head(writer, namespace), migrationA);
    }

    /// A zero head never matches anything, including on a line that has
    /// applied nothing — which is the whole reason genesis is not zero. An
    /// uninitialised predecessor constant is a revert in every line state,
    /// rather than a successful first application on every chain that happens
    /// to be empty.
    function testApplyMigrationZeroHeadRevertsOnEmptyNamespace(address writer, bytes32 namespace, bytes32 migration)
        external
    {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migration);

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.UnexpectedMigrationHead.selector,
                writer,
                namespace,
                bytes32(0),
                MIGRATION_HEAD_GENESIS
            )
        );
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migration, onto(writer, namespace, bytes32(0)));

        assertEq(sRegistry.applied(writer, namespace, migration), 0);
    }

    /// And on a line that has applied something.
    function testApplyMigrationZeroHeadRevertsOnUsedNamespace(
        address writer,
        bytes32 namespace,
        bytes32 migrationA,
        bytes32 migrationB
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.assume(migrationA != migrationB);

        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationA, onto(writer, namespace, MIGRATION_HEAD_GENESIS));

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.UnexpectedMigrationHead.selector, writer, namespace, bytes32(0), migrationA
            )
        );
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationB, onto(writer, namespace, bytes32(0)));
    }

    /// Applying twice is refused, even onto the head the migration itself
    /// became. This is what makes running a migration twice fail rather than
    /// repeat.
    function testApplyMigrationTwiceReverts(address writer, bytes32 namespace, bytes32 migration) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migration);

        vm.prank(writer);
        sRegistry.applyMigration(namespace, migration, onto(writer, namespace, MIGRATION_HEAD_GENESIS));

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.MigrationAlreadyApplied.selector, writer, namespace, migration)
        );
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migration, onto(writer, namespace, migration));

        assertEq(sRegistry.applied(writer, namespace, migration), block.timestamp);
    }

    /// The head does NOT subsume the already-applied refusal. Re-applying a
    /// migration whose successor has since landed presents a head that matches
    /// perfectly, and is still refused — otherwise the head would move BACKWARDS
    /// and the original timestamp would be overwritten, which is a record
    /// un-happening.
    function testApplyMigrationAgainOnMatchingHeadReverts(
        address writer,
        bytes32 namespace,
        bytes32 migrationA,
        bytes32 migrationB
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.assume(migrationA != migrationB);

        vm.warp(1000);
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationA, onto(writer, namespace, MIGRATION_HEAD_GENESIS));
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationB, onto(writer, namespace, migrationA));

        // The line really is at `migrationB`, so the head this names is
        // correct and only the already-applied refusal can stop it.
        assertEq(sRegistry.head(writer, namespace), migrationB);
        vm.warp(2000);
        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.MigrationAlreadyApplied.selector, writer, namespace, migrationA)
        );
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationA, onto(writer, namespace, migrationB));

        assertEq(sRegistry.head(writer, namespace), migrationB);
        assertEq(sRegistry.applied(writer, namespace, migrationA), 1000);
    }

    /// The head is checked BEFORE the already-applied refusal, so a
    /// re-dispatched script — which names the same head it named the first
    /// time, long since moved on — is told where the line is. Only a
    /// re-application naming the current head reaches the already-applied
    /// refusal, which is `testApplyMigrationAgainOnMatchingHeadReverts`.
    function testApplyMigrationHeadCheckedBeforeAlreadyApplied(
        address writer,
        bytes32 namespace,
        bytes32 migrationA,
        bytes32 migrationB
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.assume(migrationA != migrationB);

        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationA, onto(writer, namespace, MIGRATION_HEAD_GENESIS));
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationB, onto(writer, namespace, migrationA));

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.UnexpectedMigrationHead.selector,
                writer,
                namespace,
                MIGRATION_HEAD_GENESIS,
                migrationB
            )
        );
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationA, onto(writer, namespace, MIGRATION_HEAD_GENESIS));
    }

    /// A migration another writer has already applied is still a FIRST record
    /// for this one. The refusal is per line, not global, or one consumer
    /// choosing a common id would lock every other consumer out of it.
    function testApplyMigrationTwiceIsPerWriter(address writer, bytes32 namespace, address other, bytes32 migration)
        external
    {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        vm.assume(other != address(0));
        vm.assume(writer != other);
        LibMigrationFuzz.assumeMigration(vm, migration);

        vm.prank(writer);
        sRegistry.applyMigration(namespace, migration, onto(writer, namespace, MIGRATION_HEAD_GENESIS));

        vm.prank(other);
        sRegistry.applyMigration(namespace, migration, onto(other, namespace, MIGRATION_HEAD_GENESIS));

        assertEq(sRegistry.applied(other, namespace, migration), block.timestamp);
    }

    /// The zero migration id is refused. It is what an uninitialised `bytes32`
    /// constant reads as, and there is deliberately no way to apply one, which
    /// is what lets `applied` refuse it as a mistake rather than have to answer
    /// about it.
    function testApplyMigrationZeroMigrationReverts(address writer, bytes32 namespace) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(namespace, bytes32(0), onto(writer, namespace, MIGRATION_HEAD_GENESIS));
    }

    /// The zero id is refused BEFORE the already-applied read and before the
    /// head, so it is always reported as `ZeroMigration` and never as anything
    /// about where the line is.
    ///
    /// Fuzzed over the head against BOTH an empty line and one that has
    /// moved on, for the same reason
    /// `testApplyMigrationGenesisMigrationRevertsOnAnyHead` is: one line
    /// state cannot tell the orderings apart, because a head the line
    /// happens to be at is accepted whichever check runs first, and the two
    /// states here have different heads so no fuzzed head matches both.
    ///
    /// The already-applied read can never answer anything but zero for this id
    /// — this refusal is what keeps the zero id out of the records in the first
    /// place — so what the second call pins is the reachable half of the same
    /// claim: the refusal is a fact about the ID, not about the state of the
    /// line it arrives at.
    function testApplyMigrationZeroMigrationCheckedFirst(
        address writer,
        bytes32 namespace,
        bytes32 anyHead,
        bytes32 migration
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migration);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(namespace, bytes32(0), onto(writer, namespace, anyHead));

        // A line that has moved on: the zero id is still reported as
        // `ZeroMigration` rather than as anything about the head or about what
        // has already been applied.
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migration, onto(writer, namespace, MIGRATION_HEAD_GENESIS));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(namespace, bytes32(0), onto(writer, namespace, anyHead));
    }

    /// Genesis is a head, not a migration, and applying it is refused. It would
    /// otherwise leave the line's head holding the exact value an empty
    /// line reads as, so a line that had applied something would be
    /// indistinguishable from one that had not — and the next first-migration
    /// script would be accepted against it.
    function testApplyMigrationGenesisMigrationReverts(address writer, bytes32 namespace) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.GenesisMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(namespace, MIGRATION_HEAD_GENESIS, onto(writer, namespace, MIGRATION_HEAD_GENESIS));

        assertEq(sRegistry.head(writer, namespace), MIGRATION_HEAD_GENESIS);
    }

    /// Refused whatever head it is applied onto, so it is a fact about the id
    /// rather than about where the line happens to be. That means a head
    /// the line is NOT at as much as one it is: the refusal is checked
    /// before the head, so a caller that has confused a head for a migration is
    /// told which of the two it got wrong rather than sent to look at where the
    /// line has got to.
    ///
    /// Fuzzed over the head for the same reason
    /// `testApplyMigrationZeroMigrationCheckedFirst` is: a matching head alone
    /// cannot tell the two orderings apart.
    function testApplyMigrationGenesisMigrationRevertsOnAnyHead(
        address writer,
        bytes32 namespace,
        bytes32 migration,
        bytes32 anyHead
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migration);

        // An empty line, whose head is genesis: still refused onto a head
        // that does not match it.
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.GenesisMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(namespace, MIGRATION_HEAD_GENESIS, onto(writer, namespace, anyHead));

        vm.prank(writer);
        sRegistry.applyMigration(namespace, migration, onto(writer, namespace, MIGRATION_HEAD_GENESIS));

        // A line that has moved: same refusal, onto the head it is at and
        // onto any other.
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.GenesisMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(namespace, MIGRATION_HEAD_GENESIS, onto(writer, namespace, migration));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.GenesisMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(namespace, MIGRATION_HEAD_GENESIS, onto(writer, namespace, anyHead));

        assertEq(sRegistry.head(writer, namespace), migration);
    }

    /// Ids are opaque: nothing about a migration's bytes changes how it is
    /// stored or read, including ids no hashing convention would produce.
    function testApplyMigrationOpaqueMigrationIds(address writer, bytes32 namespace) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));

        bytes32[2] memory migrations = [bytes32(uint256(1)), bytes32(type(uint256).max)];
        for (uint256 i = 0; i < migrations.length; i++) {
            MigrationRegistry registry = new MigrationRegistry();
            vm.prank(writer);
            registry.applyMigration(namespace, migrations[i], onto(writer, namespace, MIGRATION_HEAD_GENESIS));
            assertEq(registry.applied(writer, namespace, migrations[i]), block.timestamp);
            assertEq(registry.head(writer, namespace), migrations[i]);
        }
    }

    /// `Migrated` is emitted with the writer and migration both indexed, so the
    /// log can be filtered by either, and carries the moment as data. The log is
    /// the only enumeration of the registry, so a record that does not emit is a
    /// record nobody can find.
    ///
    /// It carries no head because the log already holds it: one writer's entries
    /// in order ARE its chain of heads. It does carry the moment, which the
    /// block a log entry sits in does not — that block says when the record was
    /// written, and the moment says when the migration ran.
    function testApplyMigrationHistoryEvent(
        address writer,
        bytes32 namespace,
        bytes32 migration,
        uint32 appliedAt,
        uint32 writtenAt
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        vm.assume(appliedAt != 0);
        vm.assume(writtenAt > appliedAt);
        vm.warp(writtenAt);

        vm.recordLogs();
        vm.prank(writer);
        sRegistry.applyMigrationHistory(
            namespace, migration, appliedAt, onto(writer, namespace, MIGRATION_HEAD_GENESIS)
        );
        Vm.Log[] memory entries = vm.getRecordedLogs();

        assertEq(entries.length, 1);
        assertEq(entries[0].emitter, address(sRegistry));
        assertEq(entries[0].topics.length, 4);
        assertEq(entries[0].topics[0], keccak256("Migrated(address,bytes32,bytes32,uint256)"));
        assertEq(entries[0].topics[1], bytes32(uint256(uint160(writer))));
        assertEq(entries[0].topics[2], namespace);
        assertEq(entries[0].topics[3], migration);
        assertEq(entries[0].data, abi.encode(uint256(appliedAt)));
    }

    /// `applyMigration` emits the same event, carrying the block it stamped — so
    /// a reader of the log never has to know which of the two wrote a record.
    function testApplyMigrationEvent(address writer, bytes32 namespace, bytes32 migration, uint32 now_) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        vm.assume(now_ != 0);
        vm.warp(now_);

        vm.recordLogs();
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migration, onto(writer, namespace, MIGRATION_HEAD_GENESIS));
        Vm.Log[] memory entries = vm.getRecordedLogs();

        assertEq(entries.length, 1);
        assertEq(entries[0].topics[0], keccak256("Migrated(address,bytes32,bytes32,uint256)"));
        assertEq(entries[0].data, abi.encode(uint256(now_)));
    }

    /// A refused write emits nothing, so a failed apply can never be
    /// mistaken for a record by anything reading the logs — which for a
    /// re-dispatched migration is exactly the mistake that matters.
    function testApplyMigrationNoEventOnRevert(address writer, bytes32 namespace, bytes32 migration) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        vm.warp(1000);

        vm.prank(writer);
        sRegistry.applyMigration(namespace, migration, onto(writer, namespace, MIGRATION_HEAD_GENESIS));

        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.MigrationAlreadyApplied.selector, writer, namespace, migration)
        );
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migration, onto(writer, namespace, migration));
        assertEq(vm.getRecordedLogs().length, 0);

        vm.recordLogs();
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(namespace, bytes32(0), onto(writer, namespace, migration));
        assertEq(vm.getRecordedLogs().length, 0);

        vm.recordLogs();
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.GenesisMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(namespace, MIGRATION_HEAD_GENESIS, onto(writer, namespace, migration));
        assertEq(vm.getRecordedLogs().length, 0);

        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.UnexpectedMigrationHead.selector,
                writer,
                namespace,
                MIGRATION_HEAD_GENESIS,
                migration
            )
        );
        vm.prank(writer);
        sRegistry.applyMigration(
            namespace, keccak256(abi.encode(migration)), onto(writer, namespace, MIGRATION_HEAD_GENESIS)
        );
        assertEq(vm.getRecordedLogs().length, 0);

        vm.recordLogs();
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroTimestamp.selector));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(
            namespace, keccak256(abi.encode(migration)), 0, onto(writer, namespace, migration)
        );
        assertEq(vm.getRecordedLogs().length, 0);

        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.FutureTimestamp.selector, block.timestamp + 1, block.timestamp)
        );
        vm.prank(writer);
        sRegistry.applyMigrationHistory(
            namespace, keccak256(abi.encode(migration)), block.timestamp + 1, onto(writer, namespace, migration)
        );
        assertEq(vm.getRecordedLogs().length, 0);

        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.TimestampBeforeHead.selector, block.timestamp - 1, 1000)
        );
        vm.prank(writer);
        sRegistry.applyMigrationHistory(
            namespace, keccak256(abi.encode(migration)), block.timestamp - 1, onto(writer, namespace, migration)
        );
        assertEq(vm.getRecordedLogs().length, 0);
    }

    /// `applyMigrationHistory` records the moment the CALLER supplied, which is
    /// what lets a migration that already ran be recorded with the time it ran
    /// rather than the time it was written down. The block the record lands in
    /// is not the value, and a record written long after the fact says so.
    function testApplyMigrationHistoryRecordsTheSuppliedMoment(
        address writer,
        bytes32 namespace,
        bytes32 migration,
        uint32 appliedAt,
        uint32 writtenAt
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        vm.assume(appliedAt != 0);
        vm.assume(writtenAt > appliedAt);
        vm.warp(writtenAt);

        vm.prank(writer);
        sRegistry.applyMigrationHistory(
            namespace, migration, appliedAt, onto(writer, namespace, MIGRATION_HEAD_GENESIS)
        );

        assertEq(sRegistry.applied(writer, namespace, migration), appliedAt);
        assertTrue(sRegistry.applied(writer, namespace, migration) != block.timestamp);
    }

    /// The moment of the current block is an ordinary value for the parameter,
    /// which is what a caller reaching for `applyMigrationHistory` to record a
    /// migration running now passes.
    function testApplyMigrationHistoryCurrentBlockIsAccepted(
        address writer,
        bytes32 namespace,
        bytes32 migration,
        uint32 now_
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        vm.assume(now_ != 0);
        vm.warp(now_);

        vm.prank(writer);
        sRegistry.applyMigrationHistory(
            namespace, migration, block.timestamp, onto(writer, namespace, MIGRATION_HEAD_GENESIS)
        );

        assertEq(sRegistry.applied(writer, namespace, migration), now_);
    }

    /// The two writes make the SAME record when the moment is this block, down
    /// to the head each was applied onto — which is what makes `applyMigration`
    /// `applyMigrationHistory` with today's moment rather than a second way to
    /// write a record.
    function testApplyMigrationAndHistoryWriteTheSameRecord(
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

        MigrationRegistry stamping = new MigrationRegistry();
        MigrationRegistry supplied = new MigrationRegistry();

        vm.prank(writer);
        stamping.applyMigration(namespace, migrationA, onto(writer, namespace, MIGRATION_HEAD_GENESIS));
        vm.prank(writer);
        supplied.applyMigrationHistory(
            namespace, migrationA, block.timestamp, onto(writer, namespace, MIGRATION_HEAD_GENESIS)
        );

        vm.prank(writer);
        stamping.applyMigration(namespace, migrationB, onto(writer, namespace, migrationA));
        vm.prank(writer);
        supplied.applyMigrationHistory(namespace, migrationB, block.timestamp, onto(writer, namespace, migrationA));

        assertEq(stamping.applied(writer, namespace, migrationB), supplied.applied(writer, namespace, migrationB));
        assertEq(
            stamping.appliedOnto(writer, namespace, migrationB), supplied.appliedOnto(writer, namespace, migrationB)
        );
        assertEq(stamping.head(writer, namespace), supplied.head(writer, namespace));
    }

    /// A moment that has not arrived is refused. A record says a migration HAS
    /// run, so a future one is not a late record of anything, and a consumer
    /// measuring an interval since the migration would be subtracting a moment
    /// later than the one it is measuring from.
    function testApplyMigrationHistoryFutureTimestampReverts(
        address writer,
        bytes32 namespace,
        bytes32 migration,
        uint32 now_,
        uint256 appliedAt
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        vm.warp(now_);
        appliedAt = bound(appliedAt, uint256(now_) + 1, type(uint256).max);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.FutureTimestamp.selector, appliedAt, uint256(now_)));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(
            namespace, migration, appliedAt, onto(writer, namespace, MIGRATION_HEAD_GENESIS)
        );

        assertEq(sRegistry.applied(writer, namespace, migration), 0);
        assertEq(sRegistry.appliedOnto(writer, namespace, migration), bytes32(0));
        assertEq(sRegistry.head(writer, namespace), MIGRATION_HEAD_GENESIS);
    }

    /// One second past the current block is refused, and the current block is
    /// not: the boundary is the block's own timestamp, inclusive.
    function testApplyMigrationHistoryFutureBoundary(address writer, bytes32 namespace, bytes32 migration, uint32 now_)
        external
    {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        vm.assume(now_ != 0);
        vm.warp(now_);

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.FutureTimestamp.selector, uint256(now_) + 1, uint256(now_))
        );
        vm.prank(writer);
        sRegistry.applyMigrationHistory(
            namespace, migration, uint256(now_) + 1, onto(writer, namespace, MIGRATION_HEAD_GENESIS)
        );

        vm.prank(writer);
        sRegistry.applyMigrationHistory(
            namespace, migration, uint256(now_), onto(writer, namespace, MIGRATION_HEAD_GENESIS)
        );
        assertEq(sRegistry.applied(writer, namespace, migration), now_);
    }

    /// A supplied zero is refused, rather than written as a record that
    /// `applied` would read back as no record. The head does not move and the
    /// migration can still be applied.
    function testApplyMigrationHistoryZeroTimestampReverts(
        address writer,
        bytes32 namespace,
        bytes32 migration,
        uint32 now_
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        vm.assume(now_ != 0);
        vm.warp(now_);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroTimestamp.selector));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(namespace, migration, 0, onto(writer, namespace, MIGRATION_HEAD_GENESIS));

        assertEq(sRegistry.applied(writer, namespace, migration), 0);
        assertEq(sRegistry.head(writer, namespace), MIGRATION_HEAD_GENESIS);

        vm.prank(writer);
        sRegistry.applyMigrationHistory(namespace, migration, 1, onto(writer, namespace, MIGRATION_HEAD_GENESIS));
        assertEq(sRegistry.applied(writer, namespace, migration), 1);
    }

    /// A block whose timestamp is zero can hold no record at all: zero is
    /// refused as a moment, and every other moment is still in the future. The
    /// head does not move, so the line goes on describing something true
    /// and the migration is still applicable once the clock has moved.
    function testApplyMigrationHistoryZeroBlockRecordsNothing(
        address writer,
        bytes32 namespace,
        bytes32 migration,
        uint256 appliedAt
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        vm.assume(appliedAt != 0);
        vm.warp(0);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroTimestamp.selector));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(namespace, migration, 0, onto(writer, namespace, MIGRATION_HEAD_GENESIS));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.FutureTimestamp.selector, appliedAt, 0));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(
            namespace, migration, appliedAt, onto(writer, namespace, MIGRATION_HEAD_GENESIS)
        );

        assertEq(sRegistry.applied(writer, namespace, migration), 0);
        assertEq(sRegistry.head(writer, namespace), MIGRATION_HEAD_GENESIS);

        vm.warp(1);
        vm.prank(writer);
        sRegistry.applyMigrationHistory(namespace, migration, 1, onto(writer, namespace, MIGRATION_HEAD_GENESIS));
        assertEq(sRegistry.applied(writer, namespace, migration), 1);
    }

    /// The zero moment is refused BEFORE anything about the line is read,
    /// so an uninitialised argument is reported as itself rather than as
    /// whatever the line happens to make of it. Fuzzed over the head and
    /// checked against a line that has moved on, because a head the
    /// line happens to be at is accepted whichever check runs first.
    function testApplyMigrationHistoryZeroTimestampCheckedBeforeTheNamespace(
        address writer,
        bytes32 namespace,
        bytes32 migrationA,
        bytes32 migrationB,
        bytes32 anyHead
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.assume(migrationA != migrationB);

        vm.prank(writer);
        sRegistry.applyMigrationHistory(
            namespace, migrationA, block.timestamp, onto(writer, namespace, MIGRATION_HEAD_GENESIS)
        );

        // Already applied, and a zero moment: told about the moment.
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroTimestamp.selector));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(namespace, migrationA, 0, onto(writer, namespace, MIGRATION_HEAD_GENESIS));

        // A head that has moved on, and a zero moment: told about the moment.
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroTimestamp.selector));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(namespace, migrationB, 0, onto(writer, namespace, anyHead));
    }

    /// The two id refusals come before the moment, so a caller that has zeroed
    /// both an id and a moment is told about the id: an id is what the record is
    /// ABOUT, and a call with no subject has nothing to say a moment for.
    function testApplyMigrationHistoryIdCheckedBeforeTimestamp(address writer, bytes32 namespace, bytes32 anyHead)
        external
    {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(namespace, bytes32(0), 0, onto(writer, namespace, anyHead));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.GenesisMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(namespace, MIGRATION_HEAD_GENESIS, 0, onto(writer, namespace, anyHead));
    }

    /// The refusals that describe the NAMESPACE come before the future-moment
    /// one, so a re-dispatched script is told its migration already ran, and a
    /// script at the wrong point in the sequence is told where the line is,
    /// rather than either of them being sent to look at a clock.
    function testApplyMigrationHistoryNamespaceCheckedBeforeTheFuture(
        address writer,
        bytes32 namespace,
        bytes32 migrationA,
        bytes32 migrationB,
        bytes32 skipped
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        LibMigrationFuzz.assumeMigration(vm, skipped);
        vm.assume(migrationA != migrationB);
        vm.assume(skipped != migrationA);
        vm.assume(skipped != migrationB);

        vm.warp(9000);
        vm.prank(writer);
        sRegistry.applyMigrationHistory(namespace, migrationA, 5000, onto(writer, namespace, MIGRATION_HEAD_GENESIS));

        // Already applied, and in the future: told it already ran.
        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.MigrationAlreadyApplied.selector, writer, namespace, migrationA)
        );
        vm.prank(writer);
        sRegistry.applyMigrationHistory(namespace, migrationA, 9001, onto(writer, namespace, migrationA));

        // The wrong head, and in the future: told where the line is.
        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.UnexpectedMigrationHead.selector, writer, namespace, skipped, migrationA
            )
        );
        vm.prank(writer);
        sRegistry.applyMigrationHistory(namespace, migrationB, 9001, onto(writer, namespace, skipped));
    }

    /// A record may NOT carry a moment earlier than the record it is applied
    /// onto. Nothing is written and the head does not move, so the migration is
    /// still applicable with a moment the chain admits.
    function testApplyMigrationHistoryMomentBeforeHeadReverts(
        address writer,
        bytes32 namespace,
        bytes32 migrationA,
        bytes32 migrationB,
        uint32 now_,
        uint256 earlier
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.assume(migrationA != migrationB);
        vm.assume(now_ > 1);
        vm.warp(now_);
        earlier = bound(earlier, 1, uint256(now_) - 1);

        vm.prank(writer);
        sRegistry.applyMigrationHistory(
            namespace, migrationA, uint256(now_), onto(writer, namespace, MIGRATION_HEAD_GENESIS)
        );

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.TimestampBeforeHead.selector, earlier, uint256(now_))
        );
        vm.prank(writer);
        sRegistry.applyMigrationHistory(namespace, migrationB, earlier, onto(writer, namespace, migrationA));

        assertEq(sRegistry.applied(writer, namespace, migrationB), 0);
        assertEq(sRegistry.appliedOnto(writer, namespace, migrationB), bytes32(0));
        assertEq(sRegistry.head(writer, namespace), migrationA);

        vm.prank(writer);
        sRegistry.applyMigrationHistory(namespace, migrationB, uint256(now_), onto(writer, namespace, migrationA));
        assertEq(sRegistry.applied(writer, namespace, migrationB), uint256(now_));
        assertEq(sRegistry.head(writer, namespace), migrationB);
    }

    /// The boundary is the head's own moment, inclusive: exactly it is
    /// accepted, and one second below it is refused.
    function testApplyMigrationHistoryBeforeHeadBoundary(
        address writer,
        bytes32 namespace,
        bytes32 migrationA,
        bytes32 migrationB,
        uint32 headAppliedAt
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.assume(migrationA != migrationB);
        vm.assume(headAppliedAt > 1);
        vm.warp(headAppliedAt);

        vm.prank(writer);
        sRegistry.applyMigrationHistory(
            namespace, migrationA, uint256(headAppliedAt), onto(writer, namespace, MIGRATION_HEAD_GENESIS)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.TimestampBeforeHead.selector, uint256(headAppliedAt) - 1, uint256(headAppliedAt)
            )
        );
        vm.prank(writer);
        sRegistry.applyMigrationHistory(
            namespace, migrationB, uint256(headAppliedAt) - 1, onto(writer, namespace, migrationA)
        );

        vm.prank(writer);
        sRegistry.applyMigrationHistory(
            namespace, migrationB, uint256(headAppliedAt), onto(writer, namespace, migrationA)
        );
        assertEq(sRegistry.applied(writer, namespace, migrationB), uint256(headAppliedAt));
    }

    /// A moment AFTER the head's is the ordinary case, and it is the moment the
    /// record carries rather than anything derived from the one before it.
    function testApplyMigrationHistoryMomentAfterHeadIsAccepted(
        address writer,
        bytes32 namespace,
        bytes32 migrationA,
        bytes32 migrationB,
        uint32 first,
        uint32 second
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.assume(migrationA != migrationB);
        vm.assume(first != 0);
        vm.assume(second > first);
        vm.warp(second);

        vm.prank(writer);
        sRegistry.applyMigrationHistory(
            namespace, migrationA, uint256(first), onto(writer, namespace, MIGRATION_HEAD_GENESIS)
        );
        vm.prank(writer);
        sRegistry.applyMigrationHistory(namespace, migrationB, uint256(second), onto(writer, namespace, migrationA));

        assertEq(sRegistry.applied(writer, namespace, migrationA), uint256(first));
        assertEq(sRegistry.applied(writer, namespace, migrationB), uint256(second));
        assertEq(sRegistry.head(writer, namespace), migrationB);
    }

    /// The first migration in a line is compared to nothing. It is applied
    /// onto `MIGRATION_HEAD_GENESIS`, which is refused as a migration and so
    /// holds no record in any line ever — which is why the smallest moment
    /// a record may carry is accepted at genesis in the latest block.
    function testApplyMigrationHistoryNoMomentBoundAtGenesis(
        address writer,
        bytes32 namespace,
        bytes32 migration,
        uint32 now_
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        vm.assume(now_ != 0);
        vm.warp(now_);

        // Nothing can put a record at genesis to be bounded by.
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.GenesisMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(
            namespace, MIGRATION_HEAD_GENESIS, uint256(now_), onto(writer, namespace, MIGRATION_HEAD_GENESIS)
        );

        vm.prank(writer);
        sRegistry.applyMigrationHistory(namespace, migration, 1, onto(writer, namespace, MIGRATION_HEAD_GENESIS));

        assertEq(sRegistry.applied(writer, namespace, migration), 1);
        assertEq(sRegistry.appliedOnto(writer, namespace, migration), MIGRATION_HEAD_GENESIS);
    }

    /// The refusals that read the line's KEYS come before the one that
    /// reads its RECORD, so a re-dispatched script is told its migration already
    /// ran and a script at the wrong point is told where the line is,
    /// rather than either being told about the moment of a record it was never
    /// going to be chained onto. The zero moment still comes before all of them.
    function testApplyMigrationHistoryNamespaceCheckedBeforeTheHeadsMoment(
        address writer,
        bytes32 namespace,
        bytes32 migrationA,
        bytes32 migrationB,
        bytes32 skipped
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        LibMigrationFuzz.assumeMigration(vm, skipped);
        vm.assume(migrationA != migrationB);
        vm.assume(skipped != migrationA);
        vm.assume(skipped != migrationB);

        vm.warp(9000);
        vm.prank(writer);
        sRegistry.applyMigrationHistory(namespace, migrationA, 9000, onto(writer, namespace, MIGRATION_HEAD_GENESIS));

        // Already applied, and before the head's moment: told it already ran.
        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.MigrationAlreadyApplied.selector, writer, namespace, migrationA)
        );
        vm.prank(writer);
        sRegistry.applyMigrationHistory(namespace, migrationA, 1, onto(writer, namespace, migrationA));

        // The wrong head, and before the head's moment: told where the
        // line is.
        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.UnexpectedMigrationHead.selector, writer, namespace, skipped, migrationA
            )
        );
        vm.prank(writer);
        sRegistry.applyMigrationHistory(namespace, migrationB, 1, onto(writer, namespace, skipped));

        // A zero moment, which is also before the head's: told about the zero.
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroTimestamp.selector));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(namespace, migrationB, 0, onto(writer, namespace, migrationA));

        // With nothing else wrong, the head's moment is what refuses it.
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.TimestampBeforeHead.selector, 1, 9000));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(namespace, migrationB, 1, onto(writer, namespace, migrationA));
    }

    /// A head's moment bounds only its own line. Another writer at genesis
    /// is bounded by nothing, whatever moment the first line recorded.
    function testApplyMigrationHistoryHeadMomentIsPerWriter(
        address writer,
        bytes32 namespace,
        address other,
        bytes32 migrationA,
        bytes32 migrationB
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        vm.assume(other != address(0));
        vm.assume(writer != other);
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.assume(migrationA != migrationB);

        vm.warp(9000);
        vm.prank(writer);
        sRegistry.applyMigrationHistory(namespace, migrationA, 9000, onto(writer, namespace, MIGRATION_HEAD_GENESIS));

        vm.prank(other);
        sRegistry.applyMigrationHistory(namespace, migrationB, 1, onto(other, namespace, MIGRATION_HEAD_GENESIS));

        assertEq(sRegistry.applied(other, namespace, migrationB), 1);

        // And the other line's own head bounds it from there.
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.TimestampBeforeHead.selector, 1, 9000));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(namespace, migrationB, 1, onto(writer, namespace, migrationA));
    }

    /// Two records may carry the SAME moment. Two migrations applied in one
    /// transaction share a block, and two backfilled migrations known only to
    /// the same day share a moment; the chain is what orders them, so the
    /// moments are not asked to.
    function testApplyMigrationHistoryMomentsMayBeEqual(
        address writer,
        bytes32 namespace,
        bytes32 migrationA,
        bytes32 migrationB,
        uint32 appliedAt
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.assume(migrationA != migrationB);
        vm.assume(appliedAt != 0);
        vm.warp(appliedAt);

        vm.prank(writer);
        sRegistry.applyMigrationHistory(
            namespace, migrationA, appliedAt, onto(writer, namespace, MIGRATION_HEAD_GENESIS)
        );
        vm.prank(writer);
        sRegistry.applyMigrationHistory(namespace, migrationB, appliedAt, onto(writer, namespace, migrationA));

        assertEq(sRegistry.applied(writer, namespace, migrationA), appliedAt);
        assertEq(sRegistry.applied(writer, namespace, migrationB), appliedAt);
    }

    /// A record keeps the head it was applied onto, which is what makes the
    /// order structural. The first record in a line holds
    /// `MIGRATION_HEAD_GENESIS`, and each later one holds the migration before
    /// it — the value the caller named and the registry checked, not one the
    /// caller could have chosen freely.
    function testApplyMigrationRecordsTheHeadItWasAppliedOnto(
        address writer,
        bytes32 namespace,
        bytes32 migrationA,
        bytes32 migrationB
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.assume(migrationA != migrationB);

        assertEq(sRegistry.appliedOnto(writer, namespace, migrationA), bytes32(0));

        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationA, onto(writer, namespace, MIGRATION_HEAD_GENESIS));
        assertEq(sRegistry.appliedOnto(writer, namespace, migrationA), MIGRATION_HEAD_GENESIS);

        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationB, onto(writer, namespace, migrationA));
        assertEq(sRegistry.appliedOnto(writer, namespace, migrationB), migrationA);
        assertEq(sRegistry.appliedOnto(writer, namespace, migrationA), MIGRATION_HEAD_GENESIS);
    }

    /// The chain is the order the migrations ran in, and it says so where the
    /// moments cannot. Three records carrying one moment walk back from the head
    /// in the order they were APPLIED, ending at genesis.
    function testApplyMigrationHistoryChainIsTheOrderWhateverTheMoments(
        address writer,
        bytes32 namespace,
        bytes32 migrationA,
        bytes32 migrationB,
        bytes32 migrationC
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        LibMigrationFuzz.assumeMigration(vm, migrationC);
        vm.assume(migrationA != migrationB);
        vm.assume(migrationB != migrationC);
        vm.assume(migrationA != migrationC);

        vm.warp(9000);
        vm.prank(writer);
        sRegistry.applyMigrationHistory(namespace, migrationA, 3000, onto(writer, namespace, MIGRATION_HEAD_GENESIS));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(namespace, migrationB, 3000, onto(writer, namespace, migrationA));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(namespace, migrationC, 3000, onto(writer, namespace, migrationB));

        // Every moment is the same as the one before it, so nothing about the
        // order can be read out of them.
        assertEq(sRegistry.applied(writer, namespace, migrationA), 3000);
        assertEq(sRegistry.applied(writer, namespace, migrationB), 3000);
        assertEq(sRegistry.applied(writer, namespace, migrationC), 3000);

        // The chain still says exactly what happened.
        bytes32 cursor = sRegistry.head(writer, namespace);
        assertEq(cursor, migrationC);
        cursor = sRegistry.appliedOnto(writer, namespace, cursor);
        assertEq(cursor, migrationB);
        cursor = sRegistry.appliedOnto(writer, namespace, cursor);
        assertEq(cursor, migrationA);
        cursor = sRegistry.appliedOnto(writer, namespace, cursor);
        assertEq(cursor, MIGRATION_HEAD_GENESIS);
    }

    /// A chain belongs to one line. Another writer applying the same
    /// migrations builds its own chain, and neither reaches the other.
    function testApplyMigrationChainIsPerWriter(
        address writer,
        bytes32 namespace,
        address other,
        bytes32 migrationA,
        bytes32 migrationB
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        vm.assume(other != address(0));
        vm.assume(writer != other);
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.assume(migrationA != migrationB);

        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationA, onto(writer, namespace, MIGRATION_HEAD_GENESIS));
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationB, onto(writer, namespace, migrationA));

        // The other writer applies them in the opposite order, so a chain
        // that leaked would be visibly the first one's.
        vm.prank(other);
        sRegistry.applyMigration(namespace, migrationB, onto(other, namespace, MIGRATION_HEAD_GENESIS));
        vm.prank(other);
        sRegistry.applyMigration(namespace, migrationA, onto(other, namespace, migrationB));

        assertEq(sRegistry.appliedOnto(writer, namespace, migrationA), MIGRATION_HEAD_GENESIS);
        assertEq(sRegistry.appliedOnto(writer, namespace, migrationB), migrationA);
        assertEq(sRegistry.appliedOnto(other, namespace, migrationB), MIGRATION_HEAD_GENESIS);
        assertEq(sRegistry.appliedOnto(other, namespace, migrationA), migrationB);
    }

    /// The zero namespace is refused on the write's own argument. It is what
    /// an uninitialised constant reads as, so a write into it would put a
    /// record where no reader that set its constant will look. Nothing is
    /// recorded and nothing is logged.
    function testApplyMigrationZeroNamespaceReverts(address writer, bytes32 migration) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeMigration(vm, migration);

        vm.recordLogs();
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroNamespace.selector));
        vm.prank(writer);
        sRegistry.applyMigration(bytes32(0), migration, onto(writer, bytes32(0), MIGRATION_HEAD_GENESIS));
        assertEq(vm.getRecordedLogs().length, 0);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroNamespace.selector));
        sRegistry.applied(writer, bytes32(0), migration);
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroNamespace.selector));
        sRegistry.head(writer, bytes32(0));
    }

    /// And on `applyMigrationHistory`, whatever moment it supplies.
    function testApplyMigrationHistoryZeroNamespaceReverts(address writer, bytes32 migration, uint32 appliedAt)
        external
    {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        vm.assume(appliedAt != 0);
        vm.warp(appliedAt);

        vm.recordLogs();
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroNamespace.selector));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(
            bytes32(0), migration, appliedAt, onto(writer, bytes32(0), MIGRATION_HEAD_GENESIS)
        );
        assertEq(vm.getRecordedLogs().length, 0);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroNamespace.selector));
        sRegistry.applied(writer, bytes32(0), migration);
    }

    /// The zero namespace is the first argument and the first refusal: it
    /// wins over the zero id, over genesis as the id, over a zero moment and
    /// over an empty list, so a caller that has zeroed everything is told
    /// about the namespace.
    function testApplyMigrationZeroNamespaceCheckedFirst(address writer, bytes32 migration, bytes32 anyHead) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeMigration(vm, migration);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroNamespace.selector));
        vm.prank(writer);
        sRegistry.applyMigration(bytes32(0), bytes32(0), onto(writer, bytes32(0), anyHead));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroNamespace.selector));
        vm.prank(writer);
        sRegistry.applyMigration(bytes32(0), MIGRATION_HEAD_GENESIS, onto(writer, bytes32(0), anyHead));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroNamespace.selector));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(bytes32(0), migration, 0, onto(writer, bytes32(0), anyHead));

        vm.warp(0);
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroNamespace.selector));
        vm.prank(writer);
        sRegistry.applyMigration(bytes32(0), migration, onto(writer, bytes32(0), anyHead));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroNamespace.selector));
        vm.prank(writer);
        sRegistry.applyMigration(bytes32(0), migration, new Prerequisite[](0));
    }

    /// A head belongs to one line, and one writer keeps one line per
    /// namespace. Advancing one of its lines leaves the other at genesis, the
    /// other line's head is not a head here, and each line advances onto its
    /// own head independently of where the other has got to.
    function testApplyMigrationHeadIsPerNamespace(
        address writer,
        bytes32 namespace,
        bytes32 otherNamespace,
        bytes32 migrationA,
        bytes32 migrationB
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        vm.assume(otherNamespace != bytes32(0));
        vm.assume(namespace != otherNamespace);
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.assume(migrationA != migrationB);

        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationA, onto(writer, namespace, MIGRATION_HEAD_GENESIS));
        assertEq(sRegistry.head(writer, namespace), migrationA);
        assertEq(sRegistry.head(writer, otherNamespace), MIGRATION_HEAD_GENESIS);

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.UnexpectedMigrationHead.selector,
                writer,
                otherNamespace,
                migrationA,
                MIGRATION_HEAD_GENESIS
            )
        );
        vm.prank(writer);
        sRegistry.applyMigration(otherNamespace, migrationB, onto(writer, otherNamespace, migrationA));

        vm.prank(writer);
        sRegistry.applyMigration(otherNamespace, migrationB, onto(writer, otherNamespace, MIGRATION_HEAD_GENESIS));
        assertEq(sRegistry.head(writer, otherNamespace), migrationB);
        assertEq(sRegistry.head(writer, namespace), migrationA);

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.UnexpectedMigrationHead.selector, writer, namespace, migrationB, migrationA
            )
        );
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationB, onto(writer, namespace, migrationB));

        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationB, onto(writer, namespace, migrationA));
        vm.prank(writer);
        sRegistry.applyMigration(otherNamespace, migrationA, onto(writer, otherNamespace, migrationB));
        assertEq(sRegistry.head(writer, namespace), migrationB);
        assertEq(sRegistry.head(writer, otherNamespace), migrationA);
    }

    /// One writer may apply the same migration id in two namespaces, and each
    /// line answers for itself: its own moment, its own head.
    function testApplyMigrationSameMigrationUnderTwoNamespaces(
        address writer,
        bytes32 namespace,
        bytes32 otherNamespace,
        bytes32 migration,
        uint32 first,
        uint32 second
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        vm.assume(otherNamespace != bytes32(0));
        vm.assume(namespace != otherNamespace);
        LibMigrationFuzz.assumeMigration(vm, migration);
        vm.assume(first != 0);
        vm.assume(second != 0);
        vm.assume(first != second);
        vm.warp(type(uint32).max);

        vm.prank(writer);
        sRegistry.applyMigrationHistory(namespace, migration, first, onto(writer, namespace, MIGRATION_HEAD_GENESIS));
        assertEq(sRegistry.applied(writer, namespace, migration), first);
        assertEq(sRegistry.applied(writer, otherNamespace, migration), 0);
        assertEq(sRegistry.head(writer, otherNamespace), MIGRATION_HEAD_GENESIS);

        vm.prank(writer);
        sRegistry.applyMigrationHistory(
            otherNamespace, migration, second, onto(writer, otherNamespace, MIGRATION_HEAD_GENESIS)
        );
        assertEq(sRegistry.applied(writer, namespace, migration), first);
        assertEq(sRegistry.applied(writer, otherNamespace, migration), second);
        assertEq(sRegistry.head(writer, namespace), migration);
        assertEq(sRegistry.head(writer, otherNamespace), migration);
    }

    /// The already-applied refusal names the line, and it is per line: a
    /// migration applied in one namespace is still a first record in another
    /// under the same writer.
    function testApplyMigrationTwiceIsPerNamespace(
        address writer,
        bytes32 namespace,
        bytes32 otherNamespace,
        bytes32 migration
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        vm.assume(otherNamespace != bytes32(0));
        vm.assume(namespace != otherNamespace);
        LibMigrationFuzz.assumeMigration(vm, migration);

        vm.prank(writer);
        sRegistry.applyMigration(namespace, migration, onto(writer, namespace, MIGRATION_HEAD_GENESIS));

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.MigrationAlreadyApplied.selector, writer, namespace, migration)
        );
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migration, onto(writer, namespace, migration));

        vm.prank(writer);
        sRegistry.applyMigration(otherNamespace, migration, onto(writer, otherNamespace, MIGRATION_HEAD_GENESIS));
        assertEq(sRegistry.applied(writer, otherNamespace, migration), block.timestamp);

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.MigrationAlreadyApplied.selector, writer, otherNamespace, migration
            )
        );
        vm.prank(writer);
        sRegistry.applyMigration(otherNamespace, migration, onto(writer, otherNamespace, migration));
    }

    /// The first entry must name the namespace the write names. The caller in
    /// another of its own namespaces, even at exactly that line's head, is
    /// not this line's head, and the refusal names the line being written
    /// with the head it is actually at. Nothing lands in either line.
    function testApplyMigrationFirstEntryInAnotherNamespaceReverts(
        address writer,
        bytes32 namespace,
        bytes32 otherNamespace,
        bytes32 migrationA,
        bytes32 migrationB
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        vm.assume(otherNamespace != bytes32(0));
        vm.assume(namespace != otherNamespace);
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.assume(migrationA != migrationB);

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.UnexpectedMigrationHead.selector,
                writer,
                namespace,
                MIGRATION_HEAD_GENESIS,
                MIGRATION_HEAD_GENESIS
            )
        );
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationA, onto(writer, otherNamespace, MIGRATION_HEAD_GENESIS));

        assertEq(sRegistry.applied(writer, namespace, migrationA), 0);
        assertEq(sRegistry.applied(writer, otherNamespace, migrationA), 0);
        assertEq(sRegistry.head(writer, namespace), MIGRATION_HEAD_GENESIS);
        assertEq(sRegistry.head(writer, otherNamespace), MIGRATION_HEAD_GENESIS);

        vm.prank(writer);
        sRegistry.applyMigration(otherNamespace, migrationB, onto(writer, otherNamespace, MIGRATION_HEAD_GENESIS));

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.UnexpectedMigrationHead.selector,
                writer,
                namespace,
                migrationB,
                MIGRATION_HEAD_GENESIS
            )
        );
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationA, onto(writer, otherNamespace, migrationB));

        assertEq(sRegistry.applied(writer, namespace, migrationA), 0);
        assertEq(sRegistry.applied(writer, otherNamespace, migrationA), 0);
        assertEq(sRegistry.head(writer, namespace), MIGRATION_HEAD_GENESIS);
        assertEq(sRegistry.head(writer, otherNamespace), migrationB);
    }

    /// A head's moment bounds only its own line. The same writer at genesis
    /// in another namespace is bounded by nothing, whatever moment its first
    /// line recorded.
    function testApplyMigrationHistoryHeadMomentIsPerNamespace(
        address writer,
        bytes32 namespace,
        bytes32 otherNamespace,
        bytes32 migrationA,
        bytes32 migrationB
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        vm.assume(otherNamespace != bytes32(0));
        vm.assume(namespace != otherNamespace);
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.assume(migrationA != migrationB);

        vm.warp(9000);
        vm.prank(writer);
        sRegistry.applyMigrationHistory(namespace, migrationA, 9000, onto(writer, namespace, MIGRATION_HEAD_GENESIS));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.TimestampBeforeHead.selector, 1, 9000));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(namespace, migrationB, 1, onto(writer, namespace, migrationA));

        vm.prank(writer);
        sRegistry.applyMigrationHistory(
            otherNamespace, migrationB, 1, onto(writer, otherNamespace, MIGRATION_HEAD_GENESIS)
        );
        assertEq(sRegistry.applied(writer, otherNamespace, migrationB), 1);
        assertEq(sRegistry.appliedOnto(writer, otherNamespace, migrationB), MIGRATION_HEAD_GENESIS);
        assertEq(sRegistry.applied(writer, namespace, migrationB), 0);
    }

    /// A chain belongs to one line. The same writer applying the same
    /// migrations in another namespace builds its own chain, and each walks
    /// back to genesis through its own records only.
    function testApplyMigrationChainIsPerNamespace(
        address writer,
        bytes32 namespace,
        bytes32 otherNamespace,
        bytes32 migrationA,
        bytes32 migrationB
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        vm.assume(otherNamespace != bytes32(0));
        vm.assume(namespace != otherNamespace);
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.assume(migrationA != migrationB);

        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationA, onto(writer, namespace, MIGRATION_HEAD_GENESIS));
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationB, onto(writer, namespace, migrationA));

        // The other line applies them in the opposite order, so a chain that
        // leaked would be visibly the first one's.
        vm.prank(writer);
        sRegistry.applyMigration(otherNamespace, migrationB, onto(writer, otherNamespace, MIGRATION_HEAD_GENESIS));
        vm.prank(writer);
        sRegistry.applyMigration(otherNamespace, migrationA, onto(writer, otherNamespace, migrationB));

        bytes32 cursor = sRegistry.head(writer, namespace);
        assertEq(cursor, migrationB);
        cursor = sRegistry.appliedOnto(writer, namespace, cursor);
        assertEq(cursor, migrationA);
        cursor = sRegistry.appliedOnto(writer, namespace, cursor);
        assertEq(cursor, MIGRATION_HEAD_GENESIS);

        cursor = sRegistry.head(writer, otherNamespace);
        assertEq(cursor, migrationA);
        cursor = sRegistry.appliedOnto(writer, otherNamespace, cursor);
        assertEq(cursor, migrationB);
        cursor = sRegistry.appliedOnto(writer, otherNamespace, cursor);
        assertEq(cursor, MIGRATION_HEAD_GENESIS);
    }

    /// `Migrated` carries the namespace as its second indexed topic, between
    /// the writer and the migration, so the log can be filtered to one line.
    function testApplyMigrationEventCarriesTheNamespace(
        address writer,
        bytes32 namespace,
        bytes32 migration,
        uint32 now_
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        vm.assume(now_ != 0);
        vm.warp(now_);

        vm.recordLogs();
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migration, onto(writer, namespace, MIGRATION_HEAD_GENESIS));
        Vm.Log[] memory entries = vm.getRecordedLogs();

        assertEq(entries.length, 1);
        assertEq(entries[0].emitter, address(sRegistry));
        assertEq(entries[0].topics.length, 4);
        assertEq(entries[0].topics[0], keccak256("Migrated(address,bytes32,bytes32,uint256)"));
        assertEq(entries[0].topics[1], bytes32(uint256(uint160(writer))));
        assertEq(entries[0].topics[2], namespace);
        assertEq(entries[0].topics[3], migration);
        assertEq(entries[0].data, abi.encode(uint256(now_)));
    }

    /// With its one prerequisite applied, a write naming it records exactly
    /// what the write naming nothing records — the same moment, the same head
    /// applied onto, the same new head — and the list is the one thing the two
    /// records differ in. Two registries with the same prior state are written
    /// the two ways and compared, so "the list is the only difference" is a
    /// fact about the whole record rather than about one reader.
    function testApplyMigrationPrerequisiteWritesTheSameRecord(
        address writer,
        bytes32 namespace,
        address other,
        bytes32 migration,
        bytes32 prerequisite,
        uint32 now_
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        vm.assume(other != address(0));
        vm.assume(writer != other);
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, prerequisite);
        vm.assume(migration != prerequisite);
        vm.assume(now_ != 0);
        vm.warp(now_);

        MigrationRegistry plain = new MigrationRegistry();
        MigrationRegistry waiting = new MigrationRegistry();
        vm.prank(other);
        plain.applyMigration(namespace, prerequisite, onto(other, namespace, MIGRATION_HEAD_GENESIS));
        vm.prank(other);
        waiting.applyMigration(namespace, prerequisite, onto(other, namespace, MIGRATION_HEAD_GENESIS));

        bytes32 plainHead = plain.head(writer, namespace);
        bytes32 waitingHead = waiting.head(writer, namespace);
        vm.prank(writer);
        plain.applyMigration(namespace, migration, onto(writer, namespace, plainHead));
        Prerequisite[] memory waitingList =
            headThen(writer, namespace, waitingHead, one(other, namespace, prerequisite));
        vm.prank(writer);
        waiting.applyMigration(namespace, migration, waitingList);

        assertEq(waiting.applied(writer, namespace, migration), plain.applied(writer, namespace, migration));
        assertEq(waiting.applied(writer, namespace, migration), now_);
        assertEq(waiting.appliedOnto(writer, namespace, migration), plain.appliedOnto(writer, namespace, migration));
        assertEq(waiting.head(writer, namespace), plain.head(writer, namespace));
        assertEq(waiting.head(writer, namespace), migration);
        assertEq(
            abi.encode(plain.appliedAfter(writer, namespace, migration)),
            abi.encode(onto(writer, namespace, MIGRATION_HEAD_GENESIS))
        );
        assertEq(abi.encode(waiting.appliedAfter(writer, namespace, migration)), abi.encode(waitingList));
    }

    /// The same for `applyMigrationHistory`: the supplied moment is what is
    /// recorded, onto the same head, and the list is the one difference.
    function testApplyMigrationHistoryPrerequisiteWritesTheSameRecord(
        address writer,
        bytes32 namespace,
        address other,
        bytes32 migration,
        bytes32 prerequisite,
        uint32 appliedAt,
        uint32 now_
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        vm.assume(other != address(0));
        // The prerequisite is under another writer, so applying it leaves the
        // caller's head at genesis, which bounds no moment. A prerequisite in
        // the caller's own line is
        // `testApplyMigrationOwnEarlierMigrationIsNotAPrerequisite`.
        vm.assume(writer != other);
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, prerequisite);
        vm.assume(migration != prerequisite);
        vm.assume(appliedAt != 0);
        vm.assume(now_ >= appliedAt);
        vm.warp(now_);

        MigrationRegistry plain = new MigrationRegistry();
        MigrationRegistry waiting = new MigrationRegistry();
        vm.prank(other);
        plain.applyMigration(namespace, prerequisite, onto(other, namespace, MIGRATION_HEAD_GENESIS));
        vm.prank(other);
        waiting.applyMigration(namespace, prerequisite, onto(other, namespace, MIGRATION_HEAD_GENESIS));

        Prerequisite[] memory expected =
            headThen(writer, namespace, MIGRATION_HEAD_GENESIS, one(other, namespace, prerequisite));
        vm.prank(writer);
        plain.applyMigrationHistory(namespace, migration, appliedAt, onto(writer, namespace, MIGRATION_HEAD_GENESIS));
        vm.prank(writer);
        waiting.applyMigrationHistory(namespace, migration, appliedAt, expected);

        assertEq(waiting.applied(writer, namespace, migration), plain.applied(writer, namespace, migration));
        assertEq(waiting.applied(writer, namespace, migration), appliedAt);
        assertEq(waiting.appliedOnto(writer, namespace, migration), plain.appliedOnto(writer, namespace, migration));
        assertEq(waiting.head(writer, namespace), plain.head(writer, namespace));
        assertEq(waiting.head(writer, namespace), migration);
        assertEq(
            abi.encode(plain.appliedAfter(writer, namespace, migration)),
            abi.encode(onto(writer, namespace, MIGRATION_HEAD_GENESIS))
        );
        assertEq(abi.encode(waiting.appliedAfter(writer, namespace, migration)), abi.encode(expected));
    }

    /// A record keeps the list it was applied after, as given, which is
    /// what `appliedAfter` reads back. Before the write there is nothing; after a
    /// later write with a different list, the earlier record's list is what it
    /// was — the value the caller named and the registry checked.
    function testApplyMigrationRecordsThePrerequisitesAsListed(
        address writer,
        bytes32 namespace,
        address otherA,
        address otherB,
        bytes32 migrationA,
        bytes32 migrationB,
        bytes32 prerequisiteA,
        bytes32 prerequisiteB
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        vm.assume(otherA != address(0));
        vm.assume(otherB != address(0));
        vm.assume(writer != otherA);
        vm.assume(writer != otherB);
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        LibMigrationFuzz.assumeMigration(vm, prerequisiteA);
        LibMigrationFuzz.assumeMigration(vm, prerequisiteB);
        vm.assume(migrationA != migrationB);
        vm.assume(migrationA != prerequisiteA);
        vm.assume(migrationA != prerequisiteB);
        vm.assume(migrationB != prerequisiteA);
        vm.assume(migrationB != prerequisiteB);
        applyUnder(otherA, namespace, prerequisiteA);
        if (sRegistry.applied(otherB, namespace, prerequisiteB) == 0) {
            applyUnder(otherB, namespace, prerequisiteB);
        }
        Prerequisite[] memory listA = two(otherA, namespace, prerequisiteA, otherB, namespace, prerequisiteB);
        Prerequisite[] memory listB = one(otherB, namespace, prerequisiteB);

        assertEq(abi.encode(sRegistry.appliedAfter(writer, namespace, migrationA)), abi.encode(new Prerequisite[](0)));

        bytes32 head = sRegistry.head(writer, namespace);
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationA, headThen(writer, namespace, head, listA));
        assertEq(
            abi.encode(sRegistry.appliedAfter(writer, namespace, migrationA)),
            abi.encode(headThen(writer, namespace, head, listA))
        );
        assertEq(abi.encode(sRegistry.appliedAfter(writer, namespace, migrationB)), abi.encode(new Prerequisite[](0)));

        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationB, headThen(writer, namespace, migrationA, listB));
        assertEq(
            abi.encode(sRegistry.appliedAfter(writer, namespace, migrationB)),
            abi.encode(headThen(writer, namespace, migrationA, listB))
        );
        assertEq(
            abi.encode(sRegistry.appliedAfter(writer, namespace, migrationA)),
            abi.encode(headThen(writer, namespace, head, listA))
        );
    }

    /// A list of any length is recorded whole and in order: every key the
    /// caller listed after the head, once applied, comes back at the index it
    /// was listed at.
    function testApplyMigrationRecordsAListOfAnyLength(
        address writer,
        bytes32 namespace,
        bytes32 migration,
        bytes32[] memory seeds
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        Prerequisite[] memory prerequisites = keysFromSeeds(seeds);
        for (uint256 i = 0; i < prerequisites.length; i++) {
            vm.assume(prerequisites[i].migration != migration);
            if (sRegistry.applied(prerequisites[i].writer, prerequisites[i].namespace, prerequisites[i].migration) == 0)
            {
                applyUnder(prerequisites[i].writer, prerequisites[i].namespace, prerequisites[i].migration);
            }
        }

        bytes32 head = sRegistry.head(writer, namespace);
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migration, headThen(writer, namespace, head, prerequisites));

        Prerequisite[] memory recorded = sRegistry.appliedAfter(writer, namespace, migration);
        assertEq(recorded.length, prerequisites.length + 1);
        assertEq(recorded[0].writer, writer);
        assertEq(recorded[0].namespace, namespace);
        assertEq(recorded[0].migration, head);
        for (uint256 i = 0; i < prerequisites.length; i++) {
            assertEq(recorded[i + 1].writer, prerequisites[i].writer);
            assertEq(recorded[i + 1].namespace, prerequisites[i].namespace);
            assertEq(recorded[i + 1].migration, prerequisites[i].migration);
        }
    }

    /// The prerequisite's own line is read and not written: after the
    /// dependent write lands, the prerequisite's writer has the head and the
    /// record it had before.
    function testApplyMigrationPrerequisiteNamespaceIsLeftAlone(
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
        // The last assertion asks whether `migration` reached the other
        // line, which is only a question when it is not the
        // prerequisite that was put there.
        vm.assume(migration != prerequisite);
        vm.warp(1000);
        applyUnder(other, namespace, prerequisite);
        vm.warp(2000);

        vm.prank(writer);
        sRegistry.applyMigration(
            namespace,
            migration,
            headThen(writer, namespace, MIGRATION_HEAD_GENESIS, one(other, namespace, prerequisite))
        );

        assertEq(sRegistry.applied(other, namespace, prerequisite), 1000);
        assertEq(sRegistry.appliedOnto(other, namespace, prerequisite), MIGRATION_HEAD_GENESIS);
        assertEq(
            abi.encode(sRegistry.appliedAfter(other, namespace, prerequisite)),
            abi.encode(one(other, namespace, MIGRATION_HEAD_GENESIS))
        );
        assertEq(sRegistry.head(other, namespace), prerequisite);
        assertEq(sRegistry.applied(other, namespace, migration), 0);
    }

    /// A prerequisite nobody has applied refuses the write, naming it, and
    /// nothing moves: the migration stays unapplied and the head stays where
    /// it was. Once the prerequisite is applied the same call lands. This is
    /// the whole point of the list — the dependent script is held back by the
    /// registry rather than by re-reading the other migration's post-state.
    function testApplyMigrationUnappliedPrerequisiteRevertsThenLands(
        address writer,
        bytes32 namespace,
        address other,
        bytes32 migration,
        bytes32 prerequisite
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        vm.assume(other != address(0));
        // The prerequisite is under another writer, so applying it leaves the
        // caller's head where the same call expects it. A prerequisite in
        // the caller's own line is
        // `testApplyMigrationOwnEarlierMigrationIsNotAPrerequisite`.
        vm.assume(writer != other);
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, prerequisite);
        vm.assume(migration != prerequisite);

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.PrerequisiteNotApplied.selector, other, namespace, prerequisite)
        );
        vm.prank(writer);
        sRegistry.applyMigration(
            namespace,
            migration,
            headThen(writer, namespace, MIGRATION_HEAD_GENESIS, one(other, namespace, prerequisite))
        );

        assertEq(sRegistry.applied(writer, namespace, migration), 0);
        assertEq(abi.encode(sRegistry.appliedAfter(writer, namespace, migration)), abi.encode(new Prerequisite[](0)));
        assertEq(sRegistry.head(writer, namespace), MIGRATION_HEAD_GENESIS);

        applyUnder(other, namespace, prerequisite);

        vm.prank(writer);
        sRegistry.applyMigration(
            namespace,
            migration,
            headThen(writer, namespace, MIGRATION_HEAD_GENESIS, one(other, namespace, prerequisite))
        );

        assertEq(sRegistry.applied(writer, namespace, migration), block.timestamp);
        assertEq(sRegistry.appliedOnto(writer, namespace, migration), MIGRATION_HEAD_GENESIS);
        assertEq(
            abi.encode(sRegistry.appliedAfter(writer, namespace, migration)),
            abi.encode(headThen(writer, namespace, MIGRATION_HEAD_GENESIS, one(other, namespace, prerequisite)))
        );
        assertEq(sRegistry.head(writer, namespace), migration);
    }

    /// The same on `applyMigrationHistory`, with the caller's moment recorded
    /// once the prerequisite is there.
    function testApplyMigrationHistoryUnappliedPrerequisiteRevertsThenLands(
        address writer,
        bytes32 namespace,
        address other,
        bytes32 migration,
        bytes32 prerequisite,
        uint32 appliedAt,
        uint32 now_
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        vm.assume(other != address(0));
        // The prerequisite is under another writer, so applying it leaves the
        // caller's head where the same call expects it. A prerequisite in
        // the caller's own line is
        // `testApplyMigrationOwnEarlierMigrationIsNotAPrerequisite`.
        vm.assume(writer != other);
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, prerequisite);
        vm.assume(migration != prerequisite);
        vm.assume(appliedAt != 0);
        vm.assume(now_ >= appliedAt);
        vm.warp(now_);
        Prerequisite[] memory prerequisites =
            headThen(writer, namespace, MIGRATION_HEAD_GENESIS, one(other, namespace, prerequisite));

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.PrerequisiteNotApplied.selector, other, namespace, prerequisite)
        );
        vm.prank(writer);
        sRegistry.applyMigrationHistory(namespace, migration, appliedAt, prerequisites);

        assertEq(sRegistry.applied(writer, namespace, migration), 0);
        assertEq(sRegistry.head(writer, namespace), MIGRATION_HEAD_GENESIS);

        applyUnder(other, namespace, prerequisite);

        vm.prank(writer);
        sRegistry.applyMigrationHistory(namespace, migration, appliedAt, prerequisites);

        assertEq(sRegistry.applied(writer, namespace, migration), appliedAt);
        assertEq(abi.encode(sRegistry.appliedAfter(writer, namespace, migration)), abi.encode(prerequisites));
        assertEq(sRegistry.head(writer, namespace), migration);
    }

    /// A prerequisite is a particular migration, not a line that has
    /// applied something. A writer that has applied other migrations and not
    /// the one named is refused exactly as an empty line is.
    function testApplyMigrationPrerequisiteIsTheMigrationNotTheNamespace(
        address writer,
        bytes32 namespace,
        address other,
        bytes32 migration,
        bytes32 prerequisite,
        bytes32 unrelated
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        vm.assume(other != address(0));
        vm.assume(writer != other);
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, prerequisite);
        LibMigrationFuzz.assumeMigration(vm, unrelated);
        vm.assume(prerequisite != unrelated);
        applyUnder(other, namespace, unrelated);

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.PrerequisiteNotApplied.selector, other, namespace, prerequisite)
        );
        vm.prank(writer);
        sRegistry.applyMigration(
            namespace,
            migration,
            headThen(writer, namespace, MIGRATION_HEAD_GENESIS, one(other, namespace, prerequisite))
        );
    }

    /// Over a list of any length with exactly one entry unapplied, the revert
    /// names that entry — wherever it sits, whatever other lines the rest
    /// are in. Once it is applied too, the write lands and the whole list is
    /// the record's.
    function testApplyMigrationNamesTheOneUnappliedPrerequisite(
        address writer,
        bytes32 namespace,
        bytes32 migration,
        bytes32[] memory seeds,
        uint256 unappliedIndex
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        vm.assume(seeds.length > 0);
        Prerequisite[] memory prerequisites = keysFromSeeds(seeds);
        unappliedIndex = bound(unappliedIndex, 0, prerequisites.length - 1);
        Prerequisite memory unapplied = prerequisites[unappliedIndex];

        for (uint256 i = 0; i < prerequisites.length; i++) {
            // The caller's own migration is never a prerequisite here: applied
            // as one, it would make the second half `MigrationAlreadyApplied`.
            vm.assume(prerequisites[i].migration != migration);
            // Nor is the caller's own line: an own entry after the head
            // is refused as a key before any record is read.
            vm.assume(prerequisites[i].writer != writer);
            if (i == unappliedIndex) {
                continue;
            }
            // Applying any other entry must not apply the unapplied one.
            vm.assume(prerequisites[i].writer != unapplied.writer || prerequisites[i].migration != unapplied.migration);
            if (sRegistry.applied(prerequisites[i].writer, prerequisites[i].namespace, prerequisites[i].migration) == 0)
            {
                applyUnder(prerequisites[i].writer, prerequisites[i].namespace, prerequisites[i].migration);
            }
        }

        bytes32 head = sRegistry.head(writer, namespace);
        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.PrerequisiteNotApplied.selector,
                unapplied.writer,
                unapplied.namespace,
                unapplied.migration
            )
        );
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migration, headThen(writer, namespace, head, prerequisites));
        assertEq(sRegistry.applied(writer, namespace, migration), 0);

        applyUnder(unapplied.writer, unapplied.namespace, unapplied.migration);

        head = sRegistry.head(writer, namespace);
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migration, headThen(writer, namespace, head, prerequisites));
        assertEq(sRegistry.applied(writer, namespace, migration), block.timestamp);
        assertEq(
            abi.encode(sRegistry.appliedAfter(writer, namespace, migration)),
            abi.encode(headThen(writer, namespace, head, prerequisites))
        );
        assertEq(sRegistry.head(writer, namespace), migration);
    }

    /// The same on `applyMigrationHistory`.
    function testApplyMigrationHistoryNamesTheOneUnappliedPrerequisite(
        address writer,
        bytes32 namespace,
        bytes32 migration,
        bytes32[] memory seeds,
        uint256 unappliedIndex,
        uint32 appliedAt,
        uint32 now_
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        vm.assume(seeds.length > 0);
        vm.assume(appliedAt != 0);
        vm.assume(now_ >= appliedAt);
        vm.warp(now_);
        Prerequisite[] memory prerequisites = keysFromSeeds(seeds);
        unappliedIndex = bound(unappliedIndex, 0, prerequisites.length - 1);
        Prerequisite memory unapplied = prerequisites[unappliedIndex];

        for (uint256 i = 0; i < prerequisites.length; i++) {
            vm.assume(prerequisites[i].migration != migration);
            // Nothing is applied in the caller's own line, so the caller's
            // moment is bounded by genesis alone.
            vm.assume(prerequisites[i].writer != writer);
            if (i == unappliedIndex) {
                continue;
            }
            vm.assume(prerequisites[i].writer != unapplied.writer || prerequisites[i].migration != unapplied.migration);
            if (sRegistry.applied(prerequisites[i].writer, prerequisites[i].namespace, prerequisites[i].migration) == 0)
            {
                applyUnder(prerequisites[i].writer, prerequisites[i].namespace, prerequisites[i].migration);
            }
        }

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.PrerequisiteNotApplied.selector,
                unapplied.writer,
                unapplied.namespace,
                unapplied.migration
            )
        );
        vm.prank(writer);
        sRegistry.applyMigrationHistory(
            namespace, migration, appliedAt, headThen(writer, namespace, MIGRATION_HEAD_GENESIS, prerequisites)
        );
        assertEq(sRegistry.applied(writer, namespace, migration), 0);

        applyUnder(unapplied.writer, unapplied.namespace, unapplied.migration);

        vm.prank(writer);
        sRegistry.applyMigrationHistory(
            namespace, migration, appliedAt, headThen(writer, namespace, MIGRATION_HEAD_GENESIS, prerequisites)
        );
        assertEq(sRegistry.applied(writer, namespace, migration), appliedAt);
        assertEq(
            abi.encode(sRegistry.appliedAfter(writer, namespace, migration)),
            abi.encode(headThen(writer, namespace, MIGRATION_HEAD_GENESIS, prerequisites))
        );
    }

    /// With several unapplied, the FIRST in list order is the one named, and
    /// applying it moves the refusal to the next. A caller waiting on several
    /// is told about one at a time, in the order it listed them.
    function testApplyMigrationNamesTheFirstUnappliedPrerequisite(
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
        vm.assume(otherA != otherB || prerequisiteA != prerequisiteB);
        Prerequisite[] memory prerequisites = two(otherA, namespace, prerequisiteA, otherB, namespace, prerequisiteB);

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.PrerequisiteNotApplied.selector, otherA, namespace, prerequisiteA
            )
        );
        vm.prank(writer);
        sRegistry.applyMigration(
            namespace, migration, headThen(writer, namespace, MIGRATION_HEAD_GENESIS, prerequisites)
        );

        applyUnder(otherA, namespace, prerequisiteA);

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.PrerequisiteNotApplied.selector, otherB, namespace, prerequisiteB
            )
        );
        vm.prank(writer);
        sRegistry.applyMigration(
            namespace, migration, headThen(writer, namespace, MIGRATION_HEAD_GENESIS, prerequisites)
        );

        applyUnder(otherB, namespace, prerequisiteB);

        bytes32 head = sRegistry.head(writer, namespace);
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migration, headThen(writer, namespace, head, prerequisites));
        assertEq(sRegistry.applied(writer, namespace, migration), block.timestamp);
    }

    /// A prerequisite naming the zero writer is refused as `ZeroWriter`, the
    /// same refusal `applied` makes of the same key. The zero writer is
    /// provably empty, so without this the entry would be refused as unapplied
    /// forever instead of as the unset constant it is.
    function testApplyMigrationZeroWriterPrerequisiteReverts(
        address writer,
        bytes32 namespace,
        bytes32 migration,
        bytes32 prerequisite
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, prerequisite);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroWriter.selector));
        vm.prank(writer);
        sRegistry.applyMigration(
            namespace,
            migration,
            headThen(writer, namespace, MIGRATION_HEAD_GENESIS, one(address(0), namespace, prerequisite))
        );

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroWriter.selector));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(
            namespace,
            migration,
            block.timestamp,
            headThen(writer, namespace, MIGRATION_HEAD_GENESIS, one(address(0), namespace, prerequisite))
        );

        assertEq(sRegistry.applied(writer, namespace, migration), 0);
    }

    /// A prerequisite naming the zero migration is refused as `ZeroMigration`,
    /// whatever its writer: an uninitialised id names no record.
    function testApplyMigrationZeroMigrationPrerequisiteReverts(
        address writer,
        bytes32 namespace,
        address other,
        bytes32 migration
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        vm.assume(other != address(0));
        LibMigrationFuzz.assumeMigration(vm, migration);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(
            namespace, migration, headThen(writer, namespace, MIGRATION_HEAD_GENESIS, one(other, namespace, bytes32(0)))
        );

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(
            namespace,
            migration,
            block.timestamp,
            headThen(writer, namespace, MIGRATION_HEAD_GENESIS, one(other, namespace, bytes32(0)))
        );

        assertEq(sRegistry.applied(writer, namespace, migration), 0);
    }

    /// A prerequisite naming `MIGRATION_HEAD_GENESIS` is refused as
    /// `GenesisMigration`: genesis is a head, no line ever applies it, and
    /// a caller that named it has confused a head for a migration.
    function testApplyMigrationGenesisPrerequisiteReverts(
        address writer,
        bytes32 namespace,
        address other,
        bytes32 migration
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        vm.assume(other != address(0));
        LibMigrationFuzz.assumeMigration(vm, migration);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.GenesisMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(
            namespace,
            migration,
            headThen(writer, namespace, MIGRATION_HEAD_GENESIS, one(other, namespace, MIGRATION_HEAD_GENESIS))
        );

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.GenesisMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(
            namespace,
            migration,
            block.timestamp,
            headThen(writer, namespace, MIGRATION_HEAD_GENESIS, one(other, namespace, MIGRATION_HEAD_GENESIS))
        );

        assertEq(sRegistry.applied(writer, namespace, migration), 0);
    }

    /// Within one entry the key is refused in `applied`'s order: writer,
    /// then namespace, then the two reserved ids. An entry that is wrong in
    /// every field is `ZeroWriter`; one wrong in every field but the writer
    /// is `ZeroNamespace`.
    function testApplyMigrationPrerequisiteKeyRefusalOrderWithinAnEntry(
        address writer,
        bytes32 namespace,
        address other,
        bytes32 migration
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        vm.assume(other != address(0));
        LibMigrationFuzz.assumeMigration(vm, migration);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroWriter.selector));
        vm.prank(writer);
        sRegistry.applyMigration(
            namespace,
            migration,
            headThen(writer, namespace, MIGRATION_HEAD_GENESIS, one(address(0), bytes32(0), bytes32(0)))
        );

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroWriter.selector));
        vm.prank(writer);
        sRegistry.applyMigration(
            namespace,
            migration,
            headThen(writer, namespace, MIGRATION_HEAD_GENESIS, one(address(0), bytes32(0), MIGRATION_HEAD_GENESIS))
        );

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroNamespace.selector));
        vm.prank(writer);
        sRegistry.applyMigration(
            namespace,
            migration,
            headThen(writer, namespace, MIGRATION_HEAD_GENESIS, one(other, bytes32(0), bytes32(0)))
        );

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroNamespace.selector));
        vm.prank(writer);
        sRegistry.applyMigration(
            namespace,
            migration,
            headThen(writer, namespace, MIGRATION_HEAD_GENESIS, one(other, bytes32(0), MIGRATION_HEAD_GENESIS))
        );

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(
            namespace, migration, headThen(writer, namespace, MIGRATION_HEAD_GENESIS, one(other, namespace, bytes32(0)))
        );

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.GenesisMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(
            namespace,
            migration,
            headThen(writer, namespace, MIGRATION_HEAD_GENESIS, one(other, namespace, MIGRATION_HEAD_GENESIS))
        );
    }

    /// Every entry is checked as a key before any entry is read, so a
    /// malformed entry LATER in the list is reported over an unapplied entry
    /// earlier in it. A malformed argument is a mistake the caller can fix
    /// now; an unapplied prerequisite is a fact about the world, and the
    /// caller is told about its own mistakes first.
    function testApplyMigrationMalformedPrerequisiteReportedOverUnapplied(
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
        assertEq(sRegistry.applied(other, namespace, prerequisite), 0);
        Prerequisite[] memory zeroWriter = headThen(
            writer,
            namespace,
            MIGRATION_HEAD_GENESIS,
            two(other, namespace, prerequisite, address(0), namespace, prerequisite)
        );
        Prerequisite[] memory zeroMigration = headThen(
            writer, namespace, MIGRATION_HEAD_GENESIS, two(other, namespace, prerequisite, other, namespace, bytes32(0))
        );
        Prerequisite[] memory genesis = headThen(
            writer,
            namespace,
            MIGRATION_HEAD_GENESIS,
            two(other, namespace, prerequisite, other, namespace, MIGRATION_HEAD_GENESIS)
        );

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroWriter.selector));
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migration, zeroWriter);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migration, zeroMigration);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.GenesisMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migration, genesis);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroWriter.selector));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(namespace, migration, block.timestamp, zeroWriter);
    }

    /// Among several malformed entries, the first in list order is the one
    /// reported, whichever field is wrong in each.
    function testApplyMigrationFirstMalformedPrerequisiteReported(
        address writer,
        bytes32 namespace,
        address other,
        bytes32 migration
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        vm.assume(other != address(0));
        LibMigrationFuzz.assumeMigration(vm, migration);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroWriter.selector));
        vm.prank(writer);
        sRegistry.applyMigration(
            namespace,
            migration,
            headThen(
                writer,
                namespace,
                MIGRATION_HEAD_GENESIS,
                two(address(0), namespace, migration, other, namespace, bytes32(0))
            )
        );

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(
            namespace,
            migration,
            headThen(
                writer,
                namespace,
                MIGRATION_HEAD_GENESIS,
                two(other, namespace, bytes32(0), address(0), namespace, migration)
            )
        );

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.GenesisMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(
            namespace,
            migration,
            headThen(
                writer,
                namespace,
                MIGRATION_HEAD_GENESIS,
                two(other, namespace, MIGRATION_HEAD_GENESIS, other, namespace, bytes32(0))
            )
        );
    }

    /// A prerequisite naming the migration being applied is an entry after the
    /// head in the caller's own line, so it is refused as
    /// `OwnPrerequisite(migration)` before any record is read — the same
    /// refusal as any own entry, not the `PrerequisiteNotApplied` it would also
    /// be by construction. On both writes, and nothing is recorded.
    function testApplyMigrationSelfPrerequisiteReverts(address writer, bytes32 namespace, bytes32 migration) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migration);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.OwnPrerequisite.selector, migration));
        vm.prank(writer);
        sRegistry.applyMigration(
            namespace, migration, headThen(writer, namespace, MIGRATION_HEAD_GENESIS, one(writer, namespace, migration))
        );

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.OwnPrerequisite.selector, migration));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(
            namespace,
            migration,
            block.timestamp,
            headThen(writer, namespace, MIGRATION_HEAD_GENESIS, one(writer, namespace, migration))
        );

        assertEq(sRegistry.applied(writer, namespace, migration), 0);
        assertEq(sRegistry.head(writer, namespace), MIGRATION_HEAD_GENESIS);
    }

    /// The caller's own line is not a line to name after the head:
    /// an earlier migration of its own is refused as `OwnPrerequisite`,
    /// applied or not, and is never recorded as a prerequisite. The head
    /// already says everything about the caller's own line, so the earlier
    /// migration is named there and only there.
    function testApplyMigrationOwnEarlierMigrationIsNotAPrerequisite(
        address writer,
        bytes32 namespace,
        bytes32 migrationA,
        bytes32 migrationB
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.assume(migrationA != migrationB);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.OwnPrerequisite.selector, migrationA));
        vm.prank(writer);
        sRegistry.applyMigration(
            namespace,
            migrationB,
            headThen(writer, namespace, MIGRATION_HEAD_GENESIS, one(writer, namespace, migrationA))
        );

        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationA, onto(writer, namespace, MIGRATION_HEAD_GENESIS));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.OwnPrerequisite.selector, migrationA));
        vm.prank(writer);
        sRegistry.applyMigration(
            namespace, migrationB, headThen(writer, namespace, migrationA, one(writer, namespace, migrationA))
        );
        assertEq(sRegistry.applied(writer, namespace, migrationB), 0);
        assertEq(sRegistry.head(writer, namespace), migrationA);

        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationB, onto(writer, namespace, migrationA));

        assertEq(sRegistry.applied(writer, namespace, migrationB), block.timestamp);
        assertEq(sRegistry.appliedOnto(writer, namespace, migrationB), migrationA);
        assertEq(
            abi.encode(sRegistry.appliedAfter(writer, namespace, migrationB)),
            abi.encode(onto(writer, namespace, migrationA))
        );
        assertEq(sRegistry.head(writer, namespace), migrationB);
    }

    /// A prerequisite listed twice is checked twice — harmless when applied,
    /// and named once, as the first entry, when not — and recorded twice: the
    /// record says what the caller listed.
    function testApplyMigrationDuplicatePrerequisitesAreCheckedTwiceAndKept(
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
        Prerequisite[] memory prerequisites = two(other, namespace, prerequisite, other, namespace, prerequisite);

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.PrerequisiteNotApplied.selector, other, namespace, prerequisite)
        );
        vm.prank(writer);
        sRegistry.applyMigration(
            namespace, migration, headThen(writer, namespace, MIGRATION_HEAD_GENESIS, prerequisites)
        );

        applyUnder(other, namespace, prerequisite);

        bytes32 head = sRegistry.head(writer, namespace);
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migration, headThen(writer, namespace, head, prerequisites));
        assertEq(sRegistry.applied(writer, namespace, migration), block.timestamp);
        assertEq(sRegistry.appliedAfter(writer, namespace, migration).length, 3);
        assertEq(
            abi.encode(sRegistry.appliedAfter(writer, namespace, migration)),
            abi.encode(headThen(writer, namespace, head, prerequisites))
        );
    }

    /// The caller's own arguments are refused before the list is looked at:
    /// a zero or genesis migration, and a zero moment, are reported over the
    /// head alone, a malformed list and an unapplied one alike. Everything the
    /// caller handed in about its own record is what it can fix first.
    function testApplyMigrationOwnArgumentsCheckedBeforePrerequisites(
        address writer,
        bytes32 namespace,
        address other,
        bytes32 prerequisite,
        bytes32 anyHead
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        vm.assume(other != address(0));
        LibMigrationFuzz.assumeMigration(vm, prerequisite);
        vm.warp(1000);
        Prerequisite[] memory none = new Prerequisite[](0);
        Prerequisite[] memory malformed = one(address(0), namespace, prerequisite);
        Prerequisite[] memory unapplied = one(other, namespace, prerequisite);

        // Zero migration, over every kind of list.
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(namespace, bytes32(0), headThen(writer, namespace, anyHead, none));
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(namespace, bytes32(0), headThen(writer, namespace, anyHead, malformed));
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(namespace, bytes32(0), headThen(writer, namespace, anyHead, unapplied));

        // Genesis migration, over every kind of list.
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.GenesisMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(namespace, MIGRATION_HEAD_GENESIS, headThen(writer, namespace, anyHead, none));
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.GenesisMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(namespace, MIGRATION_HEAD_GENESIS, headThen(writer, namespace, anyHead, malformed));
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.GenesisMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(namespace, MIGRATION_HEAD_GENESIS, headThen(writer, namespace, anyHead, unapplied));

        // Zero moment, over every kind of list, on both writes.
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroTimestamp.selector));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(namespace, prerequisite, 0, headThen(writer, namespace, anyHead, none));
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroTimestamp.selector));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(namespace, prerequisite, 0, headThen(writer, namespace, anyHead, malformed));
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroTimestamp.selector));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(namespace, prerequisite, 0, headThen(writer, namespace, anyHead, unapplied));

        vm.warp(0);
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroTimestamp.selector));
        vm.prank(writer);
        sRegistry.applyMigration(namespace, prerequisite, headThen(writer, namespace, anyHead, none));
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroTimestamp.selector));
        vm.prank(writer);
        sRegistry.applyMigration(namespace, prerequisite, headThen(writer, namespace, anyHead, malformed));
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroTimestamp.selector));
        vm.prank(writer);
        sRegistry.applyMigration(namespace, prerequisite, headThen(writer, namespace, anyHead, unapplied));

        // And the migration before the moment.
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(namespace, bytes32(0), 0, headThen(writer, namespace, anyHead, none));
    }

    /// The prerequisites are read before the caller's own record: an unapplied
    /// prerequisite is reported over a migration the caller has already
    /// applied, onto the head that migration became. A record that exists
    /// while the prerequisites its script now names do not is the more
    /// alarming fact, and it is not hidden behind "already applied". With the
    /// prerequisite applied, the re-application is `MigrationAlreadyApplied`,
    /// as with the head alone.
    function testApplyMigrationPrerequisitesCheckedBeforeAlreadyApplied(
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
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migration, onto(writer, namespace, MIGRATION_HEAD_GENESIS));

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.PrerequisiteNotApplied.selector, other, namespace, prerequisite)
        );
        vm.prank(writer);
        sRegistry.applyMigration(
            namespace, migration, headThen(writer, namespace, migration, one(other, namespace, prerequisite))
        );

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.PrerequisiteNotApplied.selector, other, namespace, prerequisite)
        );
        vm.prank(writer);
        sRegistry.applyMigrationHistory(
            namespace,
            migration,
            block.timestamp,
            headThen(writer, namespace, migration, one(other, namespace, prerequisite))
        );

        applyUnder(other, namespace, prerequisite);

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.MigrationAlreadyApplied.selector, writer, namespace, migration)
        );
        vm.prank(writer);
        sRegistry.applyMigration(
            namespace, migration, headThen(writer, namespace, migration, one(other, namespace, prerequisite))
        );

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.MigrationAlreadyApplied.selector, writer, namespace, migration)
        );
        vm.prank(writer);
        sRegistry.applyMigrationHistory(
            namespace,
            migration,
            block.timestamp,
            headThen(writer, namespace, migration, one(other, namespace, prerequisite))
        );

        // The refusals recorded nothing over the original record's list.
        assertEq(
            abi.encode(sRegistry.appliedAfter(writer, namespace, migration)),
            abi.encode(one(writer, namespace, MIGRATION_HEAD_GENESIS))
        );
    }

    /// A wrong head is reported over an unapplied prerequisite, by both
    /// writes; with the head right, the same list is refused for the
    /// prerequisite.
    function testApplyMigrationHeadCheckedBeforePrerequisites(
        address writer,
        bytes32 namespace,
        address other,
        bytes32 migration,
        bytes32 prerequisite,
        bytes32 wrongHead
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        vm.assume(other != address(0));
        vm.assume(writer != other);
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, prerequisite);
        vm.assume(migration != prerequisite);
        vm.assume(wrongHead != MIGRATION_HEAD_GENESIS);

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.UnexpectedMigrationHead.selector,
                writer,
                namespace,
                wrongHead,
                MIGRATION_HEAD_GENESIS
            )
        );
        vm.prank(writer);
        sRegistry.applyMigration(
            namespace, migration, headThen(writer, namespace, wrongHead, one(other, namespace, prerequisite))
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.UnexpectedMigrationHead.selector,
                writer,
                namespace,
                wrongHead,
                MIGRATION_HEAD_GENESIS
            )
        );
        vm.prank(writer);
        sRegistry.applyMigrationHistory(
            namespace,
            migration,
            block.timestamp,
            headThen(writer, namespace, wrongHead, one(other, namespace, prerequisite))
        );

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.PrerequisiteNotApplied.selector, other, namespace, prerequisite)
        );
        vm.prank(writer);
        sRegistry.applyMigration(
            namespace,
            migration,
            headThen(writer, namespace, MIGRATION_HEAD_GENESIS, one(other, namespace, prerequisite))
        );

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.PrerequisiteNotApplied.selector, other, namespace, prerequisite)
        );
        vm.prank(writer);
        sRegistry.applyMigrationHistory(
            namespace,
            migration,
            block.timestamp,
            headThen(writer, namespace, MIGRATION_HEAD_GENESIS, one(other, namespace, prerequisite))
        );
    }

    /// An unapplied prerequisite is reported over a moment before the head's
    /// and over a moment in the future; with the prerequisite applied, each
    /// is reported as the head alone reports it, in the same order.
    function testApplyMigrationPrerequisitesCheckedBeforeTheMoment(
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
        vm.warp(2000);
        vm.prank(writer);
        sRegistry.applyMigrationHistory(namespace, migrationA, 2000, onto(writer, namespace, MIGRATION_HEAD_GENESIS));
        vm.warp(3000);

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.PrerequisiteNotApplied.selector, other, namespace, prerequisite)
        );
        vm.prank(writer);
        sRegistry.applyMigrationHistory(
            namespace, migrationB, 1999, headThen(writer, namespace, migrationA, one(other, namespace, prerequisite))
        );

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.PrerequisiteNotApplied.selector, other, namespace, prerequisite)
        );
        vm.prank(writer);
        sRegistry.applyMigrationHistory(
            namespace, migrationB, 3001, headThen(writer, namespace, migrationA, one(other, namespace, prerequisite))
        );

        applyUnder(other, namespace, prerequisite);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.TimestampBeforeHead.selector, 1999, 2000));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(
            namespace, migrationB, 1999, headThen(writer, namespace, migrationA, one(other, namespace, prerequisite))
        );

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.FutureTimestamp.selector, 3001, 3000));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(
            namespace, migrationB, 3001, headThen(writer, namespace, migrationA, one(other, namespace, prerequisite))
        );

        // A moment wrong both ways is reported against the head first, as with
        // the head alone: the record it reads is the one the head check just
        // confirmed, and the future is the one refusal time resolves.
        vm.warp(1000);
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.TimestampBeforeHead.selector, 1500, 2000));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(
            namespace, migrationB, 1500, headThen(writer, namespace, migrationA, one(other, namespace, prerequisite))
        );
    }

    /// With prerequisites the line's own order holds: a wrong head is
    /// reported over a migration already applied.
    function testApplyMigrationHeadCheckedBeforeAlreadyAppliedWithPrerequisites(
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
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationA, onto(writer, namespace, MIGRATION_HEAD_GENESIS));
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationB, onto(writer, namespace, migrationA));

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.UnexpectedMigrationHead.selector,
                writer,
                namespace,
                MIGRATION_HEAD_GENESIS,
                migrationB
            )
        );
        vm.prank(writer);
        sRegistry.applyMigration(
            namespace,
            migrationA,
            headThen(writer, namespace, MIGRATION_HEAD_GENESIS, one(other, namespace, prerequisite))
        );
    }

    /// A prerequisite recorded through `applyMigrationHistory` counts: what is
    /// checked is that the record exists, not which write wrote it.
    function testApplyMigrationPrerequisiteRecordedByHistoryCounts(
        address writer,
        bytes32 namespace,
        address other,
        bytes32 migration,
        bytes32 prerequisite,
        uint32 prerequisiteAt,
        uint32 now_
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        vm.assume(other != address(0));
        vm.assume(writer != other);
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, prerequisite);
        vm.assume(prerequisiteAt != 0);
        vm.assume(now_ >= prerequisiteAt);
        vm.warp(now_);
        vm.prank(other);
        sRegistry.applyMigrationHistory(
            namespace, prerequisite, prerequisiteAt, onto(other, namespace, MIGRATION_HEAD_GENESIS)
        );

        Prerequisite[] memory prerequisites =
            headThen(writer, namespace, MIGRATION_HEAD_GENESIS, one(other, namespace, prerequisite));
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migration, prerequisites);

        assertEq(sRegistry.applied(writer, namespace, migration), now_);
    }

    /// A prerequisite bounds no moment. A record whose moment is EARLIER than
    /// its prerequisite's is accepted: the moments in another line are
    /// that writer's data, and what is checked is that the record existed
    /// when this write landed, which is the chain's order and not the
    /// moments'.
    function testApplyMigrationHistoryMomentIsNotBoundedByThePrerequisite(
        address writer,
        bytes32 namespace,
        address other,
        bytes32 migration,
        bytes32 prerequisite,
        uint32 appliedAt,
        uint32 prerequisiteAt,
        uint32 now_
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        vm.assume(other != address(0));
        vm.assume(writer != other);
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, prerequisite);
        vm.assume(appliedAt != 0);
        vm.assume(prerequisiteAt > appliedAt);
        vm.assume(now_ >= prerequisiteAt);
        vm.warp(now_);
        vm.prank(other);
        sRegistry.applyMigrationHistory(
            namespace, prerequisite, prerequisiteAt, onto(other, namespace, MIGRATION_HEAD_GENESIS)
        );

        Prerequisite[] memory prerequisites =
            headThen(writer, namespace, MIGRATION_HEAD_GENESIS, one(other, namespace, prerequisite));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(namespace, migration, appliedAt, prerequisites);

        assertEq(sRegistry.applied(writer, namespace, migration), appliedAt);
        assertEq(sRegistry.applied(other, namespace, prerequisite), prerequisiteAt);
    }

    /// A write naming prerequisites emits `Migrated` exactly as one naming none
    /// does: one entry, the writer and migration indexed, the moment as data,
    /// and nothing about the list — the list is in the record, read back by
    /// `prerequisites`, so one filter on `Migrated` is the complete history.
    function testApplyMigrationWithPrerequisitesEmitsOneMigrated(
        address writer,
        bytes32 namespace,
        address otherA,
        address otherB,
        bytes32 migration,
        bytes32 prerequisiteA,
        bytes32 prerequisiteB,
        uint32 now_
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
        vm.assume(now_ != 0);
        vm.warp(now_);
        applyUnder(otherA, namespace, prerequisiteA);
        if (sRegistry.applied(otherB, namespace, prerequisiteB) == 0) {
            applyUnder(otherB, namespace, prerequisiteB);
        }
        Prerequisite[] memory prerequisites = two(otherA, namespace, prerequisiteA, otherB, namespace, prerequisiteB);

        bytes32 head = sRegistry.head(writer, namespace);
        vm.recordLogs();
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migration, headThen(writer, namespace, head, prerequisites));
        Vm.Log[] memory entries = vm.getRecordedLogs();

        assertEq(entries.length, 1);
        assertEq(entries[0].emitter, address(sRegistry));
        assertEq(entries[0].topics.length, 4);
        assertEq(entries[0].topics[0], keccak256("Migrated(address,bytes32,bytes32,uint256)"));
        assertEq(entries[0].topics[1], bytes32(uint256(uint160(writer))));
        assertEq(entries[0].topics[2], namespace);
        assertEq(entries[0].topics[3], migration);
        assertEq(entries[0].data, abi.encode(uint256(now_)));
    }

    /// The same one entry from `applyMigrationHistory`, with the caller's
    /// moment as data.
    function testApplyMigrationHistoryWithPrerequisitesEmitsOneMigrated(
        address writer,
        bytes32 namespace,
        address other,
        bytes32 migration,
        bytes32 prerequisite,
        uint32 appliedAt,
        uint32 now_
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        vm.assume(other != address(0));
        // The prerequisite is under another writer, so applying it leaves the
        // caller's head at genesis, which bounds no moment. A prerequisite in
        // the caller's own line is
        // `testApplyMigrationOwnEarlierMigrationIsNotAPrerequisite`.
        vm.assume(writer != other);
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, prerequisite);
        vm.assume(migration != prerequisite);
        vm.assume(appliedAt != 0);
        vm.assume(now_ >= appliedAt);
        vm.warp(now_);
        applyUnder(other, namespace, prerequisite);
        Prerequisite[] memory prerequisites = one(other, namespace, prerequisite);

        bytes32 head = sRegistry.head(writer, namespace);
        vm.recordLogs();
        vm.prank(writer);
        sRegistry.applyMigrationHistory(
            namespace, migration, appliedAt, headThen(writer, namespace, head, prerequisites)
        );
        Vm.Log[] memory entries = vm.getRecordedLogs();

        assertEq(entries.length, 1);
        assertEq(entries[0].emitter, address(sRegistry));
        assertEq(entries[0].topics.length, 4);
        assertEq(entries[0].topics[0], keccak256("Migrated(address,bytes32,bytes32,uint256)"));
        assertEq(entries[0].topics[1], bytes32(uint256(uint160(writer))));
        assertEq(entries[0].topics[2], namespace);
        assertEq(entries[0].topics[3], migration);
        assertEq(entries[0].data, abi.encode(uint256(appliedAt)));
    }

    /// A write after the head alone and a write with a list emit one entry each,
    /// of the same event: the list changes what is recorded and nothing about
    /// what is logged.
    function testApplyMigrationEmitsOneEntryWhateverTheList(
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

        vm.recordLogs();
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationA, onto(writer, namespace, MIGRATION_HEAD_GENESIS));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(
            namespace,
            migrationB,
            block.timestamp,
            headThen(writer, namespace, migrationA, one(other, namespace, prerequisite))
        );
        Vm.Log[] memory entries = vm.getRecordedLogs();

        assertEq(entries.length, 2);
        assertEq(entries[0].topics.length, 4);
        assertEq(entries[0].topics[0], keccak256("Migrated(address,bytes32,bytes32,uint256)"));
        assertEq(entries[0].topics[2], namespace);
        assertEq(entries[0].topics[3], migrationA);
        assertEq(entries[1].topics.length, 4);
        assertEq(entries[1].topics[0], keccak256("Migrated(address,bytes32,bytes32,uint256)"));
        assertEq(entries[1].topics[2], namespace);
        assertEq(entries[1].topics[3], migrationB);
    }

    /// A refused write naming prerequisites emits nothing, for every one of
    /// its refusals, the ones the list adds included.
    function testApplyMigrationNoEventOnRevertWithPrerequisites(
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
        vm.warp(1000);
        bytes32 next = keccak256(abi.encode(migration));
        Prerequisite[] memory applied = one(other, namespace, prerequisite);

        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.PrerequisiteNotApplied.selector, other, namespace, prerequisite)
        );
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migration, headThen(writer, namespace, MIGRATION_HEAD_GENESIS, applied));
        assertEq(vm.getRecordedLogs().length, 0);

        vm.recordLogs();
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroWriter.selector));
        vm.prank(writer);
        sRegistry.applyMigration(
            namespace,
            migration,
            headThen(writer, namespace, MIGRATION_HEAD_GENESIS, one(address(0), namespace, prerequisite))
        );
        assertEq(vm.getRecordedLogs().length, 0);

        applyUnder(other, namespace, prerequisite);
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migration, headThen(writer, namespace, MIGRATION_HEAD_GENESIS, applied));

        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.MigrationAlreadyApplied.selector, writer, namespace, migration)
        );
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migration, headThen(writer, namespace, migration, applied));
        assertEq(vm.getRecordedLogs().length, 0);

        vm.recordLogs();
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(namespace, bytes32(0), headThen(writer, namespace, migration, applied));
        assertEq(vm.getRecordedLogs().length, 0);

        vm.recordLogs();
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.GenesisMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(namespace, MIGRATION_HEAD_GENESIS, headThen(writer, namespace, migration, applied));
        assertEq(vm.getRecordedLogs().length, 0);

        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.UnexpectedMigrationHead.selector,
                writer,
                namespace,
                MIGRATION_HEAD_GENESIS,
                migration
            )
        );
        vm.prank(writer);
        sRegistry.applyMigration(namespace, next, headThen(writer, namespace, MIGRATION_HEAD_GENESIS, applied));
        assertEq(vm.getRecordedLogs().length, 0);

        vm.recordLogs();
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroTimestamp.selector));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(namespace, next, 0, headThen(writer, namespace, migration, applied));
        assertEq(vm.getRecordedLogs().length, 0);

        vm.recordLogs();
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.FutureTimestamp.selector, 1001, 1000));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(namespace, next, 1001, headThen(writer, namespace, migration, applied));
        assertEq(vm.getRecordedLogs().length, 0);

        vm.recordLogs();
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.TimestampBeforeHead.selector, 999, 1000));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(namespace, next, 999, headThen(writer, namespace, migration, applied));
        assertEq(vm.getRecordedLogs().length, 0);
    }

    /// An empty list names no head, so it is refused as a zero head on an
    /// empty line and on a used one, by both writes, and records nothing.
    function testApplyMigrationEmptyListReverts(
        address writer,
        bytes32 namespace,
        bytes32 migrationA,
        bytes32 migrationB
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.assume(migrationA != migrationB);
        vm.warp(1000);
        Prerequisite[] memory empty = new Prerequisite[](0);

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.UnexpectedMigrationHead.selector,
                writer,
                namespace,
                bytes32(0),
                MIGRATION_HEAD_GENESIS
            )
        );
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationA, empty);
        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.UnexpectedMigrationHead.selector,
                writer,
                namespace,
                bytes32(0),
                MIGRATION_HEAD_GENESIS
            )
        );
        vm.prank(writer);
        sRegistry.applyMigrationHistory(namespace, migrationA, 1, empty);
        assertEq(sRegistry.applied(writer, namespace, migrationA), 0);

        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationA, onto(writer, namespace, MIGRATION_HEAD_GENESIS));

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.UnexpectedMigrationHead.selector, writer, namespace, bytes32(0), migrationA
            )
        );
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationB, empty);
        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.UnexpectedMigrationHead.selector, writer, namespace, bytes32(0), migrationA
            )
        );
        vm.prank(writer);
        sRegistry.applyMigrationHistory(namespace, migrationB, 1000, empty);
        assertEq(sRegistry.applied(writer, namespace, migrationB), 0);
        assertEq(sRegistry.head(writer, namespace), migrationA);
    }

    /// The first entry is the caller's own head, so one under any other
    /// writer is refused even when its migration is exactly the head. The
    /// error names the migration handed in, which is the head itself.
    function testApplyMigrationFirstEntryUnderAnotherWriterReverts(
        address writer,
        bytes32 namespace,
        address other,
        bytes32 migrationA,
        bytes32 migrationB
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        vm.assume(other != address(0));
        vm.assume(writer != other);
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.assume(migrationA != migrationB);
        vm.warp(1000);

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.UnexpectedMigrationHead.selector,
                writer,
                namespace,
                MIGRATION_HEAD_GENESIS,
                MIGRATION_HEAD_GENESIS
            )
        );
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationA, onto(other, namespace, MIGRATION_HEAD_GENESIS));
        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.UnexpectedMigrationHead.selector,
                writer,
                namespace,
                MIGRATION_HEAD_GENESIS,
                MIGRATION_HEAD_GENESIS
            )
        );
        vm.prank(writer);
        sRegistry.applyMigrationHistory(namespace, migrationA, 1, onto(other, namespace, MIGRATION_HEAD_GENESIS));
        assertEq(sRegistry.applied(writer, namespace, migrationA), 0);

        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationA, onto(writer, namespace, MIGRATION_HEAD_GENESIS));

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.UnexpectedMigrationHead.selector, writer, namespace, migrationA, migrationA
            )
        );
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationB, onto(other, namespace, migrationA));
        assertEq(sRegistry.applied(writer, namespace, migrationB), 0);
        assertEq(sRegistry.head(writer, namespace), migrationA);
    }

    /// The first entry is a head, not a record key, so it is never refused as
    /// one: a zero writer, a zero migration or genesis on a used line in
    /// the first entry is a wrong head, not `ZeroWriter`, `ZeroMigration` or
    /// `GenesisMigration`.
    function testApplyMigrationFirstEntryIsNotAKey(
        address writer,
        bytes32 namespace,
        bytes32 migrationA,
        bytes32 migrationB
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.assume(migrationA != migrationB);

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.UnexpectedMigrationHead.selector,
                writer,
                namespace,
                MIGRATION_HEAD_GENESIS,
                MIGRATION_HEAD_GENESIS
            )
        );
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationA, onto(address(0), namespace, MIGRATION_HEAD_GENESIS));

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.UnexpectedMigrationHead.selector,
                writer,
                namespace,
                bytes32(0),
                MIGRATION_HEAD_GENESIS
            )
        );
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationA, onto(writer, namespace, bytes32(0)));

        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationA, onto(writer, namespace, MIGRATION_HEAD_GENESIS));

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.UnexpectedMigrationHead.selector,
                writer,
                namespace,
                MIGRATION_HEAD_GENESIS,
                migrationA
            )
        );
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationB, onto(writer, namespace, MIGRATION_HEAD_GENESIS));
        assertEq(sRegistry.head(writer, namespace), migrationA);
    }

    /// The first entry is checked against the head before the entries after
    /// it are refused as keys or as records: a malformed or unapplied later
    /// entry is reported only once the head holds, and nothing is recorded
    /// either way.
    function testApplyMigrationFirstEntryCheckedBeforeTheLater(
        address writer,
        bytes32 namespace,
        address other,
        bytes32 migration,
        bytes32 prerequisite,
        bytes32 wrongHead
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        vm.assume(other != address(0));
        vm.assume(writer != other);
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, prerequisite);
        vm.assume(migration != prerequisite);
        vm.assume(wrongHead != MIGRATION_HEAD_GENESIS);

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.UnexpectedMigrationHead.selector,
                writer,
                namespace,
                wrongHead,
                MIGRATION_HEAD_GENESIS
            )
        );
        vm.prank(writer);
        sRegistry.applyMigration(
            namespace, migration, headThen(writer, namespace, wrongHead, one(address(0), namespace, prerequisite))
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.UnexpectedMigrationHead.selector,
                writer,
                namespace,
                wrongHead,
                MIGRATION_HEAD_GENESIS
            )
        );
        vm.prank(writer);
        sRegistry.applyMigration(
            namespace, migration, headThen(writer, namespace, wrongHead, one(other, namespace, prerequisite))
        );

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroWriter.selector));
        vm.prank(writer);
        sRegistry.applyMigration(
            namespace,
            migration,
            headThen(writer, namespace, MIGRATION_HEAD_GENESIS, one(address(0), namespace, prerequisite))
        );

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.PrerequisiteNotApplied.selector, other, namespace, prerequisite)
        );
        vm.prank(writer);
        sRegistry.applyMigration(
            namespace,
            migration,
            headThen(writer, namespace, MIGRATION_HEAD_GENESIS, one(other, namespace, prerequisite))
        );
        assertEq(sRegistry.applied(writer, namespace, migration), 0);
    }

    /// An empty list is reported before a migration already applied: a
    /// re-dispatch that names no head is told it named no head, by both
    /// writes.
    function testApplyMigrationEmptyListCheckedBeforeAlreadyApplied(
        address writer,
        bytes32 namespace,
        bytes32 migration
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        vm.warp(1000);

        vm.prank(writer);
        sRegistry.applyMigration(namespace, migration, onto(writer, namespace, MIGRATION_HEAD_GENESIS));

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.UnexpectedMigrationHead.selector, writer, namespace, bytes32(0), migration
            )
        );
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migration, new Prerequisite[](0));
        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.UnexpectedMigrationHead.selector, writer, namespace, bytes32(0), migration
            )
        );
        vm.prank(writer);
        sRegistry.applyMigrationHistory(namespace, migration, 1000, new Prerequisite[](0));
    }

    /// The record is the list as given, on both writes: `appliedAfter`
    /// answers exactly what was passed and `appliedOnto` answers its first
    /// entry's migration.
    function testApplyMigrationRecordIsTheListAsGiven(
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
        vm.assume(migrationA != prerequisite);
        vm.assume(migrationB != prerequisite);
        vm.warp(1000);

        applyUnder(other, namespace, prerequisite);

        Prerequisite[] memory listA =
            headThen(writer, namespace, MIGRATION_HEAD_GENESIS, one(other, namespace, prerequisite));
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationA, listA);
        assertEq(abi.encode(sRegistry.appliedAfter(writer, namespace, migrationA)), abi.encode(listA));
        assertEq(sRegistry.appliedOnto(writer, namespace, migrationA), listA[0].migration);
        assertEq(sRegistry.appliedOnto(writer, namespace, migrationA), MIGRATION_HEAD_GENESIS);

        Prerequisite[] memory listB = headThen(writer, namespace, migrationA, one(other, namespace, prerequisite));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(namespace, migrationB, 1000, listB);
        assertEq(abi.encode(sRegistry.appliedAfter(writer, namespace, migrationB)), abi.encode(listB));
        assertEq(sRegistry.appliedOnto(writer, namespace, migrationB), listB[0].migration);
        assertEq(sRegistry.appliedOnto(writer, namespace, migrationB), migrationA);
    }

    /// An entry after the head in the caller's own line is refused as a
    /// key, before any record is read, on both writes: the head already says
    /// everything about the caller's own line.
    function testApplyMigrationOwnEntryAfterTheHeadReverts(
        address writer,
        bytes32 namespace,
        bytes32 migration,
        bytes32 own
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, own);
        vm.assume(migration != own);
        vm.warp(1000);

        Prerequisite[] memory listed = headThen(writer, namespace, MIGRATION_HEAD_GENESIS, one(writer, namespace, own));
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.OwnPrerequisite.selector, own));
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migration, listed);
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.OwnPrerequisite.selector, own));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(namespace, migration, 1000, listed);

        // Applied or not makes no difference: it is refused as a key.
        applyUnder(writer, namespace, own);
        listed = headThen(writer, namespace, own, one(writer, namespace, own));
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.OwnPrerequisite.selector, own));
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migration, listed);
        assertEq(sRegistry.applied(writer, namespace, migration), 0);
    }

    /// An own-line entry is checked as a key before it is checked as the
    /// caller.s own: a zero or genesis migration under the caller in the
    /// line being written is `ZeroMigration` or `GenesisMigration`, not
    /// `OwnPrerequisite`, on both writes.
    function testApplyMigrationOwnEntryKeyCheckedBeforeOwn(address writer, bytes32 namespace, bytes32 migration)
        external
    {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        vm.warp(1000);

        Prerequisite[] memory zero =
            headThen(writer, namespace, MIGRATION_HEAD_GENESIS, one(writer, namespace, bytes32(0)));
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migration, zero);
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(namespace, migration, 1000, zero);

        Prerequisite[] memory genesis =
            headThen(writer, namespace, MIGRATION_HEAD_GENESIS, one(writer, namespace, MIGRATION_HEAD_GENESIS));
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.GenesisMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migration, genesis);
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.GenesisMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(namespace, migration, 1000, genesis);
        assertEq(sRegistry.applied(writer, namespace, migration), 0);
    }

    /// The caller's own record in another namespace is an ordinary
    /// prerequisite: once applied there, a write in `namespace` waiting on it
    /// lands with the list as given, and the other line's head is where it
    /// was.
    function testApplyMigrationOwnOtherNamespaceIsAPrerequisite(
        address writer,
        bytes32 namespace,
        bytes32 otherNamespace,
        bytes32 migrationA,
        bytes32 migrationB
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        vm.assume(otherNamespace != bytes32(0));
        vm.assume(namespace != otherNamespace);
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.warp(1000);
        applyUnder(writer, otherNamespace, migrationA);
        vm.warp(2000);

        Prerequisite[] memory listed =
            headThen(writer, namespace, MIGRATION_HEAD_GENESIS, one(writer, otherNamespace, migrationA));
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationB, listed);

        assertEq(sRegistry.applied(writer, namespace, migrationB), 2000);
        assertEq(sRegistry.appliedOnto(writer, namespace, migrationB), MIGRATION_HEAD_GENESIS);
        assertEq(abi.encode(sRegistry.appliedAfter(writer, namespace, migrationB)), abi.encode(listed));
        assertEq(sRegistry.head(writer, namespace), migrationB);
        assertEq(sRegistry.head(writer, otherNamespace), migrationA);
        assertEq(sRegistry.applied(writer, otherNamespace, migrationA), 1000);
    }

    /// The caller's own record in another namespace, not applied there, is
    /// refused as any unapplied prerequisite is, naming the line it was
    /// looked for in, by both writes, and nothing is recorded in either line.
    function testApplyMigrationOwnOtherNamespaceUnappliedReverts(
        address writer,
        bytes32 namespace,
        bytes32 otherNamespace,
        bytes32 migrationA,
        bytes32 migrationB
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        vm.assume(otherNamespace != bytes32(0));
        vm.assume(namespace != otherNamespace);
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.warp(1000);
        Prerequisite[] memory listed =
            headThen(writer, namespace, MIGRATION_HEAD_GENESIS, one(writer, otherNamespace, migrationA));

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.PrerequisiteNotApplied.selector, writer, otherNamespace, migrationA
            )
        );
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migrationB, listed);

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.PrerequisiteNotApplied.selector, writer, otherNamespace, migrationA
            )
        );
        vm.prank(writer);
        sRegistry.applyMigrationHistory(namespace, migrationB, 1000, listed);

        assertEq(sRegistry.applied(writer, namespace, migrationB), 0);
        assertEq(sRegistry.head(writer, namespace), MIGRATION_HEAD_GENESIS);
        assertEq(sRegistry.applied(writer, otherNamespace, migrationA), 0);
        assertEq(sRegistry.applied(writer, otherNamespace, migrationB), 0);
        assertEq(sRegistry.head(writer, otherNamespace), MIGRATION_HEAD_GENESIS);
    }

    /// An entry in the caller's own line is `OwnPrerequisite` whatever else
    /// is listed beside it: an applied entry of the caller's in another
    /// namespace, before or after it, changes nothing. On both writes.
    function testApplyMigrationOwnLineEntryIsRefusedBesideAnotherNamespace(
        address writer,
        bytes32 namespace,
        bytes32 otherNamespace,
        bytes32 migration,
        bytes32 own,
        bytes32 elsewhere
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        vm.assume(otherNamespace != bytes32(0));
        vm.assume(namespace != otherNamespace);
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, own);
        LibMigrationFuzz.assumeMigration(vm, elsewhere);
        vm.assume(migration != own);
        vm.warp(1000);
        applyUnder(writer, otherNamespace, elsewhere);

        Prerequisite[] memory ownLast = headThen(
            writer, namespace, MIGRATION_HEAD_GENESIS, two(writer, otherNamespace, elsewhere, writer, namespace, own)
        );
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.OwnPrerequisite.selector, own));
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migration, ownLast);
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.OwnPrerequisite.selector, own));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(namespace, migration, 1000, ownLast);

        Prerequisite[] memory ownFirst = headThen(
            writer, namespace, MIGRATION_HEAD_GENESIS, two(writer, namespace, own, writer, otherNamespace, elsewhere)
        );
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.OwnPrerequisite.selector, own));
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migration, ownFirst);

        assertEq(sRegistry.applied(writer, namespace, migration), 0);
        assertEq(sRegistry.head(writer, namespace), MIGRATION_HEAD_GENESIS);
    }

    /// A prerequisite naming the zero namespace is refused as
    /// `ZeroNamespace`, the same refusal `applied` makes of the same key, by
    /// both writes, and nothing is recorded.
    function testApplyMigrationZeroNamespacePrerequisiteReverts(
        address writer,
        bytes32 namespace,
        address other,
        bytes32 migration,
        bytes32 prerequisite
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        vm.assume(other != address(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, prerequisite);
        vm.warp(1000);
        Prerequisite[] memory listed =
            headThen(writer, namespace, MIGRATION_HEAD_GENESIS, one(other, bytes32(0), prerequisite));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroNamespace.selector));
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migration, listed);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroNamespace.selector));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(namespace, migration, 1000, listed);

        assertEq(sRegistry.applied(writer, namespace, migration), 0);
        assertEq(sRegistry.head(writer, namespace), MIGRATION_HEAD_GENESIS);
    }

    /// A prerequisite is a record in a line, not a migration a writer has
    /// applied somewhere: the same writer and migration under another
    /// namespace is unapplied there, and the entry naming the line it is in
    /// lands.
    function testApplyMigrationPrerequisiteIsTheLineNotTheNamespace(
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
        vm.warp(1000);
        applyUnder(other, namespace, prerequisite);

        Prerequisite[] memory elsewhere =
            headThen(writer, namespace, MIGRATION_HEAD_GENESIS, one(other, otherNamespace, prerequisite));
        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.PrerequisiteNotApplied.selector, other, otherNamespace, prerequisite
            )
        );
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migration, elsewhere);
        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.PrerequisiteNotApplied.selector, other, otherNamespace, prerequisite
            )
        );
        vm.prank(writer);
        sRegistry.applyMigrationHistory(namespace, migration, 1000, elsewhere);
        assertEq(sRegistry.applied(writer, namespace, migration), 0);

        Prerequisite[] memory here =
            headThen(writer, namespace, MIGRATION_HEAD_GENESIS, one(other, namespace, prerequisite));
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migration, here);
        assertEq(sRegistry.applied(writer, namespace, migration), 1000);
        assertEq(abi.encode(sRegistry.appliedAfter(writer, namespace, migration)), abi.encode(here));
    }

    /// The one entry a write with prerequisites logs carries the write's own
    /// namespace, not a prerequisite's: the topics are the writer, the
    /// namespace and the migration, and the data is the moment.
    function testApplyMigrationWithPrerequisitesEventCarriesTheNamespace(
        address writer,
        bytes32 namespace,
        bytes32 otherNamespace,
        address other,
        bytes32 migration,
        bytes32 prerequisite,
        uint32 now_
    ) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        vm.assume(otherNamespace != bytes32(0));
        vm.assume(namespace != otherNamespace);
        vm.assume(other != address(0));
        vm.assume(writer != other);
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, prerequisite);
        vm.assume(now_ != 0);
        vm.warp(now_);
        applyUnder(other, otherNamespace, prerequisite);

        Prerequisite[] memory prerequisites =
            headThen(writer, namespace, MIGRATION_HEAD_GENESIS, one(other, otherNamespace, prerequisite));
        vm.recordLogs();
        vm.prank(writer);
        sRegistry.applyMigration(namespace, migration, prerequisites);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        assertEq(entries.length, 1);
        assertEq(entries[0].emitter, address(sRegistry));
        assertEq(entries[0].topics.length, 4);
        assertEq(entries[0].topics[0], keccak256("Migrated(address,bytes32,bytes32,uint256)"));
        assertEq(entries[0].topics[1], bytes32(uint256(uint160(writer))));
        assertEq(entries[0].topics[2], namespace);
        assertEq(entries[0].topics[3], migration);
        assertEq(entries[0].data, abi.encode(uint256(now_)));
    }
}
