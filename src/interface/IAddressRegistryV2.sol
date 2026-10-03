// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @title IAddressRegistryV2
/// @notice `IAddressRegistryV1` with provenance: an immutable root authority
/// binds a `bytes32` name (`register`), and anyone reads a bound name together
/// with the moment its address last changed (`get`). Root may re-bind a name it
/// has already bound. There is no removal, no upgrade and no authority beyond
/// root, and an implementation MUST NOT add any.
///
/// Everything `IAddressRegistryV1` says about names and about mutability holds
/// here unchanged. Names are opaque 32-byte values and an implementation MUST
/// NOT constrain how one is derived. Bindings are mutable because the addresses
/// they name are: rotating an owning multisig is ordinary business, and a
/// binding welded to one address forever would force a new name — and therefore
/// new creation code and a new deterministic address — for a routine rotation.
/// A binding moving never moves anything already deployed, because a consumer
/// resolves a name once, at construction, and stores the answer.
///
/// ## What is new, and what it is for
///
/// `IAddressRegistryV1`'s threat model turns on a compromised root being caught
/// by verifying a deployment after deploying it: the deployed contract has
/// already snapshotted the value, so a poisoned deploy is a burned
/// deterministic address, discovered before use.
///
/// That containment rests on the read happening at a moment someone is
/// watching. It does not hold for a read at an arbitrary later moment — a
/// consumer reconciling an EXISTING proxy after a beacon upgrade reads months
/// or years after its implementation was audited, and nothing new is deployed,
/// so there is no burned address to notice. A root compromise can therefore sit
/// dormant on the honest address and be switched immediately before such an
/// upgrade, converting to live capture at a moment the victim chose.
///
/// So a binding carries the moment it last moved, and `get` answers with it. A
/// reader that cares can see that the address it is about to trust changed a
/// minute ago rather than a year ago.
///
/// ## The registry does not decide what "too recent" means
///
/// Nothing is withheld and nothing is pending. `register` takes effect in the
/// block it lands in, exactly as in `IAddressRegistryV1`, and additionally
/// records when the bound address changed. There is no delay, no pending
/// binding, no cancellation and no window — an implementation MUST NOT add any.
///
/// The window a reader considers unsafe is the reader's own number, and
/// different readers can choose differently without the registry having an
/// opinion. A registry that enforced one window would have to pick it for
/// everybody, and would be answering a policy question with storage. The
/// registry stays a record with provenance; policy sits with the reader.
///
/// ## `changedAt` is about the address, not about the call
///
/// `changedAt` is the moment the bound address became what it now is, which is
/// not the same as the moment root last called `register`. Root re-binding a
/// name to the address it already holds changes nothing, so it MUST leave
/// `changedAt` where it is: a reader asking "has this moved recently?" would
/// otherwise be told yes by a call that moved nothing, and root could make an
/// untouched binding look fresh without touching it.
///
/// Nothing is hidden by that rule. It skips the update only when the stored
/// address already equals the one being bound, so any sequence that leaves the
/// name on a different address than it held updates `changedAt`.
///
/// ## Boundness is still the address, never the timestamp
///
/// `get` reverts on an unbound name rather than answering, so there is no zero
/// timestamp for a caller to interpret and no reader has to remember to check
/// one. An implementation MUST keep the nonzero address as the only thing that
/// distinguishes a bound name from an unbound one; a timestamp is a fact about
/// a binding that exists, never the test for whether it exists.
///
/// ## Mixing the two ABIs up is silent in one direction only
///
/// A function selector does not include return types, so `get(bytes32)` here
/// has the same selector as `IAddressRegistryV1.get`. What separates the two is
/// the returndata: 64 bytes here against V1's 32. The decoder takes what it
/// needs from the front and ignores the rest, which makes the two directions
/// asymmetric.
///
/// A V1 ABI reading a V2 registry SUCCEEDS, with the right address and the
/// timestamp silently dropped. A V2 ABI reading a V1 registry REVERTS, because
/// 32 bytes cannot fill the pair and nothing is invented to complete it. So the
/// only quiet mistake is the one that discards what this version adds, and it
/// is quiet at the ABI layer — which is why a reader pins a code hash alongside
/// an address rather than an address alone.
///
/// The event is unambiguous in both directions:
/// `Register(bytes32,address,uint256)` hashes to a different topic than
/// `Register(bytes32,address)`, so an indexer filtering on the V1 topic sees
/// nothing here rather than seeing it wrongly.
interface IAddressRegistryV2 {
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

    /// Emitted on every successful `register`, including one that binds a name
    /// to the address it already holds. The log is the complete history of the
    /// registry and the only way to discover a binding without already knowing
    /// the name; the most recent `Register` for a name carries its current
    /// binding whole.
    ///
    /// `changedAt` is the binding's as it stands AFTER the call, so a call that
    /// re-bound a name to the address it already held carries the older
    /// timestamp it left in place. That is what makes the log readable on its
    /// own: an entry whose `changedAt` predates its own block is a call that
    /// moved nothing, and one whose `changedAt` is its own block moved the
    /// address.
    /// @param name The name that was bound.
    /// @param account The address `name` is bound to after the call.
    /// @param changedAt The moment `account` became what `name` is bound to.
    event Register(bytes32 indexed name, address indexed account, uint256 changedAt);

    /// Binds `name` to `account`, replacing any address it is already bound to,
    /// effective in the block the call lands in.
    ///
    /// The implementation MUST revert `NotRoot` unless the caller is the root
    /// authority, and MUST revert `ZeroAccount` if `account` is the zero
    /// address. On success it MUST emit `Register`.
    ///
    /// It MUST record the current block timestamp against `name` when `account`
    /// differs from the address `name` is bound to, including the first binding
    /// of a name, and MUST leave the recorded timestamp alone when it does not.
    /// @param name The name to bind.
    /// @param account The address to bind it to.
    function register(bytes32 name, address account) external;

    /// The address `name` is currently bound to, and the moment it became that
    /// address.
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
    /// has bound most recently — which is what `changedAt` is here to make
    /// visible rather than to prevent.
    /// @param name The name to read.
    /// @return account The address bound to `name`. Never the zero address.
    /// @return changedAt The moment `account` became the address `name` is
    /// bound to. Not the moment `register` was last called for `name`: a
    /// re-bind to the address already held leaves this where it was.
    function get(bytes32 name) external view returns (address account, uint256 changedAt);
}
