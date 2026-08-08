// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibAddressRegistry} from "../../../src/lib/LibAddressRegistry.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {IAddressRegistryV1} from "../../../src/interface/IAddressRegistryV1.sol";
import {ADDRESS_REGISTRY_CREATION_CODE, ADDRESS_REGISTRY_ROOT} from "../../lib/AddressRegistryPins.sol";

/// @title LibAddressRegistryTest
/// Tests for `LibAddressRegistry`. The registry is not mocked: the real
/// `AddressRegistry` creation code is deployed through the Zoltu factory, which
/// is what puts it at the pinned address with the pinned code hash, so every
/// test here runs against the same bytecode a network would.
///
/// External wrappers are used for the library function so `vm.expectRevert`
/// lands at the correct call depth.
contract LibAddressRegistryTest is Test {
    /// Deploys the pinned `AddressRegistry` creation code through the Zoltu
    /// factory, which lands it at `LibAddressRegistry.ADDRESS_REGISTRY`.
    /// @return The deployed registry.
    function deployRegistry() internal returns (IAddressRegistryV1) {
        LibRainDeploy.etchZoltuFactory(vm);
        return IAddressRegistryV1(LibRainDeploy.deployZoltu(ADDRESS_REGISTRY_CREATION_CODE));
    }

    /// External wrapper for `resolve` so that `vm.expectRevert` works at the
    /// correct call depth.
    /// @param name The name to resolve.
    /// @return The address bound to `name`.
    function externalResolve(bytes32 name) external view returns (address) {
        return LibAddressRegistry.resolve(name);
    }

    /// The pins are derived from the registry's creation code, not asserted:
    /// deploying that creation code through the Zoltu factory MUST land at
    /// `ADDRESS_REGISTRY` with `ADDRESS_REGISTRY_CODEHASH`. The address is also
    /// derivable without deploying at all, and both derivations MUST agree.
    function testAddressRegistryPinsAreDerivable() external {
        assertEq(LibRainDeploy.zoltuAddress(ADDRESS_REGISTRY_CREATION_CODE), LibAddressRegistry.ADDRESS_REGISTRY);

        address deployed = address(deployRegistry());
        assertEq(deployed, LibAddressRegistry.ADDRESS_REGISTRY);
        assertEq(deployed.codehash, LibAddressRegistry.ADDRESS_REGISTRY_CODEHASH);
        assertEq(keccak256(deployed.code), LibAddressRegistry.ADDRESS_REGISTRY_CODEHASH);
    }

    /// A bound name resolves to the address it is bound to.
    function testResolveRegistered(bytes32 name, address account) external {
        vm.assume(account != address(0));
        IAddressRegistryV1 registry = deployRegistry();

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
        assertEq(LibAddressRegistry.ADDRESS_REGISTRY.code.length, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                LibAddressRegistry.UnexpectedAddressRegistryCodeHash.selector,
                LibAddressRegistry.ADDRESS_REGISTRY_CODEHASH,
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
        vm.assume(keccak256(code) != LibAddressRegistry.ADDRESS_REGISTRY_CODEHASH);
        vm.etch(LibAddressRegistry.ADDRESS_REGISTRY, code);

        vm.expectRevert(
            abi.encodeWithSelector(
                LibAddressRegistry.UnexpectedAddressRegistryCodeHash.selector,
                LibAddressRegistry.ADDRESS_REGISTRY_CODEHASH,
                keccak256(code)
            )
        );
        this.externalResolve(name);
    }
}
