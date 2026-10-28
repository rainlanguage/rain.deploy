// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {IRegistryDelegatesV3} from "../interface/IRegistryDelegatesV3.sol";

/// @title RegistryDelegates
/// @notice The delegation `ConfigRegistry` and `MigrationRegistry` share, as
/// `IRegistryDelegatesV3` describes it. Each registry checks its own other keys
/// before calling in.
abstract contract RegistryDelegates is IRegistryDelegatesV3 {
    mapping(address account => mapping(bytes32 scope => mapping(address delegate => bool))) internal sApproved;

    /// The delegates each account approved unscoped.
    mapping(address account => mapping(address delegate => bool)) internal sApprovedUnscoped;

    /// Refuses the zero delegate with `ZeroDelegate`.
    /// @param delegate The delegate.
    function checkDelegateKey(address delegate) internal pure {
        if (delegate == address(0)) {
            revert ZeroDelegate();
        }
    }

    /// Refuses an account this registry does not key. Nothing by default; a
    /// registry that keys fewer overrides it.
    /// @param account The account.
    function checkAccount(address account) internal pure virtual {}

    /// Reached by every write: refuses an account this registry does not key,
    /// then reverts `NotApproved` unless the caller is `account`, a delegate it
    /// approved within `scope`, or a delegate it approved unscoped.
    /// Settled before anything about the write.
    /// @param account The account written under.
    /// @param scope The scope under `account`.
    function checkWrite(address account, bytes32 scope) internal view {
        checkAccount(account);
        if (msg.sender != account && !sApproved[account][scope][msg.sender] && !sApprovedUnscoped[account][msg.sender])
        {
            revert NotApproved(account, scope, msg.sender);
        }
    }

    /// Refuses an account and scope this registry does not key. Nothing by
    /// default; a registry that keys fewer overrides it.
    /// @param account The account.
    /// @param scope The scope under it.
    function checkScope(address account, bytes32 scope) internal pure virtual {}

    /// @inheritdoc IRegistryDelegatesV3
    function approveV5(bytes32 scope, address delegate) external {
        checkScope(msg.sender, scope);
        checkDelegateKey(delegate);
        sApproved[msg.sender][scope][delegate] = true;
        emit Approved(msg.sender, scope, delegate);
    }

    /// @inheritdoc IRegistryDelegatesV3
    function revokeV5(bytes32 scope, address delegate) external {
        checkScope(msg.sender, scope);
        checkDelegateKey(delegate);
        sApproved[msg.sender][scope][delegate] = false;
        emit Revoked(msg.sender, scope, delegate);
    }

    /// @inheritdoc IRegistryDelegatesV3
    function approvedV5(address account, bytes32 scope, address delegate) external view returns (bool) {
        checkScope(account, scope);
        checkDelegateKey(delegate);
        return sApproved[account][scope][delegate];
    }

    /// @inheritdoc IRegistryDelegatesV3
    function approveUnscopedV5(address delegate) external {
        checkDelegateKey(delegate);
        sApprovedUnscoped[msg.sender][delegate] = true;
        emit ApprovedUnscoped(msg.sender, delegate);
    }

    /// @inheritdoc IRegistryDelegatesV3
    function revokeUnscopedV5(address delegate) external {
        checkDelegateKey(delegate);
        sApprovedUnscoped[msg.sender][delegate] = false;
        emit RevokedUnscoped(msg.sender, delegate);
    }

    /// @inheritdoc IRegistryDelegatesV3
    function approvedUnscopedV5(address account, address delegate) external view returns (bool) {
        checkAccount(account);
        checkDelegateKey(delegate);
        return sApprovedUnscoped[account][delegate];
    }
}
