// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";

import {IAddressRegistryV2} from "../../../src/interface/IAddressRegistryV2.sol";
import {AddressRegistry, ADDRESS_REGISTRY_ROOT} from "../../../src/concrete/AddressRegistry.sol";

/// @title AddressRegistryGetTest
/// @notice Tests for `AddressRegistry.get`: the value, the moment, the revert
/// for an unbound name, and that it is the registry's only reader.
contract AddressRegistryGetTest is Test {
    /// The registry under test.
    AddressRegistry internal sRegistry;

    function setUp() external {
        sRegistry = new AddressRegistry();
    }

    /// The value half of `get`.
    /// @param registry The registry to read.
    /// @param name The name to read.
    /// @return The value bound to `name`.
    function getValue(AddressRegistry registry, bytes32 name) internal view returns (bytes memory) {
        (bytes memory value,) = registry.get(name);
        return value;
    }

    /// The moment half of `get`.
    /// @param registry The registry to read.
    /// @param name The name to read.
    /// @return The moment `name` was most recently bound.
    function getMoment(AddressRegistry registry, bytes32 name) internal view returns (uint256) {
        (, uint256 registeredAt) = registry.get(name);
        return registeredAt;
    }

    /// A read of an unbound name reverts rather than returning an empty value.
    function testGetUnsetReverts(bytes32 name) external {
        vm.expectRevert(abi.encodeWithSelector(IAddressRegistryV2.NameNotRegistered.selector, name));
        getValue(sRegistry, name);
    }

    /// A read of a bound name returns exactly what was bound, and does not
    /// consume or alter the binding.
    function testGetReturnsRegistered(bytes32 name, bytes memory value) external {
        vm.assume(value.length > 0);

        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, value);

        assertEq(getValue(sRegistry, name), value);
        assertEq(getValue(sRegistry, name), value);
    }

    /// The value is returned byte for byte at every length either side of the
    /// boundary between the short and long storage encodings of `bytes`.
    function testGetReturnsEveryLength() external {
        uint256[7] memory lengths = [uint256(1), 30, 31, 32, 33, 64, 65];
        for (uint256 i = 0; i < lengths.length; i++) {
            bytes memory value = new bytes(lengths[i]);
            for (uint256 j = 0; j < value.length; j++) {
                value[j] = bytes1(uint8(j + 1));
            }
            bytes32 name = bytes32(i);
            vm.prank(ADDRESS_REGISTRY_ROOT);
            sRegistry.register(name, value);
            assertEq(getValue(sRegistry, name), value);
        }
    }

    /// An address binding is `abi.encode(account)`, and decodes back to the
    /// account it was bound as. The registry adds and strips nothing.
    function testGetAddressBindingDecodes(bytes32 name, address account) external {
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, abi.encode(account));

        bytes memory value = getValue(sRegistry, name);
        assertEq(value.length, 32);
        assertEq(abi.decode(value, (address)), account);
    }

    /// The zero address is a binding like any other: its encoding is a word of
    /// zeros, which is not empty, and only empty is how an unbound name reads.
    function testGetZeroAddressBindingIsBound(bytes32 name) external {
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, abi.encode(address(0)));

        bytes memory value = getValue(sRegistry, name);
        assertEq(value, new bytes(32));
        assertEq(abi.decode(value, (address)), address(0));
    }

    /// A value of any ABI shape round trips: here a dynamic tuple of the kind
    /// deploy configuration takes, a list of accounts with a threshold.
    function testGetStructuredBindingDecodes(bytes32 name, address[] memory accounts, uint256 threshold) external {
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, abi.encode(accounts, threshold));

        (address[] memory gotAccounts, uint256 gotThreshold) =
            abi.decode(getValue(sRegistry, name), (address[], uint256));
        assertEq(gotAccounts, accounts);
        assertEq(gotThreshold, threshold);
    }

    /// Names are opaque: nothing about a name's bytes changes how it is stored
    /// or read.
    function testGetOpaqueNames(bytes memory value) external {
        vm.assume(value.length > 0);

        bytes32[3] memory names = [bytes32(0), bytes32(uint256(1)), bytes32(type(uint256).max)];
        for (uint256 i = 0; i < names.length; i++) {
            AddressRegistry registry = new AddressRegistry();
            vm.prank(ADDRESS_REGISTRY_ROOT);
            registry.register(names[i], value);
            assertEq(getValue(registry, names[i]), value);
        }
    }

    /// The bindings mapping is not `public`, so the getter a `public` mapping
    /// would generate does not exist.
    function testGetNoGeneratedMappingGetter(bytes32 name) external {
        (bool success,) = address(sRegistry).call(abi.encodeWithSignature("sBindings(bytes32)", name));
        assertFalse(success);
    }

    /// An unknown selector reverts: no fallback, no receive, nothing beyond the
    /// two `IAddressRegistryV2` functions.
    function testGetNoOtherEntryPoint(bytes4 selector, bytes32 name) external {
        vm.assume(selector != IAddressRegistryV2.get.selector);
        vm.assume(selector != IAddressRegistryV2.register.selector);

        (bool success,) = address(sRegistry).call(abi.encodeWithSelector(selector, name, abi.encode(address(this))));
        assertFalse(success);
    }

    /// The ABI is exactly the two `IAddressRegistryV2` functions, counted
    /// rather than sampled.
    function testGetAbiIsExactlyTheInterface() external view {
        string[] memory signatures =
            vm.parseJsonKeys(vm.readFile("out/AddressRegistry.sol/AddressRegistry.json"), "$.methodIdentifiers");

        assertEq(signatures.length, 2);
        assertEq(signatures[0], "get(bytes32)");
        assertEq(signatures[1], "register(bytes32,bytes)");
    }

    /// The registry takes no value on any path: ether sent with or without
    /// calldata is refused, and its balance stays zero.
    function testGetNoValueEntryPoint(bytes32 name, bytes memory value) external {
        vm.assume(value.length > 0);
        vm.deal(ADDRESS_REGISTRY_ROOT, 3);

        vm.prank(ADDRESS_REGISTRY_ROOT);
        (bool bare,) = address(sRegistry).call{value: 1}("");
        assertFalse(bare);

        vm.prank(ADDRESS_REGISTRY_ROOT);
        (bool bound_,) = address(sRegistry).call{value: 1}(abi.encodeCall(IAddressRegistryV2.register, (name, value)));
        assertFalse(bound_);

        vm.prank(ADDRESS_REGISTRY_ROOT);
        (bool read,) = address(sRegistry).call{value: 1}(abi.encodeCall(IAddressRegistryV2.get, (name)));
        assertFalse(read);

        assertEq(address(sRegistry).balance, 0);
    }

    /// `get` answers with the moment the binding was made.
    function testGetReturnsMoment(bytes32 name, bytes memory value, uint256 time) external {
        vm.assume(value.length > 0);

        time = bound(time, 1, type(uint256).max);
        vm.warp(time);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, value);

        (bytes memory got, uint256 registeredAt) = sRegistry.get(name);
        assertEq(got, value);
        assertEq(registeredAt, time);
    }

    /// The moment does not drift as the chain advances: it reads back unchanged
    /// however long afterwards, so an age against `block.timestamp` grows.
    function testGetMomentStableAsTimePasses(bytes32 name, bytes memory value, uint256 time, uint256 elapsed)
        external
    {
        vm.assume(value.length > 0);
        elapsed = bound(elapsed, 0, type(uint256).max - 1);
        time = bound(time, 1, type(uint256).max - elapsed);

        vm.warp(time);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, value);

        vm.warp(time + elapsed);
        assertEq(getMoment(sRegistry, name), time);
        assertEq(block.timestamp - getMoment(sRegistry, name), elapsed);
    }

    /// The moment `get` answers with is never zero.
    function testGetMomentNeverZero(bytes32 name, bytes memory value, uint256 time) external {
        vm.assume(value.length > 0);
        time = bound(time, 1, type(uint256).max);

        vm.warp(time);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, value);

        (bytes memory got, uint256 registeredAt) = sRegistry.get(name);
        assertEq(got, value);
        assertTrue(registeredAt != 0);
        assertEq(registeredAt, time);
    }

    /// Moments are per name.
    function testGetMomentDistinctNames(
        bytes32 nameA,
        bytes32 nameB,
        bytes memory valueA,
        bytes memory valueB,
        uint256 timeA,
        uint256 timeB
    ) external {
        vm.assume(nameA != nameB);
        vm.assume(valueA.length > 0);
        vm.assume(valueB.length > 0);

        timeA = bound(timeA, 1, type(uint256).max);
        vm.warp(timeA);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(nameA, valueA);

        timeB = bound(timeB, 1, type(uint256).max);
        vm.warp(timeB);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(nameB, valueB);

        assertEq(getMoment(sRegistry, nameA), timeA);
        assertEq(getMoment(sRegistry, nameB), timeB);
    }

    /// The moment is stored at full width: clocks past every narrower width the
    /// moment could have been stored in are recorded exactly, never truncated
    /// into an older-looking moment.
    function testGetMomentFullWidth(bytes32 name, bytes memory value) external {
        vm.assume(value.length > 0);

        uint256[4] memory times = [
            uint256(type(uint64).max) + 1,
            uint256(type(uint96).max) + 1,
            uint256(type(uint128).max) + 1,
            type(uint256).max
        ];
        for (uint256 i = 0; i < times.length; i++) {
            vm.warp(times[i]);
            vm.prank(ADDRESS_REGISTRY_ROOT);
            sRegistry.register(name, value);
            assertEq(getMoment(sRegistry, name), times[i]);
        }
    }

    /// Across a run of rotations the value and the moment are always replaced
    /// together, never one lagging the other.
    function testGetValueAndMomentMoveTogether(bytes32 name, bytes[] memory values, uint256 start) external {
        vm.assume(values.length > 0);
        start = bound(start, 1, type(uint256).max - values.length);
        for (uint256 i = 0; i < values.length; i++) {
            vm.assume(values[i].length > 0);
        }

        for (uint256 i = 0; i < values.length; i++) {
            vm.warp(start + i);
            vm.prank(ADDRESS_REGISTRY_ROOT);
            sRegistry.register(name, values[i]);

            (bytes memory got, uint256 registeredAt) = sRegistry.get(name);
            assertEq(got, values[i]);
            assertEq(registeredAt, start + i);
        }
    }
}
