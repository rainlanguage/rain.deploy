// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {IConfigRegistryV5} from "../interface/IConfigRegistryV5.sol";
import {RegistryDelegates} from "../abstract/RegistryDelegates.sol";
import {LibIMetaBoardV1_2} from "rain-metadata-0.1.43/src/lib/LibIMetaBoardV1_2.sol";

/// @title ConfigRegistry
/// @notice The whole of `IConfigRegistryV5`: any account binds a `bytes32` name
/// to an ABI-encoded value of a named type under its own address or under an
/// authority that approved it, anyone reads a name under an authority it names
/// and gets back the value with the moment it was bound and the hash of its
/// type, and a read of an unbound name reverts.
///
/// There is deliberately nothing else. No removal, no upgrade, no pause, and
/// no account that writes under another that has not approved it. The value is held and
/// returned verbatim and never decoded or checked against its type. Metadata
/// is emitted and never stored.
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
contract ConfigRegistry is IConfigRegistryV5, RegistryDelegates {
    /// @dev One binding. Declared in the contract because it is storage layout
    /// and no part of anybody's ABI — `getV5` returns three flat values.
    ///
    /// The moment is a full word: `value` occupies a slot of its own whatever
    /// its length, so there is nothing for a narrower moment to pack beside,
    /// and at full width there is nothing to truncate.
    struct Binding {
        /// Empty if and only if the name is unbound, which is what `registerV5`
        /// rejecting an empty value preserves.
        bytes value;
        /// The `block.timestamp` of the most recent `registerV5`. Never zero for
        /// a bound name.
        uint256 registeredAt;
        /// `keccak256` of the value type the most recent `registerV5` named.
        bytes32 valueTypeHash;
    }

    /// The bindings, under the authority that wrote them. Not `public`: the
    /// only reader is `getV5`, which reverts on an unbound name rather than
    /// answering empty.
    mapping(address authority => mapping(bytes32 name => Binding binding)) internal sBindings;

    /// @inheritdoc IConfigRegistryV5
    function registerV5(
        address authority,
        bytes32 name,
        string calldata valueType,
        bytes calldata value,
        bytes calldata meta
    ) external {
        // Who may write is settled before anything about the write.
        checkWrite(authority, name);
        // Rejected so that a name can never be both bound and unreadable.
        if (value.length == 0) {
            revert EmptyValue(name);
        }
        if (bytes(valueType).length == 0) {
            revert EmptyValueType(name);
        }
        // Read after the cheap guards, so a refused call does not pay for it.
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
        // Assigned whole, so a re-bind replaces the moment and type in the same
        // write that replaces the value.
        sBindings[authority][name] =
            Binding({value: value, registeredAt: block.timestamp, valueTypeHash: keccak256(bytes(valueType))});
        emit Register(msg.sender, authority, name, valueType, value);
        if (meta.length > 0) {
            LibIMetaBoardV1_2.emitMeta(keccak256(abi.encode(authority, name)), meta);
        }
    }

    /// @inheritdoc IConfigRegistryV5
    /// @dev Bound-ness is read off `value`, not the moment: the value is the
    /// binding and the moment is metadata about when it was written.
    function getV5(address authority, bytes32 name) external view returns (bytes memory, uint256, bytes32) {
        Binding memory binding = sBindings[authority][name];
        // Slither reaches this because `value` shares a struct with a value
        // written from `block.timestamp`. There is no time in it, and the
        // strict equality is the definition of unbound: `registerV5` refuses an
        // empty value.
        // slither-disable-start timestamp,incorrect-equality
        if (binding.value.length == 0) {
            revert NameNotRegistered(authority, name);
        }
        // slither-disable-end timestamp,incorrect-equality
        return (binding.value, binding.registeredAt, binding.valueTypeHash);
    }
}
