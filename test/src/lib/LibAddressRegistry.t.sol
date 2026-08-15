// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibAddressRegistry} from "../../../src/lib/LibAddressRegistry.sol";
import {LibAddressRegistryDeploy} from "../../../src/lib/LibAddressRegistryDeploy.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {IAddressRegistryV1} from "../../../src/interface/IAddressRegistryV1.sol";
import {AddressRegistry, ADDRESS_REGISTRY_ROOT} from "../../../src/concrete/AddressRegistry.sol";
import {DELEGATION_DESIGNATOR_LENGTH, LibAccountCode} from "../../lib/LibAccountCode.sol";

/// @title LibAddressRegistryTest
/// Tests for `LibAddressRegistry`. The registry is not mocked: the real
/// `AddressRegistry` is deployed through the Zoltu factory, which is what puts
/// it at the pinned address with the pinned code hash, so every test runs
/// against the same bytecode a network would.
///
/// External wrappers are used for the library function so `vm.expectRevert`
/// lands at the correct call depth.
contract LibAddressRegistryTest is Test {
    /// Deploys `AddressRegistry` through the Zoltu factory, which lands it at
    /// the pinned address.
    /// @return The deployed registry.
    function deployRegistry() internal returns (IAddressRegistryV1) {
        LibRainDeploy.etchZoltuFactory(vm);
        return IAddressRegistryV1(LibRainDeploy.deployZoltu(type(AddressRegistry).creationCode));
    }

    /// External wrapper for `resolve` so that `vm.expectRevert` works at the
    /// correct call depth.
    /// @param name The name to resolve.
    /// @return The address bound to `name`.
    function externalResolve(bytes32 name) external view returns (address) {
        return LibAddressRegistry.resolve(name);
    }

    /// A bound name resolves to the address it is bound to.
    function testResolveRegistered(bytes32 name, address account) external {
        vm.assume(account != address(0));
        IAddressRegistryV1 registry = deployRegistry();

        vm.prank(ADDRESS_REGISTRY_ROOT);
        registry.register(name, account);

        assertEq(LibAddressRegistry.resolve(name), account);
    }

    /// `resolve` answers with the current binding, not the first one. A caller
    /// that wants an answer which cannot move has to read once and store it —
    /// the library deliberately does not pretend to offer that itself.
    function testResolveFollowsRebinding(bytes32 name, address bound, address account) external {
        vm.assume(bound != address(0));
        vm.assume(account != address(0));
        vm.assume(bound != account);
        IAddressRegistryV1 registry = deployRegistry();

        vm.prank(ADDRESS_REGISTRY_ROOT);
        registry.register(name, bound);
        assertEq(LibAddressRegistry.resolve(name), bound);

        vm.prank(ADDRESS_REGISTRY_ROOT);
        registry.register(name, account);
        assertEq(LibAddressRegistry.resolve(name), account);
    }

    /// An unbound name reverts. The registry, not this library, is what refuses
    /// to answer with the zero address, so the revert arrives unmodified.
    function testResolveUnregistered(bytes32 name) external {
        deployRegistry();

        vm.expectRevert(abi.encodeWithSelector(IAddressRegistryV1.NameNotRegistered.selector, name));
        this.externalResolve(name);
    }

    /// A chain with no registry deployed reverts on the code hash rather than
    /// calling into an empty account, which would otherwise succeed silently
    /// and return nothing.
    function testResolveNoRegistry(bytes32 name) external {
        assertEq(LibAddressRegistryDeploy.ADDRESS_REGISTRY_DEPLOYED_ADDRESS.code.length, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                LibAddressRegistry.UnexpectedAddressRegistryCodeHash.selector,
                LibAddressRegistryDeploy.ADDRESS_REGISTRY_DEPLOYED_CODEHASH,
                bytes32(0)
            )
        );
        this.externalResolve(name);
    }

    /// A chain where ORDINARY code — anything that is not a delegation
    /// designator — occupies the address reverts on the code hash, so a name is
    /// never resolved by code the caller did not compile against.
    ///
    /// The designator family is excluded here and covered by
    /// `testResolveDelegatedCode` instead. `LibAccountCode` is what says why:
    /// it is the other KIND of account code, not another value of this one, and
    /// the arbitrary-`bytes` domain this used to fuzz is not the domain of
    /// things an account can hold.
    function testResolveWrongCode(bytes32 name, bytes memory code) external {
        vm.assume(code.length > 0);
        vm.assume(!LibAccountCode.hasDelegationPrefix(code));
        vm.assume(keccak256(code) != LibAddressRegistryDeploy.ADDRESS_REGISTRY_DEPLOYED_CODEHASH);
        vm.etch(LibAddressRegistryDeploy.ADDRESS_REGISTRY_DEPLOYED_ADDRESS, code);

        vm.expectRevert(
            abi.encodeWithSelector(
                LibAddressRegistry.UnexpectedAddressRegistryCodeHash.selector,
                LibAddressRegistryDeploy.ADDRESS_REGISTRY_DEPLOYED_CODEHASH,
                keccak256(code)
            )
        );
        this.externalResolve(name);
    }

    /// A chain where an EOA has DELEGATED the registry address under EIP-7702
    /// reverts on the code hash too. This is the other way an address gets
    /// occupied, and the more dangerous one: the account carries only 23 bytes
    /// of designator while executing whatever the delegate holds, so an address
    /// that looks nothing like a registry can answer `get` however it likes.
    ///
    /// The code hash is what refuses it, without knowing anything about 7702:
    /// the account hashes its designator, never the delegate's code, so a
    /// delegation can never present the pinned registry's hash.
    ///
    /// A delegation to the zero address is the CLEARING form — it leaves the
    /// account with no code at all, which is `testResolveNoRegistry`, not this.
    /// @param name The name a caller would resolve.
    /// @param delegate The account the registry address is delegated to.
    function testResolveDelegatedCode(bytes32 name, address delegate) external {
        vm.assume(delegate != address(0));
        bytes memory designator = LibAccountCode.delegationDesignator(delegate);
        assertEq(designator.length, DELEGATION_DESIGNATOR_LENGTH);
        assertTrue(LibAccountCode.hasDelegationPrefix(designator));

        vm.etch(LibAddressRegistryDeploy.ADDRESS_REGISTRY_DEPLOYED_ADDRESS, designator);
        assertEq(LibAddressRegistryDeploy.ADDRESS_REGISTRY_DEPLOYED_ADDRESS.codehash, keccak256(designator));

        vm.expectRevert(
            abi.encodeWithSelector(
                LibAddressRegistry.UnexpectedAddressRegistryCodeHash.selector,
                LibAddressRegistryDeploy.ADDRESS_REGISTRY_DEPLOYED_CODEHASH,
                keccak256(designator)
            )
        );
        this.externalResolve(name);
    }
}
