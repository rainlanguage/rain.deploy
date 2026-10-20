// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";

import {ConfigRegistry} from "../../../src/concrete/ConfigRegistry.sol";
import {IConfigRegistryV1} from "../../../src/interface/IConfigRegistryV1.sol";
import {LibConfigRegistry} from "../../../src/lib/LibConfigRegistry.sol";
import {LibConfigRegistryDeploy} from "../../../src/lib/LibConfigRegistryDeploy.sol";
import {LibConfigRegistryRegister} from "../../../src/lib/LibConfigRegistryRegister.sol";
import {LibRainDeploy, SupportedNetwork} from "../../../src/lib/LibRainDeploy.sol";
import {MockRevertingRegistry} from "../../concrete/MockRevertingRegistry.sol";
import {LibConfigRegistryRead} from "../../lib/LibConfigRegistryRead.sol";

/// @title LibConfigRegistryRegisterTest
/// Every guard `LibConfigRegistryRegister` makes before a bind, and the bind
/// itself, on the local chain: the real `ConfigRegistry` deployed through the
/// Zoltu factory at the pinned address, and the chain id set to the network's.
/// Nothing here forks; `LibConfigRegistryRegisterOnForksTest` drives the fork
/// loops.
contract LibConfigRegistryRegisterTest is Test {
    /// The authority every run here binds under and reads under. Any account
    /// is one.
    address internal constant AUTHORITY = address(0xA11CE);

    /// The catalogue entry the local chain is dressed up as.
    /// @return Base's catalogue entry.
    function base() internal pure returns (SupportedNetwork memory) {
        string[] memory names = new string[](1);
        names[0] = LibRainDeploy.BASE;
        return LibRainDeploy.declaredNetworkConfigs(names)[0];
    }

    /// Deploys the real registry at its pinned address and sets the chain id to
    /// Base's.
    /// @return The registry.
    function deployRegistry() internal returns (IConfigRegistryV1) {
        vm.chainId(base().chainId);
        LibRainDeploy.etchZoltuFactory(vm);
        address registry = LibRainDeploy.deployZoltu(type(ConfigRegistry).creationCode);
        assertEq(registry, LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS);
        return IConfigRegistryV1(registry);
    }

    /// One-element string list.
    function list(string memory only) internal pure returns (string[] memory) {
        string[] memory networks = new string[](1);
        networks[0] = only;
        return networks;
    }

    /// Two-element string list.
    function list(string memory first, string memory second) internal pure returns (string[] memory) {
        string[] memory networks = new string[](2);
        networks[0] = first;
        networks[1] = second;
        return networks;
    }

    /// Three-element string list.
    function list(string memory first, string memory second, string memory third)
        internal
        pure
        returns (string[] memory)
    {
        string[] memory networks = new string[](3);
        networks[0] = first;
        networks[1] = second;
        networks[2] = third;
        return networks;
    }

    function externalNameHash(string memory name) external pure returns (bytes32) {
        return LibConfigRegistryRegister.nameHash(name);
    }

    function externalSelectNetworks(string[] memory selected, string[] memory declared)
        external
        pure
        returns (SupportedNetwork[] memory)
    {
        return LibConfigRegistryRegister.selectNetworks(selected, declared);
    }

    function externalCheckSender(address sender, address authority) external pure {
        LibConfigRegistryRegister.checkSender(sender, authority);
    }

    function externalCurrentBinding(bytes32 name) external view returns (bytes memory, uint256) {
        return LibConfigRegistryRegister.currentBinding(AUTHORITY, name);
    }

    function externalRegisterOnSelectedChain(
        SupportedNetwork memory network,
        address sender,
        bytes32 name,
        bytes memory value
    ) external returns (bool, string memory) {
        return LibConfigRegistryRegister.registerOnSelectedChain(vm, network, sender, name, value);
    }

    function externalRegisterOnNetworks(
        string[] memory selected,
        string[] memory declared,
        address sender,
        string memory name,
        bytes memory value
    ) external returns (uint256[] memory, string memory) {
        return LibConfigRegistryRegister.registerOnNetworks(vm, selected, declared, sender, AUTHORITY, name, value);
    }

    function externalCheckRegisteredOnForks(
        string[] memory selected,
        string[] memory declared,
        uint256[] memory forkIds,
        string memory name,
        bytes memory value
    ) external {
        LibConfigRegistryRegister.checkRegisteredOnForks(vm, selected, declared, forkIds, AUTHORITY, name, value);
    }

    function externalCheckRegisteredOnSelectedChain(SupportedNetwork memory network, bytes32 name, bytes memory value)
        external
        view
        returns (uint256)
    {
        return LibConfigRegistryRegister.checkRegisteredOnSelectedChain(vm, network, AUTHORITY, name, value);
    }

    function externalCheckRegisteredOnNetworks(
        string[] memory selected,
        string[] memory declared,
        string memory name,
        bytes memory value
    ) external {
        LibConfigRegistryRegister.checkRegisteredOnNetworks(vm, selected, declared, AUTHORITY, name, value);
    }

    /// The name is the `keccak256` of its string, the derivation consumers
    /// use: st0x resolves its token-owner Safe as
    /// `keccak256("st0x.token-owner-safe")`.
    function testNameHashIsTheConsumerDerivation() external pure {
        assertEq(LibConfigRegistryRegister.nameHash("st0x.token-owner-safe"), keccak256("st0x.token-owner-safe"));
        assertEq(LibConfigRegistryRegister.nameHash("a.b"), keccak256("a.b"));
        assertEq(LibConfigRegistryRegister.nameHash("z9.0-a"), keccak256("z9.0-a"));
        assertEq(LibConfigRegistryRegister.nameHash("az09.za-90"), keccak256("az09.za-90"));
    }

    /// Asserts `name` is refused as non-canonical.
    function assertNonCanonical(string memory name) internal {
        vm.expectRevert(abi.encodeWithSelector(LibConfigRegistryRegister.NonCanonicalName.selector, name));
        this.externalNameHash(name);
    }

    /// Every near miss of a canonical name is refused: empty, capitals, a
    /// leading digit (which is every `0x…` hash), a separator at either end or
    /// twice in a row, whitespace, the characters either side of each accepted
    /// range, and a name with no `.` after an `<org>`. Each case other than the
    /// unqualified ones holds a `.`, so it is refused for its own defect.
    function testNonCanonicalNamesAreRefused() external {
        assertNonCanonical("");
        assertNonCanonical("A.a");
        assertNonCanonical("st0x.Token-owner-safe");
        assertNonCanonical("1abc.a");
        assertNonCanonical("0x0b300013cd54a8f1ac40981f80faaa18b8cc1e4c0b300013cd54a8f1ac409810");
        assertNonCanonical(".a");
        assertNonCanonical("-a.a");
        assertNonCanonical("a.");
        assertNonCanonical("o.a-");
        assertNonCanonical("a..b");
        assertNonCanonical("a.-b");
        assertNonCanonical("o.a--b");
        assertNonCanonical(" a.a");
        assertNonCanonical("o.a ");
        assertNonCanonical("o.a\n");
        assertNonCanonical("o.a b");
        assertNonCanonical("o.a_b");
        assertNonCanonical("o.a/b");
        assertNonCanonical("o.a:b");
        assertNonCanonical("o.a`b");
        assertNonCanonical("o.a{b");
        assertNonCanonical("o.a@b");
        assertNonCanonical("o.a[b");
        assertNonCanonical("`a.a");
        assertNonCanonical("{a.a");
        assertNonCanonical(unicode"o.é");
        assertNonCanonical("a");
        assertNonCanonical("a-b");
        assertNonCanonical("token-owner-safe");
    }

    /// An empty selection is refused.
    function testSelectNoNetworks() external {
        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.NoNetworks.selector));
        this.externalSelectNetworks(new string[](0), LibRainDeploy.supportedNetworks());
    }

    /// A network outside the declaration is refused, even one the catalogue
    /// knows.
    function testSelectUndeclaredNetwork() external {
        vm.expectRevert(abi.encodeWithSelector(LibConfigRegistryRegister.NetworkNotDeclared.selector, "nowhere"));
        this.externalSelectNetworks(list("base", "nowhere"), LibRainDeploy.supportedNetworks());

        vm.expectRevert(abi.encodeWithSelector(LibConfigRegistryRegister.NetworkNotDeclared.selector, "base"));
        this.externalSelectNetworks(list("base"), list("arbitrum"));
    }

    /// A network selected twice is refused.
    function testSelectDuplicateNetwork() external {
        vm.expectRevert(abi.encodeWithSelector(LibConfigRegistryRegister.DuplicateNetwork.selector, "base"));
        this.externalSelectNetworks(list("base", "base"), LibRainDeploy.supportedNetworks());
    }

    /// The repeated network is named, not the first one selected.
    function testSelectDuplicateNetworkNamesTheRepeat() external {
        vm.expectRevert(abi.encodeWithSelector(LibConfigRegistryRegister.DuplicateNetwork.selector, "arbitrum"));
        this.externalSelectNetworks(list("base", "arbitrum", "arbitrum"), LibRainDeploy.supportedNetworks());
    }

    /// A selection answers with the catalogue entry of each selected network,
    /// in selection order.
    function testSelectSubsetInSelectionOrder() external pure {
        SupportedNetwork[] memory selected =
            LibConfigRegistryRegister.selectNetworks(list("base", "arbitrum"), LibRainDeploy.supportedNetworks());
        assertEq(selected.length, 2);
        assertEq(selected[0].name, "base");
        assertEq(selected[0].chainId, 8453);
        assertEq(selected[1].name, "arbitrum");
        assertEq(selected[1].chainId, 42161);
    }

    /// Every declared network is selectable at once.
    function testSelectEveryDeclaredNetwork() external pure {
        string[] memory declared = LibRainDeploy.supportedNetworks();
        assertEq(LibConfigRegistryRegister.selectNetworks(declared, declared).length, declared.length);
    }

    /// Any sender but the authority is refused, naming both.
    function testSenderNotAuthority(address sender, address authority) external {
        vm.assume(sender != authority);
        vm.expectRevert(
            abi.encodeWithSelector(LibConfigRegistryRegister.SenderNotAuthority.selector, sender, authority)
        );
        this.externalCheckSender(sender, authority);
    }

    /// The authority passes, whichever account it is.
    function testSenderIsAuthority(address authority) external pure {
        LibConfigRegistryRegister.checkSender(authority, authority);
    }

    /// The input refusals come before anything is forked, in order: name,
    /// value, networks, sender. Every case here would otherwise reach a fork
    /// of a network this test supplies no endpoint for.
    function testRegisterOnNetworksRefusesInputsInOrder(address sender) external {
        vm.assume(sender != AUTHORITY);
        string[] memory declared = LibRainDeploy.supportedNetworks();

        vm.expectRevert(abi.encodeWithSelector(LibConfigRegistryRegister.NonCanonicalName.selector, "A"));
        this.externalRegisterOnNetworks(new string[](0), declared, sender, "A", "");

        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV1.EmptyValue.selector, keccak256("a.b")));
        this.externalRegisterOnNetworks(new string[](0), declared, sender, "a.b", "");

        bytes memory bare = abi.encodePacked(address(0xdEaD));
        vm.expectRevert(abi.encodeWithSelector(LibConfigRegistryRegister.NonCanonicalValue.selector, bare));
        this.externalRegisterOnNetworks(new string[](0), declared, sender, "a.b", bare);

        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.NoNetworks.selector));
        this.externalRegisterOnNetworks(new string[](0), declared, sender, "a.b", abi.encode(address(1)));

        vm.expectRevert(abi.encodeWithSelector(LibConfigRegistryRegister.NetworkNotDeclared.selector, "nowhere"));
        this.externalRegisterOnNetworks(list("nowhere"), declared, sender, "a.b", abi.encode(address(1)));

        vm.expectRevert(
            abi.encodeWithSelector(LibConfigRegistryRegister.SenderNotAuthority.selector, sender, AUTHORITY)
        );
        this.externalRegisterOnNetworks(list("base"), declared, sender, "a.b", abi.encode(address(1)));
    }

    /// A non-empty value is refused exactly when its length is not a multiple
    /// of 32; a whole number of words passes the value check and reaches the
    /// networks.
    function testRegisterOnNetworksValueIsWholeWords(uint16 length) external {
        vm.assume(length > 0);
        bytes memory value = new bytes(length);
        if (length % 32 == 0) {
            vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.NoNetworks.selector));
        } else {
            vm.expectRevert(abi.encodeWithSelector(LibConfigRegistryRegister.NonCanonicalValue.selector, value));
        }
        this.externalRegisterOnNetworks(new string[](0), LibRainDeploy.supportedNetworks(), AUTHORITY, "a.b", value);
    }

    /// Fixed lengths on and either side of the first three word boundaries,
    /// which a uniform fuzz of the length rarely lands on.
    function testRegisterOnNetworksValueLengthBoundaries() external {
        uint256[8] memory refused = [uint256(1), 20, 31, 33, 63, 65, 95, 97];
        for (uint256 i = 0; i < refused.length; i++) {
            bytes memory value = new bytes(refused[i]);
            vm.expectRevert(abi.encodeWithSelector(LibConfigRegistryRegister.NonCanonicalValue.selector, value));
            this.externalRegisterOnNetworks(new string[](0), LibRainDeploy.supportedNetworks(), AUTHORITY, "a.b", value);
        }
        uint256[3] memory passed = [uint256(32), 64, 96];
        for (uint256 i = 0; i < passed.length; i++) {
            vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.NoNetworks.selector));
            this.externalRegisterOnNetworks(
                new string[](0), LibRainDeploy.supportedNetworks(), AUTHORITY, "a.b", new bytes(passed[i])
            );
        }
    }

    function externalCheckInputs(
        string[] memory selected,
        string[] memory declared,
        address sender,
        string memory name,
        bytes memory value
    ) external pure returns (bytes32, SupportedNetwork[] memory, string memory) {
        return LibConfigRegistryRegister.checkInputs(vm, selected, declared, sender, AUTHORITY, name, value);
    }

    /// Inputs that pass every refusal give the hashed name, the selected
    /// networks and the record of exactly the inputs signed.
    function testCheckInputsRecordIsTheInputsSigned(uint8 words, bytes32 seed) external view {
        bytes memory value = new bytes(32 * (uint256(words) % 4 + 1));
        for (uint256 i = 0; i < value.length; i++) {
            value[i] = keccak256(abi.encode(seed, i))[0];
        }
        string[] memory selected = list(LibRainDeploy.ARBITRUM_ONE, LibRainDeploy.BASE);
        (bytes32 hashed, SupportedNetwork[] memory networks, string memory record) =
            this.externalCheckInputs(selected, LibRainDeploy.supportedNetworks(), AUTHORITY, "a.b", value);
        assertEq(hashed, keccak256("a.b"));
        assertEq(networks.length, 2);
        assertEq(networks[0].name, LibRainDeploy.ARBITRUM_ONE);
        assertEq(networks[1].name, LibRainDeploy.BASE);
        assertEq(record, LibConfigRegistryRegister.describeInputs(vm, "a.b", value, AUTHORITY));
    }

    /// The confirmed check refuses its inputs before anything is forked.
    function testCheckRegisteredOnNetworksRefusesInputs() external {
        string[] memory declared = LibRainDeploy.supportedNetworks();

        vm.expectRevert(abi.encodeWithSelector(LibConfigRegistryRegister.NonCanonicalName.selector, "A"));
        this.externalCheckRegisteredOnNetworks(list("base"), declared, "A", abi.encode(address(1)));

        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.NoNetworks.selector));
        this.externalCheckRegisteredOnNetworks(new string[](0), declared, "a.b", abi.encode(address(1)));

        vm.expectRevert(abi.encodeWithSelector(LibConfigRegistryRegister.NetworkNotDeclared.selector, "nowhere"));
        this.externalCheckRegisteredOnNetworks(list("nowhere"), declared, "a.b", abi.encode(address(1)));
    }

    /// The fork check refuses fork ids that do not pair with the networks,
    /// before selecting any.
    function testCheckRegisteredOnForksRefusesUnpairedForks() external {
        string[] memory declared = LibRainDeploy.supportedNetworks();
        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.ForkIdsLengthMismatch.selector, 2, 1));
        this.externalCheckRegisteredOnForks(
            list("base", "arbitrum"), declared, new uint256[](1), "a.b", abi.encode(address(1))
        );

        vm.expectRevert(abi.encodeWithSelector(LibConfigRegistryRegister.NonCanonicalName.selector, "A"));
        this.externalCheckRegisteredOnForks(list("base"), declared, new uint256[](1), "A", abi.encode(address(1)));

        vm.expectRevert(abi.encodeWithSelector(LibConfigRegistryRegister.NetworkNotDeclared.selector, "nowhere"));
        this.externalCheckRegisteredOnForks(list("nowhere"), declared, new uint256[](1), "a.b", abi.encode(address(1)));
    }

    /// The fork check refuses more fork ids than networks, before selecting
    /// any.
    function testCheckRegisteredOnForksRefusesExtraForkIds() external {
        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.ForkIdsLengthMismatch.selector, 2, 3));
        this.externalCheckRegisteredOnForks(
            list("base", "arbitrum"), LibRainDeploy.supportedNetworks(), new uint256[](3), "a.b", abi.encode(address(1))
        );
    }

    /// The check passes on the bound value and returns the moment it was
    /// bound.
    function testCheckRegisteredOnSelectedChainBound(bytes32 name, bytes memory value, uint96 time) external {
        vm.assume(value.length > 0);
        time = uint96(bound(time, 1, type(uint96).max));
        IConfigRegistryV1 registry = deployRegistry();
        vm.warp(time);
        vm.prank(AUTHORITY);
        registry.registerV1(name, value);
        vm.warp(uint256(time) + 1);

        assertEq(this.externalCheckRegisteredOnSelectedChain(base(), name, value), time);
    }

    /// Any other bound value is refused, naming the network, the name, the
    /// value expected and the value bound, in that order.
    function testCheckRegisteredOnSelectedChainOtherValue(bytes32 name, bytes memory bound_, bytes memory value)
        external
    {
        vm.assume(bound_.length > 0);
        vm.assume(keccak256(bound_) != keccak256(value));
        IConfigRegistryV1 registry = deployRegistry();
        vm.warp(1);
        vm.prank(AUTHORITY);
        registry.registerV1(name, bound_);

        vm.expectRevert(
            abi.encodeWithSelector(
                LibConfigRegistryRegister.UnexpectedBinding.selector, "base", AUTHORITY, name, value, bound_
            )
        );
        this.externalCheckRegisteredOnSelectedChain(base(), name, value);
    }

    /// An unbound name is refused by the registry itself.
    function testCheckRegisteredOnSelectedChainUnbound(bytes32 name) external {
        deployRegistry();
        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV1.NameNotRegistered.selector, AUTHORITY, name));
        this.externalCheckRegisteredOnSelectedChain(base(), name, abi.encode(address(1)));
    }

    /// A chain that is not the network's is refused before the registry is
    /// read, even when the name is bound to the value.
    function testCheckRegisteredOnSelectedChainWrongChain(uint64 chainId) external {
        vm.assume(chainId != base().chainId);
        IConfigRegistryV1 registry = deployRegistry();
        vm.warp(1);
        vm.prank(AUTHORITY);
        registry.registerV1(keccak256("a"), abi.encode(address(1)));
        vm.chainId(chainId);

        vm.expectRevert(
            abi.encodeWithSelector(
                LibConfigRegistryRegister.UnexpectedChainId.selector, "base", base().chainId, uint256(chainId)
            )
        );
        this.externalCheckRegisteredOnSelectedChain(base(), keccak256("a"), abi.encode(address(1)));
    }

    /// A registry address without the pinned code is refused.
    function testCheckRegisteredOnSelectedChainWithoutRegistry() external {
        vm.chainId(base().chainId);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibConfigRegistry.UnexpectedConfigRegistryCodeHash.selector,
                LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_CODEHASH,
                bytes32(0)
            )
        );
        this.externalCheckRegisteredOnSelectedChain(base(), keccak256("a"), abi.encode(address(1)));
    }

    /// A chain that is not the network's is refused before the registry is
    /// read.
    function testRegisterOnWrongChain(uint64 chainId) external {
        vm.assume(chainId != base().chainId);
        deployRegistry();
        vm.chainId(chainId);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibConfigRegistryRegister.UnexpectedChainId.selector, "base", base().chainId, uint256(chainId)
            )
        );
        this.externalRegisterOnSelectedChain(base(), AUTHORITY, keccak256("a"), abi.encode(address(1)));
    }

    /// A registry address without the pinned code is refused.
    function testRegisterWithoutRegistry() external {
        vm.chainId(base().chainId);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibConfigRegistry.UnexpectedConfigRegistryCodeHash.selector,
                LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_CODEHASH,
                bytes32(0)
            )
        );
        this.externalRegisterOnSelectedChain(base(), AUTHORITY, keccak256("a"), abi.encode(address(1)));
    }

    /// Something else at the registry address is refused.
    function testRegisterWithOtherCodeAtRegistry() external {
        vm.chainId(base().chainId);
        deployCodeTo(
            "MockRevertingRegistry.sol", abi.encode(bytes("")), LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                LibConfigRegistry.UnexpectedConfigRegistryCodeHash.selector,
                LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_CODEHASH,
                LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS.codehash
            )
        );
        this.externalRegisterOnSelectedChain(base(), AUTHORITY, keccak256("a"), abi.encode(address(1)));
    }

    /// An unbound name is bound, from the sender.
    function testRegisterUnbound(bytes32 name, bytes memory value, uint96 time) external {
        vm.assume(value.length > 0);
        time = uint96(bound(time, 1, type(uint96).max));
        IConfigRegistryV1 registry = deployRegistry();
        vm.warp(time);

        (bool broadcast, string memory record) = this.externalRegisterOnSelectedChain(base(), AUTHORITY, name, value);
        assertTrue(broadcast);
        assertEq(record, LibConfigRegistryRegister.describeNetwork(vm, base().name, base().chainId, "", 0, value));
        (bytes memory boundValue, uint256 registeredAt) = registry.getV1(AUTHORITY, name);
        assertEq(boundValue, value);
        assertEq(registeredAt, time);
    }

    /// The bind is broadcast from the sender it is given, so it lands under
    /// that sender as authority and under no other.
    function testRegisterBroadcastsFromSender(address sender) external {
        assumeNotPrecompile(sender);
        assumeNotForgeAddress(sender);
        vm.assume(sender != AUTHORITY);
        IConfigRegistryV1 registry = deployRegistry();
        bytes32 name = keccak256("a");
        bytes memory value = abi.encode(address(1));
        vm.warp(1);
        (bool broadcast,) = this.externalRegisterOnSelectedChain(base(), sender, name, value);
        assertTrue(broadcast);
        assertEq(LibConfigRegistryRead.getValue(registry, sender, name), value);
        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV1.NameNotRegistered.selector, AUTHORITY, name));
        registry.getV1(AUTHORITY, name);
    }

    /// A name bound to another value is re-bound.
    function testRegisterRebinds(bytes32 name, bytes memory previous, bytes memory value) external {
        vm.assume(previous.length > 0);
        vm.assume(value.length > 0);
        vm.assume(keccak256(previous) != keccak256(value));
        IConfigRegistryV1 registry = deployRegistry();
        vm.warp(1);
        vm.prank(AUTHORITY);
        registry.registerV1(name, previous);
        vm.warp(2);

        (bool broadcast, string memory record) = this.externalRegisterOnSelectedChain(base(), AUTHORITY, name, value);
        assertTrue(broadcast);
        assertEq(record, LibConfigRegistryRegister.describeNetwork(vm, base().name, base().chainId, previous, 1, value));
        (bytes memory boundValue, uint256 registeredAt) = registry.getV1(AUTHORITY, name);
        assertEq(boundValue, value);
        assertEq(registeredAt, 2);
    }

    /// A value that differs from the bound one only past its first word, or
    /// only in length, is a different value and is re-bound: the comparison is
    /// of the whole value.
    function testRegisterRebindsNearMisses() external {
        bytes32 name = keccak256("a.b");
        IConfigRegistryV1 registry = deployRegistry();
        bytes memory previous = abi.encode(uint256(1), uint256(2));
        bytes[3] memory nearMisses = [
            abi.encode(uint256(1), uint256(3)), abi.encode(uint256(1)), abi.encode(uint256(1), uint256(2), uint256(0))
        ];
        for (uint256 i = 0; i < nearMisses.length; i++) {
            vm.warp(2 * i + 1);
            vm.prank(AUTHORITY);
            registry.registerV1(name, previous);
            vm.warp(2 * i + 2);

            (bool broadcast,) = this.externalRegisterOnSelectedChain(base(), AUTHORITY, name, nearMisses[i]);
            assertTrue(broadcast);
            assertEq(LibConfigRegistryRead.getValue(registry, AUTHORITY, name), nearMisses[i]);
        }
    }

    /// A name already bound to the value is skipped: nothing is broadcast, so
    /// the moment stays the original bind's.
    function testRegisterSkipsSameBinding(bytes32 name, bytes memory value) external {
        vm.assume(value.length > 0);
        IConfigRegistryV1 registry = deployRegistry();
        vm.warp(1);
        vm.prank(AUTHORITY);
        registry.registerV1(name, value);
        vm.warp(2);

        (bool broadcast, string memory record) = this.externalRegisterOnSelectedChain(base(), AUTHORITY, name, value);
        assertFalse(broadcast);
        assertEq(record, LibConfigRegistryRegister.describeNetwork(vm, base().name, base().chainId, value, 1, value));
        (bytes memory boundValue, uint256 registeredAt) = registry.getV1(AUTHORITY, name);
        assertEq(boundValue, value);
        assertEq(registeredAt, 1);
    }

    /// An unbound name reads as an empty value and a zero moment; a bound one
    /// as its binding.
    function testCurrentBinding(bytes32 name, bytes32 other, bytes memory value) external {
        vm.assume(value.length > 0);
        vm.assume(name != other);
        IConfigRegistryV1 registry = deployRegistry();
        (bytes memory boundValue, uint256 registeredAt) = LibConfigRegistryRegister.currentBinding(AUTHORITY, name);
        assertEq(boundValue, "");
        assertEq(registeredAt, 0);

        vm.warp(7);
        vm.prank(AUTHORITY);
        registry.registerV1(name, value);
        (boundValue, registeredAt) = LibConfigRegistryRegister.currentBinding(AUTHORITY, name);
        assertEq(boundValue, value);
        assertEq(registeredAt, 7);
        (boundValue, registeredAt) = LibConfigRegistryRegister.currentBinding(AUTHORITY, other);
        assertEq(boundValue, "");
        assertEq(registeredAt, 0);
    }

    /// Only the registry's `NameNotRegistered` for THIS authority and name
    /// reads as unbound. Any other revert — for another name, another
    /// authority, or anything else — is re-raised as it was.
    function testCurrentBindingReraisesOtherReverts(bytes32 name, bytes32 other, address otherAuthority) external {
        vm.assume(name != other);
        vm.assume(otherAuthority != AUTHORITY);
        bytes memory otherAuthorityName =
            abi.encodeWithSelector(IConfigRegistryV1.NameNotRegistered.selector, otherAuthority, name);
        deployCodeTo(
            "MockRevertingRegistry.sol",
            abi.encode(otherAuthorityName),
            LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS
        );
        vm.expectRevert(otherAuthorityName);
        this.externalCurrentBinding(name);

        bytes memory otherName = abi.encodeWithSelector(IConfigRegistryV1.NameNotRegistered.selector, AUTHORITY, other);
        deployCodeTo(
            "MockRevertingRegistry.sol", abi.encode(otherName), LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS
        );
        vm.expectRevert(otherName);
        this.externalCurrentBinding(name);

        bytes memory anything = abi.encodeWithSignature("Error(string)", "anything");
        deployCodeTo(
            "MockRevertingRegistry.sol", abi.encode(anything), LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS
        );
        vm.expectRevert(anything);
        this.externalCurrentBinding(name);

        deployCodeTo(
            "MockRevertingRegistry.sol", abi.encode(bytes("")), LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS
        );
        vm.expectRevert(bytes(""));
        this.externalCurrentBinding(name);

        bytes memory thisName = abi.encodeWithSelector(IConfigRegistryV1.NameNotRegistered.selector, AUTHORITY, name);
        deployCodeTo(
            "MockRevertingRegistry.sol", abi.encode(thisName), LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS
        );
        (bytes memory boundValue, uint256 registeredAt) = this.externalCurrentBinding(name);
        assertEq(boundValue, "");
        assertEq(registeredAt, 0);
    }

    /// The bind's calldata is `registerV1(bytes32,bytes)` — selector
    /// `0xb5a8845f`, from `cast sig` — over the name hash and the value as a
    /// dynamic argument: its offset, its length and its bytes right-padded to
    /// a word. It is exactly the call the bind makes.
    function testRegisterCalldataIsTheCallSent(bytes32 name, bytes memory value) external {
        vm.assume(value.length > 0);
        bytes memory expected = abi.encodePacked(
            bytes4(0xb5a8845f),
            name,
            uint256(0x40),
            uint256(value.length),
            value,
            new bytes((32 - value.length % 32) % 32)
        );
        assertEq(LibConfigRegistryRegister.registerCalldata(name, value), expected);

        deployRegistry();
        vm.warp(1);
        vm.expectCall(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS, expected, 1);
        this.externalRegisterOnSelectedChain(base(), AUTHORITY, name, value);
    }

    /// The inputs record, field for field, for st0x's token-owner Safe bound to
    /// `0x…dEaD`. The hash, value and calldata are `cast keccak
    /// st0x.token-owner-safe`, `cast abi-encode "f(address)" 0x…dEaD` and
    /// `cast calldata "registerV1(bytes32,bytes)" <hash> <value>`.
    function testDescribeInputs() external pure {
        assertEq(
            LibConfigRegistryRegister.describeInputs(
                vm, "st0x.token-owner-safe", abi.encode(address(0xdEaD)), AUTHORITY
            ),
            string.concat(
                "Name: st0x.token-owner-safe\n",
                "Name hash (keccak256 of the name): 0xba1ec70c388d07ed204e3cfdcbdc2564f9aa2e5b310aeae3767c61a68306cfc8\n",
                "Value: 0x000000000000000000000000000000000000000000000000000000000000dead\n",
                "Authority (sender): ",
                vm.toString(AUTHORITY),
                "\n",
                "Registry: ",
                vm.toString(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS),
                "\n",
                "Calldata: 0xb5a8845fba1ec70c388d07ed204e3cfdcbdc2564f9aa2e5b310aeae3767c61a68306cfc8",
                "0000000000000000000000000000000000000000000000000000000000000040",
                "0000000000000000000000000000000000000000000000000000000000000020",
                "000000000000000000000000000000000000000000000000000000000000dead"
            )
        );
    }

    /// The inputs record refuses a non-canonical name, as the bind does.
    function testDescribeInputsRefusesNonCanonicalName() external {
        vm.expectRevert(abi.encodeWithSelector(LibConfigRegistryRegister.NonCanonicalName.selector, "A"));
        this.externalDescribeInputs("A");
    }

    function externalDescribeInputs(string memory name) external pure returns (string memory) {
        return LibConfigRegistryRegister.describeInputs(vm, name, abi.encode(address(0xdEaD)), AUTHORITY);
    }

    /// An unbound name is a BIND.
    function testDescribeNetworkUnbound() external pure {
        assertEq(
            LibConfigRegistryRegister.describeNetwork(vm, "base", 8453, "", 0, hex"dead"),
            "Network: base\n  chain id: 8453\n  current: unbound\n  BIND: -> 0xdead"
        );
    }

    /// A name bound elsewhere is a REBIND, showing the old binding and when it
    /// was made.
    function testDescribeNetworkRebind() external pure {
        assertEq(
            LibConfigRegistryRegister.describeNetwork(vm, "arbitrum", 42161, hex"0b30", 7, hex"dead"),
            string.concat(
                "Network: arbitrum\n  chain id: 42161\n", "  current: 0x0b30 (bound at 7)\n", "  REBIND: -> 0xdead"
            )
        );
    }

    /// A name bound to the value already is a SKIP.
    function testDescribeNetworkSkip() external pure {
        assertEq(
            LibConfigRegistryRegister.describeNetwork(vm, "flare", 14, hex"dead", 7, hex"dead"),
            string.concat(
                "Network: flare\n  chain id: 14\n",
                "  current: 0xdead (bound at 7)\n",
                "  SKIP: already bound to 0xdead"
            )
        );
    }

    /// A bound value that differs from the one to bind only in length is a
    /// REBIND, not a SKIP.
    function testDescribeNetworkLengthMismatchIsRebind() external pure {
        assertEq(
            LibConfigRegistryRegister.describeNetwork(vm, "flare", 14, hex"dead00", 7, hex"dead"),
            string.concat(
                "Network: flare\n  chain id: 14\n", "  current: 0xdead00 (bound at 7)\n", "  REBIND: -> 0xdead"
            )
        );
    }
}
