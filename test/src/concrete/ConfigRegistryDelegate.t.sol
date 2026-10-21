// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {ZeroDelegate} from "../../../src/error/ErrRegistryDelegates.sol";
import {Test, Vm} from "forge-std-1.17.0/src/Test.sol";

import {IConfigRegistryV1} from "../../../src/interface/IConfigRegistryV1.sol";
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
    bytes32 internal constant NAME = keccak256("a.b");

    function setUp() external {
        sRegistry = new ConfigRegistry();
    }

    function approveDelegate() internal {
        vm.prank(AUTHORITY);
        sRegistry.approveV1(NAME, DELEGATE);
    }

    /// Nothing is approved until the authority approves it.
    function testApprovedIsFalseUntilApproved(address authority, bytes32 name, address delegate) external view {
        vm.assume(delegate != address(0));
        assertFalse(sRegistry.approvedV1(authority, name, delegate));
    }

    /// An approval is the caller's, for one name and one delegate, and is emitted.
    function testApproveIsPerAuthorityNameAndDelegate(address otherAuthority, bytes32 otherName, address otherDelegate)
        external
    {
        vm.assume(otherAuthority != AUTHORITY);
        vm.assume(otherName != NAME);
        vm.assume(otherDelegate != DELEGATE && otherDelegate != address(0));
        vm.expectEmit(address(sRegistry));
        emit IConfigRegistryV1.Approved(AUTHORITY, NAME, DELEGATE);
        approveDelegate();
        assertTrue(sRegistry.approvedV1(AUTHORITY, NAME, DELEGATE));
        assertFalse(sRegistry.approvedV1(otherAuthority, NAME, DELEGATE));
        assertFalse(sRegistry.approvedV1(AUTHORITY, otherName, DELEGATE));
        assertFalse(sRegistry.approvedV1(AUTHORITY, NAME, otherDelegate));
    }

    /// `Approved` and `Revoked` carry the sender, the name and the delegate,
    /// all indexed, and nothing in the data.
    function testApprovalEventLayout() external {
        vm.recordLogs();
        approveDelegate();
        vm.prank(AUTHORITY);
        sRegistry.revokeV1(NAME, DELEGATE);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        assertEq(entries.length, 2);
        assertEq(entries[0].topics.length, 4);
        assertEq(entries[0].topics[0], keccak256("Approved(address,bytes32,address)"));
        assertEq(entries[0].topics[1], bytes32(uint256(uint160(AUTHORITY))));
        assertEq(entries[0].topics[2], NAME);
        assertEq(entries[0].topics[3], bytes32(uint256(uint160(DELEGATE))));
        assertEq(entries[0].data.length, 0);
        assertEq(entries[1].topics.length, 4);
        assertEq(entries[1].topics[0], keccak256("Revoked(address,bytes32,address)"));
        assertEq(entries[1].topics[1], bytes32(uint256(uint160(AUTHORITY))));
        assertEq(entries[1].topics[2], NAME);
        assertEq(entries[1].topics[3], bytes32(uint256(uint160(DELEGATE))));
        assertEq(entries[1].data.length, 0);
    }

    /// Revoking an unapproved delegate, approving twice and revoking twice
    /// each emit and leave the approval as named.
    function testRevokeRemovesTheApproval() external {
        vm.expectEmit(address(sRegistry));
        emit IConfigRegistryV1.Revoked(AUTHORITY, NAME, DELEGATE);
        vm.prank(AUTHORITY);
        sRegistry.revokeV1(NAME, DELEGATE);
        assertFalse(sRegistry.approvedV1(AUTHORITY, NAME, DELEGATE));
        for (uint256 i = 0; i < 2; i++) {
            vm.expectEmit(address(sRegistry));
            emit IConfigRegistryV1.Approved(AUTHORITY, NAME, DELEGATE);
            approveDelegate();
            assertTrue(sRegistry.approvedV1(AUTHORITY, NAME, DELEGATE));
        }
        for (uint256 i = 0; i < 2; i++) {
            vm.expectEmit(address(sRegistry));
            emit IConfigRegistryV1.Revoked(AUTHORITY, NAME, DELEGATE);
            vm.prank(AUTHORITY);
            sRegistry.revokeV1(NAME, DELEGATE);
            assertFalse(sRegistry.approvedV1(AUTHORITY, NAME, DELEGATE));
        }
    }

    /// A revoke by one authority leaves another authority's approval of the
    /// same delegate.
    function testRevokeIsPerAuthority(address other) external {
        vm.assume(other != AUTHORITY);
        approveDelegate();
        vm.prank(other);
        sRegistry.approveV1(NAME, DELEGATE);

        vm.prank(AUTHORITY);
        sRegistry.revokeV1(NAME, DELEGATE);

        assertFalse(sRegistry.approvedV1(AUTHORITY, NAME, DELEGATE));
        assertTrue(sRegistry.approvedV1(other, NAME, DELEGATE));
    }

    /// The zero delegate names no approval: `approveV1`, `revokeV1` and
    /// `approvedV1` refuse it, whoever calls and under whichever authority,
    /// and a refused approve or revoke emits nothing.
    function testApprovalRefusesZeroDelegate(address caller, address authority) external {
        vm.recordLogs();
        vm.expectRevert(ZeroDelegate.selector);
        vm.prank(caller);
        sRegistry.approveV1(NAME, address(0));
        vm.expectRevert(ZeroDelegate.selector);
        vm.prank(caller);
        sRegistry.revokeV1(NAME, address(0));
        assertEq(vm.getRecordedLogs().length, 0);
        vm.expectRevert(ZeroDelegate.selector);
        sRegistry.approvedV1(authority, NAME, address(0));
    }

    /// The zero authority answers false for every delegate rather than
    /// reverting: nothing calls from it, so nothing approves under it.
    function testApprovedZeroAuthorityIsFalse(address delegate) external view {
        vm.assume(delegate != address(0));
        assertFalse(sRegistry.approvedV1(address(0), NAME, delegate));
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
        emit IConfigRegistryV1.Register(DELEGATE, AUTHORITY, NAME, value);
        vm.prank(DELEGATE);
        sRegistry.registerV1(AUTHORITY, NAME, value);

        assertEq(LibConfigRegistryRead.getValue(sRegistry, AUTHORITY, NAME), value);
        assertEq(LibConfigRegistryRead.getMoment(sRegistry, AUTHORITY, NAME), moment);
        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV1.NameNotRegistered.selector, DELEGATE, NAME));
        LibConfigRegistryRead.getValue(sRegistry, DELEGATE, NAME);
    }

    /// An approval covers only its name: the delegate binds that name under the
    /// authority and is refused every other, which stays unbound.
    function testApprovalCoversOnlyItsName(bytes32 other) external {
        vm.assume(other != NAME);
        approveDelegate();

        vm.prank(DELEGATE);
        sRegistry.registerV1(AUTHORITY, NAME, hex"01");
        assertEq(LibConfigRegistryRead.getValue(sRegistry, AUTHORITY, NAME), hex"01");

        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV1.NotApproved.selector, AUTHORITY, other, DELEGATE));
        vm.prank(DELEGATE);
        sRegistry.registerV1(AUTHORITY, other, hex"02");
        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV1.NameNotRegistered.selector, AUTHORITY, other));
        LibConfigRegistryRead.getValue(sRegistry, AUTHORITY, other);
    }

    /// A revoke for one name leaves the same delegate's approval for another.
    function testRevokeIsPerName(bytes32 other) external {
        vm.assume(other != NAME);
        approveDelegate();
        vm.prank(AUTHORITY);
        sRegistry.approveV1(other, DELEGATE);

        vm.prank(AUTHORITY);
        sRegistry.revokeV1(NAME, DELEGATE);

        assertFalse(sRegistry.approvedV1(AUTHORITY, NAME, DELEGATE));
        assertTrue(sRegistry.approvedV1(AUTHORITY, other, DELEGATE));
        vm.prank(DELEGATE);
        sRegistry.registerV1(AUTHORITY, other, hex"01");
        assertEq(LibConfigRegistryRead.getValue(sRegistry, AUTHORITY, other), hex"01");
    }

    /// An approved delegate still binds under itself, as any account does.
    function testApprovedDelegateStillBindsUnderItself() external {
        approveDelegate();
        vm.prank(DELEGATE);
        sRegistry.registerV1(DELEGATE, NAME, hex"01");
        assertEq(LibConfigRegistryRead.getValue(sRegistry, DELEGATE, NAME), hex"01");
        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV1.NameNotRegistered.selector, AUTHORITY, NAME));
        LibConfigRegistryRead.getValue(sRegistry, AUTHORITY, NAME);
    }

    /// An unapproved caller is refused under the authority, naming the
    /// authority and itself; nothing is bound and nothing is emitted.
    function testUnapprovedCallerIsRefused(address caller, bytes memory value) external {
        vm.assume(caller != AUTHORITY);
        vm.assume(value.length > 0);

        vm.recordLogs();
        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV1.NotApproved.selector, AUTHORITY, NAME, caller));
        vm.prank(caller);
        sRegistry.registerV1(AUTHORITY, NAME, value);
        assertEq(vm.getRecordedLogs().length, 0);

        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV1.NameNotRegistered.selector, AUTHORITY, NAME));
        LibConfigRegistryRead.getValue(sRegistry, AUTHORITY, NAME);
    }

    /// The caller is refused before anything about the write: an unapproved
    /// caller with an empty value, or at a clock of zero, is `NotApproved`,
    /// not `EmptyValue` or `TimestampNotAfterBinding`.
    function testUnapprovedCallerIsRefusedBeforeItsArguments(address caller) external {
        vm.assume(caller != AUTHORITY);

        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV1.NotApproved.selector, AUTHORITY, NAME, caller));
        vm.prank(caller);
        sRegistry.registerV1(AUTHORITY, NAME, "");

        vm.warp(0);
        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV1.NotApproved.selector, AUTHORITY, NAME, caller));
        vm.prank(caller);
        sRegistry.registerV1(AUTHORITY, NAME, hex"01");
    }

    /// An approved delegate's binds are held to the same refusals as the
    /// authority's: an empty value is `EmptyValue`.
    function testApprovedDelegateEmptyValueIsRefused() external {
        approveDelegate();
        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV1.EmptyValue.selector, NAME));
        vm.prank(DELEGATE);
        sRegistry.registerV1(AUTHORITY, NAME, "");
    }

    /// The zero authority refuses every caller: nothing calls from it, so
    /// nothing is approved under it.
    function testZeroAuthorityRefusesEveryCaller(address caller) external {
        vm.assume(caller != address(0));
        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV1.NotApproved.selector, address(0), NAME, caller));
        vm.prank(caller);
        sRegistry.registerV1(address(0), NAME, hex"01");
    }

    /// An approval from one authority binds under no other, even when that
    /// other has approved some other delegate.
    function testApprovalWritesNoOtherAuthority(address other, address otherDelegate) external {
        vm.assume(other != AUTHORITY && other != DELEGATE);
        vm.assume(otherDelegate != DELEGATE && otherDelegate != address(0));
        approveDelegate();
        vm.prank(other);
        sRegistry.approveV1(NAME, otherDelegate);

        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV1.NotApproved.selector, other, NAME, DELEGATE));
        vm.prank(DELEGATE);
        sRegistry.registerV1(other, NAME, hex"01");
    }

    /// An approval does not chain: an account a delegate approves binds under
    /// the delegate, never under the authority that approved the delegate.
    function testApprovalDoesNotChain(address grand) external {
        vm.assume(grand != AUTHORITY && grand != DELEGATE && grand != address(0));
        approveDelegate();
        vm.prank(DELEGATE);
        sRegistry.approveV1(NAME, grand);

        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV1.NotApproved.selector, AUTHORITY, NAME, grand));
        vm.prank(grand);
        sRegistry.registerV1(AUTHORITY, NAME, hex"01");

        vm.prank(grand);
        sRegistry.registerV1(DELEGATE, NAME, hex"02");
        assertEq(LibConfigRegistryRead.getValue(sRegistry, DELEGATE, NAME), hex"02");
    }

    /// A revoked delegate is refused, and the binding it made while approved
    /// stays until re-bound.
    function testRevokedDelegateIsRefused() external {
        approveDelegate();
        vm.warp(1);
        vm.prank(DELEGATE);
        sRegistry.registerV1(AUTHORITY, NAME, hex"01");

        vm.prank(AUTHORITY);
        sRegistry.revokeV1(NAME, DELEGATE);

        vm.warp(2);
        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV1.NotApproved.selector, AUTHORITY, NAME, DELEGATE));
        vm.prank(DELEGATE);
        sRegistry.registerV1(AUTHORITY, NAME, hex"02");

        assertEq(LibConfigRegistryRead.getValue(sRegistry, AUTHORITY, NAME), hex"01");
        assertEq(LibConfigRegistryRead.getMoment(sRegistry, AUTHORITY, NAME), 1);
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
        sRegistry.registerV1(AUTHORITY, NAME, hex"01");

        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV1.TimestampNotAfterBinding.selector, NAME, time, time));
        vm.prank(DELEGATE);
        sRegistry.registerV1(AUTHORITY, NAME, hex"02");

        vm.warp(time + 1);
        vm.prank(DELEGATE);
        sRegistry.registerV1(AUTHORITY, NAME, hex"02");
        assertEq(LibConfigRegistryRead.getValue(sRegistry, AUTHORITY, NAME), hex"02");
        assertEq(LibConfigRegistryRead.getMoment(sRegistry, AUTHORITY, NAME), time + 1);

        vm.expectRevert(
            abi.encodeWithSelector(IConfigRegistryV1.TimestampNotAfterBinding.selector, NAME, time + 1, time + 1)
        );
        vm.prank(AUTHORITY);
        sRegistry.registerV1(AUTHORITY, NAME, hex"03");
    }

    /// `approveV1` and `revokeV1` take no value.
    function testApprovalTakesNoValue() external {
        vm.deal(AUTHORITY, 2);
        vm.prank(AUTHORITY);
        (bool approved,) =
            address(sRegistry).call{value: 1}(abi.encodeCall(IConfigRegistryV1.approveV1, (NAME, DELEGATE)));
        assertFalse(approved);
        vm.prank(AUTHORITY);
        (bool revoked,) =
            address(sRegistry).call{value: 1}(abi.encodeCall(IConfigRegistryV1.revokeV1, (NAME, DELEGATE)));
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
