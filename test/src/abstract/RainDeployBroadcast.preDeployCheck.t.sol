// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {DeployDependency, DeploySuite} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeploy, SupportedNetwork} from "../../../src/lib/LibRainDeploy.sol";
import {MOCK_CREATE2_FACTORY, MOCK_CREATE2_SALT} from "../../lib/LibMockCreate2Mechanism.sol";
import {LocalForkVm} from "../../concrete/LocalForkVm.sol";
import {MockCreate2Deploy} from "../../concrete/MockCreate2Deploy.sol";
import {MockCreate2Factory} from "../../concrete/MockCreate2Factory.sol";
import {MockDeployable} from "../../concrete/MockDeployable.sol";
import {
    PreDeployCheckCall,
    PreDeployCheckRecordingDeploy,
    PreDeployCheckRefused
} from "../../concrete/PreDeployCheckRecordingDeploy.sol";

/// @title RainDeployBroadcastPreDeployCheckTest
/// @notice `preDeployCheck` over a per-network mechanism broadcast to Arbitrum One then Polygon on local forks.
contract RainDeployBroadcastPreDeployCheckTest is Test {
    address constant DEPENDENCY = address(0xdef);

    PreDeployCheckRecordingDeploy internal sDeploy;
    LocalForkVm internal sForkVm;

    function setUp() external {
        sDeploy = new PreDeployCheckRecordingDeploy();
        sForkVm = new LocalForkVm();
        vm.etch(MOCK_CREATE2_FACTORY, type(MockCreate2Factory).runtimeCode);
    }

    function networkSalt(uint256 chainId) internal pure returns (bytes32) {
        return keccak256(abi.encode(MOCK_CREATE2_SALT, abi.encode(chainId)));
    }

    function networkAddress(uint256 chainId) internal pure returns (address) {
        return address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            MOCK_CREATE2_FACTORY,
                            networkSalt(chainId),
                            keccak256(type(MockDeployable).creationCode)
                        )
                    )
                )
            )
        );
    }

    function stepCall(uint256 chainId) internal pure returns (bytes memory) {
        return abi.encodeCall(MockCreate2Factory.deploy, (networkSalt(chainId), type(MockDeployable).creationCode));
    }

    function broadcast(DeploySuite memory release) internal returns (address[] memory) {
        string[] memory networks = new string[](2);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;
        networks[1] = LibRainDeploy.POLYGON;
        (address[] memory deployed,) =
            sDeploy.externalDeployAndBroadcast(Vm(address(sForkVm)), networks, 1, release, release);
        return deployed;
    }

    function dependentRelease(bytes memory runtimeCode) internal view returns (DeploySuite memory) {
        DeploySuite memory release = sDeploy.externalMockRelease();
        release.dependencies = new DeployDependency[](1);
        release.dependencies[0] = DeployDependency({deployedAddress: DEPENDENCY, runtimeCode: runtimeCode});
        return release;
    }

    /// The hook runs once per network, in order, on that network's selected fork, with the suite and before the
    /// step puts the suite there.
    function testRunsOncePerNetworkOnItsForkBeforeItsStep() external {
        DeploySuite memory release = sDeploy.externalMockRelease();
        address[] memory deployed = broadcast(release);

        PreDeployCheckCall[] memory calls = sDeploy.preDeployChecks();
        assertEq(calls.length, 2);
        assertEq(calls[0].network, LibRainDeploy.ARBITRUM_ONE);
        assertEq(calls[1].network, LibRainDeploy.POLYGON);
        uint256[2] memory chainIds = [uint256(42161), 137];
        for (uint256 i = 0; i < 2; i++) {
            assertEq(calls[i].suite, release.suite);
            assertEq(calls[i].networkChainId, chainIds[i]);
            assertEq(calls[i].forkChainId, chainIds[i]);
            assertEq(calls[i].recordedCodeLength, 0);
            assertEq(deployed[i], networkAddress(chainIds[i]));
            assertEq(deployed[i].code, type(MockDeployable).runtimeCode);
        }
    }

    /// The hook runs on a network the suite is already on, where the step is skipped.
    function testRunsOnANetworkAlreadyDeployed() external {
        DeploySuite memory release = sDeploy.externalMockRelease();
        vm.etch(networkAddress(42161), type(MockDeployable).runtimeCode);
        vm.expectCall(MOCK_CREATE2_FACTORY, stepCall(42161), 0);
        broadcast(release);

        PreDeployCheckCall[] memory calls = sDeploy.preDeployChecks();
        assertEq(calls.length, 2);
        assertEq(calls[0].network, LibRainDeploy.ARBITRUM_ONE);
        assertEq(calls[0].recordedCodeLength, type(MockDeployable).runtimeCode.length);
        assertEq(calls[1].network, LibRainDeploy.POLYGON);
        assertEq(calls[1].recordedCodeLength, 0);
    }

    /// A fork reporting another chain is refused before the hook runs on it.
    function testChainIdIsCheckedBeforeTheHook() external {
        DeploySuite memory release = sDeploy.externalMockRelease();
        sForkVm.setReportedChainId(1);
        sDeploy.refuseOn(42161);
        vm.expectRevert(
            abi.encodeWithSelector(LibRainDeploy.NetworkChainIdMismatch.selector, LibRainDeploy.ARBITRUM_ONE, 42161, 1)
        );
        broadcast(release);
    }

    /// A missing declared dependency is refused before the hook runs on its network.
    function testMissingDependencyIsRefusedBeforeTheHook() external {
        DeploySuite memory release = dependentRelease(hex"00");
        sDeploy.refuseOn(42161);
        vm.expectRevert(
            abi.encodeWithSelector(LibRainDeploy.MissingDependency.selector, LibRainDeploy.ARBITRUM_ONE, DEPENDENCY)
        );
        broadcast(release);
    }

    /// A declared dependency holding other code is refused before the hook runs on its network.
    function testChangedDependencyIsRefusedBeforeTheHook() external {
        DeploySuite memory release = dependentRelease(hex"00");
        vm.etch(DEPENDENCY, hex"01");
        sDeploy.refuseOn(42161);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.DependencyChanged.selector,
                LibRainDeploy.ARBITRUM_ONE,
                DEPENDENCY,
                keccak256(hex"00"),
                keccak256(hex"01")
            )
        );
        broadcast(release);
    }

    /// The hook runs on a network whose declared dependencies are in place.
    function testRunsWhereTheDependenciesAreInPlace() external {
        vm.etch(DEPENDENCY, hex"00");
        broadcast(dependentRelease(hex"00"));
        assertEq(sDeploy.preDeployChecks().length, 2);
    }

    /// A hook refusing the first network aborts the broadcast before any step on any network.
    function testRefusalOnTheFirstNetworkDeploysNothing() external {
        DeploySuite memory release = sDeploy.externalMockRelease();
        sDeploy.refuseOn(42161);
        vm.expectCall(MOCK_CREATE2_FACTORY, abi.encodeWithSelector(MockCreate2Factory.deploy.selector), 0);
        vm.expectRevert(abi.encodeWithSelector(PreDeployCheckRefused.selector, LibRainDeploy.ARBITRUM_ONE, 42161));
        broadcast(release);
    }

    /// A hook refusing a later network reverts the whole run before that network's step.
    function testRefusalOnALaterNetworkRevertsTheRunBeforeItsStep() external {
        DeploySuite memory release = sDeploy.externalMockRelease();
        sDeploy.refuseOn(137);
        vm.expectCall(MOCK_CREATE2_FACTORY, stepCall(42161), 1);
        vm.expectCall(MOCK_CREATE2_FACTORY, stepCall(137), 0);
        vm.expectRevert(abi.encodeWithSelector(PreDeployCheckRefused.selector, LibRainDeploy.POLYGON, 137));
        broadcast(release);
    }

    /// The default hook does nothing: it does not revert, touches no storage and emits nothing, on any network
    /// whatever fork is selected.
    /// @param chainId The network's chain id.
    function testDefaultHookDoesNothing(uint256 chainId) external {
        MockCreate2Deploy deploy = new MockCreate2Deploy();
        DeploySuite memory release = deploy.externalMockRelease();
        string[] memory names = new string[](1);
        names[0] = LibRainDeploy.POLYGON;
        SupportedNetwork memory network = LibRainDeploy.declaredNetworkConfigs(names)[0];
        network.chainId = chainId;
        vm.record();
        vm.recordLogs();
        deploy.externalPreDeployCheck(release, network);
        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(address(deploy));
        assertEq(reads.length, 0);
        assertEq(writes.length, 0);
        assertEq(vm.getRecordedLogs().length, 0);
    }
}
