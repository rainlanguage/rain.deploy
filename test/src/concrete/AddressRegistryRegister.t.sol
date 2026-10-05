// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, Vm} from "forge-std-1.17.0/src/Test.sol";

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

    /// The address half of `get`, for the assertions that are only about which
    /// address a name is bound to.
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

        assertEq(getAddress(sRegistry, name), bound);
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
        assertEq(getAddress(sRegistry, name), bound);

        // A re-bind has to be in a later block than the bind it replaces, so
        // the moment can be strictly after. `testRegisterRefusesClockEqualToTheBinding`
        // covers the same-block attempt.
        vm.warp(block.timestamp + 1);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, account);
        assertEq(getAddress(sRegistry, name), account);
    }

    /// Re-binding a name to the address it already holds is allowed and leaves
    /// the address it answers with unchanged. There is no special case for it in
    /// either direction — in particular it is not a no-op, because it refreshes
    /// the moment like any other bind; `testRegisterRebindSameAccountRefreshesMoment`
    /// is where that is pinned.
    function testRegisterRebindSameAccount(bytes32 name, address account) external {
        vm.assume(account != address(0));

        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, account);

        vm.warp(block.timestamp + 1);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, account);

        assertEq(getAddress(sRegistry, name), account);
    }

    /// Re-binding survives any number of rotations, and only the most recent one
    /// counts.
    function testRegisterRebindRepeatedly(bytes32 name, address[] memory accounts) external {
        vm.assume(accounts.length > 0);
        for (uint256 i = 0; i < accounts.length; i++) {
            vm.assume(accounts[i] != address(0));
        }

        for (uint256 i = 0; i < accounts.length; i++) {
            // Each re-bind is a block later than the last, because a name's
            // moment must be strictly after the one it replaces.
            vm.warp(block.timestamp + 1);
            vm.prank(ADDRESS_REGISTRY_ROOT);
            sRegistry.register(name, accounts[i]);
            assertEq(getAddress(sRegistry, name), accounts[i]);
        }
        assertEq(getAddress(sRegistry, name), accounts[accounts.length - 1]);
    }

    /// The zero address is rejected. An unbound name reads as the zero address
    /// internally, so binding it would produce a name that is bound but
    /// unreadable.
    function testRegisterZeroAccount(bytes32 name) external {
        vm.expectRevert(abi.encodeWithSelector(IAddressRegistryV1.ZeroAccount.selector, name));
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, address(0));

        vm.expectRevert(abi.encodeWithSelector(IAddressRegistryV1.NameNotRegistered.selector, name));
        getAddress(sRegistry, name);
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

        assertEq(getAddress(sRegistry, name), bound);
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
        getAddress(sRegistry, nameB);

        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(nameB, accountB);

        assertEq(getAddress(sRegistry, nameA), accountA);
        assertEq(getAddress(sRegistry, nameB), accountB);
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

        vm.warp(block.timestamp + 1);
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

    /// Root is the CALLER, never the transaction origin. A call from a non-root
    /// account is refused even when the transaction originates from root, so no
    /// intermediary contract can borrow root's authority merely by being called
    /// by it, and root signing a transaction is not root making the call.
    function testRegisterRootIsCallerNotOrigin(address sender, bytes32 name, address account) external {
        vm.assume(sender != ADDRESS_REGISTRY_ROOT);
        vm.assume(account != address(0));

        vm.expectRevert(abi.encodeWithSelector(IAddressRegistryV1.NotRoot.selector, sender));
        vm.prank(sender, ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, account);

        vm.expectRevert(abi.encodeWithSelector(IAddressRegistryV1.NameNotRegistered.selector, name));
        getAddress(sRegistry, name);
    }

    /// A re-bind replaces the moment along with the address. The age a caller
    /// cares about is the age of the address it is about to snapshot, so a
    /// rotation makes the binding new again.
    function testRegisterRebindRefreshesMoment(
        bytes32 name,
        address bound_,
        address account,
        uint96 first,
        uint96 second
    ) external {
        vm.assume(bound_ != address(0));
        vm.assume(account != address(0));
        // A name's moment is strictly increasing, so the second bind happens
        // strictly after the first. `testRegisterRefusesClockBehindTheBinding`
        // and `testRegisterRefusesClockEqualToTheBinding` cover the other two
        // orders.
        first = uint96(bound(first, 1, type(uint96).max - 1));
        second = uint96(bound(second, uint256(first) + 1, type(uint96).max));

        vm.warp(first);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, bound_);
        assertEq(getMoment(sRegistry, name), first);

        vm.warp(second);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, account);

        assertEq(getAddress(sRegistry, name), account);
        assertEq(getMoment(sRegistry, name), second);
    }

    /// Re-binding a name to the address it already holds still refreshes the
    /// moment. The moment dates the WRITE, not the value — root re-asserting a
    /// binding is root touching it — and reporting the later moment is the
    /// conservative direction: it can only make an answer look fresher than the
    /// address really is, so a caller refusing fresh answers errs toward
    /// refusing.
    function testRegisterRebindSameAccountRefreshesMoment(bytes32 name, address account, uint96 first, uint96 second)
        external
    {
        vm.assume(account != address(0));
        // Strictly later, so the refresh is observable, and because a name's
        // moment never goes backwards.
        first = uint96(bound(first, 1, type(uint96).max - 1));
        second = uint96(bound(second, uint256(first) + 1, type(uint96).max));

        vm.warp(first);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, account);
        assertEq(getMoment(sRegistry, name), first);

        vm.warp(second);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, account);

        assertEq(getAddress(sRegistry, name), account);
        assertEq(getMoment(sRegistry, name), second);
    }

    /// A rejected `register` never moves a moment. A non-root caller cannot
    /// refresh a binding's age, which would otherwise let anybody launder a
    /// stale binding into one that looks newly reviewed.
    function testRegisterNonRootCannotMoveMoment(
        address sender,
        bytes32 name,
        address bound_,
        address account,
        uint96 first,
        uint96 second
    ) external {
        vm.assume(sender != ADDRESS_REGISTRY_ROOT);
        vm.assume(bound_ != address(0));
        first = uint96(bound(first, 1, type(uint96).max));

        vm.warp(first);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, bound_);

        vm.warp(second);
        vm.expectRevert(abi.encodeWithSelector(IAddressRegistryV1.NotRoot.selector, sender));
        vm.prank(sender);
        sRegistry.register(name, account);

        assertEq(getMoment(sRegistry, name), first);
    }

    /// A name's moment never goes backwards. A re-bind at a clock behind the
    /// moment the name carries is refused, so a caller deriving an age from the
    /// moment can never be handed one larger than the time that actually
    /// passed — which is what a clock-regressing chain would otherwise produce,
    /// making a re-bind from moments ago report as long-settled.
    function testRegisterRefusesClockBehindTheBinding(
        bytes32 name,
        address bound_,
        address account,
        uint96 first,
        uint96 second
    ) external {
        vm.assume(bound_ != address(0));
        vm.assume(account != address(0));
        second = uint96(bound(second, 0, type(uint96).max - 1));
        first = uint96(bound(first, uint256(second) + 1, type(uint96).max));

        vm.warp(first);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, bound_);

        vm.warp(second);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAddressRegistryV1.TimestampNotAfterBinding.selector, name, uint256(second), uint256(first)
            )
        );
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, account);

        // The refused bind left the binding and its moment untouched.
        assertEq(getAddress(sRegistry, name), bound_);
        assertEq(getMoment(sRegistry, name), first);
    }

    /// A re-bind at EXACTLY the moment the name carries is refused too, so the
    /// moment is strictly increasing rather than merely non-decreasing.
    ///
    /// Two transactions in one block share a `block.timestamp`, so allowing
    /// equality would let a re-bind replace the address while leaving the moment
    /// identical — two distinct bindings that a caller cannot tell apart by the
    /// only signal the registry gives it about when the binding changed. The
    /// permissive edge is refused rather than chosen by accident.
    function testRegisterRefusesClockEqualToTheBinding(bytes32 name, address bound_, address account, uint96 time)
        external
    {
        vm.assume(bound_ != address(0));
        vm.assume(account != address(0));

        time = uint96(bound(time, 1, type(uint96).max));
        vm.warp(time);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, bound_);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAddressRegistryV1.TimestampNotAfterBinding.selector, name, uint256(time), uint256(time)
            )
        );
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, account);

        // The refused bind left the binding and its moment untouched.
        assertEq(getAddress(sRegistry, name), bound_);
        assertEq(getMoment(sRegistry, name), time);
    }

    /// One block later is enough. The rule is strictly-after, not some wider
    /// gap, so a re-bind in the very next block is accepted — which is what
    /// keeps a rotation an ordinary operation rather than a scheduled one.
    function testRegisterAllowsClockOneAfterTheBinding(bytes32 name, address bound_, address account, uint96 time)
        external
    {
        vm.assume(bound_ != address(0));
        vm.assume(account != address(0));
        time = uint96(bound(time, 1, type(uint96).max - 1));

        vm.warp(time);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, bound_);

        vm.warp(uint256(time) + 1);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, account);

        assertEq(getAddress(sRegistry, name), account);
        assertEq(getMoment(sRegistry, name), uint256(time) + 1);
    }

    /// A bind at a clock of ZERO is refused, first bind or not. The rule is
    /// unconditional, and an unbound name reads as a moment of zero, so zero is
    /// not strictly after it.
    ///
    /// That is the point rather than a side effect: zero is the unset value of
    /// the moment field, so a binding allowed to store it would be one whose
    /// moment cannot be told apart from never having been bound. Refusing it is
    /// what makes a stored moment never zero.
    function testRegisterRefusesClockZero(bytes32 name, address account) external {
        vm.assume(account != address(0));

        vm.warp(0);
        vm.expectRevert(
            abi.encodeWithSelector(IAddressRegistryV1.TimestampNotAfterBinding.selector, name, uint256(0), uint256(0))
        );
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, account);

        // Nothing was bound, so the name still reads as unbound rather than as
        // bound with a zero moment.
        vm.expectRevert(abi.encodeWithSelector(IAddressRegistryV1.NameNotRegistered.selector, name));
        getAddress(sRegistry, name);
    }

    /// A first bind at any clock past zero succeeds, and its moment is that
    /// clock. Together with the refusal above this pins the floor: one is the
    /// earliest moment the registry will store.
    function testRegisterFirstBindAtClockOne(bytes32 name, address account) external {
        vm.assume(account != address(0));

        vm.warp(1);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, account);

        assertEq(getAddress(sRegistry, name), account);
        assertEq(getMoment(sRegistry, name), 1);
    }

    /// No bound name carries a moment of zero, whatever order the binds happen
    /// in. This is the invariant the refusal above exists to hold, asserted
    /// over a run of binds rather than at one point.
    function testRegisterMomentNeverZero(bytes32 name, address[] memory accounts, uint96 start) external {
        vm.assume(accounts.length > 0);
        start = uint96(bound(start, 1, type(uint96).max - accounts.length));
        for (uint256 i = 0; i < accounts.length; i++) {
            vm.assume(accounts[i] != address(0));
        }

        for (uint256 i = 0; i < accounts.length; i++) {
            vm.warp(uint256(start) + i);
            vm.prank(ADDRESS_REGISTRY_ROOT);
            sRegistry.register(name, accounts[i]);
            assertTrue(getMoment(sRegistry, name) != 0);
        }
    }

    /// The rule is per name: a name's moment constrains only its own re-binds,
    /// so a clock behind ONE name's moment does not stop another name being
    /// bound.
    function testRegisterMonotonicityIsPerName(bytes32 nameA, bytes32 nameB, address account, uint96 high, uint96 low)
        external
    {
        vm.assume(nameA != nameB);
        vm.assume(account != address(0));
        low = uint96(bound(low, 1, type(uint96).max - 1));
        high = uint96(bound(high, uint256(low) + 1, type(uint96).max));

        vm.warp(high);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(nameA, account);

        // The clock is now behind nameA's moment, but nameB has none of its own.
        vm.warp(low);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(nameB, account);

        assertEq(getMoment(sRegistry, nameA), high);
        assertEq(getMoment(sRegistry, nameB), low);
    }

    /// A zero-address `register` never moves a moment either, so there is no way
    /// to refresh a binding's age without also re-asserting its address.
    function testRegisterZeroAccountCannotMoveMoment(bytes32 name, address bound_, uint96 first, uint96 second)
        external
    {
        vm.assume(bound_ != address(0));
        first = uint96(bound(first, 1, type(uint96).max));

        vm.warp(first);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, bound_);

        vm.warp(second);
        vm.expectRevert(abi.encodeWithSelector(IAddressRegistryV1.ZeroAccount.selector, name));
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, address(0));

        assertEq(getMoment(sRegistry, name), first);
    }
}
