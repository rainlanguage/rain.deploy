// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {IAddressRegistryV2} from "../interface/IAddressRegistryV2.sol";
import {ADDRESS_REGISTRY_ROOT} from "./AddressRegistry.sol";

/// @dev One name's binding: the address it is bound to and the moment that
/// address became what it is. Written in one call, so a binding can never hold
/// one half of itself.
///
/// `account` is 160 bits and `changedAt` is 96, so the pair is exactly one
/// storage slot: one `SSTORE` on a rebind and one `SLOAD` on every read, where
/// two mappings would cost two of each. A reader pays that cost on every
/// resolve, which is the whole point of recording the timestamp.
///
/// 96 bits of seconds runs out around 2.5e21 years from now, so narrowing
/// `block.timestamp` to fit cannot truncate on any chain that exists. The
/// width is chosen to fill the slot rather than to bound the value: there is
/// nothing left over to find a use for, and nothing to overflow.
struct AddressBinding {
    /// The address the name is bound to. The zero address if and only if the
    /// name is unbound, which is why `register` rejects the zero address.
    address account;
    /// The moment `account` became the address the name is bound to. Not the
    /// moment `register` was last called for the name.
    uint96 changedAt;
}

/// @title AddressRegistryV2
/// @notice The whole of `IAddressRegistryV2`: an immutable root authority binds
/// a `bytes32` name, anyone reads a bound name together with the moment its
/// address last changed, and a read of an unbound name reverts.
///
/// There is deliberately nothing else. No removal, no upgrade, no pause, and no
/// authority besides root — root is a compile-time constant, so it cannot even
/// hand itself over. In particular there is no delay and no pending binding: a
/// `register` takes effect in the block it lands in, and the recorded timestamp
/// is what lets a reader decide for itself whether that is too recent to trust.
/// Deciding it here would be picking one window for every consumer.
///
/// This is a SEPARATE contract from `AddressRegistry` rather than a change to
/// it. `IAddressRegistryV1` rules out changing that contract's shape — "There
/// is no removal, no upgrade and no authority beyond root, and an
/// implementation MUST NOT add any" — and storing a timestamp plus returning it
/// is a shape change. So the V1 registry stays exactly where it is, at the
/// deterministic address its own creation code derives, with the bindings it
/// already holds; this is a new contract with its own creation code and
/// therefore its own address. Bindings do not carry between them, the same way
/// they did not carry when the V1 address itself moved.
///
/// The root authority is the SAME account, imported from `AddressRegistry` so
/// it is spelled once. It is one organisation's root, not one contract's, so
/// rotating it is one edit that moves the deterministic address of both
/// registries together — which is what a second spelling here would quietly
/// make untrue.
///
/// The storage mapping is `internal` rather than `public`: a public mapping's
/// generated getter answers an unbound name with a zero-filled binding, which
/// is exactly the silent failure `get` reverts to prevent.
contract AddressRegistryV2 is IAddressRegistryV2 {
    /// The bindings. Not `public`: the only reader is `get`, which reverts on
    /// an unbound name. A name maps to a binding whose `account` is the zero
    /// address if and only if it is unbound, which is why `register` rejects
    /// the zero address.
    mapping(bytes32 name => AddressBinding binding) internal sBindings;

    /// @inheritdoc IAddressRegistryV2
    /// @dev The timestamp moves only when the bound address does, so root
    /// re-binding a name to the address it already holds is a no-op on storage
    /// rather than a write that makes an untouched binding look fresh. The
    /// comparison is against the stored address, so the only call it skips is
    /// one that would have stored the value already there.
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
        AddressBinding memory binding = sBindings[name];
        if (binding.account != account) {
            binding.account = account;
            // Cannot truncate: see `AddressBinding`.
            binding.changedAt = uint96(block.timestamp);
            sBindings[name] = binding;
        }
        // The binding as it stands after the call, which on a no-op rebind is
        // the timestamp that was already there.
        emit Register(name, account, binding.changedAt);
    }

    /// @inheritdoc IAddressRegistryV2
    /// @dev Returns whatever root has bound most recently, and when that
    /// binding became what it is. A caller that needs an answer that cannot
    /// move reads once and stores it, which is what a consumer resolving a name
    /// in its constructor does; the timestamp is what a caller reading at any
    /// other moment can hold against its own idea of too recent.
    ///
    /// Boundness is tested on the address and never on the timestamp, so a
    /// chain whose `block.timestamp` is somehow zero at the moment of a bind
    /// still has a bound name rather than one that reads as never bound.
    function get(bytes32 name) external view returns (address, uint256) {
        AddressBinding memory binding = sBindings[name];
        if (binding.account == address(0)) {
            revert NameNotRegistered(name);
        }
        return (binding.account, binding.changedAt);
    }
}
