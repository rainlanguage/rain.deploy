// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, Vm} from "forge-std-1.16.1/src/Test.sol";

import {IMigrationRegistryV2, MIGRATION_HEAD_GENESIS} from "../../../src/interface/IMigrationRegistryV2.sol";
import {MigrationRegistryV2} from "../../../src/concrete/MigrationRegistryV2.sol";

/// @title MigrationRegistryV2ApplyMigrationTest
/// @notice A test suite for `MigrationRegistryV2.applyMigration`: who a record
/// belongs to, that a migration is applied at most once and only onto the head
/// its caller named, which moments a record may carry, what a record carries,
/// and what it may never become.
contract MigrationRegistryV2ApplyMigrationTest is Test {
    /// The registry under test. Stateful, so a fresh one per test.
    MigrationRegistryV2 internal sRegistry;

    function setUp() external {
        sRegistry = new MigrationRegistryV2();
    }

    /// A migration id that is neither of the two values the head space reserves,
    /// which is what every test that is not about those values wants.
    /// @param migration The fuzzed candidate.
    function assumeMigration(bytes32 migration) internal pure {
        vm.assume(migration != bytes32(0));
        vm.assume(migration != MIGRATION_HEAD_GENESIS);
    }

    /// Anyone may apply, and the record lands under the caller. There is no
    /// authority to be refused by, which is the whole access-control design:
    /// the namespace IS the caller.
    function testApplyMigrationAnyCallerAppliesUnderItself(address writer, bytes32 migration) external {
        vm.assume(writer != address(0));
        assumeMigration(migration);

        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migration, block.timestamp);

        assertEq(sRegistry.applied(writer, migration), block.timestamp);
    }

    /// A record carries the moment the CALLER supplied, which is what lets a
    /// migration that already ran be recorded with the time it ran rather than
    /// the time it was written down. The block the record lands in is not the
    /// value, and a record written long after the fact says so.
    function testApplyMigrationRecordsTheSuppliedMoment(
        address writer,
        bytes32 migration,
        uint32 appliedAt,
        uint32 writtenAt
    ) external {
        vm.assume(writer != address(0));
        assumeMigration(migration);
        vm.assume(appliedAt != 0);
        vm.assume(writtenAt > appliedAt);
        vm.warp(writtenAt);

        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migration, appliedAt);

        assertEq(sRegistry.applied(writer, migration), appliedAt);
        assertTrue(sRegistry.applied(writer, migration) != block.timestamp);
    }

    /// The moment of the current block is an ordinary value for the parameter,
    /// which is what a script recording a migration as it runs passes. There is
    /// one way to write a record and this is it with today's argument.
    function testApplyMigrationCurrentBlockIsAccepted(address writer, bytes32 migration, uint32 now_) external {
        vm.assume(writer != address(0));
        assumeMigration(migration);
        vm.assume(now_ != 0);
        vm.warp(now_);

        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migration, block.timestamp);

        assertEq(sRegistry.applied(writer, migration), now_);
    }

    /// A moment that has not arrived is refused. A record says a migration HAS
    /// run, so a future one is not a late record of anything, and a consumer
    /// measuring an interval since the migration would be subtracting a moment
    /// later than the one it is measuring from.
    function testApplyMigrationFutureTimestampReverts(address writer, bytes32 migration, uint32 now_, uint256 appliedAt)
        external
    {
        vm.assume(writer != address(0));
        assumeMigration(migration);
        vm.warp(now_);
        appliedAt = bound(appliedAt, uint256(now_) + 1, type(uint256).max);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.FutureTimestamp.selector, appliedAt, uint256(now_)));
        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migration, appliedAt);

        assertEq(sRegistry.applied(writer, migration), 0);
        assertEq(sRegistry.head(writer), MIGRATION_HEAD_GENESIS);
    }

    /// One second past the current block is refused, and the current block is
    /// not: the boundary is the block's own timestamp, inclusive.
    function testApplyMigrationFutureBoundary(address writer, bytes32 migration, uint32 now_) external {
        vm.assume(writer != address(0));
        assumeMigration(migration);
        vm.assume(now_ != 0);
        vm.warp(now_);

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.FutureTimestamp.selector, uint256(now_) + 1, uint256(now_))
        );
        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migration, uint256(now_) + 1);

        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migration, uint256(now_));
        assertEq(sRegistry.applied(writer, migration), now_);
    }

    /// A block whose timestamp is zero can hold no record at all: zero is
    /// refused as a moment, and every other moment is still in the future. The
    /// head does not move, so the namespace goes on describing something true
    /// and the migration is still applicable once the clock has moved.
    function testApplyMigrationZeroBlockRecordsNothing(address writer, bytes32 migration, uint256 appliedAt) external {
        vm.assume(writer != address(0));
        assumeMigration(migration);
        vm.assume(appliedAt != 0);
        vm.warp(0);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroTimestamp.selector));
        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migration, 0);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.FutureTimestamp.selector, appliedAt, 0));
        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migration, appliedAt);

        assertEq(sRegistry.applied(writer, migration), 0);
        assertEq(sRegistry.head(writer), MIGRATION_HEAD_GENESIS);

        vm.warp(1);
        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migration, 1);
        assertEq(sRegistry.applied(writer, migration), 1);
    }

    /// A record refuses to be written at all with a zero moment, rather than
    /// write one that `applied` would read back as no record. The head does not
    /// move and the migration can still be applied, which is the only outcome
    /// that leaves the namespace describing something true.
    function testApplyMigrationZeroTimestampReverts(address writer, bytes32 migration, uint32 now_) external {
        vm.assume(writer != address(0));
        assumeMigration(migration);
        vm.assume(now_ != 0);
        vm.warp(now_);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroTimestamp.selector));
        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migration, 0);

        assertEq(sRegistry.applied(writer, migration), 0);
        assertEq(sRegistry.head(writer), MIGRATION_HEAD_GENESIS);

        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migration, 1);
        assertEq(sRegistry.applied(writer, migration), 1);
    }

    /// A namespace that has applied nothing has no record to be after, so every
    /// moment the block allows is accepted — the floor is not the current block,
    /// which is the whole of what backfilling a first migration needs.
    function testApplyMigrationEmptyNamespaceHasNoFloor(
        address writer,
        bytes32 migration,
        uint32 now_,
        uint256 appliedAt
    ) external {
        vm.assume(writer != address(0));
        assumeMigration(migration);
        vm.assume(now_ != 0);
        vm.warp(now_);
        appliedAt = bound(appliedAt, 1, uint256(now_));

        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migration, appliedAt);

        assertEq(sRegistry.applied(writer, migration), appliedAt);
    }

    /// A record may not predate the record of the head it is applied onto. The
    /// head chain is the order the migrations ran in, so a moment behind the one
    /// before it contradicts the sequence it is being appended to.
    function testApplyMigrationBeforeHeadReverts(
        address writer,
        bytes32 migrationA,
        bytes32 migrationB,
        uint32 headAppliedAt,
        uint256 appliedAt
    ) external {
        vm.assume(writer != address(0));
        assumeMigration(migrationA);
        assumeMigration(migrationB);
        vm.assume(migrationA != migrationB);
        vm.assume(headAppliedAt > 1);
        vm.warp(headAppliedAt);
        appliedAt = bound(appliedAt, 1, uint256(headAppliedAt) - 1);

        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migrationA, headAppliedAt);

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.TimestampBeforeHead.selector, writer, migrationA, appliedAt, uint256(headAppliedAt)
            )
        );
        vm.prank(writer);
        sRegistry.applyMigration(migrationA, migrationB, appliedAt);

        assertEq(sRegistry.applied(writer, migrationB), 0);
        assertEq(sRegistry.head(writer), migrationA);
    }

    /// The floor is inclusive. Two migrations applied in one transaction share a
    /// block, and two backfilled migrations known only to the same day share a
    /// moment; the head chain is what orders them, so forcing the moments apart
    /// would make them carry an ordering they do not have.
    function testApplyMigrationEqualToHeadIsAccepted(
        address writer,
        bytes32 migrationA,
        bytes32 migrationB,
        uint32 appliedAt
    ) external {
        vm.assume(writer != address(0));
        assumeMigration(migrationA);
        assumeMigration(migrationB);
        vm.assume(migrationA != migrationB);
        vm.assume(appliedAt != 0);
        vm.warp(appliedAt);

        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migrationA, appliedAt);
        vm.prank(writer);
        sRegistry.applyMigration(migrationA, migrationB, appliedAt);

        assertEq(sRegistry.applied(writer, migrationA), appliedAt);
        assertEq(sRegistry.applied(writer, migrationB), appliedAt);
    }

    /// One second before the head's record is refused, and the head's own moment
    /// is not: the floor is the head's record, inclusive.
    ///
    /// The floor is at least 2, so that one second below it is a moment a record
    /// could otherwise carry. A floor of 1 puts that second at zero, which is
    /// refused as a moment before any floor is consulted — a true refusal of a
    /// different rule, and one that says nothing about where this boundary sits.
    function testApplyMigrationFloorBoundary(address writer, bytes32 migrationA, bytes32 migrationB, uint32 now_)
        external
    {
        vm.assume(writer != address(0));
        assumeMigration(migrationA);
        assumeMigration(migrationB);
        vm.assume(migrationA != migrationB);
        vm.assume(now_ > 2);
        vm.warp(now_);

        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migrationA, uint256(now_) - 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.TimestampBeforeHead.selector,
                writer,
                migrationA,
                uint256(now_) - 2,
                uint256(now_) - 1
            )
        );
        vm.prank(writer);
        sRegistry.applyMigration(migrationA, migrationB, uint256(now_) - 2);

        vm.prank(writer);
        sRegistry.applyMigration(migrationA, migrationB, uint256(now_) - 1);
        assertEq(sRegistry.applied(writer, migrationB), uint256(now_) - 1);
    }

    /// The floor follows the HEAD's record rather than staying at whatever the
    /// first one was, so a sequence backfilled in head order keeps every moment
    /// it was given and each step is measured against the step before it.
    function testApplyMigrationFloorFollowsTheHead(
        address writer,
        bytes32 migrationA,
        bytes32 migrationB,
        bytes32 migrationC
    ) external {
        vm.assume(writer != address(0));
        assumeMigration(migrationA);
        assumeMigration(migrationB);
        assumeMigration(migrationC);
        vm.assume(migrationA != migrationB);
        vm.assume(migrationB != migrationC);
        vm.assume(migrationA != migrationC);

        vm.warp(9000);
        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migrationA, 1000);
        vm.prank(writer);
        sRegistry.applyMigration(migrationA, migrationB, 2000);

        // Above the first record and below the second, so a floor that had
        // stayed at the first would accept this.
        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.TimestampBeforeHead.selector, writer, migrationB, uint256(1500), uint256(2000)
            )
        );
        vm.prank(writer);
        sRegistry.applyMigration(migrationB, migrationC, 1500);

        vm.prank(writer);
        sRegistry.applyMigration(migrationB, migrationC, 3000);

        assertEq(sRegistry.applied(writer, migrationA), 1000);
        assertEq(sRegistry.applied(writer, migrationB), 2000);
        assertEq(sRegistry.applied(writer, migrationC), 3000);
    }

    /// The floor belongs to one namespace. Another writer's records say nothing
    /// about what this one may record, which is the same confinement the records
    /// and the heads already have.
    function testApplyMigrationFloorIsPerWriter(address writer, address other, bytes32 migrationA, bytes32 migrationB)
        external
    {
        vm.assume(writer != address(0));
        vm.assume(other != address(0));
        vm.assume(writer != other);
        assumeMigration(migrationA);
        assumeMigration(migrationB);
        vm.assume(migrationA != migrationB);

        vm.warp(9000);
        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migrationA, 5000);

        vm.prank(other);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migrationB, 1000);

        assertEq(sRegistry.applied(other, migrationB), 1000);
    }

    /// Two migrations applied at different moments carry those moments, and the
    /// earlier one does not move when the later one lands. A record is of the
    /// moment it happened, not of the last time anything happened.
    function testApplyMigrationTimestampsAreIndependent(address writer, bytes32 migrationA, bytes32 migrationB)
        external
    {
        vm.assume(writer != address(0));
        assumeMigration(migrationA);
        assumeMigration(migrationB);
        vm.assume(migrationA != migrationB);

        vm.warp(1000);
        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migrationA, 1000);

        vm.warp(2000);
        vm.prank(writer);
        sRegistry.applyMigration(migrationA, migrationB, 2000);

        assertEq(sRegistry.applied(writer, migrationA), 1000);
        assertEq(sRegistry.applied(writer, migrationB), 2000);
    }

    /// The zero moment is refused BEFORE anything about the namespace is read,
    /// so an uninitialised argument is reported as itself rather than as
    /// whatever the namespace happens to make of it. Fuzzed over the head and
    /// checked against a namespace that has moved on, because a head the
    /// namespace happens to be at is accepted whichever check runs first.
    function testApplyMigrationZeroTimestampCheckedBeforeTheNamespace(
        address writer,
        bytes32 migrationA,
        bytes32 migrationB,
        bytes32 anyHead
    ) external {
        vm.assume(writer != address(0));
        assumeMigration(migrationA);
        assumeMigration(migrationB);
        vm.assume(migrationA != migrationB);

        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migrationA, block.timestamp);

        // Already applied, and a zero moment: told about the moment.
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroTimestamp.selector));
        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migrationA, 0);

        // A head that has moved on, and a zero moment: told about the moment.
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroTimestamp.selector));
        vm.prank(writer);
        sRegistry.applyMigration(anyHead, migrationB, 0);
    }

    /// The two id refusals come before the moment, so a caller that has zeroed
    /// both an id and a moment is told about the id: an id is what the record
    /// is ABOUT, and a call with no subject has nothing to say a moment for.
    function testApplyMigrationIdCheckedBeforeTimestamp(address writer, bytes32 anyHead) external {
        vm.assume(writer != address(0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(anyHead, bytes32(0), 0);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.GenesisMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(anyHead, MIGRATION_HEAD_GENESIS, 0);
    }

    /// The refusals that describe the NAMESPACE come before the two that
    /// describe the moment against it, so a re-dispatched script is told its
    /// migration already ran, and a script at the wrong point in the sequence is
    /// told where the namespace is, rather than either of them being sent to
    /// look at a clock.
    function testApplyMigrationNamespaceCheckedBeforeTheWindow(
        address writer,
        bytes32 migrationA,
        bytes32 migrationB,
        bytes32 skipped
    ) external {
        vm.assume(writer != address(0));
        assumeMigration(migrationA);
        assumeMigration(migrationB);
        assumeMigration(skipped);
        vm.assume(migrationA != migrationB);
        vm.assume(skipped != migrationA);
        vm.assume(skipped != migrationB);

        vm.warp(9000);
        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migrationA, 5000);

        // Already applied, and backdated: told it already ran.
        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.MigrationAlreadyApplied.selector, writer, migrationA)
        );
        vm.prank(writer);
        sRegistry.applyMigration(migrationA, migrationA, 1000);

        // Already applied, and in the future: told it already ran.
        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.MigrationAlreadyApplied.selector, writer, migrationA)
        );
        vm.prank(writer);
        sRegistry.applyMigration(migrationA, migrationA, 9001);

        // The wrong head, and backdated: told where the namespace is.
        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.UnexpectedMigrationHead.selector, writer, skipped, migrationA)
        );
        vm.prank(writer);
        sRegistry.applyMigration(skipped, migrationB, 1000);

        // The wrong head, and in the future: told where the namespace is.
        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.UnexpectedMigrationHead.selector, writer, skipped, migrationA)
        );
        vm.prank(writer);
        sRegistry.applyMigration(skipped, migrationB, 9001);
    }

    /// A record is confined to the caller's namespace. Applying under one
    /// writer says nothing about any other, which is what makes a reader's
    /// choice of namespace the whole of who it trusts — a hostile caller can
    /// apply whatever it likes and reach nobody.
    function testApplyMigrationDoesNotReachAnotherNamespace(address writer, address other, bytes32 migration) external {
        vm.assume(writer != address(0));
        vm.assume(other != address(0));
        vm.assume(writer != other);
        assumeMigration(migration);

        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migration, block.timestamp);

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
        assumeMigration(migration);

        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migration, block.timestamp);
        vm.prank(other);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migration, block.timestamp);

        assertEq(sRegistry.applied(writer, migration), block.timestamp);
        assertEq(sRegistry.applied(other, migration), block.timestamp);
    }

    /// Migrations are independent within one namespace: applying one says
    /// nothing about any other. This is what a set buys over a high-water mark
    /// — a reader asks about the migration its assertion actually depends on
    /// rather than about a number that stands in for all of them.
    function testApplyMigrationDistinctMigrations(address writer, bytes32 migrationA, bytes32 migrationB) external {
        vm.assume(writer != address(0));
        assumeMigration(migrationA);
        assumeMigration(migrationB);
        vm.assume(migrationA != migrationB);

        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migrationA, block.timestamp);

        assertEq(sRegistry.applied(writer, migrationA), block.timestamp);
        assertEq(sRegistry.applied(writer, migrationB), 0);

        vm.prank(writer);
        sRegistry.applyMigration(migrationA, migrationB, block.timestamp);

        assertEq(sRegistry.applied(writer, migrationA), block.timestamp);
        assertEq(sRegistry.applied(writer, migrationB), block.timestamp);
    }

    /// A successful application makes its migration the namespace's new head,
    /// which is what the next one has to name.
    function testApplyMigrationAdvancesTheHead(address writer, bytes32 migrationA, bytes32 migrationB) external {
        vm.assume(writer != address(0));
        assumeMigration(migrationA);
        assumeMigration(migrationB);
        vm.assume(migrationA != migrationB);

        assertEq(sRegistry.head(writer), MIGRATION_HEAD_GENESIS);

        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migrationA, block.timestamp);
        assertEq(sRegistry.head(writer), migrationA);

        vm.prank(writer);
        sRegistry.applyMigration(migrationA, migrationB, block.timestamp);
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
        assumeMigration(migrationA);
        assumeMigration(migrationB);
        assumeMigration(skipped);
        vm.assume(migrationA != migrationB);
        vm.assume(skipped != migrationA);
        vm.assume(skipped != migrationB);

        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migrationA, block.timestamp);

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.UnexpectedMigrationHead.selector, writer, skipped, migrationA)
        );
        vm.prank(writer);
        sRegistry.applyMigration(skipped, migrationB, block.timestamp);

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
        assumeMigration(migrationA);
        assumeMigration(migrationB);
        vm.assume(migrationA != migrationB);

        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migrationA, block.timestamp);

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.UnexpectedMigrationHead.selector, writer, MIGRATION_HEAD_GENESIS, migrationA
            )
        );
        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migrationB, block.timestamp);
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
        assumeMigration(migrationA);
        assumeMigration(migrationB);
        vm.assume(migrationA != migrationB);

        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migrationA, block.timestamp);

        assertEq(sRegistry.head(other), MIGRATION_HEAD_GENESIS);

        // The other namespace is still at genesis, so `migrationA` is not the
        // head there and naming it is refused.
        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.UnexpectedMigrationHead.selector, other, migrationA, MIGRATION_HEAD_GENESIS
            )
        );
        vm.prank(other);
        sRegistry.applyMigration(migrationA, migrationB, block.timestamp);

        vm.prank(other);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migrationB, block.timestamp);
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
        assumeMigration(migration);

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.UnexpectedMigrationHead.selector, writer, bytes32(0), MIGRATION_HEAD_GENESIS
            )
        );
        vm.prank(writer);
        sRegistry.applyMigration(bytes32(0), migration, block.timestamp);

        assertEq(sRegistry.applied(writer, migration), 0);
    }

    /// And on a namespace that has applied something.
    function testApplyMigrationZeroHeadRevertsOnUsedNamespace(address writer, bytes32 migrationA, bytes32 migrationB)
        external
    {
        vm.assume(writer != address(0));
        assumeMigration(migrationA);
        assumeMigration(migrationB);
        vm.assume(migrationA != migrationB);

        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migrationA, block.timestamp);

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.UnexpectedMigrationHead.selector, writer, bytes32(0), migrationA
            )
        );
        vm.prank(writer);
        sRegistry.applyMigration(bytes32(0), migrationB, block.timestamp);
    }

    /// Applying twice is refused. This is what makes running a migration twice
    /// fail rather than repeat: a re-dispatched script cannot quietly apply
    /// its way to looking like a first run.
    function testApplyMigrationTwiceReverts(address writer, bytes32 migration) external {
        vm.assume(writer != address(0));
        assumeMigration(migration);

        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migration, block.timestamp);

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.MigrationAlreadyApplied.selector, writer, migration)
        );
        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migration, block.timestamp);

        assertEq(sRegistry.applied(writer, migration), block.timestamp);
    }

    /// The head does NOT subsume the already-applied refusal. Re-applying a
    /// migration whose successor has since landed presents a head that matches
    /// perfectly, and is still refused — otherwise the head would move BACKWARDS
    /// and the original moment would be overwritten, which is a record
    /// un-happening.
    function testApplyMigrationAgainOnMatchingHeadReverts(address writer, bytes32 migrationA, bytes32 migrationB)
        external
    {
        vm.assume(writer != address(0));
        assumeMigration(migrationA);
        assumeMigration(migrationB);
        vm.assume(migrationA != migrationB);

        vm.warp(1000);
        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migrationA, 1000);
        vm.prank(writer);
        sRegistry.applyMigration(migrationA, migrationB, 1000);

        // The namespace really is at `migrationB`, so the head this names is
        // correct and only the already-applied refusal can stop it.
        assertEq(sRegistry.head(writer), migrationB);
        vm.warp(2000);
        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.MigrationAlreadyApplied.selector, writer, migrationA)
        );
        vm.prank(writer);
        sRegistry.applyMigration(migrationB, migrationA, 2000);

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
        assumeMigration(migrationA);
        assumeMigration(migrationB);
        vm.assume(migrationA != migrationB);

        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migrationA, block.timestamp);
        vm.prank(writer);
        sRegistry.applyMigration(migrationA, migrationB, block.timestamp);

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.MigrationAlreadyApplied.selector, writer, migrationA)
        );
        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migrationA, block.timestamp);
    }

    /// A migration another writer has already applied is still a FIRST record
    /// for this one. The refusal is per namespace, not global, or one consumer
    /// choosing a common id would lock every other consumer out of it.
    function testApplyMigrationTwiceIsPerWriter(address writer, address other, bytes32 migration) external {
        vm.assume(writer != address(0));
        vm.assume(other != address(0));
        vm.assume(writer != other);
        assumeMigration(migration);

        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migration, block.timestamp);

        vm.prank(other);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migration, block.timestamp);

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
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, bytes32(0), block.timestamp);
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
        assumeMigration(migration);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(anyHead, bytes32(0), block.timestamp);

        // A namespace that has moved on: the zero id is still reported as
        // `ZeroMigration` rather than as anything about the head or about what
        // has already been applied.
        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migration, block.timestamp);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(anyHead, bytes32(0), block.timestamp);
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
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, MIGRATION_HEAD_GENESIS, block.timestamp);

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
        assumeMigration(migration);

        // An empty namespace, whose head is genesis: still refused onto a head
        // that does not match it.
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.GenesisMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(anyHead, MIGRATION_HEAD_GENESIS, block.timestamp);

        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migration, block.timestamp);

        // A namespace that has moved: same refusal, onto the head it is at and
        // onto any other.
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.GenesisMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(migration, MIGRATION_HEAD_GENESIS, block.timestamp);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.GenesisMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(anyHead, MIGRATION_HEAD_GENESIS, block.timestamp);

        assertEq(sRegistry.head(writer), migration);
    }

    /// Ids are opaque: nothing about a migration's bytes changes how it is
    /// stored or read, including ids no hashing convention would produce.
    function testApplyMigrationOpaqueMigrationIds(address writer) external {
        vm.assume(writer != address(0));

        bytes32[2] memory migrations = [bytes32(uint256(1)), bytes32(type(uint256).max)];
        for (uint256 i = 0; i < migrations.length; i++) {
            MigrationRegistryV2 registry = new MigrationRegistryV2();
            vm.prank(writer);
            registry.applyMigration(MIGRATION_HEAD_GENESIS, migrations[i], block.timestamp);
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
    function testApplyMigrationEvent(address writer, bytes32 migration, uint32 appliedAt, uint32 writtenAt) external {
        vm.assume(writer != address(0));
        assumeMigration(migration);
        vm.assume(appliedAt != 0);
        vm.assume(writtenAt > appliedAt);
        vm.warp(writtenAt);

        vm.recordLogs();
        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migration, appliedAt);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        assertEq(entries.length, 1);
        assertEq(entries[0].emitter, address(sRegistry));
        assertEq(entries[0].topics.length, 3);
        assertEq(entries[0].topics[0], keccak256("Migrated(address,bytes32,uint256)"));
        assertEq(entries[0].topics[1], bytes32(uint256(uint160(writer))));
        assertEq(entries[0].topics[2], migration);
        assertEq(entries[0].data, abi.encode(uint256(appliedAt)));
    }

    /// A refused `applyMigration` emits nothing, so a failed apply can never be
    /// mistaken for a record by anything reading the logs — which for a
    /// re-dispatched migration is exactly the mistake that matters.
    function testApplyMigrationNoEventOnRevert(address writer, bytes32 migration) external {
        vm.assume(writer != address(0));
        assumeMigration(migration);

        vm.warp(9000);
        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migration, 5000);

        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.MigrationAlreadyApplied.selector, writer, migration)
        );
        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migration, 5000);
        assertEq(vm.getRecordedLogs().length, 0);

        vm.recordLogs();
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(migration, bytes32(0), 5000);
        assertEq(vm.getRecordedLogs().length, 0);

        vm.recordLogs();
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.GenesisMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(migration, MIGRATION_HEAD_GENESIS, 5000);
        assertEq(vm.getRecordedLogs().length, 0);

        vm.recordLogs();
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroTimestamp.selector));
        vm.prank(writer);
        sRegistry.applyMigration(migration, keccak256(abi.encode(migration)), 0);
        assertEq(vm.getRecordedLogs().length, 0);

        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.UnexpectedMigrationHead.selector, writer, MIGRATION_HEAD_GENESIS, migration
            )
        );
        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, keccak256(abi.encode(migration)), 5000);
        assertEq(vm.getRecordedLogs().length, 0);

        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.TimestampBeforeHead.selector, writer, migration, uint256(4999), uint256(5000)
            )
        );
        vm.prank(writer);
        sRegistry.applyMigration(migration, keccak256(abi.encode(migration)), 4999);
        assertEq(vm.getRecordedLogs().length, 0);

        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.FutureTimestamp.selector, uint256(9001), uint256(9000))
        );
        vm.prank(writer);
        sRegistry.applyMigration(migration, keccak256(abi.encode(migration)), 9001);
        assertEq(vm.getRecordedLogs().length, 0);
    }
}
