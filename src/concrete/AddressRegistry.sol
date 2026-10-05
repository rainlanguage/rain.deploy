// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {IAddressRegistryV1} from "../interface/IAddressRegistryV1.sol";

/// @dev The only account that may bind a name. A compile-time constant rather
/// than storage, so it can never be rotated, and part of the creation code, so
/// changing it changes the deterministic deploy address and code hash of
/// `AddressRegistry` on every network.
///
/// Rotating it is an ordinary source change that moves the creation code, and
/// therefore the deploy address, the code hash, the snapshot `script/Build.sol`
/// generates and the release that carries them.
address constant ADDRESS_REGISTRY_ROOT = 0x0b300013CD54a8F1aC40981f80FaaA18b8Cc1E4c;

/// @title AddressRegistry
/// @notice The whole of `IAddressRegistryV1`: an immutable root authority binds
/// a `bytes32` name, anyone reads a bound name and gets back the address with
/// the moment it was bound, and a read of an unbound name reverts.
///
/// There is deliberately nothing else. No removal, no upgrade, no pause, and no
/// authority besides root — root is a compile-time constant, so it cannot even
/// hand itself over.
///
/// A binding is mutable because the address it names is. Rotating an owning
/// multisig is ordinary business and has to be expressible without moving
/// anybody's deterministic address, which a binding welded to one address
/// forever would make impossible: the name is in the consumer's creation code,
/// so a new name means new creation code and a new address.
///
/// Mutability costs nothing already deployed. A consumer resolves a name once,
/// in its constructor, and never reads the registry again, so re-binding a name
/// changes what the next deployment resolves and nothing else — a rotation is a
/// deliberate migration, never a silent change to live contracts.
///
/// The moment is reported and nothing more. A fresh binding is live
/// immediately and this contract holds nothing pending; a caller that wants to
/// refuse an answer bound moments ago has what it needs to refuse it itself.
///
/// A name's moment is non-decreasing. `register` refuses a bind whose clock is
/// behind the moment the name already carries, so the age a caller derives from
/// it can never overstate the time that has passed — which is the only reason
/// the moment is worth reading.
///
/// The storage mapping is `internal` rather than `public`: a public mapping's
/// generated getter answers an unbound name with a zero binding, which is
/// exactly the silent failure `get` reverts to prevent.
contract AddressRegistry is IAddressRegistryV1 {
    /// Thrown when `block.timestamp` does not fit the binding's moment, instead
    /// of narrowing it to something that fits.
    ///
    /// Unreachable on any chain whose block time is a plausible wall clock, and
    /// kept because the alternative is not an error that never fires but a
    /// truncation that fires silently and in the unsafe direction.
    /// @param timestamp The `block.timestamp` that did not fit.
    error TimestampOverflow(uint256 timestamp);

    /// @dev One binding: the address a name is bound to, and when it was bound.
    ///
    /// A struct because these are mapping values, which is where packing needs
    /// one. The two share a word, so `get` reads both out of one slot and
    /// `register` cannot write one without the other. 96 bits is what is left
    /// beside a 160-bit address, and far wider than a block timestamp needs —
    /// `2**96` seconds is some 2.5e21 years — but `register` checks rather than
    /// assumes it, because a truncated moment reads as an older binding.
    ///
    /// Declared inside the contract rather than at file scope because it is
    /// this contract's storage layout and no part of anybody's ABI: `get`
    /// returns two flat values. A file-scope struct would be importable, which
    /// would invite a consumer to depend on the layout.
    struct Binding {
        /// The address the name is bound to. Zero if and only if the name is
        /// unbound, which is what `register` rejecting the zero address
        /// preserves.
        address account;
        /// The `block.timestamp` of the most recent `register` for the name.
        uint96 registeredAt;
    }

    /// The bindings. Not `public`: the only reader is `get`, which reverts on an
    /// unbound name. A name's `account` is the zero address if and only if it is
    /// unbound, which is why `register` rejects the zero address, and why
    /// bound-ness is never decided from the moment — the moment of a bound name
    /// is legitimately zero on a chain at block time zero.
    mapping(bytes32 name => Binding binding) internal sBindings;

    /// @inheritdoc IAddressRegistryV1
    function register(bytes32 name, address account) external {
        if (msg.sender != ADDRESS_REGISTRY_ROOT) {
            revert NotRoot(msg.sender);
        }
        // Rejected so that a name can never be both bound and unreadable. There
        // is deliberately no way to unbind a name; the nearest thing is
        // re-binding it to something inert.
        if (account == address(0)) {
            revert ZeroAccount(name);
        }
        // The hazard behind a `block.timestamp` comparison — a validator
        // nudging the clock to land on the side of it that suits them — does
        // not reach this one. It compares the clock against the WIDTH of the
        // moment, not against any moment: the seconds of slack a validator has
        // cannot move a plausible timestamp past 2**96.
        //
        // Slither's is a start/end pair rather than a next-line because only
        // one comment fits immediately above the `if` and that one has to be
        // forge-lint's, which has no pair form.
        // slither-disable-start timestamp
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp > type(uint96).max) {
            revert TimestampOverflow(block.timestamp);
        }
        // slither-disable-end timestamp
        // A name's moment never goes backwards, whatever the chain's clock
        // does. Without this a clock that regressed would let a re-bind write a
        // SMALLER moment than the binding it replaces, and a caller measuring
        // `block.timestamp -` that moment would get an age larger than the time
        // that actually passed — so a re-bind from moments ago could report as
        // long-settled. An unbound name carries a moment of zero, which no
        // clock is below, so the first bind of a name is never affected.
        //
        // This does NOT make the clock trustworthy at read time: it can still
        // regress between a bind and a read, which is what
        // `LibAddressRegistry.resolveSafe` reports as `BindingStampedInFuture`.
        // The two guards cover different moments and neither subsumes the other.
        // slither-disable-start timestamp
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp < sBindings[name].registeredAt) {
            revert TimestampBeforeBinding(name, block.timestamp, sBindings[name].registeredAt);
        }
        // slither-disable-end timestamp
        // Assigned whole, so a re-bind replaces the moment in the same write
        // that replaces the address.
        sBindings[name] = Binding({account: account, registeredAt: uint96(block.timestamp)});
        emit Register(name, account);
    }

    /// @inheritdoc IAddressRegistryV1
    /// @dev Returns whatever root has bound most recently. A caller that needs
    /// an answer that cannot move reads once and stores it, which is what a
    /// consumer resolving a name in its constructor does.
    ///
    /// Bound-ness is read off `account`, never off the moment, so a binding
    /// made on a chain at block time zero is answered rather than mistaken for
    /// a name nobody bound.
    function get(bytes32 name) external view returns (address, uint256) {
        Binding memory binding = sBindings[name];
        // There is no time in this comparison. Slither reaches it because
        // `account` shares a struct with a value written from `block.timestamp`,
        // so the whole binding is tainted and an address check against zero is
        // reported as a dangerous timestamp comparison.
        // slither-disable-start timestamp
        if (binding.account == address(0)) {
            revert NameNotRegistered(name);
        }
        // slither-disable-end timestamp
        return (binding.account, binding.registeredAt);
    }
}
