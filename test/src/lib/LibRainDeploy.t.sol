// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibRainDeployTestBase} from "../../abstract/LibRainDeployTestBase.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {IAddressRegistryV1} from "../../../src/interface/IAddressRegistryV1.sol";
import {ADDRESS_REGISTRY_ROOT} from "../../../src/concrete/AddressRegistry.sol";
import {MockAddressRevertingFactory} from "../../concrete/MockAddressRevertingFactory.sol";
import {MockResolvedOwner} from "../../concrete/MockResolvedOwner.sol";
import {MockDirtyWordOwner} from "../../concrete/MockDirtyWordOwner.sol";
import {MockDeployable} from "../../concrete/MockDeployable.sol";
import {MockReverter} from "../../concrete/MockReverter.sol";

/// @title LibRainDeployTest
/// The `LibRainDeploy` tests that read no chain state, and therefore fork
/// nothing. Every one of them either touches no address the chain would supply,
/// or etches the whole of what it touches — so a fork would only slow it down
/// and tie it to an RPC endpoint being up.
///
/// The name deliberately has no `Chain` in it: this contract is what
/// `forge test --no-match-contract Chain` runs, and it MUST stay runnable with
/// no `.env` at all. A test added here that needs a chain belongs in
/// `LibRainDeployChainTest` instead.
contract LibRainDeployTest is LibRainDeployTestBase {
    /// The address the Zoltu factory derives for empty creation code, i.e.
    /// CREATE2 over the factory address, a zero salt and the hash of empty
    /// creation code. An account is created there but it has no code.
    address constant ZOLTU_EMPTY_CREATION_CODE_ADDRESS = 0x5DC93B79FBDD6f26Ed9540597C78eD5893F9aC7A;

    /// `findDeployBlock` MUST revert with `NotDeployed` when the target
    /// address has no code. The guard runs before the search does, so no fork
    /// history is read to reach it.
    function testFindDeployBlockNotDeployedReverts() external {
        assertEq(address(0xdead).code.length, 0);
        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.NotDeployed.selector, address(0xdead)));
        this.externalFindDeployBlock(address(0xdead), bytes32(0), 0);
    }

    /// `findDeployBlock` MUST revert with `UnexpectedDeployedCodeHash` when
    /// the target's code hash does not match the expected value. Also runs
    /// before the search, so the factory is etched rather than forked to: what
    /// the etched code hash is on a real network is
    /// `LibRainDeployChainTest.testZoltuFactoryCodehash`'s subject, not this
    /// one's.
    function testFindDeployBlockWrongCodeHashReverts() external {
        LibRainDeploy.etchZoltuFactory(vm);
        bytes32 wrongHash = bytes32(uint256(1));
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.UnexpectedDeployedCodeHash.selector, wrongHash, LibRainDeploy.ZOLTU_FACTORY_CODEHASH
            )
        );
        this.externalFindDeployBlock(LibRainDeploy.ZOLTU_FACTORY, wrongHash, 0);
    }

    /// `supportedNetworks` MUST return exactly 5 networks in the expected
    /// order matching the library constants.
    function testSupportedNetworks() external pure {
        string[] memory networks = LibRainDeploy.supportedNetworks();
        assertEq(networks.length, 5);
        assertEq(networks[0], LibRainDeploy.ARBITRUM_ONE);
        assertEq(networks[1], LibRainDeploy.BASE);
        assertEq(networks[2], LibRainDeploy.BASE_SEPOLIA);
        assertEq(networks[3], LibRainDeploy.FLARE);
        assertEq(networks[4], LibRainDeploy.POLYGON);
    }

    /// `etchZoltuFactory` MUST place the correct bytecode and codehash at the
    /// Zoltu factory address.
    function testEtchZoltuFactory() external {
        assertEq(LibRainDeploy.ZOLTU_FACTORY.code.length, 0);
        LibRainDeploy.etchZoltuFactory(vm);
        assertEq(LibRainDeploy.ZOLTU_FACTORY.code, LibRainDeploy.ZOLTU_FACTORY_BYTECODE);
        assertEq(LibRainDeploy.ZOLTU_FACTORY.codehash, LibRainDeploy.ZOLTU_FACTORY_CODEHASH);
    }

    /// Empty networks array MUST revert with `NoNetworks`.
    function testNoNetworksReverts() external {
        string[] memory networks = new string[](0);
        address[] memory dependencies = new address[](0);
        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.NoNetworks.selector));
        this.externalDeployAndBroadcast(networks, 1, hex"", "", address(0), bytes32(0), dependencies);
    }

    /// `deployToNetworks` MUST revert with `NoNetworks` when given an empty
    /// networks array, before any other input is checked.
    function testDeployToNetworksNoNetworksReverts() external {
        string[] memory networks = new string[](0);
        address[] memory dependencies = new address[](0);
        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.NoNetworks.selector));
        this.externalDeployToNetworks(networks, address(this), hex"", "", address(0), bytes32(0), dependencies);
    }

    /// `deployZoltu` MUST revert with `DeployFailed` when the Zoltu factory
    /// has no code.
    function testDeployZoltuRevertsNoFactory() external {
        // The precondition, stated rather than arranged: nothing has etched the
        // factory, so a call to it succeeds and returns nothing.
        assertEq(LibRainDeploy.ZOLTU_FACTORY.code.length, 0);
        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.DeployFailed.selector, true, address(0)));
        this.externalDeployZoltu(type(MockDeployable).creationCode);
    }

    /// `deployZoltu` MUST revert with `DeployFailed` when the creation code
    /// has a reverting constructor (success=false from factory call).
    function testDeployZoltuRevertsRevertingConstructor() external {
        LibRainDeploy.etchZoltuFactory(vm);
        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.DeployFailed.selector, false, address(0)));
        this.externalDeployZoltu(type(MockReverter).creationCode);
    }

    /// `deployZoltu` MUST report the zero address when the factory call fails,
    /// even when the factory reverts with data that reads as an address. The
    /// call output buffer holds revert data on the failure path, so anything
    /// read from it there is not an address the factory returned.
    function testDeployZoltuFailedCallReportsZeroAddress() external {
        vm.etch(LibRainDeploy.ZOLTU_FACTORY, address(new MockAddressRevertingFactory()).code);

        // The discriminating power of this test is entirely the shape of the
        // fixture's revert data: a failing call returning the twenty bytes of
        // an address that has code. Asserted rather than assumed, because a
        // fixture that reverted with fewer than twenty bytes would leave the
        // pre-zeroed output buffer reading as the zero address, and the
        // assertion below would then hold whether or not the failure path
        // reads that buffer.
        (bool factorySuccess, bytes memory factoryRevertData) = LibRainDeploy.ZOLTU_FACTORY.call("");
        assertFalse(factorySuccess);
        assertEq(factoryRevertData, abi.encodePacked(bytes20(LibRainDeploy.ZOLTU_FACTORY)));
        assertGt(LibRainDeploy.ZOLTU_FACTORY.code.length, 0);

        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.DeployFailed.selector, false, address(0)));
        this.externalDeployZoltu(type(MockDeployable).creationCode);
    }

    /// `deployToNetworks` MUST revert with `UnexpectedDeployedAddress` when the
    /// creation code does not deploy to the expected address.
    function testUnexpectedDeployedAddressReverts() external {
        string[] memory networks = new string[](1);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;
        address[] memory dependencies = new address[](0);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.UnexpectedDeployedAddress.selector, address(0xdead), mockDeployableAddress()
            )
        );
        this.externalDeployToNetworks(
            networks, address(this), type(MockDeployable).creationCode, "", address(0xdead), bytes32(0), dependencies
        );
    }

    /// `deployToNetworks` MUST check `expectedAddress` against the creation
    /// code before it forks anything, so the mismatch is reported without any
    /// network being reachable at all.
    function testDeployToNetworksStaleExpectedAddressRevertsBeforeForking() external {
        string[] memory networks = new string[](1);
        // Not a configured RPC alias, so forking it is itself an error.
        networks[0] = "unconfigured_network";
        address[] memory dependencies = new address[](0);

        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.UnexpectedDeployedAddress.selector, address(0xdead), mockDeployableAddress()
            )
        );
        this.externalDeployToNetworks(
            networks, address(this), type(MockDeployable).creationCode, "", address(0xdead), bytes32(0), dependencies
        );
    }

    /// `checkResolvedAddresses` MUST pass when the deployed contract holds the
    /// address the deployment expects.
    function testCheckResolvedAddressesMatch(bytes32 name, address account) external {
        vm.assume(account != address(0));
        (, MockResolvedOwner consumer) = deployRegistryAndConsumer(name, account);

        LibRainDeploy.checkResolvedAddresses("test_network", address(consumer), ownerReadCalls(), expected(account));
    }

    /// The check is against settled state, which is the entire point of running
    /// it after the deploy rather than before. Re-binding the name afterwards
    /// changes what the registry answers but cannot change what the deployed
    /// contract holds, so the check still passes against the address the
    /// deployment actually took.
    function testCheckResolvedAddressesUnaffectedByRebinding(bytes32 name, address account, address rebound) external {
        vm.assume(account != address(0));
        vm.assume(rebound != address(0));
        vm.assume(rebound != account);
        (IAddressRegistryV1 registry, MockResolvedOwner consumer) = deployRegistryAndConsumer(name, account);

        vm.prank(ADDRESS_REGISTRY_ROOT);
        registry.register(name, rebound);
        assertEq(registry.get(name), rebound);

        assertEq(consumer.iOwner(), account);
        LibRainDeploy.checkResolvedAddresses("test_network", address(consumer), ownerReadCalls(), expected(account));

        // And the value the registry now answers with is NOT what this
        // deployment holds, so a check against it fails.
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.UnexpectedResolvedAddress.selector,
                "test_network",
                address(consumer),
                uint256(0),
                rebound,
                account
            )
        );
        this.externalCheckResolvedAddresses("test_network", address(consumer), ownerReadCalls(), expected(rebound));
    }

    /// `checkResolvedAddresses` MUST revert with `UnexpectedResolvedAddress`
    /// when the deployed contract holds something else, naming the network and
    /// which read disagreed.
    function testCheckResolvedAddressesMismatchReverts(bytes32 name, address account, address wrong) external {
        vm.assume(account != address(0));
        vm.assume(wrong != account);
        (, MockResolvedOwner consumer) = deployRegistryAndConsumer(name, account);

        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.UnexpectedResolvedAddress.selector,
                "test_network",
                address(consumer),
                uint256(0),
                wrong,
                account
            )
        );
        this.externalCheckResolvedAddresses("test_network", address(consumer), ownerReadCalls(), expected(wrong));
    }

    /// `checkResolvedAddresses` MUST check every read, not only the first, so a
    /// later value that disagrees is still caught.
    function testCheckResolvedAddressesChecksEveryRead(bytes32 name, address account, address wrong) external {
        vm.assume(account != address(0));
        vm.assume(wrong != account);
        (, MockResolvedOwner consumer) = deployRegistryAndConsumer(name, account);

        bytes[] memory readCalls = new bytes[](2);
        readCalls[0] = abi.encodeWithSignature("iOwner()");
        readCalls[1] = abi.encodeWithSignature("iOwner()");
        address[] memory expectedAddresses = new address[](2);
        expectedAddresses[0] = account;
        expectedAddresses[1] = wrong;

        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.UnexpectedResolvedAddress.selector,
                "test_network",
                address(consumer),
                uint256(1),
                wrong,
                account
            )
        );
        this.externalCheckResolvedAddresses("test_network", address(consumer), readCalls, expectedAddresses);
    }

    /// A read that cannot be answered is never a pass. An address with no code
    /// static-calls successfully and returns nothing, which would compare equal
    /// to nothing at all if the length were not checked.
    function testCheckResolvedAddressesUnreadableTargetReverts(address target, address account) external {
        vm.assume(target.code.length == 0);
        // The low address space is reserved for precompiles, which have no code
        // and yet DO answer — the identity precompile echoes its calldata back,
        // so a read of one returns data rather than nothing. They are not
        // instances of the case under test. Bounded by the reserved range rather
        // than by listing today's precompiles, so a chain or fork that adds one
        // does not reintroduce this.
        vm.assume(uint160(target) > 0xffff);

        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.ResolvedAddressReadFailed.selector, "test_network", target, uint256(0), bytes("")
            )
        );
        this.externalCheckResolvedAddresses("test_network", target, ownerReadCalls(), expected(account));
    }

    /// A read that reverts is never a pass either.
    function testCheckResolvedAddressesRevertingReadReverts(bytes32 name, address account) external {
        vm.assume(account != address(0));
        (, MockResolvedOwner consumer) = deployRegistryAndConsumer(name, account);

        bytes[] memory readCalls = new bytes[](1);
        readCalls[0] = abi.encodeWithSignature("thisFunctionDoesNotExist()");

        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.ResolvedAddressReadFailed.selector,
                "test_network",
                address(consumer),
                uint256(0),
                bytes("")
            )
        );
        this.externalCheckResolvedAddresses("test_network", address(consumer), readCalls, expected(account));
    }

    /// A read that answers with one word whose upper 96 bits are dirty has not
    /// answered with an address, and MUST be reported as
    /// `ResolvedAddressReadFailed` — the error whose stated subject is a read
    /// that answers with something that is not a single address-sized word.
    ///
    /// The expected address here is the word's own low 160 bits, so the only
    /// thing wrong with the answer is the dirty bits. That rules out both ways
    /// of getting this wrong at once: truncating the word silently PASSES this
    /// check against an address the read never gave, and decoding it as an
    /// address reverts inside the decoder with no return data at all — a bare
    /// revert naming neither the network, the target, nor which read produced
    /// it, which is exactly what this error exists to avoid.
    function testCheckResolvedAddressesDirtyWordReverts(bytes32 word) external {
        // Only the words that are not an address. A clean one is an address and
        // decodes, which is `testCheckResolvedAddressesMatch`'s case.
        vm.assume(uint256(word) > type(uint160).max);
        MockDirtyWordOwner target = new MockDirtyWordOwner(word);

        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.ResolvedAddressReadFailed.selector,
                "test_network",
                address(target),
                uint256(0),
                abi.encode(word)
            )
        );
        this.externalCheckResolvedAddresses(
            "test_network", address(target), ownerReadCalls(), expected(address(uint160(uint256(word))))
        );
    }

    /// `checkResolvedAddresses` MUST revert when the reads and expected
    /// addresses do not pair up, rather than checking the shorter of the two.
    function testCheckResolvedAddressesLengthMismatchReverts(uint8 readCallsLength, uint8 expectedLength) external {
        vm.assume(readCallsLength != expectedLength);

        bytes[] memory readCalls = new bytes[](readCallsLength);
        address[] memory expectedAddresses = new address[](expectedLength);

        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.ResolvedAddressesLengthMismatch.selector,
                uint256(readCallsLength),
                uint256(expectedLength)
            )
        );
        this.externalCheckResolvedAddresses("test_network", address(this), readCalls, expectedAddresses);
    }

    /// `checkResolvedAddressesOnNetworks` MUST revert with `NoNetworks` when
    /// given none, so an empty target set can never be mistaken for every read
    /// checking out.
    function testCheckResolvedAddressesOnNetworksNoNetworksReverts(address account) external {
        string[] memory networks = new string[](0);

        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.NoNetworks.selector));
        this.externalCheckResolvedAddressesOnNetworks(networks, address(this), ownerReadCalls(), expected(account));
    }

    /// `checkResolvedAddressesOnNetworks` MUST check the reads and expected
    /// addresses pair up before it forks anything, so a mispaired call is
    /// reported without any network being reachable at all.
    function testCheckResolvedAddressesOnNetworksLengthMismatchRevertsBeforeForking() external {
        string[] memory networks = new string[](1);
        // Not a configured RPC alias, so forking it is itself an error.
        networks[0] = "unconfigured_network";
        bytes[] memory readCalls = new bytes[](2);
        address[] memory expectedAddresses = new address[](1);

        vm.expectRevert(
            abi.encodeWithSelector(LibRainDeploy.ResolvedAddressesLengthMismatch.selector, uint256(2), uint256(1))
        );
        this.externalCheckResolvedAddressesOnNetworks(networks, address(this), readCalls, expectedAddresses);
    }

    /// `deployZoltu` MUST revert when the factory call succeeds but leaves no
    /// code at the resulting address. Empty creation code creates an account
    /// with no runtime code, which is not a deployment.
    function testDeployZoltuRevertsEmptyCreationCode() external {
        LibRainDeploy.etchZoltuFactory(vm);
        vm.expectRevert(
            abi.encodeWithSelector(LibRainDeploy.DeployFailed.selector, true, ZOLTU_EMPTY_CREATION_CODE_ADDRESS)
        );
        this.externalDeployZoltu(hex"");
    }

    /// `deployZoltu` MUST NOT report the zero address as a deployment, even
    /// when the zero address has code.
    function testDeployZoltuRevertsZeroAddressWithCode() external {
        // A call to an address with no code succeeds and returns nothing, so
        // the factory yields the zero address.
        assertEq(LibRainDeploy.ZOLTU_FACTORY.code.length, 0);
        vm.etch(address(0), hex"00");
        assertGt(address(0).code.length, 0);

        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.DeployFailed.selector, true, address(0)));
        this.externalDeployZoltu(type(MockDeployable).creationCode);
    }

    /// `deployZoltu` MUST NOT forward the caller's value to the factory. The
    /// deployed mock has a non payable constructor, so forwarded value would
    /// fail the deployment outright.
    function testDeployZoltuDoesNotForwardValue() external {
        LibRainDeploy.etchZoltuFactory(vm);
        vm.deal(address(this), 1 ether);
        address deployed = this.externalDeployZoltuPayable{value: 1}(type(MockDeployable).creationCode);
        assertEq(deployed, mockDeployableAddress());
        assertEq(deployed.balance, 0);
        assertEq(LibRainDeploy.ZOLTU_FACTORY.balance, 0);
    }
}
