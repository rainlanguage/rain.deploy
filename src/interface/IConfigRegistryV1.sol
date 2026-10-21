// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {IRegistryDelegatesV1} from "./IRegistryDelegatesV1.sol";

/// @title IConfigRegistryV1
/// @notice A registry of `bytes32` names to ABI-encoded values, keyed by the
/// authority that bound them. A write names the authority it binds under, and
/// that authority, or an account it has approved, binds a name there
/// (`registerV1`); anyone reads a name under an authority it names (`getV1`).
/// An authority may re-bind a name it has already bound. An authority approves
/// and revokes delegates (`approveV1`, `revokeV1`), and anyone reads an
/// approval (`approvedV1`). There is no removal, no upgrade, and no way for
/// one account to write under another that has not approved it, and an
/// implementation MUST NOT add any.
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
/// ## The authority and its delegates are the whole access control
///
/// A binding is keyed by its authority, and only the authority, or an account
/// it has approved, writes under its address. Anyone may bind, but only under
/// their own address or one whose authority approved them, so a reader that
/// reads the names of an authority it already trusts is reading something only
/// that authority, or an account it chose, could have written. Bindings under
/// any other authority are unforgeable garbage no reader asks for, and one name
/// under two authorities is two unrelated bindings.
///
/// This is deliberately not a root. A root welded into creation code is one
/// authority for every consumer, so every consumer trusts whoever holds it, and
/// giving each consumer its own root gives each a different registry address.
/// Keyed by authority, the implementation is identical for every consumer and
/// lives at one deterministic address on every chain, and the authority a
/// consumer trusts sits in that consumer's creation code beside the name it
/// resolves.
///
/// ## Delegation is per authority and name
///
/// Only the authority decides who writes under it. An approval names one
/// delegate for one name under the approving authority: it covers no other
/// name, and approving a delegate under one authority never lets it write
/// under another.
///
/// This decouples an authority from whichever account sends its binds. A Safe
/// or timelock authority approves a hardware-wallet key, which then binds under
/// the Safe without the Safe executing each bind.
///
/// The authority can always write under itself, approved or not. Revoking
/// stops later writes and nothing else: a binding a delegate wrote while
/// approved stays until it is re-bound, as every binding does. Every delegate
/// is one more key whose compromise rebinds the name it was approved for, so
/// a name is only as trustworthy as every delegate it has ever had, revoked
/// ones included; `Register` names the account that
/// wrote each binding. Approve only accounts held to the authority's own
/// custody, and revoke before rotating one out. Approvals cannot be enumerated
/// here, only asked about one delegate at a time, so a consumer's prod tests
/// assert `approvedV1` is false for every retired delegate beside the true
/// answers for the live ones. Approvals are per-chain state, like a contract
/// authority's controllers: an approval or revocation is made on every chain
/// the authority's names are consumed on.
///
/// A consumer resolves under one authority address on every chain, so it
/// trusts whoever controls that address on each of them. An EOA is one key on
/// every chain; a contract authority is not. Its controllers are per-chain
/// state, so a rotation of a Safe's owners or threshold, or of a timelock's
/// roles, is done on every chain its names are consumed on and verified on
/// each; a chain left out is still controlled by the old controllers, who can
/// rebind every name there. Where it is not yet deployed, its address is
/// claimable by whoever deploys there first if the deployment path does not
/// commit to its controllers — a CREATE-nonce deployment, or a factory that
/// does not bind the initializer or is missing on that chain. A Zoltu timelock
/// or a SafeProxyFactory CREATE2 Safe commits to its init, but that init names
/// the original controllers, so replaying it on a chain after a rotation seats
/// the controllers the rotation removed. A contract authority is deployed on
/// every chain before any rotation, then rotated on each.
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
/// A compromised authority or delegate therefore cannot touch anything
/// deployed, nor any other authority's bindings. It can point one of its own
/// names at a value it chose, so that a deployment made after the compromise
/// snapshots that value.
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
interface IConfigRegistryV1 is IRegistryDelegatesV1 {
    /// Thrown when `registerV1` is called with an empty value. Empty is how an
    /// unbound name reads, so binding it would produce a name that is both
    /// bound and unreadable. A name cannot be unbound once bound; the closest
    /// thing is binding it to something deliberately inert.
    /// @param name The name that was being bound to an empty value.
    error EmptyValue(bytes32 name);

