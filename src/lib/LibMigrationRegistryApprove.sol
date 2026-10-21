// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {IMigrationRegistryV3} from "../interface/IMigrationRegistryV3.sol";
import {LibMigrationRegistry} from "./LibMigrationRegistry.sol";
import {LibMigrationRegistryDeploy} from "./LibMigrationRegistryDeploy.sol";
import {RegistryDelegation} from "./LibRegistryDelegatesApprove.sol";

/// @title LibMigrationRegistryApprove
/// @notice A writer's delegation side of `MigrationRegistry`: the
/// `RegistryDelegation` that `LibRegistryDelegatesApprove` drives to approve
/// one delegate for one namespace under the writer on every network it is
/// given, or revoke it, signed by the writer itself.
/// `script/ApproveMigrationDelegate.sol` is the entry point and says how it is
/// run. The namespace is written as a consumer writes it before hashing, and
/// refused unless canonical.
library LibMigrationRegistryApprove {
    /// `MigrationRegistry`'s delegation surface.
    /// @return The registry, as `LibRegistryDelegatesApprove` drives it.
    function delegation() internal pure returns (RegistryDelegation memory) {
        return RegistryDelegation({
            scopeLabel: "Namespace",
            scopeNoun: "namespace",
            registry: LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS,
            checkCodeHash: LibMigrationRegistry.checkCodeHash,
            approved: approved,
            approveCalldata: approveCalldata,
            setApproval: setApproval
        });
    }

    /// Whether `delegate` is approved for `namespace` under `writer`.
    /// @param writer The writer.
    /// @param namespace The hashed namespace.
    /// @param delegate The delegate.
    /// @return The registry's answer.
    function approved(address writer, bytes32 namespace, address delegate) internal view returns (bool) {
        return IMigrationRegistryV3(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS)
            .approvedV3(writer, namespace, delegate);
    }

    /// The calldata of the approval or revocation: what the device signs.
    /// @param namespace The hashed namespace.
    /// @param delegate The delegate.
    /// @param approve True for `approveV3`, false for `revokeV3`.
    /// @return The calldata.
    function approveCalldata(bytes32 namespace, address delegate, bool approve) internal pure returns (bytes memory) {
        return approve
            ? abi.encodeCall(IMigrationRegistryV3.approveV3, (namespace, delegate))
            : abi.encodeCall(IMigrationRegistryV3.revokeV3, (namespace, delegate));
    }

    /// Approves `delegate` for `namespace`, or revokes it, as the caller.
    /// @param namespace The hashed namespace.
    /// @param delegate The delegate.
    /// @param approve True to approve, false to revoke.
    function setApproval(bytes32 namespace, address delegate, bool approve) internal {
        IMigrationRegistryV3 registry =
            IMigrationRegistryV3(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS);
        if (approve) {
            registry.approveV3(namespace, delegate);
        } else {
            registry.revokeV3(namespace, delegate);
        }
    }
}
