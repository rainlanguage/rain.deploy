// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {LibMigrationRegistryDeploy} from "./LibMigrationRegistryDeploy.sol";
import {RegistryDelegation} from "./LibRegistryDelegatesApprove.sol";

/// @title LibMigrationRegistryApprove
/// @notice The pinned `MigrationRegistry` as `LibRegistryDelegatesApprove` drives it.
library LibMigrationRegistryApprove {
    /// @return The pinned registry and its code hash.
    function delegation() internal pure returns (RegistryDelegation memory) {
        return RegistryDelegation({
            registry: LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS,
            codehash: LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_CODEHASH
        });
    }
}
