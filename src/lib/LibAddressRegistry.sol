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
/// says it will accept. What a consumer resolves a name for, and when — an
/// owner set in a constructor or an initializer, under `Ownable` or RBAC or
/// nothing at all — is entirely the consumer's business and none of this
/// library's.
///
/// Bindings are mutable, so `resolve` answers with whatever root has bound most
/// recently. A caller that needs an answer that cannot move afterwards resolves
/// once, in its constructor, and stores the result; it must not re-read at the
/// point of use. That single read at construction is what makes a deployment
/// verifiable after the fact: the value is settled the moment the contract
/// exists, and no later re-binding can move it.
///
/// The moment comes back alongside the address so that a caller about to
/// snapshot one can tell whether it has just moved. `resolveSafe` is that
/// comparison written once: it takes the caller's own minimum age and reverts
/// rather than returning a binding younger than it. The threshold is never this
/// library's — it is a parameter, because what counts as too fresh depends on
/// what the name is being resolved for, and only the caller knows that.
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

    /// Thrown by `resolveSafe` when asked to accept any age at all. A `minAge`
    /// of zero is satisfied by every binding, including one made in the block
    /// being read, so it is `resolve` wearing the name of the checked version —
    /// the one shape of call that looks guarded and is not. Refused rather than
    /// answered, for the same reason `get` refuses an unbound name instead of
    /// returning zero: a caller that reaches zero has reached it by accident,
    /// from an unset constant or an unconfigured parameter, and that is a
    /// mistake to report rather than a request to honour. A caller that really
    /// wants no threshold says so by calling `resolve`.
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
        // Destructured rather than returned straight through, so that both
        // halves are visibly used: a tuple handed back untouched reads to the
        // static analysers as a return value nobody looked at.
        (address account, uint256 registeredAt) =
            IAddressRegistryV1(LibAddressRegistryDeploy.ADDRESS_REGISTRY_DEPLOYED_ADDRESS).get(name);
        return (account, registeredAt);
    }

    /// `resolve`, refusing a binding that has not stood for `minAge` seconds.
    ///
    /// This is the check the registry deliberately does not make for anyone: a
    /// rebind timed to land immediately before a resolve is how a dormant root
    /// compromise converts to live capture, and the moment is what lets a caller
    /// refuse it. The threshold is the caller's, passed in here, because only
    /// the caller knows what it is resolving the name for.
    ///
    /// A binding exactly `minAge` old passes — the requirement is that it has
    /// stood for at least that long, so the boundary is inclusive.
    ///
    /// A `minAge` of zero is REFUSED, before the registry is read at all. Zero
    /// accepts everything, so it would make this function `resolve` under a
    /// name that promises a check — the one call shape that looks guarded while
    /// guarding nothing. `resolve` is how a caller asks for no threshold.
    ///
    /// A binding stamped in the future is treated as having no age at all and
    /// so always refused, rather than reverting on the underflow of
    /// `block.timestamp - registeredAt`. A future stamp means the chain's clock
    /// moved backwards since the bind, which is not a state to hand a caller an
    /// address out of.
    ///
    /// Returns the address alone. Vetting it is this function's whole purpose,
    /// so the moment has been spent; a caller that wants it as well uses
    /// `resolve` and compares for itself.
    /// @param name The name to resolve. Opaque, as in `resolve`.
    /// @param minAge The least time, in seconds, the binding must have stood.
    /// Never zero.
    /// @return The address bound to `name`.
    function resolveSafe(bytes32 name, uint256 minAge) internal view returns (address) {
        // First, so that a caller which asked for no threshold is told so
        // whatever the registry would have said — including on a chain with no
        // registry, and for a name nobody has bound. The call is wrong before
        // any of that is reached.
        if (minAge == 0) {
            revert ZeroMinAge(name);
        }
        (address account, uint256 registeredAt) = resolve(name);
        // Clamped rather than subtracted blind, so a future stamp is refused by
        // the check below instead of reverting as an arithmetic panic.
        //
        // Unlike the width check in `AddressRegistry.register`, these
        // comparisons really are about a moment, which is what the analysers
        // flag. The hazard is priced by the caller: a validator's few seconds
        // of slack at the boundary cannot matter to a `minAge` chosen to be
        // long enough to notice a rebind in, and a caller that would be harmed
        // by seconds has not picked a `minAge` that protects it from anything.
        // Suppressed on these two comparisons rather than turned off for the
        // repo.
        //
        // Slither's is a start/end pair because forge-lint's has to be the
        // comment immediately above the line and has no pair form.
        // slither-disable-start timestamp
        // forge-lint: disable-next-line(block-timestamp)
        uint256 age = block.timestamp > registeredAt ? block.timestamp - registeredAt : 0;
        if (age < minAge) {
            revert BindingTooFresh(name, age, minAge);
        }
        // slither-disable-end timestamp
        return account;
    }
}
