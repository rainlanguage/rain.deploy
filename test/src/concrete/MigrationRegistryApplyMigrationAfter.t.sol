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

/// @title MigrationRegistryApplyMigrationAfterTest
/// @notice A test suite for `MigrationRegistry.applyMigrationAfter` and
/// `MigrationRegistry.applyMigrationHistoryAfter`: that each is its plain write
/// exactly once every prerequisite is applied, which prerequisite is named
/// when one is not, which prerequisites are refused as keys before any is
/// read, where in the order of refusals the prerequisites sit, and what the
/// two writes put in the log.
contract MigrationRegistryApplyMigrationAfterTest is Test {
    /// The registry under test. Stateful, so a fresh one per test.
    MigrationRegistry internal sRegistry;

    function setUp() external {
        sRegistry = new MigrationRegistry();
    }

    /// One prerequisite, as a list. Most cases here wait on exactly one thing
    /// and the entry point takes a list, so this is the list.
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
        sRegistry.applyMigration(head, migration);
    }

    /// With its one prerequisite applied, `applyMigrationAfter` writes exactly
    /// what `applyMigration` writes: the same moment, the same head applied
    /// onto, the same new head — and the same STORAGE SLOTS, so nothing about
    /// the prerequisites was recorded anywhere. Two registries with the same
    /// prior state are written by the two entry points and compared, which is
    /// what makes "nothing new is stored" a fact about the slots rather than a
    /// fact about the three readers.
    function testApplyMigrationAfterWritesThePlainRecord(
        address writer,
        address other,
        bytes32 migration,
        bytes32 prerequisite,
        uint32 now_
    ) external {
        vm.assume(writer != address(0));
        vm.assume(other != address(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, prerequisite);
        vm.assume(migration != prerequisite);
        vm.assume(now_ != 0);
        vm.warp(now_);

        MigrationRegistry plain = new MigrationRegistry();
        MigrationRegistry waiting = new MigrationRegistry();
        vm.prank(other);
        plain.applyMigration(MIGRATION_HEAD_GENESIS, prerequisite);
        vm.prank(other);
        waiting.applyMigration(MIGRATION_HEAD_GENESIS, prerequisite);

        bytes32 plainHead = plain.head(writer);
        bytes32 waitingHead = waiting.head(writer);
        vm.record();
        vm.prank(writer);
        plain.applyMigration(plainHead, migration);
        (, bytes32[] memory plainWrites) = vm.accesses(address(plain));
        vm.prank(writer);
        waiting.applyMigrationAfter(waitingHead, migration, one(other, prerequisite));
        (, bytes32[] memory afterWrites) = vm.accesses(address(waiting));

        assertEq(waiting.applied(writer, migration), plain.applied(writer, migration));
        assertEq(waiting.applied(writer, migration), now_);
        assertEq(waiting.appliedOnto(writer, migration), plain.appliedOnto(writer, migration));
        assertEq(waiting.head(writer), plain.head(writer));
        assertEq(waiting.head(writer), migration);
        assertEq(afterWrites, plainWrites);
        assertTrue(afterWrites.length > 0);
    }

    /// The same for `applyMigrationHistoryAfter` against
    /// `applyMigrationHistory`: the supplied moment is what is recorded, onto
    /// the same head, into the same slots.
    function testApplyMigrationHistoryAfterWritesThePlainRecord(
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
        // `testApplyMigrationAfterOwnEarlierMigrationIsAPrerequisite`.
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
        plain.applyMigration(MIGRATION_HEAD_GENESIS, prerequisite);
        vm.prank(other);
        waiting.applyMigration(MIGRATION_HEAD_GENESIS, prerequisite);

        bytes32 plainHead = plain.head(writer);
        bytes32 waitingHead = waiting.head(writer);
        vm.record();
        vm.prank(writer);
        plain.applyMigrationHistory(plainHead, migration, appliedAt);
        (, bytes32[] memory plainWrites) = vm.accesses(address(plain));
        vm.prank(writer);
        waiting.applyMigrationHistoryAfter(waitingHead, migration, appliedAt, one(other, prerequisite));
        (, bytes32[] memory afterWrites) = vm.accesses(address(waiting));

        assertEq(waiting.applied(writer, migration), plain.applied(writer, migration));
        assertEq(waiting.applied(writer, migration), appliedAt);
        assertEq(waiting.appliedOnto(writer, migration), plain.appliedOnto(writer, migration));
        assertEq(waiting.head(writer), plain.head(writer));
        assertEq(waiting.head(writer), migration);
        assertEq(afterWrites, plainWrites);
        assertTrue(afterWrites.length > 0);
    }

    /// The prerequisite's own namespace is read and not written: after the
    /// dependent write lands, the prerequisite's writer has the head and the
    /// record it had before.
    function testApplyMigrationAfterLeavesThePrerequisiteNamespaceAlone(
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
        sRegistry.applyMigrationAfter(MIGRATION_HEAD_GENESIS, migration, one(other, prerequisite));

        assertEq(sRegistry.applied(other, prerequisite), 1000);
        assertEq(sRegistry.appliedOnto(other, prerequisite), MIGRATION_HEAD_GENESIS);
        assertEq(sRegistry.head(other), prerequisite);
        assertEq(sRegistry.applied(other, migration), 0);
    }

    /// A prerequisite nobody has applied refuses the write, naming it, and
    /// nothing moves: the migration stays unapplied and the head stays where
    /// it was. Once the prerequisite is applied the same call lands. This is
    /// the whole point of the entry point — the dependent script is held back
    /// by the registry rather than by re-reading the other migration's
    /// post-state.
    function testApplyMigrationAfterUnappliedPrerequisiteRevertsThenLands(
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
        // `testApplyMigrationAfterOwnEarlierMigrationIsAPrerequisite`.
        vm.assume(writer != other);
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, prerequisite);
        vm.assume(migration != prerequisite);

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.PrerequisiteNotApplied.selector, other, prerequisite)
        );
        vm.prank(writer);
        sRegistry.applyMigrationAfter(MIGRATION_HEAD_GENESIS, migration, one(other, prerequisite));

        assertEq(sRegistry.applied(writer, migration), 0);
        assertEq(sRegistry.head(writer), MIGRATION_HEAD_GENESIS);

        applyUnder(other, prerequisite);

        vm.prank(writer);
        sRegistry.applyMigrationAfter(MIGRATION_HEAD_GENESIS, migration, one(other, prerequisite));

        assertEq(sRegistry.applied(writer, migration), block.timestamp);
        assertEq(sRegistry.appliedOnto(writer, migration), MIGRATION_HEAD_GENESIS);
        assertEq(sRegistry.head(writer), migration);
    }

    /// The same on `applyMigrationHistoryAfter`, with the caller's moment
    /// recorded once the prerequisite is there.
    function testApplyMigrationHistoryAfterUnappliedPrerequisiteRevertsThenLands(
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
        // `testApplyMigrationAfterOwnEarlierMigrationIsAPrerequisite`.
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
        sRegistry.applyMigrationHistoryAfter(MIGRATION_HEAD_GENESIS, migration, appliedAt, one(other, prerequisite));

        assertEq(sRegistry.applied(writer, migration), 0);
        assertEq(sRegistry.head(writer), MIGRATION_HEAD_GENESIS);

        applyUnder(other, prerequisite);

        vm.prank(writer);
        sRegistry.applyMigrationHistoryAfter(MIGRATION_HEAD_GENESIS, migration, appliedAt, one(other, prerequisite));

        assertEq(sRegistry.applied(writer, migration), appliedAt);
        assertEq(sRegistry.head(writer), migration);
    }

    /// A prerequisite is a particular migration, not a namespace that has
    /// applied something. A writer that has applied other migrations and not
    /// the one named is refused exactly as an empty namespace is.
    function testApplyMigrationAfterPrerequisiteIsTheMigrationNotTheNamespace(
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
        sRegistry.applyMigrationAfter(MIGRATION_HEAD_GENESIS, migration, one(other, prerequisite));
    }

    /// Over a list of any length with exactly one entry unapplied, the revert
    /// names that entry — wherever it sits, whatever namespaces the others are
    /// in, the caller's own included. Once it is applied too, the write lands.
    function testApplyMigrationAfterNamesTheOneUnapplied(
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
        sRegistry.applyMigrationAfter(head, migration, prerequisites);
        assertEq(sRegistry.applied(writer, migration), 0);

        applyUnder(unapplied.writer, unapplied.migration);

        head = sRegistry.head(writer);
        vm.prank(writer);
        sRegistry.applyMigrationAfter(head, migration, prerequisites);
        assertEq(sRegistry.applied(writer, migration), block.timestamp);
        assertEq(sRegistry.head(writer), migration);
    }

    /// The same on `applyMigrationHistoryAfter`.
    function testApplyMigrationHistoryAfterNamesTheOneUnapplied(
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
        sRegistry.applyMigrationHistoryAfter(MIGRATION_HEAD_GENESIS, migration, appliedAt, prerequisites);
        assertEq(sRegistry.applied(writer, migration), 0);

        applyUnder(unapplied.writer, unapplied.migration);

        vm.prank(writer);
        sRegistry.applyMigrationHistoryAfter(MIGRATION_HEAD_GENESIS, migration, appliedAt, prerequisites);
        assertEq(sRegistry.applied(writer, migration), appliedAt);
    }

    /// With several unapplied, the FIRST in list order is the one named, and
    /// applying it moves the refusal to the next. A caller waiting on several
    /// is told about one at a time, in the order it listed them.
    function testApplyMigrationAfterNamesTheFirstUnapplied(
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
        sRegistry.applyMigrationAfter(MIGRATION_HEAD_GENESIS, migration, prerequisites);

        applyUnder(otherA, prerequisiteA);

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.PrerequisiteNotApplied.selector, otherB, prerequisiteB)
        );
        vm.prank(writer);
        sRegistry.applyMigrationAfter(MIGRATION_HEAD_GENESIS, migration, prerequisites);

        applyUnder(otherB, prerequisiteB);

        bytes32 head = sRegistry.head(writer);
        vm.prank(writer);
        sRegistry.applyMigrationAfter(head, migration, prerequisites);
        assertEq(sRegistry.applied(writer, migration), block.timestamp);
    }

    /// An empty list is refused as `NoPrerequisites` on both `After` writes,
    /// on an empty namespace and a used one alike, while the plain write with
    /// the same arguments lands. A caller that chose the write that waits on
    /// something and named nothing has mis-set the list, and the mistake is
    /// reported rather than turned into a record.
    function testApplyMigrationAfterEmptyReverts(address writer, bytes32 migrationA, bytes32 migrationB, uint32 now_)
        external
    {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.assume(migrationA != migrationB);
        vm.assume(now_ != 0);
        vm.warp(now_);
        Prerequisite[] memory none = new Prerequisite[](0);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.NoPrerequisites.selector));
        vm.prank(writer);
        sRegistry.applyMigrationAfter(MIGRATION_HEAD_GENESIS, migrationA, none);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.NoPrerequisites.selector));
        vm.prank(writer);
        sRegistry.applyMigrationHistoryAfter(MIGRATION_HEAD_GENESIS, migrationA, now_, none);

        assertEq(sRegistry.applied(writer, migrationA), 0);
        assertEq(sRegistry.head(writer), MIGRATION_HEAD_GENESIS);

        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migrationA);
        assertEq(sRegistry.applied(writer, migrationA), now_);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.NoPrerequisites.selector));
        vm.prank(writer);
        sRegistry.applyMigrationAfter(migrationA, migrationB, none);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.NoPrerequisites.selector));
        vm.prank(writer);
        sRegistry.applyMigrationHistoryAfter(migrationA, migrationB, now_, none);

        assertEq(sRegistry.applied(writer, migrationB), 0);
        assertEq(sRegistry.head(writer), migrationA);
    }

    /// A prerequisite naming the zero writer is refused as `ZeroWriter`, the
    /// same refusal `applied` makes of the same key. The zero namespace is
    /// provably empty, so without this the entry would be refused as unapplied
    /// forever instead of as the unset constant it is.
    function testApplyMigrationAfterZeroWriterReverts(address writer, bytes32 migration, bytes32 prerequisite)
        external
    {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, prerequisite);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroWriter.selector));
        vm.prank(writer);
        sRegistry.applyMigrationAfter(MIGRATION_HEAD_GENESIS, migration, one(address(0), prerequisite));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroWriter.selector));
        vm.prank(writer);
        sRegistry.applyMigrationHistoryAfter(
            MIGRATION_HEAD_GENESIS, migration, block.timestamp, one(address(0), prerequisite)
        );

        assertEq(sRegistry.applied(writer, migration), 0);
    }

    /// A prerequisite naming the zero migration is refused as `ZeroMigration`,
    /// whatever its writer: an uninitialised id names no record.
    function testApplyMigrationAfterZeroMigrationPrerequisiteReverts(address writer, address other, bytes32 migration)
        external
    {
        vm.assume(writer != address(0));
        vm.assume(other != address(0));
        LibMigrationFuzz.assumeMigration(vm, migration);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigrationAfter(MIGRATION_HEAD_GENESIS, migration, one(other, bytes32(0)));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigrationHistoryAfter(MIGRATION_HEAD_GENESIS, migration, block.timestamp, one(other, bytes32(0)));

        assertEq(sRegistry.applied(writer, migration), 0);
    }

    /// A prerequisite naming `MIGRATION_HEAD_GENESIS` is refused as
    /// `GenesisMigration`: genesis is a head, no namespace ever applies it, and
    /// a caller that named it has confused a head for a migration.
    function testApplyMigrationAfterGenesisPrerequisiteReverts(address writer, address other, bytes32 migration)
        external
    {
        vm.assume(writer != address(0));
        vm.assume(other != address(0));
        LibMigrationFuzz.assumeMigration(vm, migration);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.GenesisMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigrationAfter(MIGRATION_HEAD_GENESIS, migration, one(other, MIGRATION_HEAD_GENESIS));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.GenesisMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigrationHistoryAfter(
            MIGRATION_HEAD_GENESIS, migration, block.timestamp, one(other, MIGRATION_HEAD_GENESIS)
        );

        assertEq(sRegistry.applied(writer, migration), 0);
    }

    /// Within one entry the key is refused in `applied`'s order: writer first,
    /// then the two reserved ids. An entry that is wrong in every field is
    /// `ZeroWriter`.
    function testApplyMigrationAfterKeyRefusalOrderWithinAnEntry(address writer, bytes32 migration) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeMigration(vm, migration);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroWriter.selector));
        vm.prank(writer);
        sRegistry.applyMigrationAfter(MIGRATION_HEAD_GENESIS, migration, one(address(0), bytes32(0)));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroWriter.selector));
        vm.prank(writer);
        sRegistry.applyMigrationAfter(MIGRATION_HEAD_GENESIS, migration, one(address(0), MIGRATION_HEAD_GENESIS));
    }

    /// Every entry is checked as a key before any entry is read, so a
    /// malformed entry LATER in the list is reported over an unapplied entry
    /// earlier in it. A malformed argument is a mistake the caller can fix
    /// now; an unapplied prerequisite is a fact about the world, and the
    /// caller is told about its own mistakes first.
    function testApplyMigrationAfterMalformedEntryReportedOverUnappliedEntry(
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
        sRegistry.applyMigrationAfter(
            MIGRATION_HEAD_GENESIS, migration, two(other, prerequisite, address(0), prerequisite)
        );

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigrationAfter(MIGRATION_HEAD_GENESIS, migration, two(other, prerequisite, other, bytes32(0)));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.GenesisMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigrationAfter(
            MIGRATION_HEAD_GENESIS, migration, two(other, prerequisite, other, MIGRATION_HEAD_GENESIS)
        );

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroWriter.selector));
        vm.prank(writer);
        sRegistry.applyMigrationHistoryAfter(
            MIGRATION_HEAD_GENESIS, migration, block.timestamp, two(other, prerequisite, address(0), prerequisite)
        );
    }

    /// Among several malformed entries, the first in list order is the one
    /// reported, whichever field is wrong in each.
    function testApplyMigrationAfterFirstMalformedEntryReported(address writer, address other, bytes32 migration)
        external
    {
        vm.assume(writer != address(0));
        vm.assume(other != address(0));
        LibMigrationFuzz.assumeMigration(vm, migration);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroWriter.selector));
        vm.prank(writer);
        sRegistry.applyMigrationAfter(MIGRATION_HEAD_GENESIS, migration, two(address(0), migration, other, bytes32(0)));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigrationAfter(MIGRATION_HEAD_GENESIS, migration, two(other, bytes32(0), address(0), migration));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.GenesisMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigrationAfter(
            MIGRATION_HEAD_GENESIS, migration, two(other, MIGRATION_HEAD_GENESIS, other, bytes32(0))
        );
    }

    /// A prerequisite naming the migration being applied is unapplied by
    /// construction — the write that would apply it is the one being refused
    /// — so it is `PrerequisiteNotApplied(writer, migration)` rather than a
    /// record, on both `After` writes.
    function testApplyMigrationAfterSelfPrerequisiteReverts(address writer, bytes32 migration) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeMigration(vm, migration);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.PrerequisiteNotApplied.selector, writer, migration));
        vm.prank(writer);
        sRegistry.applyMigrationAfter(MIGRATION_HEAD_GENESIS, migration, one(writer, migration));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.PrerequisiteNotApplied.selector, writer, migration));
        vm.prank(writer);
        sRegistry.applyMigrationHistoryAfter(MIGRATION_HEAD_GENESIS, migration, block.timestamp, one(writer, migration));

        assertEq(sRegistry.applied(writer, migration), 0);
        assertEq(sRegistry.head(writer), MIGRATION_HEAD_GENESIS);
    }

    /// The caller's own namespace is an ordinary namespace to name: an earlier
    /// migration of its own is a prerequisite like any other, applied or not.
    function testApplyMigrationAfterOwnEarlierMigrationIsAPrerequisite(
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
        sRegistry.applyMigrationAfter(MIGRATION_HEAD_GENESIS, migrationB, one(writer, migrationA));

        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migrationA);

        vm.prank(writer);
        sRegistry.applyMigrationAfter(migrationA, migrationB, one(writer, migrationA));

        assertEq(sRegistry.applied(writer, migrationB), block.timestamp);
        assertEq(sRegistry.appliedOnto(writer, migrationB), migrationA);
        assertEq(sRegistry.head(writer), migrationB);
    }

    /// A prerequisite listed twice is checked twice: harmless when applied,
    /// and named once — as the first entry — when not.
    function testApplyMigrationAfterDuplicatesAreCheckedTwice(
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
        sRegistry.applyMigrationAfter(MIGRATION_HEAD_GENESIS, migration, prerequisites);

        applyUnder(other, prerequisite);

        bytes32 head = sRegistry.head(writer);
        vm.prank(writer);
        sRegistry.applyMigrationAfter(head, migration, prerequisites);
        assertEq(sRegistry.applied(writer, migration), block.timestamp);
    }

    /// The caller's own arguments are refused before the list is looked at:
    /// a zero or genesis migration, and a zero moment, are reported over a
    /// list that would itself be refused — empty, malformed or unapplied.
    /// Everything the caller handed in about its own record is what it can
    /// fix first.
    function testApplyMigrationAfterOwnArgumentsCheckedBeforePrerequisites(
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

        // Zero migration, over every kind of bad list.
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigrationAfter(anyHead, bytes32(0), none);
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigrationAfter(anyHead, bytes32(0), malformed);
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigrationAfter(anyHead, bytes32(0), unapplied);

        // Genesis migration, over every kind of bad list.
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.GenesisMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigrationAfter(anyHead, MIGRATION_HEAD_GENESIS, none);
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.GenesisMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigrationAfter(anyHead, MIGRATION_HEAD_GENESIS, malformed);
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.GenesisMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigrationAfter(anyHead, MIGRATION_HEAD_GENESIS, unapplied);

        // Zero moment, over every kind of bad list, on both writes.
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroTimestamp.selector));
        vm.prank(writer);
        sRegistry.applyMigrationHistoryAfter(anyHead, prerequisite, 0, none);
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroTimestamp.selector));
        vm.prank(writer);
        sRegistry.applyMigrationHistoryAfter(anyHead, prerequisite, 0, malformed);
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroTimestamp.selector));
        vm.prank(writer);
        sRegistry.applyMigrationHistoryAfter(anyHead, prerequisite, 0, unapplied);

        vm.warp(0);
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroTimestamp.selector));
        vm.prank(writer);
        sRegistry.applyMigrationAfter(anyHead, prerequisite, none);
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroTimestamp.selector));
        vm.prank(writer);
        sRegistry.applyMigrationAfter(anyHead, prerequisite, malformed);
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroTimestamp.selector));
        vm.prank(writer);
        sRegistry.applyMigrationAfter(anyHead, prerequisite, unapplied);

        // And the migration before the moment, as on the plain write.
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigrationHistoryAfter(anyHead, bytes32(0), 0, none);
    }

    /// The prerequisites are read before anything about the caller's own
    /// namespace: an unapplied prerequisite is reported over a migration the
    /// caller has already applied. A record that exists while the
    /// prerequisites its script now names do not is the more alarming fact,
    /// and it is not hidden behind "already applied". With the prerequisite
    /// applied, the re-dispatch is `MigrationAlreadyApplied`, as on the plain
    /// write.
    function testApplyMigrationAfterPrerequisitesCheckedBeforeAlreadyApplied(
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
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migration);

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.PrerequisiteNotApplied.selector, other, prerequisite)
        );
        vm.prank(writer);
        sRegistry.applyMigrationAfter(MIGRATION_HEAD_GENESIS, migration, one(other, prerequisite));

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.PrerequisiteNotApplied.selector, other, prerequisite)
        );
        vm.prank(writer);
        sRegistry.applyMigrationHistoryAfter(
            MIGRATION_HEAD_GENESIS, migration, block.timestamp, one(other, prerequisite)
        );

        applyUnder(other, prerequisite);

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.MigrationAlreadyApplied.selector, writer, migration)
        );
        vm.prank(writer);
        sRegistry.applyMigrationAfter(MIGRATION_HEAD_GENESIS, migration, one(other, prerequisite));

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.MigrationAlreadyApplied.selector, writer, migration)
        );
        vm.prank(writer);
        sRegistry.applyMigrationHistoryAfter(
            MIGRATION_HEAD_GENESIS, migration, block.timestamp, one(other, prerequisite)
        );
    }

    /// An unapplied prerequisite is reported over a wrong head, and with the
    /// prerequisite applied the wrong head is reported exactly as the plain
    /// write reports it.
    function testApplyMigrationAfterPrerequisitesCheckedBeforeHead(
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
        sRegistry.applyMigrationAfter(wrongHead, migration, one(other, prerequisite));

        applyUnder(other, prerequisite);
        vm.assume(sRegistry.head(writer) == MIGRATION_HEAD_GENESIS);

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.UnexpectedMigrationHead.selector, writer, wrongHead, MIGRATION_HEAD_GENESIS
            )
        );
        vm.prank(writer);
        sRegistry.applyMigrationAfter(wrongHead, migration, one(other, prerequisite));

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.UnexpectedMigrationHead.selector, writer, wrongHead, MIGRATION_HEAD_GENESIS
            )
        );
        vm.prank(writer);
        sRegistry.applyMigrationHistoryAfter(wrongHead, migration, block.timestamp, one(other, prerequisite));
    }

    /// An unapplied prerequisite is reported over a moment before the head's
    /// and over a moment in the future; with the prerequisite applied, each
    /// is reported as the plain write reports it, in the plain write's order.
    function testApplyMigrationAfterPrerequisitesCheckedBeforeTheMoment(
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
        sRegistry.applyMigrationHistory(MIGRATION_HEAD_GENESIS, migrationA, 2000);
        vm.warp(3000);

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.PrerequisiteNotApplied.selector, other, prerequisite)
        );
        vm.prank(writer);
        sRegistry.applyMigrationHistoryAfter(migrationA, migrationB, 1999, one(other, prerequisite));

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.PrerequisiteNotApplied.selector, other, prerequisite)
        );
        vm.prank(writer);
        sRegistry.applyMigrationHistoryAfter(migrationA, migrationB, 3001, one(other, prerequisite));

        applyUnder(other, prerequisite);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.TimestampBeforeHead.selector, 1999, 2000));
        vm.prank(writer);
        sRegistry.applyMigrationHistoryAfter(migrationA, migrationB, 1999, one(other, prerequisite));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.FutureTimestamp.selector, 3001, 3000));
        vm.prank(writer);
        sRegistry.applyMigrationHistoryAfter(migrationA, migrationB, 3001, one(other, prerequisite));

        // A moment wrong both ways is reported against the head first, as on
        // the plain write: the record it reads is the one the head check just
        // confirmed, and the future is the one refusal time resolves.
        vm.warp(1000);
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.TimestampBeforeHead.selector, 1500, 2000));
        vm.prank(writer);
        sRegistry.applyMigrationHistoryAfter(migrationA, migrationB, 1500, one(other, prerequisite));
    }

    /// Once the prerequisites pass, the plain write's own order holds: a
    /// migration already applied is reported over a wrong head.
    function testApplyMigrationAfterAlreadyAppliedCheckedBeforeHead(
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
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migrationA);
        vm.prank(writer);
        sRegistry.applyMigration(migrationA, migrationB);

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.MigrationAlreadyApplied.selector, writer, migrationA)
        );
        vm.prank(writer);
        sRegistry.applyMigrationAfter(MIGRATION_HEAD_GENESIS, migrationA, one(other, prerequisite));
    }

    /// A prerequisite recorded through `applyMigrationHistory` counts: what is
    /// checked is that the record exists, not which write wrote it.
    function testApplyMigrationAfterHistoryPrerequisiteCounts(
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
        sRegistry.applyMigrationHistory(MIGRATION_HEAD_GENESIS, prerequisite, prerequisiteAt);

        vm.prank(writer);
        sRegistry.applyMigrationAfter(MIGRATION_HEAD_GENESIS, migration, one(other, prerequisite));

        assertEq(sRegistry.applied(writer, migration), now_);
    }

    /// A prerequisite bounds no moment. A record whose moment is EARLIER than
    /// its prerequisite's is accepted: the moments in another namespace are
    /// that writer's data, and what is checked is that the record existed
    /// when this write landed, which is the chain's order and not the
    /// moments'.
    function testApplyMigrationHistoryAfterMomentIsNotBoundedByThePrerequisite(
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
        sRegistry.applyMigrationHistory(MIGRATION_HEAD_GENESIS, prerequisite, prerequisiteAt);

        vm.prank(writer);
        sRegistry.applyMigrationHistoryAfter(MIGRATION_HEAD_GENESIS, migration, appliedAt, one(other, prerequisite));

        assertEq(sRegistry.applied(writer, migration), appliedAt);
        assertEq(sRegistry.applied(other, prerequisite), prerequisiteAt);
    }

    /// `applyMigrationAfter` emits `Migrated` exactly as `applyMigration`
    /// does, then `MigratedAfter` with the writer and migration indexed the
    /// same way and the prerequisites, as listed, as data. Two entries, in
    /// that order, from the registry: one filter on `Migrated` is still the
    /// complete history, and the second entry is where the prerequisites go
    /// instead of storage.
    function testApplyMigrationAfterEvents(
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
        sRegistry.applyMigrationAfter(head, migration, prerequisites);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        assertEq(entries.length, 2);
        assertEq(entries[0].emitter, address(sRegistry));
        assertEq(entries[0].topics.length, 3);
        assertEq(entries[0].topics[0], keccak256("Migrated(address,bytes32,uint256)"));
        assertEq(entries[0].topics[1], bytes32(uint256(uint160(writer))));
        assertEq(entries[0].topics[2], migration);
        assertEq(entries[0].data, abi.encode(uint256(now_)));
        assertEq(entries[1].emitter, address(sRegistry));
        assertEq(entries[1].topics.length, 3);
        assertEq(entries[1].topics[0], keccak256("MigratedAfter(address,bytes32,(address,bytes32)[])"));
        assertEq(entries[1].topics[1], bytes32(uint256(uint160(writer))));
        assertEq(entries[1].topics[2], migration);
        assertEq(entries[1].data, abi.encode(prerequisites));
    }

    /// The same two entries from `applyMigrationHistoryAfter`, with the
    /// caller's moment in `Migrated`.
    function testApplyMigrationHistoryAfterEvents(
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
        // `testApplyMigrationAfterOwnEarlierMigrationIsAPrerequisite`.
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
        sRegistry.applyMigrationHistoryAfter(head, migration, appliedAt, prerequisites);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        assertEq(entries.length, 2);
        assertEq(entries[0].topics[0], keccak256("Migrated(address,bytes32,uint256)"));
        assertEq(entries[0].topics[1], bytes32(uint256(uint160(writer))));
        assertEq(entries[0].topics[2], migration);
        assertEq(entries[0].data, abi.encode(uint256(appliedAt)));
        assertEq(entries[1].topics[0], keccak256("MigratedAfter(address,bytes32,(address,bytes32)[])"));
        assertEq(entries[1].topics[1], bytes32(uint256(uint160(writer))));
        assertEq(entries[1].topics[2], migration);
        assertEq(entries[1].data, abi.encode(prerequisites));
    }

    /// `MigratedAfter` carries the list as the caller listed it, duplicates
    /// and all: the log says what the caller asserted.
    function testApplyMigrationAfterEventCarriesDuplicates(
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
        applyUnder(other, prerequisite);
        Prerequisite[] memory prerequisites = two(other, prerequisite, other, prerequisite);

        bytes32 head = sRegistry.head(writer);
        vm.recordLogs();
        vm.prank(writer);
        sRegistry.applyMigrationAfter(head, migration, prerequisites);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        assertEq(entries.length, 2);
        assertEq(entries[1].data, abi.encode(prerequisites));
    }

    /// A refused `After` write emits nothing — neither `Migrated` nor
    /// `MigratedAfter` — for every one of its refusals, the two it adds
    /// included.
    function testApplyMigrationAfterNoEventOnRevert(
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
        sRegistry.applyMigrationAfter(MIGRATION_HEAD_GENESIS, migration, applied);
        assertEq(vm.getRecordedLogs().length, 0);

        vm.recordLogs();
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.NoPrerequisites.selector));
        vm.prank(writer);
        sRegistry.applyMigrationAfter(MIGRATION_HEAD_GENESIS, migration, new Prerequisite[](0));
        assertEq(vm.getRecordedLogs().length, 0);

        vm.recordLogs();
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroWriter.selector));
        vm.prank(writer);
        sRegistry.applyMigrationAfter(MIGRATION_HEAD_GENESIS, migration, one(address(0), prerequisite));
        assertEq(vm.getRecordedLogs().length, 0);

        applyUnder(other, prerequisite);
        vm.prank(writer);
        sRegistry.applyMigrationAfter(MIGRATION_HEAD_GENESIS, migration, applied);

        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.MigrationAlreadyApplied.selector, writer, migration)
        );
        vm.prank(writer);
        sRegistry.applyMigrationAfter(MIGRATION_HEAD_GENESIS, migration, applied);
        assertEq(vm.getRecordedLogs().length, 0);

        vm.recordLogs();
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigrationAfter(migration, bytes32(0), applied);
        assertEq(vm.getRecordedLogs().length, 0);

        vm.recordLogs();
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.GenesisMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigrationAfter(migration, MIGRATION_HEAD_GENESIS, applied);
        assertEq(vm.getRecordedLogs().length, 0);

        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.UnexpectedMigrationHead.selector, writer, MIGRATION_HEAD_GENESIS, migration
            )
        );
        vm.prank(writer);
        sRegistry.applyMigrationAfter(MIGRATION_HEAD_GENESIS, next, applied);
        assertEq(vm.getRecordedLogs().length, 0);

        vm.recordLogs();
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroTimestamp.selector));
        vm.prank(writer);
        sRegistry.applyMigrationHistoryAfter(migration, next, 0, applied);
        assertEq(vm.getRecordedLogs().length, 0);

        vm.recordLogs();
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.FutureTimestamp.selector, 1001, 1000));
        vm.prank(writer);
        sRegistry.applyMigrationHistoryAfter(migration, next, 1001, applied);
        assertEq(vm.getRecordedLogs().length, 0);

        vm.recordLogs();
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.TimestampBeforeHead.selector, 999, 1000));
        vm.prank(writer);
        sRegistry.applyMigrationHistoryAfter(migration, next, 999, applied);
        assertEq(vm.getRecordedLogs().length, 0);
    }

    /// The plain writes still emit exactly one entry, so `MigratedAfter` is
    /// the `After` writes' alone and a plain record never claims to have
    /// waited on anything.
    function testApplyMigrationPlainWritesEmitNoMigratedAfter(address writer, bytes32 migrationA, bytes32 migrationB)
        external
    {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.assume(migrationA != migrationB);

        vm.recordLogs();
        vm.prank(writer);
        sRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migrationA);
        vm.prank(writer);
        sRegistry.applyMigrationHistory(migrationA, migrationB, block.timestamp);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        assertEq(entries.length, 2);
        assertEq(entries[0].topics[0], keccak256("Migrated(address,bytes32,uint256)"));
        assertEq(entries[1].topics[0], keccak256("Migrated(address,bytes32,uint256)"));
    }
}
