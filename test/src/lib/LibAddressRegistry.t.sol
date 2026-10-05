// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibAddressRegistry} from "../../../src/lib/LibAddressRegistry.sol";
import {LibAddressRegistryDeploy} from "../../../src/lib/LibAddressRegistryDeploy.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {IAddressRegistryV1} from "../../../src/interface/IAddressRegistryV1.sol";
import {AddressRegistry, ADDRESS_REGISTRY_ROOT} from "../../../src/concrete/AddressRegistry.sol";
import {DELEGATION_DESIGNATOR_LENGTH, LibAccountCode} from "../../lib/LibAccountCode.sol";
import {MockSafeResolvedOwner} from "../../concrete/MockSafeResolvedOwner.sol";

/// @title LibAddressRegistryTest
/// Tests for `LibAddressRegistry`. The registry is not mocked: the real
/// `AddressRegistry` is deployed through the Zoltu factory, which lands it at
/// the pinned address with the pinned code hash.
contract LibAddressRegistryTest is Test {
    /// Deploys `AddressRegistry` through the Zoltu factory.
    /// @return The deployed registry.
    function deployRegistry() internal returns (IAddressRegistryV1) {
        LibRainDeploy.etchZoltuFactory(vm);
        return IAddressRegistryV1(LibRainDeploy.deployZoltu(type(AddressRegistry).creationCode));
    }

    /// External wrapper for `resolve`, for `vm.expectRevert`'s call depth.
    /// @param name The name to resolve.
    /// @return The address bound to `name`.
    function externalResolve(bytes32 name) external view returns (address) {
        (address account,) = LibAddressRegistry.resolve(name);
        return account;
    }

    /// The address half of `resolve`.
    /// @param name The name to resolve.
    /// @return The address bound to `name`.
    function resolveAddress(bytes32 name) internal view returns (address) {
        (address account,) = LibAddressRegistry.resolve(name);
        return account;
    }

    /// A bound name resolves to the address it is bound to, and to the moment
    /// that address was bound.
    function testResolveRegistered(bytes32 name, address account, uint96 time) external {
        vm.assume(account != address(0));
        IAddressRegistryV1 registry = deployRegistry();

        time = uint96(bound(time, 1, type(uint96).max));
        vm.warp(time);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        registry.register(name, account);

        (address resolved, uint256 registeredAt) = LibAddressRegistry.resolve(name);
        assertEq(resolved, account);
        assertEq(registeredAt, time);
    }

    /// `resolve` answers with the current binding, not the first one, and the
    /// moment follows the address.
    function testResolveFollowsRebinding(bytes32 name, address bound, address account, uint96 first, uint96 second)
        external
    {
        vm.assume(bound != address(0));
        vm.assume(account != address(0));
        vm.assume(bound != account);
        // `vm.assume` rather than `bound` because this test's `bound` parameter
        // shadows forge-std's helper of that name.
        vm.assume(first > 0);
        vm.assume(second > first);
        IAddressRegistryV1 registry = deployRegistry();

        vm.warp(first);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        registry.register(name, bound);
        assertEq(resolveAddress(name), bound);

        vm.warp(second);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        registry.register(name, account);
        (address resolved, uint256 registeredAt) = LibAddressRegistry.resolve(name);
        assertEq(resolved, account);
        assertEq(registeredAt, second);
    }

    /// An unbound name reverts, with the registry's own error unmodified.
    function testResolveUnregistered(bytes32 name) external {
        deployRegistry();

        vm.expectRevert(abi.encodeWithSelector(IAddressRegistryV1.NameNotRegistered.selector, name));
        this.externalResolve(name);
    }

    /// A chain with no registry deployed reverts on the code hash, with an
    /// actual hash of zero: a never-touched address does not exist at all.
    function testResolveNoRegistry(bytes32 name) external {
        assertEq(LibAddressRegistryDeploy.ADDRESS_REGISTRY_DEPLOYED_ADDRESS.code.length, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                LibAddressRegistry.UnexpectedAddressRegistryCodeHash.selector,
                LibAddressRegistryDeploy.ADDRESS_REGISTRY_DEPLOYED_CODEHASH,
                bytes32(0)
            )
        );
        this.externalResolve(name);
    }

    /// A codeless registry address that EXISTS — funded with a single wei —
    /// hashes to the empty string, not to zero, and the guard still fires.
    function testResolveNoRegistryFundedAccount(bytes32 name, uint256 balance) external {
        balance = bound(balance, 1, type(uint128).max);
        vm.deal(LibAddressRegistryDeploy.ADDRESS_REGISTRY_DEPLOYED_ADDRESS, balance);

        assertEq(LibAddressRegistryDeploy.ADDRESS_REGISTRY_DEPLOYED_ADDRESS.code.length, 0);
        assertEq(LibAddressRegistryDeploy.ADDRESS_REGISTRY_DEPLOYED_ADDRESS.codehash, keccak256(""));

        vm.expectRevert(
            abi.encodeWithSelector(
                LibAddressRegistry.UnexpectedAddressRegistryCodeHash.selector,
                LibAddressRegistryDeploy.ADDRESS_REGISTRY_DEPLOYED_CODEHASH,
                keccak256("")
            )
        );
        this.externalResolve(name);
    }

    /// A chain where ORDINARY code — anything that is not a delegation
    /// designator — occupies the address reverts on the code hash.
    function testResolveWrongCode(bytes32 name, bytes memory code) external {
        vm.assume(code.length > 0);
        vm.assume(!LibAccountCode.hasDelegationPrefix(code));
        vm.assume(keccak256(code) != LibAddressRegistryDeploy.ADDRESS_REGISTRY_DEPLOYED_CODEHASH);
        vm.etch(LibAddressRegistryDeploy.ADDRESS_REGISTRY_DEPLOYED_ADDRESS, code);

        vm.expectRevert(
            abi.encodeWithSelector(
                LibAddressRegistry.UnexpectedAddressRegistryCodeHash.selector,
                LibAddressRegistryDeploy.ADDRESS_REGISTRY_DEPLOYED_CODEHASH,
                keccak256(code)
            )
        );
        this.externalResolve(name);
    }

    /// A chain where an EOA has DELEGATED the registry address under EIP-7702
    /// reverts on the code hash too: the account hashes its 23-byte designator,
    /// never the delegate's code, so it can never present the pinned hash.
    /// @param name The name a caller would resolve.
    /// @param delegate The account the registry address is delegated to.
    function testResolveDelegatedCode(bytes32 name, address delegate) external {
        vm.assume(delegate != address(0));
        bytes memory designator = LibAccountCode.delegationDesignator(delegate);
        assertEq(designator.length, DELEGATION_DESIGNATOR_LENGTH);
        assertTrue(LibAccountCode.hasDelegationPrefix(designator));

        vm.etch(LibAddressRegistryDeploy.ADDRESS_REGISTRY_DEPLOYED_ADDRESS, designator);
        assertEq(LibAddressRegistryDeploy.ADDRESS_REGISTRY_DEPLOYED_ADDRESS.codehash, keccak256(designator));

        vm.expectRevert(
            abi.encodeWithSelector(
                LibAddressRegistry.UnexpectedAddressRegistryCodeHash.selector,
                LibAddressRegistryDeploy.ADDRESS_REGISTRY_DEPLOYED_CODEHASH,
                keccak256(designator)
            )
        );
        this.externalResolve(name);
    }

    /// External wrapper for `resolveSafe`, for `vm.expectRevert`'s call depth.
    /// @param name The name to resolve.
    /// @param minAge The least time the binding must have stood.
    /// @return The address bound to `name`.
    function externalResolveSafe(bytes32 name, uint256 minAge) external view returns (address) {
        return LibAddressRegistry.resolveSafe(name, minAge);
    }

    /// A binding that has stood longer than the caller's minimum resolves to its
    /// address.
    function testResolveSafeOldEnough(bytes32 name, address account, uint64 minAge, uint64 extra) external {
        vm.assume(account != address(0));
        vm.assume(minAge > 0);
        IAddressRegistryV1 registry = deployRegistry();

        vm.prank(ADDRESS_REGISTRY_ROOT);
        registry.register(name, account);

        extra = uint64(bound(extra, 1, type(uint64).max));
        vm.warp(block.timestamp + uint256(minAge) + uint256(extra));
        assertEq(LibAddressRegistry.resolveSafe(name, minAge), account);
    }

    /// A binding exactly `minAge` old is REFUSED: the binding must have stood
    /// for strictly longer.
    function testResolveSafeRefusesExactlyMinAge(bytes32 name, address account, uint64 minAge) external {
        vm.assume(account != address(0));
        vm.assume(minAge > 0);
        IAddressRegistryV1 registry = deployRegistry();

        vm.prank(ADDRESS_REGISTRY_ROOT);
        registry.register(name, account);

        vm.warp(block.timestamp + uint256(minAge));
        vm.expectRevert(
            abi.encodeWithSelector(LibAddressRegistry.BindingTooFresh.selector, name, uint256(minAge), uint256(minAge))
        );
        this.externalResolveSafe(name, minAge);
    }

    /// One second past `minAge` is accepted.
    function testResolveSafeAcceptsOneSecondPastMinAge(bytes32 name, address account, uint64 minAge) external {
        vm.assume(account != address(0));
        vm.assume(minAge > 0);
        IAddressRegistryV1 registry = deployRegistry();

        vm.prank(ADDRESS_REGISTRY_ROOT);
        registry.register(name, account);

        vm.warp(block.timestamp + uint256(minAge) + 1);
        assertEq(LibAddressRegistry.resolveSafe(name, minAge), account);
    }

    /// A binding younger than the minimum is refused, and the revert carries the
    /// age it had and the age it needed.
    function testResolveSafeTooFresh(bytes32 name, address account, uint64 age, uint64 minAge) external {
        vm.assume(account != address(0));
        vm.assume(age < minAge);
        IAddressRegistryV1 registry = deployRegistry();

        vm.prank(ADDRESS_REGISTRY_ROOT);
        registry.register(name, account);

        vm.warp(block.timestamp + uint256(age));
        vm.expectRevert(abi.encodeWithSelector(LibAddressRegistry.BindingTooFresh.selector, name, age, minAge));
        this.externalResolveSafe(name, minAge);
    }

    /// A binding made in the block being read is refused by any nonzero minimum.
    function testResolveSafeSameBlockRefused(bytes32 name, address account, uint64 minAge) external {
        vm.assume(account != address(0));
        vm.assume(minAge > 0);
        IAddressRegistryV1 registry = deployRegistry();

        vm.prank(ADDRESS_REGISTRY_ROOT);
        registry.register(name, account);

        vm.expectRevert(abi.encodeWithSelector(LibAddressRegistry.BindingTooFresh.selector, name, 0, minAge));
        this.externalResolveSafe(name, minAge);
    }

    /// A minimum of zero is refused rather than honoured, even for a binding
    /// that would pass any real threshold.
    function testResolveSafeZeroMinAgeRefused(bytes32 name, address account, uint64 aged) external {
        vm.assume(account != address(0));
        IAddressRegistryV1 registry = deployRegistry();

        vm.prank(ADDRESS_REGISTRY_ROOT);
        registry.register(name, account);
        vm.warp(block.timestamp + uint256(aged));

        vm.expectRevert(abi.encodeWithSelector(LibAddressRegistry.ZeroMinAge.selector, name));
        this.externalResolveSafe(name, 0);
    }

    /// Zero is refused before the registry is read at all, so an unbound name
    /// with a zero minimum reports the zero rather than the missing binding.
    function testResolveSafeZeroMinAgeBeatsUnregistered(bytes32 name) external {
        deployRegistry();

        vm.expectRevert(abi.encodeWithSelector(LibAddressRegistry.ZeroMinAge.selector, name));
        this.externalResolveSafe(name, 0);
    }

    /// And before the code-hash guard, so a zero minimum is reported even on a
    /// chain with no registry deployed.
    function testResolveSafeZeroMinAgeBeatsMissingRegistry(bytes32 name) external {
        assertEq(LibAddressRegistryDeploy.ADDRESS_REGISTRY_DEPLOYED_ADDRESS.code.length, 0);

        vm.expectRevert(abi.encodeWithSelector(LibAddressRegistry.ZeroMinAge.selector, name));
        this.externalResolveSafe(name, 0);
    }

    /// A re-bind makes the name fresh again, so a binding that passed before the
    /// rotation is refused after it.
    function testResolveSafeRebindResetsAge(bytes32 name, address boundTo, address account, uint64 minAge, uint64 aged)
        external
    {
        vm.assume(boundTo != address(0));
        vm.assume(account != address(0));
        vm.assume(minAge > 0);
        vm.assume(minAge < type(uint64).max);
        aged = uint64(bound(aged, uint256(minAge) + 1, type(uint64).max));
        IAddressRegistryV1 registry = deployRegistry();

        vm.prank(ADDRESS_REGISTRY_ROOT);
        registry.register(name, boundTo);

        vm.warp(block.timestamp + uint256(aged));
        assertEq(LibAddressRegistry.resolveSafe(name, minAge), boundTo);

        vm.prank(ADDRESS_REGISTRY_ROOT);
        registry.register(name, account);

        vm.expectRevert(abi.encodeWithSelector(LibAddressRegistry.BindingTooFresh.selector, name, 0, minAge));
        this.externalResolveSafe(name, minAge);
    }

    /// A binding stamped in the future is refused with `BindingStampedInFuture`
    /// rather than reverting on an underflow of `block.timestamp -
    /// registeredAt`.
    function testResolveSafeStampedInFuture(bytes32 name, address account, uint64 ahead, uint64 minAge) external {
        vm.assume(account != address(0));
        vm.assume(ahead > 0);
        vm.assume(minAge > 0);
        IAddressRegistryV1 registry = deployRegistry();

        vm.warp(uint256(ahead) + 1);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        registry.register(name, account);

        // The clock goes backwards, leaving the binding stamped ahead of it.
        vm.warp(1);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibAddressRegistry.BindingStampedInFuture.selector, name, uint256(ahead) + 1, uint256(1)
            )
        );
        this.externalResolveSafe(name, minAge);
    }

    /// A future stamp is refused however large the caller's minimum.
    function testResolveSafeStampedInFutureRefusedAtAnyMinAge(bytes32 name, address account, uint64 ahead) external {
        vm.assume(account != address(0));
        vm.assume(ahead > 0);
        IAddressRegistryV1 registry = deployRegistry();

        vm.warp(uint256(ahead) + 1);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        registry.register(name, account);
        vm.warp(1);

        uint256[3] memory minAges = [uint256(1), uint256(type(uint64).max), type(uint256).max];
        for (uint256 i = 0; i < minAges.length; i++) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    LibAddressRegistry.BindingStampedInFuture.selector, name, uint256(ahead) + 1, uint256(1)
                )
            );
            this.externalResolveSafe(name, minAges[i]);
        }
    }

    /// A binding stamped at exactly the clock is NOT in the future — it is the
    /// too-fresh case, which is the boundary between the two errors.
    function testResolveSafeSameTimestampIsFreshNotFuture(bytes32 name, address account, uint64 minAge) external {
        vm.assume(account != address(0));
        vm.assume(minAge > 0);
        IAddressRegistryV1 registry = deployRegistry();

        vm.prank(ADDRESS_REGISTRY_ROOT);
        registry.register(name, account);

        vm.expectRevert(abi.encodeWithSelector(LibAddressRegistry.BindingTooFresh.selector, name, 0, minAge));
        this.externalResolveSafe(name, minAge);
    }

    /// An unbound name reverts from the registry, before the freshness check can
    /// have an opinion.
    function testResolveSafeUnregistered(bytes32 name, uint256 minAge) external {
        vm.assume(minAge > 0);
        deployRegistry();

        vm.expectRevert(abi.encodeWithSelector(IAddressRegistryV1.NameNotRegistered.selector, name));
        this.externalResolveSafe(name, minAge);
    }

    /// The code-hash guard runs first here too.
    function testResolveSafeNoRegistry(bytes32 name, uint256 minAge) external {
        vm.assume(minAge > 0);
        assertEq(LibAddressRegistryDeploy.ADDRESS_REGISTRY_DEPLOYED_ADDRESS.code.length, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                LibAddressRegistry.UnexpectedAddressRegistryCodeHash.selector,
                LibAddressRegistryDeploy.ADDRESS_REGISTRY_DEPLOYED_CODEHASH,
                bytes32(0)
            )
        );
        this.externalResolveSafe(name, minAge);
    }

    /// A consumer resolving once, in its constructor, under its own threshold
    /// comes into existence holding the vetted address.
    function testResolveSafeFromConstructor(bytes32 name, address account, uint64 minAge, uint64 extra) external {
        vm.assume(account != address(0));
        vm.assume(minAge > 0);
        IAddressRegistryV1 registry = deployRegistry();

        vm.prank(ADDRESS_REGISTRY_ROOT);
        registry.register(name, account);
        extra = uint64(bound(extra, 1, type(uint64).max));
        vm.warp(block.timestamp + uint256(minAge) + uint256(extra));

        MockSafeResolvedOwner consumer = new MockSafeResolvedOwner(name, minAge);
        assertEq(consumer.iOwner(), account);
    }

    /// A consumer's deploy reverts against a binding that has not stood long
    /// enough, so no contract is left holding an unvetted address.
    function testResolveSafeFromConstructorRefusesFreshBinding(bytes32 name, address account, uint64 minAge, uint64 age)
        external
    {
        vm.assume(account != address(0));
        vm.assume(age < minAge);
        IAddressRegistryV1 registry = deployRegistry();

        vm.prank(ADDRESS_REGISTRY_ROOT);
        registry.register(name, account);
        vm.warp(block.timestamp + uint256(age));

        vm.expectRevert(abi.encodeWithSelector(LibAddressRegistry.BindingTooFresh.selector, name, age, minAge));
        new MockSafeResolvedOwner(name, minAge);
    }

    /// The Zoltu deploy really does land the registry on its pinned address
    /// with its pinned code hash.
    function testDeployMatchesPins() external {
        deployRegistry();

        assertEq(
            LibAddressRegistryDeploy.ADDRESS_REGISTRY_DEPLOYED_ADDRESS.codehash,
            LibAddressRegistryDeploy.ADDRESS_REGISTRY_DEPLOYED_CODEHASH
        );
    }
}
