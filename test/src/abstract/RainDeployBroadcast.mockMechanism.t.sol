// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {SuiteSeatsDeployKey} from "../../../src/abstract/RainDeployBroadcast.sol";
import {DeployDependency, DeploySuite} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {LibMockNetworkRecord, MockNetworkDeploy} from "../../lib/LibMockNetworkRecord.sol";
import {
    LibMockCreate2Mechanism,
    MOCK_CREATE2_FACTORY,
    MOCK_CREATE2_MECHANISM_ID,
    MOCK_CREATE2_SALT,
    MockCreate2Mechanism,
    MockCreate2NetworkUnfrozen
} from "../../lib/LibMockCreate2Mechanism.sol";
import {IMockMechanismProbe, MOCK_MECHANISM_PROBE} from "../../lib/LibMockMechanismProbe.sol";
import {MockCreate2Deploy} from "../../concrete/MockCreate2Deploy.sol";
import {MockCreate2Factory} from "../../concrete/MockCreate2Factory.sol";
import {MockChainOriginOwned} from "../../concrete/MockChainOriginOwned.sol";
import {MockDeployable} from "../../concrete/MockDeployable.sol";
import {LocalForkVm} from "../../concrete/LocalForkVm.sol";
import {CallerHeldMockBroadcast} from "../../concrete/CallerHeldMockBroadcast.sol";

