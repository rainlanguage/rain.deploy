// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";

import {AddressRegistry, ADDRESS_REGISTRY_ROOT} from "../../../src/concrete/AddressRegistry.sol";
import {IAddressRegistryV1} from "../../../src/interface/IAddressRegistryV1.sol";
import {LibAddressRegistry} from "../../../src/lib/LibAddressRegistry.sol";
import {LibAddressRegistryDeploy} from "../../../src/lib/LibAddressRegistryDeploy.sol";
import {LibAddressRegistryRegister} from "../../../src/lib/LibAddressRegistryRegister.sol";
import {LibRainDeploy, SupportedNetwork} from "../../../src/lib/LibRainDeploy.sol";
import {MockRevertingRegistry} from "../../concrete/MockRevertingRegistry.sol";

/// @title LibAddressRegistryRegisterTest
/// Every guard `LibAddressRegistryRegister` makes before a bind, and the bind
/// itself, on the local chain: the real `AddressRegistry` deployed through the
/// Zoltu factory at the pinned address, and the chain id set to the network's.
/// Nothing here forks; `LibAddressRegistryRegisterForkTest` drives the fork
/// loops.
contract LibAddressRegistryRegisterTest is Test {
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
    function deployRegistry() internal returns (IAddressRegistryV1) {
        vm.chainId(base().chainId);
        LibRainDeploy.etchZoltuFactory(vm);
        address registry = LibRainDeploy.deployZoltu(type(AddressRegistry).creationCode);
        assertEq(registry, LibAddressRegistryDeploy.ADDRESS_REGISTRY_DEPLOYED_ADDRESS);
        return IAddressRegistryV1(registry);
    }

    /// One-element string list.
    function list(string memory a) internal pure returns (string[] memory networks) {
        networks = new string[](1);
        networks[0] = a;
    }

    /// Two-element string list.
    function list(string memory a, string memory b) internal pure returns (string[] memory networks) {
        networks = new string[](2);
        networks[0] = a;
        networks[1] = b;
    }

    function externalNameHash(string memory name) external pure returns (bytes32) {
        return LibAddressRegistryRegister.nameHash(name);
    }

    function externalSelectNetworks(string[] memory selected, string[] memory declared)
        external
        pure
        returns (SupportedNetwork[] memory)
    {
        return LibAddressRegistryRegister.selectNetworks(selected, declared);
    }

    function externalCheckSender(address sender) external pure {
        LibAddressRegistryRegister.checkSender(sender);
    }

    function externalCurrentBinding(bytes32 name) external view returns (address, uint256) {
        return LibAddressRegistryRegister.currentBinding(name);
    }

    function externalRegisterOnSelectedChain(
        SupportedNetwork memory network,
        address sender,
        bytes32 name,
        address account
    ) external returns (bool) {
        return LibAddressRegistryRegister.registerOnSelectedChain(vm, network, sender, name, account);
    }

    function externalRegisterOnNetworks(
        string[] memory selected,
        string[] memory declared,
        address sender,
        string memory name,
        address account
    ) external returns (uint256[] memory) {
        return LibAddressRegistryRegister.registerOnNetworks(vm, selected, declared, sender, name, account);
    }

    function externalCheckRegisteredOnForks(
        string[] memory selected,
        string[] memory declared,
        uint256[] memory forkIds,
        string memory name,
        address account
    ) external {
        LibAddressRegistryRegister.checkRegisteredOnForks(vm, selected, declared, forkIds, name, account);
    }

    function externalCheckRegisteredOnNetworks(
        string[] memory selected,
        string[] memory declared,
        string memory name,
        address account
    ) external {
        LibAddressRegistryRegister.checkRegisteredOnNetworks(vm, selected, declared, name, account);
    }

    /// The name is the `keccak256` of its string, the derivation consumers
    /// use: st0x resolves its token-owner Safe as
    /// `keccak256("st0x.token-owner-safe")`.
    function testNameHashIsTheConsumerDerivation() external pure {
        assertEq(LibAddressRegistryRegister.nameHash("st0x.token-owner-safe"), keccak256("st0x.token-owner-safe"));
        assertEq(LibAddressRegistryRegister.nameHash("a"), keccak256("a"));
        assertEq(LibAddressRegistryRegister.nameHash("z9.0-a"), keccak256("z9.0-a"));
        assertEq(LibAddressRegistryRegister.nameHash("az09.za-90"), keccak256("az09.za-90"));
    }

    /// Asserts `name` is refused as non-canonical.
    function assertNonCanonical(string memory name) internal {
        vm.expectRevert(abi.encodeWithSelector(LibAddressRegistryRegister.NonCanonicalName.selector, name));
        this.externalNameHash(name);
    }

    /// Every near miss of a canonical name is refused: empty, capitals, a
    /// leading digit (which is every `0x…` hash), a separator at either end or
    /// twice in a row, whitespace, and the characters either side of each
    /// accepted range.
    function testNonCanonicalNamesAreRefused() external {
        assertNonCanonical("");
        assertNonCanonical("A");
        assertNonCanonical("st0x.Token-owner-safe");
        assertNonCanonical("1abc");
        assertNonCanonical("0x0b300013cd54a8f1ac40981f80faaa18b8cc1e4c0b300013cd54a8f1ac409810");
        assertNonCanonical(".a");
        assertNonCanonical("-a");
        assertNonCanonical("a.");
        assertNonCanonical("a-");
        assertNonCanonical("a..b");
        assertNonCanonical("a.-b");
        assertNonCanonical("a--b");
        assertNonCanonical(" a");
        assertNonCanonical("a ");
        assertNonCanonical("a\n");
        assertNonCanonical("a b");
        assertNonCanonical("a_b");
        assertNonCanonical("a/b");
        assertNonCanonical("a:b");
        assertNonCanonical("a`b");
        assertNonCanonical("a{b");
        assertNonCanonical("a@b");
        assertNonCanonical("a[b");
        assertNonCanonical("`a");
        assertNonCanonical("{a");
        assertNonCanonical(unicode"é");
    }

    /// An empty selection is refused.
    function testSelectNoNetworks() external {
        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.NoNetworks.selector));
        this.externalSelectNetworks(new string[](0), LibRainDeploy.supportedNetworks());
    }

    /// A network outside the declaration is refused, even one the catalogue
    /// knows.
    function testSelectUndeclaredNetwork() external {
        vm.expectRevert(abi.encodeWithSelector(LibAddressRegistryRegister.NetworkNotDeclared.selector, "nowhere"));
        this.externalSelectNetworks(list("base", "nowhere"), LibRainDeploy.supportedNetworks());

        vm.expectRevert(abi.encodeWithSelector(LibAddressRegistryRegister.NetworkNotDeclared.selector, "base"));
        this.externalSelectNetworks(list("base"), list("arbitrum"));
    }

    /// A network selected twice is refused.
    function testSelectDuplicateNetwork() external {
        vm.expectRevert(abi.encodeWithSelector(LibAddressRegistryRegister.DuplicateNetwork.selector, "base"));
        this.externalSelectNetworks(list("base", "base"), LibRainDeploy.supportedNetworks());
    }

    /// A selection answers with the catalogue entry of each selected network,
    /// in selection order.
    function testSelectSubsetInSelectionOrder() external pure {
        SupportedNetwork[] memory selected =
            LibAddressRegistryRegister.selectNetworks(list("base", "arbitrum"), LibRainDeploy.supportedNetworks());
        assertEq(selected.length, 2);
        assertEq(selected[0].name, "base");
        assertEq(selected[0].chainId, 8453);
        assertEq(selected[1].name, "arbitrum");
        assertEq(selected[1].chainId, 42161);
    }

    /// Every declared network is selectable at once.
    function testSelectEveryDeclaredNetwork() external pure {
        string[] memory declared = LibRainDeploy.supportedNetworks();
        assertEq(LibAddressRegistryRegister.selectNetworks(declared, declared).length, declared.length);
    }

    /// Any sender but root is refused, naming both.
    function testSenderNotRoot(address sender) external {
        vm.assume(sender != ADDRESS_REGISTRY_ROOT);
        vm.expectRevert(
            abi.encodeWithSelector(LibAddressRegistryRegister.SenderNotRoot.selector, sender, ADDRESS_REGISTRY_ROOT)
        );
        this.externalCheckSender(sender);
    }

    /// Root passes.
    function testSenderRoot() external pure {
        LibAddressRegistryRegister.checkSender(ADDRESS_REGISTRY_ROOT);
    }

    /// The input refusals come before anything is forked, in order: name,
    /// account, networks, sender. Every case here would otherwise reach a fork
    /// of a network this test supplies no endpoint for.
    function testRegisterOnNetworksRefusesInputsInOrder(address sender) external {
        vm.assume(sender != ADDRESS_REGISTRY_ROOT);
        string[] memory declared = LibRainDeploy.supportedNetworks();

        vm.expectRevert(abi.encodeWithSelector(LibAddressRegistryRegister.NonCanonicalName.selector, "A"));
        this.externalRegisterOnNetworks(new string[](0), declared, sender, "A", address(0));

        vm.expectRevert(abi.encodeWithSelector(IAddressRegistryV1.ZeroAccount.selector, keccak256("a")));
        this.externalRegisterOnNetworks(new string[](0), declared, sender, "a", address(0));

        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.NoNetworks.selector));
        this.externalRegisterOnNetworks(new string[](0), declared, sender, "a", address(1));

        vm.expectRevert(abi.encodeWithSelector(LibAddressRegistryRegister.NetworkNotDeclared.selector, "nowhere"));
        this.externalRegisterOnNetworks(list("nowhere"), declared, sender, "a", address(1));

        vm.expectRevert(
            abi.encodeWithSelector(LibAddressRegistryRegister.SenderNotRoot.selector, sender, ADDRESS_REGISTRY_ROOT)
        );
        this.externalRegisterOnNetworks(list("base"), declared, sender, "a", address(1));
    }

    /// The confirmed check refuses its inputs before anything is forked.
    function testCheckRegisteredOnNetworksRefusesInputs() external {
        string[] memory declared = LibRainDeploy.supportedNetworks();

        vm.expectRevert(abi.encodeWithSelector(LibAddressRegistryRegister.NonCanonicalName.selector, "A"));
        this.externalCheckRegisteredOnNetworks(list("base"), declared, "A", address(1));

        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.NoNetworks.selector));
        this.externalCheckRegisteredOnNetworks(new string[](0), declared, "a", address(1));

        vm.expectRevert(abi.encodeWithSelector(LibAddressRegistryRegister.NetworkNotDeclared.selector, "nowhere"));
        this.externalCheckRegisteredOnNetworks(list("nowhere"), declared, "a", address(1));
    }

    /// The fork check refuses fork ids that do not pair with the networks,
    /// before selecting any.
    function testCheckRegisteredOnForksRefusesUnpairedForks() external {
        string[] memory declared = LibRainDeploy.supportedNetworks();
        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.ForkIdsLengthMismatch.selector, 2, 1));
        this.externalCheckRegisteredOnForks(list("base", "arbitrum"), declared, new uint256[](1), "a", address(1));

        vm.expectRevert(abi.encodeWithSelector(LibAddressRegistryRegister.NonCanonicalName.selector, "A"));
        this.externalCheckRegisteredOnForks(list("base"), declared, new uint256[](1), "A", address(1));

        vm.expectRevert(abi.encodeWithSelector(LibAddressRegistryRegister.NetworkNotDeclared.selector, "nowhere"));
        this.externalCheckRegisteredOnForks(list("nowhere"), declared, new uint256[](1), "a", address(1));
    }

    /// A chain that is not the network's is refused before the registry is
    /// read.
    function testRegisterOnWrongChain(uint64 chainId) external {
        vm.assume(chainId != base().chainId);
        deployRegistry();
        vm.chainId(chainId);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibAddressRegistryRegister.UnexpectedChainId.selector, "base", base().chainId, uint256(chainId)
            )
        );
        this.externalRegisterOnSelectedChain(base(), ADDRESS_REGISTRY_ROOT, keccak256("a"), address(1));
    }

    /// A registry address without the pinned code is refused.
    function testRegisterWithoutRegistry() external {
        vm.chainId(base().chainId);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibAddressRegistry.UnexpectedAddressRegistryCodeHash.selector,
                LibAddressRegistryDeploy.ADDRESS_REGISTRY_DEPLOYED_CODEHASH,
                bytes32(0)
            )
        );
        this.externalRegisterOnSelectedChain(base(), ADDRESS_REGISTRY_ROOT, keccak256("a"), address(1));
    }

    /// Something else at the registry address is refused.
    function testRegisterWithOtherCodeAtRegistry() external {
        vm.chainId(base().chainId);
        deployCodeTo(
            "MockRevertingRegistry.sol",
            abi.encode(bytes("")),
            LibAddressRegistryDeploy.ADDRESS_REGISTRY_DEPLOYED_ADDRESS
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                LibAddressRegistry.UnexpectedAddressRegistryCodeHash.selector,
                LibAddressRegistryDeploy.ADDRESS_REGISTRY_DEPLOYED_CODEHASH,
                LibAddressRegistryDeploy.ADDRESS_REGISTRY_DEPLOYED_ADDRESS.codehash
            )
        );
        this.externalRegisterOnSelectedChain(base(), ADDRESS_REGISTRY_ROOT, keccak256("a"), address(1));
    }

    /// An unbound name is bound, from the sender.
    function testRegisterUnbound(bytes32 name, address account, uint96 time) external {
        vm.assume(account != address(0));
        time = uint96(bound(time, 1, type(uint96).max));
        IAddressRegistryV1 registry = deployRegistry();
        vm.warp(time);

        assertTrue(this.externalRegisterOnSelectedChain(base(), ADDRESS_REGISTRY_ROOT, name, account));
        (address bound_, uint256 registeredAt) = registry.get(name);
        assertEq(bound_, account);
        assertEq(registeredAt, time);
    }

    /// The bind is broadcast from the sender it is given: the registry itself
    /// refuses any other.
    function testRegisterBroadcastsFromSender(address sender) external {
        vm.assume(sender != ADDRESS_REGISTRY_ROOT);
        deployRegistry();
        vm.warp(1);
        vm.expectRevert(abi.encodeWithSelector(IAddressRegistryV1.NotRoot.selector, sender));
        this.externalRegisterOnSelectedChain(base(), sender, keccak256("a"), address(1));
    }

    /// A name bound to another account is re-bound.
    function testRegisterRebinds(bytes32 name, address previous, address account) external {
        vm.assume(previous != address(0));
        vm.assume(account != address(0));
        vm.assume(previous != account);
        IAddressRegistryV1 registry = deployRegistry();
        vm.warp(1);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        registry.register(name, previous);
        vm.warp(2);

        assertTrue(this.externalRegisterOnSelectedChain(base(), ADDRESS_REGISTRY_ROOT, name, account));
        (address bound_, uint256 registeredAt) = registry.get(name);
        assertEq(bound_, account);
        assertEq(registeredAt, 2);
    }

    /// A name already bound to the account is skipped: nothing is broadcast,
    /// so the moment stays the original bind's.
    function testRegisterSkipsSameBinding(bytes32 name, address account) external {
        vm.assume(account != address(0));
        IAddressRegistryV1 registry = deployRegistry();
        vm.warp(1);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        registry.register(name, account);
        vm.warp(2);

        assertFalse(this.externalRegisterOnSelectedChain(base(), ADDRESS_REGISTRY_ROOT, name, account));
        (address bound_, uint256 registeredAt) = registry.get(name);
        assertEq(bound_, account);
        assertEq(registeredAt, 1);
    }

    /// An unbound name reads as the zero address and moment; a bound one as its
    /// binding.
    function testCurrentBinding(bytes32 name, bytes32 other, address account) external {
        vm.assume(account != address(0));
        vm.assume(name != other);
        IAddressRegistryV1 registry = deployRegistry();
        (address bound_, uint256 registeredAt) = LibAddressRegistryRegister.currentBinding(name);
        assertEq(bound_, address(0));
        assertEq(registeredAt, 0);

        vm.warp(7);
        vm.prank(ADDRESS_REGISTRY_ROOT);
        registry.register(name, account);
        (bound_, registeredAt) = LibAddressRegistryRegister.currentBinding(name);
        assertEq(bound_, account);
        assertEq(registeredAt, 7);
        (bound_, registeredAt) = LibAddressRegistryRegister.currentBinding(other);
        assertEq(bound_, address(0));
        assertEq(registeredAt, 0);
    }

    /// Only the registry's `NameNotRegistered` for THIS name reads as unbound.
    /// Any other revert — for another name, or anything else — is re-raised
    /// as it was.
    function testCurrentBindingReraisesOtherReverts(bytes32 name, bytes32 other) external {
        vm.assume(name != other);
        bytes memory otherName = abi.encodeWithSelector(IAddressRegistryV1.NameNotRegistered.selector, other);
        deployCodeTo(
            "MockRevertingRegistry.sol",
            abi.encode(otherName),
            LibAddressRegistryDeploy.ADDRESS_REGISTRY_DEPLOYED_ADDRESS
        );
        vm.expectRevert(otherName);
        this.externalCurrentBinding(name);

        bytes memory anything = abi.encodeWithSignature("Error(string)", "anything");
        deployCodeTo(
            "MockRevertingRegistry.sol",
            abi.encode(anything),
            LibAddressRegistryDeploy.ADDRESS_REGISTRY_DEPLOYED_ADDRESS
        );
        vm.expectRevert(anything);
        this.externalCurrentBinding(name);

        deployCodeTo(
            "MockRevertingRegistry.sol",
            abi.encode(bytes("")),
            LibAddressRegistryDeploy.ADDRESS_REGISTRY_DEPLOYED_ADDRESS
        );
        vm.expectRevert(bytes(""));
        this.externalCurrentBinding(name);

        bytes memory thisName = abi.encodeWithSelector(IAddressRegistryV1.NameNotRegistered.selector, name);
        deployCodeTo(
            "MockRevertingRegistry.sol",
            abi.encode(thisName),
            LibAddressRegistryDeploy.ADDRESS_REGISTRY_DEPLOYED_ADDRESS
        );
        (address bound_, uint256 registeredAt) = this.externalCurrentBinding(name);
        assertEq(bound_, address(0));
        assertEq(registeredAt, 0);
    }

    /// The bind's calldata is `register(bytes32,address)` — selector
    /// `0xd22057a9`, from `cast sig` — over the name hash and the account
    /// left-padded to a word, and it is exactly the call the bind makes.
    function testRegisterCalldataIsTheCallSent(bytes32 name, address account) external {
        vm.assume(account != address(0));
        bytes memory expected = abi.encodePacked(bytes4(0xd22057a9), name, uint256(uint160(account)));
        assertEq(LibAddressRegistryRegister.registerCalldata(name, account), expected);

        deployRegistry();
        vm.warp(1);
        vm.expectCall(LibAddressRegistryDeploy.ADDRESS_REGISTRY_DEPLOYED_ADDRESS, expected, 1);
        this.externalRegisterOnSelectedChain(base(), ADDRESS_REGISTRY_ROOT, name, account);
    }

    /// The inputs record, field for field, for st0x's token-owner Safe. The
    /// hash and calldata are `cast keccak st0x.token-owner-safe` and
    /// `cast calldata "register(bytes32,address)" <hash> 0x…dEaD`.
    function testDescribeInputs() external pure {
        assertEq(
            LibAddressRegistryRegister.describeInputs(
                vm, "st0x.token-owner-safe", address(0xdEaD), ADDRESS_REGISTRY_ROOT
            ),
            string.concat(
                "Name: st0x.token-owner-safe\n",
                "Name hash (keccak256 of the name): 0xba1ec70c388d07ed204e3cfdcbdc2564f9aa2e5b310aeae3767c61a68306cfc8\n",
                "Account: 0x000000000000000000000000000000000000dEaD\n",
                "Sender (root): 0x0b300013CD54a8F1aC40981f80FaaA18b8Cc1E4c\n",
                "Registry: 0xe2B4C27224DdeFFf7D2B3b0e66E3955ab4e2466A\n",
                "Calldata: 0xd22057a9ba1ec70c388d07ed204e3cfdcbdc2564f9aa2e5b310aeae3767c61a68306cfc8",
                "000000000000000000000000000000000000000000000000000000000000dead"
            )
        );
    }

    /// The inputs record refuses a non-canonical name, as the bind does.
    function testDescribeInputsRefusesNonCanonicalName() external {
        vm.expectRevert(abi.encodeWithSelector(LibAddressRegistryRegister.NonCanonicalName.selector, "A"));
        this.externalDescribeInputs("A");
    }

    function externalDescribeInputs(string memory name) external pure returns (string memory) {
        return LibAddressRegistryRegister.describeInputs(vm, name, address(0xdEaD), ADDRESS_REGISTRY_ROOT);
    }

    /// An unbound name is a BIND.
    function testDescribeNetworkUnbound() external pure {
        assertEq(
            LibAddressRegistryRegister.describeNetwork(vm, "base", 8453, address(0), 0, address(0xdEaD)),
            "Network: base\n  chain id: 8453\n  current: unbound\n  BIND: -> 0x000000000000000000000000000000000000dEaD"
        );
    }

    /// A name bound elsewhere is a REBIND, showing the old binding and when it
    /// was made.
    function testDescribeNetworkRebind() external pure {
        assertEq(
            LibAddressRegistryRegister.describeNetwork(
                vm, "arbitrum", 42161, ADDRESS_REGISTRY_ROOT, 7, address(0xdEaD)
            ),
            string.concat(
                "Network: arbitrum\n  chain id: 42161\n",
                "  current: 0x0b300013CD54a8F1aC40981f80FaaA18b8Cc1E4c (bound at 7)\n",
                "  REBIND: -> 0x000000000000000000000000000000000000dEaD"
            )
        );
    }

    /// A name bound to the account already is a SKIP.
    function testDescribeNetworkSkip() external pure {
        assertEq(
            LibAddressRegistryRegister.describeNetwork(vm, "flare", 14, address(0xdEaD), 7, address(0xdEaD)),
            string.concat(
                "Network: flare\n  chain id: 14\n",
                "  current: 0x000000000000000000000000000000000000dEaD (bound at 7)\n",
                "  SKIP: already bound to 0x000000000000000000000000000000000000dEaD"
            )
        );
    }
}
