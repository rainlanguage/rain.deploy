// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {IRegistryDelegatesV1} from "../../../src/interface/IRegistryDelegatesV1.sol";
import {Test, Vm} from "forge-std-1.17.0/src/Test.sol";

import {IConfigRegistryV4} from "../../../src/interface/IConfigRegistryV4.sol";
import {ConfigRegistry} from "../../../src/concrete/ConfigRegistry.sol";
import {LibConfigRegistryRead} from "../../lib/LibConfigRegistryRead.sol";

/// @title ConfigRegistryRegisterTest
/// @notice Tests for `ConfigRegistry.registerV4`: that any caller binds under
/// itself and, unapproved, under nothing else, that an authority may re-bind its own name, and what
/// a binding may never become.
contract ConfigRegistryRegisterTest is Test {
    /// The authority most tests bind under. Any account is one.
    address internal constant AUTHORITY = address(0xA11CE);

    /// The type most tests bind as. The registry never parses it.
    string internal constant VALUE_TYPE = "bytes";

    /// The registry under test.
    ConfigRegistry internal sRegistry;

    function setUp() external {
        sRegistry = new ConfigRegistry();
    }

    /// Binds `name` to `value` as `VALUE_TYPE` under `AUTHORITY`, from it.
    function bindAsAuthority(string memory name, bytes memory value) internal {
        vm.prank(AUTHORITY);
        sRegistry.registerV4(AUTHORITY, name, VALUE_TYPE, value);
    }

    /// Asserts `entry` is the one `Register` a bind of `name` to `value` of
    /// type `valueType` under `authority` by `sender` emits: nothing indexed,
    /// the sender, the authority, the name's hash, the name, the type and the
    /// whole value in the data.
    function assertRegisterLog(
        Vm.Log memory entry,
        address sender,
        address authority,
        string memory name,
        string memory valueType,
        bytes memory value
    ) internal view {
        assertEq(entry.emitter, address(sRegistry));
        assertEq(entry.topics.length, 1);
        assertEq(entry.topics[0], keccak256("Register(address,address,bytes32,string,string,bytes)"));
        assertEq(entry.topics[0], IConfigRegistryV4.Register.selector);
        assertEq(entry.data, abi.encode(sender, authority, keccak256(bytes(name)), name, valueType, value));
    }

    /// Any caller binds, with no permission asked, and the binding lands under
    /// the caller: it reads back under the caller and emits `Register` naming
    /// it.
    function testRegisterAnyCallerBindsUnderItself(address sender, string memory name, bytes memory value) external {
        vm.assume(bytes(name).length > 0);
        vm.assume(value.length > 0);
        bytes32 nameHash = keccak256(bytes(name));

        vm.recordLogs();
        vm.prank(sender);
        sRegistry.registerV4(sender, name, VALUE_TYPE, value);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        assertEq(LibConfigRegistryRead.getValue(sRegistry, sender, nameHash), value);
        assertEq(LibConfigRegistryRead.getMoment(sRegistry, sender, nameHash), block.timestamp);
        assertEq(entries.length, 1);
        assertRegisterLog(entries[0], sender, sender, name, VALUE_TYPE, value);
    }

    /// A bind lands under the caller and no other account: the same name stays
    /// unbound under every other authority.
    function testRegisterBindsUnderNoOtherAuthority(
        address sender,
        address other,
        string memory name,
        bytes memory value
    ) external {
        vm.assume(sender != other);
        vm.assume(bytes(name).length > 0);
        vm.assume(value.length > 0);
        bytes32 nameHash = keccak256(bytes(name));

        vm.prank(sender);
        sRegistry.registerV4(sender, name, VALUE_TYPE, value);

        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV4.NameNotRegistered.selector, other, nameHash));
        LibConfigRegistryRead.getValue(sRegistry, other, nameHash);
    }

    /// Another account binding the same name, at any clock, leaves the
    /// authority's binding — value, moment and type — untouched, and gets a
    /// binding of its own.
    function testRegisterOtherCallerLeavesBindingUntouched(
        address sender,
        string memory name,
        bytes memory boundValue,
        bytes memory value,
        uint256 first,
        uint256 second
    ) external {
        vm.assume(sender != AUTHORITY);
        vm.assume(bytes(name).length > 0);
        vm.assume(boundValue.length > 0);
        vm.assume(value.length > 0);
        bytes32 nameHash = keccak256(bytes(name));
        first = bound(first, 1, type(uint256).max);
        second = bound(second, 1, type(uint256).max);

        vm.warp(first);
        bindAsAuthority(name, boundValue);

        vm.warp(second);
        vm.prank(sender);
        sRegistry.registerV4(sender, name, "uint256", value);

        assertEq(LibConfigRegistryRead.getValue(sRegistry, AUTHORITY, nameHash), boundValue);
        assertEq(LibConfigRegistryRead.getMoment(sRegistry, AUTHORITY, nameHash), first);
        assertEq(LibConfigRegistryRead.getValueTypeHash(sRegistry, AUTHORITY, nameHash), keccak256(bytes(VALUE_TYPE)));
        assertEq(LibConfigRegistryRead.getValue(sRegistry, sender, nameHash), value);
        assertEq(LibConfigRegistryRead.getMoment(sRegistry, sender, nameHash), second);
        assertEq(LibConfigRegistryRead.getValueTypeHash(sRegistry, sender, nameHash), keccak256("uint256"));
    }

    /// Who may write is the CALLER, never the transaction origin: a call made
    /// by another account in a transaction the authority originates binds
    /// under that account, and is `NotApproved` under the authority.
    function testRegisterAuthorityIsCallerNotOrigin(address sender, string memory name, bytes memory value) external {
        vm.assume(sender != AUTHORITY);
        vm.assume(bytes(name).length > 0);
        vm.assume(value.length > 0);
        bytes32 nameHash = keccak256(bytes(name));

        vm.prank(sender, AUTHORITY);
        sRegistry.registerV4(sender, name, VALUE_TYPE, value);

        vm.expectRevert(abi.encodeWithSelector(IRegistryDelegatesV1.NotApproved.selector, AUTHORITY, nameHash, sender));
        vm.prank(sender, AUTHORITY);
        sRegistry.registerV4(AUTHORITY, name, VALUE_TYPE, value);

        assertEq(LibConfigRegistryRead.getValue(sRegistry, sender, nameHash), value);
        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV4.NameNotRegistered.selector, AUTHORITY, nameHash));
        LibConfigRegistryRead.getValue(sRegistry, AUTHORITY, nameHash);
    }

    /// An empty value is refused whoever calls.
    function testRegisterEmptyValueAnyCaller(address sender, string memory name) external {
        vm.assume(bytes(name).length > 0);
        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV4.EmptyValue.selector, keccak256(bytes(name))));
        vm.prank(sender);
        sRegistry.registerV4(sender, name, VALUE_TYPE, "");
    }

    /// An empty name is refused whoever calls, whatever the type and value,
    /// and nothing is bound under the empty string's hash or emitted.
    function testRegisterEmptyNameRefused(address sender, string memory valueType, bytes memory value) external {
        vm.recordLogs();
        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV4.EmptyName.selector));
        vm.prank(sender);
        sRegistry.registerV4(sender, "", valueType, value);
        assertEq(vm.getRecordedLogs().length, 0);

        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV4.NameNotRegistered.selector, sender, keccak256("")));
        LibConfigRegistryRead.getValue(sRegistry, sender, keccak256(""));
    }

    /// An empty value type is refused whoever calls, whatever the value,
    /// naming the name's hash, and the name is left unbound with nothing
    /// emitted.
    function testRegisterEmptyValueTypeRefused(address sender, string memory name, bytes memory value) external {
        vm.assume(bytes(name).length > 0);
        bytes32 nameHash = keccak256(bytes(name));

        vm.recordLogs();
        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV4.EmptyValueType.selector, nameHash));
        vm.prank(sender);
        sRegistry.registerV4(sender, name, "", value);
        assertEq(vm.getRecordedLogs().length, 0);

        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV4.NameNotRegistered.selector, sender, nameHash));
        LibConfigRegistryRead.getValue(sRegistry, sender, nameHash);
    }

    /// An empty value type cannot re-bind a bound name either: the binding,
    /// its moment and its type stay.
    function testRegisterEmptyValueTypeCannotRebind(string memory name, bytes memory boundValue, bytes memory value)
        external
    {
        vm.assume(bytes(name).length > 0);
        vm.assume(boundValue.length > 0);
        vm.assume(value.length > 0);
        bytes32 nameHash = keccak256(bytes(name));
        vm.warp(1);
        bindAsAuthority(name, boundValue);

        vm.warp(2);
        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV4.EmptyValueType.selector, nameHash));
        vm.prank(AUTHORITY);
        sRegistry.registerV4(AUTHORITY, name, "", value);

        (bytes memory got, uint256 registeredAt, bytes32 valueTypeHash) = sRegistry.getV4(AUTHORITY, nameHash);
        assertEq(got, boundValue);
        assertEq(registeredAt, 1);
        assertEq(valueTypeHash, keccak256(bytes(VALUE_TYPE)));
    }

    /// The refusals come in argument order after the caller: with every later
    /// argument also invalid and the clock at zero, an empty name is
    /// `EmptyName`, then an empty type `EmptyValueType`, then an empty value
    /// `EmptyValue`, and only then the clock.
    function testRegisterRefusesArgumentsInOrder(string memory name) external {
        vm.assume(bytes(name).length > 0);
        bytes32 nameHash = keccak256(bytes(name));
        vm.warp(0);

        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV4.EmptyName.selector));
        vm.prank(AUTHORITY);
        sRegistry.registerV4(AUTHORITY, "", "", "");

        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV4.EmptyValueType.selector, nameHash));
        vm.prank(AUTHORITY);
        sRegistry.registerV4(AUTHORITY, name, "", "");

        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV4.EmptyValue.selector, nameHash));
        vm.prank(AUTHORITY);
        sRegistry.registerV4(AUTHORITY, name, VALUE_TYPE, "");

        vm.expectRevert(
            abi.encodeWithSelector(IConfigRegistryV4.TimestampNotAfterBinding.selector, nameHash, 0, 0)
        );
        vm.prank(AUTHORITY);
        sRegistry.registerV4(AUTHORITY, name, VALUE_TYPE, hex"01");
    }

    /// The binding stores the hash of the type it was bound as, and `getV4`
    /// answers with it, whatever the type string: the registry hashes it and
    /// never parses it.
    function testRegisterValueTypeHashRoundTrips(string memory name, string memory valueType, bytes memory value)
        external
    {
        vm.assume(bytes(name).length > 0);
        vm.assume(bytes(valueType).length > 0);
        vm.assume(value.length > 0);

        vm.prank(AUTHORITY);
        sRegistry.registerV4(AUTHORITY, name, valueType, value);

        (bytes memory got, uint256 registeredAt, bytes32 valueTypeHash) =
            sRegistry.getV4(AUTHORITY, keccak256(bytes(name)));
        assertEq(got, value);
        assertEq(registeredAt, block.timestamp);
        assertEq(valueTypeHash, keccak256(bytes(valueType)));
    }

    /// A re-bind replaces the type along with the value and the moment, so a
    /// name re-bound as another type answers with the new type's hash.
    function testRegisterRebindReplacesValueType(
        string memory name,
        string memory boundType,
        string memory valueType,
        bytes memory value
    ) external {
        vm.assume(bytes(name).length > 0);
        vm.assume(bytes(boundType).length > 0);
        vm.assume(bytes(valueType).length > 0);
        vm.assume(value.length > 0);
        bytes32 nameHash = keccak256(bytes(name));

        vm.warp(1);
        vm.prank(AUTHORITY);
        sRegistry.registerV4(AUTHORITY, name, boundType, value);
        assertEq(LibConfigRegistryRead.getValueTypeHash(sRegistry, AUTHORITY, nameHash), keccak256(bytes(boundType)));

        vm.warp(2);
        vm.prank(AUTHORITY);
        sRegistry.registerV4(AUTHORITY, name, valueType, value);
        assertEq(LibConfigRegistryRead.getValueTypeHash(sRegistry, AUTHORITY, nameHash), keccak256(bytes(valueType)));
        assertEq(LibConfigRegistryRead.getValue(sRegistry, AUTHORITY, nameHash), value);
        assertEq(LibConfigRegistryRead.getMoment(sRegistry, AUTHORITY, nameHash), 2);
    }

    /// The strings `Register` carries are the ones the binding is keyed and
    /// typed by: the logged name hashes to the logged name hash, under which
    /// `getV4` answers with the logged value, and the logged type hashes to
    /// the type hash it answers with. A log reader needs nothing else to find
    /// and decode every binding.
    function testRegisterEmittedStringsHashToStoredKeys(
        address sender,
        string memory name,
        string memory valueType,
        bytes memory value
    ) external {
        vm.assume(bytes(name).length > 0);
        vm.assume(bytes(valueType).length > 0);
        vm.assume(value.length > 0);

        vm.recordLogs();
        vm.prank(sender);
        sRegistry.registerV4(sender, name, valueType, value);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 1);

        (
            address loggedSender,
            address loggedAuthority,
            bytes32 loggedNameHash,
            string memory loggedName,
            string memory loggedValueType,
            bytes memory loggedValue
        ) = abi.decode(entries[0].data, (address, address, bytes32, string, string, bytes));
        assertEq(loggedSender, sender);
        assertEq(loggedAuthority, sender);
        assertEq(loggedName, name);
        assertEq(loggedValueType, valueType);
        assertEq(keccak256(bytes(loggedName)), loggedNameHash);

        (bytes memory got,, bytes32 valueTypeHash) = sRegistry.getV4(loggedAuthority, loggedNameHash);
        assertEq(got, loggedValue);
        assertEq(keccak256(bytes(loggedValueType)), valueTypeHash);
    }

    /// An authority may re-bind a name to a different value, and the new
    /// binding is what `getV4` answers with from then on.
    function testRegisterRebind(string memory name, bytes memory boundValue, bytes memory value) external {
        vm.assume(bytes(name).length > 0);
        vm.assume(boundValue.length > 0);
        vm.assume(value.length > 0);
        bytes32 nameHash = keccak256(bytes(name));

        bindAsAuthority(name, boundValue);
        assertEq(LibConfigRegistryRead.getValue(sRegistry, AUTHORITY, nameHash), boundValue);

        // A re-bind has to be in a later block than the bind it replaces.
        vm.warp(block.timestamp + 1);
        bindAsAuthority(name, value);
        assertEq(LibConfigRegistryRead.getValue(sRegistry, AUTHORITY, nameHash), value);
    }

    /// A re-bind replaces the value whole, whichever of the two is longer: a
    /// value moving between the short and long storage encodings, or shrinking
    /// within the long one, leaves nothing of the old value behind in storage.
    function testRegisterRebindAcrossLengths() external {
        string memory name = "a.b";
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
            bindAsAuthority(name, values[i]);
            assertEq(LibConfigRegistryRead.getValue(sRegistry, AUTHORITY, keccak256(bytes(name))), values[i]);
            assertStoredBinding(AUTHORITY, keccak256(bytes(name)), values[i], i + 1, keccak256(bytes(VALUE_TYPE)));
        }
    }

    /// Asserts the raw storage of `authority`'s binding of `nameHash`.
    /// `sBindings` is slot 1, after the inherited `sApproved`, so the
    /// authority's inner mapping is at `keccak256(authority . 1)` and the
    /// binding at `keccak256(nameHash . that)`; `value` is the struct's first
    /// slot, `registeredAt` its second and `valueTypeHash` its third. A value
    /// under 32 bytes is stored left-aligned with `length * 2` in the low byte;
    /// a longer one as `length * 2 + 1`, its bytes from `keccak256(base)`.
    /// Slots `data + 0..2` cover every value here, the longest being three
    /// words, and any not holding this value are zero.
    /// @param authority The authority it is bound under.
    /// @param nameHash The hash of the bound name.
    /// @param value The value it is bound to.
    /// @param moment The moment it was bound at.
    /// @param valueTypeHash The hash of the type it was bound as.
    function assertStoredBinding(
        address authority,
        bytes32 nameHash,
        bytes memory value,
        uint256 moment,
        bytes32 valueTypeHash
    ) internal view {
        bytes32 base = keccak256(abi.encode(nameHash, keccak256(abi.encode(authority, uint256(1)))));
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
        assertEq(vm.load(address(sRegistry), bytes32(uint256(base) + 2)), valueTypeHash);
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
    function testRegisterRebindSameValue(string memory name, bytes memory value) external {
        vm.assume(bytes(name).length > 0);
        vm.assume(value.length > 0);

        bindAsAuthority(name, value);

        vm.warp(block.timestamp + 1);
        bindAsAuthority(name, value);

        assertEq(LibConfigRegistryRead.getValue(sRegistry, AUTHORITY, keccak256(bytes(name))), value);
    }

    /// Re-binding survives any number of rotations, and only the most recent one
    /// counts.
    function testRegisterRebindRepeatedly(string memory name, bytes[] memory values) external {
        vm.assume(bytes(name).length > 0);
        vm.assume(values.length > 0);
        for (uint256 i = 0; i < values.length; i++) {
            vm.assume(values[i].length > 0);
        }
        bytes32 nameHash = keccak256(bytes(name));

        for (uint256 i = 0; i < values.length; i++) {
            // Each re-bind is a block later than the last.
            vm.warp(vm.getBlockTimestamp() + 1);
            bindAsAuthority(name, values[i]);
            assertEq(LibConfigRegistryRead.getValue(sRegistry, AUTHORITY, nameHash), values[i]);
        }
        assertEq(LibConfigRegistryRead.getValue(sRegistry, AUTHORITY, nameHash), values[values.length - 1]);
    }

    /// An empty value is rejected, and the name is left unbound.
    function testRegisterEmptyValue(string memory name) external {
        vm.assume(bytes(name).length > 0);
        bytes32 nameHash = keccak256(bytes(name));
        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV4.EmptyValue.selector, nameHash));
        bindAsAuthority(name, "");

        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV4.NameNotRegistered.selector, AUTHORITY, nameHash));
        LibConfigRegistryRead.getValue(sRegistry, AUTHORITY, nameHash);
    }

    /// The empty tuple is the only ABI encoding that is empty, so it is the
    /// only one refused.
    function testRegisterEmptyTupleIsTheEmptyValue(string memory name) external {
        vm.assume(bytes(name).length > 0);
        assertEq(abi.encode().length, 0);
        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV4.EmptyValue.selector, keccak256(bytes(name))));
        bindAsAuthority(name, abi.encode());
    }

    /// The zero value of every kind of type Solidity can encode is at least one
    /// word, so it binds and reads back exactly: a static zero, a zero in a
    /// fixed array or struct-shaped tuple, and an empty dynamic value. Solidity
    /// has no empty struct and no zero-length fixed array to encode.
    function testRegisterZeroValuesOfEveryKindBind(string memory name) external {
        vm.assume(bytes(name).length > 0);
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
            bindAsAuthority(name, values[i]);
            assertEq(LibConfigRegistryRead.getValue(sRegistry, AUTHORITY, keccak256(bytes(name))), values[i]);
        }
    }

    /// A single byte is the shortest value accepted: the refusal is of empty,
    /// not of short.
    function testRegisterOneByteValue(string memory name, bytes1 b) external {
        vm.assume(bytes(name).length > 0);
        bindAsAuthority(name, abi.encodePacked(b));

        assertEq(LibConfigRegistryRead.getValue(sRegistry, AUTHORITY, keccak256(bytes(name))), abi.encodePacked(b));
    }

    /// A single byte is the shortest name and the shortest type accepted: the
    /// refusals are of empty, not of short.
    function testRegisterOneByteNameAndValueType(bytes1 n, bytes1 t) external {
        string memory name = string(abi.encodePacked(n));
        string memory valueType = string(abi.encodePacked(t));
        vm.prank(AUTHORITY);
        sRegistry.registerV4(AUTHORITY, name, valueType, hex"01");

        (bytes memory got,, bytes32 valueTypeHash) = sRegistry.getV4(AUTHORITY, keccak256(abi.encodePacked(n)));
        assertEq(got, hex"01");
        assertEq(valueTypeHash, keccak256(abi.encodePacked(t)));
    }

    /// An empty value is rejected for an already bound name too, so a name
    /// cannot be unbound by re-binding it to nothing.
    function testRegisterEmptyValueCannotUnbind(string memory name, bytes memory boundValue) external {
        vm.assume(bytes(name).length > 0);
        vm.assume(boundValue.length > 0);
        bytes32 nameHash = keccak256(bytes(name));

        bindAsAuthority(name, boundValue);

        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV4.EmptyValue.selector, nameHash));
        bindAsAuthority(name, "");

        assertEq(LibConfigRegistryRead.getValue(sRegistry, AUTHORITY, nameHash), boundValue);
    }

    /// Names are independent: binding one says nothing about any other.
    function testRegisterDistinctNames(
        string memory nameA,
        string memory nameB,
        bytes memory valueA,
        bytes memory valueB
    ) external {
        vm.assume(bytes(nameA).length > 0);
        vm.assume(bytes(nameB).length > 0);
        vm.assume(keccak256(bytes(nameA)) != keccak256(bytes(nameB)));
        vm.assume(valueA.length > 0);
        vm.assume(valueB.length > 0);
        bytes32 hashA = keccak256(bytes(nameA));
        bytes32 hashB = keccak256(bytes(nameB));

        bindAsAuthority(nameA, valueA);

        // Binding `nameA` did not bind `nameB`.
        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV4.NameNotRegistered.selector, AUTHORITY, hashB));
        LibConfigRegistryRead.getValue(sRegistry, AUTHORITY, hashB);

        bindAsAuthority(nameB, valueB);

        assertEq(LibConfigRegistryRead.getValue(sRegistry, AUTHORITY, hashA), valueA);
        assertEq(LibConfigRegistryRead.getValue(sRegistry, AUTHORITY, hashB), valueB);
    }

    /// `Register` is emitted once, with nothing indexed and every field, the
    /// whole value included, in the data.
    function testRegisterEvent(string memory name, string memory valueType, bytes memory value) external {
        vm.assume(bytes(name).length > 0);
        vm.assume(bytes(valueType).length > 0);
        vm.assume(value.length > 0);

        vm.recordLogs();
        vm.prank(AUTHORITY);
        sRegistry.registerV4(AUTHORITY, name, valueType, value);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        assertEq(entries.length, 1);
        assertRegisterLog(entries[0], AUTHORITY, AUTHORITY, name, valueType, value);
    }

    /// A re-binding emits its own `Register`, so the most recent entry for a
    /// name is its current binding.
    function testRegisterRebindEvent(string memory name, bytes memory boundValue, bytes memory value) external {
        vm.assume(bytes(name).length > 0);
        vm.assume(boundValue.length > 0);
        vm.assume(value.length > 0);

        bindAsAuthority(name, boundValue);

        vm.warp(block.timestamp + 1);
        vm.recordLogs();
        bindAsAuthority(name, value);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        assertEq(entries.length, 1);
        assertRegisterLog(entries[0], AUTHORITY, AUTHORITY, name, VALUE_TYPE, value);
    }

    /// Re-binding a name to the value it already holds is a bind like any
    /// other, so it emits its own `Register` too.
    function testRegisterRebindSameValueEvent(string memory name, bytes memory value) external {
        vm.assume(bytes(name).length > 0);
        vm.assume(value.length > 0);

        bindAsAuthority(name, value);

        vm.warp(block.timestamp + 1);
        vm.recordLogs();
        bindAsAuthority(name, value);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        assertEq(entries.length, 1);
        assertRegisterLog(entries[0], AUTHORITY, AUTHORITY, name, VALUE_TYPE, value);
    }

    /// A rejected `registerV4` emits nothing.
    function testRegisterNoEventOnRevert(address sender, string memory name) external {
        vm.assume(bytes(name).length > 0);
        vm.recordLogs();
        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV4.EmptyValue.selector, keccak256(bytes(name))));
        vm.prank(sender);
        sRegistry.registerV4(sender, name, VALUE_TYPE, "");
        assertEq(vm.getRecordedLogs().length, 0);
    }

    /// A re-bind replaces the moment along with the value.
    function testRegisterRebindRefreshesMoment(
        string memory name,
        bytes memory boundValue,
        bytes memory value,
        uint256 first,
        uint256 second
    ) external {
        vm.assume(bytes(name).length > 0);
        vm.assume(boundValue.length > 0);
        vm.assume(value.length > 0);
        bytes32 nameHash = keccak256(bytes(name));
        // The second bind happens strictly after the first.
        first = bound(first, 1, type(uint256).max - 1);
        second = bound(second, first + 1, type(uint256).max);

        vm.warp(first);
        bindAsAuthority(name, boundValue);
        assertEq(LibConfigRegistryRead.getMoment(sRegistry, AUTHORITY, nameHash), first);

        vm.warp(second);
        bindAsAuthority(name, value);

        assertEq(LibConfigRegistryRead.getValue(sRegistry, AUTHORITY, nameHash), value);
        assertEq(LibConfigRegistryRead.getMoment(sRegistry, AUTHORITY, nameHash), second);
    }

    /// Re-binding a name to the value it already holds still refreshes the
    /// moment: the moment dates the WRITE, not the value.
    function testRegisterRebindSameValueRefreshesMoment(
        string memory name,
        bytes memory value,
        uint256 first,
        uint256 second
    ) external {
        vm.assume(bytes(name).length > 0);
        vm.assume(value.length > 0);
        bytes32 nameHash = keccak256(bytes(name));
        // Strictly later, so the refresh is observable.
        first = bound(first, 1, type(uint256).max - 1);
        second = bound(second, first + 1, type(uint256).max);

        vm.warp(first);
        bindAsAuthority(name, value);
        assertEq(LibConfigRegistryRead.getMoment(sRegistry, AUTHORITY, nameHash), first);

        vm.warp(second);
        bindAsAuthority(name, value);

        assertEq(LibConfigRegistryRead.getValue(sRegistry, AUTHORITY, nameHash), value);
        assertEq(LibConfigRegistryRead.getMoment(sRegistry, AUTHORITY, nameHash), second);
    }

    /// A re-bind at a clock behind the moment the name carries is refused, and
    /// leaves the binding, its moment and its type untouched.
    function testRegisterRefusesClockBehindTheBinding(
        string memory name,
        bytes memory boundValue,
        bytes memory value,
        uint256 first,
        uint256 second
    ) external {
        vm.assume(bytes(name).length > 0);
        vm.assume(boundValue.length > 0);
        vm.assume(value.length > 0);
        bytes32 nameHash = keccak256(bytes(name));
        second = bound(second, 0, type(uint256).max - 1);
        first = bound(first, second + 1, type(uint256).max);

        vm.warp(first);
        bindAsAuthority(name, boundValue);

        vm.warp(second);
        vm.expectRevert(
            abi.encodeWithSelector(IConfigRegistryV4.TimestampNotAfterBinding.selector, nameHash, second, first)
        );
        vm.prank(AUTHORITY);
        sRegistry.registerV4(AUTHORITY, name, "uint256", value);

        assertEq(LibConfigRegistryRead.getValue(sRegistry, AUTHORITY, nameHash), boundValue);
        assertEq(LibConfigRegistryRead.getMoment(sRegistry, AUTHORITY, nameHash), first);
        assertEq(LibConfigRegistryRead.getValueTypeHash(sRegistry, AUTHORITY, nameHash), keccak256(bytes(VALUE_TYPE)));
    }

    /// A re-bind at EXACTLY the moment the name carries is refused too, so the
    /// moment is strictly increasing rather than merely non-decreasing. The
    /// binding and its moment are left untouched.
    function testRegisterRefusesClockEqualToTheBinding(
        string memory name,
        bytes memory boundValue,
        bytes memory value,
        uint256 time
    ) external {
        vm.assume(bytes(name).length > 0);
        vm.assume(boundValue.length > 0);
        vm.assume(value.length > 0);
        bytes32 nameHash = keccak256(bytes(name));

        time = bound(time, 1, type(uint256).max);
        vm.warp(time);
        bindAsAuthority(name, boundValue);

        vm.expectRevert(
            abi.encodeWithSelector(IConfigRegistryV4.TimestampNotAfterBinding.selector, nameHash, time, time)
        );
        bindAsAuthority(name, value);

        assertEq(LibConfigRegistryRead.getValue(sRegistry, AUTHORITY, nameHash), boundValue);
        assertEq(LibConfigRegistryRead.getMoment(sRegistry, AUTHORITY, nameHash), time);
    }

    /// One block later is enough: the rule is strictly-after, not some wider
    /// gap, so a re-bind in the very next block is accepted.
    function testRegisterAllowsClockOneAfterTheBinding(
        string memory name,
        bytes memory boundValue,
        bytes memory value,
        uint256 time
    ) external {
        vm.assume(bytes(name).length > 0);
        vm.assume(boundValue.length > 0);
        vm.assume(value.length > 0);
        bytes32 nameHash = keccak256(bytes(name));
        time = bound(time, 1, type(uint256).max - 1);

        vm.warp(time);
        bindAsAuthority(name, boundValue);

        vm.warp(time + 1);
        bindAsAuthority(name, value);

        assertEq(LibConfigRegistryRead.getValue(sRegistry, AUTHORITY, nameHash), value);
        assertEq(LibConfigRegistryRead.getMoment(sRegistry, AUTHORITY, nameHash), time + 1);
    }

    /// A bind at a clock of ZERO is refused, first bind or not, and the name
    /// still reads as unbound rather than as bound with a zero moment.
    function testRegisterRefusesClockZero(string memory name, bytes memory value) external {
        vm.assume(bytes(name).length > 0);
        vm.assume(value.length > 0);
        bytes32 nameHash = keccak256(bytes(name));

        vm.warp(0);
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigRegistryV4.TimestampNotAfterBinding.selector, nameHash, uint256(0), uint256(0)
            )
        );
        bindAsAuthority(name, value);

        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV4.NameNotRegistered.selector, AUTHORITY, nameHash));
        LibConfigRegistryRead.getValue(sRegistry, AUTHORITY, nameHash);
    }

    /// A first bind at a clock of one succeeds, and its moment is that clock, so
    /// one is the earliest moment the registry will store.
    function testRegisterFirstBindAtClockOne(string memory name, bytes memory value) external {
        vm.assume(bytes(name).length > 0);
        vm.assume(value.length > 0);
        bytes32 nameHash = keccak256(bytes(name));

        vm.warp(1);
        bindAsAuthority(name, value);

        assertEq(LibConfigRegistryRead.getValue(sRegistry, AUTHORITY, nameHash), value);
        assertEq(LibConfigRegistryRead.getMoment(sRegistry, AUTHORITY, nameHash), 1);
    }

    /// The rule is per name: a clock behind ONE name's moment does not stop
    /// another name being bound.
    function testRegisterMonotonicityIsPerName(
        string memory nameA,
        string memory nameB,
        bytes memory value,
        uint256 high,
        uint256 low
    ) external {
        vm.assume(bytes(nameA).length > 0);
        vm.assume(bytes(nameB).length > 0);
        vm.assume(keccak256(bytes(nameA)) != keccak256(bytes(nameB)));
        vm.assume(value.length > 0);
        low = bound(low, 1, type(uint256).max - 1);
        high = bound(high, low + 1, type(uint256).max);

        vm.warp(high);
        bindAsAuthority(nameA, value);

        // The clock is now behind nameA's moment.
        vm.warp(low);
        bindAsAuthority(nameB, value);

        assertEq(LibConfigRegistryRead.getMoment(sRegistry, AUTHORITY, keccak256(bytes(nameA))), high);
        assertEq(LibConfigRegistryRead.getMoment(sRegistry, AUTHORITY, keccak256(bytes(nameB))), low);
    }

    /// The rule is per authority too: a clock behind one authority's moment
    /// for a name does not stop another authority binding the same name.
    function testRegisterMonotonicityIsPerAuthority(
        address other,
        string memory name,
        bytes memory value,
        uint256 high,
        uint256 low
    ) external {
        vm.assume(other != AUTHORITY);
        vm.assume(bytes(name).length > 0);
        vm.assume(value.length > 0);
        bytes32 nameHash = keccak256(bytes(name));
        low = bound(low, 1, type(uint256).max - 1);
        high = bound(high, low + 1, type(uint256).max);

        vm.warp(high);
        bindAsAuthority(name, value);

        // The clock is now behind the authority's moment for the name.
        vm.warp(low);
        vm.prank(other);
        sRegistry.registerV4(other, name, VALUE_TYPE, value);

        assertEq(LibConfigRegistryRead.getMoment(sRegistry, AUTHORITY, nameHash), high);
        assertEq(LibConfigRegistryRead.getMoment(sRegistry, other, nameHash), low);
    }

    /// One name under two authorities is two bindings in two storage slots,
    /// each holding exactly its own value, moment and type.
    function testRegisterSameNameTwoAuthoritiesStoredApart(address other) external {
        vm.assume(other != AUTHORITY);
        bytes32 nameHash = keccak256("a.b");
        bytes memory valueA = abi.encode(uint256(1), uint256(2));
        bytes memory valueB = hex"03";

        vm.warp(5);
        vm.prank(AUTHORITY);
        sRegistry.registerV4(AUTHORITY, "a.b", "(uint256,uint256)", valueA);
        vm.warp(7);
        vm.prank(other);
        sRegistry.registerV4(other, "a.b", "bytes1", valueB);

        assertStoredBinding(AUTHORITY, nameHash, valueA, 5, keccak256("(uint256,uint256)"));
        assertStoredBinding(other, nameHash, valueB, 7, keccak256("bytes1"));
    }

    /// An empty-value `registerV4` never moves a moment either.
    function testRegisterEmptyValueCannotMoveMoment(
        string memory name,
        bytes memory boundValue,
        uint256 first,
        uint256 second
    ) external {
        vm.assume(bytes(name).length > 0);
        vm.assume(boundValue.length > 0);
        bytes32 nameHash = keccak256(bytes(name));
        first = bound(first, 1, type(uint256).max);

        vm.warp(first);
        bindAsAuthority(name, boundValue);

        vm.warp(second);
        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV4.EmptyValue.selector, nameHash));
        bindAsAuthority(name, "");

        assertEq(LibConfigRegistryRead.getMoment(sRegistry, AUTHORITY, nameHash), first);
    }
}
