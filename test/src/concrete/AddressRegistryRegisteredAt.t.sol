// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";

import {IAddressRegistryV1} from "../../../src/interface/IAddressRegistryV1.sol";
import {AddressRegistry, ADDRESS_REGISTRY_ROOT} from "../../../src/concrete/AddressRegistry.sol";

/// @title AddressRegistryRegisteredAtTest
/// @notice A test suite for `AddressRegistry.registeredAt`: it dates the write
/// rather than the value, it refuses an unbound name rather than answering with
/// an age that passes every test, and it never narrows the stamp it reports.
contract AddressRegistryRegisteredAtTest is Test {
    /// The registry under test. Stateful, so a fresh one per test.
    AddressRegistry internal sRegistry;

    function setUp() external {
        sRegistry = new AddressRegistry();
    }

    /// The stamp of an unbound name reverts rather than reading as zero. Zero is
    /// an ordinary number to subtract from, so a caller handed it would compute
    /// an age of the whole of time — the one age that passes every freshness
    /// test, handed out for the names nobody has bound at all.
    function testRegisteredAtUnsetReverts(bytes32 name) external {
        vm.expectRevert(abi.encodeWithSelector(IAddressRegistryV1.NameNotRegistered.selector, name));
        sRegistry.registeredAt(name);
    }

    /// A binding records the block time it was made at, which is the whole point
    /// of the reader: the age of the answer is on chain rather than only in the
    /// logs.
    function testRegisteredAtRecordsBindTime(bytes32 name, address account, uint96 time) external {
        vm.assume(account != address(0));

        vm.warp(time);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, account);

        assertEq(sRegistry.registeredAt(name), time);
    }

    /// The stamp does not drift as the chain advances. It is the moment of the
    /// write, read back unchanged however long afterwards, so an age computed
    /// against `block.timestamp` grows rather than standing still.
    function testRegisteredAtStableAsTimePasses(bytes32 name, address account, uint96 time, uint96 elapsed) external {
        vm.assume(account != address(0));
        time = uint96(bound(time, 0, type(uint96).max - elapsed));

        vm.warp(time);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, account);

        vm.warp(uint256(time) + elapsed);
        assertEq(sRegistry.registeredAt(name), time);
        assertEq(block.timestamp - sRegistry.registeredAt(name), elapsed);
    }

    /// A re-bind replaces the stamp along with the address. The age a consumer
    /// cares about is the age of the address it is about to snapshot, so a
    /// rotation makes the binding new again.
    function testRegisteredAtRebindRefreshes(bytes32 name, address bound_, address account, uint96 first, uint96 second)
        external
    {
        vm.assume(bound_ != address(0));
        vm.assume(account != address(0));

        vm.warp(first);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, bound_);
        assertEq(sRegistry.registeredAt(name), first);

        vm.warp(second);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, account);
        assertEq(sRegistry.registeredAt(name), second);
        assertEq(sRegistry.get(name), account);
    }

    /// Re-binding a name to the address it already holds still refreshes the
    /// stamp. The stamp dates the WRITE, not the value — root re-asserting a
    /// binding is root touching it — and reporting the later moment is the
    /// conservative direction: it can only make an answer look fresher than the
    /// address really is, so a consumer refusing fresh answers errs toward
    /// refusing.
    function testRegisteredAtRebindSameAccountRefreshes(bytes32 name, address account, uint96 first, uint96 second)
        external
    {
        vm.assume(account != address(0));
        vm.assume(first != second);

        vm.warp(first);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, account);
        assertEq(sRegistry.registeredAt(name), first);

        vm.warp(second);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, account);

        assertEq(sRegistry.registeredAt(name), second);
        assertEq(sRegistry.get(name), account);
    }

    /// Stamps are per name. Binding one name says nothing about another's age,
    /// and re-binding one does not disturb another's stamp.
    function testRegisteredAtDistinctNames(
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

        vm.warp(timeA);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(nameA, accountA);

        // Binding `nameA` did not stamp `nameB`.
        vm.expectRevert(abi.encodeWithSelector(IAddressRegistryV1.NameNotRegistered.selector, nameB));
        sRegistry.registeredAt(nameB);

        vm.warp(timeB);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(nameB, accountB);

        assertEq(sRegistry.registeredAt(nameA), timeA);
        assertEq(sRegistry.registeredAt(nameB), timeB);
    }

    /// A name bound on a chain at block time zero is bound, and its stamp is
    /// legitimately zero. This is why neither reader decides bound-ness from the
    /// stamp: here the stamp of a bound name is indistinguishable from the stamp
    /// of a name nobody ever bound, while `get` and the revert are not.
    function testRegisteredAtZeroBlockTime(bytes32 name, bytes32 unbound, address account) external {
        vm.assume(account != address(0));
        vm.assume(name != unbound);

        vm.warp(0);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, account);

        assertEq(sRegistry.registeredAt(name), 0);
        assertEq(sRegistry.get(name), account);

        vm.expectRevert(abi.encodeWithSelector(IAddressRegistryV1.NameNotRegistered.selector, unbound));
        sRegistry.registeredAt(unbound);
    }

    /// The widest stamp that fits is accepted, so the rejection below is a
    /// boundary and not an off-by-one that refuses legitimate binds.
    function testRegisteredAtMaxStampAccepted(bytes32 name, address account) external {
        vm.assume(account != address(0));

        vm.warp(type(uint96).max);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, account);

        assertEq(sRegistry.registeredAt(name), type(uint96).max);
    }

    /// A timestamp too wide for the stamp is REFUSED, never narrowed. A
    /// truncated stamp is a smaller number, which reads as an older binding,
    /// which passes exactly the check the reader exists to let a caller fail —
    /// so the unsafe direction is the one made impossible.
    function testRegisteredAtOverflowRejected(bytes32 name, address account, uint256 time) external {
        vm.assume(account != address(0));
        time = bound(time, uint256(type(uint96).max) + 1, type(uint256).max);

        vm.warp(time);
        vm.expectRevert(abi.encodeWithSelector(AddressRegistry.TimestampOverflow.selector, time));
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, account);

        // Refused outright: the name is not bound by a register that overflowed.
        vm.expectRevert(abi.encodeWithSelector(IAddressRegistryV1.NameNotRegistered.selector, name));
        sRegistry.registeredAt(name);
    }

    /// An overflowing `register` leaves an existing binding and its stamp
    /// exactly as they were, rather than half-writing one.
    function testRegisteredAtOverflowLeavesBindingIntact(
        bytes32 name,
        address bound_,
        address account,
        uint96 first,
        uint256 time
    ) external {
        vm.assume(bound_ != address(0));
        vm.assume(account != address(0));
        time = bound(time, uint256(type(uint96).max) + 1, type(uint256).max);

        vm.warp(first);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, bound_);

        vm.warp(time);
        vm.expectRevert(abi.encodeWithSelector(AddressRegistry.TimestampOverflow.selector, time));
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, account);

        assertEq(sRegistry.get(name), bound_);
        assertEq(sRegistry.registeredAt(name), first);
    }

    /// A rejected `register` never moves a stamp. A non-root caller cannot
    /// refresh a binding's age, which would otherwise let anybody launder a
    /// stale binding into one that looks newly reviewed.
    function testRegisteredAtUnchangedByNonRoot(
        address sender,
        bytes32 name,
        address bound_,
        address account,
        uint96 first,
        uint96 second
    ) external {
        vm.assume(sender != ADDRESS_REGISTRY_ROOT);
        vm.assume(bound_ != address(0));

        vm.warp(first);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, bound_);

        vm.warp(second);
        vm.expectRevert(abi.encodeWithSelector(IAddressRegistryV1.NotRoot.selector, sender));
        vm.prank(sender);
        sRegistry.register(name, account);

        assertEq(sRegistry.registeredAt(name), first);
    }

    /// A zero-address `register` never moves a stamp either, so there is no way
    /// to refresh a binding's age without also re-asserting its address.
    function testRegisteredAtUnchangedByZeroAccount(bytes32 name, address bound_, uint96 first, uint96 second)
        external
    {
        vm.assume(bound_ != address(0));

        vm.warp(first);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, bound_);

        vm.warp(second);
        vm.expectRevert(abi.encodeWithSelector(IAddressRegistryV1.ZeroAccount.selector, name));
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, address(0));

        assertEq(sRegistry.registeredAt(name), first);
    }

    /// Reading a stamp does not consume or alter it.
    function testRegisteredAtIdempotentRead(bytes32 name, address account, uint96 time) external {
        vm.assume(account != address(0));

        vm.warp(time);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        sRegistry.register(name, account);

        assertEq(sRegistry.registeredAt(name), time);
        assertEq(sRegistry.registeredAt(name), time);
    }

    /// The address and the stamp share a storage word, so a bind writes both or
    /// neither. Reading them back after a rotation proves they were replaced
    /// together rather than one lagging the other — a stamp that could lag its
    /// address would be worse than no stamp, because a stale answer would read
    /// as a fresh one.
    function testRegisteredAtPairedWithAccount(bytes32 name, address[] memory accounts, uint96 start) external {
        vm.assume(accounts.length > 0);
        start = uint96(bound(start, 0, type(uint96).max - accounts.length));
        for (uint256 i = 0; i < accounts.length; i++) {
            vm.assume(accounts[i] != address(0));
        }

        for (uint256 i = 0; i < accounts.length; i++) {
            vm.warp(uint256(start) + i);
            vm.prank(ADDRESS_REGISTRY_ROOT);
            sRegistry.register(name, accounts[i]);

            assertEq(sRegistry.get(name), accounts[i]);
            assertEq(sRegistry.registeredAt(name), uint256(start) + i);
        }
    }
}
