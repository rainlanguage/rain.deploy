// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {IAddressRegistryV1} from "../interface/IAddressRegistryV1.sol";
import {LibAddressRegistryDeploy} from "./LibAddressRegistryDeploy.sol";

/// @title LibAddressRegistry
/// @notice Reads the `AddressRegistry` deployed at a single deterministic
/// address on every network, verifying the registry's code hash first, exactly
/// as `LibRainDeploy` verifies `ZOLTU_FACTORY_CODEHASH` before using the Zoltu
/// factory. An address alone says nothing on a chain the caller has not
/// audited; the address plus the code hash says the caller is talking to the
/// registry it compiled against.
///
/// That is the whole library. It resolves a name to an address and the moment
/// that address was bound, and will refuse a binding younger than the caller
/// says it will accept. What a consumer resolves a name for, and when, is
/// entirely the consumer's business and none of this library's.
///
/// Bindings are mutable, so `resolve` answers with whatever root has bound most
/// recently. A caller that needs an answer that cannot move afterwards resolves
/// once, in its constructor, and stores the result; it must not re-read at the
/// point of use. That single read at construction is what makes a deployment
/// verifiable after the fact.
library LibAddressRegistry {
    /// Thrown when the code at the registry address is not the registry this
    /// library was compiled against. An address with no code hits this too: a
    /// codeless account hashes to zero while it does not exist, and to the hash
    /// of the empty string once a single wei brings it into existence. Neither
    /// is the expected value.
    /// @param expectedCodeHash The code hash of the pinned registry.
    /// @param actualCodeHash The code hash actually found at the address.
    error UnexpectedAddressRegistryCodeHash(bytes32 expectedCodeHash, bytes32 actualCodeHash);

    /// Thrown by `resolveSafe` when the binding has not stood for long enough.
    /// @param name The name that resolved to too fresh a binding.
    /// @param age How long the binding had stood, in seconds.
    /// @param minAge How long it had to have stood.
    error BindingTooFresh(bytes32 name, uint256 age, uint256 minAge);

    /// Thrown by `resolveSafe` when the binding is stamped ahead of the clock.
    ///
    /// Separate from `BindingTooFresh` because the caller's response differs: a
    /// too-fresh binding becomes acceptable by waiting, while a clock that moved
    /// backwards since the bind makes every binding's age on that chain
    /// unreliable and waiting fixes nothing.
    /// @param name The name that was being resolved.
    /// @param registeredAt The moment the binding carries.
    /// @param blockTimestamp The clock it was read against.
    error BindingStampedInFuture(bytes32 name, uint256 registeredAt, uint256 blockTimestamp);

    /// Thrown by `resolveSafe` when `minAge` is zero, which every binding
    /// satisfies. Honouring it would make this `resolve` under a name that
    /// promises a check. A caller that wants no threshold calls `resolve`.
    /// @param name The name that was being resolved.
    error ZeroMinAge(bytes32 name);

    /// The address `name` is currently bound to in the registry, and when it was
    /// bound.
    ///
    /// Verifies the registry's code hash before reading, so a chain where the
    /// registry is absent, or where something else occupies its address, is a
    /// loud revert rather than a call into unknown code. The registry itself
    /// reverts on an unbound name, so a returned address is always a real
    /// binding and is never the zero address.
    /// @param name The name to resolve. Opaque; the registry constrains nothing
    /// about how it was derived.
    /// @return The address bound to `name`.
    /// @return The `block.timestamp` at which `name` was most recently bound.
    function resolve(bytes32 name) internal view returns (address, uint256) {
        bytes32 actualCodeHash = LibAddressRegistryDeploy.ADDRESS_REGISTRY_DEPLOYED_ADDRESS.codehash;
        if (actualCodeHash != LibAddressRegistryDeploy.ADDRESS_REGISTRY_DEPLOYED_CODEHASH) {
            revert UnexpectedAddressRegistryCodeHash(
                LibAddressRegistryDeploy.ADDRESS_REGISTRY_DEPLOYED_CODEHASH, actualCodeHash
            );
        }
        // Destructured rather than returned straight through, so both halves are
        // visibly used: a passed-through tuple reads to the analysers as a
        // return value nobody looked at.
        (address account, uint256 registeredAt) =
            IAddressRegistryV1(LibAddressRegistryDeploy.ADDRESS_REGISTRY_DEPLOYED_ADDRESS).get(name);
        return (account, registeredAt);
    }

    /// `resolve`, refusing a binding that has not stood for longer than
    /// `minAge`, and returning the address alone.
    ///
    /// This is the check the registry leaves to consumers: a rebind timed to
    /// land immediately before a resolve is how a dormant root compromise
    /// converts to live capture. The threshold is the caller's because only the
    /// caller knows what it is resolving the name for.
    ///
    /// What `minAge` buys is an observation WINDOW, not protection. An attacker
    /// who rebinds and waits it out passes. What it guarantees is that the
    /// rebind was public for that long first, which is worth something only if
    /// something is watching.
    ///
    /// The boundary is exclusive: a binding exactly `minAge` old is refused, the
    /// fail-safe reading of the edge.
    /// @param name The name to resolve. Opaque, as in `resolve`.
    /// @param minAge The time, in seconds, the binding must have stood for.
    /// Never zero.
    /// @return The address bound to `name`.
    function resolveSafe(bytes32 name, uint256 minAge) internal view returns (address) {
        // First, so a caller that asked for no threshold is told so whatever the
        // registry would have said.
        if (minAge == 0) {
            revert ZeroMinAge(name);
        }
        (address account, uint256 registeredAt) = resolve(name);
        // Checked before the subtraction, so a future stamp is reported as what
        // it is rather than underflowing. These comparisons really are about a
        // moment; a validator's seconds of slack cannot matter to a `minAge`
        // long enough to notice a rebind in.
        // slither-disable-start timestamp
        // forge-lint: disable-next-line(block-timestamp)
        if (registeredAt > block.timestamp) {
            revert BindingStampedInFuture(name, registeredAt, block.timestamp);
        }
        uint256 age = block.timestamp - registeredAt;
        if (age <= minAge) {
            revert BindingTooFresh(name, age, minAge);
        }
        // slither-disable-end timestamp
        return account;
    }
}
