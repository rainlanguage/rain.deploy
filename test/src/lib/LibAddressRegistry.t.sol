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

/// @title LibAddressRegistryTest
/// Tests for `LibAddressRegistry`. The registry is not mocked: the real
/// `AddressRegistry` is deployed through the Zoltu factory, which is what puts
/// it at the pinned address with the pinned code hash, so every test runs
/// against the same bytecode a network would.
///
/// External wrappers are used for the library function so `vm.expectRevert`
/// lands at the correct call depth.
contract LibAddressRegistryTest is Test {
    /// Deploys `AddressRegistry` through the Zoltu factory, which lands it at
    /// the pinned address.
    /// @return The deployed registry.
    function deployRegistry() internal returns (IAddressRegistryV1) {
        LibRainDeploy.etchZoltuFactory(vm);
        return IAddressRegistryV1(LibRainDeploy.deployZoltu(type(AddressRegistry).creationCode));
    }

    /// External wrapper for `resolve` so that `vm.expectRevert` works at the
    /// correct call depth.
    /// @param name The name to resolve.
    /// @return The address bound to `name`.
    function externalResolve(bytes32 name) external view returns (address) {
        (address account,) = LibAddressRegistry.resolve(name);
        return account;
    }

    /// The address half of `resolve`, for the assertions that are only about
    /// which address a name resolves to.
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

        vm.warp(time);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        registry.register(name, account);

        (address resolved, uint256 registeredAt) = LibAddressRegistry.resolve(name);
        assertEq(resolved, account);
        assertEq(registeredAt, time);
    }

    /// `resolve` answers with the current binding, not the first one. A caller
    /// that wants an answer which cannot move has to read once and store it —
    /// the library deliberately does not pretend to offer that itself.
    function testResolveFollowsRebinding(bytes32 name, address bound, address account, uint96 first, uint96 second)
        external
    {
        vm.assume(bound != address(0));
        vm.assume(account != address(0));
        vm.assume(bound != account);
        IAddressRegistryV1 registry = deployRegistry();

        vm.warp(first);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        registry.register(name, bound);
        assertEq(resolveAddress(name), bound);

        // The moment follows the address, so a caller reading both is told the
        // age of the address it was just given, never the age of one it was not.
        vm.warp(second);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        registry.register(name, account);
        (address resolved, uint256 registeredAt) = LibAddressRegistry.resolve(name);
        assertEq(resolved, account);
        assertEq(registeredAt, second);
    }

    /// An unbound name reverts. The registry, not this library, is what refuses
    /// to answer with the zero address, so the revert arrives unmodified.
    function testResolveUnregistered(bytes32 name) external {
        deployRegistry();

        vm.expectRevert(abi.encodeWithSelector(IAddressRegistryV1.NameNotRegistered.selector, name));
        this.externalResolve(name);
    }

    /// A chain with no registry deployed reverts on the code hash rather than
    /// calling into an empty account, which would otherwise succeed silently
    /// and return nothing.
    ///
    /// Zero is what the address hashes to only while the account does not
    /// exist at all, which is what a never-touched address is.
    /// `testResolveNoRegistryFundedAccount` is the other codeless value.
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

    /// A codeless registry address that EXISTS hashes to the empty string, not
    /// to zero, and anyone can bring it into existence on a chain without the
    /// registry by sending it a single wei. The guard fires either way, so what
    /// this pins is the value a caller reading `actualCodeHash` off the revert
    /// is handed.
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
    /// designator — occupies the address reverts on the code hash, so a name is
    /// never resolved by code the caller did not compile against.
    ///
    /// The designator family is excluded here and covered by
    /// `testResolveDelegatedCode` instead. `LibAccountCode` is what says why:
    /// it is the other KIND of account code, not another value of this one, and
    /// the arbitrary-`bytes` domain this used to fuzz is not the domain of
    /// things an account can hold.
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
    /// reverts on the code hash too. This is the other way an address gets
    /// occupied, and the more dangerous one: the account carries only 23 bytes
    /// of designator while executing whatever the delegate holds, so an address
    /// that looks nothing like a registry can answer `get` however it likes.
    ///
    /// The code hash is what refuses it, without knowing anything about 7702:
    /// the account hashes its designator, never the delegate's code, so a
    /// delegation can never present the pinned registry's hash.
    ///
    /// A delegation to the zero address is the CLEARING form — it leaves the
    /// account with no code at all, which is `testResolveNoRegistry`, not this.
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

    /// External wrapper for `resolveSafe` so that `vm.expectRevert` works at the
    /// correct call depth.
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

        vm.warp(block.timestamp + uint256(minAge) + uint256(extra));
        assertEq(LibAddressRegistry.resolveSafe(name, minAge), account);
    }

    /// A binding exactly `minAge` old passes. The requirement is that it has
    /// stood for AT LEAST that long, so the boundary is inclusive — an exclusive
    /// one would refuse a binding that has met the caller's own condition.
    function testResolveSafeExactlyMinAge(bytes32 name, address account, uint64 minAge) external {
        vm.assume(account != address(0));
        vm.assume(minAge > 0);
        IAddressRegistryV1 registry = deployRegistry();

        vm.prank(ADDRESS_REGISTRY_ROOT);
        registry.register(name, account);

        vm.warp(block.timestamp + uint256(minAge));
        assertEq(LibAddressRegistry.resolveSafe(name, minAge), account);
    }

    /// A binding younger than the minimum is refused, and the revert carries the
    /// age it had against the age it needed.
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

    /// A binding made in the block being read is refused by any nonzero
    /// minimum. This is the case the function exists for: a rebind landing
    /// immediately before the resolve.
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
    /// that would pass any real threshold. Zero is satisfied by every binding,
    /// so honouring it would make this `resolve` under a name that promises a
    /// check — the one call shape that looks guarded while guarding nothing.
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
    /// with a zero minimum reports the zero rather than the missing binding. The
    /// call is wrong before the registry could have an opinion, and saying
    /// `NameNotRegistered` would send the caller looking at the wrong thing.
    function testResolveSafeZeroMinAgeBeatsUnregistered(bytes32 name) external {
        deployRegistry();

        vm.expectRevert(abi.encodeWithSelector(LibAddressRegistry.ZeroMinAge.selector, name));
        this.externalResolveSafe(name, 0);
    }

    /// And before the code-hash guard, so a zero minimum is reported even on a
    /// chain with no registry deployed. This pins the order of the two
    /// refusals rather than leaving it to whichever happens to run first.
    function testResolveSafeZeroMinAgeBeatsMissingRegistry(bytes32 name) external {
        assertEq(LibAddressRegistryDeploy.ADDRESS_REGISTRY_DEPLOYED_ADDRESS.code.length, 0);

        vm.expectRevert(abi.encodeWithSelector(LibAddressRegistry.ZeroMinAge.selector, name));
        this.externalResolveSafe(name, 0);
    }

    /// A re-bind makes the name fresh again, so a binding that passed before the
    /// rotation is refused after it. Without this the check would be about the
    /// age of the NAME rather than of the address it currently answers with.
    function testResolveSafeRebindResetsAge(bytes32 name, address boundTo, address account, uint64 minAge, uint64 aged)
        external
    {
        vm.assume(boundTo != address(0));
        vm.assume(account != address(0));
        vm.assume(minAge > 0);
        aged = uint64(bound(aged, minAge, type(uint64).max));
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

    /// A binding stamped in the future has no age at all rather than reverting
    /// on the underflow of `block.timestamp - registeredAt`, so it is refused by
    /// the freshness check like any other too-fresh binding. A clock that moved
    /// backwards since the bind is not a state to hand a caller an address out
    /// of.
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

    /// A future stamp is refused however large the caller's minimum, so it is
    /// not a threshold that happens to be unmet — it is a chain whose clock
    /// cannot be used to age anything.
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

    /// A binding stamped at exactly the clock is NOT in the future — it is a
    /// binding made in the block being read, which is the too-fresh case. This
    /// is the boundary between the two errors, and reporting the wrong one here
    /// would tell a caller its chain was broken when it only had to wait.
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
    /// have an opinion — so a name nobody bound is never reported as merely too
    /// fresh, which would read as "wait and try again".
    function testResolveSafeUnregistered(bytes32 name, uint256 minAge) external {
        vm.assume(minAge > 0);
        deployRegistry();

        vm.expectRevert(abi.encodeWithSelector(IAddressRegistryV1.NameNotRegistered.selector, name));
        this.externalResolveSafe(name, minAge);
    }

    /// The code-hash guard runs first here too, so a chain where something else
    /// occupies the registry's address cannot be talked into answering a
    /// freshness-checked read.
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

    /// The Zoltu deploy really does land the registry on its pinned address
    /// with its pinned code hash. Every other test here depends on that, and a
    /// pin that had gone stale would otherwise show up as an unrelated
    /// code-hash revert in all of them.
    function testDeployMatchesPins() external {
        deployRegistry();

        assertEq(
            LibAddressRegistryDeploy.ADDRESS_REGISTRY_DEPLOYED_ADDRESS.codehash,
            LibAddressRegistryDeploy.ADDRESS_REGISTRY_DEPLOYED_CODEHASH
        );
    }
}
