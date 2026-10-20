// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @title IConfigRegistryV1
/// @notice A registry of `bytes32` names to ABI-encoded values, keyed by the
/// authority that bound them, with exactly two operations: any account binds a
/// name under its own address (`registerV1`), and anyone reads a name under an
/// authority it names (`getV1`). An authority may re-bind a name it has already
/// bound. There is no removal, no upgrade, and no way for one account to write
/// under another, and an implementation MUST NOT add any.
///
/// Deploy-time configuration compiled into creation code — an address, a role
/// id, a threshold, a delay, a list of accounts, a code hash — moves the
/// deterministic address whenever it changes. This binds a name to `bytes`,
/// which the registry holds and returns verbatim. What they encode is agreed
/// between the authority that binds the name and whoever reads it: an address
/// binding is `abi.encode(account)`, and its reader decodes it with
/// `abi.decode(value, (address))`. The registry never decodes a value and an
/// implementation MUST NOT constrain one beyond refusing it empty.
///
/// Names are opaque 32-byte values. This interface says nothing about how a
/// name is derived — hashed from a string, a raw ASCII literal, a counter — and
/// an implementation MUST NOT constrain it. Two callers agreeing on a name is
/// entirely their business.
///
/// ## The authority is the whole access control
///
/// A binding is keyed by the account that wrote it, and only that account
/// writes under its address. Anyone may bind, but only for themselves, so a
/// reader that reads the names of an authority it already trusts is reading
/// something only that authority could have written. Bindings under any other
/// authority are unforgeable garbage no reader asks for, and one name under two
/// authorities is two unrelated bindings.
///
/// This is deliberately not a root. A root welded into creation code is one
/// authority for every consumer, so every consumer trusts whoever holds it, and
/// giving each consumer its own root gives each a different registry address.
/// Keyed by authority, the implementation is identical for every consumer and
/// lives at one deterministic address on every chain, and the authority a
/// consumer trusts sits in that consumer's creation code beside the name it
/// resolves.
///
/// There are no delegates. A binding is a standalone write with nothing that
/// has to land atomically beside it, so the authority can always make it
/// itself, and an authority whose operators rotate is an account whose address
/// survives the rotation — a Safe, a timelock — not a key that hands its
/// authority on. Every approved account would be one more key whose compromise
/// rebinds the authority's names.
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
/// A compromised authority therefore cannot touch anything deployed, nor any
/// other authority's bindings. It can point one of its own names at a value it
/// chose, so that a deployment made after the compromise snapshots that value.
/// That is caught by verifying a deployment after deploying it and before
/// anything depends on it: the deployed contract has already snapshotted the
/// value, so checking it is checking settled state. A poisoned deploy is a
/// burned deterministic address, discovered before use.
/// `LibRainDeploy.checkResolvedValues` is that check for a value of any type,
/// compared as the exact bytes the deployment answers.
///
/// `getV1` also answers with the moment a binding was made, because a value alone
/// cannot say that it has just moved. The registry reports the moment and
/// imposes nothing on it: a fresh binding is live at once, and an
/// implementation MUST NOT withhold one. What counts as too fresh belongs to
/// the caller.
interface IConfigRegistryV1 {
    /// Thrown when `registerV1` is called with an empty value. Empty is how an
    /// unbound name reads, so binding it would produce a name that is both
    /// bound and unreadable. A name cannot be unbound once bound; the closest
    /// thing is binding it to something deliberately inert.
    /// @param name The name that was being bound to an empty value.
    error EmptyValue(bytes32 name);

    /// Thrown by `getV1` when `authority` has never bound `name`, so that a
    /// caller cannot silently proceed on an empty value by forgetting to check.
    /// The zero authority is one of these for every name: nothing calls from
    /// it, so nothing is ever bound under it.
    /// @param authority The authority the name was read under.
    /// @param name The name that is not bound under it.
    error NameNotRegistered(address authority, bytes32 name);

    /// Thrown by `registerV1` when the clock is not strictly after the moment the
    /// name already carries under the caller.
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
    /// @param registeredAt The moment the name carries under the caller. Zero
    /// when unbound.
    error TimestampNotAfterBinding(bytes32 name, uint256 timestamp, uint256 registeredAt);

    /// Emitted every time `sender` binds `name`, including when it re-binds it.
    /// The log is the complete history of the registry and the only way to
    /// discover a binding without already knowing its authority and name; the
    /// most recent `Register` from an authority for a name is that authority's
    /// current binding of it.
    ///
    /// `value` is not indexed, because an indexed `bytes` is logged as its hash
    /// and the history would then not hold the values.
    ///
    /// The moment is not a field here, because a log already carries the block
    /// it was emitted in.
    /// @param sender The account that called, which is the authority `name` is
    /// bound under.
    /// @param name The name that was bound.
    /// @param value The value `name` was bound to.
    event Register(address indexed sender, bytes32 indexed name, bytes value);

    /// Binds `name` to `value` under the caller, replacing any value the caller
    /// has already bound it to. No other authority's binding is read or
    /// touched.
    ///
    /// The implementation MUST revert `EmptyValue` if `value` is empty, and
    /// MUST revert `TimestampNotAfterBinding` unless the clock is strictly
    /// after the moment the name carries under the caller, so a binding's
    /// moment strictly increases. On success it MUST emit `Register` and record
    /// `block.timestamp` as the moment — including when `value` is the value
    /// already bound, which is a bind like any other. The moment dates the
    /// write, not the value.
    /// An implementation storing the moment narrower than `block.timestamp`
    /// MUST revert on a clock that does not fit rather than truncate it, since a
    /// truncated moment reads as older.
    /// @param name The name to bind.
    /// @param value The ABI-encoded value to bind it to.
    function registerV1(bytes32 name, bytes calldata value) external;

    /// The value `authority` currently binds `name` to, and when it bound it.
    ///
    /// The implementation MUST revert `NameNotRegistered` when `authority` has
    /// not bound `name`, rather than returning an empty value, so that no
    /// caller has to remember to check. It MUST NOT expose any other reader
    /// that returns an empty value for an unbound name, as that reintroduces
    /// exactly the mistake this reverting read exists to prevent.
    ///
    /// Answers with the current binding: whatever `authority` has bound most
    /// recently, and the moment it was bound. A caller that stores the result
    /// keeps that value; one that reads again gets whatever is current then.
    /// @param authority The account whose binding to read.
    /// @param name The name to read.
    /// @return The value bound to `name` under `authority`, byte for byte as it
    /// was bound. Never empty.
    /// @return The `block.timestamp` of `authority`'s most recent `registerV1`
    /// for `name`. Never zero.
    function getV1(address authority, bytes32 name) external view returns (bytes memory, uint256);
}
