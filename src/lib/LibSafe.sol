// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {IProxy} from "safe-global-safe-smart-account-1.4.1-3/contracts/proxies/SafeProxy.sol";
import {
    BYTECODE_HASH as SAFE_V1_4_1_SAFE_BYTECODE_HASH,
    RUNTIME_CODE as SAFE_V1_4_1_SAFE_RUNTIME_CODE
} from "../generated/safe_v1_4_1/Safe.sol";
import {
    BYTECODE_HASH as SAFE_V1_4_1_SAFE_L2_BYTECODE_HASH,
    RUNTIME_CODE as SAFE_V1_4_1_SAFE_L2_RUNTIME_CODE
} from "../generated/safe_v1_4_1/SafeL2.sol";
import {
    BYTECODE_HASH as SAFE_V1_4_1_SAFE_PROXY_FACTORY_BYTECODE_HASH,
    RUNTIME_CODE as SAFE_V1_4_1_SAFE_PROXY_FACTORY_RUNTIME_CODE
} from "../generated/safe_v1_4_1/SafeProxyFactory.sol";
import {
    BYTECODE_HASH as SAFE_V1_4_1_COMPAT_HANDLER_BYTECODE_HASH,
    RUNTIME_CODE as SAFE_V1_4_1_COMPAT_HANDLER_RUNTIME_CODE
} from "../generated/safe_v1_4_1/CompatibilityFallbackHandler.sol";
import {
    BYTECODE_HASH as SAFE_V1_4_1_SAFE_TO_L2_SETUP_BYTECODE_HASH,
    RUNTIME_CODE as SAFE_V1_4_1_SAFE_TO_L2_SETUP_RUNTIME_CODE
} from "../generated/safe_v1_4_1/SafeToL2Setup.sol";
import {
    BYTECODE_HASH as SAFE_V1_4_1_SAFE_PROXY_BYTECODE_HASH,
    RUNTIME_CODE as SAFE_V1_4_1_SAFE_PROXY_RUNTIME_CODE
} from "../generated/safe_v1_4_1/SafeProxy.sol";
import {
    BYTECODE_HASH as SAFE_V1_3_0_GNOSIS_SAFE_PROXY_BYTECODE_HASH,
    RUNTIME_CODE as SAFE_V1_3_0_GNOSIS_SAFE_PROXY_RUNTIME_CODE
} from "../generated/safe_v1_3_0/GnosisSafeProxy.sol";

