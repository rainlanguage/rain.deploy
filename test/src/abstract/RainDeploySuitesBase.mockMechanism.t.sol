// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {DeploySuite} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {ChainDeploy, LibRainDeployExtendedNetworks} from "../../../src/lib/LibRainDeployExtendedNetworks.sol";
import {LibRainDeployZoltuMechanism, ZOLTU_MECHANISM_ID} from "../../../src/lib/LibRainDeployZoltuMechanism.sol";
import {
    LibMockCreate2Mechanism,
    MOCK_CREATE2_FACTORY,
    MOCK_CREATE2_MECHANISM_ID,
    MOCK_CREATE2_SALT,
    MockCreate2Mechanism,
    MockCreate2NetworkUndeclared,
    MockCreate2NetworkUnfrozen
} from "../../lib/LibMockCreate2Mechanism.sol";
import {IMockMechanismProbe, MOCK_MECHANISM_PROBE} from "../../lib/LibMockMechanismProbe.sol";
import {MockCreate2Deploy} from "../../concrete/MockCreate2Deploy.sol";
import {MockCreate2Factory} from "../../concrete/MockCreate2Factory.sol";
import {MockDeployable} from "../../concrete/MockDeployable.sol";
import {LocalForkVm} from "../../concrete/LocalForkVm.sol";

