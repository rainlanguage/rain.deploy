// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";

import {IAddressRegistryV1} from "../../../src/interface/IAddressRegistryV1.sol";
import {AddressRegistry, ADDRESS_REGISTRY_ROOT} from "../../../src/concrete/AddressRegistry.sol";

/// @title AddressRegistryGetTest
/// @notice A test suite for `AddressRegistry.get`: it answers a bound name with
/// its address and an unbound name with a revert, and it is the only reader.
contract AddressRegistryGetTest is Test {
    /// The registry under test. Stateful, so a fresh one per test.
    AddressRegistry internal sRegistry;

    function setUp() external {
        sRegistry = new AddressRegistry();
    }

    /// A read of an unbound name reverts rather than returning the zero
    /// address, so a caller cannot proceed on a name nobody bound by forgetting
    /// to check.
    function testGetUnsetReverts(bytes32 name) external {
        vm.expectRevert(abi.encodeWithSelector(IAddressRegistryV1.NameNotRegistered.selector, name));
        sRegistry.get(name);
    }

    /// A read of a bound name returns exactly what was bound, and reading does
    /// not consume or alter the binding.
    function testGetReturnsRegistered(bytes32 name, address account) external {
        vm.assume(account != address(0));

        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, account);

        assertEq(sRegistry.get(name), account);
        assertEq(sRegistry.get(name), account);
    }

    /// Names are opaque: nothing about a name's bytes changes how it is stored
    /// or read, including names a string-hashing convention would never
    /// produce.
    function testGetOpaqueNames(address account) external {
        vm.assume(account != address(0));

        bytes32[3] memory names = [bytes32(0), bytes32(uint256(1)), bytes32(type(uint256).max)];
        for (uint256 i = 0; i < names.length; i++) {
            AddressRegistry registry = new AddressRegistry();
            vm.prank(ADDRESS_REGISTRY_ROOT);
            registry.register(names[i], account);
            assertEq(registry.get(names[i]), account);
        }
    }

    /// `get` is the only reader. The bindings mapping is not `public`, so the
    /// getter a `public` mapping would generate — which answers an unbound name
    /// with the zero address, the exact silent failure `get` reverts to prevent
    /// — does not exist.
    function testGetNoGeneratedMappingGetter(bytes32 name) external {
        (bool success,) = address(sRegistry).call(abi.encodeWithSignature("sAddresses(bytes32)", name));
        assertFalse(success);
    }

    /// There is no other entry point at all: no fallback, no receive, and
    /// nothing beyond the two `IAddressRegistryV1` functions, so an unknown
    /// selector reverts instead of being silently absorbed.
    function testGetNoOtherEntryPoint(bytes4 selector, bytes32 name) external {
        vm.assume(selector != IAddressRegistryV1.get.selector);
        vm.assume(selector != IAddressRegistryV1.register.selector);

        (bool success,) = address(sRegistry).call(abi.encodeWithSelector(selector, name, address(this)));
        assertFalse(success);
    }
}
