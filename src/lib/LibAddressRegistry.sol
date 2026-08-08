// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {IAddressRegistryV1} from "../interface/IAddressRegistryV1.sol";

/// @title LibAddressRegistry
/// @notice Reads the `IAddressRegistryV1` deployed at a single deterministic
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
library LibAddressRegistry {
    /// Thrown when the code at the registry address is not the registry this
    /// library was compiled against. An address with no code hits this too: an
    /// empty account's code hash is zero (or the hash of empty code), never the
    /// expected value.
    /// @param expectedCodeHash The code hash of the pinned registry.
    /// @param actualCodeHash The code hash actually found at the address.
    error UnexpectedAddressRegistryCodeHash(bytes32 expectedCodeHash, bytes32 actualCodeHash);

    /// The deterministic Zoltu deploy address of `AddressRegistry`, the same on
    /// every network.
    ///
    /// Derived from that contract's creation code, not observed from a chain:
    /// the Zoltu factory is `CREATE2` over its calldata with a zero salt, so the
    /// address is a pure function of the creation code
    /// (`LibRainDeploy.zoltuAddress`). The root authority is a constant in that
    /// creation code, so changing the root moves this address, and both this and
    /// `ADDRESS_REGISTRY_CODEHASH` MUST be re-derived whenever it changes.
    address constant ADDRESS_REGISTRY = 0x619e47868cE4a9AEbBD6444c9385f1558c79ED52;

    /// The code hash of `AddressRegistry` once deployed, i.e. `keccak256` over
    /// the runtime code its creation code leaves behind. Derived from the same
    /// compilation as `ADDRESS_REGISTRY`, and moves with it.
    bytes32 constant ADDRESS_REGISTRY_CODEHASH = 0x01e8bf67abc9d4b4abe2d39c66c07c1b02e39bdf559c694f94f5853bad6394d8;

    /// The address a name is bound to in the registry.
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
        bytes32 actualCodeHash = ADDRESS_REGISTRY.codehash;
        if (actualCodeHash != ADDRESS_REGISTRY_CODEHASH) {
            revert UnexpectedAddressRegistryCodeHash(ADDRESS_REGISTRY_CODEHASH, actualCodeHash);
        }
        return IAddressRegistryV1(ADDRESS_REGISTRY).get(name);
    }
}
