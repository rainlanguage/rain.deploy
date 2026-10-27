// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";

import {IConfigRegistryV4} from "../../../src/interface/IConfigRegistryV4.sol";
import {IRegistryDelegatesV1} from "../../../src/interface/IRegistryDelegatesV1.sol";
import {ConfigRegistry} from "../../../src/concrete/ConfigRegistry.sol";
import {LibConfigRegistryRead} from "../../lib/LibConfigRegistryRead.sol";

/// @title ConfigRegistryGetTest
/// @notice Tests for `ConfigRegistry.getV4`: the value, the moment, the type,
/// the revert for an unbound name, and that it is the registry's only reader.
contract ConfigRegistryGetTest is Test {
    /// The authority most tests bind and read under. Any account is one.
    address internal constant AUTHORITY = address(0xA11CE);

    /// The type most tests bind as. The registry never parses it.
    string internal constant VALUE_TYPE = "bytes";

    /// The registry under test.
    ConfigRegistry internal sRegistry;

    function setUp() external {
        sRegistry = new ConfigRegistry();
    }

    /// Binds `name` to `value` as `valueType` under `AUTHORITY`, from it.
    function bindAsAuthority(string memory name, string memory valueType, bytes memory value) internal {
        vm.prank(AUTHORITY);
        sRegistry.registerV4(AUTHORITY, name, valueType, value);
    }

    /// A read of an unbound name reverts rather than returning an empty value.
    function testGetUnsetReverts(bytes32 nameHash) external {
        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV4.NameNotRegistered.selector, AUTHORITY, nameHash));
        LibConfigRegistryRead.getValue(sRegistry, AUTHORITY, nameHash);
    }

    /// A name another authority has bound is still unbound under this one,
    /// and the revert names the authority that was asked.
    function testGetOtherAuthorityBindingIsUnbound(address other, address asked, string memory name, bytes memory value)
        external
    {
        vm.assume(other != asked);
        vm.assume(bytes(name).length > 0);
        vm.assume(value.length > 0);
        bytes32 nameHash = keccak256(bytes(name));

        vm.prank(other);
        sRegistry.registerV4(other, name, VALUE_TYPE, value);

        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV4.NameNotRegistered.selector, asked, nameHash));
        LibConfigRegistryRead.getValue(sRegistry, asked, nameHash);
    }

    /// The zero authority never binds anything, so every name reads unbound
    /// under it.
    function testGetZeroAuthorityUnbound(string memory name, bytes memory value) external {
        vm.assume(bytes(name).length > 0);
        vm.assume(value.length > 0);
        bytes32 nameHash = keccak256(bytes(name));
        bindAsAuthority(name, VALUE_TYPE, value);

        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV4.NameNotRegistered.selector, address(0), nameHash));
        LibConfigRegistryRead.getValue(sRegistry, address(0), nameHash);
    }

    /// A read of a bound name returns exactly what was bound, and does not
    /// consume or alter the binding.
    function testGetReturnsRegistered(string memory name, bytes memory value) external {
        vm.assume(bytes(name).length > 0);
        vm.assume(value.length > 0);
        bytes32 nameHash = keccak256(bytes(name));

        bindAsAuthority(name, VALUE_TYPE, value);

        assertEq(LibConfigRegistryRead.getValue(sRegistry, AUTHORITY, nameHash), value);
        assertEq(LibConfigRegistryRead.getValue(sRegistry, AUTHORITY, nameHash), value);
    }

    /// A bound name is read by the hash of its string and by nothing else: a
    /// read under any other key, the string's raw bytes padded to a word
    /// included, is unbound.
    function testGetReadsByTheNameHash(string memory name, bytes32 other) external {
        vm.assume(bytes(name).length > 0);
        bytes32 nameHash = keccak256(bytes(name));
        vm.assume(other != nameHash);

        bindAsAuthority(name, VALUE_TYPE, hex"01");

        assertEq(LibConfigRegistryRead.getValue(sRegistry, AUTHORITY, nameHash), hex"01");
        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV4.NameNotRegistered.selector, AUTHORITY, other));
        LibConfigRegistryRead.getValue(sRegistry, AUTHORITY, other);
    }

    /// The value is returned byte for byte at every length either side of the
    /// boundary between the short and long storage encodings of `bytes`.
    function testGetReturnsEveryLength() external {
        uint256[7] memory lengths = [uint256(1), 30, 31, 32, 33, 64, 65];
        for (uint256 i = 0; i < lengths.length; i++) {
            bytes memory value = vm.randomBytes(lengths[i]);
            string memory name = vm.toString(i);
            bindAsAuthority(name, VALUE_TYPE, value);
            assertEq(LibConfigRegistryRead.getValue(sRegistry, AUTHORITY, keccak256(bytes(name))), value);
        }
    }

    /// An address binding is `abi.encode(account)` of type `address`, and
    /// decodes back to the account it was bound as. The registry adds and
    /// strips nothing.
    function testGetAddressBindingDecodes(string memory name, address account) external {
        vm.assume(bytes(name).length > 0);
        bindAsAuthority(name, "address", abi.encode(account));

        (bytes memory value,, bytes32 valueTypeHash) = sRegistry.getV4(AUTHORITY, keccak256(bytes(name)));
        assertEq(value.length, 32);
        assertEq(abi.decode(value, (address)), account);
        assertEq(valueTypeHash, keccak256("address"));
    }

    /// The zero address is a binding like any other: its encoding is a word of
    /// zeros, which is not empty, and only empty is how an unbound name reads.
    function testGetZeroAddressBindingIsBound(string memory name) external {
        vm.assume(bytes(name).length > 0);
        bindAsAuthority(name, "address", abi.encode(address(0)));

        bytes memory value = LibConfigRegistryRead.getValue(sRegistry, AUTHORITY, keccak256(bytes(name)));
        assertEq(value, new bytes(32));
        assertEq(abi.decode(value, (address)), address(0));
    }

    /// A value of any ABI shape round trips: here a dynamic tuple of the kind
    /// deploy configuration takes, a list of accounts with a threshold.
    function testGetStructuredBindingDecodes(string memory name, address[] memory accounts, uint256 threshold)
        external
    {
        vm.assume(bytes(name).length > 0);
        bindAsAuthority(name, "(address[],uint256)", abi.encode(accounts, threshold));

        (bytes memory value,, bytes32 valueTypeHash) = sRegistry.getV4(AUTHORITY, keccak256(bytes(name)));
        (address[] memory gotAccounts, uint256 gotThreshold) = abi.decode(value, (address[], uint256));
        assertEq(gotAccounts, accounts);
        assertEq(gotThreshold, threshold);
        assertEq(valueTypeHash, keccak256("(address[],uint256)"));
    }

    /// Names are opaque: nothing about a name's bytes changes how it is stored
    /// or read, not a byte outside any alphabet, nor a name that is itself
    /// the hex of a hash.
    function testGetOpaqueNames(bytes memory value) external {
        vm.assume(value.length > 0);

        string[4] memory names = [
            string(hex"00"),
            string(bytes(hex"ff")),
            "Not Canonical\n",
            "0x0b300013cd54a8f1ac40981f80faaa18b8cc1e4c0b300013cd54a8f1ac409810"
        ];
        for (uint256 i = 0; i < names.length; i++) {
            ConfigRegistry registry = new ConfigRegistry();
            vm.prank(AUTHORITY);
            registry.registerV4(AUTHORITY, names[i], VALUE_TYPE, value);
            assertEq(LibConfigRegistryRead.getValue(registry, AUTHORITY, keccak256(bytes(names[i]))), value);
        }
    }

    /// Types are opaque too: nothing about a type string's bytes changes how
    /// its hash is stored or read.
    function testGetOpaqueValueTypes(bytes memory value) external {
        vm.assume(value.length > 0);

        string[4] memory valueTypes = [string(hex"00"), string(bytes(hex"ff")), "Address ", "not a type"];
        for (uint256 i = 0; i < valueTypes.length; i++) {
            ConfigRegistry registry = new ConfigRegistry();
            vm.prank(AUTHORITY);
            registry.registerV4(AUTHORITY, "a.b", valueTypes[i], value);
            assertEq(
                LibConfigRegistryRead.getValueTypeHash(registry, AUTHORITY, keccak256("a.b")),
                keccak256(bytes(valueTypes[i]))
            );
        }
    }

    /// The bindings mapping is not `public`, so the getter a `public` mapping
    /// would generate does not exist.
    function testGetNoGeneratedMappingGetter(address authority, bytes32 nameHash) external {
        (bool success,) =
            address(sRegistry).call(abi.encodeWithSignature("sBindings(address,bytes32)", authority, nameHash));
        assertFalse(success);
    }

    /// An unknown selector reverts: no fallback, no receive, nothing beyond the
    /// five `IConfigRegistryV4` functions.
    function testGetNoOtherEntryPoint(bytes4 selector, bytes32 nameHash) external {
        vm.assume(selector != IConfigRegistryV4.getV4.selector);
        vm.assume(selector != IConfigRegistryV4.registerV4.selector);
        vm.assume(selector != IRegistryDelegatesV1.approveV3.selector);
        vm.assume(selector != IRegistryDelegatesV1.revokeV3.selector);
        vm.assume(selector != IRegistryDelegatesV1.approvedV3.selector);

        (bool success,) = address(sRegistry).call(abi.encodeWithSelector(selector, nameHash, abi.encode(address(this))));
        assertFalse(success);
    }

    /// The registry takes no value on any path: ether sent with or without
    /// calldata is refused, and its balance stays zero.
    function testGetNoValueEntryPoint(string memory name, bytes memory value) external {
        vm.assume(bytes(name).length > 0);
        vm.assume(value.length > 0);
        vm.deal(AUTHORITY, 3);

        vm.prank(AUTHORITY);
        (bool bare,) = address(sRegistry).call{value: 1}("");
        assertFalse(bare);

        vm.prank(AUTHORITY);
        (bool registered,) = address(sRegistry).call{value: 1}(
            abi.encodeCall(IConfigRegistryV4.registerV4, (AUTHORITY, name, VALUE_TYPE, value))
        );
        assertFalse(registered);

        vm.prank(AUTHORITY);
        (bool read,) = address(sRegistry).call{value: 1}(
            abi.encodeCall(IConfigRegistryV4.getV4, (AUTHORITY, keccak256(bytes(name))))
        );
        assertFalse(read);

        assertEq(address(sRegistry).balance, 0);
    }

    /// `getV4` answers with the moment the binding was made and the hash of
    /// the type it was made as.
    function testGetReturnsMomentAndValueType(
        string memory name,
        string memory valueType,
        bytes memory value,
        uint256 time
    ) external {
        vm.assume(bytes(name).length > 0);
        vm.assume(bytes(valueType).length > 0);
        vm.assume(value.length > 0);

        time = bound(time, 1, type(uint256).max);
        vm.warp(time);
        bindAsAuthority(name, valueType, value);

        (bytes memory got, uint256 registeredAt, bytes32 valueTypeHash) =
            sRegistry.getV4(AUTHORITY, keccak256(bytes(name)));
        assertEq(got, value);
        assertEq(registeredAt, time);
        assertEq(valueTypeHash, keccak256(bytes(valueType)));
    }

    /// The moment does not drift as the chain advances: it reads back unchanged
    /// however long afterwards, so an age against `block.timestamp` grows.
    function testGetMomentStableAsTimePasses(string memory name, bytes memory value, uint256 time, uint256 elapsed)
        external
    {
        vm.assume(bytes(name).length > 0);
        vm.assume(value.length > 0);
        bytes32 nameHash = keccak256(bytes(name));
        elapsed = bound(elapsed, 0, type(uint256).max - 1);
        time = bound(time, 1, type(uint256).max - elapsed);

        vm.warp(time);
        bindAsAuthority(name, VALUE_TYPE, value);

        vm.warp(time + elapsed);
        assertEq(LibConfigRegistryRead.getMoment(sRegistry, AUTHORITY, nameHash), time);
        assertEq(block.timestamp - LibConfigRegistryRead.getMoment(sRegistry, AUTHORITY, nameHash), elapsed);
    }

    /// Moments and types are per name.
    function testGetMomentDistinctNames(
        string memory nameA,
        string memory nameB,
        bytes memory valueA,
        bytes memory valueB,
        uint256 timeA,
        uint256 timeB
    ) external {
        vm.assume(bytes(nameA).length > 0);
        vm.assume(bytes(nameB).length > 0);
        vm.assume(keccak256(bytes(nameA)) != keccak256(bytes(nameB)));
        vm.assume(valueA.length > 0);
        vm.assume(valueB.length > 0);

        timeA = bound(timeA, 1, type(uint256).max);
        vm.warp(timeA);
        bindAsAuthority(nameA, "uint256", valueA);

        timeB = bound(timeB, 1, type(uint256).max);
        vm.warp(timeB);
        bindAsAuthority(nameB, "address", valueB);

        assertEq(LibConfigRegistryRead.getMoment(sRegistry, AUTHORITY, keccak256(bytes(nameA))), timeA);
        assertEq(LibConfigRegistryRead.getMoment(sRegistry, AUTHORITY, keccak256(bytes(nameB))), timeB);
        assertEq(
            LibConfigRegistryRead.getValueTypeHash(sRegistry, AUTHORITY, keccak256(bytes(nameA))), keccak256("uint256")
        );
        assertEq(
            LibConfigRegistryRead.getValueTypeHash(sRegistry, AUTHORITY, keccak256(bytes(nameB))), keccak256("address")
        );
    }

    /// The moment is stored at full width: clocks past every narrower width the
    /// moment could have been stored in are recorded exactly, never truncated
    /// into an older-looking moment.
    function testGetMomentFullWidth(string memory name, bytes memory value) external {
        vm.assume(bytes(name).length > 0);
        vm.assume(value.length > 0);
        bytes32 nameHash = keccak256(bytes(name));

        uint256[4] memory times = [
            uint256(type(uint64).max) + 1,
            uint256(type(uint96).max) + 1,
            uint256(type(uint128).max) + 1,
            type(uint256).max
        ];
        for (uint256 i = 0; i < times.length; i++) {
            vm.warp(times[i]);
            bindAsAuthority(name, VALUE_TYPE, value);
            assertEq(LibConfigRegistryRead.getMoment(sRegistry, AUTHORITY, nameHash), times[i]);
        }
    }

    /// Across a run of rotations the value, the moment and the type are always
    /// replaced together, never one lagging another.
    function testGetValueMomentAndTypeMoveTogether(string memory name, bytes[] memory values, uint256 start) external {
        vm.assume(bytes(name).length > 0);
        vm.assume(values.length > 0);
        start = bound(start, 1, type(uint256).max - values.length);
        for (uint256 i = 0; i < values.length; i++) {
            vm.assume(values[i].length > 0);
        }

        for (uint256 i = 0; i < values.length; i++) {
            string memory valueType = string.concat("t", vm.toString(i));
            vm.warp(start + i);
            bindAsAuthority(name, valueType, values[i]);

            (bytes memory got, uint256 registeredAt, bytes32 valueTypeHash) =
                sRegistry.getV4(AUTHORITY, keccak256(bytes(name)));
            assertEq(got, values[i]);
            assertEq(registeredAt, start + i);
            assertEq(valueTypeHash, keccak256(bytes(valueType)));
        }
    }
}
