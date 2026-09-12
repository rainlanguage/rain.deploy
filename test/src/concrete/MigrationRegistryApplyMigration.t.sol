// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, Vm} from "forge-std-1.16.2/src/Test.sol";

import {IMigrationRegistryV2, Prerequisite} from "../../../src/interface/IMigrationRegistryV2.sol";
import {MigrationRegistry} from "../../../src/concrete/MigrationRegistry.sol";
import {LibMigrationFuzz} from "../../lib/LibMigrationFuzz.sol";

/// @title MigrationRegistryApplyMigrationTest
/// @notice `MigrationRegistry.applyMigration`: the record it writes, what it
/// refuses and in which order, what the prerequisites check and that nothing
/// about them is stored, and what reaches the log.
contract MigrationRegistryApplyMigrationTest is Test {
    MigrationRegistry internal sRegistry;

    function setUp() external {
        sRegistry = new MigrationRegistry();
    }

    /// Applies `migration` under `writer` as a root, so a test can make a
    /// prerequisite true.
    function applyUnder(address writer, bytes32 migration) internal {
        vm.prank(writer);
        sRegistry.applyMigration(migration, new Prerequisite[](0));
    }

    function testApplyMigrationAnyCallerAppliesUnderItself(address writer, bytes32 migration, uint32 now_) external {
        LibMigrationFuzz.assumeKey(vm, writer, migration);
        vm.assume(now_ != 0);
        vm.warp(now_);

        vm.prank(writer);
        sRegistry.applyMigration(migration, new Prerequisite[](0));

        assertEq(sRegistry.applied(writer, migration), now_);
    }

    /// A record is of the moment it happened, not of the last time anything
    /// happened.
    function testApplyMigrationTimestampsAreIndependent(address writer, bytes32 migrationA, bytes32 migrationB)
        external
    {
        LibMigrationFuzz.assumeKey(vm, writer, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.assume(migrationA != migrationB);

        vm.warp(1000);
        applyUnder(writer, migrationA);
        vm.warp(2000);
        applyUnder(writer, migrationB);

        assertEq(sRegistry.applied(writer, migrationA), 1000);
        assertEq(sRegistry.applied(writer, migrationB), 2000);
    }

    /// A zero block would write the one moment that reads back as no record.
    function testApplyMigrationZeroBlockReverts(address writer, bytes32 migration) external {
        LibMigrationFuzz.assumeKey(vm, writer, migration);
        vm.warp(0);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroTimestamp.selector));
        vm.prank(writer);
        sRegistry.applyMigration(migration, new Prerequisite[](0));

        assertEq(sRegistry.applied(writer, migration), 0);

        vm.warp(1);
        applyUnder(writer, migration);
        assertEq(sRegistry.applied(writer, migration), 1);
    }

    function testApplyMigrationDoesNotReachAnotherNamespace(address writer, address other, bytes32 migration) external {
        LibMigrationFuzz.assumeKey(vm, writer, migration);
        vm.assume(other != address(0));
        vm.assume(other != writer);

        applyUnder(writer, migration);

        assertEq(sRegistry.applied(writer, migration), block.timestamp);
        assertEq(sRegistry.applied(other, migration), 0);

        // The other namespace is still free to apply the same id.
        vm.warp(block.timestamp + 1);
        applyUnder(other, migration);
        assertEq(sRegistry.applied(other, migration), block.timestamp);
        assertEq(sRegistry.applied(writer, migration), block.timestamp - 1);
    }

    function testApplyMigrationTwiceReverts(address writer, bytes32 migration) external {
        LibMigrationFuzz.assumeKey(vm, writer, migration);
        vm.warp(1000);
        applyUnder(writer, migration);

        vm.warp(2000);
        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.MigrationAlreadyApplied.selector, writer, migration)
        );
        vm.prank(writer);
        sRegistry.applyMigration(migration, new Prerequisite[](0));

        assertEq(sRegistry.applied(writer, migration), 1000);
    }

    function testApplyMigrationZeroMigrationReverts(address writer, Prerequisite[] memory prerequisites) external {
        vm.assume(writer != address(0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(bytes32(0), prerequisites);
    }

    /// A zero id in a zero block with a malformed, unapplied prerequisite trips
    /// every refusal at once; the id is the one reported.
    function testApplyMigrationZeroMigrationCheckedFirst(address writer, bytes32 other) external {
        vm.assume(writer != address(0));
        vm.warp(0);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(bytes32(0), LibMigrationFuzz.one(address(0), other));
    }

    /// A zero block with a malformed, unapplied prerequisite and an already
    /// applied migration: the moment is reported.
    function testApplyMigrationZeroBlockCheckedBeforePrerequisitesAndNamespace(
        address writer,
        bytes32 migration,
        bytes32 other
    ) external {
        LibMigrationFuzz.assumeKey(vm, writer, migration);
        vm.warp(1000);
        applyUnder(writer, migration);
        vm.warp(0);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroTimestamp.selector));
        vm.prank(writer);
        sRegistry.applyMigration(migration, LibMigrationFuzz.one(address(0), other));
    }

    /// Any nonzero 32 bytes is an id; nothing constrains its derivation.
    function testApplyMigrationOpaqueMigrationIds(address writer) external {
        vm.assume(writer != address(0));
        bytes32 hashed = keccak256("script/20260623-upgrade-receipt-vaults.s.sol");
        bytes32 counter = bytes32(uint256(1));
        bytes32 max = bytes32(type(uint256).max);

        applyUnder(writer, hashed);
        applyUnder(writer, counter);
        applyUnder(writer, max);

        assertEq(sRegistry.applied(writer, hashed), block.timestamp);
        assertEq(sRegistry.applied(writer, counter), block.timestamp);
        assertEq(sRegistry.applied(writer, max), block.timestamp);
    }

    /// An empty list is a root, on an empty namespace and a used one.
    function testApplyMigrationEmptyPrerequisitesIsARoot(address writer, bytes32 migrationA, bytes32 migrationB)
        external
    {
        LibMigrationFuzz.assumeKey(vm, writer, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.assume(migrationA != migrationB);

        applyUnder(writer, migrationA);
        applyUnder(writer, migrationB);

        assertEq(sRegistry.applied(writer, migrationA), block.timestamp);
        assertEq(sRegistry.applied(writer, migrationB), block.timestamp);
    }

    /// Refused naming the prerequisite while it is unapplied, and lands once
    /// it is. Nothing is recorded by the refusal.
    function testApplyMigrationUnappliedPrerequisiteRevertsThenLands(
        address writer,
        address other,
        bytes32 migration,
        bytes32 prerequisite
    ) external {
        LibMigrationFuzz.assumeKey(vm, writer, migration);
        LibMigrationFuzz.assumeKey(vm, other, prerequisite);
        vm.assume(writer != other || migration != prerequisite);
        Prerequisite[] memory prerequisites = LibMigrationFuzz.one(other, prerequisite);

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.PrerequisiteNotApplied.selector, other, prerequisite)
        );
        vm.prank(writer);
        sRegistry.applyMigration(migration, prerequisites);
        assertEq(sRegistry.applied(writer, migration), 0);

        applyUnder(other, prerequisite);
        vm.prank(writer);
        sRegistry.applyMigration(migration, prerequisites);
        assertEq(sRegistry.applied(writer, migration), block.timestamp);
    }

    /// The prerequisite is a migration under a writer, not the writer having
    /// applied anything at all.
    function testApplyMigrationPrerequisiteIsTheMigrationNotTheNamespace(
        address writer,
        address other,
        bytes32 migration,
        bytes32 applied,
        bytes32 prerequisite
    ) external {
        LibMigrationFuzz.assumeKey(vm, writer, migration);
        LibMigrationFuzz.assumeKey(vm, other, applied);
        LibMigrationFuzz.assumeMigration(vm, prerequisite);
        vm.assume(applied != prerequisite);
        applyUnder(other, applied);

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.PrerequisiteNotApplied.selector, other, prerequisite)
        );
        vm.prank(writer);
        sRegistry.applyMigration(migration, LibMigrationFuzz.one(other, prerequisite));
    }

    /// The writer's own predecessor is a prerequisite like any other: the
    /// ordering within a namespace.
    function testApplyMigrationOwnPredecessorIsAPrerequisite(address writer, bytes32 migrationA, bytes32 migrationB)
        external
    {
        LibMigrationFuzz.assumeKey(vm, writer, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.assume(migrationA != migrationB);
        Prerequisite[] memory predecessor = LibMigrationFuzz.one(writer, migrationA);

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.PrerequisiteNotApplied.selector, writer, migrationA)
        );
        vm.prank(writer);
        sRegistry.applyMigration(migrationB, predecessor);

        applyUnder(writer, migrationA);
        vm.prank(writer);
        sRegistry.applyMigration(migrationB, predecessor);
        assertEq(sRegistry.applied(writer, migrationB), block.timestamp);
    }

    /// A migration naming itself is unapplied by construction.
    function testApplyMigrationSelfPrerequisiteReverts(address writer, bytes32 migration) external {
        LibMigrationFuzz.assumeKey(vm, writer, migration);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.PrerequisiteNotApplied.selector, writer, migration));
        vm.prank(writer);
        sRegistry.applyMigration(migration, LibMigrationFuzz.one(writer, migration));
    }

    /// Over a list of any length with every entry applied but one, the one is
    /// named, wherever it sits.
    function testApplyMigrationNamesTheOneUnapplied(
        address writer,
        bytes32 migration,
        bytes32[] memory seeds,
        uint256 index
    ) external {
        LibMigrationFuzz.assumeKey(vm, writer, migration);
        vm.assume(seeds.length > 0);
        vm.assume(seeds.length <= 16);
        index = bound(index, 0, seeds.length - 1);
        Prerequisite[] memory prerequisites = LibMigrationFuzz.keysFromSeeds(vm, seeds);
        for (uint256 i = 0; i < prerequisites.length; i++) {
            vm.assume(prerequisites[i].migration != migration);
            if (i != index && sRegistry.applied(prerequisites[i].writer, prerequisites[i].migration) == 0) {
                applyUnder(prerequisites[i].writer, prerequisites[i].migration);
            }
        }
        // A seed repeated elsewhere in the list would have applied the entry.
        vm.assume(sRegistry.applied(prerequisites[index].writer, prerequisites[index].migration) == 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.PrerequisiteNotApplied.selector,
                prerequisites[index].writer,
                prerequisites[index].migration
            )
        );
        vm.prank(writer);
        sRegistry.applyMigration(migration, prerequisites);
        assertEq(sRegistry.applied(writer, migration), 0);

        applyUnder(prerequisites[index].writer, prerequisites[index].migration);
        vm.prank(writer);
        sRegistry.applyMigration(migration, prerequisites);
        assertEq(sRegistry.applied(writer, migration), block.timestamp);
    }

    /// With two unapplied, the first in list order is named.
    function testApplyMigrationNamesTheFirstUnapplied(
        address writer,
        address otherA,
        address otherB,
        bytes32 migration,
        bytes32 prerequisiteA,
        bytes32 prerequisiteB
    ) external {
        LibMigrationFuzz.assumeKey(vm, writer, migration);
        LibMigrationFuzz.assumeKey(vm, otherA, prerequisiteA);
        LibMigrationFuzz.assumeKey(vm, otherB, prerequisiteB);
        vm.assume(otherA != otherB || prerequisiteA != prerequisiteB);

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.PrerequisiteNotApplied.selector, otherA, prerequisiteA)
        );
        vm.prank(writer);
        sRegistry.applyMigration(migration, LibMigrationFuzz.two(otherA, prerequisiteA, otherB, prerequisiteB));

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.PrerequisiteNotApplied.selector, otherB, prerequisiteB)
        );
        vm.prank(writer);
        sRegistry.applyMigration(migration, LibMigrationFuzz.two(otherB, prerequisiteB, otherA, prerequisiteA));
    }

    function testApplyMigrationZeroWriterPrerequisiteReverts(address writer, bytes32 migration, bytes32 prerequisite)
        external
    {
        LibMigrationFuzz.assumeKey(vm, writer, migration);
        LibMigrationFuzz.assumeMigration(vm, prerequisite);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroWriter.selector));
        vm.prank(writer);
        sRegistry.applyMigration(migration, LibMigrationFuzz.one(address(0), prerequisite));
    }

    function testApplyMigrationZeroMigrationPrerequisiteReverts(address writer, address other, bytes32 migration)
        external
    {
        LibMigrationFuzz.assumeKey(vm, writer, migration);
        vm.assume(other != address(0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(migration, LibMigrationFuzz.one(other, bytes32(0)));
    }

    /// An entry with both halves zero trips both key refusals; the writer's is
    /// reported, as `applied` reports it.
    function testApplyMigrationPrerequisiteKeyRefusalOrder(address writer, bytes32 migration) external {
        LibMigrationFuzz.assumeKey(vm, writer, migration);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroWriter.selector));
        vm.prank(writer);
        sRegistry.applyMigration(migration, LibMigrationFuzz.one(address(0), bytes32(0)));
    }

    /// Entries are checked in list order, each as a key then as a record: an
    /// unapplied first entry is reported over a malformed second, and a
    /// malformed first over an unapplied second.
    function testApplyMigrationPrerequisitesCheckedInListOrder(
        address writer,
        address other,
        bytes32 migration,
        bytes32 prerequisite
    ) external {
        LibMigrationFuzz.assumeKey(vm, writer, migration);
        LibMigrationFuzz.assumeKey(vm, other, prerequisite);
        vm.assume(migration != prerequisite);

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.PrerequisiteNotApplied.selector, other, prerequisite)
        );
        vm.prank(writer);
        sRegistry.applyMigration(migration, LibMigrationFuzz.two(other, prerequisite, address(0), prerequisite));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroWriter.selector));
        vm.prank(writer);
        sRegistry.applyMigration(migration, LibMigrationFuzz.two(address(0), prerequisite, other, prerequisite));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(migration, LibMigrationFuzz.two(other, bytes32(0), other, prerequisite));
    }

    function testApplyMigrationDuplicatePrerequisitesAreFine(
        address writer,
        address other,
        bytes32 migration,
        bytes32 prerequisite
    ) external {
        LibMigrationFuzz.assumeKey(vm, writer, migration);
        LibMigrationFuzz.assumeKey(vm, other, prerequisite);
        vm.assume(migration != prerequisite);
        Prerequisite[] memory twice = LibMigrationFuzz.two(other, prerequisite, other, prerequisite);

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.PrerequisiteNotApplied.selector, other, prerequisite)
        );
        vm.prank(writer);
        sRegistry.applyMigration(migration, twice);

        applyUnder(other, prerequisite);
        vm.prank(writer);
        sRegistry.applyMigration(migration, twice);
        assertEq(sRegistry.applied(writer, migration), block.timestamp);
    }

    /// Already applied AND an unapplied prerequisite: the prerequisite is
    /// reported.
    function testApplyMigrationPrerequisitesCheckedBeforeAlreadyApplied(
        address writer,
        address other,
        bytes32 migration,
        bytes32 prerequisite
    ) external {
        LibMigrationFuzz.assumeKey(vm, writer, migration);
        LibMigrationFuzz.assumeKey(vm, other, prerequisite);
        vm.assume(writer != other || migration != prerequisite);
        applyUnder(writer, migration);

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.PrerequisiteNotApplied.selector, other, prerequisite)
        );
        vm.prank(writer);
        sRegistry.applyMigration(migration, LibMigrationFuzz.one(other, prerequisite));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroWriter.selector));
        vm.prank(writer);
        sRegistry.applyMigration(migration, LibMigrationFuzz.one(address(0), prerequisite));
    }

    /// Already applied with every prerequisite applied is `MigrationAlreadyApplied`:
    /// a re-dispatched script passes its list as it did the first time.
    function testApplyMigrationAlreadyAppliedWithPrerequisitesApplied(
        address writer,
        address other,
        bytes32 migration,
        bytes32 prerequisite
    ) external {
        LibMigrationFuzz.assumeKey(vm, writer, migration);
        LibMigrationFuzz.assumeKey(vm, other, prerequisite);
        vm.assume(writer != other || migration != prerequisite);
        applyUnder(other, prerequisite);
        Prerequisite[] memory prerequisites = LibMigrationFuzz.one(other, prerequisite);
        vm.prank(writer);
        sRegistry.applyMigration(migration, prerequisites);

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.MigrationAlreadyApplied.selector, writer, migration)
        );
        vm.prank(writer);
        sRegistry.applyMigration(migration, prerequisites);
    }

    /// A prerequisite recorded through `applyMigrationHistory` counts.
    function testApplyMigrationHistoryRecordedPrerequisiteCounts(
        address writer,
        address other,
        bytes32 migration,
        bytes32 prerequisite,
        uint32 prerequisiteAt,
        uint32 now_
    ) external {
        LibMigrationFuzz.assumeKey(vm, writer, migration);
        LibMigrationFuzz.assumeKey(vm, other, prerequisite);
        vm.assume(writer != other || migration != prerequisite);
        vm.assume(prerequisiteAt != 0);
        vm.assume(now_ >= prerequisiteAt);
        vm.warp(now_);
        vm.prank(other);
        sRegistry.applyMigrationHistory(prerequisite, prerequisiteAt, new Prerequisite[](0));

        vm.prank(writer);
        sRegistry.applyMigration(migration, LibMigrationFuzz.one(other, prerequisite));

        assertEq(sRegistry.applied(writer, migration), now_);
        assertEq(sRegistry.applied(other, prerequisite), prerequisiteAt);
    }

    /// Nothing about the prerequisites is stored: a write naming one touches
    /// the same storage slots as a root write of the same migration.
    function testApplyMigrationStoresNothingAboutPrerequisites(
        address writer,
        address other,
        bytes32 migration,
        bytes32 prerequisite
    ) external {
        LibMigrationFuzz.assumeKey(vm, writer, migration);
        LibMigrationFuzz.assumeKey(vm, other, prerequisite);
        vm.assume(migration != prerequisite);

        MigrationRegistry root = new MigrationRegistry();
        MigrationRegistry naming = new MigrationRegistry();
        vm.prank(other);
        root.applyMigration(prerequisite, new Prerequisite[](0));
        vm.prank(other);
        naming.applyMigration(prerequisite, new Prerequisite[](0));

        vm.record();
        vm.prank(writer);
        root.applyMigration(migration, new Prerequisite[](0));
        (, bytes32[] memory rootWrites) = vm.accesses(address(root));
        vm.prank(writer);
        naming.applyMigration(migration, LibMigrationFuzz.one(other, prerequisite));
        (, bytes32[] memory afterWrites) = vm.accesses(address(naming));

        assertEq(afterWrites, rootWrites);
        assertEq(afterWrites.length, 1);
        assertEq(naming.applied(writer, migration), root.applied(writer, migration));
    }

    /// `Migrated`: writer and migration indexed, the moment and the list as
    /// listed as data, topic and data recomputed here.
    function testApplyMigrationEvent(
        address writer,
        address other,
        bytes32 migration,
        bytes32 prerequisite,
        uint32 now_
    ) external {
        LibMigrationFuzz.assumeKey(vm, writer, migration);
        LibMigrationFuzz.assumeKey(vm, other, prerequisite);
        vm.assume(migration != prerequisite);
        vm.assume(now_ != 0);
        vm.warp(now_);
        applyUnder(other, prerequisite);
        Prerequisite[] memory prerequisites = LibMigrationFuzz.two(other, prerequisite, other, prerequisite);

        vm.recordLogs();
        vm.prank(writer);
        sRegistry.applyMigration(migration, prerequisites);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        assertEq(entries.length, 1);
        assertEq(entries[0].emitter, address(sRegistry));
        assertEq(entries[0].topics.length, 3);
        assertEq(entries[0].topics[0], keccak256("Migrated(address,bytes32,uint256,(address,bytes32)[])"));
        assertEq(entries[0].topics[1], bytes32(uint256(uint160(writer))));
        assertEq(entries[0].topics[2], migration);
        assertEq(entries[0].data, abi.encode(uint256(now_), prerequisites));
    }

    function testApplyMigrationRootEvent(address writer, bytes32 migration, uint32 now_) external {
        LibMigrationFuzz.assumeKey(vm, writer, migration);
        vm.assume(now_ != 0);
        vm.warp(now_);

        vm.recordLogs();
        vm.prank(writer);
        sRegistry.applyMigration(migration, new Prerequisite[](0));
        Vm.Log[] memory entries = vm.getRecordedLogs();

        assertEq(entries.length, 1);
        assertEq(entries[0].topics[0], keccak256("Migrated(address,bytes32,uint256,(address,bytes32)[])"));
        assertEq(entries[0].data, abi.encode(uint256(now_), new Prerequisite[](0)));
    }

    /// Every refusal emits nothing.
    function testApplyMigrationNoEventOnRevert(address writer, address other, bytes32 migration, bytes32 prerequisite)
        external
    {
        LibMigrationFuzz.assumeKey(vm, writer, migration);
        LibMigrationFuzz.assumeKey(vm, other, prerequisite);
        vm.assume(migration != prerequisite);
        vm.warp(1000);
        Prerequisite[] memory prerequisites = LibMigrationFuzz.one(other, prerequisite);

        vm.recordLogs();
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(bytes32(0), prerequisites);
        assertEq(vm.getRecordedLogs().length, 0);

        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.PrerequisiteNotApplied.selector, other, prerequisite)
        );
        vm.prank(writer);
        sRegistry.applyMigration(migration, prerequisites);
        assertEq(vm.getRecordedLogs().length, 0);

        vm.recordLogs();
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroWriter.selector));
        vm.prank(writer);
        sRegistry.applyMigration(migration, LibMigrationFuzz.one(address(0), prerequisite));
        assertEq(vm.getRecordedLogs().length, 0);

        vm.recordLogs();
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroMigration.selector));
        vm.prank(writer);
        sRegistry.applyMigration(migration, LibMigrationFuzz.one(other, bytes32(0)));
        assertEq(vm.getRecordedLogs().length, 0);

        applyUnder(other, prerequisite);
        vm.prank(writer);
        sRegistry.applyMigration(migration, prerequisites);

        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.MigrationAlreadyApplied.selector, writer, migration)
        );
        vm.prank(writer);
        sRegistry.applyMigration(migration, prerequisites);
        assertEq(vm.getRecordedLogs().length, 0);

        vm.warp(0);
        vm.recordLogs();
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroTimestamp.selector));
        vm.prank(writer);
        sRegistry.applyMigration(keccak256(abi.encode(migration)), prerequisites);
        assertEq(vm.getRecordedLogs().length, 0);
    }
}
