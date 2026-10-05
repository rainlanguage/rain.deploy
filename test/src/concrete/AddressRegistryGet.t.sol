// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";

import {IAddressRegistryV1} from "../../../src/interface/IAddressRegistryV1.sol";
import {AddressRegistry, ADDRESS_REGISTRY_ROOT} from "../../../src/concrete/AddressRegistry.sol";

/// @title AddressRegistryGetTest
/// @notice Tests for `AddressRegistry.get`: the address, the moment, the revert
/// for an unbound name, and that it is the registry's only reader.
contract AddressRegistryGetTest is Test {
    /// The registry under test.
    AddressRegistry internal sRegistry;

    function setUp() external {
        sRegistry = new AddressRegistry();
    }

    /// The address half of `get`.
    /// @param registry The registry to read.
    /// @param name The name to read.
    /// @return The address bound to `name`.
    function getAddress(AddressRegistry registry, bytes32 name) internal view returns (address) {
        (address account,) = registry.get(name);
        return account;
    }

    /// The moment half of `get`.
    /// @param registry The registry to read.
    /// @param name The name to read.
    /// @return The moment `name` was most recently bound.
    function getMoment(AddressRegistry registry, bytes32 name) internal view returns (uint256) {
        (, uint256 registeredAt) = registry.get(name);
        return registeredAt;
    }

    /// A read of an unbound name reverts rather than returning the zero address.
    function testGetUnsetReverts(bytes32 name) external {
        vm.expectRevert(abi.encodeWithSelector(IAddressRegistryV1.NameNotRegistered.selector, name));
        getAddress(sRegistry, name);
    }

    /// A read of a bound name returns exactly what was bound, and does not
    /// consume or alter the binding.
    function testGetReturnsRegistered(bytes32 name, address account) external {
        vm.assume(account != address(0));

        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, account);

        assertEq(getAddress(sRegistry, name), account);
        assertEq(getAddress(sRegistry, name), account);
    }

    /// Names are opaque: nothing about a name's bytes changes how it is stored
    /// or read.
    function testGetOpaqueNames(address account) external {
        vm.assume(account != address(0));

        bytes32[3] memory names = [bytes32(0), bytes32(uint256(1)), bytes32(type(uint256).max)];
        for (uint256 i = 0; i < names.length; i++) {
            AddressRegistry registry = new AddressRegistry();
            vm.prank(ADDRESS_REGISTRY_ROOT);
            registry.register(names[i], account);
            assertEq(getAddress(registry, names[i]), account);
        }
    }

    /// The bindings mapping is not `public`, so the getter a `public` mapping
    /// would generate does not exist.
    function testGetNoGeneratedMappingGetter(bytes32 name) external {
        (bool success,) = address(sRegistry).call(abi.encodeWithSignature("sBindings(bytes32)", name));
        assertFalse(success);
    }

    /// An unknown selector reverts: no fallback, no receive, nothing beyond the
    /// two `IAddressRegistryV1` functions.
    function testGetNoOtherEntryPoint(bytes4 selector, bytes32 name) external {
        vm.assume(selector != IAddressRegistryV1.get.selector);
        vm.assume(selector != IAddressRegistryV1.register.selector);

        (bool success,) = address(sRegistry).call(abi.encodeWithSelector(selector, name, address(this)));
        assertFalse(success);
    }

    /// The ABI is exactly the two `IAddressRegistryV1` functions, counted
    /// rather than sampled.
    function testGetAbiIsExactlyTheInterface() external view {
        string[] memory signatures =
            vm.parseJsonKeys(vm.readFile("out/AddressRegistry.sol/AddressRegistry.json"), "$.methodIdentifiers");

        assertEq(signatures.length, 2);
        assertEq(signatures[0], "get(bytes32)");
        assertEq(signatures[1], "register(bytes32,address)");
    }

    /// The registry takes no value on any path: ether sent with or without
    /// calldata is refused, and its balance stays zero.
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

    /// `get` answers with the moment the binding was made.
    function testGetReturnsMoment(bytes32 name, address account, uint96 time) external {
        vm.assume(account != address(0));

        time = uint96(bound(time, 1, type(uint96).max));
        vm.warp(time);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, account);

        (address got, uint256 registeredAt) = sRegistry.get(name);
        assertEq(got, account);
        assertEq(registeredAt, time);
    }

    /// The moment does not drift as the chain advances: it reads back unchanged
    /// however long afterwards, so an age against `block.timestamp` grows.
    function testGetMomentStableAsTimePasses(bytes32 name, address account, uint96 time, uint96 elapsed) external {
        vm.assume(account != address(0));
        elapsed = uint96(bound(elapsed, 0, type(uint96).max - 1));
        time = uint96(bound(time, 1, type(uint96).max - elapsed));

        vm.warp(time);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, account);

        vm.warp(uint256(time) + elapsed);
        assertEq(getMoment(sRegistry, name), time);
        assertEq(block.timestamp - getMoment(sRegistry, name), elapsed);
    }

    /// The moment `get` answers with is never zero.
    function testGetMomentNeverZero(bytes32 name, address account, uint96 time) external {
        vm.assume(account != address(0));
        time = uint96(bound(time, 1, type(uint96).max));

        vm.warp(time);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, account);

        (address got, uint256 registeredAt) = sRegistry.get(name);
        assertEq(got, account);
        assertTrue(registeredAt != 0);
        assertEq(registeredAt, time);
    }

    /// Moments are per name.
    function testGetMomentDistinctNames(
        bytes32 nameA,
        bytes32 nameB,
        address accountA,
        address accountB,
        uint96 timeA,
        uint96 timeB
    ) external {
        vm.assume(nameA != nameB);
        vm.assume(accountA != address(0));
        vm.assume(accountB != address(0));

        timeA = uint96(bound(timeA, 1, type(uint96).max));
        vm.warp(timeA);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(nameA, accountA);

        timeB = uint96(bound(timeB, 1, type(uint96).max));
        vm.warp(timeB);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(nameB, accountB);

        assertEq(getMoment(sRegistry, nameA), timeA);
        assertEq(getMoment(sRegistry, nameB), timeB);
    }

    /// The widest moment that fits is accepted.
    function testGetMomentMaxAccepted(bytes32 name, address account) external {
        vm.assume(account != address(0));

        vm.warp(type(uint96).max);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, account);

        assertEq(getMoment(sRegistry, name), type(uint96).max);
    }

    /// A timestamp too wide for the moment is REFUSED, never narrowed, and the
    /// name is left unbound.
    function testGetMomentOverflowRejected(bytes32 name, address account, uint256 time) external {
        vm.assume(account != address(0));
        time = bound(time, uint256(type(uint96).max) + 1, type(uint256).max);

        vm.warp(time);
        vm.expectRevert(abi.encodeWithSelector(AddressRegistry.TimestampOverflow.selector, time));
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, account);

        vm.expectRevert(abi.encodeWithSelector(IAddressRegistryV1.NameNotRegistered.selector, name));
        getAddress(sRegistry, name);
    }

    /// An overflowing `register` leaves an existing binding and its moment
    /// exactly as they were, rather than half-writing one.
    function testGetMomentOverflowLeavesBindingIntact(
        bytes32 name,
        address bound_,
        address account,
        uint96 first,
        uint256 time
    ) external {
        vm.assume(bound_ != address(0));
        vm.assume(account != address(0));
        time = bound(time, uint256(type(uint96).max) + 1, type(uint256).max);
        first = uint96(bound(first, 1, type(uint96).max));

        vm.warp(first);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, bound_);

        vm.warp(time);
        vm.expectRevert(abi.encodeWithSelector(AddressRegistry.TimestampOverflow.selector, time));
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, account);

        (address got, uint256 registeredAt) = sRegistry.get(name);
        assertEq(got, bound_);
        assertEq(registeredAt, first);
    }

    /// Across a run of rotations the address and the moment are always replaced
    /// together, never one lagging the other.
    function testGetAddressAndMomentMoveTogether(bytes32 name, address[] memory accounts, uint96 start) external {
        vm.assume(accounts.length > 0);
        start = uint96(bound(start, 1, type(uint96).max - accounts.length));
        for (uint256 i = 0; i < accounts.length; i++) {
            vm.assume(accounts[i] != address(0));
        }

        for (uint256 i = 0; i < accounts.length; i++) {
            vm.warp(uint256(start) + i);
            vm.prank(ADDRESS_REGISTRY_ROOT);
            sRegistry.register(name, accounts[i]);

            (address got, uint256 registeredAt) = sRegistry.get(name);
            assertEq(got, accounts[i]);
            assertEq(registeredAt, uint256(start) + i);
        }
    }
}
