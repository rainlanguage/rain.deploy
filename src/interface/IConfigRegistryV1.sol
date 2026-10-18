// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @title IConfigRegistryV1
/// @notice A registry of `bytes32` names to ABI-encoded values with exactly two
/// operations: an immutable root authority binds a name (`register`), and
/// anyone reads a bound name (`get`). Root may re-bind a name it has already
/// bound. There is no removal, no upgrade and no authority beyond root, and an
/// implementation MUST NOT add any.
///
/// `IAddressRegistryV1` binds a name to an `address` and nothing else, so every other piece of
/// deploy-time configuration — a role id, a threshold, a delay, a list of
/// accounts, a code hash — still has to be compiled into creation code, where
/// changing it moves the deterministic address. This binds a name to `bytes`,
/// which the registry holds and returns verbatim. What they encode is agreed
/// between whoever binds the name and whoever reads it: an address binding is
/// `abi.encode(account)`, and its reader decodes it with
/// `abi.decode(value, (address))`. The registry never decodes a value and an
/// implementation MUST NOT constrain one beyond refusing it empty.
///
/// Names are opaque 32-byte values. This interface says nothing about how a
/// name is derived — hashed from a string, a raw ASCII literal, a counter — and
/// an implementation MUST NOT constrain it. Two callers agreeing on a name is
/// entirely their business.
///
/// Bindings are mutable because the configuration they name is. Rotating an
/// owning multisig is ordinary business, and a binding that could never change
/// would make it impossible: the name a consumer resolves is in that consumer's
/// creation code, so a name welded to one value forever would force a new name
/// — and therefore new creation code and a new deterministic address — for a
/// routine rotation. That is the problem the registry exists to remove, not a
/// property worth keeping.
///
/// A binding moving never moves anything already deployed. A consumer resolves
/// a name once, at construction, and stores the answer; it never consults the
/// registry again. So re-binding a name changes what the *next* deployment
/// resolves and nothing else, which is exactly what makes a rotation a
/// deliberate migration rather than a silent, retroactive change to live
/// contracts.
///
/// A compromised root therefore cannot touch anything deployed. It can point a
/// name at a value it chose, so that a deployment made after the compromise
/// snapshots that value. That is caught by verifying a deployment after
/// deploying it and before anything depends on it: the deployed contract has
/// already snapshotted the value, so checking it is checking settled state. A
/// poisoned deploy is a burned deterministic address, discovered before use.
///
/// `get` also answers with the moment a binding was made, because a value alone
/// cannot say that it has just moved. The registry reports the moment and
/// imposes nothing on it: a fresh binding is live at once, and an
/// implementation MUST NOT withhold one. What counts as too fresh belongs to
/// the caller.
interface IConfigRegistryV1 {
    /// Thrown when an account that is not the root authority calls `register`.
    /// @param sender The `msg.sender` that was not root.
    error NotRoot(address sender);

    /// Thrown when `register` is called with an empty value. Empty is how an
    /// unbound name reads, so binding it would produce a name that is both
    /// bound and unreadable. A name cannot be unbound once bound; the closest
    /// thing is binding it to something deliberately inert.
    /// @param name The name that was being bound to an empty value.
    error EmptyValue(bytes32 name);

    /// Thrown by `get` when a name has never been bound, so that a caller
    /// cannot silently proceed on an empty value by forgetting to check.
    /// @param name The name that is not bound.
    error NameNotRegistered(bytes32 name);

    /// Thrown by `register` when the clock is not strictly after the moment the
    /// name already carries.
    ///
    /// Behind it would lower the moment, and a caller measuring
    /// `block.timestamp -` it would then read an age larger than the time that
    /// passed. Equal to it means a re-bind that changes the value while leaving
    /// the moment identical, which a caller cannot detect. An unbound name reads
    /// as a moment of zero, so a bind at a clock of zero is refused too: zero is
    /// the field's unset value, and refusing it is what makes a stored moment
    /// never zero.
    /// @param name The name that was being bound.
    /// @param timestamp The clock the bind was attempted at.
    /// @param registeredAt The moment the name carries. Zero when unbound.
    error TimestampNotAfterBinding(bytes32 name, uint256 timestamp, uint256 registeredAt);

    /// Emitted every time `name` is bound, including when it is re-bound. The
    /// log is the complete history of the registry and the only way to discover
    /// a binding without already knowing the name; the most recent `Register`
    /// for a name is its current binding.
    ///
    /// `value` is not indexed, because an indexed `bytes` is logged as its hash
    /// and the history would then not hold the values.
    ///
    /// The moment is not a field here, because a log already carries the block
    /// it was emitted in.
    /// @param sender The account that called, which is always the root.
    /// @param name The name that was bound.
    /// @param value The value `name` was bound to.
    event Register(address sender, bytes32 indexed name, bytes value);

    /// Binds `name` to `value`, replacing any value it is already bound to.
    ///
    /// The implementation MUST revert `NotRoot` unless the caller is the root
    /// authority, MUST revert `EmptyValue` if `value` is empty, and MUST revert
    /// `TimestampNotAfterBinding` unless the clock is strictly after the moment
    /// the name carries, so a name's moment strictly increases. On success it
    /// MUST emit `Register` and record `block.timestamp` as the moment —
    /// including when `value` is the value already bound, which is a bind like
    /// any other. The moment dates the write, not the value.
    /// @param name The name to bind.
    /// @param value The ABI-encoded value to bind it to.
    function register(bytes32 name, bytes calldata value) external;

    /// The value `name` is currently bound to, and when it was bound.
    ///
    /// The implementation MUST revert `NameNotRegistered` when `name` is
    /// unbound, rather than returning an empty value, so that no caller has to
    /// remember to check. It MUST NOT expose any other reader that returns an
    /// empty value for an unbound name, as that reintroduces exactly the mistake
    /// this reverting read exists to prevent. An implementation storing the
    /// moment narrower than `block.timestamp` MUST reject what does not fit
    /// rather than truncate it, since a truncated moment reads as older.
    ///
    /// Answers with the current binding: whatever root has bound most
    /// recently, and the moment it was bound. A caller that stores the result
    /// keeps that value; one that reads again gets whatever is current then.
    /// @param name The name to read.
    /// @return The value bound to `name`, byte for byte as it was bound. Never
    /// empty.
    /// @return The `block.timestamp` of the most recent `register` for `name`.
    /// Never zero, so zero in this field means unbound and nothing else.
    function get(bytes32 name) external view returns (bytes memory, uint256);
}
