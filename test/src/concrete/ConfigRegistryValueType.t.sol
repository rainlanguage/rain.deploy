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
