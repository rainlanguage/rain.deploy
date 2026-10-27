// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {IRegistryDelegatesV1} from "../../../src/interface/IRegistryDelegatesV1.sol";
import {Test, Vm} from "forge-std-1.17.0/src/Test.sol";

import {IConfigRegistryV4} from "../../../src/interface/IConfigRegistryV4.sol";
import {ConfigRegistry} from "../../../src/concrete/ConfigRegistry.sol";
import {LibConfigRegistryRead} from "../../lib/LibConfigRegistryRead.sol";

/// @title ConfigRegistryDelegateTest
/// @notice Tests for delegated binds: an authority approves a delegate for a
/// name, the delegate binds that name under that authority and nothing else, and a revoked or
/// unapproved caller is refused.
contract ConfigRegistryDelegateTest is Test {
    /// The registry under test. Stateful, so a fresh one per test.
    ConfigRegistry internal sRegistry;

    address internal constant AUTHORITY = address(0x1111);
    address internal constant DELEGATE = address(0x2222);
    string internal constant NAME = "a.b";
    bytes32 internal constant NAME_HASH = keccak256("a.b");
    string internal constant VALUE_TYPE = "bytes";

    function setUp() external {
        sRegistry = new ConfigRegistry();
    }

    function approveDelegate() internal {
        vm.prank(AUTHORITY);
        sRegistry.approveV3(NAME_HASH, DELEGATE);
    }

    /// Nothing is approved until the authority approves it.
    function testApprovedIsFalseUntilApproved(address authority, bytes32 name, address delegate) external view {
        vm.assume(delegate != address(0));
        assertFalse(sRegistry.approvedV3(authority, name, delegate));
    }

    /// An approval is the caller's, for one name and one delegate, and is emitted.
    function testApproveIsPerAuthorityNameAndDelegate(address otherAuthority, bytes32 otherName, address otherDelegate)
        external
    {
        vm.assume(otherAuthority != AUTHORITY);
        vm.assume(otherName != NAME_HASH);
        vm.assume(otherDelegate != DELEGATE && otherDelegate != address(0));
        vm.expectEmit(address(sRegistry));
        emit IRegistryDelegatesV1.Approved(AUTHORITY, NAME_HASH, DELEGATE);
        approveDelegate();
        assertTrue(sRegistry.approvedV3(AUTHORITY, NAME_HASH, DELEGATE));
        assertFalse(sRegistry.approvedV3(otherAuthority, NAME_HASH, DELEGATE));
        assertFalse(sRegistry.approvedV3(AUTHORITY, otherName, DELEGATE));
        assertFalse(sRegistry.approvedV3(AUTHORITY, NAME_HASH, otherDelegate));
    }

    /// `Approved` and `Revoked` carry the sender, the name and the delegate,
    /// none indexed: the selector is the one topic and all three are the data.
    function testApprovalEventLayout() external {
        vm.recordLogs();
        approveDelegate();
        vm.prank(AUTHORITY);
        sRegistry.revokeV3(NAME_HASH, DELEGATE);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        assertEq(entries.length, 2);
        assertEq(entries[0].topics.length, 1);
        assertEq(entries[0].topics[0], keccak256("Approved(address,bytes32,address)"));
        assertEq(entries[0].data, abi.encode(AUTHORITY, NAME_HASH, DELEGATE));
        assertEq(entries[1].topics.length, 1);
        assertEq(entries[1].topics[0], keccak256("Revoked(address,bytes32,address)"));
        assertEq(entries[1].data, abi.encode(AUTHORITY, NAME_HASH, DELEGATE));
    }

    /// Revoking an unapproved delegate, approving twice and revoking twice
    /// each emit and leave the approval as named.
    function testRevokeRemovesTheApproval() external {
        vm.expectEmit(address(sRegistry));
        emit IRegistryDelegatesV1.Revoked(AUTHORITY, NAME_HASH, DELEGATE);
        vm.prank(AUTHORITY);
        sRegistry.revokeV3(NAME_HASH, DELEGATE);
        assertFalse(sRegistry.approvedV3(AUTHORITY, NAME_HASH, DELEGATE));
        for (uint256 i = 0; i < 2; i++) {
            vm.expectEmit(address(sRegistry));
            emit IRegistryDelegatesV1.Approved(AUTHORITY, NAME_HASH, DELEGATE);
            approveDelegate();
            assertTrue(sRegistry.approvedV3(AUTHORITY, NAME_HASH, DELEGATE));
        }
        for (uint256 i = 0; i < 2; i++) {
            vm.expectEmit(address(sRegistry));
            emit IRegistryDelegatesV1.Revoked(AUTHORITY, NAME_HASH, DELEGATE);
            vm.prank(AUTHORITY);
            sRegistry.revokeV3(NAME_HASH, DELEGATE);
            assertFalse(sRegistry.approvedV3(AUTHORITY, NAME_HASH, DELEGATE));
        }
    }

    /// A revoke by one authority leaves another authority's approval of the
    /// same delegate.
    function testRevokeIsPerAuthority(address other) external {
        vm.assume(other != AUTHORITY);
        approveDelegate();
        vm.prank(other);
        sRegistry.approveV3(NAME_HASH, DELEGATE);

        vm.prank(AUTHORITY);
        sRegistry.revokeV3(NAME_HASH, DELEGATE);

        assertFalse(sRegistry.approvedV3(AUTHORITY, NAME_HASH, DELEGATE));
        assertTrue(sRegistry.approvedV3(other, NAME_HASH, DELEGATE));
    }

    /// The zero delegate names no approval: `approveV3`, `revokeV3` and
    /// `approvedV3` refuse it, whoever calls and under whichever authority,
    /// and a refused approve or revoke emits nothing.
    function testApprovalRefusesZeroDelegate(address caller, address authority) external {
        vm.recordLogs();
        vm.expectRevert(IRegistryDelegatesV1.ZeroDelegate.selector);
        vm.prank(caller);
        sRegistry.approveV3(NAME_HASH, address(0));
        vm.expectRevert(IRegistryDelegatesV1.ZeroDelegate.selector);
        vm.prank(caller);
        sRegistry.revokeV3(NAME_HASH, address(0));
        assertEq(vm.getRecordedLogs().length, 0);
        vm.expectRevert(IRegistryDelegatesV1.ZeroDelegate.selector);
        sRegistry.approvedV3(authority, NAME_HASH, address(0));
    }

    /// The zero authority answers false for every delegate rather than
    /// reverting: nothing calls from it, so nothing approves under it.
    function testApprovedZeroAuthorityIsFalse(address delegate) external view {
        vm.assume(delegate != address(0));
        assertFalse(sRegistry.approvedV3(address(0), NAME_HASH, delegate));
    }

    /// An approved delegate binds under the authority: the value and moment
    /// read back under the authority, `Register` names the delegate as sender
    /// and the authority beside it, and nothing is bound under the delegate.
    function testApprovedDelegateBindsUnderTheAuthority(bytes memory value, uint256 moment) external {
        vm.assume(value.length > 0);
        moment = bound(moment, 1, type(uint256).max);
        approveDelegate();

        vm.warp(moment);
        vm.expectEmit(address(sRegistry));
        emit IConfigRegistryV4.Register(DELEGATE, AUTHORITY, NAME_HASH, NAME, VALUE_TYPE, value);
        vm.prank(DELEGATE);
        sRegistry.registerV4(AUTHORITY, NAME, VALUE_TYPE, value);

        assertEq(LibConfigRegistryRead.getValue(sRegistry, AUTHORITY, NAME_HASH), value);
        assertEq(LibConfigRegistryRead.getMoment(sRegistry, AUTHORITY, NAME_HASH), moment);
        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV4.NameNotRegistered.selector, DELEGATE, NAME_HASH));
        LibConfigRegistryRead.getValue(sRegistry, DELEGATE, NAME_HASH);
    }

    /// An approval covers only its name: the delegate binds that name under the
    /// authority and is refused every other, which stays unbound.
    function testApprovalCoversOnlyItsName(string memory other) external {
        bytes32 otherHash = keccak256(bytes(other));
        vm.assume(bytes(other).length > 0 && otherHash != NAME_HASH);
        approveDelegate();

        vm.prank(DELEGATE);
        sRegistry.registerV4(AUTHORITY, NAME, VALUE_TYPE, hex"01");
        assertEq(LibConfigRegistryRead.getValue(sRegistry, AUTHORITY, NAME_HASH), hex"01");

        vm.expectRevert(
            abi.encodeWithSelector(IRegistryDelegatesV1.NotApproved.selector, AUTHORITY, otherHash, DELEGATE)
        );
        vm.prank(DELEGATE);
        sRegistry.registerV4(AUTHORITY, other, VALUE_TYPE, hex"02");
        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV4.NameNotRegistered.selector, AUTHORITY, otherHash));
        LibConfigRegistryRead.getValue(sRegistry, AUTHORITY, otherHash);
    }

    /// The scope an approval names is the hash of the name a write takes: an
    /// approval of `keccak256(bytes(name))` lets the delegate write `name`,
    /// and an approval of any other word — the name's own bytes padded to a
    /// word among them — lets it write nothing.
    function testApprovalScopeIsTheNameHash(string memory name) external {
        vm.assume(bytes(name).length > 0 && bytes(name).length <= 32);
        bytes32 nameHash = keccak256(bytes(name));
        bytes32 raw = bytes32(bytes(name));
        vm.assume(raw != nameHash);

        vm.prank(AUTHORITY);
        sRegistry.approveV3(raw, DELEGATE);
        vm.expectRevert(
            abi.encodeWithSelector(IRegistryDelegatesV1.NotApproved.selector, AUTHORITY, nameHash, DELEGATE)
        );
        vm.prank(DELEGATE);
        sRegistry.registerV4(AUTHORITY, name, VALUE_TYPE, hex"01");

        vm.prank(AUTHORITY);
        sRegistry.approveV3(nameHash, DELEGATE);
        vm.prank(DELEGATE);
        sRegistry.registerV4(AUTHORITY, name, VALUE_TYPE, hex"01");
        assertEq(LibConfigRegistryRead.getValue(sRegistry, AUTHORITY, nameHash), hex"01");
    }

    /// A revoke for one name leaves the same delegate's approval for another.
    function testRevokeIsPerName(string memory other) external {
        bytes32 otherHash = keccak256(bytes(other));
        vm.assume(bytes(other).length > 0 && otherHash != NAME_HASH);
        approveDelegate();
        vm.prank(AUTHORITY);
        sRegistry.approveV3(otherHash, DELEGATE);

        vm.prank(AUTHORITY);
        sRegistry.revokeV3(NAME_HASH, DELEGATE);

        assertFalse(sRegistry.approvedV3(AUTHORITY, NAME_HASH, DELEGATE));
        assertTrue(sRegistry.approvedV3(AUTHORITY, otherHash, DELEGATE));
        vm.prank(DELEGATE);
        sRegistry.registerV4(AUTHORITY, other, VALUE_TYPE, hex"01");
        assertEq(LibConfigRegistryRead.getValue(sRegistry, AUTHORITY, otherHash), hex"01");
    }

    /// An approved delegate still binds under itself, as any account does.
    function testApprovedDelegateStillBindsUnderItself() external {
        approveDelegate();
        vm.prank(DELEGATE);
        sRegistry.registerV4(DELEGATE, NAME, VALUE_TYPE, hex"01");
        assertEq(LibConfigRegistryRead.getValue(sRegistry, DELEGATE, NAME_HASH), hex"01");
        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV4.NameNotRegistered.selector, AUTHORITY, NAME_HASH));
        LibConfigRegistryRead.getValue(sRegistry, AUTHORITY, NAME_HASH);
    }

    /// An unapproved caller is refused under the authority, naming the
    /// authority and itself; nothing is bound and nothing is emitted.
    function testUnapprovedCallerIsRefused(address caller, bytes memory value) external {
        vm.assume(caller != AUTHORITY);
        vm.assume(value.length > 0);

        vm.recordLogs();
        vm.expectRevert(abi.encodeWithSelector(IRegistryDelegatesV1.NotApproved.selector, AUTHORITY, NAME_HASH, caller));
        vm.prank(caller);
        sRegistry.registerV4(AUTHORITY, NAME, VALUE_TYPE, value);
        assertEq(vm.getRecordedLogs().length, 0);

        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV4.NameNotRegistered.selector, AUTHORITY, NAME_HASH));
        LibConfigRegistryRead.getValue(sRegistry, AUTHORITY, NAME_HASH);
    }

    /// The caller is refused before anything about the write: an unapproved
    /// caller with an empty name, type or value, or at a clock of zero, is
    /// `NotApproved`, not `EmptyName`, `EmptyValueType`, `EmptyValue` or
    /// `TimestampNotAfterBinding`. An empty name is refused under the empty
    /// string's hash, the scope it would have to have been approved for.
    function testUnapprovedCallerIsRefusedBeforeItsArguments(address caller) external {
        vm.assume(caller != AUTHORITY);

        vm.expectRevert(
            abi.encodeWithSelector(IRegistryDelegatesV1.NotApproved.selector, AUTHORITY, keccak256(""), caller)
        );
        vm.prank(caller);
        sRegistry.registerV4(AUTHORITY, "", "", "");

        vm.expectRevert(abi.encodeWithSelector(IRegistryDelegatesV1.NotApproved.selector, AUTHORITY, NAME_HASH, caller));
        vm.prank(caller);
        sRegistry.registerV4(AUTHORITY, NAME, "", "");

        vm.expectRevert(abi.encodeWithSelector(IRegistryDelegatesV1.NotApproved.selector, AUTHORITY, NAME_HASH, caller));
        vm.prank(caller);
        sRegistry.registerV4(AUTHORITY, NAME, VALUE_TYPE, "");

        vm.warp(0);
        vm.expectRevert(abi.encodeWithSelector(IRegistryDelegatesV1.NotApproved.selector, AUTHORITY, NAME_HASH, caller));
        vm.prank(caller);
        sRegistry.registerV4(AUTHORITY, NAME, VALUE_TYPE, hex"01");
    }

    /// An approved delegate's binds are held to the same refusals as the
    /// authority's: an empty type is `EmptyValueType` and an empty value is
    /// `EmptyValue`.
    function testApprovedDelegateEmptyValueIsRefused() external {
        approveDelegate();
        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV4.EmptyValueType.selector, NAME_HASH));
        vm.prank(DELEGATE);
        sRegistry.registerV4(AUTHORITY, NAME, "", hex"01");
        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV4.EmptyValue.selector, NAME_HASH));
        vm.prank(DELEGATE);
        sRegistry.registerV4(AUTHORITY, NAME, VALUE_TYPE, "");
    }

    /// The zero authority refuses every caller: nothing calls from it, so
    /// nothing is approved under it.
    function testZeroAuthorityRefusesEveryCaller(address caller) external {
        vm.assume(caller != address(0));
        vm.expectRevert(
            abi.encodeWithSelector(IRegistryDelegatesV1.NotApproved.selector, address(0), NAME_HASH, caller)
        );
        vm.prank(caller);
        sRegistry.registerV4(address(0), NAME, VALUE_TYPE, hex"01");
    }

    /// An approval from one authority binds under no other, even when that
    /// other has approved some other delegate.
    function testApprovalWritesNoOtherAuthority(address other, address otherDelegate) external {
        vm.assume(other != AUTHORITY && other != DELEGATE);
        vm.assume(otherDelegate != DELEGATE && otherDelegate != address(0));
        approveDelegate();
        vm.prank(other);
        sRegistry.approveV3(NAME_HASH, otherDelegate);

        vm.expectRevert(abi.encodeWithSelector(IRegistryDelegatesV1.NotApproved.selector, other, NAME_HASH, DELEGATE));
        vm.prank(DELEGATE);
        sRegistry.registerV4(other, NAME, VALUE_TYPE, hex"01");
    }

    /// An approval does not chain: an account a delegate approves binds under
    /// the delegate, never under the authority that approved the delegate.
    function testApprovalDoesNotChain(address grand) external {
        vm.assume(grand != AUTHORITY && grand != DELEGATE && grand != address(0));
        approveDelegate();
        vm.prank(DELEGATE);
        sRegistry.approveV3(NAME_HASH, grand);

        vm.expectRevert(abi.encodeWithSelector(IRegistryDelegatesV1.NotApproved.selector, AUTHORITY, NAME_HASH, grand));
        vm.prank(grand);
        sRegistry.registerV4(AUTHORITY, NAME, VALUE_TYPE, hex"01");

        vm.prank(grand);
        sRegistry.registerV4(DELEGATE, NAME, VALUE_TYPE, hex"02");
        assertEq(LibConfigRegistryRead.getValue(sRegistry, DELEGATE, NAME_HASH), hex"02");
    }

    /// A revoked delegate is refused, and the binding it made while approved
    /// stays until re-bound.
    function testRevokedDelegateIsRefused() external {
        approveDelegate();
        vm.warp(1);
        vm.prank(DELEGATE);
        sRegistry.registerV4(AUTHORITY, NAME, VALUE_TYPE, hex"01");

        vm.prank(AUTHORITY);
        sRegistry.revokeV3(NAME_HASH, DELEGATE);

        vm.warp(2);
        vm.expectRevert(
            abi.encodeWithSelector(IRegistryDelegatesV1.NotApproved.selector, AUTHORITY, NAME_HASH, DELEGATE)
        );
        vm.prank(DELEGATE);
        sRegistry.registerV4(AUTHORITY, NAME, VALUE_TYPE, hex"02");

        assertEq(LibConfigRegistryRead.getValue(sRegistry, AUTHORITY, NAME_HASH), hex"01");
        assertEq(LibConfigRegistryRead.getMoment(sRegistry, AUTHORITY, NAME_HASH), 1);
    }

    /// The authority and its delegate share one binding per name, so the moment
    /// rule is the authority's: a delegate re-bind in the block of the
    /// authority's bind is refused naming the authority's moment, a block later
    /// it lands, and the authority is then held to the delegate's moment.
    function testDelegateSharesTheAuthoritysMoment(uint256 time) external {
        time = bound(time, 1, type(uint256).max - 1);
        approveDelegate();

        vm.warp(time);
        vm.prank(AUTHORITY);
        sRegistry.registerV4(AUTHORITY, NAME, VALUE_TYPE, hex"01");

        vm.expectRevert(
            abi.encodeWithSelector(IConfigRegistryV4.TimestampNotAfterBinding.selector, NAME_HASH, time, time)
        );
        vm.prank(DELEGATE);
        sRegistry.registerV4(AUTHORITY, NAME, VALUE_TYPE, hex"02");

        vm.warp(time + 1);
        vm.prank(DELEGATE);
        sRegistry.registerV4(AUTHORITY, NAME, VALUE_TYPE, hex"02");
        assertEq(LibConfigRegistryRead.getValue(sRegistry, AUTHORITY, NAME_HASH), hex"02");
        assertEq(LibConfigRegistryRead.getMoment(sRegistry, AUTHORITY, NAME_HASH), time + 1);

        vm.expectRevert(
            abi.encodeWithSelector(IConfigRegistryV4.TimestampNotAfterBinding.selector, NAME_HASH, time + 1, time + 1)
        );
        vm.prank(AUTHORITY);
        sRegistry.registerV4(AUTHORITY, NAME, VALUE_TYPE, hex"03");
    }

    /// `approveV3` and `revokeV3` take no value.
    function testApprovalTakesNoValue() external {
        vm.deal(AUTHORITY, 2);
        vm.prank(AUTHORITY);
        (bool approved,) =
            address(sRegistry).call{value: 1}(abi.encodeCall(IRegistryDelegatesV1.approveV3, (NAME_HASH, DELEGATE)));
        assertFalse(approved);
        vm.prank(AUTHORITY);
        (bool revoked,) =
            address(sRegistry).call{value: 1}(abi.encodeCall(IRegistryDelegatesV1.revokeV3, (NAME_HASH, DELEGATE)));
        assertFalse(revoked);
        assertEq(address(sRegistry).balance, 0);
    }

    /// The approvals mapping is not `public`, so there is no generated getter
    /// answering the zero delegate with false.
    function testApprovedNoGeneratedMappingGetter(address authority, bytes32 scope, address delegate) external {
        (bool success,) = address(sRegistry)
            .call(abi.encodeWithSignature("sApproved(address,bytes32,address)", authority, scope, delegate));
        assertFalse(success);
    }
}
