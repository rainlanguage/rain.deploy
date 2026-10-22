// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {IRegistryDelegatesV1} from "../interface/IRegistryDelegatesV1.sol";

/// @title LibRegistryDelegates
/// @notice The calldata of `IRegistryDelegatesV1`, which every registry
/// implements identically.
library LibRegistryDelegates {
    /// @param scope The scope under the sending account.
    /// @param delegate The delegate.
    /// @param approve True for `approveV3`, false for `revokeV3`.
    /// @return The calldata.
    function approveCalldata(bytes32 scope, address delegate, bool approve) internal pure returns (bytes memory) {
        return approve
            ? abi.encodeCall(IRegistryDelegatesV1.approveV3, (scope, delegate))
            : abi.encodeCall(IRegistryDelegatesV1.revokeV3, (scope, delegate));
    }
}
