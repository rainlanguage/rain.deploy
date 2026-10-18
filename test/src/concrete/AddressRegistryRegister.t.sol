// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, Vm} from "forge-std-1.17.0/src/Test.sol";

import {IAddressRegistryV2} from "../../../src/interface/IAddressRegistryV2.sol";
import {AddressRegistry, ADDRESS_REGISTRY_ROOT} from "../../../src/concrete/AddressRegistry.sol";

/// @title AddressRegistryRegisterTest
/// @notice Tests for `AddressRegistry.register`: who may bind a name, that root
/// may re-bind one, and what a binding may never become.
contract AddressRegistryRegisterTest is Test {
    /// The registry under test.
    AddressRegistry internal sRegistry;

    function setUp() external {
        sRegistry = new AddressRegistry();
    }

    /// The value half of `get`.
    /// @param registry The registry to read.
    /// @param name The name to read.
    /// @return The value bound to `name`.
    function getValue(AddressRegistry registry, bytes32 name) internal view returns (bytes memory) {
        (bytes memory value,) = registry.get(name);
        return value;
    }

    /// The moment half of `get`.
    /// @param registry The registry to read.
    /// @param name The name to read.
    /// @return The moment `name` was most recently bound.
    function getMoment(AddressRegistry registry, bytes32 name) internal view returns (uint256) {
        (, uint256 registeredAt) = registry.get(name);
        return registeredAt;
    }

    /// Only root may bind a name, and a non-root caller is rejected as `NotRoot`
    /// whatever it passes — the root check runs before the empty-value one.
    function testRegisterOnlyRoot(address sender, bytes32 name, bytes memory value) external {
        vm.assume(sender != ADDRESS_REGISTRY_ROOT);

        vm.expectRevert(abi.encodeWithSelector(IAddressRegistryV2.NotRoot.selector, sender));
        vm.prank(sender);
        sRegistry.register(name, value);
    }

    /// Re-binding is root's alone, and the failed attempt leaves the binding
    /// untouched.
    function testRegisterRebindOnlyRoot(address sender, bytes32 name, bytes memory bound_, bytes memory value)
        external
    {
        vm.assume(sender != ADDRESS_REGISTRY_ROOT);
        vm.assume(bound_.length > 0);

        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, bound_);

        vm.expectRevert(abi.encodeWithSelector(IAddressRegistryV2.NotRoot.selector, sender));
        vm.prank(sender);
        sRegistry.register(name, value);

        assertEq(getValue(sRegistry, name), bound_);
    }

    /// Root may re-bind a name to a different value, and the new binding is
    /// what `get` answers with from then on.
    function testRegisterRebind(bytes32 name, bytes memory bound_, bytes memory value) external {
        vm.assume(bound_.length > 0);
        vm.assume(value.length > 0);

        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, bound_);
        assertEq(getValue(sRegistry, name), bound_);

        // A re-bind has to be in a later block than the bind it replaces.
        vm.warp(block.timestamp + 1);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, value);
        assertEq(getValue(sRegistry, name), value);
    }

    /// A re-bind replaces the value whole, whichever of the two is longer: a
    /// value moving between the short and long storage encodings, or shrinking
    /// within the long one, leaves nothing of the old value behind.
    function testRegisterRebindAcrossLengths() external {
        bytes32 name = keccak256("a.b");
        bytes[6] memory values = [
            bytes(hex"01"),
            abi.encode(uint256(type(uint256).max), uint256(type(uint256).max), uint256(type(uint256).max)),
            bytes(hex"02"),
            abi.encodePacked(bytes31(type(uint248).max)),
            abi.encodePacked(bytes32(type(uint256).max), bytes1(0xff)),
            abi.encodePacked(bytes32(uint256(1)))
        ];
        for (uint256 i = 0; i < values.length; i++) {
            vm.warp(i + 1);
            vm.prank(ADDRESS_REGISTRY_ROOT);
            sRegistry.register(name, values[i]);
            assertEq(getValue(sRegistry, name), values[i]);
        }
    }

    /// Re-binding a name to the value it already holds is allowed and leaves the
    /// value it answers with unchanged.
    function testRegisterRebindSameValue(bytes32 name, bytes memory value) external {
        vm.assume(value.length > 0);

        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, value);

        vm.warp(block.timestamp + 1);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, value);

        assertEq(getValue(sRegistry, name), value);
    }

    /// Re-binding survives any number of rotations, and only the most recent one
    /// counts.
    function testRegisterRebindRepeatedly(bytes32 name, bytes[] memory values) external {
        vm.assume(values.length > 0);
        for (uint256 i = 0; i < values.length; i++) {
            vm.assume(values[i].length > 0);
        }

        for (uint256 i = 0; i < values.length; i++) {
            // Each re-bind is a block later than the last.
            vm.warp(block.timestamp + 1);
            vm.prank(ADDRESS_REGISTRY_ROOT);
            sRegistry.register(name, values[i]);
            assertEq(getValue(sRegistry, name), values[i]);
        }
        assertEq(getValue(sRegistry, name), values[values.length - 1]);
    }

    /// An empty value is rejected, and the name is left unbound.
    function testRegisterEmptyValue(bytes32 name) external {
        vm.expectRevert(abi.encodeWithSelector(IAddressRegistryV2.EmptyValue.selector, name));
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, "");

        vm.expectRevert(abi.encodeWithSelector(IAddressRegistryV2.NameNotRegistered.selector, name));
        getValue(sRegistry, name);
    }

    /// A single byte is the shortest value accepted: the refusal is of empty,
    /// not of short.
    function testRegisterOneByteValue(bytes32 name, bytes1 b) external {
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, abi.encodePacked(b));

        assertEq(getValue(sRegistry, name), abi.encodePacked(b));
    }

    /// An empty value is rejected for an already bound name too, so a name
    /// cannot be unbound by re-binding it to nothing.
    function testRegisterEmptyValueCannotUnbind(bytes32 name, bytes memory bound_) external {
        vm.assume(bound_.length > 0);

        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, bound_);

        vm.expectRevert(abi.encodeWithSelector(IAddressRegistryV2.EmptyValue.selector, name));
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, "");

        assertEq(getValue(sRegistry, name), bound_);
    }

    /// Names are independent: binding one says nothing about any other.
    function testRegisterDistinctNames(bytes32 nameA, bytes32 nameB, bytes memory valueA, bytes memory valueB)
        external
    {
        vm.assume(nameA != nameB);
        vm.assume(valueA.length > 0);
        vm.assume(valueB.length > 0);

        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(nameA, valueA);

        // Binding `nameA` did not bind `nameB`.
        vm.expectRevert(abi.encodeWithSelector(IAddressRegistryV2.NameNotRegistered.selector, nameB));
        getValue(sRegistry, nameB);

        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(nameB, valueB);

        assertEq(getValue(sRegistry, nameA), valueA);
        assertEq(getValue(sRegistry, nameB), valueB);
    }

    /// `Register` is emitted once, with the name indexed and the value whole in
    /// the data, so the log holds the value itself rather than its hash.
    function testRegisterEvent(bytes32 name, bytes memory value) external {
        vm.assume(value.length > 0);

        vm.recordLogs();
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, value);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        assertEq(entries.length, 1);
        assertEq(entries[0].emitter, address(sRegistry));
        assertEq(entries[0].topics.length, 2);
        assertEq(entries[0].topics[0], keccak256("Register(bytes32,bytes)"));
        assertEq(entries[0].topics[1], name);
        assertEq(entries[0].data, abi.encode(value));
    }

    /// A re-binding emits its own `Register`, so the most recent entry for a
    /// name is its current binding.
    function testRegisterRebindEvent(bytes32 name, bytes memory bound_, bytes memory value) external {
        vm.assume(bound_.length > 0);
        vm.assume(value.length > 0);

        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, bound_);

        vm.warp(block.timestamp + 1);
        vm.recordLogs();
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, value);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        assertEq(entries.length, 1);
        assertEq(entries[0].topics[1], name);
        assertEq(entries[0].data, abi.encode(value));
    }

    /// A rejected `register` emits nothing.
    function testRegisterNoEventOnRevert(address sender, bytes32 name, bytes memory value) external {
        vm.assume(sender != ADDRESS_REGISTRY_ROOT);

        vm.recordLogs();
        vm.expectRevert(abi.encodeWithSelector(IAddressRegistryV2.NotRoot.selector, sender));
        vm.prank(sender);
        sRegistry.register(name, value);
        assertEq(vm.getRecordedLogs().length, 0);
    }

    /// Root is the CALLER, never the transaction origin: a call from a non-root
    /// account is refused even when the transaction originates from root.
    function testRegisterRootIsCallerNotOrigin(address sender, bytes32 name, bytes memory value) external {
        vm.assume(sender != ADDRESS_REGISTRY_ROOT);
        vm.assume(value.length > 0);

        vm.expectRevert(abi.encodeWithSelector(IAddressRegistryV2.NotRoot.selector, sender));
        vm.prank(sender, ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, value);

        vm.expectRevert(abi.encodeWithSelector(IAddressRegistryV2.NameNotRegistered.selector, name));
        getValue(sRegistry, name);
    }

    /// A re-bind replaces the moment along with the value.
    function testRegisterRebindRefreshesMoment(
        bytes32 name,
        bytes memory bound_,
        bytes memory value,
        uint256 first,
        uint256 second
    ) external {
        vm.assume(bound_.length > 0);
        vm.assume(value.length > 0);
        // The second bind happens strictly after the first.
        first = bound(first, 1, type(uint256).max - 1);
        second = bound(second, first + 1, type(uint256).max);

        vm.warp(first);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, bound_);
        assertEq(getMoment(sRegistry, name), first);

        vm.warp(second);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, value);

        assertEq(getValue(sRegistry, name), value);
        assertEq(getMoment(sRegistry, name), second);
    }

    /// Re-binding a name to the value it already holds still refreshes the
    /// moment: the moment dates the WRITE, not the value.
    function testRegisterRebindSameValueRefreshesMoment(bytes32 name, bytes memory value, uint256 first, uint256 second)
        external
    {
        vm.assume(value.length > 0);
        // Strictly later, so the refresh is observable.
        first = bound(first, 1, type(uint256).max - 1);
        second = bound(second, first + 1, type(uint256).max);

        vm.warp(first);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, value);
        assertEq(getMoment(sRegistry, name), first);

        vm.warp(second);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, value);

        assertEq(getValue(sRegistry, name), value);
        assertEq(getMoment(sRegistry, name), second);
    }

    /// A non-root caller cannot refresh a binding's age.
    function testRegisterNonRootCannotMoveMoment(
        address sender,
        bytes32 name,
        bytes memory bound_,
        bytes memory value,
        uint256 first,
        uint256 second
    ) external {
        vm.assume(sender != ADDRESS_REGISTRY_ROOT);
        vm.assume(bound_.length > 0);
        first = bound(first, 1, type(uint256).max);

        vm.warp(first);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, bound_);

        vm.warp(second);
        vm.expectRevert(abi.encodeWithSelector(IAddressRegistryV2.NotRoot.selector, sender));
        vm.prank(sender);
        sRegistry.register(name, value);

        assertEq(getMoment(sRegistry, name), first);
    }

    /// A re-bind at a clock behind the moment the name carries is refused, and
    /// leaves the binding and its moment untouched.
    function testRegisterRefusesClockBehindTheBinding(
        bytes32 name,
        bytes memory bound_,
        bytes memory value,
        uint256 first,
        uint256 second
    ) external {
        vm.assume(bound_.length > 0);
        vm.assume(value.length > 0);
        second = bound(second, 0, type(uint256).max - 1);
        first = bound(first, second + 1, type(uint256).max);

        vm.warp(first);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, bound_);

        vm.warp(second);
        vm.expectRevert(abi.encodeWithSelector(IAddressRegistryV2.TimestampNotAfterBinding.selector, name, second, first));
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, value);

        assertEq(getValue(sRegistry, name), bound_);
        assertEq(getMoment(sRegistry, name), first);
    }

    /// A re-bind at EXACTLY the moment the name carries is refused too, so the
    /// moment is strictly increasing rather than merely non-decreasing. The
    /// binding and its moment are left untouched.
    function testRegisterRefusesClockEqualToTheBinding(
        bytes32 name,
        bytes memory bound_,
        bytes memory value,
        uint256 time
    ) external {
        vm.assume(bound_.length > 0);
        vm.assume(value.length > 0);

        time = bound(time, 1, type(uint256).max);
        vm.warp(time);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, bound_);

        vm.expectRevert(abi.encodeWithSelector(IAddressRegistryV2.TimestampNotAfterBinding.selector, name, time, time));
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, value);

        assertEq(getValue(sRegistry, name), bound_);
        assertEq(getMoment(sRegistry, name), time);
    }

    /// One block later is enough: the rule is strictly-after, not some wider
    /// gap, so a re-bind in the very next block is accepted.
    function testRegisterAllowsClockOneAfterTheBinding(
        bytes32 name,
        bytes memory bound_,
        bytes memory value,
        uint256 time
    ) external {
        vm.assume(bound_.length > 0);
        vm.assume(value.length > 0);
        time = bound(time, 1, type(uint256).max - 1);

        vm.warp(time);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, bound_);

        vm.warp(time + 1);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, value);

        assertEq(getValue(sRegistry, name), value);
        assertEq(getMoment(sRegistry, name), time + 1);
    }

    /// A bind at a clock of ZERO is refused, first bind or not, and the name
    /// still reads as unbound rather than as bound with a zero moment.
    function testRegisterRefusesClockZero(bytes32 name, bytes memory value) external {
        vm.assume(value.length > 0);

        vm.warp(0);
        vm.expectRevert(
            abi.encodeWithSelector(IAddressRegistryV2.TimestampNotAfterBinding.selector, name, uint256(0), uint256(0))
        );
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, value);

        vm.expectRevert(abi.encodeWithSelector(IAddressRegistryV2.NameNotRegistered.selector, name));
        getValue(sRegistry, name);
    }

    /// A first bind at a clock of one succeeds, and its moment is that clock, so
    /// one is the earliest moment the registry will store.
    function testRegisterFirstBindAtClockOne(bytes32 name, bytes memory value) external {
        vm.assume(value.length > 0);

        vm.warp(1);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, value);

        assertEq(getValue(sRegistry, name), value);
        assertEq(getMoment(sRegistry, name), 1);
    }

    /// No bound name carries a moment of zero, asserted over a run of binds.
    function testRegisterMomentNeverZero(bytes32 name, bytes[] memory values, uint256 start) external {
        vm.assume(values.length > 0);
        start = bound(start, 1, type(uint256).max - values.length);
        for (uint256 i = 0; i < values.length; i++) {
            vm.assume(values[i].length > 0);
        }

        for (uint256 i = 0; i < values.length; i++) {
            vm.warp(start + i);
            vm.prank(ADDRESS_REGISTRY_ROOT);
            sRegistry.register(name, values[i]);
            assertTrue(getMoment(sRegistry, name) != 0);
        }
    }

    /// The rule is per name: a clock behind ONE name's moment does not stop
    /// another name being bound.
    function testRegisterMonotonicityIsPerName(
        bytes32 nameA,
        bytes32 nameB,
        bytes memory value,
        uint256 high,
        uint256 low
    ) external {
        vm.assume(nameA != nameB);
        vm.assume(value.length > 0);
        low = bound(low, 1, type(uint256).max - 1);
        high = bound(high, low + 1, type(uint256).max);

        vm.warp(high);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(nameA, value);

        // The clock is now behind nameA's moment.
        vm.warp(low);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(nameB, value);

        assertEq(getMoment(sRegistry, nameA), high);
        assertEq(getMoment(sRegistry, nameB), low);
    }

    /// An empty-value `register` never moves a moment either.
    function testRegisterEmptyValueCannotMoveMoment(bytes32 name, bytes memory bound_, uint256 first, uint256 second)
        external
    {
        vm.assume(bound_.length > 0);
        first = bound(first, 1, type(uint256).max);

        vm.warp(first);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, bound_);

        vm.warp(second);
        vm.expectRevert(abi.encodeWithSelector(IAddressRegistryV2.EmptyValue.selector, name));
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, "");

        assertEq(getMoment(sRegistry, name), first);
    }
}
