// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {IRegistryDelegatesV2} from "../../../src/interface/IRegistryDelegatesV2.sol";
import {Test, Vm} from "forge-std-1.17.0/src/Test.sol";

import {IConfigRegistryV4} from "../../../src/interface/IConfigRegistryV4.sol";
import {ConfigRegistry} from "../../../src/concrete/ConfigRegistry.sol";

/// @title ConfigRegistryValueTypeTest
/// @notice `registerV4`'s `valueType`: refused empty, stored as its hash only,
/// replaced by a rebind, carried as the string in `Register`.
contract ConfigRegistryValueTypeTest is Test {
    struct Pair {
        address account;
        uint256 amount;
    }

    struct PairWithHashes {
        Pair pair;
        bytes32[] hashes;
    }

    struct Flag {
        address account;
        bool on;
    }

    struct Entry {
        uint256 id;
        Flag[] flags;
    }

    ConfigRegistry internal sRegistry;

    function setUp() external {
        sRegistry = new ConfigRegistry();
    }

    /// An empty type is refused.
    function testRegisterEmptyValueTypeReverts(address authority, bytes32 name, bytes memory value) external {
        vm.assume(value.length > 0);
        vm.recordLogs();
        vm.prank(authority);
        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV4.EmptyValueType.selector, name));
        sRegistry.registerV4(authority, name, "", value, "");
        assertEq(vm.getRecordedLogs().length, 0);
        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV4.NameNotRegistered.selector, authority, name));
        sRegistry.getV4(authority, name);
    }

    /// An empty type does not unbind or retype a bound name.
    function testRegisterEmptyValueTypeLeavesBinding(address authority, bytes32 name) external {
        vm.warp(1);
        vm.prank(authority);
        sRegistry.registerV4(authority, name, "address", hex"01", "");
        vm.warp(2);
        vm.prank(authority);
        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV4.EmptyValueType.selector, name));
        sRegistry.registerV4(authority, name, "", hex"02", "");
        (bytes memory value, uint256 registeredAt, bytes32 valueTypeHash) = sRegistry.getV4(authority, name);
        assertEq(value, hex"01");
        assertEq(registeredAt, 1);
        assertEq(valueTypeHash, keccak256("address"));
    }

    /// Who may write is checked before the type, the value before the type,
    /// and the type before the clock.
    function testRegisterEmptyValueTypeOrder(address authority, address sender, bytes32 name) external {
        vm.assume(sender != authority);
        vm.prank(sender);
        vm.expectRevert(abi.encodeWithSelector(IRegistryDelegatesV2.NotApproved.selector, authority, name, sender));
        sRegistry.registerV4(authority, name, "", "", "");

        vm.prank(authority);
        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV4.EmptyValue.selector, name));
        sRegistry.registerV4(authority, name, "", "", "");

        vm.warp(5);
        vm.prank(authority);
        sRegistry.registerV4(authority, name, "address", hex"01", "");
        vm.prank(authority);
        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV4.EmptyValueType.selector, name));
        sRegistry.registerV4(authority, name, "", hex"01", "");
    }

    /// The hash of the type is stored and returned, and any non-empty string is
    /// a type.
    function testRegisterStoresValueTypeHash(address authority, bytes32 name, string memory valueType) external {
        vm.assume(bytes(valueType).length > 0);
        vm.prank(authority);
        sRegistry.registerV4(authority, name, valueType, hex"01", "");
        (,, bytes32 valueTypeHash) = sRegistry.getV4(authority, name);
        assertEq(valueTypeHash, keccak256(bytes(valueType)));
    }

    /// The type is in `Register` as given.
    function testRegisterEventCarriesValueType(address authority, bytes32 name, string memory valueType) external {
        vm.assume(bytes(valueType).length > 0);
        vm.recordLogs();
        vm.prank(authority);
        sRegistry.registerV4(authority, name, valueType, hex"01", "");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 1);
        assertEq(entries[0].data, abi.encode(authority, authority, name, valueType, hex"01"));
    }

    /// A rebind replaces the type with the value, including a rebind that
    /// changes only the type.
    function testRegisterRebindReplacesValueType(address authority, bytes32 name) external {
        vm.warp(1);
        vm.prank(authority);
        sRegistry.registerV4(authority, name, "address", hex"01", "");
        vm.warp(2);
        vm.prank(authority);
        sRegistry.registerV4(authority, name, "uint256", hex"01", "");
        (bytes memory value, uint256 registeredAt, bytes32 valueTypeHash) = sRegistry.getV4(authority, name);
        assertEq(value, hex"01");
        assertEq(registeredAt, 2);
        assertEq(valueTypeHash, keccak256("uint256"));
    }

    /// Binds `value` as `valueType` and checks the type hash, the `Register`
    /// type string and the value.
    function registerStructured(address authority, bytes32 name, string memory valueType, bytes memory value)
        internal
        returns (bytes memory)
    {
        vm.recordLogs();
        vm.prank(authority);
        sRegistry.registerV4(authority, name, valueType, value, "");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 1);
        assertEq(entries[0].data, abi.encode(authority, authority, name, valueType, value));
        (bytes memory bound,, bytes32 valueTypeHash) = sRegistry.getV4(authority, name);
        assertEq(valueTypeHash, keccak256(bytes(valueType)));
        assertEq(bound, value);
        return bound;
    }

    function testRegisterTupleValueType(address authority, bytes32 name, Pair memory pair) external {
        bytes memory bound = registerStructured(authority, name, "(address,uint256)", abi.encode(pair));
        Pair memory decoded = abi.decode(bound, (Pair));
        assertEq(decoded.account, pair.account);
        assertEq(decoded.amount, pair.amount);
    }

    function testRegisterNestedTupleWithArrayValueType(address authority, bytes32 name, PairWithHashes memory value)
        external
    {
        bytes memory bound = registerStructured(authority, name, "((address,uint256),bytes32[])", abi.encode(value));
        PairWithHashes memory decoded = abi.decode(bound, (PairWithHashes));
        assertEq(decoded.pair.account, value.pair.account);
        assertEq(decoded.pair.amount, value.pair.amount);
        assertEq(decoded.hashes, value.hashes);
    }

    function testRegisterArrayOfTuplesWithTupleArraysValueType(address authority, bytes32 name) external {
        Entry[] memory entries = new Entry[](2);
        entries[0].id = 1;
        entries[0].flags = new Flag[](2);
        entries[0].flags[0] = Flag(address(0xA), true);
        entries[0].flags[1] = Flag(address(0xB), false);
        entries[1].id = type(uint256).max;
        entries[1].flags = new Flag[](1);
        entries[1].flags[0] = Flag(address(0xC), true);

        bytes memory bound = registerStructured(authority, name, "(uint256,(address,bool)[])[]", abi.encode(entries));
        Entry[] memory decoded = abi.decode(bound, (Entry[]));
        assertEq(decoded.length, entries.length);
        for (uint256 i = 0; i < entries.length; i++) {
            assertEq(decoded[i].id, entries[i].id);
            assertEq(decoded[i].flags.length, entries[i].flags.length);
            for (uint256 j = 0; j < entries[i].flags.length; j++) {
                assertEq(decoded[i].flags[j].account, entries[i].flags[j].account);
                assertEq(decoded[i].flags[j].on, entries[i].flags[j].on);
            }
        }
    }

    /// Types are per authority and name.
    function testValueTypeIsPerBinding(address authority, address other, bytes32 name, bytes32 otherName) external {
        vm.assume(authority != other && name != otherName);
        vm.prank(authority);
        sRegistry.registerV4(authority, name, "address", hex"01", "");
        vm.prank(authority);
        sRegistry.registerV4(authority, otherName, "bytes", hex"01", "");
        vm.prank(other);
        sRegistry.registerV4(other, name, "uint256", hex"01", "");
        (,, bytes32 a) = sRegistry.getV4(authority, name);
        (,, bytes32 b) = sRegistry.getV4(authority, otherName);
        (,, bytes32 c) = sRegistry.getV4(other, name);
        assertEq(a, keccak256("address"));
        assertEq(b, keccak256("bytes"));
        assertEq(c, keccak256("uint256"));
    }
}
