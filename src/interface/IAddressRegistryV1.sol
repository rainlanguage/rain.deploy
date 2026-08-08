// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @title IAddressRegistryV1
/// @notice A registry of `bytes32` names to addresses with exactly two
/// operations: an immutable root authority binds a name that is unbound, and
/// anyone reads a name that is bound. There is no rotation, no removal, no
/// upgrade and no admin surface, and an implementation MUST NOT add any: the
/// value of the registry is that a binding, once made, is a constant.
///
/// Names are opaque 32-byte values. This interface says nothing about how a
/// name is derived — hashed from a string, a raw ASCII literal, a counter — and
/// an implementation MUST NOT constrain it. Two callers agreeing on a name is
/// entirely their business.
///
/// The write-once property is what makes a deploy-time check of a binding worth
/// anything. Against a mutable value the check would be a race, because the
/// value could move between the check and the read that consumes it. Here, once
/// `get` returns for a name, it returns the same address forever.
///
/// Compromising root therefore cannot change any existing binding. It can reach
/// a network nobody has deployed to yet and bind the intended names against
/// itself, burning them there, which forces a different name on that network
/// and moves addresses on that network only. That is a loud, per-network loss
/// of determinism, never a silent or retroactive change.
interface IAddressRegistryV1 {
    /// Thrown when an account that is not the root authority calls `register`.
    /// @param sender The `msg.sender` that was not root.
    error NotRoot(address sender);

    /// Thrown when `register` is called for a name that is already bound.
    /// Bindings are write-once, so this is thrown even for root, and even when
    /// the account being registered is the account already bound.
    /// @param name The name that is already bound.
    /// @param account The address `name` is bound to.
    error NameAlreadyRegistered(bytes32 name, address account);

    /// Thrown when `register` is called with the zero address. The zero address
    /// is how an unbound name reads, so binding it would produce a name that is
    /// both bound and unreadable, and that `register` would accept a second
    /// time.
    /// @param name The name that was being bound to the zero address.
    error ZeroAccount(bytes32 name);

    /// Thrown by `get` when a name has never been bound, so that a caller
    /// cannot silently proceed on the zero address by forgetting to check.
    /// @param name The name that is not bound.
    error NameNotRegistered(bytes32 name);

    /// Emitted when `name` is bound to `account`. Bindings are write-once, so
    /// exactly one `Register` is ever emitted per name, and the log is the
    /// complete enumeration of the registry — there is no other way to discover
    /// a binding without already knowing the name. Both parameters are indexed
    /// for that reason: the log has to answer "what is this name bound to" and
    /// "what did root bind to this address" without a full scan.
    /// @param name The name that was bound.
    /// @param account The address `name` was bound to.
    event Register(bytes32 indexed name, address indexed account);

    /// Binds `name` to `account`, permanently.
    ///
    /// The implementation MUST revert `NotRoot` unless the caller is the root
    /// authority, MUST revert `ZeroAccount` if `account` is the zero address,
    /// and MUST revert `NameAlreadyRegistered` if `name` is already bound —
    /// including when the caller is root and including when `account` is the
    /// address already bound. On success it MUST emit `Register`.
    /// @param name The name to bind.
    /// @param account The address to bind it to.
    function register(bytes32 name, address account) external;

    /// The address `name` is bound to.
    ///
    /// The implementation MUST revert `NameNotRegistered` when `name` is
    /// unbound, rather than returning the zero address, so that no caller has
    /// to remember to check. It MUST NOT expose any other reader that returns
    /// the zero address for an unbound name, as that reintroduces exactly the
    /// mistake this reverting read exists to prevent.
    /// @param name The name to read.
    /// @return account The address bound to `name`. Never the zero address.
    function get(bytes32 name) external view returns (address account);
}
