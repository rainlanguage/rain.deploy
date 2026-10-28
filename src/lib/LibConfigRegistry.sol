// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {IConfigRegistryV5} from "../interface/IConfigRegistryV5.sol";
import {LibConfigRegistryDeploy} from "./LibConfigRegistryDeploy.sol";

/// @title LibConfigRegistry
/// @notice Reads the `ConfigRegistry` deployed at a single deterministic
/// address on every network, verifying the registry's code hash first, exactly
/// as `LibRainDeploy` verifies `ZOLTU_FACTORY_CODEHASH` before using the Zoltu
/// factory. An address alone says nothing on a chain the caller has not
/// audited; the address plus the code hash says the caller is talking to the
/// registry it compiled against.
///
/// That is the whole library. It resolves a name under an authority to the
/// ABI-encoded value that authority bound it to and the moment it was bound,
/// and will refuse a binding made as a type other than the caller expects, or
/// younger than the caller says it will accept. It never decodes the value:
/// the caller decodes, as `abi.decode(value, (address))` for a binding resolved
/// with `keccak256("address")`.
/// What a consumer resolves a name for, and when, is entirely the consumer's
/// business and none of this library's.
///
/// The authority is the caller's choice and the whole of what it trusts: a
/// binding is only ever written by the authority it is read under, so the
/// caller names the account it already trusts for the name, beside the name,
/// in its own creation code. It MUST be a constant or a constructor argument,
/// which the deterministic address commits to, never `tx.origin`, `msg.sender`
/// or anything else read at construction, which it does not commit to.
///
/// Bindings are mutable, so `resolve` answers with whatever the authority has
/// bound most recently. A caller that needs an answer that cannot move
/// afterwards resolves once, in its constructor, and stores the result; it
/// must not re-read at the point of use. That single read at construction is
/// what makes a deployment verifiable after the fact.
library LibConfigRegistry {
    /// Thrown when the code at the registry address is not the registry this
    /// library was compiled against. An address with no code hits this too: a
    /// codeless account hashes to zero while it does not exist, and to the hash
    /// of the empty string once a single wei brings it into existence. Neither
    /// is the expected value.
    /// @param expectedCodeHash The code hash of the pinned registry.
    /// @param actualCodeHash The code hash actually found at the address.
    error UnexpectedConfigRegistryCodeHash(bytes32 expectedCodeHash, bytes32 actualCodeHash);

    /// Thrown by `resolveSafe` when the binding has not stood for long enough.
    /// @param authority The authority the name was resolved under.
    /// @param name The name that resolved to too fresh a binding.
    /// @param age How long the binding had stood, in seconds.
    /// @param minAge How long it had to have stood.
    error BindingTooFresh(address authority, bytes32 name, uint256 age, uint256 minAge);

    /// Thrown by `resolveSafe` when the binding is stamped ahead of the clock.
    ///
    /// Separate from `BindingTooFresh` because the caller's response differs: a
    /// too-fresh binding becomes acceptable by waiting, while a clock that moved
    /// backwards since the bind makes every binding's age on that chain
    /// unreliable and waiting fixes nothing.
    /// @param authority The authority the name was resolved under.
    /// @param name The name that was being resolved.
    /// @param registeredAt The moment the binding carries.
    /// @param blockTimestamp The clock it was read against.
    error BindingStampedInFuture(address authority, bytes32 name, uint256 registeredAt, uint256 blockTimestamp);

    /// Thrown by `resolveSafe` when `minAge` is zero, which every binding
    /// satisfies. Honouring it would make this `resolve` under a name that
    /// promises a check. A caller that wants no threshold calls `resolve`.
    /// @param authority The authority the name was being resolved under.
    /// @param name The name that was being resolved.
    error ZeroMinAge(address authority, bytes32 name);

    /// Thrown by `resolve` and `resolveSafe` when the binding was made as a
    /// type other than the one the caller decodes it as.
    /// @param authority The authority the name was resolved under.
    /// @param name The name that was being resolved.
    /// @param expectedValueTypeHash The hash of the type the caller expects.
    /// @param actualValueTypeHash The hash of the type the binding was made as.
    error ValueTypeMismatch(
        address authority, bytes32 name, bytes32 expectedValueTypeHash, bytes32 actualValueTypeHash
    );

    /// Reverts unless the registry address holds the code this library was
    /// compiled against: the check `resolve` makes before every read, for a
    /// caller that has to know it is talking to the pinned registry before
    /// doing anything else with it — writing to it, or reading a name that may
    /// be unbound.
    function checkCodeHash() internal view {
        bytes32 actualCodeHash = LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS.codehash;
        if (actualCodeHash != LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_CODEHASH) {
            revert UnexpectedConfigRegistryCodeHash(
                LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_CODEHASH, actualCodeHash
            );
        }
    }

    /// The value `authority` currently binds `name` to in the registry, and
    /// when it bound it, refusing a binding made as any type but the one the
    /// caller expects.
    ///
    /// Verifies the registry's code hash before reading, so a chain where the
    /// registry is absent, or where something else occupies its address, is a
    /// loud revert rather than a call into unknown code. The registry itself
    /// reverts on a name the authority has not bound, so a returned value is
    /// always a real binding and is never empty.
    ///
    /// The value is returned exactly as the authority bound it. The caller
    /// decodes it with the type it expects. The type hash is the authority's
    /// statement of that type, and the registry never checks the value
    /// against it. `abi.decode` refuses some wrongly
    /// shaped values, such as one shorter than the type's encoding or one with
    /// bits a narrow type cannot hold, but it ignores trailing bytes and
    /// decodes any word that is valid for the requested type. A caller that must
    /// refuse a wrongly shaped binding checks it, e.g. `value.length == 32` for
    /// one static type, or `keccak256(abi.encode(decoded)) == keccak256(value)`.
    /// @param authority The account whose binding to read: the one the caller
    /// trusts for `name`.
    /// @param name The name to resolve. Opaque; the registry constrains nothing
    /// about how it was derived.
    /// @param valueTypeHash `keccak256` of the normalized ABI type the caller
    /// decodes the value as, e.g. `keccak256("address")`.
    /// @return The ABI-encoded value `authority` bound `name` to.
    /// @return The `block.timestamp` at which `authority` most recently bound
    /// `name`.
    function resolve(address authority, bytes32 name, bytes32 valueTypeHash)
        internal
        view
        returns (bytes memory, uint256)
    {
        checkCodeHash();
        (bytes memory value, uint256 registeredAt, bytes32 actualValueTypeHash) =
            IConfigRegistryV5(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS).getV5(authority, name);
        if (actualValueTypeHash != valueTypeHash) {
            revert ValueTypeMismatch(authority, name, valueTypeHash, actualValueTypeHash);
        }
        return (value, registeredAt);
    }

    /// `resolve`, refusing a binding that has not stood for longer than
    /// `minAge`, and returning the value alone.
    ///
    /// This is the check the registry leaves to consumers: a rebind timed to
    /// land immediately before a resolve is how a dormant authority compromise
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
    /// @param authority The account whose binding to read, as in `resolve`.
    /// @param name The name to resolve. Opaque, as in `resolve`.
    /// @param valueTypeHash The hash of the type the caller expects, as in
    /// `resolve`.
    /// @param minAge The time, in seconds, the binding must have stood for.
    /// Never zero.
    /// @return The ABI-encoded value `authority` bound `name` to, for the
    /// caller to decode as in `resolve`.
    function resolveSafe(address authority, bytes32 name, bytes32 valueTypeHash, uint256 minAge)
        internal
        view
        returns (bytes memory)
    {
        // First, so a caller that asked for no threshold is told so whatever the
        // registry would have said.
        if (minAge == 0) {
            revert ZeroMinAge(authority, name);
        }
        (bytes memory value, uint256 registeredAt) = resolve(authority, name, valueTypeHash);
        // Checked before the subtraction, so a future stamp is reported as what
        // it is rather than underflowing. These comparisons really are about a
        // moment; a validator's seconds of slack cannot matter to a `minAge`
        // long enough to notice a rebind in.
        // slither-disable-start timestamp
        // forge-lint: disable-next-line(block-timestamp)
        if (registeredAt > block.timestamp) {
            revert BindingStampedInFuture(authority, name, registeredAt, block.timestamp);
        }
        uint256 age = block.timestamp - registeredAt;
        // forge-lint: disable-next-line(block-timestamp)
        if (age <= minAge) {
            revert BindingTooFresh(authority, name, age, minAge);
        }
        // slither-disable-end timestamp
        return value;
    }
}
