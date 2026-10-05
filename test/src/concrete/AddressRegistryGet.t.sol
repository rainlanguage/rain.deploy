// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";

import {IAddressRegistryV1} from "../../../src/interface/IAddressRegistryV1.sol";
import {AddressRegistry, ADDRESS_REGISTRY_ROOT} from "../../../src/concrete/AddressRegistry.sol";

/// @title AddressRegistryGetTest
/// @notice A test suite for `AddressRegistry.get`: it answers a bound name with
/// its address AND the moment that address was bound, an unbound name with a
/// revert, and it is the only reader the registry has.
contract AddressRegistryGetTest is Test {
    /// The registry under test. Stateful, so a fresh one per test.
    AddressRegistry internal sRegistry;

    function setUp() external {
        sRegistry = new AddressRegistry();
    }

    /// The address half of `get`, for the assertions that are only about the
    /// address. The moment has its own tests rather than being repeated into
    /// every one of them.
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

    /// A read of an unbound name reverts rather than returning the zero
    /// address, so a caller cannot proceed on a name nobody bound by forgetting
    /// to check.
    function testGetUnsetReverts(bytes32 name) external {
        vm.expectRevert(abi.encodeWithSelector(IAddressRegistryV1.NameNotRegistered.selector, name));
        getAddress(sRegistry, name);
    }

    /// A read of a bound name returns exactly what was bound, and reading does
    /// not consume or alter the binding.
    function testGetReturnsRegistered(bytes32 name, address account) external {
        vm.assume(account != address(0));

        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, account);

        assertEq(getAddress(sRegistry, name), account);
        assertEq(getAddress(sRegistry, name), account);
    }

    /// Names are opaque: nothing about a name's bytes changes how it is stored
    /// or read, including names a string-hashing convention would never
    /// produce.
    function testGetOpaqueNames(address account) external {
        vm.assume(account != address(0));

        bytes32[3] memory names = [bytes32(0), bytes32(uint256(1)), bytes32(type(uint256).max)];
        for (uint256 i = 0; i < names.length; i++) {
            AddressRegistry registry = new AddressRegistry();
            vm.prank(ADDRESS_REGISTRY_ROOT);
            registry.register(names[i], account);
            assertEq(getAddress(registry, names[i]), account);
        }
    }

    /// The bindings mapping is not `public`, so the getter a `public` mapping
    /// would generate — which answers an unbound name with a zero `account`,
    /// the exact silent failure `get` reverts to prevent — does not exist.
    function testGetNoGeneratedMappingGetter(bytes32 name) external {
        (bool success,) = address(sRegistry).call(abi.encodeWithSignature("sBindings(bytes32)", name));
        assertFalse(success);
    }

    /// There is no other entry point at all: no fallback, no receive, and
    /// nothing beyond the two `IAddressRegistryV1` functions, so an unknown
    /// selector reverts instead of being silently absorbed.
    function testGetNoOtherEntryPoint(bytes4 selector, bytes32 name) external {
        vm.assume(selector != IAddressRegistryV1.get.selector);
        vm.assume(selector != IAddressRegistryV1.register.selector);

        (bool success,) = address(sRegistry).call(abi.encodeWithSelector(selector, name, address(this)));
        assertFalse(success);
    }

    /// The ABI is exactly the two `IAddressRegistryV1` functions, counted
    /// rather than sampled. A fuzz over unknown selectors cannot see a reader
    /// added under a name of its own, and such a reader is precisely what the
    /// interface forbids: it would answer an unbound name with the zero
    /// address, the silent failure `get` reverts to prevent.
    function testGetAbiIsExactlyTheInterface() external view {
        string[] memory signatures =
            vm.parseJsonKeys(vm.readFile("out/AddressRegistry.sol/AddressRegistry.json"), "$.methodIdentifiers");

        assertEq(signatures.length, 2);
        assertEq(signatures[0], "get(bytes32)");
        assertEq(signatures[1], "register(bytes32,address)");
    }

    /// The registry takes no value on any path. Neither entry point is payable
    /// and there is no `receive`, so ether sent with or without calldata is
    /// refused rather than trapped in a contract that holds no way to move it
    /// out again.
    function testGetNoValueEntryPoint(bytes32 name, address account) external {
        vm.assume(account != address(0));
        vm.deal(ADDRESS_REGISTRY_ROOT, 3);

        vm.prank(ADDRESS_REGISTRY_ROOT);
        (bool bare,) = address(sRegistry).call{value: 1}("");
        assertFalse(bare);

        vm.prank(ADDRESS_REGISTRY_ROOT);
        (bool bound,) = address(sRegistry).call{value: 1}(abi.encodeCall(IAddressRegistryV1.register, (name, account)));
        assertFalse(bound);

        vm.prank(ADDRESS_REGISTRY_ROOT);
        (bool read,) = address(sRegistry).call{value: 1}(abi.encodeCall(IAddressRegistryV1.get, (name)));
        assertFalse(read);

        assertEq(address(sRegistry).balance, 0);
    }

    /// `get` answers with the moment the binding was made, which is the whole
    /// point of it returning two values: the age of the answer is on chain
    /// rather than only recoverable from the logs.
    function testGetReturnsMoment(bytes32 name, address account, uint96 time) external {
        vm.assume(account != address(0));

        time = uint96(bound(time, 1, type(uint96).max));
        vm.warp(time);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, account);

        (address got, uint256 registeredAt) = sRegistry.get(name);
        assertEq(got, account);
        assertEq(registeredAt, time);
    }

    /// The moment does not drift as the chain advances. It is the moment of the
    /// write, read back unchanged however long afterwards, so an age computed
    /// against `block.timestamp` grows rather than standing still.
    function testGetMomentStableAsTimePasses(bytes32 name, address account, uint96 time, uint96 elapsed) external {
        vm.assume(account != address(0));
        elapsed = uint96(bound(elapsed, 0, type(uint96).max - 1));
        time = uint96(bound(time, 1, type(uint96).max - elapsed));

        vm.warp(time);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, account);

        vm.warp(uint256(time) + elapsed);
        assertEq(getMoment(sRegistry, name), time);
        assertEq(block.timestamp - getMoment(sRegistry, name), elapsed);
    }

    /// The moment `get` answers with is never zero. `register` refuses a bind at
    /// a clock of zero, so zero in the moment field means unbound and nothing
    /// else — the one reading that would otherwise be ambiguous.
    function testGetMomentNeverZero(bytes32 name, address account, uint96 time) external {
        vm.assume(account != address(0));
        time = uint96(bound(time, 1, type(uint96).max));

        vm.warp(time);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, account);

        (address got, uint256 registeredAt) = sRegistry.get(name);
        assertEq(got, account);
        assertTrue(registeredAt != 0);
        assertEq(registeredAt, time);
    }

    /// Moments are per name. Binding one name says nothing about another's age.
    function testGetMomentDistinctNames(
        bytes32 nameA,
        bytes32 nameB,
        address accountA,
        address accountB,
        uint96 timeA,
        uint96 timeB
    ) external {
        vm.assume(nameA != nameB);
        vm.assume(accountA != address(0));
        vm.assume(accountB != address(0));

        timeA = uint96(bound(timeA, 1, type(uint96).max));
        vm.warp(timeA);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(nameA, accountA);

        timeB = uint96(bound(timeB, 1, type(uint96).max));
        vm.warp(timeB);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(nameB, accountB);

        assertEq(getMoment(sRegistry, nameA), timeA);
        assertEq(getMoment(sRegistry, nameB), timeB);
    }

    /// The widest moment that fits is accepted, so the rejection below is a
    /// boundary and not an off-by-one refusing legitimate binds.
    function testGetMomentMaxAccepted(bytes32 name, address account) external {
        vm.assume(account != address(0));

        vm.warp(type(uint96).max);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, account);

        assertEq(getMoment(sRegistry, name), type(uint96).max);
    }

    /// A timestamp too wide for the moment is REFUSED, never narrowed. A
    /// truncated moment is a smaller number, which reads as an older binding,
    /// which passes exactly the check a caller reads it to fail — so the unsafe
    /// direction is made impossible rather than improbable.
    function testGetMomentOverflowRejected(bytes32 name, address account, uint256 time) external {
        vm.assume(account != address(0));
        time = bound(time, uint256(type(uint96).max) + 1, type(uint256).max);

        vm.warp(time);
        vm.expectRevert(abi.encodeWithSelector(AddressRegistry.TimestampOverflow.selector, time));
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, account);

        // Refused outright: the name is not bound by a register that overflowed.
        vm.expectRevert(abi.encodeWithSelector(IAddressRegistryV1.NameNotRegistered.selector, name));
        getAddress(sRegistry, name);
    }

    /// An overflowing `register` leaves an existing binding and its moment
    /// exactly as they were, rather than half-writing one.
    function testGetMomentOverflowLeavesBindingIntact(
        bytes32 name,
        address bound_,
        address account,
        uint96 first,
        uint256 time
    ) external {
        vm.assume(bound_ != address(0));
        vm.assume(account != address(0));
        // Past the stamp's width, so the width guard is what refuses the second
        // bind. Deliberately a `uint256` beyond `uint96` range, so it must NOT
        // be clamped back into it.
        time = bound(time, uint256(type(uint96).max) + 1, type(uint256).max);
        // Nonzero, because a bind at a clock of zero is refused outright.
        first = uint96(bound(first, 1, type(uint96).max));

        vm.warp(first);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, bound_);

        vm.warp(time);
        vm.expectRevert(abi.encodeWithSelector(AddressRegistry.TimestampOverflow.selector, time));
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, account);

        (address got, uint256 registeredAt) = sRegistry.get(name);
        assertEq(got, bound_);
        assertEq(registeredAt, first);
    }

    /// The address and the moment share a storage word, so a bind writes both or
    /// neither. Reading them back across a run of rotations proves they were
    /// replaced together rather than one lagging the other — a moment that could
    /// lag its address would be worse than none, because a stale answer would
    /// read as a fresh one.
    function testGetAddressAndMomentMoveTogether(bytes32 name, address[] memory accounts, uint96 start) external {
        vm.assume(accounts.length > 0);
        start = uint96(bound(start, 1, type(uint96).max - accounts.length));
        for (uint256 i = 0; i < accounts.length; i++) {
            vm.assume(accounts[i] != address(0));
        }

        for (uint256 i = 0; i < accounts.length; i++) {
            vm.warp(uint256(start) + i);
            vm.prank(ADDRESS_REGISTRY_ROOT);
            sRegistry.register(name, accounts[i]);

            (address got, uint256 registeredAt) = sRegistry.get(name);
            assertEq(got, accounts[i]);
            assertEq(registeredAt, uint256(start) + i);
        }
    }
}
