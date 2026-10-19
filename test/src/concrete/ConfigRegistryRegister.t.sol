// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, Vm} from "forge-std-1.17.0/src/Test.sol";

import {IConfigRegistryV1} from "../../../src/interface/IConfigRegistryV1.sol";
import {ConfigRegistry, CONFIG_REGISTRY_ROOT} from "../../../src/concrete/ConfigRegistry.sol";
import {LibConfigRegistryRead} from "../../lib/LibConfigRegistryRead.sol";

/// @title ConfigRegistryRegisterTest
/// @notice Tests for `ConfigRegistry.registerV1`: who may bind a name, that root
/// may re-bind one, and what a binding may never become.
contract ConfigRegistryRegisterTest is Test {
    /// The registry under test.
    ConfigRegistry internal sRegistry;

    function setUp() external {
        sRegistry = new ConfigRegistry();
    }

    /// Only root may bind a name, and a non-root caller is rejected as `NotRoot`
    /// whatever it passes — the root check runs before the empty-value one.
    function testRegisterOnlyRoot(address sender, bytes32 name, bytes memory value) external {
        vm.assume(sender != CONFIG_REGISTRY_ROOT);

        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV1.NotRoot.selector, sender));
        vm.prank(sender);
        sRegistry.registerV1(name, value);
    }

    /// A non-root caller with an empty value is refused as `NotRoot`, not
    /// `EmptyValue`: the root check runs first.
    function testRegisterNonRootEmptyValueIsNotRoot(address sender, bytes32 name) external {
        vm.assume(sender != CONFIG_REGISTRY_ROOT);

        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV1.NotRoot.selector, sender));
        vm.prank(sender);
        sRegistry.registerV1(name, "");
    }

    /// Re-binding is root's alone, and the failed attempt leaves the binding
    /// untouched.
    function testRegisterRebindOnlyRoot(address sender, bytes32 name, bytes memory boundValue, bytes memory value)
        external
    {
        vm.assume(sender != CONFIG_REGISTRY_ROOT);
        vm.assume(boundValue.length > 0);

        vm.prank(CONFIG_REGISTRY_ROOT);
        sRegistry.registerV1(name, boundValue);

        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV1.NotRoot.selector, sender));
        vm.prank(sender);
        sRegistry.registerV1(name, value);

        assertEq(LibConfigRegistryRead.getValue(sRegistry, name), boundValue);
    }

    /// Root may re-bind a name to a different value, and the new binding is
    /// what `getV1` answers with from then on.
    function testRegisterRebind(bytes32 name, bytes memory boundValue, bytes memory value) external {
        vm.assume(boundValue.length > 0);
        vm.assume(value.length > 0);

        vm.prank(CONFIG_REGISTRY_ROOT);
        sRegistry.registerV1(name, boundValue);
        assertEq(LibConfigRegistryRead.getValue(sRegistry, name), boundValue);

        // A re-bind has to be in a later block than the bind it replaces.
        vm.warp(block.timestamp + 1);
        vm.prank(CONFIG_REGISTRY_ROOT);
        sRegistry.registerV1(name, value);
        assertEq(LibConfigRegistryRead.getValue(sRegistry, name), value);
    }

    /// A re-bind replaces the value whole, whichever of the two is longer: a
    /// value moving between the short and long storage encodings, or shrinking
    /// within the long one, leaves nothing of the old value behind in storage.
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
            vm.prank(CONFIG_REGISTRY_ROOT);
            sRegistry.registerV1(name, values[i]);
            assertEq(LibConfigRegistryRead.getValue(sRegistry, name), values[i]);
            assertStoredBinding(name, values[i], i + 1);
        }
    }

    /// Asserts the raw storage of `name`'s binding. `sBindings` is slot 0;
    /// `value` is the struct's first slot and `registeredAt` its second. A
    /// value under 32 bytes is stored left-aligned with `length * 2` in the low
    /// byte; a longer one as `length * 2 + 1`, its bytes from
    /// `keccak256(base)`. Slots `data + 0..2` cover every value here, the
    /// longest being three words, and any not holding this value are zero.
    /// @param name The bound name.
    /// @param value The value it is bound to.
    /// @param moment The moment it was bound at.
    function assertStoredBinding(bytes32 name, bytes memory value, uint256 moment) internal view {
        bytes32 base = keccak256(abi.encode(name, uint256(0)));
        uint256 data = uint256(keccak256(abi.encode(base)));
        bool short = value.length < 32;
        bytes memory padded = bytes.concat(value, new bytes(96));
        assertEq(
            vm.load(address(sRegistry), base),
            short ? wordAt(padded, 0) | bytes32(value.length * 2) : bytes32(value.length * 2 + 1)
        );
        for (uint256 k = 0; k < 3; k++) {
            bytes32 expected = !short && k * 32 < value.length ? wordAt(padded, k) : bytes32(0);
            assertEq(vm.load(address(sRegistry), bytes32(data + k)), expected);
        }
        assertEq(uint256(vm.load(address(sRegistry), bytes32(uint256(base) + 1))), moment);
    }

    /// The `k`th 32-byte word of `b`.
    /// @param b The bytes, at least `(k + 1) * 32` long.
    /// @param k The word index.
    /// @return The word.
    function wordAt(bytes memory b, uint256 k) internal pure returns (bytes32) {
        bytes32 word;
        assembly ("memory-safe") {
            word := mload(add(add(b, 0x20), mul(k, 0x20)))
        }
        return word;
    }

    /// Re-binding a name to the value it already holds is allowed and leaves the
    /// value it answers with unchanged.
    function testRegisterRebindSameValue(bytes32 name, bytes memory value) external {
        vm.assume(value.length > 0);

        vm.prank(CONFIG_REGISTRY_ROOT);
        sRegistry.registerV1(name, value);

        vm.warp(block.timestamp + 1);
        vm.prank(CONFIG_REGISTRY_ROOT);
        sRegistry.registerV1(name, value);

        assertEq(LibConfigRegistryRead.getValue(sRegistry, name), value);
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
            vm.warp(vm.getBlockTimestamp() + 1);
            vm.prank(CONFIG_REGISTRY_ROOT);
            sRegistry.registerV1(name, values[i]);
            assertEq(LibConfigRegistryRead.getValue(sRegistry, name), values[i]);
        }
        assertEq(LibConfigRegistryRead.getValue(sRegistry, name), values[values.length - 1]);
    }

    /// An empty value is rejected, and the name is left unbound.
    function testRegisterEmptyValue(bytes32 name) external {
        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV1.EmptyValue.selector, name));
        vm.prank(CONFIG_REGISTRY_ROOT);
        sRegistry.registerV1(name, "");

        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV1.NameNotRegistered.selector, name));
        LibConfigRegistryRead.getValue(sRegistry, name);
    }

    /// The empty tuple is the only ABI encoding that is empty, so it is the
    /// only one refused.
    function testRegisterEmptyTupleIsTheEmptyValue(bytes32 name) external {
        assertEq(abi.encode().length, 0);
        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV1.EmptyValue.selector, name));
        vm.prank(CONFIG_REGISTRY_ROOT);
        sRegistry.registerV1(name, abi.encode());
    }

    /// The zero value of every kind of type Solidity can encode is at least one
    /// word, so it binds and reads back exactly: a static zero, a zero in a
    /// fixed array or struct-shaped tuple, and an empty dynamic value. Solidity
    /// has no empty struct and no zero-length fixed array to encode.
    function testRegisterZeroValuesOfEveryKindBind(bytes32 name) external {
        bytes[] memory values = new bytes[](11);
        values[0] = abi.encode(false);
        values[1] = abi.encode(address(0));
        values[2] = abi.encode(uint8(0));
        values[3] = abi.encode(int256(0));
        values[4] = abi.encode(bytes1(0));
        values[5] = abi.encode(bytes32(0));
        values[6] = abi.encode([uint256(0)]);
        values[7] = abi.encode(uint256(0), address(0));
        values[8] = abi.encode("");
        values[9] = abi.encode(bytes(""));
        values[10] = abi.encode(new uint256[](0));
        for (uint256 i = 0; i < values.length; i++) {
            assertGe(values[i].length, 32);
            vm.warp(vm.getBlockTimestamp() + 1);
            vm.prank(CONFIG_REGISTRY_ROOT);
            sRegistry.registerV1(name, values[i]);
            assertEq(LibConfigRegistryRead.getValue(sRegistry, name), values[i]);
        }
    }

    /// A single byte is the shortest value accepted: the refusal is of empty,
    /// not of short.
    function testRegisterOneByteValue(bytes32 name, bytes1 b) external {
        vm.prank(CONFIG_REGISTRY_ROOT);
        sRegistry.registerV1(name, abi.encodePacked(b));

        assertEq(LibConfigRegistryRead.getValue(sRegistry, name), abi.encodePacked(b));
    }

    /// An empty value is rejected for an already bound name too, so a name
    /// cannot be unbound by re-binding it to nothing.
    function testRegisterEmptyValueCannotUnbind(bytes32 name, bytes memory boundValue) external {
        vm.assume(boundValue.length > 0);

        vm.prank(CONFIG_REGISTRY_ROOT);
        sRegistry.registerV1(name, boundValue);

        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV1.EmptyValue.selector, name));
        vm.prank(CONFIG_REGISTRY_ROOT);
        sRegistry.registerV1(name, "");

        assertEq(LibConfigRegistryRead.getValue(sRegistry, name), boundValue);
    }

    /// Names are independent: binding one says nothing about any other.
    function testRegisterDistinctNames(bytes32 nameA, bytes32 nameB, bytes memory valueA, bytes memory valueB)
        external
    {
        vm.assume(nameA != nameB);
        vm.assume(valueA.length > 0);
        vm.assume(valueB.length > 0);

        vm.prank(CONFIG_REGISTRY_ROOT);
        sRegistry.registerV1(nameA, valueA);

        // Binding `nameA` did not bind `nameB`.
        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV1.NameNotRegistered.selector, nameB));
        LibConfigRegistryRead.getValue(sRegistry, nameB);

        vm.prank(CONFIG_REGISTRY_ROOT);
        sRegistry.registerV1(nameB, valueB);

        assertEq(LibConfigRegistryRead.getValue(sRegistry, nameA), valueA);
        assertEq(LibConfigRegistryRead.getValue(sRegistry, nameB), valueB);
    }

    /// `Register` is emitted once, with the name indexed and the value whole in
    /// the data, so the log holds the value itself rather than its hash.
    function testRegisterEvent(bytes32 name, bytes memory value) external {
        vm.assume(value.length > 0);

        vm.recordLogs();
        vm.prank(CONFIG_REGISTRY_ROOT);
        sRegistry.registerV1(name, value);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        assertEq(entries.length, 1);
        assertEq(entries[0].emitter, address(sRegistry));
        assertEq(entries[0].topics.length, 2);
        assertEq(entries[0].topics[0], keccak256("Register(address,bytes32,bytes)"));
        assertEq(entries[0].topics[1], name);
        assertEq(entries[0].data, abi.encode(CONFIG_REGISTRY_ROOT, value));
    }

    /// A re-binding emits its own `Register`, so the most recent entry for a
    /// name is its current binding.
    function testRegisterRebindEvent(bytes32 name, bytes memory boundValue, bytes memory value) external {
        vm.assume(boundValue.length > 0);
        vm.assume(value.length > 0);

        vm.prank(CONFIG_REGISTRY_ROOT);
        sRegistry.registerV1(name, boundValue);

        vm.warp(block.timestamp + 1);
        vm.recordLogs();
        vm.prank(CONFIG_REGISTRY_ROOT);
        sRegistry.registerV1(name, value);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        assertEq(entries.length, 1);
        assertEq(entries[0].emitter, address(sRegistry));
        assertEq(entries[0].topics.length, 2);
        assertEq(entries[0].topics[0], keccak256("Register(address,bytes32,bytes)"));
        assertEq(entries[0].topics[1], name);
        assertEq(entries[0].data, abi.encode(CONFIG_REGISTRY_ROOT, value));
    }

    /// Re-binding a name to the value it already holds is a bind like any
    /// other, so it emits its own `Register` too.
    function testRegisterRebindSameValueEvent(bytes32 name, bytes memory value) external {
        vm.assume(value.length > 0);

        vm.prank(CONFIG_REGISTRY_ROOT);
        sRegistry.registerV1(name, value);

        vm.warp(block.timestamp + 1);
        vm.recordLogs();
        vm.prank(CONFIG_REGISTRY_ROOT);
        sRegistry.registerV1(name, value);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        assertEq(entries.length, 1);
        assertEq(entries[0].emitter, address(sRegistry));
        assertEq(entries[0].topics.length, 2);
        assertEq(entries[0].topics[0], keccak256("Register(address,bytes32,bytes)"));
        assertEq(entries[0].topics[1], name);
        assertEq(entries[0].data, abi.encode(CONFIG_REGISTRY_ROOT, value));
    }

    /// A rejected `registerV1` emits nothing.
    function testRegisterNoEventOnRevert(address sender, bytes32 name, bytes memory value) external {
        vm.assume(sender != CONFIG_REGISTRY_ROOT);

        vm.recordLogs();
        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV1.NotRoot.selector, sender));
        vm.prank(sender);
        sRegistry.registerV1(name, value);
        assertEq(vm.getRecordedLogs().length, 0);
    }

    /// Root is the CALLER, never the transaction origin: a call from a non-root
    /// account is refused even when the transaction originates from root.
    function testRegisterRootIsCallerNotOrigin(address sender, bytes32 name, bytes memory value) external {
        vm.assume(sender != CONFIG_REGISTRY_ROOT);
        vm.assume(value.length > 0);

        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV1.NotRoot.selector, sender));
        vm.prank(sender, CONFIG_REGISTRY_ROOT);
        sRegistry.registerV1(name, value);

        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV1.NameNotRegistered.selector, name));
        LibConfigRegistryRead.getValue(sRegistry, name);
    }

    /// A re-bind replaces the moment along with the value.
    function testRegisterRebindRefreshesMoment(
        bytes32 name,
        bytes memory boundValue,
        bytes memory value,
        uint256 first,
        uint256 second
    ) external {
        vm.assume(boundValue.length > 0);
        vm.assume(value.length > 0);
        // The second bind happens strictly after the first.
        first = bound(first, 1, type(uint256).max - 1);
        second = bound(second, first + 1, type(uint256).max);

        vm.warp(first);
        vm.prank(CONFIG_REGISTRY_ROOT);
        sRegistry.registerV1(name, boundValue);
        assertEq(LibConfigRegistryRead.getMoment(sRegistry, name), first);

        vm.warp(second);
        vm.prank(CONFIG_REGISTRY_ROOT);
        sRegistry.registerV1(name, value);

        assertEq(LibConfigRegistryRead.getValue(sRegistry, name), value);
        assertEq(LibConfigRegistryRead.getMoment(sRegistry, name), second);
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
        vm.prank(CONFIG_REGISTRY_ROOT);
        sRegistry.registerV1(name, value);
        assertEq(LibConfigRegistryRead.getMoment(sRegistry, name), first);

        vm.warp(second);
        vm.prank(CONFIG_REGISTRY_ROOT);
        sRegistry.registerV1(name, value);

        assertEq(LibConfigRegistryRead.getValue(sRegistry, name), value);
        assertEq(LibConfigRegistryRead.getMoment(sRegistry, name), second);
    }

    /// A non-root caller cannot refresh a binding's age.
    function testRegisterNonRootCannotMoveMoment(
        address sender,
        bytes32 name,
        bytes memory boundValue,
        bytes memory value,
        uint256 first,
        uint256 second
    ) external {
        vm.assume(sender != CONFIG_REGISTRY_ROOT);
        vm.assume(boundValue.length > 0);
        first = bound(first, 1, type(uint256).max);

        vm.warp(first);
        vm.prank(CONFIG_REGISTRY_ROOT);
        sRegistry.registerV1(name, boundValue);

        vm.warp(second);
        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV1.NotRoot.selector, sender));
        vm.prank(sender);
        sRegistry.registerV1(name, value);

        assertEq(LibConfigRegistryRead.getMoment(sRegistry, name), first);
    }

    /// A re-bind at a clock behind the moment the name carries is refused, and
    /// leaves the binding and its moment untouched.
    function testRegisterRefusesClockBehindTheBinding(
        bytes32 name,
        bytes memory boundValue,
        bytes memory value,
        uint256 first,
        uint256 second
    ) external {
        vm.assume(boundValue.length > 0);
        vm.assume(value.length > 0);
        second = bound(second, 0, type(uint256).max - 1);
        first = bound(first, second + 1, type(uint256).max);

        vm.warp(first);
        vm.prank(CONFIG_REGISTRY_ROOT);
        sRegistry.registerV1(name, boundValue);

        vm.warp(second);
        vm.expectRevert(
            abi.encodeWithSelector(IConfigRegistryV1.TimestampNotAfterBinding.selector, name, second, first)
        );
        vm.prank(CONFIG_REGISTRY_ROOT);
        sRegistry.registerV1(name, value);

        assertEq(LibConfigRegistryRead.getValue(sRegistry, name), boundValue);
        assertEq(LibConfigRegistryRead.getMoment(sRegistry, name), first);
    }

    /// A re-bind at EXACTLY the moment the name carries is refused too, so the
    /// moment is strictly increasing rather than merely non-decreasing. The
    /// binding and its moment are left untouched.
    function testRegisterRefusesClockEqualToTheBinding(
        bytes32 name,
        bytes memory boundValue,
        bytes memory value,
        uint256 time
    ) external {
        vm.assume(boundValue.length > 0);
        vm.assume(value.length > 0);

        time = bound(time, 1, type(uint256).max);
        vm.warp(time);
        vm.prank(CONFIG_REGISTRY_ROOT);
        sRegistry.registerV1(name, boundValue);

        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV1.TimestampNotAfterBinding.selector, name, time, time));
        vm.prank(CONFIG_REGISTRY_ROOT);
        sRegistry.registerV1(name, value);

        assertEq(LibConfigRegistryRead.getValue(sRegistry, name), boundValue);
        assertEq(LibConfigRegistryRead.getMoment(sRegistry, name), time);
    }

    /// One block later is enough: the rule is strictly-after, not some wider
    /// gap, so a re-bind in the very next block is accepted.
    function testRegisterAllowsClockOneAfterTheBinding(
        bytes32 name,
        bytes memory boundValue,
        bytes memory value,
        uint256 time
    ) external {
        vm.assume(boundValue.length > 0);
        vm.assume(value.length > 0);
        time = bound(time, 1, type(uint256).max - 1);

        vm.warp(time);
        vm.prank(CONFIG_REGISTRY_ROOT);
        sRegistry.registerV1(name, boundValue);

        vm.warp(time + 1);
        vm.prank(CONFIG_REGISTRY_ROOT);
        sRegistry.registerV1(name, value);

        assertEq(LibConfigRegistryRead.getValue(sRegistry, name), value);
        assertEq(LibConfigRegistryRead.getMoment(sRegistry, name), time + 1);
    }

    /// A bind at a clock of ZERO is refused, first bind or not, and the name
    /// still reads as unbound rather than as bound with a zero moment.
    function testRegisterRefusesClockZero(bytes32 name, bytes memory value) external {
        vm.assume(value.length > 0);

        vm.warp(0);
        vm.expectRevert(
            abi.encodeWithSelector(IConfigRegistryV1.TimestampNotAfterBinding.selector, name, uint256(0), uint256(0))
        );
        vm.prank(CONFIG_REGISTRY_ROOT);
        sRegistry.registerV1(name, value);

        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV1.NameNotRegistered.selector, name));
        LibConfigRegistryRead.getValue(sRegistry, name);
    }

    /// A first bind at a clock of one succeeds, and its moment is that clock, so
    /// one is the earliest moment the registry will store.
    function testRegisterFirstBindAtClockOne(bytes32 name, bytes memory value) external {
        vm.assume(value.length > 0);

        vm.warp(1);
        vm.prank(CONFIG_REGISTRY_ROOT);
        sRegistry.registerV1(name, value);

        assertEq(LibConfigRegistryRead.getValue(sRegistry, name), value);
        assertEq(LibConfigRegistryRead.getMoment(sRegistry, name), 1);
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
        vm.prank(CONFIG_REGISTRY_ROOT);
        sRegistry.registerV1(nameA, value);

        // The clock is now behind nameA's moment.
        vm.warp(low);
        vm.prank(CONFIG_REGISTRY_ROOT);
        sRegistry.registerV1(nameB, value);

        assertEq(LibConfigRegistryRead.getMoment(sRegistry, nameA), high);
        assertEq(LibConfigRegistryRead.getMoment(sRegistry, nameB), low);
    }

    /// An empty-value `registerV1` never moves a moment either.
    function testRegisterEmptyValueCannotMoveMoment(
        bytes32 name,
        bytes memory boundValue,
        uint256 first,
        uint256 second
    ) external {
        vm.assume(boundValue.length > 0);
        first = bound(first, 1, type(uint256).max);

        vm.warp(first);
        vm.prank(CONFIG_REGISTRY_ROOT);
        sRegistry.registerV1(name, boundValue);

        vm.warp(second);
        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV1.EmptyValue.selector, name));
        vm.prank(CONFIG_REGISTRY_ROOT);
        sRegistry.registerV1(name, "");

        assertEq(LibConfigRegistryRead.getMoment(sRegistry, name), first);
    }
}
