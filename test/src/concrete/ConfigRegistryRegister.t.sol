// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {IRegistryDelegatesV3} from "../../../src/interface/IRegistryDelegatesV3.sol";
import {Test, Vm} from "forge-std-1.17.0/src/Test.sol";

import {IConfigRegistryV5} from "../../../src/interface/IConfigRegistryV5.sol";
import {ConfigRegistry} from "../../../src/concrete/ConfigRegistry.sol";
import {LibConfigRegistryRead} from "../../lib/LibConfigRegistryRead.sol";
import {VALUE_TYPE} from "../../lib/ConfigTestBinding.sol";

/// @title ConfigRegistryRegisterTest
/// @notice Tests for `ConfigRegistry.registerV5`: that any caller binds under
/// itself and, unapproved, under nothing else, that an authority may re-bind its own name, and what
/// a binding may never become.
contract ConfigRegistryRegisterTest is Test {
    /// The authority most tests bind under. Any account is one.
    address internal constant AUTHORITY = address(0xA11CE);

    /// The registry under test.
    ConfigRegistry internal sRegistry;

    function setUp() external {
        sRegistry = new ConfigRegistry();
    }

    /// Asserts `entry` is the one `Register` a bind of `name` to `value` under
    /// `authority` by `sender` emits: nothing indexed, the sender, the
    /// authority, the name and the whole value in the data.
    /// @param entry The log.
    /// @param sender The account that bound.
    /// @param authority The authority it bound under.
    /// @param name The name bound.
    /// @param value The value bound.
    function assertRegisterLog(Vm.Log memory entry, address sender, address authority, bytes32 name, bytes memory value)
        internal
        view
    {
        assertEq(entry.emitter, address(sRegistry));
        assertEq(entry.topics.length, 1);
        assertEq(entry.topics[0], keccak256("Register(address,address,bytes32,string,bytes)"));
        assertEq(entry.topics[0], IConfigRegistryV5.Register.selector);
        assertEq(entry.data, abi.encode(sender, authority, name, VALUE_TYPE, value));
    }

    /// Any caller binds, with no permission asked, and the binding lands under
    /// the caller: it reads back under the caller and emits `Register` naming
    /// it.
    function testRegisterAnyCallerBindsUnderItself(address sender, bytes32 name, bytes memory value) external {
        vm.assume(value.length > 0);

        vm.recordLogs();
        vm.prank(sender);
        sRegistry.registerV5(sender, name, VALUE_TYPE, value, "");
        Vm.Log[] memory entries = vm.getRecordedLogs();

        assertEq(LibConfigRegistryRead.getValue(sRegistry, sender, name), value);
        assertEq(LibConfigRegistryRead.getMoment(sRegistry, sender, name), block.timestamp);
        assertEq(entries.length, 1);
        assertRegisterLog(entries[0], sender, sender, name, value);
    }

    /// A bind lands under the caller and no other account: the same name stays
    /// unbound under every other authority.
    function testRegisterBindsUnderNoOtherAuthority(address sender, address other, bytes32 name, bytes memory value)
        external
    {
        vm.assume(sender != other);
        vm.assume(value.length > 0);

        vm.prank(sender);
        sRegistry.registerV5(sender, name, VALUE_TYPE, value, "");

        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV5.NameNotRegistered.selector, other, name));
        LibConfigRegistryRead.getValue(sRegistry, other, name);
    }

    /// Another account binding the same name, at any clock, leaves the
    /// authority's binding — value and moment — untouched, and gets a binding
    /// of its own.
    function testRegisterOtherCallerLeavesBindingUntouched(
        address sender,
        bytes32 name,
        bytes memory boundValue,
        bytes memory value,
        uint256 first,
        uint256 second
    ) external {
        vm.assume(sender != AUTHORITY);
        vm.assume(boundValue.length > 0);
        vm.assume(value.length > 0);
        first = bound(first, 1, type(uint256).max);
        second = bound(second, 1, type(uint256).max);

        vm.warp(first);
        vm.prank(AUTHORITY);
        sRegistry.registerV5(AUTHORITY, name, VALUE_TYPE, boundValue, "");

        vm.warp(second);
        vm.prank(sender);
        sRegistry.registerV5(sender, name, VALUE_TYPE, value, "");

        assertEq(LibConfigRegistryRead.getValue(sRegistry, AUTHORITY, name), boundValue);
        assertEq(LibConfigRegistryRead.getMoment(sRegistry, AUTHORITY, name), first);
        assertEq(LibConfigRegistryRead.getValue(sRegistry, sender, name), value);
        assertEq(LibConfigRegistryRead.getMoment(sRegistry, sender, name), second);
    }

    /// Who may write is the CALLER, never the transaction origin: a call made
    /// by another account in a transaction the authority originates binds
    /// under that account, and is `NotApproved` under the authority.
    function testRegisterAuthorityIsCallerNotOrigin(address sender, bytes32 name, bytes memory value) external {
        vm.assume(sender != AUTHORITY);
        vm.assume(value.length > 0);

        vm.prank(sender, AUTHORITY);
        sRegistry.registerV5(sender, name, VALUE_TYPE, value, "");

        vm.expectRevert(abi.encodeWithSelector(IRegistryDelegatesV3.NotApproved.selector, AUTHORITY, name, sender));
        vm.prank(sender, AUTHORITY);
        sRegistry.registerV5(AUTHORITY, name, VALUE_TYPE, value, "");

        assertEq(LibConfigRegistryRead.getValue(sRegistry, sender, name), value);
        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV5.NameNotRegistered.selector, AUTHORITY, name));
        LibConfigRegistryRead.getValue(sRegistry, AUTHORITY, name);
    }

    /// An empty value is refused whoever calls.
    function testRegisterEmptyValueAnyCaller(address sender, bytes32 name) external {
        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV5.EmptyValue.selector, name));
        vm.prank(sender);
        sRegistry.registerV5(sender, name, VALUE_TYPE, "", "");
    }

    /// An authority may re-bind a name to a different value, and the new
    /// binding is what `getV5` answers with from then on.
    function testRegisterRebind(bytes32 name, bytes memory boundValue, bytes memory value) external {
        vm.assume(boundValue.length > 0);
        vm.assume(value.length > 0);

        vm.prank(AUTHORITY);
        sRegistry.registerV5(AUTHORITY, name, VALUE_TYPE, boundValue, "");
        assertEq(LibConfigRegistryRead.getValue(sRegistry, AUTHORITY, name), boundValue);

        // A re-bind has to be in a later block than the bind it replaces.
        vm.warp(block.timestamp + 1);
        vm.prank(AUTHORITY);
        sRegistry.registerV5(AUTHORITY, name, VALUE_TYPE, value, "");
        assertEq(LibConfigRegistryRead.getValue(sRegistry, AUTHORITY, name), value);
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
            vm.prank(AUTHORITY);
            sRegistry.registerV5(AUTHORITY, name, VALUE_TYPE, values[i], "");
            assertEq(LibConfigRegistryRead.getValue(sRegistry, AUTHORITY, name), values[i]);
            assertStoredBinding(AUTHORITY, name, values[i], i + 1);
        }
    }

    /// Asserts the raw storage of `authority`'s binding of `name`. `sBindings`
    /// is slot 1, after the inherited `sApproved`, so the authority's inner
    /// mapping is at `keccak256(authority . 1)` and the binding at `keccak256(name . that)`;
    /// `value` is the struct's first slot and `registeredAt` its second. A
    /// value under 32 bytes is stored left-aligned with `length * 2` in the low
    /// byte; a longer one as `length * 2 + 1`, its bytes from
    /// `keccak256(base)`. Slots `data + 0..2` cover every value here, the
    /// longest being three words, and any not holding this value are zero.
    /// @param authority The authority it is bound under.
    /// @param name The bound name.
    /// @param value The value it is bound to.
    /// @param moment The moment it was bound at.
    function assertStoredBinding(address authority, bytes32 name, bytes memory value, uint256 moment) internal view {
        bytes32 base = keccak256(abi.encode(name, keccak256(abi.encode(authority, uint256(1)))));
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

        vm.prank(AUTHORITY);
        sRegistry.registerV5(AUTHORITY, name, VALUE_TYPE, value, "");

        vm.warp(block.timestamp + 1);
        vm.prank(AUTHORITY);
        sRegistry.registerV5(AUTHORITY, name, VALUE_TYPE, value, "");

        assertEq(LibConfigRegistryRead.getValue(sRegistry, AUTHORITY, name), value);
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
            vm.prank(AUTHORITY);
            sRegistry.registerV5(AUTHORITY, name, VALUE_TYPE, values[i], "");
            assertEq(LibConfigRegistryRead.getValue(sRegistry, AUTHORITY, name), values[i]);
        }
        assertEq(LibConfigRegistryRead.getValue(sRegistry, AUTHORITY, name), values[values.length - 1]);
    }

    /// An empty value is rejected, and the name is left unbound.
    function testRegisterEmptyValue(bytes32 name) external {
        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV5.EmptyValue.selector, name));
        vm.prank(AUTHORITY);
        sRegistry.registerV5(AUTHORITY, name, VALUE_TYPE, "", "");

        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV5.NameNotRegistered.selector, AUTHORITY, name));
        LibConfigRegistryRead.getValue(sRegistry, AUTHORITY, name);
    }

    /// The empty tuple is the only ABI encoding that is empty, so it is the
    /// only one refused.
    function testRegisterEmptyTupleIsTheEmptyValue(bytes32 name) external {
        assertEq(abi.encode().length, 0);
        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV5.EmptyValue.selector, name));
        vm.prank(AUTHORITY);
        sRegistry.registerV5(AUTHORITY, name, VALUE_TYPE, abi.encode(), "");
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
            vm.prank(AUTHORITY);
            sRegistry.registerV5(AUTHORITY, name, VALUE_TYPE, values[i], "");
            assertEq(LibConfigRegistryRead.getValue(sRegistry, AUTHORITY, name), values[i]);
        }
    }

    /// A single byte is the shortest value accepted: the refusal is of empty,
    /// not of short.
    function testRegisterOneByteValue(bytes32 name, bytes1 b) external {
        vm.prank(AUTHORITY);
        sRegistry.registerV5(AUTHORITY, name, VALUE_TYPE, abi.encodePacked(b), "");

        assertEq(LibConfigRegistryRead.getValue(sRegistry, AUTHORITY, name), abi.encodePacked(b));
    }

    /// An empty value is rejected for an already bound name too, so a name
    /// cannot be unbound by re-binding it to nothing.
    function testRegisterEmptyValueCannotUnbind(bytes32 name, bytes memory boundValue) external {
        vm.assume(boundValue.length > 0);

        vm.prank(AUTHORITY);
        sRegistry.registerV5(AUTHORITY, name, VALUE_TYPE, boundValue, "");

        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV5.EmptyValue.selector, name));
        vm.prank(AUTHORITY);
        sRegistry.registerV5(AUTHORITY, name, VALUE_TYPE, "", "");

        assertEq(LibConfigRegistryRead.getValue(sRegistry, AUTHORITY, name), boundValue);
    }

    /// Names are independent: binding one says nothing about any other.
    function testRegisterDistinctNames(bytes32 nameA, bytes32 nameB, bytes memory valueA, bytes memory valueB)
        external
    {
        vm.assume(nameA != nameB);
        vm.assume(valueA.length > 0);
        vm.assume(valueB.length > 0);

        vm.prank(AUTHORITY);
        sRegistry.registerV5(AUTHORITY, nameA, VALUE_TYPE, valueA, "");

        // Binding `nameA` did not bind `nameB`.
        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV5.NameNotRegistered.selector, AUTHORITY, nameB));
        LibConfigRegistryRead.getValue(sRegistry, AUTHORITY, nameB);

        vm.prank(AUTHORITY);
        sRegistry.registerV5(AUTHORITY, nameB, VALUE_TYPE, valueB, "");

        assertEq(LibConfigRegistryRead.getValue(sRegistry, AUTHORITY, nameA), valueA);
        assertEq(LibConfigRegistryRead.getValue(sRegistry, AUTHORITY, nameB), valueB);
    }

    /// `Register` is emitted once, with nothing indexed and every field, the
    /// whole value included, in the data.
    function testRegisterEvent(bytes32 name, bytes memory value) external {
        vm.assume(value.length > 0);

        vm.recordLogs();
        vm.prank(AUTHORITY);
        sRegistry.registerV5(AUTHORITY, name, VALUE_TYPE, value, "");
        Vm.Log[] memory entries = vm.getRecordedLogs();

        assertEq(entries.length, 1);
        assertRegisterLog(entries[0], AUTHORITY, AUTHORITY, name, value);
    }

    /// A re-binding emits its own `Register`, so the most recent entry for a
    /// name is its current binding.
    function testRegisterRebindEvent(bytes32 name, bytes memory boundValue, bytes memory value) external {
        vm.assume(boundValue.length > 0);
        vm.assume(value.length > 0);

        vm.prank(AUTHORITY);
        sRegistry.registerV5(AUTHORITY, name, VALUE_TYPE, boundValue, "");

        vm.warp(block.timestamp + 1);
        vm.recordLogs();
        vm.prank(AUTHORITY);
        sRegistry.registerV5(AUTHORITY, name, VALUE_TYPE, value, "");
        Vm.Log[] memory entries = vm.getRecordedLogs();

        assertEq(entries.length, 1);
        assertRegisterLog(entries[0], AUTHORITY, AUTHORITY, name, value);
    }

    /// Re-binding a name to the value it already holds is a bind like any
    /// other, so it emits its own `Register` too.
    function testRegisterRebindSameValueEvent(bytes32 name, bytes memory value) external {
        vm.assume(value.length > 0);

        vm.prank(AUTHORITY);
        sRegistry.registerV5(AUTHORITY, name, VALUE_TYPE, value, "");

        vm.warp(block.timestamp + 1);
        vm.recordLogs();
        vm.prank(AUTHORITY);
        sRegistry.registerV5(AUTHORITY, name, VALUE_TYPE, value, "");
        Vm.Log[] memory entries = vm.getRecordedLogs();

        assertEq(entries.length, 1);
        assertRegisterLog(entries[0], AUTHORITY, AUTHORITY, name, value);
    }

    /// A rejected `registerV5` emits nothing.
    function testRegisterNoEventOnRevert(address sender, bytes32 name) external {
        vm.recordLogs();
        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV5.EmptyValue.selector, name));
        vm.prank(sender);
        sRegistry.registerV5(sender, name, VALUE_TYPE, "", "");
        assertEq(vm.getRecordedLogs().length, 0);
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
        vm.prank(AUTHORITY);
        sRegistry.registerV5(AUTHORITY, name, VALUE_TYPE, boundValue, "");
        assertEq(LibConfigRegistryRead.getMoment(sRegistry, AUTHORITY, name), first);

        vm.warp(second);
        vm.prank(AUTHORITY);
        sRegistry.registerV5(AUTHORITY, name, VALUE_TYPE, value, "");

        assertEq(LibConfigRegistryRead.getValue(sRegistry, AUTHORITY, name), value);
        assertEq(LibConfigRegistryRead.getMoment(sRegistry, AUTHORITY, name), second);
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
        vm.prank(AUTHORITY);
        sRegistry.registerV5(AUTHORITY, name, VALUE_TYPE, value, "");
        assertEq(LibConfigRegistryRead.getMoment(sRegistry, AUTHORITY, name), first);

        vm.warp(second);
        vm.prank(AUTHORITY);
        sRegistry.registerV5(AUTHORITY, name, VALUE_TYPE, value, "");

        assertEq(LibConfigRegistryRead.getValue(sRegistry, AUTHORITY, name), value);
        assertEq(LibConfigRegistryRead.getMoment(sRegistry, AUTHORITY, name), second);
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
        vm.prank(AUTHORITY);
        sRegistry.registerV5(AUTHORITY, name, VALUE_TYPE, boundValue, "");

        vm.warp(second);
        vm.expectRevert(
            abi.encodeWithSelector(IConfigRegistryV5.TimestampNotAfterBinding.selector, name, second, first)
        );
        vm.prank(AUTHORITY);
        sRegistry.registerV5(AUTHORITY, name, VALUE_TYPE, value, "");

        assertEq(LibConfigRegistryRead.getValue(sRegistry, AUTHORITY, name), boundValue);
        assertEq(LibConfigRegistryRead.getMoment(sRegistry, AUTHORITY, name), first);
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
        vm.prank(AUTHORITY);
        sRegistry.registerV5(AUTHORITY, name, VALUE_TYPE, boundValue, "");

        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV5.TimestampNotAfterBinding.selector, name, time, time));
        vm.prank(AUTHORITY);
        sRegistry.registerV5(AUTHORITY, name, VALUE_TYPE, value, "");

        assertEq(LibConfigRegistryRead.getValue(sRegistry, AUTHORITY, name), boundValue);
        assertEq(LibConfigRegistryRead.getMoment(sRegistry, AUTHORITY, name), time);
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
        vm.prank(AUTHORITY);
        sRegistry.registerV5(AUTHORITY, name, VALUE_TYPE, boundValue, "");

        vm.warp(time + 1);
        vm.prank(AUTHORITY);
        sRegistry.registerV5(AUTHORITY, name, VALUE_TYPE, value, "");

        assertEq(LibConfigRegistryRead.getValue(sRegistry, AUTHORITY, name), value);
        assertEq(LibConfigRegistryRead.getMoment(sRegistry, AUTHORITY, name), time + 1);
    }

    /// A bind at a clock of ZERO is refused, first bind or not, and the name
    /// still reads as unbound rather than as bound with a zero moment.
    function testRegisterRefusesClockZero(bytes32 name, bytes memory value) external {
        vm.assume(value.length > 0);

        vm.warp(0);
        vm.expectRevert(
            abi.encodeWithSelector(IConfigRegistryV5.TimestampNotAfterBinding.selector, name, uint256(0), uint256(0))
        );
        vm.prank(AUTHORITY);
        sRegistry.registerV5(AUTHORITY, name, VALUE_TYPE, value, "");

        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV5.NameNotRegistered.selector, AUTHORITY, name));
        LibConfigRegistryRead.getValue(sRegistry, AUTHORITY, name);
    }

    /// A first bind at a clock of one succeeds, and its moment is that clock, so
    /// one is the earliest moment the registry will store.
    function testRegisterFirstBindAtClockOne(bytes32 name, bytes memory value) external {
        vm.assume(value.length > 0);

        vm.warp(1);
        vm.prank(AUTHORITY);
        sRegistry.registerV5(AUTHORITY, name, VALUE_TYPE, value, "");

        assertEq(LibConfigRegistryRead.getValue(sRegistry, AUTHORITY, name), value);
        assertEq(LibConfigRegistryRead.getMoment(sRegistry, AUTHORITY, name), 1);
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
        vm.prank(AUTHORITY);
        sRegistry.registerV5(AUTHORITY, nameA, VALUE_TYPE, value, "");

        // The clock is now behind nameA's moment.
        vm.warp(low);
        vm.prank(AUTHORITY);
        sRegistry.registerV5(AUTHORITY, nameB, VALUE_TYPE, value, "");

        assertEq(LibConfigRegistryRead.getMoment(sRegistry, AUTHORITY, nameA), high);
        assertEq(LibConfigRegistryRead.getMoment(sRegistry, AUTHORITY, nameB), low);
    }

    /// The rule is per authority too: a clock behind one authority's moment
    /// for a name does not stop another authority binding the same name.
    function testRegisterMonotonicityIsPerAuthority(
        address other,
        bytes32 name,
        bytes memory value,
        uint256 high,
        uint256 low
    ) external {
        vm.assume(other != AUTHORITY);
        vm.assume(value.length > 0);
        low = bound(low, 1, type(uint256).max - 1);
        high = bound(high, low + 1, type(uint256).max);

        vm.warp(high);
        vm.prank(AUTHORITY);
        sRegistry.registerV5(AUTHORITY, name, VALUE_TYPE, value, "");

        // The clock is now behind the authority's moment for the name.
        vm.warp(low);
        vm.prank(other);
        sRegistry.registerV5(other, name, VALUE_TYPE, value, "");

        assertEq(LibConfigRegistryRead.getMoment(sRegistry, AUTHORITY, name), high);
        assertEq(LibConfigRegistryRead.getMoment(sRegistry, other, name), low);
    }

    /// One name under two authorities is two bindings in two storage slots,
    /// each holding exactly its own value and moment.
    function testRegisterSameNameTwoAuthoritiesStoredApart(address other) external {
        vm.assume(other != AUTHORITY);
        bytes32 name = keccak256("a.b");
        bytes memory valueA = abi.encode(uint256(1), uint256(2));
        bytes memory valueB = hex"03";

        vm.warp(5);
        vm.prank(AUTHORITY);
        sRegistry.registerV5(AUTHORITY, name, VALUE_TYPE, valueA, "");
        vm.warp(7);
        vm.prank(other);
        sRegistry.registerV5(other, name, VALUE_TYPE, valueB, "");

        assertStoredBinding(AUTHORITY, name, valueA, 5);
        assertStoredBinding(other, name, valueB, 7);
    }

    /// An empty-value `registerV5` never moves a moment either.
    function testRegisterEmptyValueCannotMoveMoment(
        bytes32 name,
        bytes memory boundValue,
        uint256 first,
        uint256 second
    ) external {
        vm.assume(boundValue.length > 0);
        first = bound(first, 1, type(uint256).max);

        vm.warp(first);
        vm.prank(AUTHORITY);
        sRegistry.registerV5(AUTHORITY, name, VALUE_TYPE, boundValue, "");

        vm.warp(second);
        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV5.EmptyValue.selector, name));
        vm.prank(AUTHORITY);
        sRegistry.registerV5(AUTHORITY, name, VALUE_TYPE, "", "");

        assertEq(LibConfigRegistryRead.getMoment(sRegistry, AUTHORITY, name), first);
    }
}