/// @title LibSafe
/// @notice The canonical Safe v1.4.1 deployment — addresses, runtime code,
/// runtime code hashes and storage slots — and assertions that a Safe on the
/// selected chain is a genuine v1.4.1 Safe in a given configuration. Every
/// assertion returns silently when it holds and reverts with a typed error
/// naming the drift when it does not.
///
/// Addresses are those of https://github.com/safe-global/safe-deployments
/// v1.4.1, identical on every network this repo supports. Runtime code and its
/// hash are the records `script/BuildSafeRecords.sol` reads from the chain
/// into `src/generated/safe_v1_4_1/` and `src/generated/safe_v1_3_0/`. Storage
/// slots are those of
/// https://github.com/safe-global/safe-smart-account/tree/v1.4.1/contracts.
///
/// ## Trust order
///
/// A Safe proxy delegates every call except `masterCopy()` to its singleton, so
/// what `getStorageAt`, `getOwners`, `getThreshold`, `getModulesPaginated` and
/// `VERSION` return is only as trustworthy as the singleton's code.
/// `assertIdentity` establishes that trust from the bottom up — the proxy's own
/// code hash, then the singleton the proxy itself reports, then that
/// singleton's code hash — before making any delegated call. Every other
/// assertion on a Safe makes delegated calls, so it says nothing about a Safe
/// that `assertIdentity` has not passed.
library LibSafe {
    /// A canonical Safe contract is absent or carries other code.
    /// @param account The canonical address.
    /// @param expected The pinned runtime code hash.
    /// @param actual The code hash at `account`.
    error SafeCodehashMismatch(address account, bytes32 expected, bytes32 actual);

    /// The code at `safe` is neither the v1.3.0 nor the v1.4.1 `SafeProxy`.
    /// @param safe The Safe.
    /// @param actual The code hash at `safe`.
    error SafeUnknownProxyCodehash(address safe, bytes32 actual);

    /// The proxy's singleton is neither canonical v1.4.1 singleton.
    /// @param safe The Safe.
    /// @param singleton The singleton the proxy holds.
    error SafeUnknownSingleton(address safe, address singleton);

    /// A canonical v1.4.1 singleton address carries other code.
    /// @param safe The Safe.
    /// @param singleton The singleton the proxy holds.
    /// @param expected The pinned code hash for that singleton.
    /// @param actual The code hash at `singleton`.
    error SafeSingletonCodehashMismatch(address safe, address singleton, bytes32 expected, bytes32 actual);

    /// The singleton reports a version other than `SAFE_V1_4_1_VERSION`.
    /// @param safe The Safe.
    /// @param actual The reported version.
    error SafeVersionMismatch(address safe, string actual);

    /// The Safe has a module enabled.
    /// @param safe The Safe.
    /// @param module The first module in the Safe's module list.
    error SafeUnexpectedModule(address safe, address module);

    /// The Safe has a transaction guard set.
    /// @param safe The Safe.
    /// @param guard The guard.
    error SafeUnexpectedGuard(address safe, address guard);

    /// The Safe's fallback handler is not the expected one.
    /// @param safe The Safe.
    /// @param expected The expected fallback handler.
    /// @param actual The Safe's fallback handler.
    error SafeFallbackHandlerMismatch(address safe, address expected, address actual);

    /// The Safe has a different number of owners than expected.
    /// @param safe The Safe.
    /// @param expected The expected owner count.
    /// @param actual The Safe's owner count.
    error SafeOwnerCountMismatch(address safe, uint256 expected, uint256 actual);

    /// The Safe's owner at `index` of `getOwners()` is not the expected one.
    /// @param safe The Safe.
    /// @param index The position in `getOwners()`.
    /// @param expected The expected owner at `index`.
    /// @param actual The Safe's owner at `index`.
    error SafeOwnerMismatch(address safe, uint256 index, address expected, address actual);

    /// The Safe has an owner that is not among the expected owners.
    /// @param safe The Safe.
    /// @param owner The unexpected owner.
    error SafeUnexpectedOwner(address safe, address owner);

    /// The Safe's threshold is not the expected one.
    /// @param safe The Safe.
    /// @param expected The expected threshold.
    /// @param actual The Safe's threshold.
    error SafeThresholdMismatch(address safe, uint256 expected, uint256 actual);

    /// What both v1.4.1 singletons return from `VERSION()`.
    string internal constant SAFE_V1_4_1_VERSION = "1.4.1";

    /// The v1.4.1 `Safe` singleton, without the `SafeL2` events. The default on
    /// Ethereum mainnet.
    address internal constant SAFE_V1_4_1_L1_SINGLETON = 0x41675C099F32341bf84BFc5382aF534df5C7461a;
    /// Runtime code hash of `SAFE_V1_4_1_L1_SINGLETON`.
    bytes32 internal constant SAFE_V1_4_1_L1_SINGLETON_CODEHASH = SAFE_V1_4_1_SAFE_BYTECODE_HASH;
    /// Runtime code of `SAFE_V1_4_1_L1_SINGLETON`.
    bytes internal constant SAFE_V1_4_1_L1_SINGLETON_RUNTIME_CODE = SAFE_V1_4_1_SAFE_RUNTIME_CODE;

    /// The v1.4.1 `SafeL2` singleton: `Safe` plus events for indexers. The
    /// default off Ethereum mainnet.
    address internal constant SAFE_V1_4_1_L2_SINGLETON = 0x29fcB43b46531BcA003ddC8FCB67FFE91900C762;
    /// Runtime code hash of `SAFE_V1_4_1_L2_SINGLETON`.
    bytes32 internal constant SAFE_V1_4_1_L2_SINGLETON_CODEHASH = SAFE_V1_4_1_SAFE_L2_BYTECODE_HASH;
    /// Runtime code of `SAFE_V1_4_1_L2_SINGLETON`.
    bytes internal constant SAFE_V1_4_1_L2_SINGLETON_RUNTIME_CODE = SAFE_V1_4_1_SAFE_L2_RUNTIME_CODE;

    /// The v1.4.1 `SafeProxyFactory`.
    address internal constant SAFE_V1_4_1_PROXY_FACTORY = 0x4e1DCf7AD4e460CfD30791CCC4F9c8a4f820ec67;
    /// Runtime code hash of `SAFE_V1_4_1_PROXY_FACTORY`.
    bytes32 internal constant SAFE_V1_4_1_PROXY_FACTORY_CODEHASH = SAFE_V1_4_1_SAFE_PROXY_FACTORY_BYTECODE_HASH;
    /// Runtime code of `SAFE_V1_4_1_PROXY_FACTORY`.
    bytes internal constant SAFE_V1_4_1_PROXY_FACTORY_RUNTIME_CODE = SAFE_V1_4_1_SAFE_PROXY_FACTORY_RUNTIME_CODE;

    /// The init code hash `SAFE_V1_4_1_PROXY_FACTORY` CREATE2s over for a proxy
    /// on `SAFE_V1_4_1_L1_SINGLETON`:
    /// `keccak256(proxyCreationCode() ++ abi.encode(SAFE_V1_4_1_L1_SINGLETON))`.
    /// With the factory address and the salt
    /// `keccak256(keccak256(initializer) ++ saltNonce)` it gives the address of
    /// a proxy created with `createProxyWithNonce`, independent of the sender.
    bytes32 internal constant SAFE_V1_4_1_L1_PROXY_INITCODE_HASH =
        0x76733d705f71b79841c0ee960a0ca880f779cde7ef446c989e6d23efc0a4adfb;

    /// The v1.4.1 `CompatibilityFallbackHandler`.
    address internal constant SAFE_V1_4_1_COMPATIBILITY_FALLBACK_HANDLER = 0xfd0732Dc9E303f09fCEf3a7388Ad10A83459Ec99;
    /// Runtime code hash of `SAFE_V1_4_1_COMPATIBILITY_FALLBACK_HANDLER`.
    bytes32 internal constant SAFE_V1_4_1_COMPATIBILITY_FALLBACK_HANDLER_CODEHASH =
        SAFE_V1_4_1_COMPAT_HANDLER_BYTECODE_HASH;
    /// Runtime code of `SAFE_V1_4_1_COMPATIBILITY_FALLBACK_HANDLER`.
    bytes internal constant SAFE_V1_4_1_COMPATIBILITY_FALLBACK_HANDLER_RUNTIME_CODE =
        SAFE_V1_4_1_COMPAT_HANDLER_RUNTIME_CODE;

    /// The v1.4.1 `SafeToL2Setup`: delegatecalled from `setup`, it moves a
    /// proxy created on `SAFE_V1_4_1_L1_SINGLETON` to
    /// `SAFE_V1_4_1_L2_SINGLETON` on any chain but Ethereum mainnet.
    address internal constant SAFE_V1_4_1_TO_L2_SETUP = 0xBD89A1CE4DDe368FFAB0eC35506eEcE0b1fFdc54;
    /// Runtime code hash of `SAFE_V1_4_1_TO_L2_SETUP`.
    bytes32 internal constant SAFE_V1_4_1_TO_L2_SETUP_CODEHASH = SAFE_V1_4_1_SAFE_TO_L2_SETUP_BYTECODE_HASH;
    /// Runtime code of `SAFE_V1_4_1_TO_L2_SETUP`.
    bytes internal constant SAFE_V1_4_1_TO_L2_SETUP_RUNTIME_CODE = SAFE_V1_4_1_SAFE_TO_L2_SETUP_RUNTIME_CODE;

    /// Runtime code hash of a proxy created by the v1.4.1 `SafeProxyFactory`.
    /// The singleton lives in the proxy's storage, not its code, so every such
    /// proxy has this hash whatever its singleton.
    bytes32 internal constant SAFE_V1_4_1_PROXY_CODEHASH = SAFE_V1_4_1_SAFE_PROXY_BYTECODE_HASH;
    /// Runtime code of a v1.4.1-factory proxy.
    bytes internal constant SAFE_V1_4_1_PROXY_RUNTIME_CODE = SAFE_V1_4_1_SAFE_PROXY_RUNTIME_CODE;

    /// The canonical v1.3.0 `GnosisSafeProxyFactory`. Its
    /// `createProxyWithNonce` has the v1.4.1 `SafeProxyFactory` signature.
    address internal constant SAFE_V1_3_0_PROXY_FACTORY = 0xa6B71E26C5e0845f74c812102Ca7114b6a896AB2;

    /// Runtime code hash of a proxy created by the v1.3.0
    /// `GnosisSafeProxyFactory`. Such a proxy runs a v1.4.1 singleton once it
    /// has been migrated to one, so it is a v1.4.1 Safe on this proxy code.
    bytes32 internal constant SAFE_V1_3_0_PROXY_CODEHASH = SAFE_V1_3_0_GNOSIS_SAFE_PROXY_BYTECODE_HASH;
    /// Runtime code of a v1.3.0-factory proxy.
    bytes internal constant SAFE_V1_3_0_PROXY_RUNTIME_CODE = SAFE_V1_3_0_GNOSIS_SAFE_PROXY_RUNTIME_CODE;

    /// `keccak256("guard_manager.guard.address")`: the slot `GuardManager`
    /// holds the transaction guard in.
    bytes32 internal constant SAFE_GUARD_STORAGE_SLOT =
        0x4a204f620c8c5ccdca3fd54d003badd85ba500436a431f0cbda4f558c93c34c8;

    /// `keccak256("fallback_manager.handler.address")`: the slot
    /// `FallbackManager` holds the fallback handler in.
    bytes32 internal constant SAFE_FALLBACK_HANDLER_STORAGE_SLOT =
        0x6c9a6c4a39284e37ed1cf53d337577d14212a4870fb976a4366c693b939918d5;

    /// The head of `ModuleManager`'s module list, from which
    /// `getModulesPaginated` enumerates.
    address internal constant SAFE_MODULES_SENTINEL = address(0x1);

    /// Every canonical v1.4.1 contract is on the selected chain with its pinned
    /// code: the proxy factory, both singletons, `SafeToL2Setup` and the
    /// compatibility fallback handler. Safe's own `setup` checks neither of the
    /// last two, so a Safe is created against a chain missing either, and its
    /// `setupToL2` delegatecall or its fallback calls then reach no code.
    function assertCanonicalContracts() internal view {
        assertCodehash(SAFE_V1_4_1_PROXY_FACTORY, SAFE_V1_4_1_PROXY_FACTORY_CODEHASH);
        assertCodehash(SAFE_V1_4_1_L1_SINGLETON, SAFE_V1_4_1_L1_SINGLETON_CODEHASH);
        assertCodehash(SAFE_V1_4_1_L2_SINGLETON, SAFE_V1_4_1_L2_SINGLETON_CODEHASH);
        assertCodehash(SAFE_V1_4_1_TO_L2_SETUP, SAFE_V1_4_1_TO_L2_SETUP_CODEHASH);
        assertCodehash(SAFE_V1_4_1_COMPATIBILITY_FALLBACK_HANDLER, SAFE_V1_4_1_COMPATIBILITY_FALLBACK_HANDLER_CODEHASH);
    }

    /// The code at `account` hashes to `expected`. An account with no code
    /// hashes to `0` or to the empty-code hash, neither of which is ever a
    /// pinned contract's hash.
    /// @param account The account.
    /// @param expected The expected runtime code hash.
    function assertCodehash(address account, bytes32 expected) internal view {
        bytes32 actual = account.codehash;
        if (actual != expected) revert SafeCodehashMismatch(account, expected, actual);
    }

    /// `safe` is a genuine Safe v1.4.1: a v1.3.0 or v1.4.1 `SafeProxy` whose
    /// singleton is one of the two canonical v1.4.1 singletons, carrying its
    /// pinned code, and reporting `SAFE_V1_4_1_VERSION`. See "Trust order" for
    /// why the checks run in this order.
    /// @param safe The Safe.
    function assertIdentity(Safe safe) internal view {
        bytes32 proxyCodehash = address(safe).codehash;
        if (proxyCodehash != SAFE_V1_4_1_PROXY_CODEHASH && proxyCodehash != SAFE_V1_3_0_PROXY_CODEHASH) {
            revert SafeUnknownProxyCodehash(address(safe), proxyCodehash);
        }

        // Answered by the proxy code just pinned, not by the singleton.
        address singleton = IProxy(address(safe)).masterCopy();
        if (singleton != SAFE_V1_4_1_L1_SINGLETON && singleton != SAFE_V1_4_1_L2_SINGLETON) {
            revert SafeUnknownSingleton(address(safe), singleton);
        }
        bytes32 expectedSingletonCodehash = singleton == SAFE_V1_4_1_L1_SINGLETON
            ? SAFE_V1_4_1_L1_SINGLETON_CODEHASH
            : SAFE_V1_4_1_L2_SINGLETON_CODEHASH;
        bytes32 singletonCodehash = singleton.codehash;
        if (singletonCodehash != expectedSingletonCodehash) {
            revert SafeSingletonCodehashMismatch(address(safe), singleton, expectedSingletonCodehash, singletonCodehash);
        }

        string memory version = safe.VERSION();
        if (keccak256(bytes(version)) != keccak256(bytes(SAFE_V1_4_1_VERSION))) {
            revert SafeVersionMismatch(address(safe), version);
        }
    }

    /// The Safe has no module enabled. A module executes transactions without
    /// owner signatures.
    /// @param safe The Safe.
    function assertNoModules(Safe safe) internal view {
        // One is enough: any enabled module is the first on the first page.
        //slither-disable-next-line unused-return
        (address[] memory modules,) = safe.getModulesPaginated(SAFE_MODULES_SENTINEL, 1);
        if (modules.length != 0) revert SafeUnexpectedModule(address(safe), modules[0]);
    }

    /// The Safe has no transaction guard. A guard can block every transaction,
    /// including the one that would remove it.
    /// @param safe The Safe.
    function assertNoGuard(Safe safe) internal view {
        address guard = readStorageAddress(safe, SAFE_GUARD_STORAGE_SLOT);
        if (guard != address(0)) revert SafeUnexpectedGuard(address(safe), guard);
    }

    /// The Safe's fallback handler is `expected`. The fallback handler answers
    /// every selector the singleton does not implement.
    /// @param safe The Safe.
    /// @param expected The expected fallback handler.
    function assertFallbackHandler(Safe safe, address expected) internal view {
        address handler = readStorageAddress(safe, SAFE_FALLBACK_HANDLER_STORAGE_SLOT);
        if (handler != expected) revert SafeFallbackHandlerMismatch(address(safe), expected, handler);
    }

    /// `assertIdentity`, then no module, no guard, and the canonical
    /// compatibility fallback handler: a v1.4.1 Safe that nothing but its
    /// owners' signatures can move.
    /// @param safe The Safe.
    function assertLockedDown(Safe safe) internal view {
        assertIdentity(safe);
        assertNoModules(safe);
        assertNoGuard(safe);
        assertFallbackHandler(safe, SAFE_V1_4_1_COMPATIBILITY_FALLBACK_HANDLER);
    }

    /// The address in the low 20 bytes of the Safe's storage `slot`, the
    /// truncation Safe itself applies when it loads an address from a slot.
    /// @param safe The Safe.
    /// @param slot The slot.
    /// @return The address in `slot`.
    function readStorageAddress(Safe safe, bytes32 slot) internal view returns (address) {
        bytes memory word = safe.getStorageAt(uint256(slot), 1);
        // forge-lint: disable-next-line(unsafe-typecast)
        return address(uint160(uint256(bytes32(word))));
    }

    /// The Safe's `getOwners()` is exactly `expected`, in order. The order is
    /// Safe's linked-list order, which follows the history of owner additions,
    /// so two Safes with the same owners can differ in it; use
    /// `assertOwnersAsSet` where only membership matters.
    /// @param safe The Safe.
    /// @param expected The expected owners in `getOwners()` order.
    function assertOwnersInOrder(Safe safe, address[] memory expected) internal view {
        address[] memory actual = safe.getOwners();
        if (actual.length != expected.length) {
            revert SafeOwnerCountMismatch(address(safe), expected.length, actual.length);
        }
        for (uint256 i = 0; i < actual.length; i++) {
            if (actual[i] != expected[i]) revert SafeOwnerMismatch(address(safe), i, expected[i], actual[i]);
        }
    }

    /// The Safe's owners are exactly the members of `expected`, in any order.
    /// @dev Safe's owners are distinct, so with equal counts, every owner being
    /// in `expected` leaves no room in `expected` for a duplicate or for an
    /// address that is not an owner. Checking that every member of `expected`
    /// is an owner would not: it passes `expected` `[a, a, b]` against owners
    /// `[a, b, c]`.
    /// @param safe The Safe.
    /// @param expected The expected owners, in any order.
    function assertOwnersAsSet(Safe safe, address[] memory expected) internal view {
        address[] memory actual = safe.getOwners();
        if (actual.length != expected.length) {
            revert SafeOwnerCountMismatch(address(safe), expected.length, actual.length);
        }
        for (uint256 i = 0; i < actual.length; i++) {
            bool found = false;
            for (uint256 j = 0; j < expected.length; j++) {
                if (expected[j] == actual[i]) {
                    found = true;
                    break;
                }
            }
            if (!found) revert SafeUnexpectedOwner(address(safe), actual[i]);
        }
    }

    /// The Safe's threshold is `expected`.
    /// @param safe The Safe.
    /// @param expected The expected threshold.
    function assertThreshold(Safe safe, uint256 expected) internal view {
        uint256 actual = safe.getThreshold();
        if (actual != expected) revert SafeThresholdMismatch(address(safe), expected, actual);
    }
}
