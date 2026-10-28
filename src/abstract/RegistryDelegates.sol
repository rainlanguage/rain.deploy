// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {IRegistryDelegatesV2} from "../interface/IRegistryDelegatesV2.sol";
import {Multicall} from "@openzeppelin-contracts-5.7.0/utils/Multicall.sol";

/// @title RegistryDelegates
/// @notice The delegation `ConfigRegistry` and `MigrationRegistry` share, as
/// `IRegistryDelegatesV2` describes it. Each registry checks its own other keys
/// before calling in.
///
/// Both registries are `Multicall`, so an account batches its approvals and
/// writes into one transaction. Each call is a delegatecall into the registry
/// itself, so `msg.sender` in every call is the account that sent the batch.
abstract contract RegistryDelegates is IRegistryDelegatesV2, Multicall {
    mapping(address account => mapping(bytes32 scope => mapping(address delegate => bool))) internal sApproved;

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
    /// then reverts `NotApproved` unless the caller is `account` or a delegate
    /// it approved within `scope`. Settled before anything about the write.
    /// @param account The account written under.
    /// @param scope The scope under `account`.
    function checkWrite(address account, bytes32 scope) internal view {
        checkAccount(account);
        if (msg.sender != account && !sApproved[account][scope][msg.sender]) {
            revert NotApproved(account, scope, msg.sender);
        }
    }

    /// Refuses an account and scope this registry does not key. Nothing by
    /// default; a registry that keys fewer overrides it.
    /// @param account The account.
    /// @param scope The scope under it.
    function checkScope(address account, bytes32 scope) internal pure virtual {}

    /// @inheritdoc IRegistryDelegatesV2
    function approveV4(bytes32 scope, address delegate) external {
        checkScope(msg.sender, scope);
        checkDelegateKey(delegate);
        sApproved[msg.sender][scope][delegate] = true;
        emit Approved(msg.sender, scope, delegate);
    }

    /// @inheritdoc IRegistryDelegatesV2
    function revokeV4(bytes32 scope, address delegate) external {
        checkScope(msg.sender, scope);
        checkDelegateKey(delegate);
        sApproved[msg.sender][scope][delegate] = false;
        emit Revoked(msg.sender, scope, delegate);
    }

    /// @inheritdoc IRegistryDelegatesV2
    function approvedV4(address account, bytes32 scope, address delegate) external view returns (bool) {
        checkScope(account, scope);
        checkDelegateKey(delegate);
        return sApproved[account][scope][delegate];
    }
}
