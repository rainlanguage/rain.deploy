// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibAddressRegistry} from "../../../src/lib/LibAddressRegistry.sol";
import {LibAddressRegistryDeploy} from "../../../src/lib/LibAddressRegistryDeploy.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {IAddressRegistryV1} from "../../../src/interface/IAddressRegistryV1.sol";
import {AddressRegistry, ADDRESS_REGISTRY_ROOT} from "../../../src/concrete/AddressRegistry.sol";

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

    /// A chain where something other than the pinned registry occupies the
    /// address reverts on the code hash, so a name is never resolved by code
    /// the caller did not compile against.
    function testResolveWrongCode(bytes32 name, bytes memory code) external {
        vm.assume(code.length > 0);
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
}
