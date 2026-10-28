// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {IRegistryDelegatesV3} from "../../../src/interface/IRegistryDelegatesV3.sol";
import {Test, Vm} from "forge-std-1.17.0/src/Test.sol";

import {IConfigRegistryV5} from "../../../src/interface/IConfigRegistryV5.sol";
import {ConfigRegistry} from "../../../src/concrete/ConfigRegistry.sol";
import {VALUE_TYPE} from "../../lib/ConfigTestBinding.sol";
import {rainMeta, isNotRainMeta} from "../../lib/RainMeta.sol";
import {NotRainMetaV1} from "rain-metadata-0.1.43/src/interface/unstable/IMetaV1_2.sol";

/// @title ConfigRegistryMetaTest
/// @notice `registerV5`'s `meta`: emitted as `MetaV1_2` by the writer about
/// `keccak256(abi.encode(authority, name))` when non-empty, never emitted when
/// empty, never stored.
contract ConfigRegistryMetaTest is Test {
    ConfigRegistry internal sRegistry;

    function setUp() external {
        sRegistry = new ConfigRegistry();
    }

    function assertMetaLog(Vm.Log memory entry, address sender, bytes32 subject, bytes memory meta) internal view {
        assertEq(entry.emitter, address(sRegistry));
        assertEq(entry.topics.length, 1);
        assertEq(entry.topics[0], keccak256("MetaV1_2(address,bytes32,bytes)"));
        assertEq(entry.data, abi.encode(sender, subject, meta));
    }

    /// Non-empty meta is one `MetaV1_2` after `Register`, from the writer, about
    /// the authority's name.
    function testRegisterMetaEmitted(address authority, bytes32 name, bytes memory value, bytes memory meta) external {
        vm.assume(value.length > 0);
        meta = rainMeta(meta);
        vm.recordLogs();
        vm.prank(authority);
        sRegistry.registerV5(authority, name, VALUE_TYPE, value, meta);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 2);
        assertEq(entries[0].topics[0], IConfigRegistryV5.Register.selector);
        assertMetaLog(entries[1], authority, keccak256(abi.encode(authority, name)), meta);
    }

    /// A delegate's write names the delegate as the sender and the authority's
    /// name as the subject.
    function testRegisterMetaSenderIsTheDelegate(
        address authority,
        address delegate,
        bytes32 name,
        bytes memory value,
        bytes memory meta
    ) external {
        vm.assume(value.length > 0);
        meta = rainMeta(meta);
        vm.assume(delegate != address(0) && delegate != authority);
        vm.prank(authority);
        sRegistry.approveV5(name, delegate);
        vm.recordLogs();
        vm.prank(delegate);
        sRegistry.registerV5(authority, name, VALUE_TYPE, value, meta);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 2);
        assertMetaLog(entries[1], delegate, keccak256(abi.encode(authority, name)), meta);
    }

    /// Empty meta emits `Register` alone.
    function testRegisterEmptyMetaEmitsNoMeta(address authority, bytes32 name, bytes memory value) external {
        vm.assume(value.length > 0);
        vm.recordLogs();
        vm.prank(authority);
        sRegistry.registerV5(authority, name, VALUE_TYPE, value, "");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 1);
        assertEq(entries[0].topics[0], IConfigRegistryV5.Register.selector);
    }

    /// The magic number alone is rain meta.
    function testRegisterBareMagicNumberMetaEmitted(address authority, bytes32 name) external {
        vm.recordLogs();
        vm.prank(authority);
        sRegistry.registerV5(authority, name, VALUE_TYPE, hex"01", hex"ff0a89c674ee7874");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 2);
        assertMetaLog(entries[1], authority, keccak256(abi.encode(authority, name)), hex"ff0a89c674ee7874");
    }

    /// Non-empty meta without the magic number reverts `NotRainMetaV1` and
    /// binds nothing.
    function testRegisterNotRainMetaReverts(address authority, bytes32 name, bytes memory value, bytes memory meta)
        external
    {
        vm.assume(value.length > 0 && isNotRainMeta(meta));
        vm.prank(authority);
        vm.expectRevert(abi.encodeWithSelector(NotRainMetaV1.selector, meta));
        sRegistry.registerV5(authority, name, VALUE_TYPE, value, meta);
        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV5.NameNotRegistered.selector, authority, name));
        sRegistry.getV5(authority, name);
    }

    /// A rebind refused for its meta leaves the earlier binding as it was.
    function testRegisterNotRainMetaKeepsBinding(address authority, bytes32 name, bytes memory meta) external {
        vm.assume(isNotRainMeta(meta));
        vm.warp(10);
        vm.prank(authority);
        sRegistry.registerV5(authority, name, VALUE_TYPE, hex"01", "");
        vm.warp(20);
        vm.prank(authority);
        vm.expectRevert(abi.encodeWithSelector(NotRainMetaV1.selector, meta));
        sRegistry.registerV5(authority, name, "uint256", hex"02", meta);
        (bytes memory value, uint256 registeredAt, bytes32 valueTypeHash) = sRegistry.getV5(authority, name);
        assertEq(value, hex"01");
        assertEq(registeredAt, 10);
        assertEq(valueTypeHash, keccak256(bytes(VALUE_TYPE)));
    }

    /// A short meta and one whose first bytes are almost the magic number are
    /// both refused.
    function testRegisterNearMissMetaReverts(address authority, bytes32 name) external {
        bytes[3] memory metas = [bytes(hex"01"), bytes(hex"ff0a89c674ee78"), bytes(hex"ff0a89c674ee787500")];
        for (uint256 i = 0; i < metas.length; i++) {
            vm.prank(authority);
            vm.expectRevert(abi.encodeWithSelector(NotRainMetaV1.selector, metas[i]));
            sRegistry.registerV5(authority, name, VALUE_TYPE, hex"01", metas[i]);
        }
    }

    /// Every rebind of a name carries the same subject, and distinct names or
    /// authorities carry distinct subjects.
    function testRegisterMetaSubjectIsTheAuthoritysName(
        address authority,
        address other,
        bytes32 name,
        bytes32 otherName,
        bytes memory meta
    ) external {
        meta = rainMeta(meta);
        vm.assume(other != authority && otherName != name);
        bytes32 subject = keccak256(abi.encode(authority, name));
        vm.warp(10);
        vm.recordLogs();
        vm.prank(authority);
        sRegistry.registerV5(authority, name, VALUE_TYPE, hex"01", meta);
        vm.warp(20);
        vm.prank(authority);
        sRegistry.registerV5(authority, name, "uint256", hex"02", meta);
        vm.prank(authority);
        sRegistry.registerV5(authority, otherName, VALUE_TYPE, hex"01", meta);
        vm.prank(other);
        sRegistry.registerV5(other, name, VALUE_TYPE, hex"01", meta);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 8);
        assertMetaLog(entries[1], authority, subject, meta);
        assertMetaLog(entries[3], authority, subject, meta);
        assertMetaLog(entries[5], authority, keccak256(abi.encode(authority, otherName)), meta);
        assertMetaLog(entries[7], other, keccak256(abi.encode(other, name)), meta);
    }

    /// A refused write emits no meta.
    function testRegisterRefusedEmitsNoMeta(address authority, address sender, bytes32 name, bytes memory meta)
        external
    {
        vm.assume(sender != authority);
        meta = rainMeta(meta);
        vm.recordLogs();
        vm.prank(sender);
        vm.expectRevert(abi.encodeWithSelector(IRegistryDelegatesV3.NotApproved.selector, authority, name, sender));
        sRegistry.registerV5(authority, name, VALUE_TYPE, hex"01", meta);
        vm.prank(authority);
        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV5.EmptyValue.selector, name));
        sRegistry.registerV5(authority, name, VALUE_TYPE, "", meta);
        assertEq(vm.getRecordedLogs().length, 0);
    }

    /// Meta is not stored: the write touches the same slots with the same
    /// values whatever the meta, and the read is the same.
    function testRegisterMetaNotStored(address authority, bytes32 name, bytes memory value, bytes memory meta)
        external
    {
        vm.assume(value.length > 0);
        meta = rainMeta(meta);
        ConfigRegistry plain = new ConfigRegistry();
        ConfigRegistry withMeta = new ConfigRegistry();

        vm.record();
        vm.prank(authority);
        plain.registerV5(authority, name, VALUE_TYPE, value, "");
        (, bytes32[] memory plainWrites) = vm.accesses(address(plain));

        vm.record();
        vm.prank(authority);
        withMeta.registerV5(authority, name, VALUE_TYPE, value, meta);
        (, bytes32[] memory metaWrites) = vm.accesses(address(withMeta));

        assertGt(plainWrites.length, 0);
        assertEq(metaWrites.length, plainWrites.length);
        for (uint256 i = 0; i < metaWrites.length; i++) {
            assertEq(metaWrites[i], plainWrites[i]);
            assertEq(vm.load(address(withMeta), metaWrites[i]), vm.load(address(plain), plainWrites[i]));
        }
        (bytes memory a, uint256 aAt, bytes32 aType) = plain.getV5(authority, name);
        (bytes memory b, uint256 bAt, bytes32 bType) = withMeta.getV5(authority, name);
        assertEq(b, a);
        assertEq(bAt, aAt);
        assertEq(bType, aType);
    }
}
