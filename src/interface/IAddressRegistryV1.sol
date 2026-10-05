// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @title IAddressRegistryV1
/// @notice A registry of `bytes32` names to addresses with exactly three
/// operations: an immutable root authority binds a name (`register`), anyone
/// reads a bound name (`get`), and anyone reads when it was most recently bound
/// (`registeredAt`). Root may re-bind a name it has already bound. There is no
/// removal, no upgrade and no authority beyond root, and an implementation MUST
/// NOT add any.
///
/// Names are opaque 32-byte values. This interface says nothing about how a
/// name is derived — hashed from a string, a raw ASCII literal, a counter — and
/// an implementation MUST NOT constrain it. Two callers agreeing on a name is
/// entirely their business.
///
/// Bindings are mutable because the addresses they name are. Rotating an owning
/// multisig is ordinary business, and a binding that could never change would
/// make it impossible: the name a consumer resolves is in that consumer's
/// creation code, so a name welded to one address forever would force a new
/// name — and therefore new creation code and a new deterministic address — for
/// a routine rotation. That is the problem the registry exists to remove, not a
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
/// name at an address it controls, so that a deployment made after the
/// compromise snapshots that address. That is caught by verifying a deployment
/// after deploying it and before anything depends on it: the deployed contract
/// has already snapshotted the value, so checking it is checking settled state.
/// A poisoned deploy is a burned deterministic address, discovered before use.
///
/// That containment rests on the resolve happening at a moment someone is
/// watching, which a deploy is. It says nothing about a resolve that happens
/// later, so a root compromise can sit dormant on an honest binding and be
/// switched immediately before one — and an address on its own cannot say that
/// it has just moved. `registeredAt` is what makes the age of an answer
/// readable on chain, where before it could only be recovered by enumerating
/// `Register` logs, which a contract cannot do at all and an archive-less node
/// cannot be relied on to answer.
///
/// The registry reports the age and imposes nothing on it. A fresh binding is
/// live the moment it is bound, exactly as before; the registry does NOT hold
/// one pending until some delay elapses, and an implementation MUST NOT. How
/// fresh is too fresh belongs to the consumer, which is the only party that
/// knows what it is resolving a name for, and differs between consumers — a
/// single delay here would weld one answer into a contract that can never be
/// upgraded, and a pending binding would additionally be a second thing a name
/// can be and an authority over readers that this interface does not grant.
interface IAddressRegistryV1 {
    /// Thrown when an account that is not the root authority calls `register`.
    /// @param sender The `msg.sender` that was not root.
    error NotRoot(address sender);

    /// Thrown when `register` is called with the zero address. The zero address
    /// is how an unbound name reads, so binding it would produce a name that is
    /// both bound and unreadable. A name cannot be unbound once bound; the
    /// closest thing is binding it somewhere deliberately inert.
    /// @param name The name that was being bound to the zero address.
    error ZeroAccount(bytes32 name);

    /// Thrown by `get` when a name has never been bound, so that a caller
    /// cannot silently proceed on the zero address by forgetting to check.
    /// @param name The name that is not bound.
    error NameNotRegistered(bytes32 name);

    /// Emitted every time `name` is bound, including when it is re-bound. The
    /// log is the complete history of the registry and the only way to discover
    /// a binding without already knowing the name; the most recent `Register`
    /// for a name is its current binding.
    ///
    /// The stamp `registeredAt` answers with is deliberately not a field here. A
    /// log already carries the block it was emitted in, so emitting
    /// `block.timestamp` beside it would be the same fact twice, and a reader
    /// taking the stamp from the event body rather than from the block would be
    /// trusting the emitter for something the chain already told it.
    /// @param name The name that was bound.
    /// @param account The address `name` was bound to.
    event Register(bytes32 indexed name, address indexed account);

    /// Binds `name` to `account`, replacing any address it is already bound to.
    ///
    /// The implementation MUST revert `NotRoot` unless the caller is the root
    /// authority, and MUST revert `ZeroAccount` if `account` is the zero
    /// address. On success it MUST emit `Register`, and MUST record
    /// `block.timestamp` as the name's stamp in place of any stamp it already
    /// carries — including when `account` is the address `name` already holds,
    /// which is a bind like any other and so refreshes the stamp. The stamp
    /// dates the WRITE, not the value: root re-asserting a binding is root
    /// touching it, and reporting the later moment is the conservative
    /// direction — it can only make an answer look fresher than the address
    /// really is, so a consumer refusing fresh answers errs toward refusing,
    /// never toward accepting one it meant to refuse.
    /// @param name The name to bind.
    /// @param account The address to bind it to.
    function register(bytes32 name, address account) external;

    /// The address `name` is currently bound to.
    ///
    /// The implementation MUST revert `NameNotRegistered` when `name` is
    /// unbound, rather than returning the zero address, so that no caller has
    /// to remember to check. It MUST NOT expose any other reader that returns
    /// the zero address for an unbound name, as that reintroduces exactly the
    /// mistake this reverting read exists to prevent.
    ///
    /// A caller that needs an answer that cannot move MUST read once and store
    /// the result, which is what a consumer resolving a name in its constructor
    /// does. Reading at the point of use instead means reading whatever root
    /// has bound most recently.
    /// @param name The name to read.
    /// @return The address bound to `name`. Never the zero address.
    function get(bytes32 name) external view returns (address);

    /// When `name` was most recently bound.
    ///
    /// The implementation MUST revert `NameNotRegistered` when `name` is
    /// unbound, for the same reason `get` does, and here the reason is sharper:
    /// zero is an ordinary number to subtract from, so answering an unbound name
    /// with zero would hand a freshness check an age of "the whole of time" —
    /// the one answer that passes every such check.
    ///
    /// An implementation that stores the stamp narrower than `block.timestamp`
    /// MUST reject a timestamp that does not fit rather than truncate it. A
    /// truncated stamp is a SMALLER number, which reads as an OLDER binding,
    /// which passes exactly the check this reader exists to let a caller fail.
    /// @param name The name to read.
    /// @return The `block.timestamp` of the most recent `register` for `name`.
    /// Zero only on a chain whose block time is itself zero, which is why an
    /// unbound name is a revert and not a zero: nothing else separates the two.
    function registeredAt(bytes32 name) external view returns (uint256);
}
