// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, Vm} from "forge-std-1.17.0/src/Test.sol";

import {IAddressRegistryV2} from "../../../src/interface/IAddressRegistryV2.sol";
import {ADDRESS_REGISTRY_ROOT} from "../../../src/concrete/AddressRegistry.sol";
import {AddressRegistryV2} from "../../../src/concrete/AddressRegistryV2.sol";

/// @title AddressRegistryV2RegisterTest
/// @notice A test suite for `AddressRegistryV2.register`: who may bind a name,
/// that root may re-bind one, what a binding may never become, and when the
/// recorded timestamp moves.
contract AddressRegistryV2RegisterTest is Test {
    /// The registry under test. Stateful, so a fresh one per test.
    AddressRegistryV2 internal sRegistry;

    function setUp() external {
        sRegistry = new AddressRegistryV2();
    }

    /// Only root may bind a name. Checked before the zero-address check, so a
    /// non-root caller is rejected as `NotRoot` whatever it passes.
    function testRegisterV2OnlyRoot(address sender, bytes32 name, address account) external {
        vm.assume(sender != ADDRESS_REGISTRY_ROOT);

        vm.expectRevert(abi.encodeWithSelector(IAddressRegistryV2.NotRoot.selector, sender));
        vm.prank(sender);
        sRegistry.register(name, account);
    }

    /// Re-binding is root's alone. A name being already bound gives nobody else
    /// authority over it, and the failed attempt leaves both halves of the
    /// binding untouched.
    function testRegisterV2RebindOnlyRoot(address sender, bytes32 name, address boundAccount, address account)
        external
    {
        vm.assume(sender != ADDRESS_REGISTRY_ROOT);
        vm.assume(boundAccount != address(0));

        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, boundAccount);
        (, uint256 changedAt) = sRegistry.get(name);

        vm.warp(block.timestamp + 1 days);
        vm.expectRevert(abi.encodeWithSelector(IAddressRegistryV2.NotRoot.selector, sender));
        vm.prank(sender);
        sRegistry.register(name, account);

        (address actualAccount, uint256 actualChangedAt) = sRegistry.get(name);
        assertEq(actualAccount, boundAccount);
        assertEq(actualChangedAt, changedAt);
    }

    /// Root may re-bind a name to a different address, and the new binding is
    /// what `get` answers with from then on. This is the rotation case: an
    /// owning multisig changes without any consumer's name, creation code or
    /// deterministic address moving. The recorded timestamp moves with the
    /// address, which is the whole of what this version adds.
    function testRegisterV2Rebind(bytes32 name, address boundAccount, address account, uint64 gap) external {
        vm.assume(boundAccount != address(0));
        vm.assume(account != address(0));
        vm.assume(boundAccount != account);
        gap = uint64(bound(uint256(gap), 1, type(uint32).max));

        uint256 firstBindAt = block.timestamp;
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, boundAccount);
        (address firstAccount, uint256 firstChangedAt) = sRegistry.get(name);
        assertEq(firstAccount, boundAccount);
        assertEq(firstChangedAt, firstBindAt);

        vm.warp(block.timestamp + gap);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, account);

        (address secondAccount, uint256 secondChangedAt) = sRegistry.get(name);
        assertEq(secondAccount, account);
        assertEq(secondChangedAt, block.timestamp);
        assertEq(secondChangedAt, firstChangedAt + gap);
    }

    /// Re-binding a name to the address it already holds is allowed and is a
    /// no-op on the binding — BOTH halves of it. The timestamp is the moment
    /// the address changed, and a call that stores the address already there
    /// changed nothing, so a reader asking "has this moved recently?" is not
    /// told yes by a call that moved nothing.
    function testRegisterV2RebindSameAccount(bytes32 name, address account, uint64 gap) external {
        vm.assume(account != address(0));
        gap = uint64(bound(uint256(gap), 1, type(uint32).max));

        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, account);
        (, uint256 firstChangedAt) = sRegistry.get(name);

        vm.warp(block.timestamp + gap);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, account);

        (address actualAccount, uint256 actualChangedAt) = sRegistry.get(name);
        assertEq(actualAccount, account);
        assertEq(actualChangedAt, firstChangedAt);
        assertEq(block.timestamp - actualChangedAt, gap);
    }

    /// Nothing is hidden by the no-op rule. It skips the write only when the
    /// stored address already equals the one being bound, so a name that leaves
    /// an address and comes back to it records every move, including the move
    /// back.
    function testRegisterV2RebindBackToPrevious(bytes32 name, address first, address second, uint64 gap) external {
        vm.assume(first != address(0));
        vm.assume(second != address(0));
        vm.assume(first != second);
        gap = uint64(bound(uint256(gap), 1, type(uint32).max));

        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, first);
        (, uint256 firstChangedAt) = sRegistry.get(name);

        vm.warp(block.timestamp + gap);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, second);

        vm.warp(block.timestamp + gap);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, first);

        (address actualAccount, uint256 actualChangedAt) = sRegistry.get(name);
        assertEq(actualAccount, first);
        assertEq(actualChangedAt, block.timestamp);
        assertEq(actualChangedAt, firstChangedAt + uint256(gap) * 2);
    }

    /// Re-binding survives any number of rotations, only the most recent one
    /// counts, and the recorded timestamp is the moment of that one.
    function testRegisterV2RebindRepeatedly(bytes32 name, address[] memory accounts) external {
        vm.assume(accounts.length > 0);
        for (uint256 i = 0; i < accounts.length; i++) {
            vm.assume(accounts[i] != address(0));
        }

        uint256 lastChangeAt = block.timestamp;
        for (uint256 i = 0; i < accounts.length; i++) {
            vm.warp(block.timestamp + 1 days);
            address previousAccount = address(0);
            uint256 previousChangedAt = 0;
            if (i > 0) {
                (previousAccount, previousChangedAt) = sRegistry.get(name);
            }

            vm.prank(ADDRESS_REGISTRY_ROOT);
            sRegistry.register(name, accounts[i]);

            // Only a call that moved the address moved the timestamp.
            lastChangeAt = previousAccount == accounts[i] ? previousChangedAt : block.timestamp;

            (address actualAccount, uint256 actualChangedAt) = sRegistry.get(name);
            assertEq(actualAccount, accounts[i]);
            assertEq(actualChangedAt, lastChangeAt);
        }

        (address finalAccount, uint256 finalChangedAt) = sRegistry.get(name);
        assertEq(finalAccount, accounts[accounts.length - 1]);
        assertEq(finalChangedAt, lastChangeAt);
    }

    /// The zero address is rejected. An unbound name reads as the zero address
    /// internally, so binding it would produce a name that is bound but
    /// unreadable — and a binding with a timestamp but no address.
    function testRegisterV2ZeroAccount(bytes32 name) external {
        vm.expectRevert(abi.encodeWithSelector(IAddressRegistryV2.ZeroAccount.selector, name));
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, address(0));

        vm.expectRevert(abi.encodeWithSelector(IAddressRegistryV2.NameNotRegistered.selector, name));
        sRegistry.get(name);
    }

    /// The zero address is rejected for a name that is already bound too, so
    /// there is no way to unbind a name by re-binding it to zero — the existing
    /// binding survives intact, timestamp included, rather than the name
    /// reverting to "never bound".
    function testRegisterV2ZeroAccountCannotUnbind(bytes32 name, address boundAccount) external {
        vm.assume(boundAccount != address(0));

        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, boundAccount);
        (, uint256 changedAt) = sRegistry.get(name);

        vm.warp(block.timestamp + 1 days);
        vm.expectRevert(abi.encodeWithSelector(IAddressRegistryV2.ZeroAccount.selector, name));
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, address(0));

        (address actualAccount, uint256 actualChangedAt) = sRegistry.get(name);
        assertEq(actualAccount, boundAccount);
        assertEq(actualChangedAt, changedAt);
    }

    /// Names are independent: binding one says nothing about any other, and
    /// re-binding one disturbs neither the address nor the timestamp of
    /// another.
    function testRegisterV2DistinctNames(bytes32 nameA, bytes32 nameB, address accountA, address accountB) external {
        vm.assume(nameA != nameB);
        vm.assume(accountA != address(0));
        vm.assume(accountB != address(0));

        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(nameA, accountA);
        uint256 changedAtA = block.timestamp;

        // Binding `nameA` did not bind `nameB`.
        vm.expectRevert(abi.encodeWithSelector(IAddressRegistryV2.NameNotRegistered.selector, nameB));
        sRegistry.get(nameB);

        vm.warp(block.timestamp + 1 days);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(nameB, accountB);

        (address actualAccountA, uint256 actualChangedAtA) = sRegistry.get(nameA);
        assertEq(actualAccountA, accountA);
        assertEq(actualChangedAtA, changedAtA);

        (address actualAccountB, uint256 actualChangedAtB) = sRegistry.get(nameB);
        assertEq(actualAccountB, accountB);
        assertEq(actualChangedAtB, block.timestamp);
    }

    /// `Register` is emitted with the name and account both indexed, so the log
    /// can be filtered by either, and the timestamp in the data. The log is the
    /// only enumeration of the registry, so a binding that does not emit is a
    /// binding nobody can find.
    function testRegisterV2Event(bytes32 name, address account) external {
        vm.assume(account != address(0));

        vm.recordLogs();
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, account);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        assertEq(entries.length, 1);
        assertEq(entries[0].emitter, address(sRegistry));
        assertEq(entries[0].topics.length, 3);
        assertEq(entries[0].topics[0], keccak256("Register(bytes32,address,uint256)"));
        assertEq(entries[0].topics[1], name);
        assertEq(entries[0].topics[2], bytes32(uint256(uint160(account))));
        assertEq(abi.decode(entries[0].data, (uint256)), block.timestamp);
    }

    /// The V1 event topic is not this event's topic. An indexer filtering on
    /// `Register(bytes32,address)` sees nothing here, which is a migration cost
    /// rather than a silent one only if it is stated.
    function testRegisterV2EventTopicIsNotV1(bytes32 name, address account) external {
        vm.assume(account != address(0));

        vm.recordLogs();
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, account);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        assertEq(entries.length, 1);
        assertTrue(entries[0].topics[0] != keccak256("Register(bytes32,address)"));
    }

    /// A re-binding emits its own `Register`, so the log is the full history and
    /// the most recent entry for a name carries its current binding whole.
    /// Without this an indexer would still be serving the original binding
    /// after a rotation.
    function testRegisterV2RebindEvent(bytes32 name, address boundAccount, address account, uint64 gap) external {
        vm.assume(boundAccount != address(0));
        vm.assume(account != address(0));
        vm.assume(boundAccount != account);
        gap = uint64(bound(uint256(gap), 1, type(uint32).max));

        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, boundAccount);

        vm.warp(block.timestamp + gap);
        vm.recordLogs();
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, account);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        assertEq(entries.length, 1);
        assertEq(entries[0].topics[1], name);
        assertEq(entries[0].topics[2], bytes32(uint256(uint160(account))));
        assertEq(abi.decode(entries[0].data, (uint256)), block.timestamp);
    }

    /// A re-bind that moved nothing emits the timestamp it left in place, not
    /// the block it happened in. That is what makes the log readable on its
    /// own: an entry whose `changedAt` predates its own block is a call that
    /// moved nothing.
    function testRegisterV2RebindSameAccountEvent(bytes32 name, address account, uint64 gap) external {
        vm.assume(account != address(0));
        gap = uint64(bound(uint256(gap), 1, type(uint32).max));

        uint256 firstBindAt = block.timestamp;
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, account);

        vm.warp(block.timestamp + gap);
        vm.recordLogs();
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, account);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        assertEq(entries.length, 1);
        assertEq(entries[0].topics[2], bytes32(uint256(uint160(account))));
        assertEq(abi.decode(entries[0].data, (uint256)), firstBindAt);
        assertEq(block.timestamp - firstBindAt, gap);
    }

    /// A rejected `register` emits nothing, so a failed bind can never be
    /// mistaken for a binding by anything reading the logs.
    function testRegisterV2NoEventOnRevert(address sender, bytes32 name, address account) external {
        vm.assume(sender != ADDRESS_REGISTRY_ROOT);

        vm.recordLogs();
        vm.expectRevert(abi.encodeWithSelector(IAddressRegistryV2.NotRoot.selector, sender));
        vm.prank(sender);
        sRegistry.register(name, account);
        assertEq(vm.getRecordedLogs().length, 0);
    }

    /// Root is the CALLER, never the transaction origin. A call from a non-root
    /// account is refused even when the transaction originates from root, so no
    /// intermediary contract can borrow root's authority merely by being called
    /// by it, and root signing a transaction is not root making the call.
    function testRegisterV2RootIsCallerNotOrigin(address sender, bytes32 name, address account) external {
        vm.assume(sender != ADDRESS_REGISTRY_ROOT);
        vm.assume(account != address(0));

        vm.expectRevert(abi.encodeWithSelector(IAddressRegistryV2.NotRoot.selector, sender));
        vm.prank(sender, ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, account);

        vm.expectRevert(abi.encodeWithSelector(IAddressRegistryV2.NameNotRegistered.selector, name));
        sRegistry.get(name);
    }

    /// The recorded timestamp is the block's, whatever the block's is, over the
    /// whole range the slot holds. Nothing derives it, offsets it or rounds it.
    function testRegisterV2ChangedAtIsBlockTimestamp(bytes32 name, address account, uint96 timestamp) external {
        vm.assume(account != address(0));

        vm.warp(timestamp);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, account);

        (, uint256 changedAt) = sRegistry.get(name);
        assertEq(changedAt, timestamp);
    }

    /// Boundness is the address and never the timestamp. A bind in a block
    /// whose timestamp is zero is a bound name that reads normally, rather than
    /// one that reads as never bound — the same reason `get` reverts on the
    /// zero address instead of returning it.
    function testRegisterV2ZeroTimestampIsStillBound(bytes32 name, address account) external {
        vm.assume(account != address(0));

        vm.warp(0);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, account);

        (address actualAccount, uint256 changedAt) = sRegistry.get(name);
        assertEq(actualAccount, account);
        assertEq(changedAt, 0);
    }
}
