// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, Vm} from "forge-std-1.16.2/src/Test.sol";

import {IMigrationRegistryV1, MIGRATION_HEAD_GENESIS} from "../../../src/interface/IMigrationRegistryV1.sol";
import {MigrationRegistry} from "../../../src/concrete/MigrationRegistry.sol";
import {LibMigrationFuzz} from "../../lib/LibMigrationFuzz.sol";

/// @title MigrationRegistryApplyMigrationTest
/// @notice A test suite for `MigrationRegistry.applyMigration` and
/// `MigrationRegistry.applyMigrationHistory`: who a record belongs to, that a
/// migration is applied at most once and only onto the head its caller named,
/// which moments a record may carry, what a record carries, and what it may
/// never become.
contract MigrationRegistryApplyMigrationTest is Test {
    /// The registry under test. Stateful, so a fresh one per test.
    MigrationRegistry internal sRegistry;

    function setUp() external {
        sRegistry = new MigrationRegistry();
    }

    /// Anyone may apply, and the record lands under the caller. There is no
    /// authority to be refused by, which is the whole access-control design:
    /// the namespace IS the caller.
    function testApplyMigrationAnyCallerAppliesUnderItself(address writer, bytes32 migration) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeMigration(vm, migration);

        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migration);

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
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migration);

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
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migrationA);

        vm.warp(2000);
        vm.prank(writer);
        sRegistry.applyMigration(migrationA, migrationB);

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

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.ZeroTimestamp.selector));
        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migration);

        assertEq(sRegistry.applied(writer, migration), 0);
        assertEq(sRegistry.head(writer), MIGRATION_HEAD_GENESIS);

        vm.warp(1);
        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migration);
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
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migrationA);

        vm.warp(0);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.ZeroMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(anyHead, bytes32(0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.GenesisMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(anyHead, MIGRATION_HEAD_GENESIS);

        // Already applied, in a block that can hold no record: told about the
        // moment, because the record could not be written whatever namespace it
        // arrived at.
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.ZeroTimestamp.selector));
        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migrationA);

        // A head the namespace has moved on from, in the same block: told about
        // the moment.
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.ZeroTimestamp.selector));
        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migrationB);
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
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migration);

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
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migration);
        vm.prank(other);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migration);

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
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migrationA);

        assertEq(sRegistry.applied(writer, migrationA), block.timestamp);
        assertEq(sRegistry.applied(writer, migrationB), 0);

        vm.prank(writer);
        sRegistry.applyMigration(migrationA, migrationB);

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
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migrationA);
        assertEq(sRegistry.head(writer), migrationA);

        vm.prank(writer);
        sRegistry.applyMigration(migrationA, migrationB);
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
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migrationA);

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV1.UnexpectedMigrationHead.selector, writer, skipped, migrationA)
        );
        vm.prank(writer);
        sRegistry.applyMigration(skipped, migrationB);

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
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migrationA);

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV1.UnexpectedMigrationHead.selector, writer, MIGRATION_HEAD_GENESIS, migrationA
            )
        );
        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migrationB);
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
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migrationA);

        assertEq(sRegistry.head(other), MIGRATION_HEAD_GENESIS);

        // The other namespace is still at genesis, so `migrationA` is not the
        // head there and naming it is refused.
        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV1.UnexpectedMigrationHead.selector, other, migrationA, MIGRATION_HEAD_GENESIS
            )
        );
        vm.prank(other);
        sRegistry.applyMigration(migrationA, migrationB);

        vm.prank(other);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migrationB);
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
                IMigrationRegistryV1.UnexpectedMigrationHead.selector, writer, bytes32(0), MIGRATION_HEAD_GENESIS
            )
        );
        vm.prank(writer);
        sRegistry.applyMigration(bytes32(0), migration);

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
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migrationA);

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV1.UnexpectedMigrationHead.selector, writer, bytes32(0), migrationA
            )
        );
        vm.prank(writer);
        sRegistry.applyMigration(bytes32(0), migrationB);
    }

    /// Applying twice is refused. This is what makes running a migration twice
    /// fail rather than repeat: a re-dispatched script cannot quietly apply
    /// its way to looking like a first run.
    function testApplyMigrationTwiceReverts(address writer, bytes32 migration) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeMigration(vm, migration);

        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migration);

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV1.MigrationAlreadyApplied.selector, writer, migration)
        );
        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migration);

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
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migrationA);
        vm.prank(writer);
        sRegistry.applyMigration(migrationA, migrationB);

        // The namespace really is at `migrationB`, so the head this names is
        // correct and only the already-applied refusal can stop it.
        assertEq(sRegistry.head(writer), migrationB);
        vm.warp(2000);
        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV1.MigrationAlreadyApplied.selector, writer, migrationA)
        );
        vm.prank(writer);
        sRegistry.applyMigration(migrationB, migrationA);

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
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migrationA);
        vm.prank(writer);
        sRegistry.applyMigration(migrationA, migrationB);

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV1.MigrationAlreadyApplied.selector, writer, migrationA)
        );
        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migrationA);
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
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migration);

        vm.prank(other);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migration);

        assertEq(sRegistry.applied(other, migration), block.timestamp);
    }

    /// The zero migration id is refused. It is what an uninitialised `bytes32`
    /// constant reads as, and there is deliberately no way to apply one, which
    /// is what lets `applied` refuse it as a mistake rather than have to answer
    /// about it.
    function testApplyMigrationZeroMigrationReverts(address writer) external {
        vm.assume(writer != address(0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.ZeroMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, bytes32(0));
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

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.ZeroMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(anyHead, bytes32(0));

        // A namespace that has moved on: the zero id is still reported as
        // `ZeroMigration` rather than as anything about the head or about what
        // has already been applied.
        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migration);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.ZeroMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(anyHead, bytes32(0));
    }

    /// Genesis is a head, not a migration, and applying it is refused. It would
    /// otherwise leave the namespace's head holding the exact value an empty
    /// namespace reads as, so a namespace that had applied something would be
    /// indistinguishable from one that had not — and the next first-migration
    /// script would be accepted against it.
    function testApplyMigrationGenesisMigrationReverts(address writer) external {
        vm.assume(writer != address(0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.GenesisMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, MIGRATION_HEAD_GENESIS);

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
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.GenesisMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(anyHead, MIGRATION_HEAD_GENESIS);

        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migration);

        // A namespace that has moved: same refusal, onto the head it is at and
        // onto any other.
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.GenesisMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(migration, MIGRATION_HEAD_GENESIS);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.GenesisMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(anyHead, MIGRATION_HEAD_GENESIS);

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
            registry.applyMigration(MIGRATION_HEAD_GENESIS, migrations[i]);
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
        sRegistry.applyMigrationHistory(MIGRATION_HEAD_GENESIS, migration, appliedAt);
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
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migration);
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
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migration);

        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV1.MigrationAlreadyApplied.selector, writer, migration)
        );
        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migration);
        assertEq(vm.getRecordedLogs().length, 0);

        vm.recordLogs();
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.ZeroMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(migration, bytes32(0));
        assertEq(vm.getRecordedLogs().length, 0);

        vm.recordLogs();
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.GenesisMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(migration, MIGRATION_HEAD_GENESIS);
        assertEq(vm.getRecordedLogs().length, 0);

        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV1.UnexpectedMigrationHead.selector, writer, MIGRATION_HEAD_GENESIS, migration
            )
        );
        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, keccak256(abi.encode(migration)));
        assertEq(vm.getRecordedLogs().length, 0);

        vm.recordLogs();
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.ZeroTimestamp.selector));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(migration, keccak256(abi.encode(migration)), 0);
        assertEq(vm.getRecordedLogs().length, 0);

        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV1.FutureTimestamp.selector, block.timestamp + 1, block.timestamp)
        );
        vm.prank(writer);
        sRegistry.applyMigrationHistory(migration, keccak256(abi.encode(migration)), block.timestamp + 1);
        assertEq(vm.getRecordedLogs().length, 0);

        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV1.TimestampBeforeHead.selector, block.timestamp - 1, 1000)
        );
        vm.prank(writer);
        sRegistry.applyMigrationHistory(migration, keccak256(abi.encode(migration)), block.timestamp - 1);
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
        sRegistry.applyMigrationHistory(MIGRATION_HEAD_GENESIS, migration, appliedAt);

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
        sRegistry.applyMigrationHistory(MIGRATION_HEAD_GENESIS, migration, block.timestamp);

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
        stamping.applyMigration(MIGRATION_HEAD_GENESIS, migrationA);
        vm.prank(writer);
        supplied.applyMigrationHistory(MIGRATION_HEAD_GENESIS, migrationA, block.timestamp);

        vm.prank(writer);
        stamping.applyMigration(migrationA, migrationB);
        vm.prank(writer);
        supplied.applyMigrationHistory(migrationA, migrationB, block.timestamp);

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

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.FutureTimestamp.selector, appliedAt, uint256(now_)));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(MIGRATION_HEAD_GENESIS, migration, appliedAt);

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
            abi.encodeWithSelector(IMigrationRegistryV1.FutureTimestamp.selector, uint256(now_) + 1, uint256(now_))
        );
        vm.prank(writer);
        sRegistry.applyMigrationHistory(MIGRATION_HEAD_GENESIS, migration, uint256(now_) + 1);

        vm.prank(writer);
        sRegistry.applyMigrationHistory(MIGRATION_HEAD_GENESIS, migration, uint256(now_));
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

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.ZeroTimestamp.selector));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(MIGRATION_HEAD_GENESIS, migration, 0);

        assertEq(sRegistry.applied(writer, migration), 0);
        assertEq(sRegistry.head(writer), MIGRATION_HEAD_GENESIS);

        vm.prank(writer);
        sRegistry.applyMigrationHistory(MIGRATION_HEAD_GENESIS, migration, 1);
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

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.ZeroTimestamp.selector));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(MIGRATION_HEAD_GENESIS, migration, 0);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.FutureTimestamp.selector, appliedAt, 0));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(MIGRATION_HEAD_GENESIS, migration, appliedAt);

        assertEq(sRegistry.applied(writer, migration), 0);
        assertEq(sRegistry.head(writer), MIGRATION_HEAD_GENESIS);

        vm.warp(1);
        vm.prank(writer);
        sRegistry.applyMigrationHistory(MIGRATION_HEAD_GENESIS, migration, 1);
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
        sRegistry.applyMigrationHistory(MIGRATION_HEAD_GENESIS, migrationA, block.timestamp);

        // Already applied, and a zero moment: told about the moment.
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.ZeroTimestamp.selector));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(MIGRATION_HEAD_GENESIS, migrationA, 0);

        // A head that has moved on, and a zero moment: told about the moment.
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.ZeroTimestamp.selector));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(anyHead, migrationB, 0);
    }

    /// The two id refusals come before the moment, so a caller that has zeroed
    /// both an id and a moment is told about the id: an id is what the record is
    /// ABOUT, and a call with no subject has nothing to say a moment for.
    function testApplyMigrationHistoryIdCheckedBeforeTimestamp(address writer, bytes32 anyHead) external {
        vm.assume(writer != address(0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.ZeroMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(anyHead, bytes32(0), 0);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.GenesisMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(anyHead, MIGRATION_HEAD_GENESIS, 0);
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
        sRegistry.applyMigrationHistory(MIGRATION_HEAD_GENESIS, migrationA, 5000);

        // Already applied, and in the future: told it already ran.
        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV1.MigrationAlreadyApplied.selector, writer, migrationA)
        );
        vm.prank(writer);
        sRegistry.applyMigrationHistory(migrationA, migrationA, 9001);

        // The wrong head, and in the future: told where the namespace is.
        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV1.UnexpectedMigrationHead.selector, writer, skipped, migrationA)
        );
        vm.prank(writer);
        sRegistry.applyMigrationHistory(skipped, migrationB, 9001);
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
        sRegistry.applyMigrationHistory(MIGRATION_HEAD_GENESIS, migrationA, uint256(now_));

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV1.TimestampBeforeHead.selector, earlier, uint256(now_))
        );
        vm.prank(writer);
        sRegistry.applyMigrationHistory(migrationA, migrationB, earlier);

        assertEq(sRegistry.applied(writer, migrationB), 0);
        assertEq(sRegistry.appliedOnto(writer, migrationB), bytes32(0));
        assertEq(sRegistry.head(writer), migrationA);

        vm.prank(writer);
        sRegistry.applyMigrationHistory(migrationA, migrationB, uint256(now_));
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
        sRegistry.applyMigrationHistory(MIGRATION_HEAD_GENESIS, migrationA, uint256(headAppliedAt));

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV1.TimestampBeforeHead.selector, uint256(headAppliedAt) - 1, uint256(headAppliedAt)
            )
        );
        vm.prank(writer);
        sRegistry.applyMigrationHistory(migrationA, migrationB, uint256(headAppliedAt) - 1);

        vm.prank(writer);
        sRegistry.applyMigrationHistory(migrationA, migrationB, uint256(headAppliedAt));
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
        sRegistry.applyMigrationHistory(MIGRATION_HEAD_GENESIS, migrationA, uint256(first));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(migrationA, migrationB, uint256(second));

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
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.GenesisMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(MIGRATION_HEAD_GENESIS, MIGRATION_HEAD_GENESIS, uint256(now_));

        vm.prank(writer);
        sRegistry.applyMigrationHistory(MIGRATION_HEAD_GENESIS, migration, 1);

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
        sRegistry.applyMigrationHistory(MIGRATION_HEAD_GENESIS, migrationA, 9000);

        // Already applied, and before the head's moment: told it already ran.
        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV1.MigrationAlreadyApplied.selector, writer, migrationA)
        );
        vm.prank(writer);
        sRegistry.applyMigrationHistory(migrationA, migrationA, 1);

        // The wrong head, and before the head's moment: told where the
        // namespace is.
        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV1.UnexpectedMigrationHead.selector, writer, skipped, migrationA)
        );
        vm.prank(writer);
        sRegistry.applyMigrationHistory(skipped, migrationB, 1);

        // A zero moment, which is also before the head's: told about the zero.
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.ZeroTimestamp.selector));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(migrationA, migrationB, 0);

        // With nothing else wrong, the head's moment is what refuses it.
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.TimestampBeforeHead.selector, 1, 9000));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(migrationA, migrationB, 1);
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
        sRegistry.applyMigrationHistory(MIGRATION_HEAD_GENESIS, migrationA, 9000);

        vm.prank(other);
        sRegistry.applyMigrationHistory(MIGRATION_HEAD_GENESIS, migrationB, 1);

        assertEq(sRegistry.applied(other, migrationB), 1);

        // And the other namespace's own head bounds it from there.
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.TimestampBeforeHead.selector, 1, 9000));
        vm.prank(writer);
        sRegistry.applyMigrationHistory(migrationA, migrationB, 1);
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
        sRegistry.applyMigrationHistory(MIGRATION_HEAD_GENESIS, migrationA, appliedAt);
        vm.prank(writer);
        sRegistry.applyMigrationHistory(migrationA, migrationB, appliedAt);

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
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migrationA);
        assertEq(sRegistry.appliedOnto(writer, migrationA), MIGRATION_HEAD_GENESIS);

        vm.prank(writer);
        sRegistry.applyMigration(migrationA, migrationB);
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
        sRegistry.applyMigrationHistory(MIGRATION_HEAD_GENESIS, migrationA, 3000);
        vm.prank(writer);
        sRegistry.applyMigrationHistory(migrationA, migrationB, 3000);
        vm.prank(writer);
        sRegistry.applyMigrationHistory(migrationB, migrationC, 3000);

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
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migrationA);
        vm.prank(writer);
        sRegistry.applyMigration(migrationA, migrationB);

        // The other namespace applies them in the opposite order, so a chain
        // that leaked would be visibly the first one's.
        vm.prank(other);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migrationB);
        vm.prank(other);
        sRegistry.applyMigration(migrationB, migrationA);

        assertEq(sRegistry.appliedOnto(writer, migrationA), MIGRATION_HEAD_GENESIS);
        assertEq(sRegistry.appliedOnto(writer, migrationB), migrationA);
        assertEq(sRegistry.appliedOnto(other, migrationB), MIGRATION_HEAD_GENESIS);
        assertEq(sRegistry.appliedOnto(other, migrationA), migrationB);
    }
}
