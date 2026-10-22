// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {IRegistryDelegatesV1} from "../interface/IRegistryDelegatesV1.sol";

/// @title RegistryDelegates
/// @notice The delegation `ConfigRegistry` and `MigrationRegistry` share, as
/// `IRegistryDelegatesV1` describes it. Each registry checks its own other keys
/// before calling in.
abstract contract RegistryDelegates is IRegistryDelegatesV1 {
    mapping(address account => mapping(bytes32 scope => mapping(address delegate => bool))) internal sApproved;

    /// Refuses the zero delegate with `ZeroDelegate`.
    /// @param delegate The delegate.
    function checkDelegateKey(address delegate) internal pure {
        if (delegate == address(0)) {
            revert ZeroDelegate();
        }
    }

    /// Approves `delegate` within `scope` under the caller and emits
    /// `Approved`.
    /// @param scope The scope under the caller.
    /// @param delegate The delegate.
    function approveWithin(bytes32 scope, address delegate) internal {
        checkDelegateKey(delegate);
        sApproved[msg.sender][scope][delegate] = true;
        emit Approved(msg.sender, scope, delegate);
    }

    /// Revokes `delegate` within `scope` under the caller and emits `Revoked`.
    /// @param scope The scope under the caller.
    /// @param delegate The delegate.
    function revokeWithin(bytes32 scope, address delegate) internal {
        checkDelegateKey(delegate);
        sApproved[msg.sender][scope][delegate] = false;
        emit Revoked(msg.sender, scope, delegate);
    }

    /// @param account The approving account.
    /// @param scope The scope under `account`.
    /// @param delegate The delegate.
    /// @return Whether `account` has approved `delegate` within `scope`.
    function approvedWithin(address account, bytes32 scope, address delegate) internal view returns (bool) {
        checkDelegateKey(delegate);
        return sApproved[account][scope][delegate];
    }

    /// Reverts `NotApproved` unless the caller is `account` or a delegate it
    /// approved within `scope`.
    /// @param account The account written under.
    /// @param scope The scope under `account`.
    function checkCallerWritesUnder(address account, bytes32 scope) internal view {
        if (msg.sender != account && !sApproved[account][scope][msg.sender]) {
            revert NotApproved(account, scope, msg.sender);
        }
    }

    /// Refuses an account and scope this registry does not key. Nothing by
    /// default; a registry that keys fewer overrides it.
    /// @param account The account.
    /// @param scope The scope under it.
    function checkScope(address account, bytes32 scope) internal view virtual {}

    /// @inheritdoc IRegistryDelegatesV1
    function approveV3(bytes32 scope, address delegate) external {
        checkScope(msg.sender, scope);
        approveWithin(scope, delegate);
    }

    /// @inheritdoc IRegistryDelegatesV1
    function revokeV3(bytes32 scope, address delegate) external {
        checkScope(msg.sender, scope);
        revokeWithin(scope, delegate);
    }

    /// @inheritdoc IRegistryDelegatesV1
    function approvedV3(address account, bytes32 scope, address delegate) external view returns (bool) {
        checkScope(account, scope);
        return approvedWithin(account, scope, delegate);
    }
}
