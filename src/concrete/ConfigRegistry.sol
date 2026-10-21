// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {IConfigRegistryV2} from "../interface/IConfigRegistryV2.sol";
import {RegistryDelegates} from "../abstract/RegistryDelegates.sol";

/// @title ConfigRegistry
/// @notice The whole of `IConfigRegistryV2`: any account binds a `bytes32` name
/// to an ABI-encoded value under its own address or under an authority that
/// approved it, anyone reads a name under an authority it names and gets back
/// the value with the moment it was bound, and a read of an unbound name
/// reverts.
///
/// There is deliberately nothing else. No removal, no upgrade, no pause, and
/// no account that writes under another that has not approved it. The value is held and
/// returned verbatim and never decoded; its type is between the authority that
/// binds the name and whoever reads it.
///
/// Nothing is configured into the creation code, so this is one contract at
/// one deterministic address on every network for every authority.
///
/// A binding is mutable because the configuration it names is. Rotating an
/// owning multisig is ordinary business and has to be expressible without
/// moving anybody's deterministic address, which a binding welded to one value
/// forever would make impossible: the name is in the consumer's creation code,
/// so a new name means new creation code and a new address.
///
/// Mutability costs nothing already deployed. A consumer resolves a name once,
/// in its constructor, and never reads the registry again, so re-binding a name
/// changes what the next deployment resolves and nothing else.
///
/// The moment is reported and nothing more; this contract holds nothing
/// pending. A binding's moment strictly increases, so an age derived from it
/// never overstates the time that passed.
contract ConfigRegistry is IConfigRegistryV2, RegistryDelegates {
    /// @dev One binding. Declared in the contract because it is storage layout
    /// and no part of anybody's ABI — `getV2` returns two flat values.
    ///
    /// The moment is a full word: `value` occupies a slot of its own whatever
    /// its length, so there is nothing for a narrower moment to pack beside,
    /// and at full width there is nothing to truncate.
    struct Binding {
        /// Empty if and only if the name is unbound, which is what `registerV2`
        /// rejecting an empty value preserves.
        bytes value;
        /// The `block.timestamp` of the most recent `registerV2`. Never zero for
        /// a bound name.
        uint256 registeredAt;
    }

    /// The bindings, under the authority that wrote them. Not `public`: the
    /// only reader is `getV2`, which reverts on an unbound name rather than
    /// answering empty.
    mapping(address authority => mapping(bytes32 name => Binding binding)) internal sBindings;

    /// @inheritdoc IConfigRegistryV2
    function registerV2(address authority, bytes32 name, bytes calldata value) external {
        // Who may write is settled before anything about the write.
        checkCallerWritesUnder(authority, name);
        // Rejected so that a name can never be both bound and unreadable.
        if (value.length == 0) {
            revert EmptyValue(name);
        }
        // Read after the cheap guard, so a refused call does not pay for it.
        uint256 registeredAt = sBindings[authority][name].registeredAt;
        // The clock is checked against a stored moment, never against a
        // deadline, so the validator-nudge hazard the analysers flag does not
        // reach it.
        // slither-disable-start timestamp
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp <= registeredAt) {
            revert TimestampNotAfterBinding(name, block.timestamp, registeredAt);
        }
        // slither-disable-end timestamp
        // Assigned whole, so a re-bind replaces the moment in the same write
        // that replaces the value.
        sBindings[authority][name] = Binding({value: value, registeredAt: block.timestamp});
        emit Register(msg.sender, authority, name, value);
    }

    /// @inheritdoc IConfigRegistryV2
    function approveV2(bytes32 name, address delegate) external {
        approveWithin(name, delegate);
    }

    /// @inheritdoc IConfigRegistryV2
    function revokeV2(bytes32 name, address delegate) external {
        revokeWithin(name, delegate);
    }

    /// @inheritdoc IConfigRegistryV2
    function approvedV2(address authority, bytes32 name, address delegate) external view returns (bool) {
        return approvedWithin(authority, name, delegate);
    }

    /// @inheritdoc IConfigRegistryV2
    /// @dev Bound-ness is read off `value`, not the moment: the value is the
    /// binding and the moment is metadata about when it was written.
    function getV2(address authority, bytes32 name) external view returns (bytes memory, uint256) {
        Binding memory binding = sBindings[authority][name];
        // Slither reaches this because `value` shares a struct with a value
        // written from `block.timestamp`. There is no time in it, and the
        // strict equality is the definition of unbound: `registerV2` refuses an
        // empty value.
        // slither-disable-start timestamp,incorrect-equality
        if (binding.value.length == 0) {
            revert NameNotRegistered(authority, name);
        }
        // slither-disable-end timestamp,incorrect-equality
        return (binding.value, binding.registeredAt);
    }
}
