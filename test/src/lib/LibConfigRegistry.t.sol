// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibConfigRegistry} from "../../../src/lib/LibConfigRegistry.sol";
import {LibConfigRegistryDeploy} from "../../../src/lib/LibConfigRegistryDeploy.sol";
import {IConfigRegistryV3} from "../../../src/interface/IConfigRegistryV3.sol";
import {DELEGATION_DESIGNATOR_LENGTH, LibAccountCode} from "../../lib/LibAccountCode.sol";
import {MockSafeResolvedOwner} from "../../concrete/MockSafeResolvedOwner.sol";
import {LibConfigRegistryFork} from "../../lib/LibConfigRegistryFork.sol";

/// @title LibConfigRegistryTest
/// Tests for `LibConfigRegistry`. The registry is not mocked: the real
/// `ConfigRegistry` is deployed through the Zoltu factory, which lands it at
/// the pinned address with the pinned code hash.
contract LibConfigRegistryTest is Test {
    /// The authority every test here binds and resolves under. Any account is
    /// one.
    address internal constant AUTHORITY = address(0xA11CE);

    /// Deploys `ConfigRegistry` through the Zoltu factory, as a release deploy
    /// does.
    /// @return The deployed registry.
    function deployRegistry() internal returns (IConfigRegistryV3) {
        LibConfigRegistryFork.ensureDeployed(vm);
        return IConfigRegistryV3(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS);
    }

    /// External wrapper for `resolve`, for `vm.expectRevert`'s call depth.
    /// @param name The name to resolve.
    /// @return The value bound to `name`.
    function externalResolve(bytes32 name) external view returns (bytes memory) {
        (bytes memory value,) = LibConfigRegistry.resolve(AUTHORITY, name);
        return value;
    }

    /// The value half of `resolve`, decoded as the address binding every test
    /// here makes.
    /// @param name The name to resolve.
    /// @return The address bound to `name`.
    function resolveAddress(bytes32 name) internal view returns (address) {
        (bytes memory value,) = LibConfigRegistry.resolve(AUTHORITY, name);
        return abi.decode(value, (address));
    }

    /// `resolve` hands back the bound bytes verbatim, whatever they encode and
    /// whether or not they are valid ABI for any type: decoding is the caller's
    /// and the library neither checks nor reshapes the value.
    function testResolveReturnsValueVerbatim(bytes32 name, bytes memory value, uint96 time) external {
        vm.assume(value.length > 0);
        IConfigRegistryV3 registry = deployRegistry();

        time = uint96(bound(time, 1, type(uint96).max));
        vm.warp(time);
        vm.prank(AUTHORITY);
        registry.registerV3(AUTHORITY, name, value);

        (bytes memory resolved, uint256 registeredAt) = LibConfigRegistry.resolve(AUTHORITY, name);
        assertEq(resolved, value);
        assertEq(registeredAt, time);
        vm.warp(uint256(time) + 2);
        assertEq(LibConfigRegistry.resolveSafe(AUTHORITY, name, 1), value);
    }

    /// A consumer that decodes a binding of the wrong shape reverts in its
    /// constructor rather than coming into existence holding a misread value:
    /// a packed 20-byte address is too short for `abi.decode(value, (address))`.
    function testConsumerRefusesWrongShape(bytes32 name, address account) external {
        IConfigRegistryV3 registry = deployRegistry();
        vm.prank(AUTHORITY);
        registry.registerV3(AUTHORITY, name, abi.encodePacked(account));
        vm.warp(block.timestamp + 2);

        // Solidity reverts a failed `abi.decode` with no data.
        vm.expectRevert(bytes(""));
        new MockSafeResolvedOwner(AUTHORITY, name, 1);
    }

    /// A bound name resolves to the address it is bound to, and to the moment
    /// that address was bound.
    function testResolveRegistered(bytes32 name, address account, uint96 time) external {
        IConfigRegistryV3 registry = deployRegistry();

        time = uint96(bound(time, 1, type(uint96).max));
        vm.warp(time);
        vm.prank(AUTHORITY);
        registry.registerV3(AUTHORITY, name, abi.encode(account));

        (bytes memory resolved, uint256 registeredAt) = LibConfigRegistry.resolve(AUTHORITY, name);
        assertEq(resolved, abi.encode(account));
        assertEq(registeredAt, time);
    }

    /// `resolve` answers with the current binding, not the first one, and the
    /// moment follows the address.
    function testResolveFollowsRebinding(bytes32 name, address bound, address account, uint96 first, uint96 second)
        external
    {
        vm.assume(bound != account);
        // `vm.assume` rather than `bound` because this test's `bound` parameter
        // shadows forge-std's helper of that name.
        vm.assume(first > 0);
        vm.assume(second > first);
        IConfigRegistryV3 registry = deployRegistry();

        vm.warp(first);
        vm.prank(AUTHORITY);
        registry.registerV3(AUTHORITY, name, abi.encode(bound));
        assertEq(resolveAddress(name), bound);

        vm.warp(second);
        vm.prank(AUTHORITY);
        registry.registerV3(AUTHORITY, name, abi.encode(account));
        (bytes memory resolved, uint256 registeredAt) = LibConfigRegistry.resolve(AUTHORITY, name);
        assertEq(resolved, abi.encode(account));
        assertEq(registeredAt, second);
    }

    /// An unbound name reverts, with the registry's own error unmodified.
    function testResolveUnregistered(bytes32 name) external {
        deployRegistry();

        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV3.NameNotRegistered.selector, AUTHORITY, name));
        this.externalResolve(name);
    }

    /// External wrapper for `resolve` under any authority, for
    /// `vm.expectRevert`'s call depth.
    /// @param authority The authority to resolve under.
    /// @param name The name to resolve.
    /// @return The value `authority` bound `name` to.
    function externalResolveUnder(address authority, bytes32 name) external view returns (bytes memory) {
        (bytes memory value,) = LibConfigRegistry.resolve(authority, name);
        return value;
    }

    /// `resolve` reads the authority it is given and no other: two authorities
    /// binding one name each resolve to their own value and moment, and a third
    /// that bound nothing reverts naming itself.
    function testResolveReadsOnlyTheNamedAuthority(
        address other,
        address third,
        bytes32 name,
        address accountA,
        address accountB
    ) external {
        vm.assume(other != AUTHORITY);
        vm.assume(third != AUTHORITY && third != other);
        IConfigRegistryV3 registry = deployRegistry();

        vm.warp(10);
        vm.prank(AUTHORITY);
        registry.registerV3(AUTHORITY, name, abi.encode(accountA));
        vm.warp(20);
        vm.prank(other);
        registry.registerV3(other, name, abi.encode(accountB));

        (bytes memory valueA, uint256 momentA) = LibConfigRegistry.resolve(AUTHORITY, name);
        (bytes memory valueB, uint256 momentB) = LibConfigRegistry.resolve(other, name);
        assertEq(valueA, abi.encode(accountA));
        assertEq(momentA, 10);
        assertEq(valueB, abi.encode(accountB));
        assertEq(momentB, 20);

        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV3.NameNotRegistered.selector, third, name));
        this.externalResolveUnder(third, name);
    }

    /// `resolveSafe` ages the named authority's binding alone: another
    /// authority binding the same name a moment ago neither makes it too
    /// fresh nor lends it age.
    function testResolveSafeAgesOnlyTheNamedAuthority(address other, bytes32 name, address account) external {
        vm.assume(other != AUTHORITY);
        IConfigRegistryV3 registry = deployRegistry();

        vm.warp(100);
        vm.prank(AUTHORITY);
        registry.registerV3(AUTHORITY, name, abi.encode(account));
        vm.warp(200);
        vm.prank(other);
        registry.registerV3(other, name, abi.encode(address(0xdead)));
        vm.warp(201);

        assertEq(LibConfigRegistry.resolveSafe(AUTHORITY, name, 100), abi.encode(account));
        vm.expectRevert(abi.encodeWithSelector(LibConfigRegistry.BindingTooFresh.selector, other, name, 1, 100));
        this.externalResolveSafeUnder(other, name, 100);
    }

    /// External wrapper for `resolveSafe` under any authority, for
    /// `vm.expectRevert`'s call depth.
    /// @param authority The authority to resolve under.
    /// @param name The name to resolve.
    /// @param minAge The binding must have stood for longer than this.
    /// @return The value `authority` bound `name` to.
    function externalResolveSafeUnder(address authority, bytes32 name, uint256 minAge)
        external
        view
        returns (bytes memory)
    {
        return LibConfigRegistry.resolveSafe(authority, name, minAge);
    }

    /// A chain with no registry deployed reverts on the code hash, with an
    /// actual hash of zero: a never-touched address does not exist at all.
    function testResolveNoRegistry(bytes32 name) external {
        assertEq(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS.code.length, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                LibConfigRegistry.UnexpectedConfigRegistryCodeHash.selector,
                LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_CODEHASH,
                bytes32(0)
            )
        );
        this.externalResolve(name);
    }

    /// A codeless registry address that EXISTS — funded with a single wei —
    /// hashes to the empty string, not to zero, and the guard still fires.
    function testResolveNoRegistryFundedAccount(bytes32 name, uint256 balance) external {
        balance = bound(balance, 1, type(uint128).max);
        vm.deal(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS, balance);

        assertEq(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS.code.length, 0);
        assertEq(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS.codehash, keccak256(""));

        vm.expectRevert(
            abi.encodeWithSelector(
                LibConfigRegistry.UnexpectedConfigRegistryCodeHash.selector,
                LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_CODEHASH,
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
        vm.assume(keccak256(code) != LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_CODEHASH);
        vm.etch(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS, code);

        vm.expectRevert(
            abi.encodeWithSelector(
                LibConfigRegistry.UnexpectedConfigRegistryCodeHash.selector,
                LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_CODEHASH,
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

        vm.etch(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS, designator);
        assertEq(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS.codehash, keccak256(designator));

        vm.expectRevert(
            abi.encodeWithSelector(
                LibConfigRegistry.UnexpectedConfigRegistryCodeHash.selector,
                LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_CODEHASH,
                keccak256(designator)
            )
        );
        this.externalResolve(name);
    }

    /// External wrapper for `resolveSafe`, for `vm.expectRevert`'s call depth.
    /// @param name The name to resolve.
    /// @param minAge The binding must have stood for longer than this.
    /// @return The ABI-encoded value bound to `name`.
    function externalResolveSafe(bytes32 name, uint256 minAge) external view returns (bytes memory) {
        return LibConfigRegistry.resolveSafe(AUTHORITY, name, minAge);
    }

    /// A binding that has stood longer than the caller's minimum resolves to its
    /// address.
    function testResolveSafeOldEnough(bytes32 name, address account, uint64 minAge, uint64 extra) external {
        vm.assume(minAge > 0);
        IConfigRegistryV3 registry = deployRegistry();

        vm.prank(AUTHORITY);
        registry.registerV3(AUTHORITY, name, abi.encode(account));

        extra = uint64(bound(extra, 1, type(uint64).max));
        vm.warp(vm.getBlockTimestamp() + uint256(minAge) + uint256(extra));
        assertEq(LibConfigRegistry.resolveSafe(AUTHORITY, name, minAge), abi.encode(account));
    }

    /// A binding exactly `minAge` old is REFUSED: the binding must have stood
    /// for strictly longer.
    function testResolveSafeRefusesExactlyMinAge(bytes32 name, address account, uint64 minAge) external {
        vm.assume(minAge > 0);
        IConfigRegistryV3 registry = deployRegistry();

        vm.prank(AUTHORITY);
        registry.registerV3(AUTHORITY, name, abi.encode(account));

        vm.warp(block.timestamp + uint256(minAge));
        vm.expectRevert(
            abi.encodeWithSelector(
                LibConfigRegistry.BindingTooFresh.selector, AUTHORITY, name, uint256(minAge), uint256(minAge)
            )
        );
        this.externalResolveSafe(name, minAge);
    }

    /// One second past `minAge` is accepted.
    function testResolveSafeAcceptsOneSecondPastMinAge(bytes32 name, address account, uint64 minAge) external {
        vm.assume(minAge > 0);
        IConfigRegistryV3 registry = deployRegistry();

        vm.prank(AUTHORITY);
        registry.registerV3(AUTHORITY, name, abi.encode(account));

        vm.warp(vm.getBlockTimestamp() + uint256(minAge) + 1);
        assertEq(LibConfigRegistry.resolveSafe(AUTHORITY, name, minAge), abi.encode(account));
    }

    /// A binding younger than the minimum is refused, and the revert carries the
    /// age it had and the age it needed.
    function testResolveSafeTooFresh(bytes32 name, address account, uint64 age, uint64 minAge) external {
        vm.assume(age < minAge);
        IConfigRegistryV3 registry = deployRegistry();

        vm.prank(AUTHORITY);
        registry.registerV3(AUTHORITY, name, abi.encode(account));

        vm.warp(block.timestamp + uint256(age));
        vm.expectRevert(
            abi.encodeWithSelector(LibConfigRegistry.BindingTooFresh.selector, AUTHORITY, name, age, minAge)
        );
        this.externalResolveSafe(name, minAge);
    }

    /// A binding made in the block being read is refused by any nonzero minimum.
    function testResolveSafeSameBlockRefused(bytes32 name, address account, uint64 minAge) external {
        vm.assume(minAge > 0);
        IConfigRegistryV3 registry = deployRegistry();

        vm.prank(AUTHORITY);
        registry.registerV3(AUTHORITY, name, abi.encode(account));

        vm.expectRevert(abi.encodeWithSelector(LibConfigRegistry.BindingTooFresh.selector, AUTHORITY, name, 0, minAge));
        this.externalResolveSafe(name, minAge);
    }

    /// A minimum of zero is refused rather than honoured, even for a binding
    /// that would pass any real threshold.
    function testResolveSafeZeroMinAgeRefused(bytes32 name, address account, uint64 aged) external {
        IConfigRegistryV3 registry = deployRegistry();

        vm.prank(AUTHORITY);
        registry.registerV3(AUTHORITY, name, abi.encode(account));
        vm.warp(block.timestamp + uint256(aged));

        vm.expectRevert(abi.encodeWithSelector(LibConfigRegistry.ZeroMinAge.selector, AUTHORITY, name));
        this.externalResolveSafe(name, 0);
    }

    /// Zero is refused before the registry is read at all, so an unbound name
    /// with a zero minimum reports the zero rather than the missing binding.
    function testResolveSafeZeroMinAgeBeatsUnregistered(bytes32 name) external {
        deployRegistry();

        vm.expectRevert(abi.encodeWithSelector(LibConfigRegistry.ZeroMinAge.selector, AUTHORITY, name));
        this.externalResolveSafe(name, 0);
    }

    /// And before the code-hash guard, so a zero minimum is reported even on a
    /// chain with no registry deployed.
    function testResolveSafeZeroMinAgeBeatsMissingRegistry(bytes32 name) external {
        assertEq(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS.code.length, 0);

        vm.expectRevert(abi.encodeWithSelector(LibConfigRegistry.ZeroMinAge.selector, AUTHORITY, name));
        this.externalResolveSafe(name, 0);
    }

    /// A re-bind makes the name fresh again, so a binding that passed before the
    /// rotation is refused after it.
    function testResolveSafeRebindResetsAge(bytes32 name, address boundTo, address account, uint64 minAge, uint64 aged)
        external
    {
        vm.assume(minAge > 0);
        vm.assume(minAge < type(uint64).max);
        aged = uint64(bound(aged, uint256(minAge) + 1, type(uint64).max));
        IConfigRegistryV3 registry = deployRegistry();

        vm.prank(AUTHORITY);
        registry.registerV3(AUTHORITY, name, abi.encode(boundTo));

        vm.warp(vm.getBlockTimestamp() + uint256(aged));
        assertEq(LibConfigRegistry.resolveSafe(AUTHORITY, name, minAge), abi.encode(boundTo));

        vm.prank(AUTHORITY);
        registry.registerV3(AUTHORITY, name, abi.encode(account));

        vm.expectRevert(abi.encodeWithSelector(LibConfigRegistry.BindingTooFresh.selector, AUTHORITY, name, 0, minAge));
        this.externalResolveSafe(name, minAge);
    }

    /// A binding stamped in the future is refused with `BindingStampedInFuture`
    /// rather than reverting on an underflow of `block.timestamp -
    /// registeredAt`.
    function testResolveSafeStampedInFuture(bytes32 name, address account, uint64 ahead, uint64 minAge) external {
        vm.assume(ahead > 0);
        vm.assume(minAge > 0);
        IConfigRegistryV3 registry = deployRegistry();

        vm.warp(uint256(ahead) + 1);
        vm.prank(AUTHORITY);
        registry.registerV3(AUTHORITY, name, abi.encode(account));

        // The clock goes backwards, leaving the binding stamped ahead of it.
        vm.warp(1);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibConfigRegistry.BindingStampedInFuture.selector, AUTHORITY, name, uint256(ahead) + 1, uint256(1)
            )
        );
        this.externalResolveSafe(name, minAge);
    }

    /// A future stamp is refused however large the caller's minimum.
    function testResolveSafeStampedInFutureRefusedAtAnyMinAge(bytes32 name, address account, uint64 ahead) external {
        vm.assume(ahead > 0);
        IConfigRegistryV3 registry = deployRegistry();

        vm.warp(uint256(ahead) + 1);
        vm.prank(AUTHORITY);
        registry.registerV3(AUTHORITY, name, abi.encode(account));
        vm.warp(1);

        uint256[3] memory minAges = [uint256(1), uint256(type(uint64).max), type(uint256).max];
        for (uint256 i = 0; i < minAges.length; i++) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    LibConfigRegistry.BindingStampedInFuture.selector, AUTHORITY, name, uint256(ahead) + 1, uint256(1)
                )
            );
            this.externalResolveSafe(name, minAges[i]);
        }
    }

    /// A binding stamped at exactly the clock is NOT in the future — it is the
    /// too-fresh case, which is the boundary between the two errors.
    function testResolveSafeSameTimestampIsFreshNotFuture(bytes32 name, address account, uint64 minAge) external {
        vm.assume(minAge > 0);
        IConfigRegistryV3 registry = deployRegistry();

        vm.prank(AUTHORITY);
        registry.registerV3(AUTHORITY, name, abi.encode(account));

        vm.expectRevert(abi.encodeWithSelector(LibConfigRegistry.BindingTooFresh.selector, AUTHORITY, name, 0, minAge));
        this.externalResolveSafe(name, minAge);
    }

    /// An unbound name reverts from the registry, before the freshness check can
    /// have an opinion.
    function testResolveSafeUnregistered(bytes32 name, uint256 minAge) external {
        vm.assume(minAge > 0);
        deployRegistry();

        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV3.NameNotRegistered.selector, AUTHORITY, name));
        this.externalResolveSafe(name, minAge);
    }

    /// The code-hash guard runs first here too.
    function testResolveSafeNoRegistry(bytes32 name, uint256 minAge) external {
        vm.assume(minAge > 0);
        assertEq(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS.code.length, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                LibConfigRegistry.UnexpectedConfigRegistryCodeHash.selector,
                LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_CODEHASH,
                bytes32(0)
            )
        );
        this.externalResolveSafe(name, minAge);
    }

    /// A consumer resolving once, in its constructor, under its own threshold
    /// comes into existence holding the vetted address.
    function testResolveSafeFromConstructor(bytes32 name, address account, uint64 minAge, uint64 extra) external {
        vm.assume(minAge > 0);
        IConfigRegistryV3 registry = deployRegistry();

        vm.prank(AUTHORITY);
        registry.registerV3(AUTHORITY, name, abi.encode(account));
        extra = uint64(bound(extra, 1, type(uint64).max));
        vm.warp(block.timestamp + uint256(minAge) + uint256(extra));

        MockSafeResolvedOwner consumer = new MockSafeResolvedOwner(AUTHORITY, name, minAge);
        assertEq(consumer.iOwner(), account);
    }

    /// A consumer's deploy reverts against a binding that has not stood long
    /// enough, so no contract is left holding an unvetted address.
    function testResolveSafeFromConstructorRefusesFreshBinding(bytes32 name, address account, uint64 minAge, uint64 age)
        external
    {
        vm.assume(age < minAge);
        IConfigRegistryV3 registry = deployRegistry();

        vm.prank(AUTHORITY);
        registry.registerV3(AUTHORITY, name, abi.encode(account));
        vm.warp(block.timestamp + uint256(age));

        vm.expectRevert(
            abi.encodeWithSelector(LibConfigRegistry.BindingTooFresh.selector, AUTHORITY, name, age, minAge)
        );
        new MockSafeResolvedOwner(AUTHORITY, name, minAge);
    }

    /// The Zoltu deploy really does land the registry on its pinned address
    /// with its pinned code hash.
    function testDeployMatchesPins() external {
        deployRegistry();

        assertEq(
            LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS.codehash,
            LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_CODEHASH
        );
    }
}
