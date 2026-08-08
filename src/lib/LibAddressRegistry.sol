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
/// That is the whole library. It resolves a name to an address. What a consumer
/// resolves a name for, and when — an owner set in a constructor or an
/// initializer, under `Ownable` or RBAC or nothing at all — is entirely the
/// consumer's business and none of this library's.
///
/// Bindings are mutable, so `resolve` answers with whatever root has bound most
/// recently. A caller that needs an answer that cannot move afterwards resolves
/// once, in its constructor, and stores the result; it must not re-read at the
/// point of use. That single read at construction is what makes a deployment
/// verifiable after the fact: the value is settled the moment the contract
/// exists, and no later re-binding can move it.
library LibAddressRegistry {
    /// Thrown when the code at the registry address is not the registry this
    /// library was compiled against. An address with no code hits this too: an
    /// empty account's code hash is zero, never the expected value.
    /// @param expectedCodeHash The code hash of the pinned registry.
    /// @param actualCodeHash The code hash actually found at the address.
    error UnexpectedAddressRegistryCodeHash(bytes32 expectedCodeHash, bytes32 actualCodeHash);

    /// The address `name` is currently bound to in the registry.
    ///
    /// Verifies the registry's code hash before reading, so a chain where the
    /// registry is absent, or where something else occupies its address, is a
    /// loud revert rather than a call into unknown code. The registry itself
    /// reverts on an unbound name, so a returned address is always a real
    /// binding and is never the zero address.
    /// @param name The name to resolve. Opaque; the registry constrains nothing
    /// about how it was derived.
    /// @return The address bound to `name`.
    function resolve(bytes32 name) internal view returns (address) {
        bytes32 actualCodeHash = LibAddressRegistryDeploy.ADDRESS_REGISTRY_DEPLOYED_ADDRESS.codehash;
        if (actualCodeHash != LibAddressRegistryDeploy.ADDRESS_REGISTRY_DEPLOYED_CODEHASH) {
            revert UnexpectedAddressRegistryCodeHash(
                LibAddressRegistryDeploy.ADDRESS_REGISTRY_DEPLOYED_CODEHASH, actualCodeHash
            );
        }
        return IAddressRegistryV1(LibAddressRegistryDeploy.ADDRESS_REGISTRY_DEPLOYED_ADDRESS).get(name);
    }
}
