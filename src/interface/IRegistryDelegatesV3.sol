// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @title IRegistryDelegatesV3
/// @notice The delegation `IConfigRegistryV5` and `IMigrationRegistryV5` share,
/// identically. An account approves a delegate to write under it, either
/// within one scope (a name in the config registry, a namespace in the
/// migration registry) or unscoped, within every scope present and future. A
/// scoped approval covers no other scope. Neither covers another account, and
/// neither chains. The two are independent: approving or revoking one leaves
/// the other as it is.
interface IRegistryDelegatesV3 {
    /// Thrown when an approve, revoke or approved is given the zero delegate,
    /// which nothing can call from and which is what an uninitialised
    /// `address` reads as.
    error ZeroDelegate();

    /// Thrown when a write's caller is not `account`, not approved by it within
    /// `scope`, and not approved by it unscoped.
    /// @param account The account the write is under.
    /// @param scope The scope under the account.
    /// @param caller The account that called.
    error NotApproved(address account, bytes32 scope, address caller);

    /// Emitted when `sender` approves `delegate` to write under it within
    /// `scope`.
    /// @param sender The approving account, which is the account that called.
    /// @param scope The scope the approval covers.
    /// @param delegate The approved account.
    event Approved(address sender, bytes32 scope, address delegate);

    /// Emitted when `sender` revokes `delegate` within `scope`, whether or not
    /// `delegate` was approved.
    /// @param sender The revoking account, which is the account that called.
    /// @param scope The scope the revocation covers.
    /// @param delegate The revoked account.
    event Revoked(address sender, bytes32 scope, address delegate);

    /// Approves `delegate` to write under the caller within `scope` and emits
    /// `Approved`. Approving an approved delegate leaves it approved and still
    /// emits. Refuses a scope the registry does not key (the migration
    /// registry's `ZeroNamespace`), then `ZeroDelegate`.
    /// @param scope The scope the approval covers.
    /// @param delegate The account to approve. MUST NOT be zero.
    function approveV5(bytes32 scope, address delegate) external;

    /// Revokes `delegate`'s approval to write under the caller within `scope`
    /// and emits `Revoked`. Revoking an unapproved delegate leaves it
    /// unapproved and still emits. Refuses as `approveV5` does.
    /// @param scope The scope the revocation covers.
    /// @param delegate The account to revoke. MUST NOT be zero.
    function revokeV5(bytes32 scope, address delegate) external;

    /// Whether `account` has approved `delegate` within `scope`. Refuses an
    /// account and scope the registry does not key (the migration registry's
    /// `ZeroWriter`, then `ZeroNamespace`), then `ZeroDelegate`, rather than
    /// answering false about a question the caller did not mean to ask. The
    /// config registry keys every account, so its zero authority answers false.
    /// @param account The approving account.
    /// @param scope The scope asked about.
    /// @param delegate The account asked about.
    /// @return True when approved.
    function approvedV5(address account, bytes32 scope, address delegate) external view returns (bool);

    /// Emitted when `sender` approves `delegate` to write under it unscoped.
    /// @param sender The approving account, which is the account that called.
    /// @param delegate The approved account.
    event ApprovedUnscoped(address sender, address delegate);

    /// Emitted when `sender` revokes `delegate`'s unscoped approval, whether or
    /// not `delegate` was approved.
    /// @param sender The revoking account, which is the account that called.
    /// @param delegate The revoked account.
    event RevokedUnscoped(address sender, address delegate);

    /// Approves `delegate` to write under the caller unscoped and emits
    /// `ApprovedUnscoped`. Approving an approved delegate leaves it approved and
    /// still emits. Refuses `ZeroDelegate`.
    /// @param delegate The account to approve. MUST NOT be zero.
    function approveUnscopedV5(address delegate) external;

    /// Revokes `delegate`'s unscoped approval under the caller and emits
    /// `RevokedUnscoped`. Scoped approvals are untouched. Refuses as
    /// `approveUnscopedV5` does.
    /// @param delegate The account to revoke. MUST NOT be zero.
    function revokeUnscopedV5(address delegate) external;

    /// Whether `account` has approved `delegate` unscoped. Refuses an account
    /// the registry does not key (the migration registry's `ZeroWriter`), then
    /// `ZeroDelegate`.
    /// @param account The approving account.
    /// @param delegate The account asked about.
    /// @return True when approved.
    function approvedUnscopedV5(address account, address delegate) external view returns (bool);
}
