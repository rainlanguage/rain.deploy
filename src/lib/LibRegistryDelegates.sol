// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {IRegistryDelegatesV2} from "../interface/IRegistryDelegatesV2.sol";

/// @title LibRegistryDelegates
/// @notice The calldata of `IRegistryDelegatesV2`, which every registry
/// implements identically.
library LibRegistryDelegates {
    /// @param scope The scope under the sending account.
    /// @param delegate The delegate.
    /// @param approve True for `approveV4`, false for `revokeV4`.
    /// @return The calldata.
    function approveCalldata(bytes32 scope, address delegate, bool approve) internal pure returns (bytes memory) {
        return approve
            ? abi.encodeCall(IRegistryDelegatesV2.approveV4, (scope, delegate))
            : abi.encodeCall(IRegistryDelegatesV2.revokeV4, (scope, delegate));
    }
}
