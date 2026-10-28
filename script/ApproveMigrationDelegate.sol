// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {ApproveRegistryDelegate} from "./ApproveRegistryDelegate.sol";
import {RegistryDelegation} from "../src/lib/LibRegistryDelegatesApprove.sol";
import {LibMigrationRegistryApprove} from "../src/lib/LibMigrationRegistryApprove.sol";

/// @title ApproveMigrationDelegate
/// @notice `ApproveRegistryDelegate` for the delegates that write an authority's line in a namespace in the `MigrationRegistry`, with
/// variables prefixed `MIGRATION_DELEGATE`.
contract ApproveMigrationDelegate is ApproveRegistryDelegate {
    /// @inheritdoc ApproveRegistryDelegate
    function envPrefix() internal pure override returns (string memory) {
        return "MIGRATION_DELEGATE";
    }

    /// @inheritdoc ApproveRegistryDelegate
    function delegation() internal pure override returns (RegistryDelegation memory) {
        return LibMigrationRegistryApprove.delegation();
    }
}
