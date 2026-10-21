// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @title IRegistryDelegatesV1
/// @notice The delegation events and errors `IConfigRegistryV2` and
/// `IMigrationRegistryV3` share. An account approves a delegate to write under
/// it within one scope: a name in the config registry, a namespace in the
/// migration registry. An approval covers no other scope and no other account,
/// and does not chain.
interface IRegistryDelegatesV1 {
    /// Thrown when an approve, revoke or approved is given the zero delegate,
    /// which nothing can call from and which is what an uninitialised
    /// `address` reads as.
    error ZeroDelegate();

    /// Thrown when a write's caller is neither `account` nor approved by it
    /// within `scope`.
    /// @param account The account the write is under.
    /// @param scope The scope under the account.
    /// @param caller The account that called.
    error NotApproved(address account, bytes32 scope, address caller);

    /// Emitted when `sender` approves `delegate` to write under it within
    /// `scope`.
    /// @param sender The approving account, which is the account that called.
    /// @param scope The scope the approval covers.
    /// @param delegate The approved account.
    event Approved(address indexed sender, bytes32 indexed scope, address indexed delegate);

    /// Emitted when `sender` revokes `delegate` within `scope`, whether or not
    /// `delegate` was approved.
    /// @param sender The revoking account, which is the account that called.
    /// @param scope The scope the revocation covers.
    /// @param delegate The revoked account.
    event Revoked(address indexed sender, bytes32 indexed scope, address indexed delegate);
}
