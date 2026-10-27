// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibConfigRegistry} from "../../../src/lib/LibConfigRegistry.sol";
import {LibConfigRegistryDeploy} from "../../../src/lib/LibConfigRegistryDeploy.sol";
import {IConfigRegistryV4} from "../../../src/interface/IConfigRegistryV4.sol";
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

    /// The value type every address binding here is made under, as
    /// `MockSafeResolvedOwner` expects it.
    bytes32 internal constant ADDRESS_TYPE_HASH = keccak256("address");

    /// Deploys `ConfigRegistry` through the Zoltu factory, as a release deploy
    /// does.
    /// @return The deployed registry.
    function deployRegistry() internal returns (IConfigRegistryV4) {
        LibConfigRegistryFork.ensureDeployed(vm);
        return IConfigRegistryV4(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS);
    }

    /// Binds `name` under `authority` as an `address`, sent by `authority`.
    function bindAddress(IConfigRegistryV4 registry, address authority, string memory name, bytes memory value)
        internal
    {
        vm.prank(authority);
        registry.registerV4(authority, name, "address", value);
    }

    /// External wrapper for `resolve`, for `vm.expectRevert`'s call depth.
    /// @param nameHash The name hash to resolve.
    /// @return The value bound to `nameHash`.
    function externalResolve(bytes32 nameHash) external view returns (bytes memory) {
        (bytes memory value,) = LibConfigRegistry.resolve(AUTHORITY, nameHash, ADDRESS_TYPE_HASH);
        return value;
    }

    /// External wrapper for `resolve` expecting any value type, for
    /// `vm.expectRevert`'s call depth.
    /// @param nameHash The name hash to resolve.
    /// @param valueTypeHash The value type hash the binding must carry.
    /// @return The value bound to `nameHash`.
    function externalResolveTyped(bytes32 nameHash, bytes32 valueTypeHash) external view returns (bytes memory) {
        (bytes memory value,) = LibConfigRegistry.resolve(AUTHORITY, nameHash, valueTypeHash);
        return value;
    }

    /// The value half of `resolve`, decoded as the address binding every test
    /// here makes.
    /// @param nameHash The name hash to resolve.
    /// @return The address bound to `nameHash`.
    function resolveAddress(bytes32 nameHash) internal view returns (address) {
        (bytes memory value,) = LibConfigRegistry.resolve(AUTHORITY, nameHash, ADDRESS_TYPE_HASH);
        return abi.decode(value, (address));
    }

    /// `resolve` hands back the bound bytes verbatim, whatever they encode and
    /// whatever type they are bound as, whether or not they are valid ABI for
    /// it: decoding is the caller's and the library neither checks nor
    /// reshapes the value.
    function testResolveReturnsValueVerbatim(
        string memory name,
        string memory valueType,
        bytes memory value,
        uint96 time
    ) external {
        vm.assume(bytes(name).length > 0);
        vm.assume(bytes(valueType).length > 0);
        vm.assume(value.length > 0);
        IConfigRegistryV4 registry = deployRegistry();
        bytes32 nameHash = keccak256(bytes(name));
        bytes32 valueTypeHash = keccak256(bytes(valueType));

        time = uint96(bound(time, 1, type(uint96).max));
        vm.warp(time);
        vm.prank(AUTHORITY);
        registry.registerV4(AUTHORITY, name, valueType, value);

        (bytes memory resolved, uint256 registeredAt) = LibConfigRegistry.resolve(AUTHORITY, nameHash, valueTypeHash);
        assertEq(resolved, value);
        assertEq(registeredAt, time);
        vm.warp(uint256(time) + 2);
        assertEq(LibConfigRegistry.resolveSafe(AUTHORITY, nameHash, valueTypeHash, 1), value);
    }

    /// A binding of any type other than the one asked for is refused by
    /// `resolve`, naming the authority, the name hash, the type hash asked for
    /// and the one bound.
    function testResolveRefusesUnexpectedValueType(
        string memory name,
        string memory valueType,
        bytes32 expectedValueTypeHash,
        bytes memory value
    ) external {
        vm.assume(bytes(name).length > 0);
        vm.assume(bytes(valueType).length > 0);
        vm.assume(value.length > 0);
        bytes32 nameHash = keccak256(bytes(name));
        bytes32 valueTypeHash = keccak256(bytes(valueType));
        vm.assume(valueTypeHash != expectedValueTypeHash);
        IConfigRegistryV4 registry = deployRegistry();

        vm.prank(AUTHORITY);
        registry.registerV4(AUTHORITY, name, valueType, value);

        vm.expectRevert(
            abi.encodeWithSelector(
                LibConfigRegistry.UnexpectedValueType.selector,
                AUTHORITY,
                nameHash,
                expectedValueTypeHash,
                valueTypeHash
            )
        );
        this.externalResolveTyped(nameHash, expectedValueTypeHash);
    }

    /// The same bytes bound as a different type are refused: the type is
    /// checked, not inferred from the value. `abi.encode(account)` is equally
    /// valid ABI for `uint256` and for `address`.
    function testResolveRefusesSameBytesUnderOtherType(string memory name, address account) external {
        vm.assume(bytes(name).length > 0);
        bytes32 nameHash = keccak256(bytes(name));
        IConfigRegistryV4 registry = deployRegistry();

        vm.prank(AUTHORITY);
        registry.registerV4(AUTHORITY, name, "uint256", abi.encode(account));

        vm.expectRevert(
            abi.encodeWithSelector(
                LibConfigRegistry.UnexpectedValueType.selector,
                AUTHORITY,
                nameHash,
                ADDRESS_TYPE_HASH,
                keccak256("uint256")
            )
        );
        this.externalResolve(nameHash);
    }

    /// A re-bind under another type moves the type `resolve` checks: the old
    /// type is refused afterwards and the new one accepted.
    function testResolveFollowsRebindToOtherType(string memory name, address account, uint256 amount) external {
        vm.assume(bytes(name).length > 0);
        bytes32 nameHash = keccak256(bytes(name));
        IConfigRegistryV4 registry = deployRegistry();

        bindAddress(registry, AUTHORITY, name, abi.encode(account));
        assertEq(resolveAddress(nameHash), account);

        vm.warp(block.timestamp + 1);
        vm.prank(AUTHORITY);
        registry.registerV4(AUTHORITY, name, "uint256", abi.encode(amount));

        (bytes memory resolved,) = LibConfigRegistry.resolve(AUTHORITY, nameHash, keccak256("uint256"));
        assertEq(resolved, abi.encode(amount));
        vm.expectRevert(
            abi.encodeWithSelector(
                LibConfigRegistry.UnexpectedValueType.selector,
                AUTHORITY,
                nameHash,
                ADDRESS_TYPE_HASH,
                keccak256("uint256")
            )
        );
        this.externalResolve(nameHash);
    }

    /// A consumer that decodes a binding of the wrong shape reverts in its
    /// constructor rather than coming into existence holding a misread value:
    /// a packed 20-byte address is too short for `abi.decode(value, (address))`.
    function testConsumerRefusesWrongShape(string memory name, address account) external {
        vm.assume(bytes(name).length > 0);
        IConfigRegistryV4 registry = deployRegistry();
        bindAddress(registry, AUTHORITY, name, abi.encodePacked(account));
        vm.warp(block.timestamp + 2);

        // Solidity reverts a failed `abi.decode` with no data.
        vm.expectRevert(bytes(""));
        new MockSafeResolvedOwner(AUTHORITY, keccak256(bytes(name)), 1);
    }

    /// A consumer refuses, in its constructor, a binding of any type but
    /// `address`, even one whose bytes would decode as an address and that is
    /// old enough.
    function testConsumerRefusesNonAddressBinding(string memory name, string memory valueType, address account)
        external
    {
        vm.assume(bytes(name).length > 0);
        vm.assume(bytes(valueType).length > 0);
        bytes32 valueTypeHash = keccak256(bytes(valueType));
        vm.assume(valueTypeHash != ADDRESS_TYPE_HASH);
        bytes32 nameHash = keccak256(bytes(name));
        IConfigRegistryV4 registry = deployRegistry();

        vm.prank(AUTHORITY);
        registry.registerV4(AUTHORITY, name, valueType, abi.encode(account));
        vm.warp(block.timestamp + 2);

        vm.expectRevert(
            abi.encodeWithSelector(
                LibConfigRegistry.UnexpectedValueType.selector, AUTHORITY, nameHash, ADDRESS_TYPE_HASH, valueTypeHash
            )
        );
        new MockSafeResolvedOwner(AUTHORITY, nameHash, 1);
    }

    /// A bound name resolves to the address it is bound to, and to the moment
    /// that address was bound.
    function testResolveRegistered(string memory name, address account, uint96 time) external {
        vm.assume(bytes(name).length > 0);
        IConfigRegistryV4 registry = deployRegistry();
        bytes32 nameHash = keccak256(bytes(name));

        time = uint96(bound(time, 1, type(uint96).max));
        vm.warp(time);
        bindAddress(registry, AUTHORITY, name, abi.encode(account));

        (bytes memory resolved, uint256 registeredAt) =
            LibConfigRegistry.resolve(AUTHORITY, nameHash, ADDRESS_TYPE_HASH);
        assertEq(resolved, abi.encode(account));
        assertEq(registeredAt, time);
    }

    /// `resolve` answers with the current binding, not the first one, and the
    /// moment follows the address.
    function testResolveFollowsRebinding(
        string memory name,
        address bound,
        address account,
        uint96 first,
        uint96 second
    ) external {
        vm.assume(bytes(name).length > 0);
        vm.assume(bound != account);
        // `vm.assume` rather than `bound` because this test's `bound` parameter
        // shadows forge-std's helper of that name.
        vm.assume(first > 0);
        vm.assume(second > first);
        IConfigRegistryV4 registry = deployRegistry();
        bytes32 nameHash = keccak256(bytes(name));

        vm.warp(first);
        bindAddress(registry, AUTHORITY, name, abi.encode(bound));
        assertEq(resolveAddress(nameHash), bound);

        vm.warp(second);
        bindAddress(registry, AUTHORITY, name, abi.encode(account));
        (bytes memory resolved, uint256 registeredAt) =
            LibConfigRegistry.resolve(AUTHORITY, nameHash, ADDRESS_TYPE_HASH);
        assertEq(resolved, abi.encode(account));
        assertEq(registeredAt, second);
    }

    /// An unbound name reverts, with the registry's own error unmodified.
    function testResolveUnregistered(bytes32 nameHash) external {
        deployRegistry();

        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV4.NameNotRegistered.selector, AUTHORITY, nameHash));
        this.externalResolve(nameHash);
    }

    /// External wrapper for `resolve` under any authority, for
    /// `vm.expectRevert`'s call depth.
    /// @param authority The authority to resolve under.
    /// @param nameHash The name hash to resolve.
    /// @return The value `authority` bound `nameHash` to.
    function externalResolveUnder(address authority, bytes32 nameHash) external view returns (bytes memory) {
        (bytes memory value,) = LibConfigRegistry.resolve(authority, nameHash, ADDRESS_TYPE_HASH);
        return value;
    }

    /// `resolve` reads the authority it is given and no other: two authorities
    /// binding one name each resolve to their own value and moment, and a third
    /// that bound nothing reverts naming itself.
    function testResolveReadsOnlyTheNamedAuthority(
        address other,
        address third,
        string memory name,
        address accountA,
        address accountB
    ) external {
        vm.assume(bytes(name).length > 0);
        vm.assume(other != AUTHORITY);
        vm.assume(third != AUTHORITY && third != other);
        IConfigRegistryV4 registry = deployRegistry();
        bytes32 nameHash = keccak256(bytes(name));

        vm.warp(10);
        bindAddress(registry, AUTHORITY, name, abi.encode(accountA));
        vm.warp(20);
        bindAddress(registry, other, name, abi.encode(accountB));

        (bytes memory valueA, uint256 momentA) = LibConfigRegistry.resolve(AUTHORITY, nameHash, ADDRESS_TYPE_HASH);
        (bytes memory valueB, uint256 momentB) = LibConfigRegistry.resolve(other, nameHash, ADDRESS_TYPE_HASH);
        assertEq(valueA, abi.encode(accountA));
        assertEq(momentA, 10);
        assertEq(valueB, abi.encode(accountB));
        assertEq(momentB, 20);

        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV4.NameNotRegistered.selector, third, nameHash));
        this.externalResolveUnder(third, nameHash);
    }

    /// `resolveSafe` ages the named authority's binding alone: another
    /// authority binding the same name a moment ago neither makes it too
    /// fresh nor lends it age.
    function testResolveSafeAgesOnlyTheNamedAuthority(address other, string memory name, address account) external {
        vm.assume(bytes(name).length > 0);
        vm.assume(other != AUTHORITY);
        IConfigRegistryV4 registry = deployRegistry();
        bytes32 nameHash = keccak256(bytes(name));

        vm.warp(100);
        bindAddress(registry, AUTHORITY, name, abi.encode(account));
        vm.warp(200);
        bindAddress(registry, other, name, abi.encode(address(0xdead)));
        vm.warp(201);

        assertEq(LibConfigRegistry.resolveSafe(AUTHORITY, nameHash, ADDRESS_TYPE_HASH, 100), abi.encode(account));
        vm.expectRevert(abi.encodeWithSelector(LibConfigRegistry.BindingTooFresh.selector, other, nameHash, 1, 100));
        this.externalResolveSafeUnder(other, nameHash, 100);
    }

    /// External wrapper for `resolveSafe` under any authority, for
    /// `vm.expectRevert`'s call depth.
    /// @param authority The authority to resolve under.
    /// @param nameHash The name hash to resolve.
    /// @param minAge The binding must have stood for longer than this.
    /// @return The value `authority` bound `nameHash` to.
    function externalResolveSafeUnder(address authority, bytes32 nameHash, uint256 minAge)
        external
        view
        returns (bytes memory)
    {
        return LibConfigRegistry.resolveSafe(authority, nameHash, ADDRESS_TYPE_HASH, minAge);
    }

    /// A chain with no registry deployed reverts on the code hash, with an
    /// actual hash of zero: a never-touched address does not exist at all.
    function testResolveNoRegistry(bytes32 nameHash) external {
        assertEq(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS.code.length, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                LibConfigRegistry.UnexpectedConfigRegistryCodeHash.selector,
                LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_CODEHASH,
                bytes32(0)
            )
        );
        this.externalResolve(nameHash);
    }

    /// A codeless registry address that EXISTS — funded with a single wei —
    /// hashes to the empty string, not to zero, and the guard still fires.
    function testResolveNoRegistryFundedAccount(bytes32 nameHash, uint256 balance) external {
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
        this.externalResolve(nameHash);
    }

    /// A chain where ORDINARY code — anything that is not a delegation
    /// designator — occupies the address reverts on the code hash.
    function testResolveWrongCode(bytes32 nameHash, bytes memory code) external {
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
        this.externalResolve(nameHash);
    }

    /// A chain where an EOA has DELEGATED the registry address under EIP-7702
    /// reverts on the code hash too: the account hashes its 23-byte designator,
    /// never the delegate's code, so it can never present the pinned hash.
    /// @param nameHash The name hash a caller would resolve.
    /// @param delegate The account the registry address is delegated to.
    function testResolveDelegatedCode(bytes32 nameHash, address delegate) external {
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
        this.externalResolve(nameHash);
    }

    /// External wrapper for `resolveSafe`, for `vm.expectRevert`'s call depth.
    /// @param nameHash The name hash to resolve.
    /// @param minAge The binding must have stood for longer than this.
    /// @return The ABI-encoded value bound to `nameHash`.
    function externalResolveSafe(bytes32 nameHash, uint256 minAge) external view returns (bytes memory) {
        return LibConfigRegistry.resolveSafe(AUTHORITY, nameHash, ADDRESS_TYPE_HASH, minAge);
    }

    /// External wrapper for `resolveSafe` expecting any value type, for
    /// `vm.expectRevert`'s call depth.
    /// @param nameHash The name hash to resolve.
    /// @param valueTypeHash The value type hash the binding must carry.
    /// @param minAge The binding must have stood for longer than this.
    /// @return The ABI-encoded value bound to `nameHash`.
    function externalResolveSafeTyped(bytes32 nameHash, bytes32 valueTypeHash, uint256 minAge)
        external
        view
        returns (bytes memory)
    {
        return LibConfigRegistry.resolveSafe(AUTHORITY, nameHash, valueTypeHash, minAge);
    }

    /// `resolveSafe` refuses a binding of another type even when it is old
    /// enough.
    function testResolveSafeRefusesUnexpectedValueType(
        string memory name,
        string memory valueType,
        bytes32 expectedValueTypeHash,
        bytes memory value,
        uint64 minAge
    ) external {
        vm.assume(bytes(name).length > 0);
        vm.assume(bytes(valueType).length > 0);
        vm.assume(value.length > 0);
        vm.assume(minAge > 0);
        bytes32 nameHash = keccak256(bytes(name));
        bytes32 valueTypeHash = keccak256(bytes(valueType));
        vm.assume(valueTypeHash != expectedValueTypeHash);
        IConfigRegistryV4 registry = deployRegistry();

        vm.prank(AUTHORITY);
        registry.registerV4(AUTHORITY, name, valueType, value);
        vm.warp(block.timestamp + uint256(minAge) + 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                LibConfigRegistry.UnexpectedValueType.selector,
                AUTHORITY,
                nameHash,
                expectedValueTypeHash,
                valueTypeHash
            )
        );
        this.externalResolveSafeTyped(nameHash, expectedValueTypeHash, minAge);
    }

    /// A type mismatch is reported before the age: a binding of the wrong type
    /// made in this very block is refused for its type, not its freshness.
    function testResolveSafeUnexpectedValueTypeBeatsTooFresh(string memory name, address account, uint64 minAge)
        external
    {
        vm.assume(bytes(name).length > 0);
        vm.assume(minAge > 0);
        bytes32 nameHash = keccak256(bytes(name));
        IConfigRegistryV4 registry = deployRegistry();

        vm.prank(AUTHORITY);
        registry.registerV4(AUTHORITY, name, "uint256", abi.encode(account));

        vm.expectRevert(
            abi.encodeWithSelector(
                LibConfigRegistry.UnexpectedValueType.selector,
                AUTHORITY,
                nameHash,
                ADDRESS_TYPE_HASH,
                keccak256("uint256")
            )
        );
        this.externalResolveSafe(nameHash, minAge);
    }

    /// A type mismatch is reported before a future stamp too.
    function testResolveSafeUnexpectedValueTypeBeatsStampedInFuture(
        string memory name,
        address account,
        uint64 ahead,
        uint64 minAge
    ) external {
        vm.assume(bytes(name).length > 0);
        vm.assume(ahead > 0);
        vm.assume(minAge > 0);
        bytes32 nameHash = keccak256(bytes(name));
        IConfigRegistryV4 registry = deployRegistry();

        vm.warp(uint256(ahead) + 1);
        vm.prank(AUTHORITY);
        registry.registerV4(AUTHORITY, name, "uint256", abi.encode(account));
        vm.warp(1);

        vm.expectRevert(
            abi.encodeWithSelector(
                LibConfigRegistry.UnexpectedValueType.selector,
                AUTHORITY,
                nameHash,
                ADDRESS_TYPE_HASH,
                keccak256("uint256")
            )
        );
        this.externalResolveSafe(nameHash, minAge);
    }

    /// A zero minimum is still reported first, ahead of a type mismatch.
    function testResolveSafeZeroMinAgeBeatsUnexpectedValueType(string memory name, address account) external {
        vm.assume(bytes(name).length > 0);
        bytes32 nameHash = keccak256(bytes(name));
        IConfigRegistryV4 registry = deployRegistry();

        vm.prank(AUTHORITY);
        registry.registerV4(AUTHORITY, name, "uint256", abi.encode(account));
        vm.warp(block.timestamp + 2);

        vm.expectRevert(abi.encodeWithSelector(LibConfigRegistry.ZeroMinAge.selector, AUTHORITY, nameHash));
        this.externalResolveSafe(nameHash, 0);
    }

    /// A binding that has stood longer than the caller's minimum resolves to its
    /// address.
    function testResolveSafeOldEnough(string memory name, address account, uint64 minAge, uint64 extra) external {
        vm.assume(bytes(name).length > 0);
        vm.assume(minAge > 0);
        IConfigRegistryV4 registry = deployRegistry();
        bytes32 nameHash = keccak256(bytes(name));

        bindAddress(registry, AUTHORITY, name, abi.encode(account));

        extra = uint64(bound(extra, 1, type(uint64).max));
        vm.warp(vm.getBlockTimestamp() + uint256(minAge) + uint256(extra));
        assertEq(LibConfigRegistry.resolveSafe(AUTHORITY, nameHash, ADDRESS_TYPE_HASH, minAge), abi.encode(account));
    }

    /// A binding exactly `minAge` old is REFUSED: the binding must have stood
    /// for strictly longer.
    function testResolveSafeRefusesExactlyMinAge(string memory name, address account, uint64 minAge) external {
        vm.assume(bytes(name).length > 0);
        vm.assume(minAge > 0);
        IConfigRegistryV4 registry = deployRegistry();
        bytes32 nameHash = keccak256(bytes(name));

        bindAddress(registry, AUTHORITY, name, abi.encode(account));

        vm.warp(block.timestamp + uint256(minAge));
        vm.expectRevert(
            abi.encodeWithSelector(
                LibConfigRegistry.BindingTooFresh.selector, AUTHORITY, nameHash, uint256(minAge), uint256(minAge)
            )
        );
        this.externalResolveSafe(nameHash, minAge);
    }

    /// One second past `minAge` is accepted.
    function testResolveSafeAcceptsOneSecondPastMinAge(string memory name, address account, uint64 minAge) external {
        vm.assume(bytes(name).length > 0);
        vm.assume(minAge > 0);
        IConfigRegistryV4 registry = deployRegistry();
        bytes32 nameHash = keccak256(bytes(name));

        bindAddress(registry, AUTHORITY, name, abi.encode(account));

        vm.warp(vm.getBlockTimestamp() + uint256(minAge) + 1);
        assertEq(LibConfigRegistry.resolveSafe(AUTHORITY, nameHash, ADDRESS_TYPE_HASH, minAge), abi.encode(account));
    }

    /// A binding younger than the minimum is refused, and the revert carries the
    /// age it had and the age it needed.
    function testResolveSafeTooFresh(string memory name, address account, uint64 age, uint64 minAge) external {
        vm.assume(bytes(name).length > 0);
        vm.assume(age < minAge);
        IConfigRegistryV4 registry = deployRegistry();
        bytes32 nameHash = keccak256(bytes(name));

        bindAddress(registry, AUTHORITY, name, abi.encode(account));

        vm.warp(block.timestamp + uint256(age));
        vm.expectRevert(
            abi.encodeWithSelector(LibConfigRegistry.BindingTooFresh.selector, AUTHORITY, nameHash, age, minAge)
        );
        this.externalResolveSafe(nameHash, minAge);
    }

    /// A binding made in the block being read is refused by any nonzero minimum.
    function testResolveSafeSameBlockRefused(string memory name, address account, uint64 minAge) external {
        vm.assume(bytes(name).length > 0);
        vm.assume(minAge > 0);
        IConfigRegistryV4 registry = deployRegistry();
        bytes32 nameHash = keccak256(bytes(name));

        bindAddress(registry, AUTHORITY, name, abi.encode(account));

        vm.expectRevert(
            abi.encodeWithSelector(LibConfigRegistry.BindingTooFresh.selector, AUTHORITY, nameHash, 0, minAge)
        );
        this.externalResolveSafe(nameHash, minAge);
    }

    /// A minimum of zero is refused rather than honoured, even for a binding
    /// that would pass any real threshold.
    function testResolveSafeZeroMinAgeRefused(string memory name, address account, uint64 aged) external {
        vm.assume(bytes(name).length > 0);
        IConfigRegistryV4 registry = deployRegistry();
        bytes32 nameHash = keccak256(bytes(name));

        bindAddress(registry, AUTHORITY, name, abi.encode(account));
        vm.warp(block.timestamp + uint256(aged));

        vm.expectRevert(abi.encodeWithSelector(LibConfigRegistry.ZeroMinAge.selector, AUTHORITY, nameHash));
        this.externalResolveSafe(nameHash, 0);
    }

    /// Zero is refused before the registry is read at all, so an unbound name
    /// with a zero minimum reports the zero rather than the missing binding.
    function testResolveSafeZeroMinAgeBeatsUnregistered(bytes32 nameHash) external {
        deployRegistry();

        vm.expectRevert(abi.encodeWithSelector(LibConfigRegistry.ZeroMinAge.selector, AUTHORITY, nameHash));
        this.externalResolveSafe(nameHash, 0);
    }

    /// And before the code-hash guard, so a zero minimum is reported even on a
    /// chain with no registry deployed.
    function testResolveSafeZeroMinAgeBeatsMissingRegistry(bytes32 nameHash) external {
        assertEq(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS.code.length, 0);

        vm.expectRevert(abi.encodeWithSelector(LibConfigRegistry.ZeroMinAge.selector, AUTHORITY, nameHash));
        this.externalResolveSafe(nameHash, 0);
    }

    /// A re-bind makes the name fresh again, so a binding that passed before the
    /// rotation is refused after it.
    function testResolveSafeRebindResetsAge(
        string memory name,
        address boundTo,
        address account,
        uint64 minAge,
        uint64 aged
    ) external {
        vm.assume(bytes(name).length > 0);
        vm.assume(minAge > 0);
        vm.assume(minAge < type(uint64).max);
        aged = uint64(bound(aged, uint256(minAge) + 1, type(uint64).max));
        IConfigRegistryV4 registry = deployRegistry();
        bytes32 nameHash = keccak256(bytes(name));

        bindAddress(registry, AUTHORITY, name, abi.encode(boundTo));

        vm.warp(vm.getBlockTimestamp() + uint256(aged));
        assertEq(LibConfigRegistry.resolveSafe(AUTHORITY, nameHash, ADDRESS_TYPE_HASH, minAge), abi.encode(boundTo));

        bindAddress(registry, AUTHORITY, name, abi.encode(account));

        vm.expectRevert(
            abi.encodeWithSelector(LibConfigRegistry.BindingTooFresh.selector, AUTHORITY, nameHash, 0, minAge)
        );
        this.externalResolveSafe(nameHash, minAge);
    }

    /// A binding stamped in the future is refused with `BindingStampedInFuture`
    /// rather than reverting on an underflow of `block.timestamp -
    /// registeredAt`.
    function testResolveSafeStampedInFuture(string memory name, address account, uint64 ahead, uint64 minAge) external {
        vm.assume(bytes(name).length > 0);
        vm.assume(ahead > 0);
        vm.assume(minAge > 0);
        IConfigRegistryV4 registry = deployRegistry();
        bytes32 nameHash = keccak256(bytes(name));

        vm.warp(uint256(ahead) + 1);
        bindAddress(registry, AUTHORITY, name, abi.encode(account));

        // The clock goes backwards, leaving the binding stamped ahead of it.
        vm.warp(1);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibConfigRegistry.BindingStampedInFuture.selector, AUTHORITY, nameHash, uint256(ahead) + 1, uint256(1)
            )
        );
        this.externalResolveSafe(nameHash, minAge);
    }

    /// A future stamp is refused however large the caller's minimum.
    function testResolveSafeStampedInFutureRefusedAtAnyMinAge(string memory name, address account, uint64 ahead)
        external
    {
        vm.assume(bytes(name).length > 0);
        vm.assume(ahead > 0);
        IConfigRegistryV4 registry = deployRegistry();
        bytes32 nameHash = keccak256(bytes(name));

        vm.warp(uint256(ahead) + 1);
        bindAddress(registry, AUTHORITY, name, abi.encode(account));
        vm.warp(1);

        uint256[3] memory minAges = [uint256(1), uint256(type(uint64).max), type(uint256).max];
        for (uint256 i = 0; i < minAges.length; i++) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    LibConfigRegistry.BindingStampedInFuture.selector,
                    AUTHORITY,
                    nameHash,
                    uint256(ahead) + 1,
                    uint256(1)
                )
            );
            this.externalResolveSafe(nameHash, minAges[i]);
        }
    }

    /// A binding stamped at exactly the clock is NOT in the future — it is the
    /// too-fresh case, which is the boundary between the two errors.
    function testResolveSafeSameTimestampIsFreshNotFuture(string memory name, address account, uint64 minAge) external {
        vm.assume(bytes(name).length > 0);
        vm.assume(minAge > 0);
        IConfigRegistryV4 registry = deployRegistry();
        bytes32 nameHash = keccak256(bytes(name));

        bindAddress(registry, AUTHORITY, name, abi.encode(account));

        vm.expectRevert(
            abi.encodeWithSelector(LibConfigRegistry.BindingTooFresh.selector, AUTHORITY, nameHash, 0, minAge)
        );
        this.externalResolveSafe(nameHash, minAge);
    }

    /// An unbound name reverts from the registry, before the freshness check can
    /// have an opinion.
    function testResolveSafeUnregistered(bytes32 nameHash, uint256 minAge) external {
        vm.assume(minAge > 0);
        deployRegistry();

        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV4.NameNotRegistered.selector, AUTHORITY, nameHash));
        this.externalResolveSafe(nameHash, minAge);
    }

    /// The code-hash guard runs first here too.
    function testResolveSafeNoRegistry(bytes32 nameHash, uint256 minAge) external {
        vm.assume(minAge > 0);
        assertEq(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS.code.length, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                LibConfigRegistry.UnexpectedConfigRegistryCodeHash.selector,
                LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_CODEHASH,
                bytes32(0)
            )
        );
        this.externalResolveSafe(nameHash, minAge);
    }

    /// A consumer resolving once, in its constructor, under its own threshold
    /// comes into existence holding the vetted address.
    function testResolveSafeFromConstructor(string memory name, address account, uint64 minAge, uint64 extra) external {
        vm.assume(bytes(name).length > 0);
        vm.assume(minAge > 0);
        IConfigRegistryV4 registry = deployRegistry();

        bindAddress(registry, AUTHORITY, name, abi.encode(account));
        extra = uint64(bound(extra, 1, type(uint64).max));
        vm.warp(block.timestamp + uint256(minAge) + uint256(extra));

        MockSafeResolvedOwner consumer = new MockSafeResolvedOwner(AUTHORITY, keccak256(bytes(name)), minAge);
        assertEq(consumer.iOwner(), account);
    }

    /// A consumer's deploy reverts against a binding that has not stood long
    /// enough, so no contract is left holding an unvetted address.
    function testResolveSafeFromConstructorRefusesFreshBinding(
        string memory name,
        address account,
        uint64 minAge,
        uint64 age
    ) external {
        vm.assume(bytes(name).length > 0);
        vm.assume(age < minAge);
        IConfigRegistryV4 registry = deployRegistry();
        bytes32 nameHash = keccak256(bytes(name));

        bindAddress(registry, AUTHORITY, name, abi.encode(account));
        vm.warp(block.timestamp + uint256(age));

        vm.expectRevert(
            abi.encodeWithSelector(LibConfigRegistry.BindingTooFresh.selector, AUTHORITY, nameHash, age, minAge)
        );
        new MockSafeResolvedOwner(AUTHORITY, nameHash, minAge);
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