/// @title RainDeploySuitesBaseMockMechanismTest
/// @notice Every mechanism step dispatches to the claiming non-Zoltu handler, and the base helpers read through it.
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

    /// `suite` on exactly `networks`, both in its payload and in `suite.networks`.
    function withNetworks(DeploySuite memory suite, ChainDeploy[] memory networks)
        internal
        pure
        returns (DeploySuite memory)
    {
        MockCreate2Mechanism memory mechanism = LibMockCreate2Mechanism.decode(suite);
        mechanism.networks = networks;
        DeploySuite memory changed = abi.decode(abi.encode(suite), (DeploySuite));
        changed.mechanismData = LibMockCreate2Mechanism.encode(mechanism);
        changed.networks = LibMockCreate2Mechanism.networkNames(networks);
        return changed;
    }

    /// The release at one address on each of its networks.
    function singleSuite() internal view returns (DeploySuite memory) {
        DeploySuite memory suite = sDeploy.externalMockRelease();
        MockCreate2Mechanism memory mechanism = LibMockCreate2Mechanism.decode(suite);
        mechanism.perNetwork = false;
        mechanism.networks = new ChainDeploy[](0);
        suite.mechanismData = LibMockCreate2Mechanism.encode(mechanism);
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

    /// The same suite carrying the Zoltu id goes to Zoltu, declared beside the mock.
    function testZoltuIdDispatchesToZoltuBesideTheMock() external view {
        DeploySuite memory suite = sDeploy.externalMockRelease();
        suite.mechanismData = LibRainDeployZoltuMechanism.mechanismData();
        suite.storedDeployedAddress = address(0x1234);
        assertEq(sDeploy.externalMechanismOf(sDeploy.externalMockRelease()), MOCK_CREATE2_MECHANISM_ID);
        assertEq(sDeploy.externalMechanismOf(suite), ZOLTU_MECHANISM_ID);
        assertEq(sDeploy.externalDeployedAddress(suite, 42161), LibRainDeploy.zoltuAddress(suite.creationCode));
        assertEq(sDeploy.externalRecordedAddress(suite, 42161), address(0x1234));
        assertEq(sDeploy.externalDeployStepData(suite, 42161), suite.creationCode);
    }

    /// `deployedAddresses` and `recordedAddresses` are one entry per `suite.networks` entry, in its order, each read
    /// through its own hook.
    function testAddressListsFollowTheSuitesNetworkOrder() external view {
        ChainDeploy[] memory networks = new ChainDeploy[](3);
        networks[0] = network(137, address(0xa1));
        networks[1] = network(8453, address(0xa2));
        networks[2] = network(42161, address(0xa3));
        DeploySuite memory suite = withNetworks(sDeploy.externalMockRelease(), networks);
        address[] memory deployed = sDeploy.externalDeployedAddresses(suite);
        address[] memory recorded = sDeploy.externalRecordedAddresses(suite);
        assertEq(deployed.length, 3);
        assertEq(recorded.length, 3);
        for (uint256 i = 0; i < 3; i++) {
            assertEq(deployed[i], networkAddress(networks[i].chainId));
            assertEq(recorded[i], networks[i].deployedAddress);
        }
    }

    /// A one-address suite answers its one address for every network it lists.
    function testAddressListsOfASingleAddressSuiteRepeatItsAddress() external view {
        DeploySuite memory suite = singleSuite();
        suite.storedDeployedAddress = address(0xb1);
        address[] memory deployed = sDeploy.externalDeployedAddresses(suite);
        address[] memory recorded = sDeploy.externalRecordedAddresses(suite);
        assertEq(deployed.length, 2);
        assertEq(recorded.length, 2);
        for (uint256 i = 0; i < 2; i++) {
            assertEq(deployed[i], create2Address(MOCK_CREATE2_SALT));
            assertEq(recorded[i], address(0xb1));
        }
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
                MOCK_CREATE2_FACTORY,
                keccak256(abi.encode(MOCK_CREATE2_SALT, abi.encode(uint256(137)))),
                release.creationCode
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
    function testAddUnrecordedNetworksAddsTheCandidatesNetworksInPlay() external view {
        DeploySuite memory release = sDeploy.externalMockRelease();
        DeploySuite memory candidate = sDeploy.externalMockCandidate();
        uint256[] memory chainIds = new uint256[](3);
        chainIds[0] = 8453;
        chainIds[1] = 137;
        chainIds[2] = 10;
        DeploySuite memory suite = sDeploy.externalAddUnrecordedNetworks(release, candidate, chainIds);
        assertEq(suite.networks.length, 3);
        assertEq(suite.networks[0], LibRainDeploy.ARBITRUM_ONE);
        assertEq(suite.networks[1], LibRainDeploy.POLYGON);
        assertEq(suite.networks[2], LibRainDeploy.BASE);
        assertEq(LibMockCreate2Mechanism.decode(suite).networks.length, 3);
        assertEq(sDeploy.externalRecordedAddress(suite, 8453), networkAddress(8453));
        assertEq(sDeploy.externalDeployedAddress(suite, 8453), networkAddress(8453));
    }

    function testAddCandidateNetworksTakesTheCandidateByKeyName() external view {
        uint256[] memory chainIds = new uint256[](1);
        chainIds[0] = 8453;
        DeploySuite memory suite = sDeploy.externalAddCandidateNetworks(sDeploy.externalMockRelease(), chainIds);
        assertEq(suite.networks.length, 3);
        assertEq(sDeploy.externalRecordedAddress(suite, 8453), networkAddress(8453));
    }

    /// The mock reads its own records under the root in its payload, appending them in order.
    function testAddRecordedNetworksAppendsTheMechanismsOwnRecords() external {
        string memory root = "test/generated-snapshot/mock-create2-recorded";
        //forge-lint: disable-next-line(unsafe-cheatcode)
        try vm.removeDir(root, true) {} catch {}
        ChainDeploy[] memory recorded = new ChainDeploy[](2);
        recorded[0] = network(8453, networkAddress(8453));
        recorded[1] = network(56, networkAddress(56));
        sDeploy.setMockRecordRoot(root);
        DeploySuite memory release = sDeploy.externalMockRelease();
        LibRainDeployExtendedNetworks.writeExtendedNetworks(vm, root, release.suite, recorded);
        vm.expectCall(
            MOCK_MECHANISM_PROBE,
            abi.encodeCall(IMockMechanismProbe.addRecordedNetworks, (MOCK_CREATE2_MECHANISM_ID, release.suite)),
            1
        );
        DeploySuite memory frozen = sDeploy.externalAddRecordedNetworks(release);
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(root, true);
        assertEq(frozen.networks.length, 4);
        assertEq(frozen.networks[2], LibRainDeploy.BASE);
        assertEq(frozen.networks[3], LibRainDeploy.BSC);
        assertEq(sDeploy.externalRecordedAddress(frozen, 8453), networkAddress(8453));
        assertEq(sDeploy.externalRecordedAddress(frozen, 56), networkAddress(56));
    }

    /// Without a record root the mock adds nothing, but the hook still runs.
    function testAddRecordedNetworksWithoutRecordsAddsNothing() external {
        DeploySuite memory release = sDeploy.externalMockRelease();
        vm.expectCall(
            MOCK_MECHANISM_PROBE,
            abi.encodeCall(IMockMechanismProbe.addRecordedNetworks, (MOCK_CREATE2_MECHANISM_ID, release.suite)),
            1
        );
        DeploySuite memory frozen = sDeploy.externalAddRecordedNetworks(release);
        assertEq(keccak256(abi.encode(frozen)), keccak256(abi.encode(release)));
    }

    function testCheckOnChainIsTheMechanisms() external {
        DeploySuite memory release = sDeploy.externalMockRelease();
        vm.expectCall(
            MOCK_MECHANISM_PROBE,
            abi.encodeCall(
                IMockMechanismProbe.checkOnChain,
                (MOCK_CREATE2_MECHANISM_ID, release.suite, LibRainDeploy.POLYGON, uint256(137), address(0xbeac))
            ),
            1
        );
        sDeploy.externalCheckOnChain(release, LibRainDeploy.POLYGON, 137, address(0xbeac));
    }

    function testCheckOnChainRefusalPropagates() external {
        DeploySuite memory release = sDeploy.externalMockRelease();
        vm.mockCallRevert(MOCK_MECHANISM_PROBE, abi.encodeWithSelector(IMockMechanismProbe.checkOnChain.selector), "no");
        vm.expectRevert(bytes("no"));
        sDeploy.externalCheckOnChain(release, LibRainDeploy.POLYGON, 137, address(0xbeac));
    }

    function testCheckNetworkFrozenRefusesANetworkTheReleaseLacks() external {
        DeploySuite memory release = sDeploy.externalMockRelease();
        sDeploy.externalCheckNetworkFrozen(release, LibRainDeploy.POLYGON, 137, address(0xe1));
        vm.expectRevert(
            abi.encodeWithSelector(
                MockCreate2NetworkUnfrozen.selector, release.suite, LibRainDeploy.BASE, address(0xe1)
            )
        );
        sDeploy.externalCheckNetworkFrozen(release, LibRainDeploy.BASE, 8453, address(0xe1));
    }

    /// `checkNetworksFrozen` checks each broadcast network the suite lists, at its recorded address.
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
            abi.encodeWithSelector(
                MockCreate2NetworkUnfrozen.selector, release.suite, LibRainDeploy.BASE, address(0xf1)
            )
        );
        sDeploy.externalCheckNetworksFrozen(release, onNetworks, names);
    }

    /// A broadcast network the suite does not list is not checked, and the listed ones pass.
    function testCheckNetworksFrozenSkipsNetworksTheSuiteDoesNotList() external view {
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
        zoltu.mechanismData = LibRainDeployZoltuMechanism.mechanismData();
        vm.etch(LibRainDeploy.zoltuAddress(zoltu.creationCode), hex"");
        vm.resetNonce(LibRainDeploy.zoltuAddress(zoltu.creationCode));
        string memory zoltuPath = sDeploy.externalWriteSuiteSnapshot(
            vm, root, "0_0_2", "MockDeployable", "LicenseRef-DCL-1.0", "Copyright", zoltu
        );
        string memory zoltuExpression = sDeploy.externalReleasedMechanismData(vm, zoltuPath, "V0_0_2");
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(root, true);
        assertTrue(
            vm.contains(
                record,
                string.concat(
                    "bytes constant MECHANISM_DATA = hex\"",
                    vm.replace(vm.toString(release.mechanismData), "0x", ""),
                    "\";"
                )
            )
        );
        assertEq(expression, "V0_0_1_MECHANISM_DATA");
        assertEq(zoltuExpression, string.concat("abi.encode(bytes32(", vm.toString(ZOLTU_MECHANISM_ID), "))"));
    }
}