    /// Thrown by `getV1` when `authority` has never bound `name`, so that a
    /// caller cannot silently proceed on an empty value by forgetting to check.
    /// The zero authority is one of these for every name: nothing calls from
    /// it, so it neither binds nor approves, and nothing is ever bound under
    /// it.
    /// @param authority The authority the name was read under.
    /// @param name The name that is not bound under it.
    error NameNotRegistered(address authority, bytes32 name);

    /// Thrown by `registerV1` when the clock is not strictly after the moment the
    /// name already carries under the authority.
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
    /// @param registeredAt The moment the name carries under the authority.
    /// Zero when unbound.
    error TimestampNotAfterBinding(bytes32 name, uint256 timestamp, uint256 registeredAt);

    /// Emitted every time `sender` binds `name` under `authority`, including
    /// when it re-binds it. The log is the complete history of the registry
    /// and the only way to discover a binding without already knowing its
    /// authority and name; the most recent `Register` under an authority for a
    /// name is that authority's current binding of it.
    ///
    /// `value` is not indexed, because an indexed `bytes` is logged as its hash
    /// and the history would then not hold the values.
    ///
    /// The moment is not a field here, because a log already carries the block
    /// it was emitted in.
    /// @param sender The account that called: `authority` or a delegate it
    /// approved.
    /// @param authority The authority `name` is bound under.
    /// @param name The name that was bound.
    /// @param value The value `name` was bound to.
    event Register(address indexed sender, address indexed authority, bytes32 indexed name, bytes value);

    /// Binds `name` to `value` under `authority`, replacing any value
    /// `authority` has already bound it to. The caller is `authority` or a
    /// delegate it has approved for `name`. No other authority's binding is read or
    /// touched.
    ///
    /// The implementation MUST first revert `NotApproved` unless the caller is
    /// `authority` or approved by it for `name`. Then it MUST revert `EmptyValue` if
    /// `value` is empty, and MUST revert `TimestampNotAfterBinding` unless the
    /// clock is strictly after the moment the name carries under `authority`,
    /// so a binding's moment strictly increases. On success it MUST emit
    /// `Register` and record
    /// `block.timestamp` as the moment — including when `value` is the value
    /// already bound, which is a bind like any other. The moment dates the
    /// write, not the value.
    /// An implementation storing the moment narrower than `block.timestamp`
    /// MUST revert on a clock that does not fit rather than truncate it, since a
    /// truncated moment reads as older.
    /// @param authority The authority to bind under: the caller, or one that
    /// approved it for `name`.
    /// @param name The name to bind.
    /// @param value The ABI-encoded value to bind it to.
    function registerV1(address authority, bytes32 name, bytes calldata value) external;

    /// Approves `delegate` to bind `name` under the caller and emits
    /// `Approved`. Approving an approved delegate leaves it approved and still
    /// emits. Refuses `ZeroDelegate`.
    /// @param name The name the approval covers.
    /// @param delegate The account to approve. MUST NOT be zero.
    function approveV1(bytes32 name, address delegate) external;

    /// Revokes `delegate`'s approval to bind `name` under the caller and emits
    /// `Revoked`. Revoking an unapproved delegate leaves it unapproved and
    /// still emits. Refuses `ZeroDelegate`.
    /// @param name The name the revocation covers.
    /// @param delegate The account to revoke. MUST NOT be zero.
    function revokeV1(bytes32 name, address delegate) external;

    /// Whether `authority` has approved `delegate` to bind `name` under it. Refuses
    /// `ZeroDelegate` rather than answering false about a question the caller
    /// did not mean to ask. The zero authority answers false for every
    /// delegate, as it answers `NameNotRegistered` for every name.
    /// @param authority The approving authority.
    /// @param name The name asked about.
    /// @param delegate The account asked about.
    /// @return True when approved.
    function approvedV1(address authority, bytes32 name, address delegate) external view returns (bool);

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
    /// @return The `block.timestamp` of the most recent `registerV1` of `name`
    /// under `authority`. Never zero.
    function getV1(address authority, bytes32 name) external view returns (bytes memory, uint256);
}
