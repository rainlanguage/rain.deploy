// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";

import {IConfigRegistryV2} from "../../../src/interface/IConfigRegistryV2.sol";
import {ConfigRegistry} from "../../../src/concrete/ConfigRegistry.sol";
import {LibConfigRegistryRead} from "../../lib/LibConfigRegistryRead.sol";

/// @title ConfigRegistryGetTest
/// @notice Tests for `ConfigRegistry.getV2`: the value, the moment, the revert
/// for an unbound name, and that it is the registry's only reader.
contract ConfigRegistryGetTest is Test {
    /// The authority most tests bind and read under. Any account is one.
    address internal constant AUTHORITY = address(0xA11CE);

    /// The registry under test.
    ConfigRegistry internal sRegistry;

    function setUp() external {
        sRegistry = new ConfigRegistry();
    }

    /// A read of an unbound name reverts rather than returning an empty value.
    function testGetUnsetReverts(bytes32 name) external {
        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV2.NameNotRegistered.selector, AUTHORITY, name));
        LibConfigRegistryRead.getValue(sRegistry, AUTHORITY, name);
    }

    /// A name another authority has bound is still unbound under this one,
    /// and the revert names the authority that was asked.
    function testGetOtherAuthorityBindingIsUnbound(address other, address asked, bytes32 name, bytes memory value)
        external
    {
        vm.assume(other != asked);
        vm.assume(value.length > 0);

        vm.prank(other);
        sRegistry.registerV2(other, name, value);

        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV2.NameNotRegistered.selector, asked, name));
        LibConfigRegistryRead.getValue(sRegistry, asked, name);
    }

    /// The zero authority never binds anything, so every name reads unbound
    /// under it.
    function testGetZeroAuthorityUnbound(bytes32 name, bytes memory value) external {
        vm.assume(value.length > 0);
        vm.prank(AUTHORITY);
        sRegistry.registerV2(AUTHORITY, name, value);

        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV2.NameNotRegistered.selector, address(0), name));
        LibConfigRegistryRead.getValue(sRegistry, address(0), name);
    }

    /// A read of a bound name returns exactly what was bound, and does not
    /// consume or alter the binding.
    function testGetReturnsRegistered(bytes32 name, bytes memory value) external {
        vm.assume(value.length > 0);

        vm.prank(AUTHORITY);
        sRegistry.registerV2(AUTHORITY, name, value);

        assertEq(LibConfigRegistryRead.getValue(sRegistry, AUTHORITY, name), value);
        assertEq(LibConfigRegistryRead.getValue(sRegistry, AUTHORITY, name), value);
    }

    /// The value is returned byte for byte at every length either side of the
    /// boundary between the short and long storage encodings of `bytes`.
    function testGetReturnsEveryLength() external {
        uint256[7] memory lengths = [uint256(1), 30, 31, 32, 33, 64, 65];
        for (uint256 i = 0; i < lengths.length; i++) {
            bytes memory value = vm.randomBytes(lengths[i]);
            bytes32 name = bytes32(i);
            vm.prank(AUTHORITY);
            sRegistry.registerV2(AUTHORITY, name, value);
            assertEq(LibConfigRegistryRead.getValue(sRegistry, AUTHORITY, name), value);
        }
    }

    /// An address binding is `abi.encode(account)`, and decodes back to the
    /// account it was bound as. The registry adds and strips nothing.
    function testGetAddressBindingDecodes(bytes32 name, address account) external {
        vm.prank(AUTHORITY);
        sRegistry.registerV2(AUTHORITY, name, abi.encode(account));

        bytes memory value = LibConfigRegistryRead.getValue(sRegistry, AUTHORITY, name);
        assertEq(value.length, 32);
        assertEq(abi.decode(value, (address)), account);
    }

    /// The zero address is a binding like any other: its encoding is a word of
    /// zeros, which is not empty, and only empty is how an unbound name reads.
    function testGetZeroAddressBindingIsBound(bytes32 name) external {
        vm.prank(AUTHORITY);
        sRegistry.registerV2(AUTHORITY, name, abi.encode(address(0)));

        bytes memory value = LibConfigRegistryRead.getValue(sRegistry, AUTHORITY, name);
        assertEq(value, new bytes(32));
        assertEq(abi.decode(value, (address)), address(0));
    }

    /// A value of any ABI shape round trips: here a dynamic tuple of the kind
    /// deploy configuration takes, a list of accounts with a threshold.
    function testGetStructuredBindingDecodes(bytes32 name, address[] memory accounts, uint256 threshold) external {
        vm.prank(AUTHORITY);
        sRegistry.registerV2(AUTHORITY, name, abi.encode(accounts, threshold));

        (address[] memory gotAccounts, uint256 gotThreshold) =
            abi.decode(LibConfigRegistryRead.getValue(sRegistry, AUTHORITY, name), (address[], uint256));
        assertEq(gotAccounts, accounts);
        assertEq(gotThreshold, threshold);
    }

    /// Names are opaque: nothing about a name's bytes changes how it is stored
    /// or read.
    function testGetOpaqueNames(bytes memory value) external {
        vm.assume(value.length > 0);

        bytes32[3] memory names = [bytes32(0), bytes32(uint256(1)), bytes32(type(uint256).max)];
        for (uint256 i = 0; i < names.length; i++) {
            ConfigRegistry registry = new ConfigRegistry();
            vm.prank(AUTHORITY);
            registry.registerV2(AUTHORITY, names[i], value);
            assertEq(LibConfigRegistryRead.getValue(registry, AUTHORITY, names[i]), value);
        }
    }

    /// The bindings mapping is not `public`, so the getter a `public` mapping
    /// would generate does not exist.
    function testGetNoGeneratedMappingGetter(address authority, bytes32 name) external {
        (bool success,) =
            address(sRegistry).call(abi.encodeWithSignature("sBindings(address,bytes32)", authority, name));
        assertFalse(success);
    }

    /// An unknown selector reverts: no fallback, no receive, nothing beyond the
    /// five `IConfigRegistryV2` functions.
    function testGetNoOtherEntryPoint(bytes4 selector, bytes32 name) external {
        vm.assume(selector != IConfigRegistryV2.getV2.selector);
        vm.assume(selector != IConfigRegistryV2.registerV2.selector);
        vm.assume(selector != IConfigRegistryV2.approveV2.selector);
        vm.assume(selector != IConfigRegistryV2.revokeV2.selector);
        vm.assume(selector != IConfigRegistryV2.approvedV2.selector);

        (bool success,) = address(sRegistry).call(abi.encodeWithSelector(selector, name, abi.encode(address(this))));
        assertFalse(success);
    }

    /// The ABI is exactly the five `IConfigRegistryV2` functions, counted
    /// rather than sampled.
    function testGetAbiIsExactlyTheInterface() external view {
        string[] memory signatures =
            vm.parseJsonKeys(vm.readFile("out/ConfigRegistry.sol/ConfigRegistry.json"), "$.methodIdentifiers");

        assertEq(signatures.length, 5);
        assertEq(signatures[0], "approveV2(bytes32,address)");
        assertEq(signatures[1], "approvedV2(address,bytes32,address)");
        assertEq(signatures[2], "getV2(address,bytes32)");
        assertEq(signatures[3], "registerV2(address,bytes32,bytes)");
        assertEq(signatures[4], "revokeV2(bytes32,address)");
    }

    /// The registry takes no value on any path: ether sent with or without
    /// calldata is refused, and its balance stays zero.
    function testGetNoValueEntryPoint(bytes32 name, bytes memory value) external {
        vm.assume(value.length > 0);
        vm.deal(AUTHORITY, 3);

        vm.prank(AUTHORITY);
        (bool bare,) = address(sRegistry).call{value: 1}("");
        assertFalse(bare);

        vm.prank(AUTHORITY);
        (bool registered,) =
            address(sRegistry).call{value: 1}(abi.encodeCall(IConfigRegistryV2.registerV2, (AUTHORITY, name, value)));
        assertFalse(registered);

        vm.prank(AUTHORITY);
        (bool read,) = address(sRegistry).call{value: 1}(abi.encodeCall(IConfigRegistryV2.getV2, (AUTHORITY, name)));
        assertFalse(read);

        assertEq(address(sRegistry).balance, 0);
    }

    /// `getV2` answers with the moment the binding was made.
    function testGetReturnsMoment(bytes32 name, bytes memory value, uint256 time) external {
        vm.assume(value.length > 0);

        time = bound(time, 1, type(uint256).max);
        vm.warp(time);
        vm.prank(AUTHORITY);
        sRegistry.registerV2(AUTHORITY, name, value);

        (bytes memory got, uint256 registeredAt) = sRegistry.getV2(AUTHORITY, name);
        assertEq(got, value);
        assertEq(registeredAt, time);
    }

    /// The moment does not drift as the chain advances: it reads back unchanged
    /// however long afterwards, so an age against `block.timestamp` grows.
    function testGetMomentStableAsTimePasses(bytes32 name, bytes memory value, uint256 time, uint256 elapsed) external {
        vm.assume(value.length > 0);
        elapsed = bound(elapsed, 0, type(uint256).max - 1);
        time = bound(time, 1, type(uint256).max - elapsed);

        vm.warp(time);
        vm.prank(AUTHORITY);
        sRegistry.registerV2(AUTHORITY, name, value);

        vm.warp(time + elapsed);
        assertEq(LibConfigRegistryRead.getMoment(sRegistry, AUTHORITY, name), time);
        assertEq(block.timestamp - LibConfigRegistryRead.getMoment(sRegistry, AUTHORITY, name), elapsed);
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
        vm.prank(AUTHORITY);
        sRegistry.registerV2(AUTHORITY, nameA, valueA);

        timeB = bound(timeB, 1, type(uint256).max);
        vm.warp(timeB);
        vm.prank(AUTHORITY);
        sRegistry.registerV2(AUTHORITY, nameB, valueB);

        assertEq(LibConfigRegistryRead.getMoment(sRegistry, AUTHORITY, nameA), timeA);
        assertEq(LibConfigRegistryRead.getMoment(sRegistry, AUTHORITY, nameB), timeB);
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
            vm.prank(AUTHORITY);
            sRegistry.registerV2(AUTHORITY, name, value);
            assertEq(LibConfigRegistryRead.getMoment(sRegistry, AUTHORITY, name), times[i]);
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
            vm.prank(AUTHORITY);
            sRegistry.registerV2(AUTHORITY, name, values[i]);

            (bytes memory got, uint256 registeredAt) = sRegistry.getV2(AUTHORITY, name);
            assertEq(got, values[i]);
            assertEq(registeredAt, start + i);
        }
    }
}
