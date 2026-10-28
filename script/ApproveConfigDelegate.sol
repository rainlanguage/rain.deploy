// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {ApproveRegistryDelegate} from "./ApproveRegistryDelegate.sol";
import {RegistryDelegation} from "../src/lib/LibRegistryDelegatesApprove.sol";
import {LibConfigRegistryApprove} from "../src/lib/LibConfigRegistryApprove.sol";

/// @title ApproveConfigDelegate
/// @notice `ApproveRegistryDelegate` for the delegates that bind a name under an authority in the `ConfigRegistry`, with
/// variables prefixed `CONFIG_DELEGATE`.
contract ApproveConfigDelegate is ApproveRegistryDelegate {
    /// @inheritdoc ApproveRegistryDelegate
    function envPrefix() internal pure override returns (string memory) {
        return "CONFIG_DELEGATE";
    }

    /// @inheritdoc ApproveRegistryDelegate
    function delegation() internal pure override returns (RegistryDelegation memory) {
        return LibConfigRegistryApprove.delegation();
    }
}
