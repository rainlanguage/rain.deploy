// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, Vm} from "forge-std-1.16.2/src/Test.sol";

import {IAddressRegistryV1} from "../../../src/interface/IAddressRegistryV1.sol";
import {AddressRegistry, ADDRESS_REGISTRY_ROOT} from "../../../src/concrete/AddressRegistry.sol";

/// @title AddressRegistryRegisterTest
/// @notice A test suite for `AddressRegistry.register`: who may bind a name,
/// that root may re-bind one, and what a binding may never become.
contract AddressRegistryRegisterTest is Test {
    /// The registry under test. Stateful, so a fresh one per test.
    AddressRegistry internal sRegistry;

    function setUp() external {
        sRegistry = new AddressRegistry();
    }

    /// Only root may bind a name. Checked before the zero-address check, so a
    /// non-root caller is rejected as `NotRoot` whatever it passes.
    function testRegisterOnlyRoot(address sender, bytes32 name, address account) external {
        vm.assume(sender != ADDRESS_REGISTRY_ROOT);

        vm.expectRevert(abi.encodeWithSelector(IAddressRegistryV1.NotRoot.selector, sender));
        vm.prank(sender);
        sRegistry.register(name, account);
    }

    /// Re-binding is root's alone. A name being already bound gives nobody else
    /// authority over it, and the failed attempt leaves the binding untouched.
    function testRegisterRebindOnlyRoot(address sender, bytes32 name, address bound, address account) external {
        vm.assume(sender != ADDRESS_REGISTRY_ROOT);
        vm.assume(bound != address(0));

        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, bound);

        vm.expectRevert(abi.encodeWithSelector(IAddressRegistryV1.NotRoot.selector, sender));
        vm.prank(sender);
        sRegistry.register(name, account);

        assertEq(sRegistry.get(name), bound);
    }

    /// Root may re-bind a name to a different address, and the new binding is
    /// what `get` answers with from then on. This is the rotation case: an
    /// owning multisig changes without any consumer's name, creation code or
    /// deterministic address moving.
    function testRegisterRebind(bytes32 name, address bound, address account) external {
        vm.assume(bound != address(0));
        vm.assume(account != address(0));

        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, bound);
        assertEq(sRegistry.get(name), bound);

        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, account);
        assertEq(sRegistry.get(name), account);
    }

    /// Re-binding a name to the address it already holds is allowed and is a
    /// no-op on the binding. There is no special case for it in either
    /// direction.
    function testRegisterRebindSameAccount(bytes32 name, address account) external {
        vm.assume(account != address(0));

        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, account);

        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, account);

        assertEq(sRegistry.get(name), account);
    }

    /// Re-binding survives any number of rotations, and only the most recent one
    /// counts.
    function testRegisterRebindRepeatedly(bytes32 name, address[] memory accounts) external {
        vm.assume(accounts.length > 0);
        for (uint256 i = 0; i < accounts.length; i++) {
            vm.assume(accounts[i] != address(0));
        }

        for (uint256 i = 0; i < accounts.length; i++) {
            vm.prank(ADDRESS_REGISTRY_ROOT);
            sRegistry.register(name, accounts[i]);
            assertEq(sRegistry.get(name), accounts[i]);
        }
        assertEq(sRegistry.get(name), accounts[accounts.length - 1]);
    }

    /// The zero address is rejected. An unbound name reads as the zero address
    /// internally, so binding it would produce a name that is bound but
    /// unreadable.
    function testRegisterZeroAccount(bytes32 name) external {
        vm.expectRevert(abi.encodeWithSelector(IAddressRegistryV1.ZeroAccount.selector, name));
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, address(0));

        vm.expectRevert(abi.encodeWithSelector(IAddressRegistryV1.NameNotRegistered.selector, name));
        sRegistry.get(name);
    }

    /// The zero address is rejected for a name that is already bound too, so
    /// there is no way to unbind a name by re-binding it to zero — the existing
    /// binding survives intact rather than the name reverting to "never bound".
    function testRegisterZeroAccountCannotUnbind(bytes32 name, address bound) external {
        vm.assume(bound != address(0));

        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, bound);

        vm.expectRevert(abi.encodeWithSelector(IAddressRegistryV1.ZeroAccount.selector, name));
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, address(0));

        assertEq(sRegistry.get(name), bound);
    }

    /// Names are independent: binding one says nothing about any other, and
    /// re-binding one does not disturb another.
    function testRegisterDistinctNames(bytes32 nameA, bytes32 nameB, address accountA, address accountB) external {
        vm.assume(nameA != nameB);
        vm.assume(accountA != address(0));
        vm.assume(accountB != address(0));

        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(nameA, accountA);

        // Binding `nameA` did not bind `nameB`.
        vm.expectRevert(abi.encodeWithSelector(IAddressRegistryV1.NameNotRegistered.selector, nameB));
        sRegistry.get(nameB);

        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(nameB, accountB);

        assertEq(sRegistry.get(nameA), accountA);
        assertEq(sRegistry.get(nameB), accountB);
    }

    /// `Register` is emitted with the name and account both indexed, so the log
    /// can be filtered by either. The log is the only enumeration of the
    /// registry, so a binding that does not emit is a binding nobody can find.
    function testRegisterEvent(bytes32 name, address account) external {
        vm.assume(account != address(0));

        vm.recordLogs();
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, account);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        assertEq(entries.length, 1);
        assertEq(entries[0].emitter, address(sRegistry));
        assertEq(entries[0].topics.length, 3);
        assertEq(entries[0].topics[0], keccak256("Register(bytes32,address)"));
        assertEq(entries[0].topics[1], name);
        assertEq(entries[0].topics[2], bytes32(uint256(uint160(account))));
        assertEq(entries[0].data.length, 0);
    }

    /// A re-binding emits its own `Register`, so the log is the full history and
    /// the most recent entry for a name is its current binding. Without this an
    /// indexer would still be serving the original binding after a rotation.
    function testRegisterRebindEvent(bytes32 name, address bound, address account) external {
        vm.assume(bound != address(0));
        vm.assume(account != address(0));

        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, bound);

        vm.recordLogs();
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, account);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        assertEq(entries.length, 1);
        assertEq(entries[0].topics[1], name);
        assertEq(entries[0].topics[2], bytes32(uint256(uint160(account))));
    }

    /// A rejected `register` emits nothing, so a failed bind can never be
    /// mistaken for a binding by anything reading the logs.
    function testRegisterNoEventOnRevert(address sender, bytes32 name, address account) external {
        vm.assume(sender != ADDRESS_REGISTRY_ROOT);

        vm.recordLogs();
        vm.expectRevert(abi.encodeWithSelector(IAddressRegistryV1.NotRoot.selector, sender));
        vm.prank(sender);
        sRegistry.register(name, account);
        assertEq(vm.getRecordedLogs().length, 0);
    }
}