/// @title RainDeployBroadcastMockMechanismTest
/// @notice `deployAndBroadcast`, `broadcastSuite` and the seat check over a per-network mechanism.
contract RainDeployBroadcastMockMechanismTest is Test {
    event MockCreate2Verification(string[] networks, string suite, address[] deployed);

    MockCreate2Deploy internal sDeploy;
    LocalForkVm internal sForkVm;

    function setUp() external {
        sDeploy = new MockCreate2Deploy();
        sForkVm = new LocalForkVm();
        vm.etch(MOCK_CREATE2_FACTORY, type(MockCreate2Factory).runtimeCode);
    }

    function networkAddress(uint256 chainId, bytes memory creationCode) internal pure returns (address) {
        bytes32 salt = keccak256(abi.encode(MOCK_CREATE2_SALT, abi.encode(chainId)));
        return address(
            uint160(
                uint256(keccak256(abi.encodePacked(bytes1(0xff), MOCK_CREATE2_FACTORY, salt, keccak256(creationCode))))
            )
        );
    }

    function networkAddress(uint256 chainId) internal pure returns (address) {
        return networkAddress(chainId, type(MockDeployable).creationCode);
    }

    function names(string memory a, string memory b) internal pure returns (string[] memory) {
        string[] memory networks = new string[](2);
        networks[0] = a;
        networks[1] = b;
        return networks;
    }

    function arbitrumAndPolygonIds() internal pure returns (uint256[] memory) {
        uint256[] memory chainIds = new uint256[](2);
        chainIds[0] = 42161;
        chainIds[1] = 137;
        return chainIds;
    }

    function anyForkExists() internal returns (bool) {
        (bool forked,) = address(vm).call(abi.encodeWithSignature("selectFork(uint256)", uint256(0)));
        return forked;
    }

    function testBroadcastsEachNetworkAtItsOwnAddress() external {
        DeploySuite memory release = sDeploy.externalMockRelease();
        address[] memory expected = new address[](2);
        expected[0] = networkAddress(42161);
        expected[1] = networkAddress(137);
        string[] memory networks = names(LibRainDeploy.ARBITRUM_ONE, LibRainDeploy.POLYGON);
        vm.expectEmit(address(sDeploy));
        emit MockCreate2Verification(networks, release.suite, expected);
        (address[] memory deployed,) =
            sDeploy.externalDeployAndBroadcast(Vm(address(sForkVm)), networks, 1, release, release);
        assertEq(deployed.length, 2);
        assertEq(deployed[0], expected[0]);
        assertEq(deployed[1], expected[1]);
        assertEq(expected[0].code, type(MockDeployable).runtimeCode);
        assertEq(expected[1].code, type(MockDeployable).runtimeCode);
    }

    /// The mechanism's verification log replaces the Zoltu verify commands.
    function testBroadcastFormatsNoZoltuVerifyCommand() external {
        DeploySuite memory release = sDeploy.externalMockRelease();
        vm.expectCall(address(sForkVm), abi.encodeWithSignature("toString(address)", networkAddress(42161)), 0);
        sDeploy.externalDeployAndBroadcast(
            Vm(address(sForkVm)), names(LibRainDeploy.ARBITRUM_ONE, LibRainDeploy.POLYGON), 1, release, release
        );
    }

    /// A network the candidate adds but the release does not record is refused before any fork, at the address the
    /// release's derivation gives it there.
    function testBroadcastRefusesAnUnfrozenCandidateNetworkBeforeAnyFork() external {
        DeploySuite memory release = sDeploy.externalMockRelease();
        DeploySuite memory candidate = sDeploy.externalMockCandidate();
        vm.expectRevert(
            abi.encodeWithSelector(
                MockCreate2NetworkUnfrozen.selector, release.suite, LibRainDeploy.BASE, networkAddress(8453)
            )
        );
        sDeploy.externalDeployAndBroadcast(
            vm, names(LibRainDeploy.ARBITRUM_ONE, LibRainDeploy.BASE), 1, release, candidate
        );
        assertFalse(anyForkExists());
    }

    /// A network the mechanism's own records add broadcasts at its recorded address.
    function testBroadcastsARecordedNetwork() external {
        string memory root = "test/generated-snapshot/broadcast-mock-recorded";
        //forge-lint: disable-next-line(unsafe-cheatcode)
        try vm.removeDir(root, true) {} catch {}
        MockNetworkDeploy[] memory recorded = new MockNetworkDeploy[](1);
        recorded[0] =
            MockNetworkDeploy({chainId: 8453, data: abi.encode(uint256(8453)), deployedAddress: networkAddress(8453)});
        sDeploy.setMockRecordRoot(root);
        DeploySuite memory release = sDeploy.externalMockRelease();
        LibMockNetworkRecord.write(vm, root, release.suite, recorded);
        DeploySuite memory frozen = sDeploy.externalAddRecordedNetworks(release);
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(root, true);
        (address[] memory deployed,) = sDeploy.externalDeployAndBroadcast(
            Vm(address(sForkVm)),
            names(LibRainDeploy.BASE, LibRainDeploy.POLYGON),
            1,
            frozen,
            sDeploy.externalMockCandidate()
        );
        assertEq(deployed[0], networkAddress(8453));
        assertEq(deployed[1], networkAddress(137));
        assertEq(networkAddress(8453).code, type(MockDeployable).runtimeCode);
    }

    /// The recorded address on each network is held to the mechanism's derivation there before any fork.
    function testBroadcastRefusesAStaleRecordedAddressBeforeAnyFork() external {
        DeploySuite memory release = sDeploy.externalMockRelease();
        MockCreate2Mechanism memory mechanism = LibMockCreate2Mechanism.decode(release);
        mechanism.networks[1].deployedAddress = address(0x5a1e);
        release.mechanismData = LibMockCreate2Mechanism.encode(mechanism);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.UnexpectedDeployedAddress.selector, address(0x5a1e), networkAddress(137)
            )
        );
        sDeploy.externalDeployAndBroadcast(
            vm, names(LibRainDeploy.ARBITRUM_ONE, LibRainDeploy.POLYGON), 1, release, release
        );
        assertFalse(anyForkExists());
    }

    /// `broadcastSuite` asks the mechanism for its recorded networks exactly once.
    function testBroadcastSuiteAddsRecordedNetworksOnce() external {
        DeploySuite memory release = sDeploy.externalMockRelease();
        vm.expectCall(
            MOCK_MECHANISM_PROBE,
            abi.encodeCall(IMockMechanismProbe.addRecordedNetworks, (MOCK_CREATE2_MECHANISM_ID, release.suite)),
            1
        );
        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.NoNetworks.selector));
        sDeploy.externalBroadcastSuite(release, new string[](0), 1);
    }

    /// The mechanism's own records and the candidate's networks widen copies; the caller's suite and declaration are
    /// what they were.
    function testBroadcastSuiteLeavesTheCallersSuiteUnchanged() external {
        string memory root = "test/generated-snapshot/broadcast-mock-caller-held";
        //forge-lint: disable-next-line(unsafe-cheatcode)
        try vm.removeDir(root, true) {} catch {}
        CallerHeldMockBroadcast deploy = new CallerHeldMockBroadcast();
        deploy.setMockRecordRoot(root);
        MockNetworkDeploy[] memory recorded = new MockNetworkDeploy[](1);
        recorded[0] =
            MockNetworkDeploy({chainId: 56, data: abi.encode(uint256(56)), deployedAddress: networkAddress(56)});
        LibMockNetworkRecord.write(vm, root, deploy.externalMockRelease().suite, recorded);
        assertEq(deploy.externalAddRecordedNetworks(deploy.externalMockRelease()).networks.length, 3);
        vm.makePersistent(MOCK_CREATE2_FACTORY);
        string[] memory networks = new string[](1);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;
        (bytes32 suiteBefore, bytes32 suiteAfter, bytes32 declarationBefore, bytes32 declarationAfter) =
            deploy.broadcastRelease(networks, 0xa11ce);
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(root, true);
        assertEq(suiteAfter, suiteBefore);
        assertEq(declarationAfter, declarationBefore);
        assertEq(networkAddress(42161).code, type(MockDeployable).runtimeCode);
    }

    function originOwnedOnSuite(uint256 ownedOn) internal view returns (DeploySuite memory) {
        bytes memory creationCode = abi.encodePacked(type(MockChainOriginOwned).creationCode, abi.encode(ownedOn));
        MockNetworkDeploy[] memory networks = new MockNetworkDeploy[](2);
        networks[0] = MockNetworkDeploy({
            chainId: 42161, data: abi.encode(uint256(42161)), deployedAddress: networkAddress(42161, creationCode)
        });
        networks[1] = MockNetworkDeploy({
            chainId: 137, data: abi.encode(uint256(137)), deployedAddress: networkAddress(137, creationCode)
        });
        DeploySuite memory suite = sDeploy.externalMockRelease();
        suite.creationCode = creationCode;
        suite.dependencies = new DeployDependency[](0);
        suite.networks = LibMockCreate2Mechanism.networkNames(networks);
        suite.mechanismData = LibMockCreate2Mechanism.encode(
            MockCreate2Mechanism({
                factory: MOCK_CREATE2_FACTORY, salt: MOCK_CREATE2_SALT, perNetwork: true, networks: networks, root: ""
            })
        );
        return suite;
    }

    /// The seat check deploys each network's address under its own chain id: the one seating the deploy key there
    /// refuses the broadcast, by its own address.
    function testSeatCheckDeploysEachNetworkUnderItsOwnChainId() external {
        address deployer = vm.addr(1);
        DeploySuite memory suite = originOwnedOnSuite(137);
        vm.expectRevert(
            abi.encodeWithSelector(SuiteSeatsDeployKey.selector, suite.suite, networkAddress(137, suite.creationCode))
        );
        sDeploy.externalCheckSeatsNoDeployKey(suite, arbitrumAndPolygonIds(), deployer);
    }

    function testSeatCheckLeavesNothingDeployed() external {
        DeploySuite memory suite = originOwnedOnSuite(1);
        sDeploy.externalCheckSeatsNoDeployKey(suite, arbitrumAndPolygonIds(), vm.addr(1));
        assertEq(networkAddress(42161, suite.creationCode).code.length, 0);
        assertEq(networkAddress(137, suite.creationCode).code.length, 0);
    }

    function testSeatCheckDeploysOnlyTheChainsOwnNetworkPerChain() external {
        DeploySuite memory suite = originOwnedOnSuite(1);
        vm.expectCall(MOCK_CREATE2_FACTORY, abi.encodeWithSelector(MockCreate2Factory.deploy.selector), 2);
        sDeploy.externalCheckSeatsNoDeployKey(suite, arbitrumAndPolygonIds(), vm.addr(1));
    }
}
