// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {IConfigRegistryV2} from "../interface/IConfigRegistryV2.sol";
import {LibConfigRegistry} from "./LibConfigRegistry.sol";
import {LibConfigRegistryDeploy} from "./LibConfigRegistryDeploy.sol";
import {RegistryDelegation} from "./LibRegistryDelegatesApprove.sol";

/// @title LibConfigRegistryApprove
/// @notice An authority's delegation side of `ConfigRegistry`: approves one
/// delegate for one name under the authority on every network it is given, or
/// revokes it, signed by the authority itself, and reads the approval back.
/// `script/ApproveConfigDelegate.sol` is the entry point and says how it is
/// run. The behaviour and the guards are `LibRegistryDelegatesApprove`'s, over
/// `delegation()`; the name is a scope, hashed the way `RegisterConfig` binds
/// it and a consumer resolves it.
library LibConfigRegistryApprove {
    /// `ConfigRegistry`'s delegation surface.
    /// @return The registry, as `LibRegistryDelegatesApprove` drives it.
    function delegation() internal pure returns (RegistryDelegation memory) {
        return RegistryDelegation({
            scopeLabel: "Name",
            scopeNoun: "name",
            registry: LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS,
            checkCodeHash: LibConfigRegistry.checkCodeHash,
            approved: approved,
            approveCalldata: approveCalldata,
            setApproval: setApproval
        });
    }

    /// Whether `delegate` is approved for `name` under `authority`.
    /// @param authority The authority.
    /// @param name The hashed name.
    /// @param delegate The delegate.
    /// @return The registry's answer.
    function approved(address authority, bytes32 name, address delegate) internal view returns (bool) {
        return IConfigRegistryV2(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS)
            .approvedV2(authority, name, delegate);
    }

    /// The calldata of the approval or revocation: what the device signs.
    /// @param name The hashed name.
    /// @param delegate The delegate.
    /// @param approve True for `approveV2`, false for `revokeV2`.
    /// @return The calldata.
    function approveCalldata(bytes32 name, address delegate, bool approve) internal pure returns (bytes memory) {
        return approve
            ? abi.encodeCall(IConfigRegistryV2.approveV2, (name, delegate))
            : abi.encodeCall(IConfigRegistryV2.revokeV2, (name, delegate));
    }

    /// Approves `delegate` for `name`, or revokes it, as the caller.
    /// @param name The hashed name.
    /// @param delegate The delegate.
    /// @param approve True to approve, false to revoke.
    function setApproval(bytes32 name, address delegate, bool approve) internal {
        IConfigRegistryV2 registry = IConfigRegistryV2(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS);
        if (approve) {
            registry.approveV2(name, delegate);
        } else {
            registry.revokeV2(name, delegate);
        }
    }
}
