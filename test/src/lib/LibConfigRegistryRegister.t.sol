// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {IRegistryDelegatesV2} from "../../../src/interface/IRegistryDelegatesV2.sol";
import {Test, Vm} from "forge-std-1.17.0/src/Test.sol";

import {ConfigRegistry} from "../../../src/concrete/ConfigRegistry.sol";
import {IConfigRegistryV4} from "../../../src/interface/IConfigRegistryV4.sol";
import {LibConfigRegistry} from "../../../src/lib/LibConfigRegistry.sol";
import {LibConfigRegistryDeploy} from "../../../src/lib/LibConfigRegistryDeploy.sol";
import {LibConfigRegistryRegister, ConfigBinding} from "../../../src/lib/LibConfigRegistryRegister.sol";
import {LibRainDeploy, SupportedNetwork} from "../../../src/lib/LibRainDeploy.sol";
import {LocalForkVm} from "../../concrete/LocalForkVm.sol";
import {MockRevertingRegistry} from "../../concrete/MockRevertingRegistry.sol";
import {LibConfigRegistryRead} from "../../lib/LibConfigRegistryRead.sol";
import {VALUE_TYPE, VALUE_TYPE_HASH, configBinding} from "../../lib/ConfigTestBinding.sol";

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
    bytes32 internal constant NAME = keccak256("a.b");

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
    function deployRegistry() internal returns (IConfigRegistryV4) {
        vm.chainId(base().chainId);
        LibRainDeploy.etchZoltuFactory(vm);
        address registry = LibRainDeploy.deployZoltu(type(ConfigRegistry).creationCode);
        assertEq(registry, LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS);
        return IConfigRegistryV4(registry);
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

    function externalCheckSender(address sender, address authority) external view {
        LibConfigRegistryRegister.checkSender(base(), sender, authority, NAME);
    }

    function externalCurrentBinding(bytes32 name) external view returns (bytes memory, uint256, bytes32) {
        return LibConfigRegistryRegister.currentBinding(AUTHORITY, name);
    }

    function externalRegisterOnSelectedChain(
        SupportedNetwork memory network,
        address sender,
        address authority,
        bytes32 name,
        bytes memory value
    ) external returns (bool, string memory) {
        return LibConfigRegistryRegister.registerOnSelectedChain(
            vm, network, sender, authority, name, configBinding("", value)
        );
    }

    function externalRegisterOnNetworks(
        string[] memory selected,
        string[] memory declared,
        address sender,
        string memory name,
        bytes memory value
    ) external returns (uint256[] memory, string memory) {
        return LibConfigRegistryRegister.registerOnNetworks(
            vm, selected, declared, sender, AUTHORITY, configBinding(name, value)
        );
    }

    function externalCheckRegisteredOnForks(
        string[] memory selected,
        string[] memory declared,
        uint256[] memory forkIds,
        string memory name,
        bytes memory value
    ) external {
        LibConfigRegistryRegister.checkRegisteredOnForks(
            vm, selected, declared, forkIds, AUTHORITY, configBinding(name, value)
        );
    }

    function externalCheckRegisteredOnSelectedChain(SupportedNetwork memory network, bytes32 name, bytes memory value)
        external
        view
        returns (uint256)
    {
        return LibConfigRegistryRegister.checkRegisteredOnSelectedChain(
            vm, network, AUTHORITY, name, configBinding("", value)
        );
    }

    function externalCheckRegisteredOnNetworks(
        string[] memory selected,
        string[] memory declared,
        string memory name,
        bytes memory value
    ) external {
        LibConfigRegistryRegister.checkRegisteredOnNetworks(
            vm, selected, declared, AUTHORITY, configBinding(name, value)
        );
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

    /// Any sender but the authority that the authority has not approved on
    /// the selected chain is refused, naming the network and both accounts.
    function testSenderNotApproved(address sender, address authority) external {
        vm.assume(sender != authority && sender != address(0));
        deployRegistry();
        vm.expectRevert(
            abi.encodeWithSelector(
                LibConfigRegistryRegister.SenderNotApproved.selector, "base", sender, authority, NAME
            )
        );
        this.externalCheckSender(sender, authority);
    }

    /// The authority passes, whichever account it is, without reading the
    /// registry: there is none here, and any read of it would revert.
    function testSenderIsAuthority(address authority) external view {
        this.externalCheckSender(authority, authority);
    }

    /// A delegate the authority approved on the selected chain passes, and is
    /// refused again once revoked.
    function testSenderIsApprovedDelegate(address sender) external {
        vm.assume(sender != AUTHORITY && sender != address(0));
        IConfigRegistryV4 registry = deployRegistry();
        vm.prank(AUTHORITY);
        registry.approveV4(NAME, sender);
        this.externalCheckSender(sender, AUTHORITY);

        vm.prank(AUTHORITY);
        registry.revokeV4(NAME, sender);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibConfigRegistryRegister.SenderNotApproved.selector, "base", sender, AUTHORITY, NAME
            )
        );
        this.externalCheckSender(sender, AUTHORITY);
    }

    /// An approval by another authority does not pass.
    function testSenderApprovedByAnotherAuthority(address sender, address other) external {
        vm.assume(sender != AUTHORITY && sender != address(0) && other != AUTHORITY);
        IConfigRegistryV4 registry = deployRegistry();
        vm.prank(other);
        registry.approveV4(NAME, sender);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibConfigRegistryRegister.SenderNotApproved.selector, "base", sender, AUTHORITY, NAME
            )
        );
        this.externalCheckSender(sender, AUTHORITY);
    }

    /// The authority's approval for another name does not pass.
    function testSenderApprovedForAnotherName(address sender, bytes32 other) external {
        vm.assume(sender != AUTHORITY && sender != address(0) && other != NAME);
        IConfigRegistryV4 registry = deployRegistry();
        vm.prank(AUTHORITY);
        registry.approveV4(other, sender);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibConfigRegistryRegister.SenderNotApproved.selector, "base", sender, AUTHORITY, NAME
            )
        );
        this.externalCheckSender(sender, AUTHORITY);
    }

    /// The input refusals come before anything is forked, in order: name,
    /// value, networks. Every case here would otherwise reach a fork of a
    /// network this test supplies no endpoint for.
    function testRegisterOnNetworksRefusesInputsInOrder(address sender) external {
        vm.assume(sender != AUTHORITY);
        string[] memory declared = LibRainDeploy.supportedNetworks();

        vm.expectRevert(abi.encodeWithSelector(LibConfigRegistryRegister.NonCanonicalName.selector, "A"));
        this.externalRegisterOnNetworks(new string[](0), declared, sender, "A", "");

        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV4.EmptyValue.selector, keccak256("a.b")));
        this.externalRegisterOnNetworks(new string[](0), declared, sender, "a.b", "");

        bytes memory bare = abi.encodePacked(address(0xdEaD));
        vm.expectRevert(abi.encodeWithSelector(LibConfigRegistryRegister.NonCanonicalValue.selector, bare));
        this.externalRegisterOnNetworks(new string[](0), declared, sender, "a.b", bare);

        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.NoNetworks.selector));
        this.externalRegisterOnNetworks(new string[](0), declared, sender, "a.b", abi.encode(address(1)));

        vm.expectRevert(abi.encodeWithSelector(LibConfigRegistryRegister.NetworkNotDeclared.selector, "nowhere"));
        this.externalRegisterOnNetworks(list("nowhere"), declared, sender, "a.b", abi.encode(address(1)));
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
        return LibConfigRegistryRegister.checkInputs(
            vm, selected, declared, sender, AUTHORITY, configBinding(name, value)
        );
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
        assertEq(
            record, LibConfigRegistryRegister.describeInputs(vm, configBinding("a.b", value), AUTHORITY, AUTHORITY)
        );
    }

    function externalRegisterOnNetworksWith(
        Vm forkVm,
        string[] memory selected,
        address sender,
        address authority,
        string memory name,
        bytes memory value
    ) external returns (uint256[] memory, string memory) {
        return LibConfigRegistryRegister.registerOnNetworks(
            forkVm, selected, LibRainDeploy.supportedNetworks(), sender, authority, configBinding(name, value)
        );
    }

    function externalCheckRegisteredOnNetworksWith(
        Vm forkVm,
        string[] memory selected,
        address authority,
        string memory name,
        bytes memory value
    ) external {
        LibConfigRegistryRegister.checkRegisteredOnNetworks(
            forkVm, selected, LibRainDeploy.supportedNetworks(), authority, configBinding(name, value)
        );
    }

    /// On the local fork seam, a signer the authority has not approved is
    /// refused on the first selected network, naming it, and nothing is bound.
    function testRegisterOnNetworksRefusesAnUnapprovedSigner(address sender) external {
        vm.assume(sender != AUTHORITY && sender != address(0));
        IConfigRegistryV4 registry = deployRegistry();
        Vm forkVm = Vm(address(new LocalForkVm()));
        vm.expectRevert(
            abi.encodeWithSelector(
                LibConfigRegistryRegister.SenderNotApproved.selector,
                LibRainDeploy.ARBITRUM_ONE,
                sender,
                AUTHORITY,
                keccak256("a.b")
            )
        );
        this.externalRegisterOnNetworksWith(
            forkVm,
            list(LibRainDeploy.ARBITRUM_ONE, LibRainDeploy.BASE),
            sender,
            AUTHORITY,
            "a.b",
            abi.encode(address(1))
        );
        vm.expectRevert(
            abi.encodeWithSelector(IConfigRegistryV4.NameNotRegistered.selector, AUTHORITY, keccak256("a.b"))
        );
        registry.getV4(AUTHORITY, keccak256("a.b"));
    }

    /// On the local fork seam, a delegate the authority approved binds under
    /// the authority on every selected network, and the confirmed check under
    /// the authority passes. The seam's broadcast is a no-op, so this contract
    /// signs and is the delegate.
    function testRegisterOnNetworksBindsAsAnApprovedDelegate() external {
        IConfigRegistryV4 registry = deployRegistry();
        Vm forkVm = Vm(address(new LocalForkVm()));
        string[] memory selected = list(LibRainDeploy.ARBITRUM_ONE, LibRainDeploy.BASE);
        bytes memory value = abi.encode(address(1));
        vm.prank(AUTHORITY);
        registry.approveV4(keccak256("a.b"), address(this));

        (, string memory record) =
            this.externalRegisterOnNetworksWith(forkVm, selected, address(this), AUTHORITY, "a.b", value);
        assertEq(
            record, LibConfigRegistryRegister.describeInputs(vm, configBinding("a.b", value), address(this), AUTHORITY)
        );
        assertEq(LibConfigRegistryRead.getValue(registry, AUTHORITY, keccak256("a.b")), value);
        vm.expectRevert(
            abi.encodeWithSelector(IConfigRegistryV4.NameNotRegistered.selector, address(this), keccak256("a.b"))
        );
        registry.getV4(address(this), keccak256("a.b"));
        this.externalCheckRegisteredOnNetworksWith(forkVm, selected, AUTHORITY, "a.b", value);
    }

    /// On the local fork seam, `registerOnNetworks` binds on every selected
    /// network in selection order and returns each network's fork and the
    /// inputs record, and the confirmed check then passes on each. The seam's
    /// broadcast is a no-op, so this contract signs and is the authority.
    function testRegisterOnNetworksReturnsEachForkAndTheRecord() external {
        IConfigRegistryV4 registry = deployRegistry();
        Vm forkVm = Vm(address(new LocalForkVm()));
        string[] memory selected = list(LibRainDeploy.ARBITRUM_ONE, LibRainDeploy.BASE);
        SupportedNetwork[] memory networks = LibRainDeploy.declaredNetworkConfigs(selected);
        bytes memory value = abi.encode(address(1));

        (uint256[] memory forkIds, string memory record) =
            this.externalRegisterOnNetworksWith(forkVm, selected, address(this), address(this), "a.b", value);
        assertEq(forkIds.length, 2);
        assertEq(forkIds[0], networks[0].chainId);
        assertEq(forkIds[1], networks[1].chainId);
        assertEq(
            record,
            LibConfigRegistryRegister.describeInputs(vm, configBinding("a.b", value), address(this), address(this))
        );
        assertEq(block.chainid, networks[1].chainId);
        assertEq(LibConfigRegistryRead.getValue(registry, address(this), keccak256("a.b")), value);

        this.externalCheckRegisteredOnNetworksWith(forkVm, selected, address(this), "a.b", value);
    }

    /// `registerOnNetworks` binds as the sender it is given, not as its own
    /// `msg.sender`: called by another account with this contract as both
    /// sender and authority, it binds on every selected network.
    function testRegisterOnNetworksBindsAsTheGivenSender(address caller) external {
        vm.assume(caller != address(this));
        IConfigRegistryV4 registry = deployRegistry();
        Vm forkVm = Vm(address(new LocalForkVm()));
        string[] memory selected = list(LibRainDeploy.ARBITRUM_ONE, LibRainDeploy.BASE);
        bytes memory value = abi.encode(address(1));

        vm.prank(caller);
        this.externalRegisterOnNetworksWith(forkVm, selected, address(this), address(this), "a.b", value);
        assertEq(LibConfigRegistryRead.getValue(registry, address(this), keccak256("a.b")), value);
        this.externalCheckRegisteredOnNetworksWith(forkVm, selected, address(this), "a.b", value);
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
        IConfigRegistryV4 registry = deployRegistry();
        vm.warp(time);
        vm.prank(AUTHORITY);
        registry.registerV4(AUTHORITY, name, VALUE_TYPE, value, "");
        vm.warp(uint256(time) + 1);

        assertEq(this.externalCheckRegisteredOnSelectedChain(base(), name, value), time);
    }

    /// Any other bound value is refused, naming the network, the authority,
    /// the name, the value expected and the value bound, in that order.
    function testCheckRegisteredOnSelectedChainOtherValue(bytes32 name, bytes memory boundValue, bytes memory value)
        external
    {
        vm.assume(boundValue.length > 0);
        vm.assume(keccak256(boundValue) != keccak256(value));
        IConfigRegistryV4 registry = deployRegistry();
        vm.warp(1);
        vm.prank(AUTHORITY);
        registry.registerV4(AUTHORITY, name, VALUE_TYPE, boundValue, "");

        vm.expectRevert(
            abi.encodeWithSelector(
                LibConfigRegistryRegister.UnexpectedBinding.selector, "base", AUTHORITY, name, value, boundValue
            )
        );
        this.externalCheckRegisteredOnSelectedChain(base(), name, value);
    }

    /// An unbound name is refused by the registry itself.
    function testCheckRegisteredOnSelectedChainUnbound(bytes32 name) external {
        deployRegistry();
        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV4.NameNotRegistered.selector, AUTHORITY, name));
        this.externalCheckRegisteredOnSelectedChain(base(), name, abi.encode(address(1)));
    }

    /// A chain that is not the network's is refused before the registry is
    /// read, even when the name is bound to the value.
    function testCheckRegisteredOnSelectedChainWrongChain(uint64 chainId) external {
        vm.assume(chainId != base().chainId);
        IConfigRegistryV4 registry = deployRegistry();
        vm.warp(1);
        vm.prank(AUTHORITY);
        registry.registerV4(AUTHORITY, keccak256("a"), VALUE_TYPE, abi.encode(address(1)), "");
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
        this.externalRegisterOnSelectedChain(base(), AUTHORITY, AUTHORITY, keccak256("a"), abi.encode(address(1)));
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
        this.externalRegisterOnSelectedChain(base(), AUTHORITY, AUTHORITY, keccak256("a"), abi.encode(address(1)));
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
        this.externalRegisterOnSelectedChain(base(), AUTHORITY, AUTHORITY, keccak256("a"), abi.encode(address(1)));
    }

    /// An unbound name is bound, from the sender.
    function testRegisterUnbound(bytes32 name, bytes memory value, uint96 time) external {
        vm.assume(value.length > 0);
        time = uint96(bound(time, 1, type(uint96).max));
        IConfigRegistryV4 registry = deployRegistry();
        vm.warp(time);

        (bool broadcast, string memory record) =
            this.externalRegisterOnSelectedChain(base(), AUTHORITY, AUTHORITY, name, value);
        assertTrue(broadcast);
        assertEq(
            record,
            LibConfigRegistryRegister.describeNetwork(
                vm, base().name, base().chainId, "", 0, bytes32(0), configBinding("", value)
            )
        );
        (bytes memory boundValue, uint256 registeredAt,) = registry.getV4(AUTHORITY, name);
        assertEq(boundValue, value);
        assertEq(registeredAt, time);
    }

    /// The bind is broadcast from the sender it is given, so as its own
    /// authority it lands under that sender and under no other, and the
    /// broadcast spends one of the sender's nonces.
    function testRegisterBroadcastsFromSender(address sender) external {
        assumeNotPrecompile(sender);
        assumeNotForgeAddress(sender);
        vm.assume(sender != AUTHORITY);
        vm.assume(sender != address(this));
        IConfigRegistryV4 registry = deployRegistry();
        bytes32 name = keccak256("a");
        bytes memory value = abi.encode(address(1));
        vm.warp(1);
        uint64 nonce = vm.getNonce(sender);
        (bool broadcast,) = this.externalRegisterOnSelectedChain(base(), sender, sender, name, value);
        assertTrue(broadcast);
        assertEq(vm.getNonce(sender), nonce + 1);
        assertEq(LibConfigRegistryRead.getValue(registry, sender, name), value);
        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV4.NameNotRegistered.selector, AUTHORITY, name));
        registry.getV4(AUTHORITY, name);
    }

    /// A delegate the authority approved broadcasts the bind from itself, and
    /// it lands under the authority and not under the delegate.
    function testRegisterBroadcastsFromAnApprovedDelegate(address sender) external {
        assumeNotPrecompile(sender);
        assumeNotForgeAddress(sender);
        vm.assume(sender != AUTHORITY);
        vm.assume(sender != address(0));
        vm.assume(sender != address(this));
        IConfigRegistryV4 registry = deployRegistry();
        vm.prank(AUTHORITY);
        registry.approveV4(keccak256("a"), sender);
        bytes32 name = keccak256("a");
        bytes memory value = abi.encode(address(1));
        vm.warp(1);
        uint64 nonce = vm.getNonce(sender);
        vm.expectEmit(address(registry));
        emit IConfigRegistryV4.Register(sender, AUTHORITY, name, VALUE_TYPE, value);
        (bool broadcast,) = this.externalRegisterOnSelectedChain(base(), sender, AUTHORITY, name, value);
        assertTrue(broadcast);
        assertEq(vm.getNonce(sender), nonce + 1);
        assertEq(LibConfigRegistryRead.getValue(registry, AUTHORITY, name), value);
        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV4.NameNotRegistered.selector, sender, name));
        registry.getV4(sender, name);
    }

    /// A sender the authority has not approved is refused on the selected
    /// chain before anything is broadcast and spends no nonce, both where the
    /// name is unbound and where the run would SKIP it.
    function testRegisterRefusesAnUnapprovedSender(address sender) external {
        assumeNotPrecompile(sender);
        assumeNotForgeAddress(sender);
        vm.assume(sender != AUTHORITY);
        vm.assume(sender != address(0));
        vm.assume(sender != address(this));
        IConfigRegistryV4 registry = deployRegistry();
        bytes32 name = keccak256("a");
        bytes memory value = abi.encode(address(1));
        vm.warp(1);
        uint64 nonce = vm.getNonce(sender);
        bytes memory refusal = abi.encodeWithSelector(
            LibConfigRegistryRegister.SenderNotApproved.selector, "base", sender, AUTHORITY, name
        );
        vm.expectRevert(refusal);
        this.externalRegisterOnSelectedChain(base(), sender, AUTHORITY, name, value);

        vm.prank(AUTHORITY);
        registry.registerV4(AUTHORITY, name, VALUE_TYPE, value, "");
        vm.warp(2);
        vm.expectRevert(refusal);
        this.externalRegisterOnSelectedChain(base(), sender, AUTHORITY, name, value);
        assertEq(vm.getNonce(sender), nonce);
    }

    /// The zero address as the sender is refused on the selected chain by the
    /// registry's own `ZeroDelegate`, which `approvedV4` raises before any
    /// approval is read, and nothing is bound.
    function testRegisterRefusesTheZeroSender() external {
        IConfigRegistryV4 registry = deployRegistry();
        bytes32 name = keccak256("a");
        vm.warp(1);
        vm.expectRevert(IRegistryDelegatesV2.ZeroDelegate.selector);
        this.externalRegisterOnSelectedChain(base(), address(0), AUTHORITY, name, abi.encode(address(1)));
        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV4.NameNotRegistered.selector, AUTHORITY, name));
        registry.getV4(AUTHORITY, name);
    }

    /// A name bound to another value is re-bound.
    function testRegisterRebinds(bytes32 name, bytes memory previous, bytes memory value) external {
        vm.assume(previous.length > 0);
        vm.assume(value.length > 0);
        vm.assume(keccak256(previous) != keccak256(value));
        IConfigRegistryV4 registry = deployRegistry();
        vm.warp(1);
        vm.prank(AUTHORITY);
        registry.registerV4(AUTHORITY, name, VALUE_TYPE, previous, "");
        vm.warp(2);

        (bool broadcast, string memory record) =
            this.externalRegisterOnSelectedChain(base(), AUTHORITY, AUTHORITY, name, value);
        assertTrue(broadcast);
        assertEq(
            record,
            LibConfigRegistryRegister.describeNetwork(
                vm, base().name, base().chainId, previous, 1, VALUE_TYPE_HASH, configBinding("", value)
            )
        );
        (bytes memory boundValue, uint256 registeredAt,) = registry.getV4(AUTHORITY, name);
        assertEq(boundValue, value);
        assertEq(registeredAt, 2);
    }

    /// A value that differs from the bound one only past its first word, or
    /// only in length, is a different value and is re-bound: the comparison is
    /// of the whole value.
    function testRegisterRebindsNearMisses() external {
        bytes32 name = keccak256("a.b");
        IConfigRegistryV4 registry = deployRegistry();
        bytes memory previous = abi.encode(uint256(1), uint256(2));
        bytes[3] memory nearMisses = [
            abi.encode(uint256(1), uint256(3)), abi.encode(uint256(1)), abi.encode(uint256(1), uint256(2), uint256(0))
        ];
        for (uint256 i = 0; i < nearMisses.length; i++) {
            vm.warp(2 * i + 1);
            vm.prank(AUTHORITY);
            registry.registerV4(AUTHORITY, name, VALUE_TYPE, previous, "");
            vm.warp(2 * i + 2);

            (bool broadcast,) = this.externalRegisterOnSelectedChain(base(), AUTHORITY, AUTHORITY, name, nearMisses[i]);
            assertTrue(broadcast);
            assertEq(LibConfigRegistryRead.getValue(registry, AUTHORITY, name), nearMisses[i]);
        }
    }

    /// A name already bound to the value is skipped: nothing is broadcast, so
    /// the moment stays the original bind's.
    function testRegisterSkipsSameBinding(bytes32 name, bytes memory value) external {
        vm.assume(value.length > 0);
        IConfigRegistryV4 registry = deployRegistry();
        vm.warp(1);
        vm.prank(AUTHORITY);
        registry.registerV4(AUTHORITY, name, VALUE_TYPE, value, "");
        vm.warp(2);

        (bool broadcast, string memory record) =
            this.externalRegisterOnSelectedChain(base(), AUTHORITY, AUTHORITY, name, value);
        assertFalse(broadcast);
        assertEq(
            record,
            LibConfigRegistryRegister.describeNetwork(
                vm, base().name, base().chainId, value, 1, VALUE_TYPE_HASH, configBinding("", value)
            )
        );
        (bytes memory boundValue, uint256 registeredAt,) = registry.getV4(AUTHORITY, name);
        assertEq(boundValue, value);
        assertEq(registeredAt, 1);
    }

    /// An unbound name reads as an empty value and a zero moment; a bound one
    /// as its binding.
    function testCurrentBinding(bytes32 name, bytes32 other, bytes memory value) external {
        vm.assume(value.length > 0);
        vm.assume(name != other);
        IConfigRegistryV4 registry = deployRegistry();
        (bytes memory boundValue, uint256 registeredAt, bytes32 boundTypeHash) =
            LibConfigRegistryRegister.currentBinding(AUTHORITY, name);
        assertEq(boundValue, "");
        assertEq(registeredAt, 0);
        assertEq(boundTypeHash, bytes32(0));

        vm.warp(7);
        vm.prank(AUTHORITY);
        registry.registerV4(AUTHORITY, name, VALUE_TYPE, value, "");
        (boundValue, registeredAt, boundTypeHash) = LibConfigRegistryRegister.currentBinding(AUTHORITY, name);
        assertEq(boundValue, value);
        assertEq(registeredAt, 7);
        assertEq(boundTypeHash, VALUE_TYPE_HASH);
        (boundValue, registeredAt, boundTypeHash) = LibConfigRegistryRegister.currentBinding(AUTHORITY, other);
        assertEq(boundValue, "");
        assertEq(registeredAt, 0);
        assertEq(boundTypeHash, bytes32(0));
    }

    /// Only the registry's `NameNotRegistered` for THIS authority and name
    /// reads as unbound. Any other revert — for another name, another
    /// authority, or anything else — is re-raised as it was.
    function testCurrentBindingReraisesOtherReverts(bytes32 name, bytes32 other, address otherAuthority) external {
        vm.assume(name != other);
        vm.assume(otherAuthority != AUTHORITY);
        bytes memory otherAuthorityName =
            abi.encodeWithSelector(IConfigRegistryV4.NameNotRegistered.selector, otherAuthority, name);
        deployCodeTo(
            "MockRevertingRegistry.sol",
            abi.encode(otherAuthorityName),
            LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS
        );
        vm.expectRevert(otherAuthorityName);
        this.externalCurrentBinding(name);

        bytes memory otherName = abi.encodeWithSelector(IConfigRegistryV4.NameNotRegistered.selector, AUTHORITY, other);
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

        bytes memory thisName = abi.encodeWithSelector(IConfigRegistryV4.NameNotRegistered.selector, AUTHORITY, name);
        deployCodeTo(
            "MockRevertingRegistry.sol", abi.encode(thisName), LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS
        );
        (bytes memory boundValue, uint256 registeredAt, bytes32 boundTypeHash) = this.externalCurrentBinding(name);
        assertEq(boundValue, "");
        assertEq(registeredAt, 0);
        assertEq(boundTypeHash, bytes32(0));
    }

    /// The bind's calldata is `registerV4(address,bytes32,string,bytes,bytes)`
    /// — selector `0x41f0fc94`, from `cast sig` — over the authority, the name
    /// hash, then the offsets of the value type, the value and the empty meta,
    /// then each dynamic argument's length and its bytes right-padded to a
    /// word. It is exactly the call the bind makes.
    function testRegisterCalldataIsTheCallSent(bytes32 name, bytes memory value) external {
        vm.assume(value.length > 0);
        uint256 paddedValueLength = value.length + (32 - value.length % 32) % 32;
        bytes memory expected = abi.encodePacked(
            bytes4(0x41f0fc94),
            uint256(uint160(AUTHORITY)),
            name,
            uint256(0xa0),
            uint256(0xe0),
            uint256(0x100 + paddedValueLength),
            uint256(7),
            bytes.concat(bytes("address"), new bytes(25)),
            uint256(value.length),
            value,
            new bytes(paddedValueLength - value.length),
            uint256(0)
        );
        assertEq(LibConfigRegistryRegister.registerCalldata(AUTHORITY, name, configBinding("", value)), expected);

        deployRegistry();
        vm.warp(1);
        vm.expectCall(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS, expected, 1);
        this.externalRegisterOnSelectedChain(base(), AUTHORITY, AUTHORITY, name, value);
    }

    /// The inputs record, field for field, for st0x's token-owner Safe bound
    /// to `0x…dEaD`. The hash, value and calldata are
    /// `cast keccak st0x.token-owner-safe`,
    /// `cast abi-encode "f(address)" 0x…dEaD` and
    /// `cast calldata "registerV4(address,bytes32,string,bytes,bytes)" <authority> <hash> address <value> 0x`;
    /// the type hash is `cast keccak address`.
    function testDescribeInputs() external pure {
        assertEq(
            LibConfigRegistryRegister.describeInputs(
                vm, configBinding("st0x.token-owner-safe", abi.encode(address(0xdEaD))), address(0xB0B), AUTHORITY
            ),
            string.concat(
                "Name: st0x.token-owner-safe\n",
                "Name hash (keccak256 of the name): 0xba1ec70c388d07ed204e3cfdcbdc2564f9aa2e5b310aeae3767c61a68306cfc8\n",
                "Value type: address\n",
                "Value type hash (keccak256 of the value type): 0x421683f821a0574472445355be6d2b769119e8515f8376a1d7878523dfdecf7b\n",
                "Value: 0x000000000000000000000000000000000000000000000000000000000000dead\n",
                "Meta: 0x\n",
                "Authority: ",
                vm.toString(AUTHORITY),
                "\n",
                "Sender: ",
                vm.toString(address(0xB0B)),
                "\n",
                "Registry: ",
                vm.toString(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS),
                "\n",
                "Calldata: 0x41f0fc94",
                "00000000000000000000000000000000000000000000000000000000000a11ce",
                "ba1ec70c388d07ed204e3cfdcbdc2564f9aa2e5b310aeae3767c61a68306cfc8",
                "00000000000000000000000000000000000000000000000000000000000000a0",
                "00000000000000000000000000000000000000000000000000000000000000e0",
                "0000000000000000000000000000000000000000000000000000000000000120",
                "0000000000000000000000000000000000000000000000000000000000000007",
                "6164647265737300000000000000000000000000000000000000000000000000",
                "0000000000000000000000000000000000000000000000000000000000000020",
                "000000000000000000000000000000000000000000000000000000000000dead",
                "0000000000000000000000000000000000000000000000000000000000000000"
            )
        );
    }

    /// The inputs record refuses a non-canonical name, as the bind does.
    function testDescribeInputsRefusesNonCanonicalName() external {
        vm.expectRevert(abi.encodeWithSelector(LibConfigRegistryRegister.NonCanonicalName.selector, "A"));
        this.externalDescribeInputs("A");
    }

    function externalDescribeInputs(string memory name) external pure returns (string memory) {
        return LibConfigRegistryRegister.describeInputs(
            vm, configBinding(name, abi.encode(address(0xdEaD))), AUTHORITY, AUTHORITY
        );
    }

    /// An unbound name is a BIND.
    function testDescribeNetworkUnbound() external pure {
        assertEq(
            LibConfigRegistryRegister.describeNetwork(
                vm, "base", 8453, "", 0, bytes32(0), configBinding("", hex"dead")
            ),
            "Network: base\n  chain id: 8453\n  current: unbound\n  BIND: -> 0xdead as address"
        );
    }

    /// A name bound elsewhere is a REBIND, showing the old binding and when it
    /// was made.
    function testDescribeNetworkRebind() external pure {
        assertEq(
            LibConfigRegistryRegister.describeNetwork(
                vm, "arbitrum", 42161, hex"0b30", 7, VALUE_TYPE_HASH, configBinding("", hex"dead")
            ),
            string.concat(
                "Network: arbitrum\n  chain id: 42161\n",
                "  current: 0x0b30 (type hash 0x421683f821a0574472445355be6d2b769119e8515f8376a1d7878523dfdecf7b, bound at 7)\n",
                "  REBIND: -> 0xdead as address"
            )
        );
    }

    /// A name bound to the value already is a SKIP.
    function testDescribeNetworkSkip() external pure {
        assertEq(
            LibConfigRegistryRegister.describeNetwork(
                vm, "flare", 14, hex"dead", 7, VALUE_TYPE_HASH, configBinding("", hex"dead")
            ),
            string.concat(
                "Network: flare\n  chain id: 14\n",
                "  current: 0xdead (type hash 0x421683f821a0574472445355be6d2b769119e8515f8376a1d7878523dfdecf7b, bound at 7)\n",
                "  SKIP: already bound to 0xdead as address"
            )
        );
    }

    /// A bound value that differs from the one to bind only in length is a
    /// REBIND, not a SKIP.
    function testDescribeNetworkLengthMismatchIsRebind() external pure {
        assertEq(
            LibConfigRegistryRegister.describeNetwork(
                vm, "flare", 14, hex"dead00", 7, VALUE_TYPE_HASH, configBinding("", hex"dead")
            ),
            string.concat(
                "Network: flare\n  chain id: 14\n",
                "  current: 0xdead00 (type hash 0x421683f821a0574472445355be6d2b769119e8515f8376a1d7878523dfdecf7b, bound at 7)\n",
                "  REBIND: -> 0xdead as address"
            )
        );
    }

    function externalRegisterBinding(bytes32 name, ConfigBinding memory binding)
        external
        returns (bool, string memory)
    {
        return LibConfigRegistryRegister.registerOnSelectedChain(vm, base(), AUTHORITY, AUTHORITY, name, binding);
    }

    /// A bound value that differs from the one to bind only in type is a
    /// REBIND, not a SKIP.
    function testDescribeNetworkTypeMismatchIsRebind() external pure {
        assertEq(
            LibConfigRegistryRegister.describeNetwork(
                vm, "flare", 14, hex"dead", 7, keccak256("uint256"), configBinding("", hex"dead")
            ),
            string.concat(
                "Network: flare\n  chain id: 14\n  current: 0xdead (type hash ",
                vm.toString(keccak256("uint256")),
                ", bound at 7)\n  REBIND: -> 0xdead as address"
            )
        );
    }

    /// A name bound to the value as another type is re-bound as the new type.
    function testRegisterRebindsOnTypeOnlyChange(bytes32 name, bytes memory value) external {
        vm.assume(value.length > 0);
        IConfigRegistryV4 registry = deployRegistry();
        vm.warp(1);
        vm.prank(AUTHORITY);
        registry.registerV4(AUTHORITY, name, "uint256", value, "");
        vm.warp(2);

        (bool broadcast,) = this.externalRegisterBinding(name, configBinding("", value));
        assertTrue(broadcast);
        (bytes memory boundValue, uint256 registeredAt, bytes32 boundTypeHash) = registry.getV4(AUTHORITY, name);
        assertEq(boundValue, value);
        assertEq(registeredAt, 2);
        assertEq(boundTypeHash, VALUE_TYPE_HASH);
    }

    /// The binding's meta is sent with the bind, as `MetaV1_2` about the
    /// authority's name.
    function testRegisterSendsMeta(bytes32 name, bytes memory value, bytes memory meta) external {
        vm.assume(value.length > 0 && meta.length > 0);
        IConfigRegistryV4 registry = deployRegistry();
        vm.warp(1);
        ConfigBinding memory binding = configBinding("", value);
        binding.meta = meta;
        vm.recordLogs();
        (bool broadcast,) = this.externalRegisterBinding(name, binding);
        assertTrue(broadcast);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256 metas = 0;
        for (uint256 i = 0; i < entries.length; i++) {
            if (
                entries[i].emitter == address(registry)
                    && entries[i].topics[0] == keccak256("MetaV1_2(address,bytes32,bytes)")
            ) {
                metas++;
                assertEq(entries[i].data, abi.encode(AUTHORITY, keccak256(abi.encode(AUTHORITY, name)), meta));
            }
        }
        assertEq(metas, 1);
    }

    /// A skip sends nothing, so its meta is not emitted.
    function testRegisterSkipSendsNoMeta(bytes32 name, bytes memory value, bytes memory meta) external {
        vm.assume(value.length > 0 && meta.length > 0);
        IConfigRegistryV4 registry = deployRegistry();
        vm.warp(1);
        vm.prank(AUTHORITY);
        registry.registerV4(AUTHORITY, name, VALUE_TYPE, value, "");
        vm.warp(2);
        ConfigBinding memory binding = configBinding("", value);
        binding.meta = meta;
        vm.recordLogs();
        (bool broadcast,) = this.externalRegisterBinding(name, binding);
        assertFalse(broadcast);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        for (uint256 i = 0; i < entries.length; i++) {
            assertTrue(entries[i].emitter != address(registry));
        }
    }
}
