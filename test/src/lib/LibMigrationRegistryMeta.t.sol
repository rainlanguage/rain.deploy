// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, Vm} from "forge-std-1.17.0/src/Test.sol";
import {LibMigrationRegistry} from "../../../src/lib/LibMigrationRegistry.sol";
import {LibMigrationRegistryDeploy} from "../../../src/lib/LibMigrationRegistryDeploy.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {IMigrationRegistryV5, Prerequisite} from "../../../src/interface/IMigrationRegistryV5.sol";
import {MigrationRegistry} from "../../../src/concrete/MigrationRegistry.sol";
import {MockMigrationApplier} from "../../concrete/MockMigrationApplier.sol";
import {LibMigrationFuzz} from "../../lib/LibMigrationFuzz.sol";
import {rainMeta} from "../../lib/RainMeta.sol";

/// @title LibMigrationRegistryMetaTest
/// @notice `LibMigrationRegistry`'s writes and write calls send their `meta`
/// to the registry, which emits it as `MetaV1_2` from the sender about the
/// record when non-empty.
contract LibMigrationRegistryMetaTest is Test {
    bytes32 internal constant META_TOPIC = keccak256("MetaV1_2(address,bytes32,bytes)");

    function deployRegistry() internal returns (IMigrationRegistryV5) {
        return IMigrationRegistryV5(LibRainDeploy.etchAndDeployZoltu(vm, type(MigrationRegistry).creationCode));
    }

    function onto(IMigrationRegistryV5 registry, address writer, bytes32 namespace)
        internal
        view
        returns (Prerequisite[] memory)
    {
        Prerequisite[] memory list = new Prerequisite[](1);
        list[0] = Prerequisite({writer: writer, namespace: namespace, migration: registry.headV5(writer, namespace)});
        return list;
    }

    function assertMeta(
        Vm.Log[] memory entries,
        address sender,
        address writer,
        bytes32 namespace,
        bytes32 migration,
        bytes memory meta
    ) internal pure {
        uint256 metas = 0;
        for (uint256 i = 0; i < entries.length; i++) {
            if (
                entries[i].emitter == LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS
                    && entries[i].topics[0] == META_TOPIC
            ) {
                metas++;
                assertEq(entries[i].data, abi.encode(sender, keccak256(abi.encode(writer, namespace, migration)), meta));
            }
        }
        assertEq(metas, meta.length > 0 ? 1 : 0);
    }

    /// The direct writes send the meta, with the calling contract as the
    /// sender.
    function testApplyMigrationSendsMeta(bytes32 namespace, bytes32 migration, bool history, bytes memory meta)
        external
    {
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        if (meta.length > 0) meta = rainMeta(meta);
        IMigrationRegistryV5 registry = deployRegistry();
        MockMigrationApplier applier = new MockMigrationApplier();
        address writer = address(applier);
        Prerequisite[] memory list = onto(registry, writer, namespace);
        vm.recordLogs();
        if (history) {
            applier.applyMigrationHistoryV5(writer, namespace, migration, block.timestamp, list, meta);
        } else {
            applier.applyMigrationV5(writer, namespace, migration, list, meta);
        }
        assertMeta(vm.getRecordedLogs(), writer, writer, namespace, migration, meta);
    }

    /// The built calls carry the meta, with the executing account, here a
    /// delegate of the writer, as the sender.
    function testApplyMigrationCallCarriesMeta(
        address writer,
        address executor,
        bytes32 namespace,
        bytes32 migration,
        bool history,
        bytes memory meta
    ) external {
        vm.assume(writer != address(0) && executor != address(0) && executor != writer);
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        if (meta.length > 0) meta = rainMeta(meta);
        IMigrationRegistryV5 registry = deployRegistry();
        vm.assume(executor != address(registry) && executor != address(vm));
        vm.prank(writer);
        registry.approveV5(namespace, executor);
        Prerequisite[] memory list = onto(registry, writer, namespace);
        (address to, bytes memory data) = history
            ? LibMigrationRegistry.applyMigrationHistoryV4Call(
                writer, namespace, migration, block.timestamp, list, meta
            )
            : LibMigrationRegistry.applyMigrationV4Call(writer, namespace, migration, list, meta);
        vm.recordLogs();
        vm.prank(executor);
        (bool success,) = to.call(data);
        assertTrue(success);
        assertMeta(vm.getRecordedLogs(), executor, writer, namespace, migration, meta);
        assertEq(registry.headV5(writer, namespace), migration);
    }
}
