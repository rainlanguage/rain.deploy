// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {DeploySuite, ExtendedNetworksUnexpected} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {ChainDeploy, LibRainDeployExtendedNetworks} from "../../../src/lib/LibRainDeployExtendedNetworks.sol";
import {
    MOCK_CREATE2_FACTORY,
    MOCK_CREATE2_SALT,
    MockCreate2Mechanism,
    MockCreate2NetworkUndeclared,
    MockCreate2NetworkUnfrozen
} from "../../abstract/MockCreate2DeploySuites.sol";
import {MockCreate2Deploy} from "../../concrete/MockCreate2Deploy.sol";
import {MockCreate2Factory} from "../../concrete/MockCreate2Factory.sol";
import {MockDeployable} from "../../concrete/MockDeployable.sol";
import {LocalForkVm} from "../../concrete/LocalForkVm.sol";

/// @title RainDeploySuitesBaseMockMechanismTest
/// @notice Every hook dispatches to an overriding mechanism, and the base helpers read through the hooks.
contract RainDeploySuitesBaseMockMechanismTest is Test {
    event MockCreate2Verification(string[] networks, string suite, address[] deployed);

    MockCreate2Deploy internal sDeploy;

    function setUp() external {
        sDeploy = new MockCreate2Deploy();
    }

    function create2Address(bytes32 salt) internal pure returns (address) {
        return address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff), MOCK_CREATE2_FACTORY, salt, keccak256(type(MockDeployable).creationCode)
                        )
                    )
                )
            )
        );
    }

    function networkAddress(uint256 chainId) internal pure returns (address) {
        return create2Address(keccak256(abi.encode(MOCK_CREATE2_SALT, abi.encode(chainId))));
    }

    function network(uint256 chainId, address recorded) internal pure returns (ChainDeploy memory) {
        return ChainDeploy({chainId: chainId, data: abi.encode(chainId), deployedAddress: recorded});
    }

    function mechanismOf(DeploySuite memory suite) internal pure returns (MockCreate2Mechanism memory) {
        return abi.decode(suite.mechanismData, (MockCreate2Mechanism));
    }

    function withNetworks(DeploySuite memory suite, ChainDeploy[] memory networks)
        internal
        pure
        returns (DeploySuite memory)
    {
        MockCreate2Mechanism memory mechanism = mechanismOf(suite);
        mechanism.networks = networks;
        suite.mechanismData = abi.encode(mechanism);
        return suite;
    }

    /// The release with the empty network list: one address on every network.
    function singleSuite() internal view returns (DeploySuite memory) {
        DeploySuite memory suite = withNetworks(sDeploy.externalMockRelease(), new ChainDeploy[](0));
        suite.storedDeployedAddress = create2Address(MOCK_CREATE2_SALT);
        return suite;
    }

    function arbitrumAndPolygon() internal pure returns (string[] memory) {
        string[] memory networks = new string[](2);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;
        networks[1] = LibRainDeploy.POLYGON;
        return networks;
    }

    function testDeployedAddressIsTheMechanismsPerNetwork() external view {
        DeploySuite memory release = sDeploy.externalMockRelease();
        assertEq(sDeploy.externalDeployedAddress(release, 42161), networkAddress(42161));
        assertEq(sDeploy.externalDeployedAddress(release, 137), networkAddress(137));
        assertTrue(networkAddress(42161) != networkAddress(137));
        assertTrue(networkAddress(42161) != LibRainDeploy.zoltuAddress(type(MockDeployable).creationCode));
    }

    function testDeployedAddressRefusesANetworkTheMechanismLacks() external {
        DeploySuite memory release = sDeploy.externalMockRelease();
        vm.expectRevert(abi.encodeWithSelector(MockCreate2NetworkUndeclared.selector, release.suite, uint256(8453)));
        sDeploy.externalDeployedAddress(release, 8453);
    }

    function testEmptyMechanismDataFallsThroughToZoltu() external view {
        DeploySuite memory suite = sDeploy.externalMockRelease();
        suite.mechanismData = "";
        suite.storedDeployedAddress = address(0x1234);
        assertEq(sDeploy.externalDeployedAddress(suite, 42161), LibRainDeploy.zoltuAddress(suite.creationCode));
        assertEq(sDeploy.externalRecordedAddress(suite, 42161), address(0x1234));
        assertEq(sDeploy.externalAddressChainIds(suite).length, 0);
        assertEq(sDeploy.externalDeployStepData(suite, 42161), suite.creationCode);
        assertEq(sDeploy.externalSuiteBeacon(suite, 42161), address(0));
    }

    /// `deployedAddresses` and `recordedAddresses` are one entry per `addressChainIds` entry, in its order, each read
    /// through its own hook.
    function testAddressListsFollowTheChainIdOrder() external view {
        ChainDeploy[] memory networks = new ChainDeploy[](3);
        networks[0] = network(137, address(0xa1));
        networks[1] = network(8453, address(0xa2));
        networks[2] = network(42161, address(0xa3));
        DeploySuite memory suite = withNetworks(sDeploy.externalMockRelease(), networks);

        uint256[] memory chainIds = sDeploy.externalAddressChainIds(suite);
        address[] memory deployed = sDeploy.externalDeployedAddresses(suite);
        address[] memory recorded = sDeploy.externalRecordedAddresses(suite);
        assertEq(chainIds.length, 3);
        assertEq(deployed.length, 3);
        assertEq(recorded.length, 3);
        for (uint256 i = 0; i < 3; i++) {
            assertEq(chainIds[i], networks[i].chainId);
            assertEq(deployed[i], networkAddress(networks[i].chainId));
            assertEq(recorded[i], networks[i].deployedAddress);
        }
    }

    /// A suite with no address chain ids has one address, read at chain id zero.
    function testAddressListsOfASingleAddressSuiteHaveOneEntry() external view {
        DeploySuite memory suite = singleSuite();
        suite.storedDeployedAddress = address(0xb1);
        address[] memory deployed = sDeploy.externalDeployedAddresses(suite);
        address[] memory recorded = sDeploy.externalRecordedAddresses(suite);
        assertEq(deployed.length, 1);
        assertEq(deployed[0], create2Address(MOCK_CREATE2_SALT));
        assertEq(recorded.length, 1);
        assertEq(recorded[0], address(0xb1));
    }

    function testRecordedAddressIsTheMechanismsPerNetwork() external view {
        ChainDeploy[] memory networks = new ChainDeploy[](1);
        networks[0] = network(42161, address(0xc1));
        DeploySuite memory suite = withNetworks(sDeploy.externalMockRelease(), networks);
        assertEq(sDeploy.externalRecordedAddress(suite, 42161), address(0xc1));
    }

    function testDeployStepRunsTheMechanismsStepWithItsData() external {
        vm.etch(MOCK_CREATE2_FACTORY, type(MockCreate2Factory).runtimeCode);
        DeploySuite memory release = sDeploy.externalMockRelease();
        bytes memory data = sDeploy.externalDeployStepData(release, 137);
        assertEq(
            data,
            abi.encode(
                MOCK_CREATE2_FACTORY, keccak256(abi.encode(MOCK_CREATE2_SALT, abi.encode(uint256(137)))), release.creationCode
            )
        );
        LocalForkVm forkVm = new LocalForkVm();
        address deployed =
            sDeploy.externalRunDeployStep(Vm(address(forkVm)), release, LibRainDeploy.POLYGON, address(this), data);
        assertEq(deployed, networkAddress(137));
        assertEq(MockDeployable(deployed).sValue(), 42);
    }

    function testDeployLocallyDeploysEveryNetworksAddress() external {
        DeploySuite memory release = sDeploy.externalMockRelease();
        address[] memory deployed = sDeploy.externalDeployLocally(vm, release);
        assertEq(deployed.length, 2);
        assertEq(deployed[0], networkAddress(42161));
        assertEq(deployed[1], networkAddress(137));
        assertEq(MockDeployable(deployed[0]).sValue(), 42);
        assertEq(MockDeployable(deployed[1]).sValue(), 42);
    }

    function testDeployLocallyOnChainDeploysOnlyThatNetworksAddress() external {
        vm.chainId(137);
        sDeploy.externalDeployLocallyOnChain(vm, sDeploy.externalMockRelease());
        assertEq(networkAddress(137).code, type(MockDeployable).runtimeCode);
        assertEq(networkAddress(42161).code.length, 0);
    }

    function testDeployLocallyOnChainOfASingleAddressSuiteDeploysItsAddress() external {
        vm.chainId(137);
        sDeploy.externalDeployLocallyOnChain(vm, singleSuite());
        assertEq(create2Address(MOCK_CREATE2_SALT).code, type(MockDeployable).runtimeCode);
    }

    /// The candidate's networks in play that the release lacks are added at the release's own derivation; those not
    /// in play, and those the release records, are not.
    function testWithUnrecordedNetworksAddsTheCandidatesNetworksInPlay() external view {
        DeploySuite memory release = sDeploy.externalMockRelease();
        DeploySuite memory candidate = sDeploy.externalMockCandidate();
        uint256[] memory chainIds = new uint256[](3);
        chainIds[0] = 8453;
        chainIds[1] = 137;
        chainIds[2] = 10;
        DeploySuite memory suite = sDeploy.externalWithUnrecordedNetworks(release, candidate, chainIds);

        uint256[] memory got = sDeploy.externalAddressChainIds(suite);
        assertEq(got.length, 3);
        assertEq(got[0], 42161);
        assertEq(got[1], 137);
        assertEq(got[2], 8453);
        assertEq(sDeploy.externalRecordedAddress(suite, 8453), networkAddress(8453));
        assertEq(sDeploy.externalDeployedAddress(suite, 8453), networkAddress(8453));
        assertEq(keccak256(abi.encode(release)), keccak256(abi.encode(sDeploy.externalMockRelease())));
    }

    function testOnSupportedNetworksTakesTheCandidateByKeyName() external view {
        uint256[] memory chainIds = new uint256[](1);
        chainIds[0] = 8453;
        DeploySuite memory suite = sDeploy.externalOnSupportedNetworks(sDeploy.externalMockRelease(), chainIds);
        assertEq(sDeploy.externalAddressChainIds(suite).length, 3);
        assertEq(sDeploy.externalRecordedAddress(suite, 8453), networkAddress(8453));
    }

    function testAppendExtendedNetworksAppendsInOrder() external view {
        ChainDeploy[] memory extended = new ChainDeploy[](2);
        extended[0] = network(8453, address(0xd1));
        extended[1] = network(10, address(0xd2));
        DeploySuite memory suite = sDeploy.externalAppendExtendedNetworks(sDeploy.externalMockRelease(), extended);
        uint256[] memory chainIds = sDeploy.externalAddressChainIds(suite);
        assertEq(chainIds.length, 4);
        assertEq(chainIds[2], 8453);
        assertEq(chainIds[3], 10);
        assertEq(sDeploy.externalRecordedAddress(suite, 8453), address(0xd1));
        assertEq(sDeploy.externalRecordedAddress(suite, 10), address(0xd2));
    }

    function testAppendExtendedNetworksRefusesASingleAddressSuite() external {
        ChainDeploy[] memory extended = new ChainDeploy[](1);
        extended[0] = network(8453, address(0xd1));
        DeploySuite memory suite = singleSuite();
        vm.expectRevert(abi.encodeWithSelector(ExtendedNetworksUnexpected.selector, suite.suite));
        sDeploy.externalAppendExtendedNetworks(suite, extended);
    }

    function testWithExtendedNetworksAppendsTheDeclaredNetworksThroughTheHook() external {
        string memory root = "test/generated-snapshot/mock-create2-extended";
        //forge-lint: disable-next-line(unsafe-cheatcode)
        try vm.removeDir(root, true) {} catch {}
        ChainDeploy[] memory extended = new ChainDeploy[](1);
        extended[0] = network(8453, networkAddress(8453));
        DeploySuite memory release = sDeploy.externalMockRelease();
        LibRainDeployExtendedNetworks.writeExtendedNetworks(vm, root, release.suite, extended);
        sDeploy.setMockExtendedNetworksRoot(root);
        sDeploy.setMockExtendedNetworks(extended);
        DeploySuite memory frozen = sDeploy.externalWithExtendedNetworks(release);
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(root, true);
        uint256[] memory chainIds = sDeploy.externalAddressChainIds(frozen);
        assertEq(chainIds.length, 3);
        assertEq(chainIds[2], 8453);
        assertEq(sDeploy.externalRecordedAddress(frozen, 8453), networkAddress(8453));
    }

    function testCheckNetworkFrozenRefusesANetworkTheReleaseLacks() external {
        DeploySuite memory release = sDeploy.externalMockRelease();
        sDeploy.externalCheckNetworkFrozen(release, LibRainDeploy.POLYGON, 137, address(0xe1));
        vm.expectRevert(
            abi.encodeWithSelector(MockCreate2NetworkUnfrozen.selector, release.suite, LibRainDeploy.BASE, address(0xe1))
        );
        sDeploy.externalCheckNetworkFrozen(release, LibRainDeploy.BASE, 8453, address(0xe1));
    }

    /// `checkNetworksFrozen` checks each broadcast network the suite has an address for, at its recorded address.
    function testCheckNetworksFrozenNamesTheUnfrozenNetworksRecordedAddress() external {
        DeploySuite memory release = sDeploy.externalMockRelease();
        ChainDeploy[] memory networks = new ChainDeploy[](3);
        networks[0] = network(42161, networkAddress(42161));
        networks[1] = network(137, networkAddress(137));
        networks[2] = network(8453, address(0xf1));
        DeploySuite memory onNetworks = withNetworks(sDeploy.externalMockRelease(), networks);
        string[] memory names = new string[](3);
        names[0] = LibRainDeploy.ARBITRUM_ONE;
        names[1] = LibRainDeploy.POLYGON;
        names[2] = LibRainDeploy.BASE;
        vm.expectRevert(
            abi.encodeWithSelector(MockCreate2NetworkUnfrozen.selector, release.suite, LibRainDeploy.BASE, address(0xf1))
        );
        sDeploy.externalCheckNetworksFrozen(release, onNetworks, names);
    }

    /// A broadcast network the suite has no address for is not checked, and the recorded ones pass.
    function testCheckNetworksFrozenSkipsNetworksWithoutAnAddress() external view {
        DeploySuite memory release = sDeploy.externalMockRelease();
        string[] memory names = new string[](3);
        names[0] = LibRainDeploy.BASE;
        names[1] = LibRainDeploy.ARBITRUM_ONE;
        names[2] = LibRainDeploy.POLYGON;
        sDeploy.externalCheckNetworksFrozen(release, release, names);
    }

    function testCheckNetworksFrozenOfASingleAddressSuiteChecksNothing() external view {
        string[] memory names = new string[](1);
        names[0] = LibRainDeploy.BASE;
        sDeploy.externalCheckNetworksFrozen(sDeploy.externalMockRelease(), singleSuite(), names);
    }

    function testSuiteBeaconIsTheMechanisms() external view {
        DeploySuite memory suite = sDeploy.externalMockRelease();
        MockCreate2Mechanism memory mechanism = mechanismOf(suite);
        mechanism.beacon = address(0xbeac);
        suite.mechanismData = abi.encode(mechanism);
        assertEq(sDeploy.externalSuiteBeacon(suite, 42161), address(0xbeac));
    }

    /// The mechanism's verification log replaces the Zoltu verify commands.
    function testLogVerificationIsTheMechanisms() external {
        DeploySuite memory release = sDeploy.externalMockRelease();
        address[] memory deployed = new address[](2);
        deployed[0] = networkAddress(42161);
        deployed[1] = networkAddress(137);
        LocalForkVm forkVm = new LocalForkVm();
        vm.expectCall(address(forkVm), abi.encodeWithSignature("toString(address)", deployed[0]), 0);
        vm.expectEmit(address(sDeploy));
        emit MockCreate2Verification(arbitrumAndPolygon(), release.suite, deployed);
        sDeploy.externalLogVerification(Vm(address(forkVm)), arbitrumAndPolygon(), release, deployed);
    }

    /// The mechanism's snapshot writer runs, and the released-lib expression reads what it wrote.
    function testWriteSuiteSnapshotAndReleasedMechanismDataAreTheMechanisms() external {
        string memory root = "test/generated-snapshot/mock-create2";
        //forge-lint: disable-next-line(unsafe-cheatcode)
        try vm.removeDir(root, true) {} catch {}
        DeploySuite memory release = sDeploy.externalMockRelease();
        string memory path = sDeploy.externalWriteSuiteSnapshot(
            vm, root, "0_0_1", "MockDeployable", "LicenseRef-DCL-1.0", "Copyright", release
        );
        string memory record = vm.readFile(path);
        string memory expression = sDeploy.externalReleasedMechanismData(vm, path, "V0_0_1");
        DeploySuite memory zoltu = sDeploy.externalMockRelease();
        zoltu.mechanismData = "";
        string memory zoltuPath =
            sDeploy.externalWriteSuiteSnapshot(vm, root, "0_0_2", "MockDeployable", "LicenseRef-DCL-1.0", "Copyright", zoltu);
        string memory zoltuExpression = sDeploy.externalReleasedMechanismData(vm, zoltuPath, "V0_0_2");
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(root, true);

        assertTrue(
            vm.contains(
                record,
                string.concat(
                    "bytes constant MECHANISM_DATA = hex\"", vm.replace(vm.toString(release.mechanismData), "0x", ""), "\";"
                )
            )
        );
        assertEq(expression, "V0_0_1_MECHANISM_DATA");
        assertEq(zoltuExpression, "\"\"");
    }
}
