// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {IAddressRegistryV1} from "../interface/IAddressRegistryV1.sol";

/// @dev The only account that may bind a name. A compile-time constant rather
/// than storage, so it can never be rotated, and part of the creation code, so
/// changing it changes the deterministic deploy address and code hash of
/// `AddressRegistry` on every network.
///
/// Zero during rollout. Nothing calls from the zero address, so no name can be
/// bound while root is zero, and `get` reverts on every name that is not bound
/// — so a registry compiled under this root answers every read with a revert
/// and cannot answer one with an address. There is no state in which a consumer
/// silently resolves something wrong from it: a zero root makes the registry
/// inert, loudly, in every direction.
///
/// Setting a real root is an ordinary source change. It moves the creation
/// code, and therefore the deploy address, the code hash, the snapshot
/// `script/Build.sol` generates and the release that carries them.
address constant ADDRESS_REGISTRY_ROOT = address(0);

/// @title AddressRegistry
/// @notice The whole of `IAddressRegistryV1`: an immutable root authority binds
/// a `bytes32` name, anyone reads a bound name, and a read of an unbound name
/// reverts.
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
/// The storage mapping is `internal` rather than `public`: a public mapping's
/// generated getter answers an unbound name with the zero address, which is
/// exactly the silent failure `get` reverts to prevent.
contract AddressRegistry is IAddressRegistryV1 {
    /// The bindings. Not `public`: the only reader is `get`, which reverts on an
    /// unbound name. A name maps to the zero address if and only if it is
    /// unbound, which is why `register` rejects the zero address.
    mapping(bytes32 name => address account) internal sAddresses;

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
        sAddresses[name] = account;
        emit Register(name, account);
    }

    /// @inheritdoc IAddressRegistryV1
    /// @dev Returns whatever root has bound most recently. A caller that needs
    /// an answer that cannot move reads once and stores it, which is what a
    /// consumer resolving a name in its constructor does.
    function get(bytes32 name) external view returns (address account) {
        account = sAddresses[name];
        if (account == address(0)) {
            revert NameNotRegistered(name);
        }
    }
}
