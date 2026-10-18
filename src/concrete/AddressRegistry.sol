// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {IAddressRegistryV2} from "../interface/IAddressRegistryV2.sol";

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
/// @notice The whole of `IAddressRegistryV2`: an immutable root authority binds
/// a `bytes32` name to an ABI-encoded value, anyone reads a bound name and gets
/// back the value with the moment it was bound, and a read of an unbound name
/// reverts.
///
/// There is deliberately nothing else. No removal, no upgrade, no pause, and no
/// authority besides root — root is a compile-time constant, so it cannot even
/// hand itself over. The value is held and returned verbatim and never decoded;
/// its type is between whoever binds the name and whoever reads it.
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
/// pending. A name's moment strictly increases, so an age derived from it never
/// overstates the time that passed.
contract AddressRegistry is IAddressRegistryV2 {
    /// @dev One binding. Declared in the contract because it is storage layout
    /// and no part of anybody's ABI — `get` returns two flat values.
    ///
    /// The moment is a full word: `value` occupies a slot of its own whatever
    /// its length, so there is nothing for a narrower moment to pack beside,
    /// and at full width there is nothing to truncate.
    struct Binding {
        /// Empty if and only if the name is unbound, which is what `register`
        /// rejecting an empty value preserves.
        bytes value;
        /// The `block.timestamp` of the most recent `register`. Never zero for
        /// a bound name.
        uint256 registeredAt;
    }

    /// The bindings. Not `public`: the only reader is `get`, which reverts on an
    /// unbound name rather than answering empty.
    mapping(bytes32 name => Binding binding) internal sBindings;

    /// @inheritdoc IAddressRegistryV2
    function register(bytes32 name, bytes calldata value) external {
        if (msg.sender != ADDRESS_REGISTRY_ROOT) {
            revert NotRoot(msg.sender);
        }
        // Rejected so that a name can never be both bound and unreadable.
        if (value.length == 0) {
            revert EmptyValue(name);
        }
        // Read after the cheap guards, so a refused call does not pay for it.
        uint256 registeredAt = sBindings[name].registeredAt;
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
        sBindings[name] = Binding({value: value, registeredAt: block.timestamp});
        emit Register(name, value);
    }

    /// @inheritdoc IAddressRegistryV2
    /// @dev Bound-ness is read off `value`, not the moment: the value is the
    /// binding and the moment is metadata about when it was written.
    function get(bytes32 name) external view returns (bytes memory, uint256) {
        Binding memory binding = sBindings[name];
        // Slither reaches this because `value` shares a struct with a value
        // written from `block.timestamp`. There is no time in it.
        // slither-disable-start timestamp
        if (binding.value.length == 0) {
            revert NameNotRegistered(name);
        }
        // slither-disable-end timestamp
        return (binding.value, binding.registeredAt);
    }
}
