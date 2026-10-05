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

/// @dev One binding: the address a name is bound to, and when it was bound.
///
/// Both halves are written by the only function that writes either, and they
/// share a word so that they cannot be written apart. A stamp that could lag
/// its address would be worse than no stamp at all, because a stale answer
/// would read as a fresh one.
///
/// 96 bits is what is left of the word beside a 160-bit address, and is far
/// wider than a block timestamp needs: `2**96` seconds is some 2.5e21 years.
/// `AddressRegistry.register` checks the width anyway rather than assuming it —
/// `IAddressRegistryV1.registeredAt` says why a narrowed stamp is the dangerous
/// direction to be wrong in.
struct Binding {
    /// The address the name is bound to. Zero if and only if the name is
    /// unbound, which is what `register` rejecting the zero address preserves.
    address account;
    /// The `block.timestamp` of the most recent `register` for the name.
    uint96 registeredAt;
}

/// @title AddressRegistry
/// @notice The whole of `IAddressRegistryV1`: an immutable root authority binds
/// a `bytes32` name, anyone reads a bound name, anyone reads when it was most
/// recently bound, and a read of an unbound name reverts.
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
/// The stamp is the one thing a resolving consumer could not previously see:
/// how old the answer is. It is reported and nothing more. A fresh binding is
/// live immediately, and this contract holds nothing pending — a consumer that
/// wants to refuse an answer bound moments ago reads the stamp and refuses it
/// itself, because only the consumer knows what it is resolving the name for.
///
/// The storage mapping is `internal` rather than `public`: a public mapping's
/// generated getter answers an unbound name with the zero address, which is
/// exactly the silent failure `get` reverts to prevent.
contract AddressRegistry is IAddressRegistryV1 {
    /// Thrown when `block.timestamp` does not fit the stamp, instead of
    /// narrowing it to something that fits.
    ///
    /// Unreachable on any chain whose block time is a plausible wall clock, and
    /// kept because the alternative is not an error that never fires but a
    /// truncation that fires silently and in the unsafe direction. A chain, or a
    /// test, that reports a timestamp this large gets a refused bind rather than
    /// a binding that reads as 2.5e21 years old.
    /// @param timestamp The `block.timestamp` that did not fit.
    error TimestampOverflow(uint256 timestamp);

    /// The bindings. Not `public`: the only readers are `get` and
    /// `registeredAt`, which both revert on an unbound name. A name's `account`
    /// is the zero address if and only if it is unbound, which is why `register`
    /// rejects the zero address, and why the stamp is never what either reader
    /// consults to decide whether a name is bound — the stamp of a bound name is
    /// legitimately zero on a chain at block time zero.
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
        if (block.timestamp > type(uint96).max) {
            revert TimestampOverflow(block.timestamp);
        }
        // Assigned whole, so the stamp of a re-bind replaces the stamp of the
        // bind before it in the same write that replaces the address.
        sBindings[name] = Binding({account: account, registeredAt: uint96(block.timestamp)});
        emit Register(name, account);
    }

    /// @inheritdoc IAddressRegistryV1
    /// @dev Returns whatever root has bound most recently. A caller that needs
    /// an answer that cannot move reads once and stores it, which is what a
    /// consumer resolving a name in its constructor does.
    function get(bytes32 name) external view returns (address) {
        address account = sBindings[name].account;
        if (account == address(0)) {
            revert NameNotRegistered(name);
        }
        return account;
    }

    /// @inheritdoc IAddressRegistryV1
    /// @dev Bound-ness is read off `account`, never off the stamp, so a binding
    /// made on a chain at block time zero is answered with zero rather than
    /// mistaken for a name nobody bound.
    function registeredAt(bytes32 name) external view returns (uint256) {
        Binding memory binding = sBindings[name];
        if (binding.account == address(0)) {
            revert NameNotRegistered(name);
        }
        return binding.registeredAt;
    }
}
