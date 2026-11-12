// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {IRegistryDelegatesV3} from "../interface/IRegistryDelegatesV3.sol";

/// @title LibRegistryDelegates
/// @notice The calldata of `IRegistryDelegatesV3`, which every registry
/// implements identically, and the write check it enforces.
library LibRegistryDelegates {
    /// `checkWrite`'s predicate: `delegate` is `account`, or approved for `scope` or unscoped.
    /// @param registry The registry asked.
    /// @param account The account written under.
    /// @param scope The scope written in.
    /// @param delegate The account that would write.
    /// @return True when `registry` lets `delegate` write.
    function approved(IRegistryDelegatesV3 registry, address account, bytes32 scope, address delegate)
        internal
        view
        returns (bool)
    {
        return delegate == account || registry.approvedV5(account, scope, delegate)
            || registry.approvedUnscopedV5(account, delegate);
    }

    /// @param scope The scope under the sending account.
    /// @param delegate The delegate.
    /// @param approve True for `approveV5`, false for `revokeV5`.
    /// @return The calldata.
    function approveCalldata(bytes32 scope, address delegate, bool approve) internal pure returns (bytes memory) {
        return approve
            ? abi.encodeCall(IRegistryDelegatesV3.approveV5, (scope, delegate))
            : abi.encodeCall(IRegistryDelegatesV3.revokeV5, (scope, delegate));
    }

    /// @param delegate The delegate.
    /// @param approve True for `approveUnscopedV5`, false for `revokeUnscopedV5`.
    /// @return The calldata.
    function approveUnscopedCalldata(address delegate, bool approve) internal pure returns (bytes memory) {
        return approve
            ? abi.encodeCall(IRegistryDelegatesV3.approveUnscopedV5, (delegate))
            : abi.encodeCall(IRegistryDelegatesV3.revokeUnscopedV5, (delegate));
    }
}
