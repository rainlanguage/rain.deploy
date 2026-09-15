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

    /// The ABI is exactly the two `IAddressRegistryV1` functions, counted
    /// rather than sampled. A fuzz over unknown selectors cannot see a reader
    /// added under a name of its own, and such a reader is precisely what the
    /// interface forbids: it would answer an unbound name with the zero
    /// address, the silent failure `get` reverts to prevent.
    function testGetAbiIsExactlyTheInterface() external view {
        string[] memory signatures =
            vm.parseJsonKeys(vm.readFile("out/AddressRegistry.sol/AddressRegistry.json"), "$.methodIdentifiers");

        assertEq(signatures.length, 2);
        assertEq(signatures[0], "get(bytes32)");
        assertEq(signatures[1], "register(bytes32,address)");
    }

    /// The registry takes no value on any path. Neither entry point is payable
    /// and there is no `receive`, so ether sent with or without calldata is
    /// refused rather than trapped in a contract that holds no way to move it
    /// out again.
    function testGetNoValueEntryPoint(bytes32 name, address account) external {
        vm.assume(account != address(0));
        vm.deal(ADDRESS_REGISTRY_ROOT, 3);

        vm.prank(ADDRESS_REGISTRY_ROOT);
        (bool bare,) = address(sRegistry).call{value: 1}("");
        assertFalse(bare);

        vm.prank(ADDRESS_REGISTRY_ROOT);
        (bool bound,) = address(sRegistry).call{value: 1}(abi.encodeCall(IAddressRegistryV1.register, (name, account)));
        assertFalse(bound);

        vm.prank(ADDRESS_REGISTRY_ROOT);
        (bool read,) = address(sRegistry).call{value: 1}(abi.encodeCall(IAddressRegistryV1.get, (name)));
        assertFalse(read);

        assertEq(address(sRegistry).balance, 0);
    }
}
