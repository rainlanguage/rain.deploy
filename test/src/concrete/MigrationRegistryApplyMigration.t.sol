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
    /// @param writer The prerequisite's namespace.
    /// @param migration The prerequisite's migration.
    /// @return prerequisites The one-entry list.
    function one(address writer, bytes32 migration) internal pure returns (Prerequisite[] memory prerequisites) {
        prerequisites = new Prerequisite[](1);
        prerequisites[0] = Prerequisite({writer: writer, migration: migration});
    }

    /// Two prerequisites, as a list, in the order given.
    /// @param writerA The first prerequisite's namespace.
    /// @param migrationA The first prerequisite's migration.
    /// @param writerB The second prerequisite's namespace.
    /// @param migrationB The second prerequisite's migration.
    /// @return prerequisites The two-entry list.
    function two(address writerA, bytes32 migrationA, address writerB, bytes32 migrationB)
        internal
        pure
        returns (Prerequisite[] memory prerequisites)
    {
        prerequisites = new Prerequisite[](2);
        prerequisites[0] = Prerequisite({writer: writerA, migration: migrationA});
        prerequisites[1] = Prerequisite({writer: writerB, migration: migrationB});
    }

    /// The list a write under `writer` onto `head` after `prerequisites`
    /// takes, which is the list `appliedAfter` answers for it: the head first,
    /// under the writer, then the prerequisites.
    /// @param writer The namespace the record is in.
    /// @param head The head it is applied onto.
    /// @param prerequisites The records it waits on.
    /// @return list The head-first list.
    function headThen(address writer, bytes32 head, Prerequisite[] memory prerequisites)
        internal
        pure
        returns (Prerequisite[] memory list)
    {
        list = new Prerequisite[](prerequisites.length + 1);
        list[0] = Prerequisite({writer: writer, migration: head});
        for (uint256 i = 0; i < prerequisites.length; i++) {
            list[i + 1] = prerequisites[i];
        }
    }

    /// The list of a write under `writer` onto `head` that waits on nothing
    /// else.
    /// @param writer The namespace the record is in.
    /// @param head The head it is applied onto.
    /// @return The one-entry list.
    function onto(address writer, bytes32 head) internal pure returns (Prerequisite[] memory) {
        return headThen(writer, head, new Prerequisite[](0));
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
                migration: keccak256(abi.encode(seeds[i], "migration"))
            });
            vm.assume(prerequisites[i].writer != address(0));
            LibMigrationFuzz.assumeMigration(vm, prerequisites[i].migration);
        }
    }

    /// Applies `migration` under `writer` onto wherever that namespace is, so
    /// a test can make a prerequisite true without caring what else the
    /// namespace has applied.
    /// @param writer The namespace to apply under.
    /// @param migration The migration to apply.
    function applyUnder(address writer, bytes32 migration) internal {
        // The head is read before the prank: the read is an external call
        // of its own and would consume the prank meant for the write.
        bytes32 head = sRegistry.head(writer);
        vm.prank(writer);
        sRegistry.applyMigration(migration, onto(writer, head));
    }

    /// Anyone may apply, and the record lands under the caller. There is no
    /// authority to be refused by, which is the whole access-control design:
    /// the namespace IS the caller.
    function testApplyMigrationAnyCallerAppliesUnderItself(address writer, bytes32 migration) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeMigration(vm, migration);

        vm.prank(writer);
        sRegistry.applyMigration(migration, onto(writer, MIGRATION_HEAD_GENESIS));

        assertEq(sRegistry.applied(writer, migration), block.timestamp);
    }

    /// `applyMigration` records the block it landed in, which is the whole
    /// difference from a flag: a consumer whose invariant starts AT the
    /// migration — a cliff, a rate change, a grace period — reads the moment
    /// from the chain rather than from a constant somebody guessed.
    function testApplyMigrationStoresTheBlockTimestamp(address writer, bytes32 migration, uint32 timestamp) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        vm.assume(timestamp != 0);
        vm.warp(timestamp);

        vm.prank(writer);
        sRegistry.applyMigration(migration, onto(writer, MIGRATION_HEAD_GENESIS));

        assertEq(sRegistry.applied(writer, migration), timestamp);
    }

    /// Two migrations applied in different blocks carry different timestamps,
    /// and the earlier one does not move when the later one lands. A record is
    /// of the moment it happened, not of the last time anything happened.
    function testApplyMigrationTimestampsAreIndependent(address writer, bytes32 migrationA, bytes32 migrationB)
        external
    {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.assume(migrationA != migrationB);

        vm.warp(1000);
        vm.prank(writer);
        sRegistry.applyMigration(migrationA, onto(writer, MIGRATION_HEAD_GENESIS));

        vm.warp(2000);
        vm.prank(writer);
        sRegistry.applyMigration(migrationB, onto(writer, migrationA));

        assertEq(sRegistry.applied(writer, migrationA), 1000);
        assertEq(sRegistry.applied(writer, migrationB), 2000);
    }

    /// `applyMigration` refuses to write at all in a block whose timestamp is
    /// zero, rather than write a record that `applied` would read back as no
    /// record. The head does not move and the migration can still be applied,
    /// which is the only outcome that leaves the namespace describing something
    /// true.
    function testApplyMigrationZeroBlockReverts(address writer, bytes32 migration) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        vm.warp(0);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroTimestamp.selector));
        vm.prank(writer);
        sRegistry.applyMigration(migration, onto(writer, MIGRATION_HEAD_GENESIS));

        assertEq(sRegistry.applied(writer, migration), 0);
        assertEq(sRegistry.head(writer), MIGRATION_HEAD_GENESIS);

        vm.warp(1);
        vm.prank(writer);
        sRegistry.applyMigration(migration, onto(writer, MIGRATION_HEAD_GENESIS));
        assertEq(sRegistry.applied(writer, migration), 1);
    }

    /// The zero moment is checked after the two id refusals and before anything
    /// about the namespace, on `applyMigration` as on `applyMigrationHistory`. An id is
    /// what a record is ABOUT, so a call with no subject has nothing to say a
    /// moment for; everything after describes a namespace no writable record
    /// will reach.
    function testApplyMigrationZeroBlockCheckedAfterIdsAndBeforeTheNamespace(
        address writer,
        bytes32 migrationA,
        bytes32 migrationB,
        bytes32 anyHead
    ) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.assume(migrationA != migrationB);

        vm.warp(1000);
        vm.prank(writer);
        sRegistry.applyMigration(migrationA, onto(writer, MIGRATION_HEAD_GENESIS));

        vm.warp(0);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(bytes32(0), onto(writer, anyHead));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.GenesisMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, onto(writer, anyHead));

        // Already applied, in a block that can hold no record: told about the
        // moment, because the record could not be written whatever namespace it
        // arrived at.
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroTimestamp.selector));
        vm.prank(writer);
        sRegistry.applyMigration(migrationA, onto(writer, MIGRATION_HEAD_GENESIS));

        // A head the namespace has moved on from, in the same block: told about
        // the moment.
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroTimestamp.selector));
        vm.prank(writer);
        sRegistry.applyMigration(migrationB, onto(writer, MIGRATION_HEAD_GENESIS));
    }

    /// A record is confined to the caller's namespace. Applying under one
    /// writer says nothing about any other, which is what makes a reader's
    /// choice of namespace the whole of who it trusts — a hostile caller can
    /// apply whatever it likes and reach nobody.
    function testApplyMigrationDoesNotReachAnotherNamespace(address writer, address other, bytes32 migration) external {
        vm.assume(writer != address(0));
        vm.assume(other != address(0));
        vm.assume(writer != other);
        LibMigrationFuzz.assumeMigration(vm, migration);

        vm.prank(writer);
        sRegistry.applyMigration(migration, onto(writer, MIGRATION_HEAD_GENESIS));

        assertEq(sRegistry.applied(writer, migration), block.timestamp);
        assertEq(sRegistry.applied(other, migration), 0);
    }

    /// Two writers may apply the same migration id independently, and each
    /// answers only for itself. Ids are opaque and namespaces are unrelated, so
    /// a shared id is not a collision — including for the head, which each
    /// writer advances from its own genesis.
    function testApplyMigrationSameMigrationUnderTwoWriters(address writer, address other, bytes32 migration) external {
        vm.assume(writer != address(0));
        vm.assume(other != address(0));
        vm.assume(writer != other);
        LibMigrationFuzz.assumeMigration(vm, migration);

        vm.prank(writer);
        sRegistry.applyMigration(migration, onto(writer, MIGRATION_HEAD_GENESIS));
        vm.prank(other);
        sRegistry.applyMigration(migration, onto(other, MIGRATION_HEAD_GENESIS));

        assertEq(sRegistry.applied(writer, migration), block.timestamp);
        assertEq(sRegistry.applied(other, migration), block.timestamp);
    }

    /// Migrations are independent within one namespace: applying one says
    /// nothing about any other. This is what a set buys over a high-water mark
    /// — a reader asks about the migration its assertion actually depends on
    /// rather than about a number that stands in for all of them.
    function testApplyMigrationDistinctMigrations(address writer, bytes32 migrationA, bytes32 migrationB) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.assume(migrationA != migrationB);

        vm.prank(writer);
        sRegistry.applyMigration(migrationA, onto(writer, MIGRATION_HEAD_GENESIS));

        assertEq(sRegistry.applied(writer, migrationA), block.timestamp);
        assertEq(sRegistry.applied(writer, migrationB), 0);

        vm.prank(writer);
        sRegistry.applyMigration(migrationB, onto(writer, migrationA));

        assertEq(sRegistry.applied(writer, migrationA), block.timestamp);
        assertEq(sRegistry.applied(writer, migrationB), block.timestamp);
    }

    /// A successful application makes its migration the namespace's new head,
    /// which is what the next one has to name.
    function testApplyMigrationAdvancesTheHead(address writer, bytes32 migrationA, bytes32 migrationB) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.assume(migrationA != migrationB);

        assertEq(sRegistry.head(writer), MIGRATION_HEAD_GENESIS);

        vm.prank(writer);
        sRegistry.applyMigration(migrationA, onto(writer, MIGRATION_HEAD_GENESIS));
        assertEq(sRegistry.head(writer), migrationA);

        vm.prank(writer);
        sRegistry.applyMigration(migrationB, onto(writer, migrationA));
        assertEq(sRegistry.head(writer), migrationB);
    }

    /// Applying onto a head the namespace is not at is refused. This is what
    /// blocks a SKIPPED step: a script names its predecessor, so a chain that
    /// never got that predecessor fails at the moment of applying rather than
    /// diverging silently from every chain that did.
    function testApplyMigrationSkippedPredecessorReverts(
        address writer,
        bytes32 migrationA,
        bytes32 migrationB,
        bytes32 skipped
    ) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        LibMigrationFuzz.assumeMigration(vm, skipped);
        vm.assume(migrationA != migrationB);
        vm.assume(skipped != migrationA);
        vm.assume(skipped != migrationB);

        vm.prank(writer);
        sRegistry.applyMigration(migrationA, onto(writer, MIGRATION_HEAD_GENESIS));

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.UnexpectedMigrationHead.selector, writer, skipped, migrationA)
        );
        vm.prank(writer);
        sRegistry.applyMigration(migrationB, onto(writer, skipped));

        assertEq(sRegistry.applied(writer, migrationB), 0);
        assertEq(sRegistry.head(writer), migrationA);
    }

    /// Genesis stops being an acceptable head the moment anything is applied,
    /// so a first-migration script re-run against a namespace that has moved on
    /// fails rather than restarting the sequence.
    function testApplyMigrationOntoGenesisAfterFirstReverts(address writer, bytes32 migrationA, bytes32 migrationB)
        external
    {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.assume(migrationA != migrationB);

        vm.prank(writer);
        sRegistry.applyMigration(migrationA, onto(writer, MIGRATION_HEAD_GENESIS));

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.UnexpectedMigrationHead.selector, writer, MIGRATION_HEAD_GENESIS, migrationA
            )
        );
        vm.prank(writer);
        sRegistry.applyMigration(migrationB, onto(writer, MIGRATION_HEAD_GENESIS));
    }

    /// A head belongs to one namespace. One writer advancing its head leaves
    /// every other writer's exactly where it was, so a second consumer's
    /// migrations are not blocked or unblocked by the first's.
    function testApplyMigrationHeadIsPerWriter(address writer, address other, bytes32 migrationA, bytes32 migrationB)
        external
    {
        vm.assume(writer != address(0));
        vm.assume(other != address(0));
        vm.assume(writer != other);
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.assume(migrationA != migrationB);

        vm.prank(writer);
        sRegistry.applyMigration(migrationA, onto(writer, MIGRATION_HEAD_GENESIS));

        assertEq(sRegistry.head(other), MIGRATION_HEAD_GENESIS);

        // The other namespace is still at genesis, so `migrationA` is not the
        // head there and naming it is refused.
        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.UnexpectedMigrationHead.selector, other, migrationA, MIGRATION_HEAD_GENESIS
            )
        );
        vm.prank(other);
        sRegistry.applyMigration(migrationB, onto(other, migrationA));

        vm.prank(other);
        sRegistry.applyMigration(migrationB, onto(other, MIGRATION_HEAD_GENESIS));
        assertEq(sRegistry.head(other), migrationB);
        assertEq(sRegistry.head(writer), migrationA);
    }

    /// A zero head never matches anything, including on a namespace that has
    /// applied nothing — which is the whole reason genesis is not zero. An
    /// uninitialised predecessor constant is a revert in every namespace state,
    /// rather than a successful first application on every chain that happens
    /// to be empty.
    function testApplyMigrationZeroHeadRevertsOnEmptyNamespace(address writer, bytes32 migration) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeMigration(vm, migration);

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.UnexpectedMigrationHead.selector, writer, bytes32(0), MIGRATION_HEAD_GENESIS
            )
        );
        vm.prank(writer);
        sRegistry.applyMigration(migration, onto(writer, bytes32(0)));

        assertEq(sRegistry.applied(writer, migration), 0);
    }

    /// And on a namespace that has applied something.
    function testApplyMigrationZeroHeadRevertsOnUsedNamespace(address writer, bytes32 migrationA, bytes32 migrationB)
        external
    {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.assume(migrationA != migrationB);

        vm.prank(writer);
        sRegistry.applyMigration(migrationA, onto(writer, MIGRATION_HEAD_GENESIS));

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.UnexpectedMigrationHead.selector, writer, bytes32(0), migrationA
            )
        );
        vm.prank(writer);
        sRegistry.applyMigration(migrationB, onto(writer, bytes32(0)));
    }

    /// Applying twice is refused. This is what makes running a migration twice
    /// fail rather than repeat: a re-dispatched script cannot quietly apply
    /// its way to looking like a first run.
    function testApplyMigrationTwiceReverts(address writer, bytes32 migration) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeMigration(vm, migration);

        vm.prank(writer);
        sRegistry.applyMigration(migration, onto(writer, MIGRATION_HEAD_GENESIS));

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.MigrationAlreadyApplied.selector, writer, migration)
        );
        vm.prank(writer);
        sRegistry.applyMigration(migration, onto(writer, MIGRATION_HEAD_GENESIS));

        assertEq(sRegistry.applied(writer, migration), block.timestamp);
    }

    /// The head does NOT subsume the already-applied refusal. Re-applying a
    /// migration whose successor has since landed presents a head that matches
    /// perfectly, and is still refused — otherwise the head would move BACKWARDS
    /// and the original timestamp would be overwritten, which is a record
    /// un-happening.
    function testApplyMigrationAgainOnMatchingHeadReverts(address writer, bytes32 migrationA, bytes32 migrationB)
        external
    {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.assume(migrationA != migrationB);

        vm.warp(1000);
        vm.prank(writer);
        sRegistry.applyMigration(migrationA, onto(writer, MIGRATION_HEAD_GENESIS));
        vm.prank(writer);
        sRegistry.applyMigration(migrationB, onto(writer, migrationA));

        // The namespace really is at `migrationB`, so the head this names is
        // correct and only the already-applied refusal can stop it.
        assertEq(sRegistry.head(writer), migrationB);
        vm.warp(2000);
        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.MigrationAlreadyApplied.selector, writer, migrationA)
        );
        vm.prank(writer);
        sRegistry.applyMigration(migrationA, onto(writer, migrationB));

        assertEq(sRegistry.head(writer), migrationB);
        assertEq(sRegistry.applied(writer, migrationA), 1000);
    }

    /// The already-applied refusal is checked BEFORE the head, so a
    /// re-dispatched script — which names the same head it named the first time,
    /// long since moved on — is told that its migration already ran rather than
    /// told the namespace is somewhere else and left to work out why.
    function testApplyMigrationAlreadyAppliedCheckedBeforeHead(address writer, bytes32 migrationA, bytes32 migrationB)
        external
    {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.assume(migrationA != migrationB);

        vm.prank(writer);
        sRegistry.applyMigration(migrationA, onto(writer, MIGRATION_HEAD_GENESIS));
        vm.prank(writer);
        sRegistry.applyMigration(migrationB, onto(writer, migrationA));

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.MigrationAlreadyApplied.selector, writer, migrationA)
        );
        vm.prank(writer);
        sRegistry.applyMigration(migrationA, onto(writer, MIGRATION_HEAD_GENESIS));
    }

    /// A migration another writer has already applied is still a FIRST record
    /// for this one. The refusal is per namespace, not global, or one consumer
    /// choosing a common id would lock every other consumer out of it.
    function testApplyMigrationTwiceIsPerWriter(address writer, address other, bytes32 migration) external {
        vm.assume(writer != address(0));
        vm.assume(other != address(0));
        vm.assume(writer != other);
        LibMigrationFuzz.assumeMigration(vm, migration);

        vm.prank(writer);
        sRegistry.applyMigration(migration, onto(writer, MIGRATION_HEAD_GENESIS));

        vm.prank(other);
        sRegistry.applyMigration(migration, onto(other, MIGRATION_HEAD_GENESIS));

        assertEq(sRegistry.applied(other, migration), block.timestamp);
    }

    /// The zero migration id is refused. It is what an uninitialised `bytes32`
    /// constant reads as, and there is deliberately no way to apply one, which
    /// is what lets `applied` refuse it as a mistake rather than have to answer
    /// about it.
    function testApplyMigrationZeroMigrationReverts(address writer) external {
        vm.assume(writer != address(0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(bytes32(0), onto(writer, MIGRATION_HEAD_GENESIS));
    }

    /// The zero id is refused BEFORE the already-applied read and before the
    /// head, so it is always reported as `ZeroMigration` and never as anything
    /// about where the namespace is.
    ///
    /// Fuzzed over the head against BOTH an empty namespace and one that has
    /// moved on, for the same reason
    /// `testApplyMigrationGenesisMigrationRevertsOnAnyHead` is: one namespace
    /// state cannot tell the orderings apart, because a head the namespace
    /// happens to be at is accepted whichever check runs first, and the two
    /// states here have different heads so no fuzzed head matches both.
    ///
    /// The already-applied read can never answer anything but zero for this id
    /// — this refusal is what keeps the zero id out of the records in the first
    /// place — so what the second call pins is the reachable half of the same
    /// claim: the refusal is a fact about the ID, not about the state of the
    /// namespace it arrives at.
    function testApplyMigrationZeroMigrationCheckedFirst(address writer, bytes32 anyHead, bytes32 migration) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeMigration(vm, migration);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(bytes32(0), onto(writer, anyHead));

        // A namespace that has moved on: the zero id is still reported as
        // `ZeroMigration` rather than as anything about the head or about what
        // has already been applied.
        vm.prank(writer);
        sRegistry.applyMigration(migration, onto(writer, MIGRATION_HEAD_GENESIS));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(bytes32(0), onto(writer, anyHead));
    }

    /// Genesis is a head, not a migration, and applying it is refused. It would
    /// otherwise leave the namespace's head holding the exact value an empty
    /// namespace reads as, so a namespace that had applied something would be
    /// indistinguishable from one that had not — and the next first-migration
    /// script would be accepted against it.
    function testApplyMigrationGenesisMigrationReverts(address writer) external {
        vm.assume(writer != address(0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.GenesisMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, onto(writer, MIGRATION_HEAD_GENESIS));

        assertEq(sRegistry.head(writer), MIGRATION_HEAD_GENESIS);
    }

    /// Refused whatever head it is applied onto, so it is a fact about the id
    /// rather than about where the namespace happens to be. That means a head
    /// the namespace is NOT at as much as one it is: the refusal is checked
    /// before the head, so a caller that has confused a head for a migration is
    /// told which of the two it got wrong rather than sent to look at where the
    /// namespace has got to.
    ///
    /// Fuzzed over the head for the same reason
    /// `testApplyMigrationZeroMigrationCheckedFirst` is: a matching head alone
    /// cannot tell the two orderings apart.
    function testApplyMigrationGenesisMigrationRevertsOnAnyHead(address writer, bytes32 migration, bytes32 anyHead)
        external
    {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeMigration(vm, migration);

        // An empty namespace, whose head is genesis: still refused onto a head
        // that does not match it.
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.GenesisMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, onto(writer, anyHead));

        vm.prank(writer);
        sRegistry.applyMigration(migration, onto(writer, MIGRATION_HEAD_GENESIS));

        // A namespace that has moved: same refusal, onto the head it is at and
        // onto any other.
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.GenesisMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, onto(writer, migration));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.GenesisMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, onto(writer, anyHead));

        assertEq(sRegistry.head(writer), migration);
    }

    /// Ids are opaque: nothing about a migration's bytes changes how it is
    /// stored or read, including ids no hashing convention would produce.
    function testApplyMigrationOpaqueMigrationIds(address writer) external {
        vm.assume(writer != address(0));

        bytes32[2] memory migrations = [bytes32(uint256(1)), bytes32(type(uint256).max)];
        for (uint256 i = 0; i < migrations.length; i++) {
            MigrationRegistry registry = new MigrationRegistry();
            vm.prank(writer);
            registry.applyMigration(migrations[i], onto(writer, MIGRATION_HEAD_GENESIS));
            assertEq(registry.applied(writer, migrations[i]), block.timestamp);
            assertEq(registry.head(writer), migrations[i]);
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
    function testApplyMigrationHistoryEvent(address writer, bytes32 migration, uint32 appliedAt, uint32 writtenAt)
        external
    {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        vm.assume(appliedAt != 0);
        vm.assume(writtenAt > appliedAt);
        vm.warp(writtenAt);

        vm.recordLogs();
        vm.prank(writer);
        sRegistry.applyMigrationHistory(migration, appliedAt, onto(writer, MIGRATION_HEAD_GENESIS));
        Vm.Log[] memory entries = vm.getRecordedLogs();

        assertEq(entries.length, 1);
        assertEq(entries[0].emitter, address(sRegistry));
        assertEq(entries[0].topics.length, 3);
        assertEq(entries[0].topics[0], keccak256("Migrated(address,bytes32,uint256)"));
        assertEq(entries[0].topics[1], bytes32(uint256(uint160(writer))));
        assertEq(entries[0].topics[2], migration);
        assertEq(entries[0].data, abi.encode(uint256(appliedAt)));
    }

    /// `applyMigration` emits the same event, carrying the block it stamped — so
    /// a reader of the log never has to know which of the two wrote a record.
    function testApplyMigrationEvent(address writer, bytes32 migration, uint32 now_) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        vm.assume(now_ != 0);
        vm.warp(now_);

        vm.recordLogs();
        vm.prank(writer);
        sRegistry.applyMigration(migration, onto(writer, MIGRATION_HEAD_GENESIS));
        Vm.Log[] memory entries = vm.getRecordedLogs();

        assertEq(entries.length, 1);
        assertEq(entries[0].topics[0], keccak256("Migrated(address,bytes32,uint256)"));
        assertEq(entries[0].data, abi.encode(uint256(now_)));
    }

    /// A refused write emits nothing, so a failed apply can never be
    /// mistaken for a record by anything reading the logs — which for a
    /// re-dispatched migration is exactly the mistake that matters.
    function testApplyMigrationNoEventOnRevert(address writer, bytes32 migration) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        vm.warp(1000);

        vm.prank(writer);
        sRegistry.applyMigration(migration, onto(writer, MIGRATION_HEAD_GENESIS));

        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.MigrationAlreadyApplied.selector, writer, migration)
        );
        vm.prank(writer);
        sRegistry.applyMigration(migration, onto(writer, MIGRATION_HEAD_GENESIS));
        assertEq(vm.getRecordedLogs().length, 0);

        vm.recordLogs();
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(bytes32(0), onto(writer, migration));
        assertEq(vm.getRecordedLogs().length, 0);

        vm.recordLogs();
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.GenesisMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, onto(writer, migration));
        assertEq(vm.getRecordedLogs().length, 0);

        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.UnexpectedMigrationHead.selector, writer, MIGRATION_HEAD_GENESIS, migration
            )
        );
        vm.prank(writer);
        sRegistry.applyMigration(keccak256(abi.encode(migration)), onto(writer, MIGRATION_HEAD_GENESIS));
        assertEq(vm.getRecordedLogs().length, 0);

        vm.recordLogs();
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroTimestamp.selector));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(keccak256(abi.encode(migration)), 0, onto(writer, migration));
        assertEq(vm.getRecordedLogs().length, 0);

        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.FutureTimestamp.selector, block.timestamp + 1, block.timestamp)
        );
        vm.prank(writer);
        sRegistry.applyMigrationHistory(keccak256(abi.encode(migration)), block.timestamp + 1, onto(writer, migration));
        assertEq(vm.getRecordedLogs().length, 0);

        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.TimestampBeforeHead.selector, block.timestamp - 1, 1000)
        );
        vm.prank(writer);
        sRegistry.applyMigrationHistory(keccak256(abi.encode(migration)), block.timestamp - 1, onto(writer, migration));
        assertEq(vm.getRecordedLogs().length, 0);
    }

    /// `applyMigrationHistory` records the moment the CALLER supplied, which is
    /// what lets a migration that already ran be recorded with the time it ran
    /// rather than the time it was written down. The block the record lands in
    /// is not the value, and a record written long after the fact says so.
    function testApplyMigrationHistoryRecordsTheSuppliedMoment(
        address writer,
        bytes32 migration,
        uint32 appliedAt,
        uint32 writtenAt
    ) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        vm.assume(appliedAt != 0);
        vm.assume(writtenAt > appliedAt);
        vm.warp(writtenAt);

        vm.prank(writer);
        sRegistry.applyMigrationHistory(migration, appliedAt, onto(writer, MIGRATION_HEAD_GENESIS));

        assertEq(sRegistry.applied(writer, migration), appliedAt);
        assertTrue(sRegistry.applied(writer, migration) != block.timestamp);
    }

    /// The moment of the current block is an ordinary value for the parameter,
    /// which is what a caller reaching for `applyMigrationHistory` to record a
    /// migration running now passes.
    function testApplyMigrationHistoryCurrentBlockIsAccepted(address writer, bytes32 migration, uint32 now_) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        vm.assume(now_ != 0);
        vm.warp(now_);

        vm.prank(writer);
        sRegistry.applyMigrationHistory(migration, block.timestamp, onto(writer, MIGRATION_HEAD_GENESIS));

        assertEq(sRegistry.applied(writer, migration), now_);
    }

    /// The two writes make the SAME record when the moment is this block, down
    /// to the head each was applied onto — which is what makes `applyMigration`
    /// `applyMigrationHistory` with today's moment rather than a second way to
    /// write a record.
    function testApplyMigrationAndHistoryWriteTheSameRecord(
        address writer,
        bytes32 migrationA,
        bytes32 migrationB,
        uint32 now_
    ) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.assume(migrationA != migrationB);
        vm.assume(now_ != 0);
        vm.warp(now_);

        MigrationRegistry stamping = new MigrationRegistry();
        MigrationRegistry supplied = new MigrationRegistry();

        vm.prank(writer);
        stamping.applyMigration(migrationA, onto(writer, MIGRATION_HEAD_GENESIS));
        vm.prank(writer);
        supplied.applyMigrationHistory(migrationA, block.timestamp, onto(writer, MIGRATION_HEAD_GENESIS));

        vm.prank(writer);
        stamping.applyMigration(migrationB, onto(writer, migrationA));
        vm.prank(writer);
        supplied.applyMigrationHistory(migrationB, block.timestamp, onto(writer, migrationA));

        assertEq(stamping.applied(writer, migrationB), supplied.applied(writer, migrationB));
        assertEq(stamping.appliedOnto(writer, migrationB), supplied.appliedOnto(writer, migrationB));
        assertEq(stamping.head(writer), supplied.head(writer));
    }

    /// A moment that has not arrived is refused. A record says a migration HAS
    /// run, so a future one is not a late record of anything, and a consumer
    /// measuring an interval since the migration would be subtracting a moment
    /// later than the one it is measuring from.
    function testApplyMigrationHistoryFutureTimestampReverts(
        address writer,
        bytes32 migration,
        uint32 now_,
        uint256 appliedAt
    ) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        vm.warp(now_);
        appliedAt = bound(appliedAt, uint256(now_) + 1, type(uint256).max);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.FutureTimestamp.selector, appliedAt, uint256(now_)));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(migration, appliedAt, onto(writer, MIGRATION_HEAD_GENESIS));

        assertEq(sRegistry.applied(writer, migration), 0);
        assertEq(sRegistry.appliedOnto(writer, migration), bytes32(0));
        assertEq(sRegistry.head(writer), MIGRATION_HEAD_GENESIS);
    }

    /// One second past the current block is refused, and the current block is
    /// not: the boundary is the block's own timestamp, inclusive.
    function testApplyMigrationHistoryFutureBoundary(address writer, bytes32 migration, uint32 now_) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        vm.assume(now_ != 0);
        vm.warp(now_);

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.FutureTimestamp.selector, uint256(now_) + 1, uint256(now_))
        );
        vm.prank(writer);
        sRegistry.applyMigrationHistory(migration, uint256(now_) + 1, onto(writer, MIGRATION_HEAD_GENESIS));

        vm.prank(writer);
        sRegistry.applyMigrationHistory(migration, uint256(now_), onto(writer, MIGRATION_HEAD_GENESIS));
        assertEq(sRegistry.applied(writer, migration), now_);
    }

    /// A supplied zero is refused, rather than written as a record that
    /// `applied` would read back as no record. The head does not move and the
    /// migration can still be applied.
    function testApplyMigrationHistoryZeroTimestampReverts(address writer, bytes32 migration, uint32 now_) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        vm.assume(now_ != 0);
        vm.warp(now_);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroTimestamp.selector));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(migration, 0, onto(writer, MIGRATION_HEAD_GENESIS));

        assertEq(sRegistry.applied(writer, migration), 0);
        assertEq(sRegistry.head(writer), MIGRATION_HEAD_GENESIS);

        vm.prank(writer);
        sRegistry.applyMigrationHistory(migration, 1, onto(writer, MIGRATION_HEAD_GENESIS));
        assertEq(sRegistry.applied(writer, migration), 1);
    }

    /// A block whose timestamp is zero can hold no record at all: zero is
    /// refused as a moment, and every other moment is still in the future. The
    /// head does not move, so the namespace goes on describing something true
    /// and the migration is still applicable once the clock has moved.
    function testApplyMigrationHistoryZeroBlockRecordsNothing(address writer, bytes32 migration, uint256 appliedAt)
        external
    {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        vm.assume(appliedAt != 0);
        vm.warp(0);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroTimestamp.selector));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(migration, 0, onto(writer, MIGRATION_HEAD_GENESIS));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.FutureTimestamp.selector, appliedAt, 0));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(migration, appliedAt, onto(writer, MIGRATION_HEAD_GENESIS));

        assertEq(sRegistry.applied(writer, migration), 0);
        assertEq(sRegistry.head(writer), MIGRATION_HEAD_GENESIS);

        vm.warp(1);
        vm.prank(writer);
        sRegistry.applyMigrationHistory(migration, 1, onto(writer, MIGRATION_HEAD_GENESIS));
        assertEq(sRegistry.applied(writer, migration), 1);
    }

    /// The zero moment is refused BEFORE anything about the namespace is read,
    /// so an uninitialised argument is reported as itself rather than as
    /// whatever the namespace happens to make of it. Fuzzed over the head and
    /// checked against a namespace that has moved on, because a head the
    /// namespace happens to be at is accepted whichever check runs first.
    function testApplyMigrationHistoryZeroTimestampCheckedBeforeTheNamespace(
        address writer,
        bytes32 migrationA,
        bytes32 migrationB,
        bytes32 anyHead
    ) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.assume(migrationA != migrationB);

        vm.prank(writer);
        sRegistry.applyMigrationHistory(migrationA, block.timestamp, onto(writer, MIGRATION_HEAD_GENESIS));

        // Already applied, and a zero moment: told about the moment.
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroTimestamp.selector));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(migrationA, 0, onto(writer, MIGRATION_HEAD_GENESIS));

        // A head that has moved on, and a zero moment: told about the moment.
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroTimestamp.selector));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(migrationB, 0, onto(writer, anyHead));
    }

    /// The two id refusals come before the moment, so a caller that has zeroed
    /// both an id and a moment is told about the id: an id is what the record is
    /// ABOUT, and a call with no subject has nothing to say a moment for.
    function testApplyMigrationHistoryIdCheckedBeforeTimestamp(address writer, bytes32 anyHead) external {
        vm.assume(writer != address(0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(bytes32(0), 0, onto(writer, anyHead));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.GenesisMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(MIGRATION_HEAD_GENESIS, 0, onto(writer, anyHead));
    }

    /// The refusals that describe the NAMESPACE come before the future-moment
    /// one, so a re-dispatched script is told its migration already ran, and a
    /// script at the wrong point in the sequence is told where the namespace is,
    /// rather than either of them being sent to look at a clock.
    function testApplyMigrationHistoryNamespaceCheckedBeforeTheFuture(
        address writer,
        bytes32 migrationA,
        bytes32 migrationB,
        bytes32 skipped
    ) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        LibMigrationFuzz.assumeMigration(vm, skipped);
        vm.assume(migrationA != migrationB);
        vm.assume(skipped != migrationA);
        vm.assume(skipped != migrationB);

        vm.warp(9000);
        vm.prank(writer);
        sRegistry.applyMigrationHistory(migrationA, 5000, onto(writer, MIGRATION_HEAD_GENESIS));

        // Already applied, and in the future: told it already ran.
        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.MigrationAlreadyApplied.selector, writer, migrationA)
        );
        vm.prank(writer);
        sRegistry.applyMigrationHistory(migrationA, 9001, onto(writer, migrationA));

        // The wrong head, and in the future: told where the namespace is.
        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.UnexpectedMigrationHead.selector, writer, skipped, migrationA)
        );
        vm.prank(writer);
        sRegistry.applyMigrationHistory(migrationB, 9001, onto(writer, skipped));
    }

    /// A record may NOT carry a moment earlier than the record it is applied
    /// onto. Nothing is written and the head does not move, so the migration is
    /// still applicable with a moment the chain admits.
    function testApplyMigrationHistoryMomentBeforeHeadReverts(
        address writer,
        bytes32 migrationA,
        bytes32 migrationB,
        uint32 now_,
        uint256 earlier
    ) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.assume(migrationA != migrationB);
        vm.assume(now_ > 1);
        vm.warp(now_);
        earlier = bound(earlier, 1, uint256(now_) - 1);

        vm.prank(writer);
        sRegistry.applyMigrationHistory(migrationA, uint256(now_), onto(writer, MIGRATION_HEAD_GENESIS));

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.TimestampBeforeHead.selector, earlier, uint256(now_))
        );
        vm.prank(writer);
        sRegistry.applyMigrationHistory(migrationB, earlier, onto(writer, migrationA));

        assertEq(sRegistry.applied(writer, migrationB), 0);
        assertEq(sRegistry.appliedOnto(writer, migrationB), bytes32(0));
        assertEq(sRegistry.head(writer), migrationA);

        vm.prank(writer);
        sRegistry.applyMigrationHistory(migrationB, uint256(now_), onto(writer, migrationA));
        assertEq(sRegistry.applied(writer, migrationB), uint256(now_));
        assertEq(sRegistry.head(writer), migrationB);
    }

    /// The boundary is the head's own moment, inclusive: exactly it is
    /// accepted, and one second below it is refused.
    function testApplyMigrationHistoryBeforeHeadBoundary(
        address writer,
        bytes32 migrationA,
        bytes32 migrationB,
        uint32 headAppliedAt
    ) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.assume(migrationA != migrationB);
        vm.assume(headAppliedAt > 1);
        vm.warp(headAppliedAt);

        vm.prank(writer);
        sRegistry.applyMigrationHistory(migrationA, uint256(headAppliedAt), onto(writer, MIGRATION_HEAD_GENESIS));

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.TimestampBeforeHead.selector, uint256(headAppliedAt) - 1, uint256(headAppliedAt)
            )
        );
        vm.prank(writer);
        sRegistry.applyMigrationHistory(migrationB, uint256(headAppliedAt) - 1, onto(writer, migrationA));

        vm.prank(writer);
        sRegistry.applyMigrationHistory(migrationB, uint256(headAppliedAt), onto(writer, migrationA));
        assertEq(sRegistry.applied(writer, migrationB), uint256(headAppliedAt));
    }

    /// A moment AFTER the head's is the ordinary case, and it is the moment the
    /// record carries rather than anything derived from the one before it.
    function testApplyMigrationHistoryMomentAfterHeadIsAccepted(
        address writer,
        bytes32 migrationA,
        bytes32 migrationB,
        uint32 first,
        uint32 second
    ) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.assume(migrationA != migrationB);
        vm.assume(first != 0);
        vm.assume(second > first);
        vm.warp(second);

        vm.prank(writer);
        sRegistry.applyMigrationHistory(migrationA, uint256(first), onto(writer, MIGRATION_HEAD_GENESIS));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(migrationB, uint256(second), onto(writer, migrationA));

        assertEq(sRegistry.applied(writer, migrationA), uint256(first));
        assertEq(sRegistry.applied(writer, migrationB), uint256(second));
        assertEq(sRegistry.head(writer), migrationB);
    }

    /// The first migration in a namespace is compared to nothing. It is applied
    /// onto `MIGRATION_HEAD_GENESIS`, which is refused as a migration and so
    /// holds no record in any namespace ever — which is why the smallest moment
    /// a record may carry is accepted at genesis in the latest block.
    function testApplyMigrationHistoryNoMomentBoundAtGenesis(address writer, bytes32 migration, uint32 now_) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        vm.assume(now_ != 0);
        vm.warp(now_);

        // Nothing can put a record at genesis to be bounded by.
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.GenesisMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(MIGRATION_HEAD_GENESIS, uint256(now_), onto(writer, MIGRATION_HEAD_GENESIS));

        vm.prank(writer);
        sRegistry.applyMigrationHistory(migration, 1, onto(writer, MIGRATION_HEAD_GENESIS));

        assertEq(sRegistry.applied(writer, migration), 1);
        assertEq(sRegistry.appliedOnto(writer, migration), MIGRATION_HEAD_GENESIS);
    }

    /// The refusals that read the namespace's KEYS come before the one that
    /// reads its RECORD, so a re-dispatched script is told its migration already
    /// ran and a script at the wrong point is told where the namespace is,
    /// rather than either being told about the moment of a record it was never
    /// going to be chained onto. The zero moment still comes before all of them.
    function testApplyMigrationHistoryNamespaceCheckedBeforeTheHeadsMoment(
        address writer,
        bytes32 migrationA,
        bytes32 migrationB,
        bytes32 skipped
    ) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        LibMigrationFuzz.assumeMigration(vm, skipped);
        vm.assume(migrationA != migrationB);
        vm.assume(skipped != migrationA);
        vm.assume(skipped != migrationB);

        vm.warp(9000);
        vm.prank(writer);
        sRegistry.applyMigrationHistory(migrationA, 9000, onto(writer, MIGRATION_HEAD_GENESIS));

        // Already applied, and before the head's moment: told it already ran.
        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.MigrationAlreadyApplied.selector, writer, migrationA)
        );
        vm.prank(writer);
        sRegistry.applyMigrationHistory(migrationA, 1, onto(writer, migrationA));

        // The wrong head, and before the head's moment: told where the
        // namespace is.
        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.UnexpectedMigrationHead.selector, writer, skipped, migrationA)
        );
        vm.prank(writer);
        sRegistry.applyMigrationHistory(migrationB, 1, onto(writer, skipped));

        // A zero moment, which is also before the head's: told about the zero.
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroTimestamp.selector));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(migrationB, 0, onto(writer, migrationA));

        // With nothing else wrong, the head's moment is what refuses it.
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.TimestampBeforeHead.selector, 1, 9000));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(migrationB, 1, onto(writer, migrationA));
    }

    /// A head's moment bounds only its own namespace. Another writer at genesis
    /// is bounded by nothing, whatever moment the first namespace recorded.
    function testApplyMigrationHistoryHeadMomentIsPerWriter(
        address writer,
        address other,
        bytes32 migrationA,
        bytes32 migrationB
    ) external {
        vm.assume(writer != address(0));
        vm.assume(other != address(0));
        vm.assume(writer != other);
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.assume(migrationA != migrationB);

        vm.warp(9000);
        vm.prank(writer);
        sRegistry.applyMigrationHistory(migrationA, 9000, onto(writer, MIGRATION_HEAD_GENESIS));

        vm.prank(other);
        sRegistry.applyMigrationHistory(migrationB, 1, onto(other, MIGRATION_HEAD_GENESIS));

        assertEq(sRegistry.applied(other, migrationB), 1);

        // And the other namespace's own head bounds it from there.
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.TimestampBeforeHead.selector, 1, 9000));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(migrationB, 1, onto(writer, migrationA));
    }

    /// Two records may carry the SAME moment. Two migrations applied in one
    /// transaction share a block, and two backfilled migrations known only to
    /// the same day share a moment; the chain is what orders them, so the
    /// moments are not asked to.
    function testApplyMigrationHistoryMomentsMayBeEqual(
        address writer,
        bytes32 migrationA,
        bytes32 migrationB,
        uint32 appliedAt
    ) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.assume(migrationA != migrationB);
        vm.assume(appliedAt != 0);
        vm.warp(appliedAt);

        vm.prank(writer);
        sRegistry.applyMigrationHistory(migrationA, appliedAt, onto(writer, MIGRATION_HEAD_GENESIS));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(migrationB, appliedAt, onto(writer, migrationA));

        assertEq(sRegistry.applied(writer, migrationA), appliedAt);
        assertEq(sRegistry.applied(writer, migrationB), appliedAt);
    }

    /// A record keeps the head it was applied onto, which is what makes the
    /// order structural. The first record in a namespace holds
    /// `MIGRATION_HEAD_GENESIS`, and each later one holds the migration before
    /// it — the value the caller named and the registry checked, not one the
    /// caller could have chosen freely.
    function testApplyMigrationRecordsTheHeadItWasAppliedOnto(address writer, bytes32 migrationA, bytes32 migrationB)
        external
    {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.assume(migrationA != migrationB);

        assertEq(sRegistry.appliedOnto(writer, migrationA), bytes32(0));

        vm.prank(writer);
        sRegistry.applyMigration(migrationA, onto(writer, MIGRATION_HEAD_GENESIS));
        assertEq(sRegistry.appliedOnto(writer, migrationA), MIGRATION_HEAD_GENESIS);

        vm.prank(writer);
        sRegistry.applyMigration(migrationB, onto(writer, migrationA));
        assertEq(sRegistry.appliedOnto(writer, migrationB), migrationA);
        assertEq(sRegistry.appliedOnto(writer, migrationA), MIGRATION_HEAD_GENESIS);
    }

    /// The chain is the order the migrations ran in, and it says so where the
    /// moments cannot. Three records carrying one moment walk back from the head
    /// in the order they were APPLIED, ending at genesis.
    function testApplyMigrationHistoryChainIsTheOrderWhateverTheMoments(
        address writer,
        bytes32 migrationA,
        bytes32 migrationB,
        bytes32 migrationC
    ) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        LibMigrationFuzz.assumeMigration(vm, migrationC);
        vm.assume(migrationA != migrationB);
        vm.assume(migrationB != migrationC);
        vm.assume(migrationA != migrationC);

        vm.warp(9000);
        vm.prank(writer);
        sRegistry.applyMigrationHistory(migrationA, 3000, onto(writer, MIGRATION_HEAD_GENESIS));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(migrationB, 3000, onto(writer, migrationA));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(migrationC, 3000, onto(writer, migrationB));

        // Every moment is the same as the one before it, so nothing about the
        // order can be read out of them.
        assertEq(sRegistry.applied(writer, migrationA), 3000);
        assertEq(sRegistry.applied(writer, migrationB), 3000);
        assertEq(sRegistry.applied(writer, migrationC), 3000);

        // The chain still says exactly what happened.
        bytes32 cursor = sRegistry.head(writer);
        assertEq(cursor, migrationC);
        cursor = sRegistry.appliedOnto(writer, cursor);
        assertEq(cursor, migrationB);
        cursor = sRegistry.appliedOnto(writer, cursor);
        assertEq(cursor, migrationA);
        cursor = sRegistry.appliedOnto(writer, cursor);
        assertEq(cursor, MIGRATION_HEAD_GENESIS);
    }

    /// A chain belongs to one namespace. Another writer applying the same
    /// migrations builds its own chain, and neither reaches the other.
    function testApplyMigrationChainIsPerWriter(address writer, address other, bytes32 migrationA, bytes32 migrationB)
        external
    {
        vm.assume(writer != address(0));
        vm.assume(other != address(0));
        vm.assume(writer != other);
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.assume(migrationA != migrationB);

        vm.prank(writer);
        sRegistry.applyMigration(migrationA, onto(writer, MIGRATION_HEAD_GENESIS));
        vm.prank(writer);
        sRegistry.applyMigration(migrationB, onto(writer, migrationA));

        // The other namespace applies them in the opposite order, so a chain
        // that leaked would be visibly the first one's.
        vm.prank(other);
        sRegistry.applyMigration(migrationB, onto(other, MIGRATION_HEAD_GENESIS));
        vm.prank(other);
        sRegistry.applyMigration(migrationA, onto(other, migrationB));

        assertEq(sRegistry.appliedOnto(writer, migrationA), MIGRATION_HEAD_GENESIS);
        assertEq(sRegistry.appliedOnto(writer, migrationB), migrationA);
        assertEq(sRegistry.appliedOnto(other, migrationB), MIGRATION_HEAD_GENESIS);
        assertEq(sRegistry.appliedOnto(other, migrationA), migrationB);
    }

    /// With its one prerequisite applied, a write naming it records exactly
    /// what the write naming nothing records — the same moment, the same head
    /// applied onto, the same new head — and the list is the one thing the two
    /// records differ in. Two registries with the same prior state are written
    /// the two ways and compared, so "the list is the only difference" is a
    /// fact about the whole record rather than about one reader.
    function testApplyMigrationPrerequisiteWritesTheSameRecord(
        address writer,
        address other,
        bytes32 migration,
        bytes32 prerequisite,
        uint32 now_
    ) external {
        vm.assume(writer != address(0));
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
        plain.applyMigration(prerequisite, onto(other, MIGRATION_HEAD_GENESIS));
        vm.prank(other);
        waiting.applyMigration(prerequisite, onto(other, MIGRATION_HEAD_GENESIS));

        bytes32 plainHead = plain.head(writer);
        bytes32 waitingHead = waiting.head(writer);
        vm.prank(writer);
        plain.applyMigration(migration, onto(writer, plainHead));
        vm.prank(writer);
        waiting.applyMigration(migration, headThen(writer, waitingHead, one(other, prerequisite)));

        assertEq(waiting.applied(writer, migration), plain.applied(writer, migration));
        assertEq(waiting.applied(writer, migration), now_);
        assertEq(waiting.appliedOnto(writer, migration), plain.appliedOnto(writer, migration));
        assertEq(waiting.head(writer), plain.head(writer));
        assertEq(waiting.head(writer), migration);
        assertEq(abi.encode(plain.appliedAfter(writer, migration)), abi.encode(onto(writer, MIGRATION_HEAD_GENESIS)));
        assertEq(
            abi.encode(waiting.appliedAfter(writer, migration)),
            abi.encode(headThen(writer, waitingHead, one(other, prerequisite)))
        );
    }

    /// The same for `applyMigrationHistory`: the supplied moment is what is
    /// recorded, onto the same head, and the list is the one difference.
    function testApplyMigrationHistoryPrerequisiteWritesTheSameRecord(
        address writer,
        address other,
        bytes32 migration,
        bytes32 prerequisite,
        uint32 appliedAt,
        uint32 now_
    ) external {
        vm.assume(writer != address(0));
        vm.assume(other != address(0));
        // The prerequisite is in another namespace, so applying it leaves the
        // caller's head at genesis, which bounds no moment. A prerequisite in
        // the caller's own namespace is
        // `testApplyMigrationOwnEarlierMigrationIsAPrerequisite`.
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
        plain.applyMigration(prerequisite, onto(other, MIGRATION_HEAD_GENESIS));
        vm.prank(other);
        waiting.applyMigration(prerequisite, onto(other, MIGRATION_HEAD_GENESIS));

        Prerequisite[] memory expected = headThen(writer, MIGRATION_HEAD_GENESIS, one(other, prerequisite));
        vm.prank(writer);
        plain.applyMigrationHistory(migration, appliedAt, onto(writer, MIGRATION_HEAD_GENESIS));
        vm.prank(writer);
        waiting.applyMigrationHistory(migration, appliedAt, expected);

        assertEq(waiting.applied(writer, migration), plain.applied(writer, migration));
        assertEq(waiting.applied(writer, migration), appliedAt);
        assertEq(waiting.appliedOnto(writer, migration), plain.appliedOnto(writer, migration));
        assertEq(waiting.head(writer), plain.head(writer));
        assertEq(waiting.head(writer), migration);
        assertEq(abi.encode(plain.appliedAfter(writer, migration)), abi.encode(onto(writer, MIGRATION_HEAD_GENESIS)));
        assertEq(abi.encode(waiting.appliedAfter(writer, migration)), abi.encode(expected));
    }

    /// A record keeps the list it was applied after, as given, which is
    /// what `appliedAfter` reads back. Before the write there is nothing; after a
    /// later write with a different list, the earlier record's list is what it
    /// was — the value the caller named and the registry checked.
    function testApplyMigrationRecordsThePrerequisitesAsListed(
        address writer,
        address otherA,
        address otherB,
        bytes32 migrationA,
        bytes32 migrationB,
        bytes32 prerequisiteA,
        bytes32 prerequisiteB
    ) external {
        vm.assume(writer != address(0));
        vm.assume(otherA != address(0));
        vm.assume(otherB != address(0));
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        LibMigrationFuzz.assumeMigration(vm, prerequisiteA);
        LibMigrationFuzz.assumeMigration(vm, prerequisiteB);
        vm.assume(migrationA != migrationB);
        vm.assume(migrationA != prerequisiteA);
        vm.assume(migrationA != prerequisiteB);
        vm.assume(migrationB != prerequisiteA);
        vm.assume(migrationB != prerequisiteB);
        applyUnder(otherA, prerequisiteA);
        if (sRegistry.applied(otherB, prerequisiteB) == 0) {
            applyUnder(otherB, prerequisiteB);
        }
        Prerequisite[] memory listA = two(otherA, prerequisiteA, otherB, prerequisiteB);
        Prerequisite[] memory listB = one(otherB, prerequisiteB);

        assertEq(abi.encode(sRegistry.appliedAfter(writer, migrationA)), abi.encode(new Prerequisite[](0)));

        bytes32 head = sRegistry.head(writer);
        vm.prank(writer);
        sRegistry.applyMigration(migrationA, headThen(writer, head, listA));
        assertEq(abi.encode(sRegistry.appliedAfter(writer, migrationA)), abi.encode(headThen(writer, head, listA)));
        assertEq(abi.encode(sRegistry.appliedAfter(writer, migrationB)), abi.encode(new Prerequisite[](0)));

        vm.prank(writer);
        sRegistry.applyMigration(migrationB, headThen(writer, migrationA, listB));
        assertEq(
            abi.encode(sRegistry.appliedAfter(writer, migrationB)), abi.encode(headThen(writer, migrationA, listB))
        );
        assertEq(abi.encode(sRegistry.appliedAfter(writer, migrationA)), abi.encode(headThen(writer, head, listA)));
    }

    /// A list of any length is recorded whole and in order: every key the
    /// caller listed after the head, once applied, comes back at the index it
    /// was listed at.
    function testApplyMigrationRecordsAListOfAnyLength(address writer, bytes32 migration, bytes32[] memory seeds)
        external
    {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        Prerequisite[] memory prerequisites = keysFromSeeds(seeds);
        for (uint256 i = 0; i < prerequisites.length; i++) {
            vm.assume(prerequisites[i].migration != migration);
            if (sRegistry.applied(prerequisites[i].writer, prerequisites[i].migration) == 0) {
                applyUnder(prerequisites[i].writer, prerequisites[i].migration);
            }
        }

        bytes32 head = sRegistry.head(writer);
        vm.prank(writer);
        sRegistry.applyMigration(migration, headThen(writer, head, prerequisites));

        Prerequisite[] memory recorded = sRegistry.appliedAfter(writer, migration);
        assertEq(recorded.length, prerequisites.length + 1);
        assertEq(recorded[0].writer, writer);
        assertEq(recorded[0].migration, head);
        for (uint256 i = 0; i < prerequisites.length; i++) {
            assertEq(recorded[i + 1].writer, prerequisites[i].writer);
            assertEq(recorded[i + 1].migration, prerequisites[i].migration);
        }
    }

    /// The prerequisite's own namespace is read and not written: after the
    /// dependent write lands, the prerequisite's writer has the head and the
    /// record it had before.
    function testApplyMigrationPrerequisiteNamespaceIsLeftAlone(
        address writer,
        address other,
        bytes32 migration,
        bytes32 prerequisite
    ) external {
        vm.assume(writer != address(0));
        vm.assume(other != address(0));
        vm.assume(writer != other);
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, prerequisite);
        // The last assertion asks whether `migration` reached the other
        // namespace, which is only a question when it is not the
        // prerequisite that was put there.
        vm.assume(migration != prerequisite);
        vm.warp(1000);
        applyUnder(other, prerequisite);
        vm.warp(2000);

        vm.prank(writer);
        sRegistry.applyMigration(migration, headThen(writer, MIGRATION_HEAD_GENESIS, one(other, prerequisite)));

        assertEq(sRegistry.applied(other, prerequisite), 1000);
        assertEq(sRegistry.appliedOnto(other, prerequisite), MIGRATION_HEAD_GENESIS);
        assertEq(
            abi.encode(sRegistry.appliedAfter(other, prerequisite)), abi.encode(one(other, MIGRATION_HEAD_GENESIS))
        );
        assertEq(sRegistry.head(other), prerequisite);
        assertEq(sRegistry.applied(other, migration), 0);
    }

    /// A prerequisite nobody has applied refuses the write, naming it, and
    /// nothing moves: the migration stays unapplied and the head stays where
    /// it was. Once the prerequisite is applied the same call lands. This is
    /// the whole point of the list — the dependent script is held back by the
    /// registry rather than by re-reading the other migration's post-state.
    function testApplyMigrationUnappliedPrerequisiteRevertsThenLands(
        address writer,
        address other,
        bytes32 migration,
        bytes32 prerequisite
    ) external {
        vm.assume(writer != address(0));
        vm.assume(other != address(0));
        // The prerequisite is in another namespace, so applying it leaves the
        // caller's head where the same call expects it. A prerequisite in
        // the caller's own namespace is
        // `testApplyMigrationOwnEarlierMigrationIsAPrerequisite`.
        vm.assume(writer != other);
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, prerequisite);
        vm.assume(migration != prerequisite);

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.PrerequisiteNotApplied.selector, other, prerequisite)
        );
        vm.prank(writer);
        sRegistry.applyMigration(migration, headThen(writer, MIGRATION_HEAD_GENESIS, one(other, prerequisite)));

        assertEq(sRegistry.applied(writer, migration), 0);
        assertEq(abi.encode(sRegistry.appliedAfter(writer, migration)), abi.encode(new Prerequisite[](0)));
        assertEq(sRegistry.head(writer), MIGRATION_HEAD_GENESIS);

        applyUnder(other, prerequisite);

        vm.prank(writer);
        sRegistry.applyMigration(migration, headThen(writer, MIGRATION_HEAD_GENESIS, one(other, prerequisite)));

        assertEq(sRegistry.applied(writer, migration), block.timestamp);
        assertEq(sRegistry.appliedOnto(writer, migration), MIGRATION_HEAD_GENESIS);
        assertEq(
            abi.encode(sRegistry.appliedAfter(writer, migration)),
            abi.encode(headThen(writer, MIGRATION_HEAD_GENESIS, one(other, prerequisite)))
        );
        assertEq(sRegistry.head(writer), migration);
    }

    /// The same on `applyMigrationHistory`, with the caller's moment recorded
    /// once the prerequisite is there.
    function testApplyMigrationHistoryUnappliedPrerequisiteRevertsThenLands(
        address writer,
        address other,
        bytes32 migration,
        bytes32 prerequisite,
        uint32 appliedAt,
        uint32 now_
    ) external {
        vm.assume(writer != address(0));
        vm.assume(other != address(0));
        // The prerequisite is in another namespace, so applying it leaves the
        // caller's head where the same call expects it. A prerequisite in
        // the caller's own namespace is
        // `testApplyMigrationOwnEarlierMigrationIsAPrerequisite`.
        vm.assume(writer != other);
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, prerequisite);
        vm.assume(migration != prerequisite);
        vm.assume(appliedAt != 0);
        vm.assume(now_ >= appliedAt);
        vm.warp(now_);

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.PrerequisiteNotApplied.selector, other, prerequisite)
        );
        vm.prank(writer);
        sRegistry.applyMigrationHistory(
            migration, appliedAt, headThen(writer, MIGRATION_HEAD_GENESIS, one(other, prerequisite))
        );

        assertEq(sRegistry.applied(writer, migration), 0);
        assertEq(sRegistry.head(writer), MIGRATION_HEAD_GENESIS);

        applyUnder(other, prerequisite);

        vm.prank(writer);
        sRegistry.applyMigrationHistory(
            migration, appliedAt, headThen(writer, MIGRATION_HEAD_GENESIS, one(other, prerequisite))
        );

        assertEq(sRegistry.applied(writer, migration), appliedAt);
        assertEq(
            abi.encode(sRegistry.appliedAfter(writer, migration)),
            abi.encode(headThen(writer, MIGRATION_HEAD_GENESIS, one(other, prerequisite)))
        );
        assertEq(sRegistry.head(writer), migration);
    }

    /// A prerequisite is a particular migration, not a namespace that has
    /// applied something. A writer that has applied other migrations and not
    /// the one named is refused exactly as an empty namespace is.
    function testApplyMigrationPrerequisiteIsTheMigrationNotTheNamespace(
        address writer,
        address other,
        bytes32 migration,
        bytes32 prerequisite,
        bytes32 unrelated
    ) external {
        vm.assume(writer != address(0));
        vm.assume(other != address(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, prerequisite);
        LibMigrationFuzz.assumeMigration(vm, unrelated);
        vm.assume(prerequisite != unrelated);
        applyUnder(other, unrelated);

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.PrerequisiteNotApplied.selector, other, prerequisite)
        );
        vm.prank(writer);
        sRegistry.applyMigration(migration, headThen(writer, MIGRATION_HEAD_GENESIS, one(other, prerequisite)));
    }

    /// Over a list of any length with exactly one entry unapplied, the revert
    /// names that entry — wherever it sits, whatever namespaces the others are
    /// in, the caller's own included. Once it is applied too, the write lands
    /// and the whole list is the record's.
    function testApplyMigrationNamesTheOneUnappliedPrerequisite(
        address writer,
        bytes32 migration,
        bytes32[] memory seeds,
        uint256 unappliedIndex
    ) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        vm.assume(seeds.length > 0);
        Prerequisite[] memory prerequisites = keysFromSeeds(seeds);
        unappliedIndex = bound(unappliedIndex, 0, prerequisites.length - 1);
        Prerequisite memory unapplied = prerequisites[unappliedIndex];

        for (uint256 i = 0; i < prerequisites.length; i++) {
            // The caller's own migration is never a prerequisite here: applied
            // as one, it would make the second half `MigrationAlreadyApplied`.
            vm.assume(prerequisites[i].migration != migration);
            if (i == unappliedIndex) {
                continue;
            }
            // Applying any other entry must not apply the unapplied one.
            vm.assume(prerequisites[i].writer != unapplied.writer || prerequisites[i].migration != unapplied.migration);
            if (sRegistry.applied(prerequisites[i].writer, prerequisites[i].migration) == 0) {
                applyUnder(prerequisites[i].writer, prerequisites[i].migration);
            }
        }

        bytes32 head = sRegistry.head(writer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.PrerequisiteNotApplied.selector, unapplied.writer, unapplied.migration
            )
        );
        vm.prank(writer);
        sRegistry.applyMigration(migration, headThen(writer, head, prerequisites));
        assertEq(sRegistry.applied(writer, migration), 0);

        applyUnder(unapplied.writer, unapplied.migration);

        head = sRegistry.head(writer);
        vm.prank(writer);
        sRegistry.applyMigration(migration, headThen(writer, head, prerequisites));
        assertEq(sRegistry.applied(writer, migration), block.timestamp);
        assertEq(
            abi.encode(sRegistry.appliedAfter(writer, migration)), abi.encode(headThen(writer, head, prerequisites))
        );
        assertEq(sRegistry.head(writer), migration);
    }

    /// The same on `applyMigrationHistory`.
    function testApplyMigrationHistoryNamesTheOneUnappliedPrerequisite(
        address writer,
        bytes32 migration,
        bytes32[] memory seeds,
        uint256 unappliedIndex,
        uint32 appliedAt,
        uint32 now_
    ) external {
        vm.assume(writer != address(0));
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
            // Nothing is applied in the caller's own namespace, so the caller's
            // moment is bounded by genesis alone.
            vm.assume(prerequisites[i].writer != writer);
            if (i == unappliedIndex) {
                continue;
            }
            vm.assume(prerequisites[i].writer != unapplied.writer || prerequisites[i].migration != unapplied.migration);
            if (sRegistry.applied(prerequisites[i].writer, prerequisites[i].migration) == 0) {
                applyUnder(prerequisites[i].writer, prerequisites[i].migration);
            }
        }

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.PrerequisiteNotApplied.selector, unapplied.writer, unapplied.migration
            )
        );
        vm.prank(writer);
        sRegistry.applyMigrationHistory(migration, appliedAt, headThen(writer, MIGRATION_HEAD_GENESIS, prerequisites));
        assertEq(sRegistry.applied(writer, migration), 0);

        applyUnder(unapplied.writer, unapplied.migration);

        vm.prank(writer);
        sRegistry.applyMigrationHistory(migration, appliedAt, headThen(writer, MIGRATION_HEAD_GENESIS, prerequisites));
        assertEq(sRegistry.applied(writer, migration), appliedAt);
        assertEq(
            abi.encode(sRegistry.appliedAfter(writer, migration)),
            abi.encode(headThen(writer, MIGRATION_HEAD_GENESIS, prerequisites))
        );
    }

    /// With several unapplied, the FIRST in list order is the one named, and
    /// applying it moves the refusal to the next. A caller waiting on several
    /// is told about one at a time, in the order it listed them.
    function testApplyMigrationNamesTheFirstUnappliedPrerequisite(
        address writer,
        address otherA,
        address otherB,
        bytes32 migration,
        bytes32 prerequisiteA,
        bytes32 prerequisiteB
    ) external {
        vm.assume(writer != address(0));
        vm.assume(otherA != address(0));
        vm.assume(otherB != address(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, prerequisiteA);
        LibMigrationFuzz.assumeMigration(vm, prerequisiteB);
        vm.assume(migration != prerequisiteA);
        vm.assume(migration != prerequisiteB);
        vm.assume(otherA != otherB || prerequisiteA != prerequisiteB);
        Prerequisite[] memory prerequisites = two(otherA, prerequisiteA, otherB, prerequisiteB);

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.PrerequisiteNotApplied.selector, otherA, prerequisiteA)
        );
        vm.prank(writer);
        sRegistry.applyMigration(migration, headThen(writer, MIGRATION_HEAD_GENESIS, prerequisites));

        applyUnder(otherA, prerequisiteA);

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.PrerequisiteNotApplied.selector, otherB, prerequisiteB)
        );
        vm.prank(writer);
        sRegistry.applyMigration(migration, headThen(writer, MIGRATION_HEAD_GENESIS, prerequisites));

        applyUnder(otherB, prerequisiteB);

        bytes32 head = sRegistry.head(writer);
        vm.prank(writer);
        sRegistry.applyMigration(migration, headThen(writer, head, prerequisites));
        assertEq(sRegistry.applied(writer, migration), block.timestamp);
    }

    /// A prerequisite naming the zero writer is refused as `ZeroWriter`, the
    /// same refusal `applied` makes of the same key. The zero namespace is
    /// provably empty, so without this the entry would be refused as unapplied
    /// forever instead of as the unset constant it is.
    function testApplyMigrationZeroWriterPrerequisiteReverts(address writer, bytes32 migration, bytes32 prerequisite)
        external
    {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, prerequisite);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroWriter.selector));
        vm.prank(writer);
        sRegistry.applyMigration(migration, headThen(writer, MIGRATION_HEAD_GENESIS, one(address(0), prerequisite)));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroWriter.selector));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(
            migration, block.timestamp, headThen(writer, MIGRATION_HEAD_GENESIS, one(address(0), prerequisite))
        );

        assertEq(sRegistry.applied(writer, migration), 0);
    }

    /// A prerequisite naming the zero migration is refused as `ZeroMigration`,
    /// whatever its writer: an uninitialised id names no record.
    function testApplyMigrationZeroMigrationPrerequisiteReverts(address writer, address other, bytes32 migration)
        external
    {
        vm.assume(writer != address(0));
        vm.assume(other != address(0));
        LibMigrationFuzz.assumeMigration(vm, migration);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(migration, headThen(writer, MIGRATION_HEAD_GENESIS, one(other, bytes32(0))));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(
            migration, block.timestamp, headThen(writer, MIGRATION_HEAD_GENESIS, one(other, bytes32(0)))
        );

        assertEq(sRegistry.applied(writer, migration), 0);
    }

    /// A prerequisite naming `MIGRATION_HEAD_GENESIS` is refused as
    /// `GenesisMigration`: genesis is a head, no namespace ever applies it, and
    /// a caller that named it has confused a head for a migration.
    function testApplyMigrationGenesisPrerequisiteReverts(address writer, address other, bytes32 migration) external {
        vm.assume(writer != address(0));
        vm.assume(other != address(0));
        LibMigrationFuzz.assumeMigration(vm, migration);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.GenesisMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(
            migration, headThen(writer, MIGRATION_HEAD_GENESIS, one(other, MIGRATION_HEAD_GENESIS))
        );

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.GenesisMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(
            migration, block.timestamp, headThen(writer, MIGRATION_HEAD_GENESIS, one(other, MIGRATION_HEAD_GENESIS))
        );

        assertEq(sRegistry.applied(writer, migration), 0);
    }

    /// Within one entry the key is refused in `applied`'s order: writer first,
    /// then the two reserved ids. An entry that is wrong in every field is
    /// `ZeroWriter`.
    function testApplyMigrationPrerequisiteKeyRefusalOrderWithinAnEntry(address writer, bytes32 migration) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeMigration(vm, migration);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroWriter.selector));
        vm.prank(writer);
        sRegistry.applyMigration(migration, headThen(writer, MIGRATION_HEAD_GENESIS, one(address(0), bytes32(0))));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroWriter.selector));
        vm.prank(writer);
        sRegistry.applyMigration(
            migration, headThen(writer, MIGRATION_HEAD_GENESIS, one(address(0), MIGRATION_HEAD_GENESIS))
        );
    }

    /// Every entry is checked as a key before any entry is read, so a
    /// malformed entry LATER in the list is reported over an unapplied entry
    /// earlier in it. A malformed argument is a mistake the caller can fix
    /// now; an unapplied prerequisite is a fact about the world, and the
    /// caller is told about its own mistakes first.
    function testApplyMigrationMalformedPrerequisiteReportedOverUnapplied(
        address writer,
        address other,
        bytes32 migration,
        bytes32 prerequisite
    ) external {
        vm.assume(writer != address(0));
        vm.assume(other != address(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, prerequisite);
        assertEq(sRegistry.applied(other, prerequisite), 0);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroWriter.selector));
        vm.prank(writer);
        sRegistry.applyMigration(
            migration, headThen(writer, MIGRATION_HEAD_GENESIS, two(other, prerequisite, address(0), prerequisite))
        );

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(
            migration, headThen(writer, MIGRATION_HEAD_GENESIS, two(other, prerequisite, other, bytes32(0)))
        );

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.GenesisMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(
            migration, headThen(writer, MIGRATION_HEAD_GENESIS, two(other, prerequisite, other, MIGRATION_HEAD_GENESIS))
        );

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroWriter.selector));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(
            migration,
            block.timestamp,
            headThen(writer, MIGRATION_HEAD_GENESIS, two(other, prerequisite, address(0), prerequisite))
        );
    }

    /// Among several malformed entries, the first in list order is the one
    /// reported, whichever field is wrong in each.
    function testApplyMigrationFirstMalformedPrerequisiteReported(address writer, address other, bytes32 migration)
        external
    {
        vm.assume(writer != address(0));
        vm.assume(other != address(0));
        LibMigrationFuzz.assumeMigration(vm, migration);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroWriter.selector));
        vm.prank(writer);
        sRegistry.applyMigration(
            migration, headThen(writer, MIGRATION_HEAD_GENESIS, two(address(0), migration, other, bytes32(0)))
        );

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(
            migration, headThen(writer, MIGRATION_HEAD_GENESIS, two(other, bytes32(0), address(0), migration))
        );

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.GenesisMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(
            migration, headThen(writer, MIGRATION_HEAD_GENESIS, two(other, MIGRATION_HEAD_GENESIS, other, bytes32(0)))
        );
    }

    /// A prerequisite naming the migration being applied is unapplied by
    /// construction — the write that would apply it is the one being refused
    /// — so it is `PrerequisiteNotApplied(writer, migration)` rather than a
    /// record, on both writes.
    function testApplyMigrationSelfPrerequisiteReverts(address writer, bytes32 migration) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeMigration(vm, migration);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.PrerequisiteNotApplied.selector, writer, migration));
        vm.prank(writer);
        sRegistry.applyMigration(migration, headThen(writer, MIGRATION_HEAD_GENESIS, one(writer, migration)));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.PrerequisiteNotApplied.selector, writer, migration));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(
            migration, block.timestamp, headThen(writer, MIGRATION_HEAD_GENESIS, one(writer, migration))
        );

        assertEq(sRegistry.applied(writer, migration), 0);
        assertEq(sRegistry.head(writer), MIGRATION_HEAD_GENESIS);
    }

    /// The caller's own namespace is an ordinary namespace to name: an earlier
    /// migration of its own is a prerequisite like any other, applied or not,
    /// and is recorded like any other.
    function testApplyMigrationOwnEarlierMigrationIsAPrerequisite(
        address writer,
        bytes32 migrationA,
        bytes32 migrationB
    ) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.assume(migrationA != migrationB);

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.PrerequisiteNotApplied.selector, writer, migrationA)
        );
        vm.prank(writer);
        sRegistry.applyMigration(migrationB, headThen(writer, MIGRATION_HEAD_GENESIS, one(writer, migrationA)));

        vm.prank(writer);
        sRegistry.applyMigration(migrationA, onto(writer, MIGRATION_HEAD_GENESIS));

        vm.prank(writer);
        sRegistry.applyMigration(migrationB, headThen(writer, migrationA, one(writer, migrationA)));

        assertEq(sRegistry.applied(writer, migrationB), block.timestamp);
        assertEq(sRegistry.appliedOnto(writer, migrationB), migrationA);
        assertEq(
            abi.encode(sRegistry.appliedAfter(writer, migrationB)),
            abi.encode(headThen(writer, migrationA, one(writer, migrationA)))
        );
        assertEq(sRegistry.head(writer), migrationB);
    }

    /// A prerequisite listed twice is checked twice — harmless when applied,
    /// and named once, as the first entry, when not — and recorded twice: the
    /// record says what the caller listed.
    function testApplyMigrationDuplicatePrerequisitesAreCheckedTwiceAndKept(
        address writer,
        address other,
        bytes32 migration,
        bytes32 prerequisite
    ) external {
        vm.assume(writer != address(0));
        vm.assume(other != address(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, prerequisite);
        vm.assume(migration != prerequisite);
        Prerequisite[] memory prerequisites = two(other, prerequisite, other, prerequisite);

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.PrerequisiteNotApplied.selector, other, prerequisite)
        );
        vm.prank(writer);
        sRegistry.applyMigration(migration, headThen(writer, MIGRATION_HEAD_GENESIS, prerequisites));

        applyUnder(other, prerequisite);

        bytes32 head = sRegistry.head(writer);
        vm.prank(writer);
        sRegistry.applyMigration(migration, headThen(writer, head, prerequisites));
        assertEq(sRegistry.applied(writer, migration), block.timestamp);
        assertEq(sRegistry.appliedAfter(writer, migration).length, 3);
        assertEq(
            abi.encode(sRegistry.appliedAfter(writer, migration)), abi.encode(headThen(writer, head, prerequisites))
        );
    }

    /// The caller's own arguments are refused before the list is looked at:
    /// a zero or genesis migration, and a zero moment, are reported over the
    /// head alone, a malformed list and an unapplied one alike. Everything the
    /// caller handed in about its own record is what it can fix first.
    function testApplyMigrationOwnArgumentsCheckedBeforePrerequisites(
        address writer,
        address other,
        bytes32 prerequisite,
        bytes32 anyHead
    ) external {
        vm.assume(writer != address(0));
        vm.assume(other != address(0));
        LibMigrationFuzz.assumeMigration(vm, prerequisite);
        vm.warp(1000);
        Prerequisite[] memory none = new Prerequisite[](0);
        Prerequisite[] memory malformed = one(address(0), prerequisite);
        Prerequisite[] memory unapplied = one(other, prerequisite);

        // Zero migration, over every kind of list.
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(bytes32(0), headThen(writer, anyHead, none));
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(bytes32(0), headThen(writer, anyHead, malformed));
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(bytes32(0), headThen(writer, anyHead, unapplied));

        // Genesis migration, over every kind of list.
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.GenesisMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, headThen(writer, anyHead, none));
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.GenesisMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, headThen(writer, anyHead, malformed));
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.GenesisMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, headThen(writer, anyHead, unapplied));

        // Zero moment, over every kind of list, on both writes.
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroTimestamp.selector));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(prerequisite, 0, headThen(writer, anyHead, none));
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroTimestamp.selector));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(prerequisite, 0, headThen(writer, anyHead, malformed));
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroTimestamp.selector));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(prerequisite, 0, headThen(writer, anyHead, unapplied));

        vm.warp(0);
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroTimestamp.selector));
        vm.prank(writer);
        sRegistry.applyMigration(prerequisite, headThen(writer, anyHead, none));
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroTimestamp.selector));
        vm.prank(writer);
        sRegistry.applyMigration(prerequisite, headThen(writer, anyHead, malformed));
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroTimestamp.selector));
        vm.prank(writer);
        sRegistry.applyMigration(prerequisite, headThen(writer, anyHead, unapplied));

        // And the migration before the moment.
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(bytes32(0), 0, headThen(writer, anyHead, none));
    }

    /// The prerequisites are read before anything about the caller's own
    /// namespace: an unapplied prerequisite is reported over a migration the
    /// caller has already applied. A record that exists while the
    /// prerequisites its script now names do not is the more alarming fact,
    /// and it is not hidden behind "already applied". With the prerequisite
    /// applied, the re-dispatch is `MigrationAlreadyApplied`, as with the head
    /// alone.
    function testApplyMigrationPrerequisitesCheckedBeforeAlreadyApplied(
        address writer,
        address other,
        bytes32 migration,
        bytes32 prerequisite
    ) external {
        vm.assume(writer != address(0));
        vm.assume(other != address(0));
        vm.assume(writer != other);
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, prerequisite);
        vm.prank(writer);
        sRegistry.applyMigration(migration, onto(writer, MIGRATION_HEAD_GENESIS));

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.PrerequisiteNotApplied.selector, other, prerequisite)
        );
        vm.prank(writer);
        sRegistry.applyMigration(migration, headThen(writer, MIGRATION_HEAD_GENESIS, one(other, prerequisite)));

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.PrerequisiteNotApplied.selector, other, prerequisite)
        );
        vm.prank(writer);
        sRegistry.applyMigrationHistory(
            migration, block.timestamp, headThen(writer, MIGRATION_HEAD_GENESIS, one(other, prerequisite))
        );

        applyUnder(other, prerequisite);

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.MigrationAlreadyApplied.selector, writer, migration)
        );
        vm.prank(writer);
        sRegistry.applyMigration(migration, headThen(writer, MIGRATION_HEAD_GENESIS, one(other, prerequisite)));

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.MigrationAlreadyApplied.selector, writer, migration)
        );
        vm.prank(writer);
        sRegistry.applyMigrationHistory(
            migration, block.timestamp, headThen(writer, MIGRATION_HEAD_GENESIS, one(other, prerequisite))
        );

        // The refusals recorded nothing over the original record's list.
        assertEq(abi.encode(sRegistry.appliedAfter(writer, migration)), abi.encode(one(writer, MIGRATION_HEAD_GENESIS)));
    }

    /// An unapplied prerequisite is reported over a wrong head, and with the
    /// prerequisite applied the wrong head is reported exactly as an empty
    /// list reports it.
    function testApplyMigrationPrerequisitesCheckedBeforeHead(
        address writer,
        address other,
        bytes32 migration,
        bytes32 prerequisite,
        bytes32 wrongHead
    ) external {
        vm.assume(writer != address(0));
        vm.assume(other != address(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, prerequisite);
        vm.assume(migration != prerequisite);
        vm.assume(wrongHead != MIGRATION_HEAD_GENESIS);

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.PrerequisiteNotApplied.selector, other, prerequisite)
        );
        vm.prank(writer);
        sRegistry.applyMigration(migration, headThen(writer, wrongHead, one(other, prerequisite)));

        applyUnder(other, prerequisite);
        vm.assume(sRegistry.head(writer) == MIGRATION_HEAD_GENESIS);

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.UnexpectedMigrationHead.selector, writer, wrongHead, MIGRATION_HEAD_GENESIS
            )
        );
        vm.prank(writer);
        sRegistry.applyMigration(migration, headThen(writer, wrongHead, one(other, prerequisite)));

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.UnexpectedMigrationHead.selector, writer, wrongHead, MIGRATION_HEAD_GENESIS
            )
        );
        vm.prank(writer);
        sRegistry.applyMigrationHistory(
            migration, block.timestamp, headThen(writer, wrongHead, one(other, prerequisite))
        );
    }

    /// An unapplied prerequisite is reported over a moment before the head's
    /// and over a moment in the future; with the prerequisite applied, each
    /// is reported as the head alone reports it, in the same order.
    function testApplyMigrationPrerequisitesCheckedBeforeTheMoment(
        address writer,
        address other,
        bytes32 migrationA,
        bytes32 migrationB,
        bytes32 prerequisite
    ) external {
        vm.assume(writer != address(0));
        vm.assume(other != address(0));
        vm.assume(writer != other);
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        LibMigrationFuzz.assumeMigration(vm, prerequisite);
        vm.assume(migrationA != migrationB);
        vm.warp(2000);
        vm.prank(writer);
        sRegistry.applyMigrationHistory(migrationA, 2000, onto(writer, MIGRATION_HEAD_GENESIS));
        vm.warp(3000);

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.PrerequisiteNotApplied.selector, other, prerequisite)
        );
        vm.prank(writer);
        sRegistry.applyMigrationHistory(migrationB, 1999, headThen(writer, migrationA, one(other, prerequisite)));

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.PrerequisiteNotApplied.selector, other, prerequisite)
        );
        vm.prank(writer);
        sRegistry.applyMigrationHistory(migrationB, 3001, headThen(writer, migrationA, one(other, prerequisite)));

        applyUnder(other, prerequisite);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.TimestampBeforeHead.selector, 1999, 2000));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(migrationB, 1999, headThen(writer, migrationA, one(other, prerequisite)));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.FutureTimestamp.selector, 3001, 3000));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(migrationB, 3001, headThen(writer, migrationA, one(other, prerequisite)));

        // A moment wrong both ways is reported against the head first, as with
        // the head alone: the record it reads is the one the head check just
        // confirmed, and the future is the one refusal time resolves.
        vm.warp(1000);
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.TimestampBeforeHead.selector, 1500, 2000));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(migrationB, 1500, headThen(writer, migrationA, one(other, prerequisite)));
    }

    /// Once the prerequisites pass, the namespace's own order holds: a
    /// migration already applied is reported over a wrong head.
    function testApplyMigrationAlreadyAppliedCheckedBeforeHeadWithPrerequisites(
        address writer,
        address other,
        bytes32 migrationA,
        bytes32 migrationB,
        bytes32 prerequisite
    ) external {
        vm.assume(writer != address(0));
        vm.assume(other != address(0));
        vm.assume(writer != other);
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        LibMigrationFuzz.assumeMigration(vm, prerequisite);
        vm.assume(migrationA != migrationB);
        applyUnder(other, prerequisite);
        vm.prank(writer);
        sRegistry.applyMigration(migrationA, onto(writer, MIGRATION_HEAD_GENESIS));
        vm.prank(writer);
        sRegistry.applyMigration(migrationB, onto(writer, migrationA));

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.MigrationAlreadyApplied.selector, writer, migrationA)
        );
        vm.prank(writer);
        sRegistry.applyMigration(migrationA, headThen(writer, MIGRATION_HEAD_GENESIS, one(other, prerequisite)));
    }

    /// A prerequisite recorded through `applyMigrationHistory` counts: what is
    /// checked is that the record exists, not which write wrote it.
    function testApplyMigrationPrerequisiteRecordedByHistoryCounts(
        address writer,
        address other,
        bytes32 migration,
        bytes32 prerequisite,
        uint32 prerequisiteAt,
        uint32 now_
    ) external {
        vm.assume(writer != address(0));
        vm.assume(other != address(0));
        vm.assume(writer != other);
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, prerequisite);
        vm.assume(prerequisiteAt != 0);
        vm.assume(now_ >= prerequisiteAt);
        vm.warp(now_);
        vm.prank(other);
        sRegistry.applyMigrationHistory(prerequisite, prerequisiteAt, onto(other, MIGRATION_HEAD_GENESIS));

        vm.prank(writer);
        sRegistry.applyMigration(migration, headThen(writer, MIGRATION_HEAD_GENESIS, one(other, prerequisite)));

        assertEq(sRegistry.applied(writer, migration), now_);
    }

    /// A prerequisite bounds no moment. A record whose moment is EARLIER than
    /// its prerequisite's is accepted: the moments in another namespace are
    /// that writer's data, and what is checked is that the record existed
    /// when this write landed, which is the chain's order and not the
    /// moments'.
    function testApplyMigrationHistoryMomentIsNotBoundedByThePrerequisite(
        address writer,
        address other,
        bytes32 migration,
        bytes32 prerequisite,
        uint32 appliedAt,
        uint32 prerequisiteAt,
        uint32 now_
    ) external {
        vm.assume(writer != address(0));
        vm.assume(other != address(0));
        vm.assume(writer != other);
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, prerequisite);
        vm.assume(appliedAt != 0);
        vm.assume(prerequisiteAt > appliedAt);
        vm.assume(now_ >= prerequisiteAt);
        vm.warp(now_);
        vm.prank(other);
        sRegistry.applyMigrationHistory(prerequisite, prerequisiteAt, onto(other, MIGRATION_HEAD_GENESIS));

        vm.prank(writer);
        sRegistry.applyMigrationHistory(
            migration, appliedAt, headThen(writer, MIGRATION_HEAD_GENESIS, one(other, prerequisite))
        );

        assertEq(sRegistry.applied(writer, migration), appliedAt);
        assertEq(sRegistry.applied(other, prerequisite), prerequisiteAt);
    }

    /// A write naming prerequisites emits `Migrated` exactly as one naming none
    /// does: one entry, the writer and migration indexed, the moment as data,
    /// and nothing about the list — the list is in the record, read back by
    /// `prerequisites`, so one filter on `Migrated` is the complete history.
    function testApplyMigrationWithPrerequisitesEmitsOneMigrated(
        address writer,
        address otherA,
        address otherB,
        bytes32 migration,
        bytes32 prerequisiteA,
        bytes32 prerequisiteB,
        uint32 now_
    ) external {
        vm.assume(writer != address(0));
        vm.assume(otherA != address(0));
        vm.assume(otherB != address(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, prerequisiteA);
        LibMigrationFuzz.assumeMigration(vm, prerequisiteB);
        vm.assume(migration != prerequisiteA);
        vm.assume(migration != prerequisiteB);
        vm.assume(now_ != 0);
        vm.warp(now_);
        applyUnder(otherA, prerequisiteA);
        if (sRegistry.applied(otherB, prerequisiteB) == 0) {
            applyUnder(otherB, prerequisiteB);
        }
        Prerequisite[] memory prerequisites = two(otherA, prerequisiteA, otherB, prerequisiteB);

        bytes32 head = sRegistry.head(writer);
        vm.recordLogs();
        vm.prank(writer);
        sRegistry.applyMigration(migration, headThen(writer, head, prerequisites));
        Vm.Log[] memory entries = vm.getRecordedLogs();

        assertEq(entries.length, 1);
        assertEq(entries[0].emitter, address(sRegistry));
        assertEq(entries[0].topics.length, 3);
        assertEq(entries[0].topics[0], keccak256("Migrated(address,bytes32,uint256)"));
        assertEq(entries[0].topics[1], bytes32(uint256(uint160(writer))));
        assertEq(entries[0].topics[2], migration);
        assertEq(entries[0].data, abi.encode(uint256(now_)));
    }

    /// The same one entry from `applyMigrationHistory`, with the caller's
    /// moment as data.
    function testApplyMigrationHistoryWithPrerequisitesEmitsOneMigrated(
        address writer,
        address other,
        bytes32 migration,
        bytes32 prerequisite,
        uint32 appliedAt,
        uint32 now_
    ) external {
        vm.assume(writer != address(0));
        vm.assume(other != address(0));
        // The prerequisite is in another namespace, so applying it leaves the
        // caller's head at genesis, which bounds no moment. A prerequisite in
        // the caller's own namespace is
        // `testApplyMigrationOwnEarlierMigrationIsAPrerequisite`.
        vm.assume(writer != other);
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, prerequisite);
        vm.assume(migration != prerequisite);
        vm.assume(appliedAt != 0);
        vm.assume(now_ >= appliedAt);
        vm.warp(now_);
        applyUnder(other, prerequisite);
        Prerequisite[] memory prerequisites = one(other, prerequisite);

        bytes32 head = sRegistry.head(writer);
        vm.recordLogs();
        vm.prank(writer);
        sRegistry.applyMigrationHistory(migration, appliedAt, headThen(writer, head, prerequisites));
        Vm.Log[] memory entries = vm.getRecordedLogs();

        assertEq(entries.length, 1);
        assertEq(entries[0].emitter, address(sRegistry));
        assertEq(entries[0].topics.length, 3);
        assertEq(entries[0].topics[0], keccak256("Migrated(address,bytes32,uint256)"));
        assertEq(entries[0].topics[1], bytes32(uint256(uint160(writer))));
        assertEq(entries[0].topics[2], migration);
        assertEq(entries[0].data, abi.encode(uint256(appliedAt)));
    }

    /// A write after the head alone and a write with a list emit one entry each,
    /// of the same event: the list changes what is recorded and nothing about
    /// what is logged.
    function testApplyMigrationEmitsOneEntryWhateverTheList(
        address writer,
        address other,
        bytes32 migrationA,
        bytes32 migrationB,
        bytes32 prerequisite
    ) external {
        vm.assume(writer != address(0));
        vm.assume(other != address(0));
        vm.assume(writer != other);
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        LibMigrationFuzz.assumeMigration(vm, prerequisite);
        vm.assume(migrationA != migrationB);
        applyUnder(other, prerequisite);

        vm.recordLogs();
        vm.prank(writer);
        sRegistry.applyMigration(migrationA, onto(writer, MIGRATION_HEAD_GENESIS));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(
            migrationB, block.timestamp, headThen(writer, migrationA, one(other, prerequisite))
        );
        Vm.Log[] memory entries = vm.getRecordedLogs();

        assertEq(entries.length, 2);
        assertEq(entries[0].topics[0], keccak256("Migrated(address,bytes32,uint256)"));
        assertEq(entries[0].topics[2], migrationA);
        assertEq(entries[1].topics[0], keccak256("Migrated(address,bytes32,uint256)"));
        assertEq(entries[1].topics[2], migrationB);
    }

    /// A refused write naming prerequisites emits nothing, for every one of
    /// its refusals, the ones the list adds included.
    function testApplyMigrationNoEventOnRevertWithPrerequisites(
        address writer,
        address other,
        bytes32 migration,
        bytes32 prerequisite
    ) external {
        vm.assume(writer != address(0));
        vm.assume(other != address(0));
        vm.assume(writer != other);
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, prerequisite);
        vm.assume(migration != prerequisite);
        vm.warp(1000);
        bytes32 next = keccak256(abi.encode(migration));
        Prerequisite[] memory applied = one(other, prerequisite);

        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.PrerequisiteNotApplied.selector, other, prerequisite)
        );
        vm.prank(writer);
        sRegistry.applyMigration(migration, headThen(writer, MIGRATION_HEAD_GENESIS, applied));
        assertEq(vm.getRecordedLogs().length, 0);

        vm.recordLogs();
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroWriter.selector));
        vm.prank(writer);
        sRegistry.applyMigration(migration, headThen(writer, MIGRATION_HEAD_GENESIS, one(address(0), prerequisite)));
        assertEq(vm.getRecordedLogs().length, 0);

        applyUnder(other, prerequisite);
        vm.prank(writer);
        sRegistry.applyMigration(migration, headThen(writer, MIGRATION_HEAD_GENESIS, applied));

        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.MigrationAlreadyApplied.selector, writer, migration)
        );
        vm.prank(writer);
        sRegistry.applyMigration(migration, headThen(writer, MIGRATION_HEAD_GENESIS, applied));
        assertEq(vm.getRecordedLogs().length, 0);

        vm.recordLogs();
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(bytes32(0), headThen(writer, migration, applied));
        assertEq(vm.getRecordedLogs().length, 0);

        vm.recordLogs();
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.GenesisMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, headThen(writer, migration, applied));
        assertEq(vm.getRecordedLogs().length, 0);

        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.UnexpectedMigrationHead.selector, writer, MIGRATION_HEAD_GENESIS, migration
            )
        );
        vm.prank(writer);
        sRegistry.applyMigration(next, headThen(writer, MIGRATION_HEAD_GENESIS, applied));
        assertEq(vm.getRecordedLogs().length, 0);

        vm.recordLogs();
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroTimestamp.selector));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(next, 0, headThen(writer, migration, applied));
        assertEq(vm.getRecordedLogs().length, 0);

        vm.recordLogs();
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.FutureTimestamp.selector, 1001, 1000));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(next, 1001, headThen(writer, migration, applied));
        assertEq(vm.getRecordedLogs().length, 0);

        vm.recordLogs();
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.TimestampBeforeHead.selector, 999, 1000));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(next, 999, headThen(writer, migration, applied));
        assertEq(vm.getRecordedLogs().length, 0);
    }

    /// An empty list names no head, so it is refused as a zero head on an
    /// empty namespace and on a used one, by both writes, and records nothing.
    function testApplyMigrationEmptyListReverts(address writer, bytes32 migrationA, bytes32 migrationB) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.assume(migrationA != migrationB);
        vm.warp(1000);
        Prerequisite[] memory empty = new Prerequisite[](0);

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.UnexpectedMigrationHead.selector, writer, bytes32(0), MIGRATION_HEAD_GENESIS
            )
        );
        vm.prank(writer);
        sRegistry.applyMigration(migrationA, empty);
        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.UnexpectedMigrationHead.selector, writer, bytes32(0), MIGRATION_HEAD_GENESIS
            )
        );
        vm.prank(writer);
        sRegistry.applyMigrationHistory(migrationA, 1, empty);
        assertEq(sRegistry.applied(writer, migrationA), 0);

        vm.prank(writer);
        sRegistry.applyMigration(migrationA, onto(writer, MIGRATION_HEAD_GENESIS));

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.UnexpectedMigrationHead.selector, writer, bytes32(0), migrationA
            )
        );
        vm.prank(writer);
        sRegistry.applyMigration(migrationB, empty);
        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.UnexpectedMigrationHead.selector, writer, bytes32(0), migrationA
            )
        );
        vm.prank(writer);
        sRegistry.applyMigrationHistory(migrationB, 1000, empty);
        assertEq(sRegistry.applied(writer, migrationB), 0);
        assertEq(sRegistry.head(writer), migrationA);
    }

    /// The first entry is the caller's own head, so one under any other
    /// writer is refused even when its migration is exactly the head. The
    /// error names the migration handed in, which is the head itself.
    function testApplyMigrationFirstEntryUnderAnotherWriterReverts(
        address writer,
        address other,
        bytes32 migrationA,
        bytes32 migrationB
    ) external {
        vm.assume(writer != address(0));
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
                MIGRATION_HEAD_GENESIS,
                MIGRATION_HEAD_GENESIS
            )
        );
        vm.prank(writer);
        sRegistry.applyMigration(migrationA, onto(other, MIGRATION_HEAD_GENESIS));
        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.UnexpectedMigrationHead.selector,
                writer,
                MIGRATION_HEAD_GENESIS,
                MIGRATION_HEAD_GENESIS
            )
        );
        vm.prank(writer);
        sRegistry.applyMigrationHistory(migrationA, 1, onto(other, MIGRATION_HEAD_GENESIS));
        assertEq(sRegistry.applied(writer, migrationA), 0);

        vm.prank(writer);
        sRegistry.applyMigration(migrationA, onto(writer, MIGRATION_HEAD_GENESIS));

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.UnexpectedMigrationHead.selector, writer, migrationA, migrationA
            )
        );
        vm.prank(writer);
        sRegistry.applyMigration(migrationB, onto(other, migrationA));
        assertEq(sRegistry.applied(writer, migrationB), 0);
        assertEq(sRegistry.head(writer), migrationA);
    }

    /// The first entry is a head, not a record key, so it is never refused as
    /// one: a zero writer, a zero migration or genesis on a used namespace in
    /// the first entry is a wrong head, not `ZeroWriter`, `ZeroMigration` or
    /// `GenesisMigration`.
    function testApplyMigrationFirstEntryIsNotAKey(address writer, bytes32 migrationA, bytes32 migrationB) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.assume(migrationA != migrationB);

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.UnexpectedMigrationHead.selector,
                writer,
                MIGRATION_HEAD_GENESIS,
                MIGRATION_HEAD_GENESIS
            )
        );
        vm.prank(writer);
        sRegistry.applyMigration(migrationA, onto(address(0), MIGRATION_HEAD_GENESIS));

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.UnexpectedMigrationHead.selector, writer, bytes32(0), MIGRATION_HEAD_GENESIS
            )
        );
        vm.prank(writer);
        sRegistry.applyMigration(migrationA, onto(writer, bytes32(0)));

        vm.prank(writer);
        sRegistry.applyMigration(migrationA, onto(writer, MIGRATION_HEAD_GENESIS));

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.UnexpectedMigrationHead.selector, writer, MIGRATION_HEAD_GENESIS, migrationA
            )
        );
        vm.prank(writer);
        sRegistry.applyMigration(migrationB, onto(writer, MIGRATION_HEAD_GENESIS));
        assertEq(sRegistry.head(writer), migrationA);
    }

    /// The entries after the head are refused, as keys and then as records,
    /// before the first entry is checked against the head: a wrong head is
    /// reported only once everything after it holds.
    function testApplyMigrationLaterEntriesCheckedBeforeTheFirst(
        address writer,
        address other,
        bytes32 migration,
        bytes32 prerequisite,
        bytes32 wrongHead
    ) external {
        vm.assume(writer != address(0));
        vm.assume(other != address(0));
        vm.assume(writer != other);
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, prerequisite);
        vm.assume(migration != prerequisite);
        vm.assume(wrongHead != MIGRATION_HEAD_GENESIS);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroWriter.selector));
        vm.prank(writer);
        sRegistry.applyMigration(migration, headThen(writer, wrongHead, one(address(0), prerequisite)));

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.PrerequisiteNotApplied.selector, other, prerequisite)
        );
        vm.prank(writer);
        sRegistry.applyMigration(migration, headThen(writer, wrongHead, one(other, prerequisite)));

        applyUnder(other, prerequisite);

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.UnexpectedMigrationHead.selector, writer, wrongHead, MIGRATION_HEAD_GENESIS
            )
        );
        vm.prank(writer);
        sRegistry.applyMigration(migration, headThen(writer, wrongHead, one(other, prerequisite)));
        assertEq(sRegistry.applied(writer, migration), 0);
    }

    /// A migration already applied is reported before an empty list is: the
    /// re-dispatch is told the migration ran, whatever it named as its head.
    function testApplyMigrationAlreadyAppliedCheckedBeforeEmptyList(address writer, bytes32 migration) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        vm.warp(1000);

        vm.prank(writer);
        sRegistry.applyMigration(migration, onto(writer, MIGRATION_HEAD_GENESIS));

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.MigrationAlreadyApplied.selector, writer, migration)
        );
        vm.prank(writer);
        sRegistry.applyMigration(migration, new Prerequisite[](0));
        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.MigrationAlreadyApplied.selector, writer, migration)
        );
        vm.prank(writer);
        sRegistry.applyMigrationHistory(migration, 1000, new Prerequisite[](0));
    }

    /// The record is the list as given, on both writes: `appliedAfter`
    /// answers exactly what was passed and `appliedOnto` answers its first
    /// entry's migration.
    function testApplyMigrationRecordIsTheListAsGiven(
        address writer,
        address other,
        bytes32 migrationA,
        bytes32 migrationB,
        bytes32 prerequisite
    ) external {
        vm.assume(writer != address(0));
        vm.assume(other != address(0));
        vm.assume(writer != other);
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        LibMigrationFuzz.assumeMigration(vm, prerequisite);
        vm.assume(migrationA != migrationB);
        vm.assume(migrationA != prerequisite);
        vm.assume(migrationB != prerequisite);
        vm.warp(1000);

        applyUnder(other, prerequisite);

        Prerequisite[] memory listA = headThen(writer, MIGRATION_HEAD_GENESIS, one(other, prerequisite));
        vm.prank(writer);
        sRegistry.applyMigration(migrationA, listA);
        assertEq(abi.encode(sRegistry.appliedAfter(writer, migrationA)), abi.encode(listA));
        assertEq(sRegistry.appliedOnto(writer, migrationA), listA[0].migration);
        assertEq(sRegistry.appliedOnto(writer, migrationA), MIGRATION_HEAD_GENESIS);

        Prerequisite[] memory listB = headThen(writer, migrationA, one(other, prerequisite));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(migrationB, 1000, listB);
        assertEq(abi.encode(sRegistry.appliedAfter(writer, migrationB)), abi.encode(listB));
        assertEq(sRegistry.appliedOnto(writer, migrationB), listB[0].migration);
        assertEq(sRegistry.appliedOnto(writer, migrationB), migrationA);
    }

    /// An entry after the head in the caller's own namespace is refused as a
    /// key, before any record is read, on both writes: the head already says
    /// everything about the caller's own line.
    function testApplyMigrationOwnEntryAfterTheHeadReverts(address writer, bytes32 migration, bytes32 own) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, own);
        vm.assume(migration != own);
        vm.warp(1000);

        Prerequisite[] memory listed = headThen(writer, MIGRATION_HEAD_GENESIS, one(writer, own));
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.OwnPrerequisite.selector, own));
        vm.prank(writer);
        sRegistry.applyMigration(migration, listed);
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.OwnPrerequisite.selector, own));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(migration, 1000, listed);

        // Applied or not makes no difference: it is refused as a key.
        applyUnder(writer, own);
        listed = headThen(writer, own, one(writer, own));
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.OwnPrerequisite.selector, own));
        vm.prank(writer);
        sRegistry.applyMigration(migration, listed);
        assertEq(sRegistry.applied(writer, migration), 0);
    }
}
