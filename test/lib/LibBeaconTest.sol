// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";
import {DeployDependency, DeployMechanism, DeploySuite} from "../../src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeploy} from "../../src/lib/LibRainDeploy.sol";
import {LibMigrationRegistry} from "../../src/lib/LibMigrationRegistry.sol";
import {LibMigrationRegistryDeploy} from "../../src/lib/LibMigrationRegistryDeploy.sol";
import {IMigrationRegistryV3, Prerequisite} from "../../src/interface/IMigrationRegistryV3.sol";

/// @title LibBeaconTest
/// @notice The fixtures and assertions the beacon tests share.
library LibBeaconTest {
    /// Fails with `reason` when a fork is selected.
    /// @param vm The Vm instance to read the selected fork from.
    /// @param reason The failure message.
    function assertNoFork(Vm vm, string memory reason) internal view {
        try vm.activeFork() returns (uint256) {
            vm.assertTrue(false, reason);
        } catch {}
    }

    /// A Zoltu suite with no dependencies, its address and code hash derived from its code.
    /// @param key The suite key.
    /// @param creationCode The creation code.
    /// @param runtimeCode The runtime code `creationCode` leaves.
    /// @param artifactPath The artifact path.
    /// @return The suite.
    function zoltuSuite(
        string memory key,
        bytes memory creationCode,
        bytes memory runtimeCode,
        string memory artifactPath
    ) internal pure returns (DeploySuite memory) {
        return DeploySuite({
            suite: key,
            creationCode: creationCode,
            storedDeployedAddress: LibRainDeploy.zoltuAddress(creationCode),
            storedBytecodeHash: keccak256(runtimeCode),
            storedRuntimeCode: runtimeCode,
            artifactPath: artifactPath,
            dependencies: new DeployDependency[](0),
            mechanism: DeployMechanism.Zoltu,
            mechanismData: "",
            describedByMeta: ""
        });
    }

    /// A Zoltu suite of an `UpgradeableBeacon` at `implementation`, owned by `owner`.
    /// @param key The suite key.
    /// @param implementation The beacon's implementation.
    /// @param owner The beacon's owner.
    /// @return The suite.
    function beaconSuite(string memory key, address implementation, address owner)
        internal
        pure
        returns (DeploySuite memory)
    {
        return zoltuSuite(
            key,
            abi.encodePacked(type(UpgradeableBeacon).creationCode, abi.encode(implementation, owner)),
            type(UpgradeableBeacon).runtimeCode,
            "dependencies/@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol:UpgradeableBeacon"
        );
    }

    /// Applies `migration` as `writer` on the deployed `MigrationRegistry`, after `prerequisites`.
    /// @param vm The Vm instance to prank with.
    /// @param writer The writer.
    /// @param namespace The namespace.
    /// @param migration The migration.
    /// @param prerequisites The records it is applied after.
    function applyMigration(
        Vm vm,
        address writer,
        bytes32 namespace,
        bytes32 migration,
        Prerequisite[] memory prerequisites
    ) internal {
        vm.prank(writer);
        IMigrationRegistryV3(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS)
            .applyMigrationV3(writer, namespace, migration, prerequisites);
    }

    /// Applies `migration` as `writer` on the deployed `MigrationRegistry`, onto `head` in `namespace`.
    /// @param vm The Vm instance to prank with.
    /// @param writer The writer.
    /// @param namespace The namespace.
    /// @param migration The migration.
    /// @param head The writer's head in `namespace`.
    function applyMigration(Vm vm, address writer, bytes32 namespace, bytes32 migration, bytes32 head) internal {
        applyMigration(vm, writer, namespace, migration, LibMigrationRegistry.onto(writer, namespace, head));
    }
}
