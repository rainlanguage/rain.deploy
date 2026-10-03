// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";

import {IAddressRegistryV1} from "../../../src/interface/IAddressRegistryV1.sol";
import {IAddressRegistryV2} from "../../../src/interface/IAddressRegistryV2.sol";
import {ADDRESS_REGISTRY_ROOT} from "../../../src/concrete/AddressRegistry.sol";
import {AddressRegistryV2} from "../../../src/concrete/AddressRegistryV2.sol";

/// @title AddressRegistryV2GetTest
/// @notice A test suite for `AddressRegistryV2.get`: it answers a bound name
/// with its address and the moment that address last changed, an unbound name
/// with a revert, and it is the only reader.
contract AddressRegistryV2GetTest is Test {
    /// The registry under test. Stateful, so a fresh one per test.
    AddressRegistryV2 internal sRegistry;

    function setUp() external {
        sRegistry = new AddressRegistryV2();
    }

    /// A read of an unbound name reverts rather than returning the zero
    /// address, so a caller cannot proceed on a name nobody bound by forgetting
    /// to check. There is therefore no zero timestamp to interpret either.
    function testGetV2UnsetReverts(bytes32 name) external {
        vm.expectRevert(abi.encodeWithSelector(IAddressRegistryV2.NameNotRegistered.selector, name));
        sRegistry.get(name);
    }

    /// A read of a bound name returns exactly what was bound and when, and
    /// reading does not consume or alter the binding.
    function testGetV2ReturnsRegistered(bytes32 name, address account) external {
        vm.assume(account != address(0));

        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, account);

        (address firstAccount, uint256 firstChangedAt) = sRegistry.get(name);
        assertEq(firstAccount, account);
        assertEq(firstChangedAt, block.timestamp);

        (address secondAccount, uint256 secondChangedAt) = sRegistry.get(name);
        assertEq(secondAccount, account);
        assertEq(secondChangedAt, firstChangedAt);
    }

    /// A read long after the bind answers with the moment of the bind, not the
    /// moment of the read. The timestamp is a fact about the binding, so the
    /// reader is the one holding it against a window of its own.
    function testGetV2ChangedAtIsNotReadTime(bytes32 name, address account, uint64 gap) external {
        vm.assume(account != address(0));
        gap = uint64(bound(uint256(gap), 1, type(uint32).max));

        uint256 bindAt = block.timestamp;
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, account);

        vm.warp(block.timestamp + gap);
        (address actualAccount, uint256 changedAt) = sRegistry.get(name);
        assertEq(actualAccount, account);
        assertEq(changedAt, bindAt);
        assertEq(block.timestamp - changedAt, gap);
    }

    /// Names are opaque: nothing about a name's bytes changes how it is stored
    /// or read, including names a string-hashing convention would never
    /// produce.
    function testGetV2OpaqueNames(address account) external {
        vm.assume(account != address(0));

        bytes32[3] memory names = [bytes32(0), bytes32(uint256(1)), bytes32(type(uint256).max)];
        for (uint256 i = 0; i < names.length; i++) {
            AddressRegistryV2 registry = new AddressRegistryV2();
            vm.prank(ADDRESS_REGISTRY_ROOT);
            registry.register(names[i], account);
            (address actualAccount, uint256 changedAt) = registry.get(names[i]);
            assertEq(actualAccount, account);
            assertEq(changedAt, block.timestamp);
        }
    }

    /// `get` is the only reader. The bindings mapping is not `public`, so the
    /// getter a `public` mapping would generate — which answers an unbound name
    /// with a zero-filled binding, the exact silent failure `get` reverts to
    /// prevent — does not exist.
    function testGetV2NoGeneratedMappingGetter(bytes32 name) external {
        (bool success,) = address(sRegistry).call(abi.encodeWithSignature("sBindings(bytes32)", name));
        assertFalse(success);
    }

    /// There is no other entry point at all: no fallback, no receive, and
    /// nothing beyond the two `IAddressRegistryV2` functions, so an unknown
    /// selector reverts instead of being silently absorbed.
    function testGetV2NoOtherEntryPoint(bytes4 selector, bytes32 name) external {
        vm.assume(selector != IAddressRegistryV2.get.selector);
        vm.assume(selector != IAddressRegistryV2.register.selector);

        (bool success,) = address(sRegistry).call(abi.encodeWithSelector(selector, name, address(this)));
        assertFalse(success);
    }

    /// The ABI is exactly the two `IAddressRegistryV2` functions, counted
    /// rather than sampled. A fuzz over unknown selectors cannot see a reader
    /// added under a name of its own, and such a reader is precisely what the
    /// interface forbids: it would answer an unbound name with a zero-filled
    /// binding, the silent failure `get` reverts to prevent. A separate reader
    /// for the timestamp alone would be one of exactly those.
    function testGetV2AbiIsExactlyTheInterface() external view {
        string[] memory signatures =
            vm.parseJsonKeys(vm.readFile("out/AddressRegistryV2.sol/AddressRegistryV2.json"), "$.methodIdentifiers");

        assertEq(signatures.length, 2);
        assertEq(signatures[0], "get(bytes32)");
        assertEq(signatures[1], "register(bytes32,address)");
    }

    /// The registry takes no value on any path. Neither entry point is payable
    /// and there is no `receive`, so ether sent with or without calldata is
    /// refused rather than trapped in a contract that holds no way to move it
    /// out again.
    function testGetV2NoValueEntryPoint(bytes32 name, address account) external {
        vm.assume(account != address(0));
        vm.deal(ADDRESS_REGISTRY_ROOT, 3);

        vm.prank(ADDRESS_REGISTRY_ROOT);
        (bool bare,) = address(sRegistry).call{value: 1}("");
        assertFalse(bare);

        vm.prank(ADDRESS_REGISTRY_ROOT);
        (bool registered,) =
            address(sRegistry).call{value: 1}(abi.encodeCall(IAddressRegistryV2.register, (name, account)));
        assertFalse(registered);

        vm.prank(ADDRESS_REGISTRY_ROOT);
        (bool read,) = address(sRegistry).call{value: 1}(abi.encodeCall(IAddressRegistryV2.get, (name)));
        assertFalse(read);

        assertEq(address(sRegistry).balance, 0);
    }

    /// A selector does not include return types, so this `get` shares one with
    /// `IAddressRegistryV1.get`. What distinguishes them is the returndata: 64
    /// bytes here against V1's 32. Recorded because a shared selector is the
    /// kind of thing that looks like an accident later, and because the two
    /// halves of the pair are what a reader of the raw call has to split.
    function testGetV2SharesTheV1Selector(bytes32 name, address account) external {
        assertEq(IAddressRegistryV2.get.selector, IAddressRegistryV1.get.selector);
        vm.assume(account != address(0));

        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, account);

        (bool success, bytes memory returnData) =
            address(sRegistry).staticcall(abi.encodeWithSelector(IAddressRegistryV1.get.selector, name));
        assertTrue(success);
        assertEq(returnData.length, 64);

        (address actualAccount, uint256 changedAt) = abi.decode(returnData, (address, uint256));
        assertEq(actualAccount, account);
        assertEq(changedAt, block.timestamp);
    }

    /// Reading this registry through the V1 ABI gets the right address and
    /// silently drops the timestamp, because the solidity decoder takes what it
    /// needs from the front of the returndata and ignores the rest. So the one
    /// way to use a V2 registry wrongly is to reach it with a V1 interface,
    /// which is a mistake that reads as working — and the reason a reader pins
    /// a code hash alongside an address rather than an address alone.
    function testGetV2ReadThroughV1AbiDropsTheTimestamp(bytes32 name, address account) external {
        vm.assume(account != address(0));

        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, account);

        assertEq(IAddressRegistryV1(address(sRegistry)).get(name), account);
    }

    /// A V2 read of a V1-shaped `get` is the other direction, and that one IS
    /// loud: 32 bytes cannot fill the pair, and the decoder takes what it needs
    /// from the front of the returndata rather than inventing what is not
    /// there, so a short answer reverts. A consumer pointed at a V1 registry
    /// with this interface fails on its first read instead of trusting a
    /// fabricated timestamp.
    ///
    /// The decode runs in the CALLER's frame, not the callee's, so the read is
    /// made one frame down — `vm.expectRevert` watches the next call, and a
    /// revert raised while decoding that call's answer is not that call
    /// reverting.
    function testGetV2ReadOfV1RegistryReverts(bytes32 name) external {
        AddressRegistryV1Stub v1 = new AddressRegistryV1Stub();
        AddressRegistryV2Reader reader = new AddressRegistryV2Reader();

        // The V1 shape returns 32 bytes, which is a complete answer to the V1
        // ABI and half of one to this.
        (bool success, bytes memory returnData) =
            address(v1).staticcall(abi.encodeWithSelector(IAddressRegistryV2.get.selector, name));
        assertTrue(success);
        assertEq(returnData.length, 32);

        vm.expectRevert();
        reader.get(address(v1), name);

        // The same reader on a V2 registry answers, so what reverted above is
        // the short returndata and not the extra frame.
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, address(this));
        (address account, uint256 changedAt) = reader.get(address(sRegistry), name);
        assertEq(account, address(this));
        assertEq(changedAt, block.timestamp);
    }
}

/// @dev A `get` read through `IAddressRegistryV2`, one frame down from the test.
/// The returndata decode happens in whichever frame made the call, so a decode
/// that reverts is only observable as a reverting CALL from here.
contract AddressRegistryV2Reader {
    /// @param registry The registry to read.
    /// @param name The name to read.
    /// @return The address bound to `name`.
    /// @return The moment it became that address.
    function get(address registry, bytes32 name) external view returns (address, uint256) {
        return IAddressRegistryV2(registry).get(name);
    }
}

/// @dev A `get` with the V1 return shape and nothing else: enough to be read
/// through the V2 interface, so the decode of 32 bytes into a pair is exercised
/// without this test suite depending on the V1 contract's own storage or root.
/// It answers with its own address, because which address it answers with is
/// not what is under test — that the answer is 32 bytes is.
contract AddressRegistryV1Stub {
    /// The V1 shape: one address, 32 bytes of returndata.
    /// @return This stub's own address.
    function get(bytes32) external view returns (address) {
        return address(this);
    }
}
