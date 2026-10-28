// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {LibConfigRegistryDeploy} from "./LibConfigRegistryDeploy.sol";
import {RegistryDelegation} from "./LibRegistryDelegatesApprove.sol";

/// @title LibConfigRegistryApprove
/// @notice The pinned `ConfigRegistry` as `LibRegistryDelegatesApprove` drives it.
library LibConfigRegistryApprove {
    /// @return The pinned registry and its code hash.
    function delegation() internal pure returns (RegistryDelegation memory) {
        return RegistryDelegation({
            registry: LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS,
            codehash: LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_CODEHASH
        });
    }
}
