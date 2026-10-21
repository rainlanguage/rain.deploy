// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @title RegistryDelegates
/// @notice The delegation `ConfigRegistry` and `MigrationRegistry` share: an
/// account approves delegates to write under it within a scope, and only the
/// account or a delegate it approved for that scope writes there. Each registry
/// checks its own keys and emits and reverts with its own interface's events
/// and errors.
abstract contract RegistryDelegates {
    mapping(address account => mapping(bytes32 scope => mapping(address delegate => bool))) internal sApproved;

    /// Sets whether `delegate` writes under the caller within `scope`.
    /// @param scope The scope under the caller.
    /// @param delegate The delegate.
    /// @param approved Whether it is approved.
    function setApproval(bytes32 scope, address delegate, bool approved) internal {
        sApproved[msg.sender][scope][delegate] = approved;
    }

    /// @param account The approving account.
    /// @param scope The scope under `account`.
    /// @param delegate The delegate.
    /// @return Whether `account` has approved `delegate` within `scope`.
    function isApproved(address account, bytes32 scope, address delegate) internal view returns (bool) {
        return sApproved[account][scope][delegate];
    }

    /// @param account The account written under.
    /// @param scope The scope under `account`.
    /// @return Whether the caller is `account` or a delegate it approved within
    /// `scope`.
    function callerWritesUnder(address account, bytes32 scope) internal view returns (bool) {
        return msg.sender == account || sApproved[account][scope][msg.sender];
    }
}
