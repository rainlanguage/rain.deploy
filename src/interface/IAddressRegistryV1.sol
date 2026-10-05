// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @title IAddressRegistryV1
/// @notice A registry of `bytes32` names to addresses with exactly two
/// operations: an immutable root authority binds a name (`register`), and
/// anyone reads a bound name (`get`), which answers with the address and the
/// moment it was bound. Root may re-bind a name it has already bound. There is
/// no removal, no upgrade and no authority beyond root, and an implementation
/// MUST NOT add any.
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
/// The moment of binding comes back with the address because an address alone
/// cannot say that it has just moved, and a caller about to snapshot one may
/// want to refuse an answer that was bound moments ago. The registry reports
/// the moment and imposes nothing on it: a fresh binding is live as soon as it
/// is bound, and an implementation MUST NOT withhold one. What counts as too
/// fresh belongs to the caller, which is the only party that knows what it is
/// resolving the name for.
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

    /// Thrown by `register` when the clock is not STRICTLY after the moment the
    /// name already carries.
    ///
    /// A name's moment is strictly increasing, and that is a property callers
    /// rely on rather than an accident of how clocks behave. Two things follow
    /// from it, and the strictness is needed for both.
    ///
    /// A clock BEHIND the stored moment would lower it. A caller measuring
    /// `block.timestamp -` that moment would then compute an age LARGER than the
    /// time that has actually passed, so a re-bind from moments ago could report
    /// as long-settled and clear a freshness threshold. The whole value of the
    /// moment is that the age derived from it is never an overstatement.
    ///
    /// A clock EQUAL to the stored moment is refused for a separate reason: two
    /// transactions in one block share a `block.timestamp`, so an equal clock
    /// means a re-bind that replaces the address while leaving the moment
    /// identical — two distinct bindings a caller cannot tell apart by the only
    /// signal the registry gives it about when it changed.
    ///
    /// The rule binds a RE-bind only. An unbound name carries no moment for a
    /// new one to be after, so a first bind is unconstrained.
    /// @param name The name that was being bound.
    /// @param timestamp The clock the bind was attempted at.
    /// @param registeredAt The moment the name already carries, which that clock
    /// is not after.
    error TimestampNotAfterBinding(bytes32 name, uint256 timestamp, uint256 registeredAt);

    /// Emitted every time `name` is bound, including when it is re-bound. The
    /// log is the complete history of the registry and the only way to discover
    /// a binding without already knowing the name; the most recent `Register`
    /// for a name is its current binding.
    ///
    /// The moment is not a field here, because a log already carries the block
    /// it was emitted in.
    /// @param name The name that was bound.
    /// @param account The address `name` was bound to.
    event Register(bytes32 indexed name, address indexed account);

    /// Binds `name` to `account`, replacing any address it is already bound to.
    ///
    /// The implementation MUST revert `NotRoot` unless the caller is the root
    /// authority, and MUST revert `ZeroAccount` if `account` is the zero
    /// address. It MUST revert `TimestampNotAfterBinding` when re-binding a name
    /// whose stored moment the clock is not strictly after, so a name's moment
    /// is strictly increasing however the chain's clock behaves and a re-bind in
    /// the same block as the bind it replaces is refused. On success it MUST
    /// emit `Register` and MUST record `block.timestamp` as the binding's
    /// moment, in place of any moment it already carries — including when
    /// `account` is the address `name` already holds, which is a bind like any
    /// other. The moment dates the write, not the value, so it can only make an
    /// answer look fresher than the address really is; a caller refusing fresh
    /// answers therefore errs toward refusing rather than toward accepting one
    /// it meant to refuse.
    /// @param name The name to bind.
    /// @param account The address to bind it to.
    function register(bytes32 name, address account) external;

    /// The address `name` is currently bound to, and when it was bound.
    ///
    /// The implementation MUST revert `NameNotRegistered` when `name` is
    /// unbound, rather than returning zeros, so that no caller has to remember
    /// to check — a zero moment would read as an age of the whole of time, which
    /// is the one age that passes every freshness test. It MUST NOT expose any
    /// other reader that returns the zero address for an unbound name, as that
    /// reintroduces exactly the mistake this reverting read exists to prevent.
    ///
    /// An implementation that stores the moment narrower than `block.timestamp`
    /// MUST reject a timestamp that does not fit rather than truncate it. A
    /// truncated moment is a smaller number, which reads as an older binding,
    /// which passes exactly the check a caller reads it to fail.
    ///
    /// A caller that needs an answer that cannot move MUST read once and store
    /// the result, which is what a consumer resolving a name in its constructor
    /// does. Reading at the point of use instead means reading whatever root
    /// has bound most recently.
    /// @param name The name to read.
    /// @return The address bound to `name`. Never the zero address.
    /// @return The `block.timestamp` of the most recent `register` for `name`.
    /// Zero only on a chain whose block time is itself zero, which is why an
    /// unbound name is a revert and not a zero: nothing else separates the two.
    function get(bytes32 name) external view returns (address, uint256);
}
