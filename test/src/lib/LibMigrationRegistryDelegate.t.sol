// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibMigrationRegistry} from "../../../src/lib/LibMigrationRegistry.sol";
import {LibMigrationRegistryDeploy} from "../../../src/lib/LibMigrationRegistryDeploy.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {Prerequisite, MIGRATION_HEAD_GENESIS} from "../../../src/interface/IMigrationRegistryV2.sol";
import {IMigrationRegistryV3} from "../../../src/interface/IMigrationRegistryV3.sol";
import {MigrationRegistry} from "../../../src/concrete/MigrationRegistry.sol";

/// @title LibMigrationRegistryDelegateTest
/// @notice The delegation builders and read: each targets the pinned
/// registry, encodes exactly the call it names, lands as that call when sent,
/// and refuses a chain without the registry by its code hash.
contract LibMigrationRegistryDelegateTest is Test {
    address internal constant WRITER = address(0x1111);
    address internal constant DELEGATE = address(0x2222);
    bytes32 internal constant NAMESPACE = keccak256("namespace");
    bytes32 internal constant MIGRATION = keccak256("migration");

    function deployRegistry() internal {
        LibRainDeploy.etchAndDeployZoltu(vm, type(MigrationRegistry).creationCode);
    }

    function genesis() internal pure returns (Prerequisite[] memory prerequisites) {
        prerequisites = new Prerequisite[](1);
        prerequisites[0] = Prerequisite({writer: WRITER, namespace: NAMESPACE, migration: MIGRATION_HEAD_GENESIS});
    }

    function send(address sender, address to, bytes memory data) internal {
        vm.prank(sender);
        (bool success,) = to.call(data);
        assertTrue(success);
    }

    function expectNoRegistry() internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                LibMigrationRegistry.UnexpectedMigrationRegistryCodeHash.selector,
                LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_CODEHASH,
                bytes32(0)
            )
        );
    }

    function externalApproveCall() external view returns (address, bytes memory) {
        return LibMigrationRegistry.approveCall(NAMESPACE, DELEGATE);
    }

    function externalRevokeCall() external view returns (address, bytes memory) {
        return LibMigrationRegistry.revokeCall(NAMESPACE, DELEGATE);
    }

    function externalApproved() external view returns (bool) {
        return LibMigrationRegistry.approved(WRITER, NAMESPACE, DELEGATE);
    }

    /// Approve then revoke, built and sent by the writer, are what `approved`
    /// answers.
    function testApproveAndRevokeCallsLand() external {
        deployRegistry();
        (address to, bytes memory data) = LibMigrationRegistry.approveCall(NAMESPACE, DELEGATE);
        assertEq(to, LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS);
        assertEq(data, abi.encodeCall(IMigrationRegistryV3.approve, (NAMESPACE, DELEGATE)));
        send(WRITER, to, data);
        assertTrue(LibMigrationRegistry.approved(WRITER, NAMESPACE, DELEGATE));

        (to, data) = LibMigrationRegistry.revokeCall(NAMESPACE, DELEGATE);
        assertEq(to, LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS);
        assertEq(data, abi.encodeCall(IMigrationRegistryV3.revoke, (NAMESPACE, DELEGATE)));
        send(WRITER, to, data);
        assertFalse(LibMigrationRegistry.approved(WRITER, NAMESPACE, DELEGATE));
    }

    /// A delegated write, built and sent by an approved delegate, lands in the
    /// writer's line.
    function testApplyMigrationCallDelegatedLands() external {
        deployRegistry();
        (address to, bytes memory data) = LibMigrationRegistry.approveCall(NAMESPACE, DELEGATE);
        send(WRITER, to, data);
        (to, data) = LibMigrationRegistry.applyMigrationV3Call(WRITER, NAMESPACE, MIGRATION, genesis());
        assertEq(to, LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS);
        assertEq(data, abi.encodeCall(IMigrationRegistryV3.applyMigrationV3, (WRITER, NAMESPACE, MIGRATION, genesis())));
        send(DELEGATE, to, data);
        assertEq(LibMigrationRegistry.applied(WRITER, NAMESPACE, MIGRATION), block.timestamp);
    }

    /// A delegated history write carries its moment into the writer's line.
    function testApplyMigrationHistoryCallDelegatedLands(uint256 appliedAt) external {
        vm.warp(1_000_000);
        appliedAt = bound(appliedAt, 1, block.timestamp);
        deployRegistry();
        (address to, bytes memory data) = LibMigrationRegistry.approveCall(NAMESPACE, DELEGATE);
        send(WRITER, to, data);
        (to, data) =
            LibMigrationRegistry.applyMigrationHistoryV3Call(WRITER, NAMESPACE, MIGRATION, appliedAt, genesis());
        assertEq(to, LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS);
        assertEq(
            data,
            abi.encodeCall(
                IMigrationRegistryV3.applyMigrationHistoryV3, (WRITER, NAMESPACE, MIGRATION, appliedAt, genesis())
            )
        );
        send(DELEGATE, to, data);
        assertEq(LibMigrationRegistry.applied(WRITER, NAMESPACE, MIGRATION), appliedAt);
    }

    /// The approval builders and the read refuse a chain with no registry.
    function testNoRegistryIsRefused() external {
        assertEq(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS.code.length, 0);
        expectNoRegistry();
        this.externalApproveCall();
        expectNoRegistry();
        this.externalRevokeCall();
        expectNoRegistry();
        this.externalApproved();
    }
}
