// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {IRegistryDelegatesV3} from "../../../src/interface/IRegistryDelegatesV3.sol";
import {Test, Vm} from "forge-std-1.17.0/src/Test.sol";

import {IMigrationRegistryV5, Prerequisite} from "../../../src/interface/IMigrationRegistryV5.sol";
import {MigrationRegistry} from "../../../src/concrete/MigrationRegistry.sol";
import {LibMigrationFuzz} from "../../lib/LibMigrationFuzz.sol";
import {rainMeta, isNotRainMeta} from "../../lib/RainMeta.sol";
import {NotRainMetaV1} from "rain-metadata-0.1.43/src/interface/unstable/IMetaV1_2.sol";

/// @title MigrationRegistryMetaTest
/// @notice The migration writes' `meta`: emitted as `MetaV1_2` by the writer
/// about `keccak256(abi.encode(writer, namespace, migration))` when non-empty,
/// never emitted when empty, never stored.
contract MigrationRegistryMetaTest is Test {
    MigrationRegistry internal sRegistry;

    function setUp() external {
        sRegistry = new MigrationRegistry();
    }

    function assumeKey(address writer, bytes32 namespace, bytes32 migration) internal pure {
        vm.assume(writer != address(0) && namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
    }

    function onto(MigrationRegistry registry, address writer, bytes32 namespace)
        internal
        view
        returns (Prerequisite[] memory)
    {
        Prerequisite[] memory list = new Prerequisite[](1);
        list[0] = Prerequisite({writer: writer, namespace: namespace, migration: registry.headV5(writer, namespace)});
        return list;
    }

    function write(
        MigrationRegistry registry,
        address sender,
        address writer,
        bytes32 namespace,
        bytes32 migration,
        bool history,
        bytes memory meta
    ) internal {
        Prerequisite[] memory list = onto(registry, writer, namespace);
        vm.prank(sender);
        if (history) {
            registry.applyMigrationHistoryV5(writer, namespace, migration, block.timestamp, list, meta);
        } else {
            registry.applyMigrationV5(writer, namespace, migration, list, meta);
        }
    }

    function assertMetaLog(Vm.Log memory entry, address sender, bytes32 subject, bytes memory meta) internal view {
        assertEq(entry.emitter, address(sRegistry));
        assertEq(entry.topics.length, 1);
        assertEq(entry.topics[0], keccak256("MetaV1_2(address,bytes32,bytes)"));
        assertEq(entry.data, abi.encode(sender, subject, meta));
    }

    /// Non-empty meta is one `MetaV1_2` after `Migrated`, from the writer,
    /// about the record, on both writes.
    function testApplyMigrationMetaEmitted(
        address writer,
        bytes32 namespace,
        bytes32 migration,
        bool history,
        bytes memory meta
    ) external {
        assumeKey(writer, namespace, migration);
        meta = rainMeta(meta);
        vm.recordLogs();
        write(sRegistry, writer, writer, namespace, migration, history, meta);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 2);
        assertEq(entries[0].topics[0], IMigrationRegistryV5.Migrated.selector);
        assertMetaLog(entries[1], writer, keccak256(abi.encode(writer, namespace, migration)), meta);
    }

    /// A delegate's write names the delegate as the sender and the writer's
    /// record as the subject.
    function testApplyMigrationMetaSenderIsTheDelegate(
        address writer,
        address delegate,
        bytes32 namespace,
        bytes32 migration,
        bool history,
        bytes memory meta
    ) external {
        assumeKey(writer, namespace, migration);
        vm.assume(delegate != address(0) && delegate != writer);
        meta = rainMeta(meta);
        vm.prank(writer);
        sRegistry.approveV5(namespace, delegate);
        vm.recordLogs();
        write(sRegistry, delegate, writer, namespace, migration, history, meta);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 2);
        assertMetaLog(entries[1], delegate, keccak256(abi.encode(writer, namespace, migration)), meta);
    }

    /// Empty meta emits `Migrated` alone.
    function testApplyMigrationEmptyMetaEmitsNoMeta(address writer, bytes32 namespace, bytes32 migration, bool history)
        external
    {
        assumeKey(writer, namespace, migration);
        vm.recordLogs();
        write(sRegistry, writer, writer, namespace, migration, history, "");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 1);
        assertEq(entries[0].topics[0], IMigrationRegistryV5.Migrated.selector);
    }

    /// Each record in a line has its own subject.
    function testApplyMigrationMetaSubjectPerRecord(
        address writer,
        bytes32 namespace,
        bytes32 first,
        bytes32 second,
        bytes memory meta
    ) external {
        assumeKey(writer, namespace, first);
        LibMigrationFuzz.assumeMigration(vm, second);
        vm.assume(first != second);
        meta = rainMeta(meta);
        vm.recordLogs();
        write(sRegistry, writer, writer, namespace, first, false, meta);
        write(sRegistry, writer, writer, namespace, second, true, meta);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 4);
        assertMetaLog(entries[1], writer, keccak256(abi.encode(writer, namespace, first)), meta);
        assertMetaLog(entries[3], writer, keccak256(abi.encode(writer, namespace, second)), meta);
    }

    /// A refused write emits no meta.
    function testApplyMigrationRefusedEmitsNoMeta(
        address writer,
        address sender,
        bytes32 namespace,
        bytes32 migration,
        bool history,
        bytes memory meta
    ) external {
        assumeKey(writer, namespace, migration);
        vm.assume(sender != writer);
        meta = rainMeta(meta);
        Prerequisite[] memory list = onto(sRegistry, writer, namespace);
        vm.recordLogs();
        vm.prank(sender);
        vm.expectRevert(abi.encodeWithSelector(IRegistryDelegatesV3.NotApproved.selector, writer, namespace, sender));
        if (history) {
            sRegistry.applyMigrationHistoryV5(writer, namespace, migration, block.timestamp, list, meta);
        } else {
            sRegistry.applyMigrationV5(writer, namespace, migration, list, meta);
        }
        assertEq(vm.getRecordedLogs().length, 0);
    }

    /// Non-empty meta without the magic number reverts `NotRainMetaV1` on both
    /// writes and records nothing.
    function testApplyMigrationNotRainMetaReverts(
        address writer,
        bytes32 namespace,
        bytes32 migration,
        bool history,
        bytes memory meta
    ) external {
        assumeKey(writer, namespace, migration);
        vm.assume(isNotRainMeta(meta));
        bytes32 head = sRegistry.headV5(writer, namespace);
        Prerequisite[] memory list = onto(sRegistry, writer, namespace);
        vm.prank(writer);
        vm.expectRevert(abi.encodeWithSelector(NotRainMetaV1.selector, meta));
        if (history) {
            sRegistry.applyMigrationHistoryV5(writer, namespace, migration, block.timestamp, list, meta);
        } else {
            sRegistry.applyMigrationV5(writer, namespace, migration, list, meta);
        }
        assertEq(sRegistry.appliedV5(writer, namespace, migration), 0);
        assertEq(sRegistry.appliedByV5(writer, namespace, migration), address(0));
        assertEq(sRegistry.headV5(writer, namespace), head);
    }

    /// The magic number alone is rain meta, and anything short of it is not.
    function testApplyMigrationMetaBoundary(address writer, bytes32 namespace, bytes32 migration, bool history)
        external
    {
        assumeKey(writer, namespace, migration);
        bytes[3] memory refused = [bytes(hex"01"), bytes(hex"ff0a89c674ee78"), bytes(hex"ff0a89c674ee787500")];
        for (uint256 i = 0; i < refused.length; i++) {
            Prerequisite[] memory list = onto(sRegistry, writer, namespace);
            vm.prank(writer);
            vm.expectRevert(abi.encodeWithSelector(NotRainMetaV1.selector, refused[i]));
            if (history) {
                sRegistry.applyMigrationHistoryV5(writer, namespace, migration, block.timestamp, list, refused[i]);
            } else {
                sRegistry.applyMigrationV5(writer, namespace, migration, list, refused[i]);
            }
        }
        vm.recordLogs();
        write(sRegistry, writer, writer, namespace, migration, history, hex"ff0a89c674ee7874");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 2);
        assertMetaLog(entries[1], writer, keccak256(abi.encode(writer, namespace, migration)), hex"ff0a89c674ee7874");
    }

    /// Meta is not stored: the write touches the same slots with the same
    /// values whatever the meta.
    function testApplyMigrationMetaNotStored(
        address writer,
        bytes32 namespace,
        bytes32 migration,
        bool history,
        bytes memory meta
    ) external {
        assumeKey(writer, namespace, migration);
        meta = rainMeta(meta);
        MigrationRegistry plain = new MigrationRegistry();
        MigrationRegistry withMeta = new MigrationRegistry();

        vm.record();
        write(plain, writer, writer, namespace, migration, history, "");
        (, bytes32[] memory plainWrites) = vm.accesses(address(plain));

        vm.record();
        write(withMeta, writer, writer, namespace, migration, history, meta);
        (, bytes32[] memory metaWrites) = vm.accesses(address(withMeta));

        assertGt(plainWrites.length, 0);
        assertEq(metaWrites.length, plainWrites.length);
        for (uint256 i = 0; i < metaWrites.length; i++) {
            assertEq(metaWrites[i], plainWrites[i]);
            assertEq(vm.load(address(withMeta), metaWrites[i]), vm.load(address(plain), plainWrites[i]));
        }
    }
}
