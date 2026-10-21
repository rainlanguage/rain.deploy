// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {DeployCandidate, DeployMechanism, DeploySuite} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {BEACON_PROXY_ARTIFACT_PATH} from "../../../src/lib/LibRainDeployBeaconProxy.sol";
import {BeaconProxyOnlyDeploySuites} from "../../concrete/BeaconProxyOnlyDeploySuites.sol";
import {MixedCloneBeaconProxyDeploySuites} from "../../concrete/MixedCloneBeaconProxyDeploySuites.sol";
import {NoFactoryDeploys} from "../../../src/abstract/RainDeployCloneSuitesBase.sol";
import {CLONE_ARTIFACT_PATH} from "../../../src/lib/LibRainDeployClone.sol";
import {CloneNetworks, CloneTarget, LibRainDeployClone} from "../../../src/lib/LibRainDeployClone.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {ConfigurablePerNetworkCloneDeploy} from "../../concrete/ConfigurablePerNetworkCloneDeploy.sol";
import {ExampleCloneDeploy} from "../../concrete/ExampleCloneDeploy.sol";
import {
    NoPerNetworkCloneAdmin,
    PER_NETWORK_CLONE_ARBITRUM_ONE_ADMIN,
    PER_NETWORK_CLONE_POLYGON_ADMIN
} from "../../abstract/PerNetworkCloneDeploys.sol";
import {exampleCloneFactory, exampleCloneImplementation} from "../../abstract/ExampleCloneDeploys.sol";
import {NoCloneDeploySuites} from "../../concrete/NoCloneDeploySuites.sol";

/// @title RainDeployCloneSuitesBaseTest Tests for `RainDeployCloneSuitesBase`: that the candidates
/// ARE the clone list rather than a second list beside it, and that an empty clone list is refused
/// where the consumer wrote it.
contract RainDeployCloneSuitesBaseTest is Test {
    /// `candidateSuites()` MUST be `cloneCandidate` mapped over `cloneDeploys()`, in order and one
    /// for one.
    function testCandidatesAreTheCloneListDerived() external {
        ExampleCloneDeploy fixtureDeploy = new ExampleCloneDeploy();

        uint256 clones = fixtureDeploy.externalCloneDeploysLength();
        DeployCandidate[] memory candidates = fixtureDeploy.externalCheckedCandidateSuites();

        assertEq(candidates.length, clones, "one candidate per clone");
        assertEq(clones, 2, "the fixture declares two, so a loop that stops early is visible");

        for (uint256 i = 0; i < clones; i++) {
            DeployCandidate memory derived = fixtureDeploy.externalCloneDeployCandidate(i);
            assertEq(candidates[i].snapshot.suite, derived.snapshot.suite);
            assertEq(candidates[i].snapshot.creationCode, derived.snapshot.creationCode);
            assertEq(candidates[i].snapshot.storedDeployedAddress, derived.snapshot.storedDeployedAddress);
            assertEq(candidates[i].snapshot.storedBytecodeHash, derived.snapshot.storedBytecodeHash);
            assertEq(candidates[i].snapshot.storedRuntimeCode, derived.snapshot.storedRuntimeCode);
            assertEq(candidates[i].snapshot.artifactPath, CLONE_ARTIFACT_PATH);
            assertEq(uint256(candidates[i].snapshot.mechanism), uint256(derived.snapshot.mechanism));
            assertEq(candidates[i].snapshot.mechanismData, derived.snapshot.mechanismData);
            assertEq(candidates[i].snapshot.dependencies.length, derived.snapshot.dependencies.length);
            assertEq(candidates[i].unanchorableReason, derived.unanchorableReason);
        }

        assertNotEq(candidates[0].snapshot.storedDeployedAddress, candidates[1].snapshot.storedDeployedAddress);
    }

    /// The derived candidates MUST satisfy `checkedCandidateSuites` — the qualifier rule included.
    function testCloneCandidatesPassTheSourceAnchor() external {
        ExampleCloneDeploy fixtureDeploy = new ExampleCloneDeploy();
        fixtureDeploy.externalCheckCandidatesAnchoredToSource();
    }

    /// Empty clone and beacon proxy lists MUST be refused with `NoFactoryDeploys`, on EVERY reader that
    /// goes through them.
    function testNoFactoryDeploysReverts() external {
        NoCloneDeploySuites empty = new NoCloneDeploySuites();

        vm.expectRevert(abi.encodeWithSelector(NoFactoryDeploys.selector));
        empty.externalCheckedCandidateSuites();

        vm.expectRevert(abi.encodeWithSelector(NoFactoryDeploys.selector));
        empty.externalCheckCandidatesAnchoredToSource();

        vm.expectRevert(abi.encodeWithSelector(NoFactoryDeploys.selector));
        empty.externalAllSuites();

        vm.expectRevert(abi.encodeWithSelector(NoFactoryDeploys.selector));
        empty.externalSuiteNames();
    }

    /// A per-network clone's candidate has one entry per supported network, in
    /// `supportedNetworks()` order, each with that network's chain id, the init data `initData`
    /// gives for it and the address that data derives.
    function testPerNetworkCandidateIsBuiltForExactlyTheSupportedNetworksInOrder() external {
        string[] memory networks = new string[](2);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;
        networks[1] = LibRainDeploy.POLYGON;
        uint256[] memory chainIds = new uint256[](2);
        chainIds[0] = 42161;
        chainIds[1] = 137;
        checkPerNetworkCandidate(networks, chainIds);

        networks[0] = LibRainDeploy.POLYGON;
        networks[1] = LibRainDeploy.ARBITRUM_ONE;
        chainIds[0] = 137;
        chainIds[1] = 42161;
        checkPerNetworkCandidate(networks, chainIds);

        networks = new string[](1);
        networks[0] = LibRainDeploy.POLYGON;
        chainIds = new uint256[](1);
        chainIds[0] = 137;
        checkPerNetworkCandidate(networks, chainIds);
    }

    /// A supported network the clone's `initData` reverts on reverts every reader of the
    /// candidates, with `initData`'s own revert.
    function testSupportedNetworkTheInitDataRevertsOnIsLoud() external {
        string[] memory networks = new string[](3);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;
        networks[1] = LibRainDeploy.POLYGON;
        networks[2] = LibRainDeploy.BASE;
        ConfigurablePerNetworkCloneDeploy deploy = new ConfigurablePerNetworkCloneDeploy(networks);
        bytes memory refusal = abi.encodeWithSelector(NoPerNetworkCloneAdmin.selector, uint256(8453));

        vm.expectRevert(refusal);
        deploy.externalCheckedCandidateSuites();
        vm.expectRevert(refusal);
        deploy.externalAllSuites();
        vm.expectRevert(refusal);
        deploy.externalCheckCandidatesAnchoredToSource();
        vm.expectRevert(refusal);
        deploy.externalCloneDeployCandidate(0);
    }

    /// Checks the per-network candidate of a declaration supporting `networks`.
    /// @param networks The supported networks, in order.
    /// @param chainIds Their chain ids, as facts of the world, in the same order.
    function checkPerNetworkCandidate(string[] memory networks, uint256[] memory chainIds) internal {
        ConfigurablePerNetworkCloneDeploy deploy = new ConfigurablePerNetworkCloneDeploy(networks);
        assertEq(deploy.externalSupportedChainIds(), chainIds);
        DeployCandidate[] memory candidates = deploy.externalCheckedCandidateSuites();
        assertEq(candidates.length, 1);
        CloneNetworks memory clones = abi.decode(candidates[0].snapshot.mechanismData, (CloneNetworks));
        assertEq(clones.networks.length, chainIds.length, "one entry per supported network");
        for (uint256 i = 0; i < chainIds.length; i++) {
            bytes memory data = abi.encode(
                chainIds[i] == 42161 ? PER_NETWORK_CLONE_ARBITRUM_ONE_ADMIN : PER_NETWORK_CLONE_POLYGON_ADMIN
            );
            assertEq(clones.networks[i].chainId, chainIds[i]);
            assertEq(clones.networks[i].data, data);
            assertEq(
                clones.networks[i].deployedAddress,
                LibRainDeployClone.cloneDeployedAddress(
                    CloneTarget({
                        factory: exampleCloneFactory(),
                        implementation: exampleCloneImplementation(),
                        data: data,
                        salt: clones.salt
                    })
                )
            );
        }
    }

    /// @param actual The candidate read.
    /// @param expected The candidate derived on its own.
    function assertSameCandidate(DeployCandidate memory actual, DeployCandidate memory expected) internal pure {
        assertEq(actual.snapshot.suite, expected.snapshot.suite);
        assertEq(actual.snapshot.creationCode, expected.snapshot.creationCode);
        assertEq(actual.snapshot.storedDeployedAddress, expected.snapshot.storedDeployedAddress);
        assertEq(actual.snapshot.storedBytecodeHash, expected.snapshot.storedBytecodeHash);
        assertEq(actual.snapshot.storedRuntimeCode, expected.snapshot.storedRuntimeCode);
        assertEq(actual.snapshot.artifactPath, expected.snapshot.artifactPath);
        assertEq(uint256(actual.snapshot.mechanism), uint256(expected.snapshot.mechanism));
        assertEq(actual.snapshot.mechanismData, expected.snapshot.mechanismData);
        assertEq(abi.encode(actual.snapshot.dependencies), abi.encode(expected.snapshot.dependencies));
        assertEq(actual.unanchorableReason, expected.unanchorableReason);
    }

    /// With no clones, the candidates MUST be `beaconProxyCandidate` mapped over `beaconProxyDeploys()`, and
    /// every reader of them answers rather than refusing `NoFactoryDeploys`.
    function testCandidatesAreTheBeaconProxyListDerived() external {
        BeaconProxyOnlyDeploySuites deploy = new BeaconProxyOnlyDeploySuites();
        assertEq(deploy.externalCloneDeploysLength(), 0);
        assertEq(deploy.externalBeaconProxyDeploysLength(), 1);

        DeployCandidate[] memory candidates = deploy.externalCheckedCandidateSuites();
        assertEq(candidates.length, 1);
        assertSameCandidate(candidates[0], deploy.externalBeaconProxyDeployCandidate(0));
        assertEq(uint256(candidates[0].snapshot.mechanism), uint256(DeployMechanism.BeaconProxy));
        assertEq(candidates[0].snapshot.artifactPath, BEACON_PROXY_ARTIFACT_PATH);

        deploy.externalCheckCandidatesAnchoredToSource();
        DeploySuite[] memory suites = deploy.externalAllSuites();
        assertEq(suites.length, 1);
        assertEq(suites[0].suite, "example-beacon-proxy");
        assertEq(deploy.externalSuiteNames(), "example-beacon-proxy");
    }

    /// With both, the candidates MUST be the clones' candidates, in order, then the beacon proxies'.
    function testCandidatesAreTheClonesThenTheBeaconProxies() external {
        MixedCloneBeaconProxyDeploySuites deploy = new MixedCloneBeaconProxyDeploySuites();
        uint256 clones = deploy.externalCloneDeploysLength();
        uint256 proxies = deploy.externalBeaconProxyDeploysLength();
        assertEq(clones, 2);
        assertEq(proxies, 2);

        DeployCandidate[] memory candidates = deploy.externalCheckedCandidateSuites();
        assertEq(candidates.length, clones + proxies);
        for (uint256 i = 0; i < clones; i++) {
            assertSameCandidate(candidates[i], deploy.externalCloneDeployCandidate(i));
        }
        for (uint256 i = 0; i < proxies; i++) {
            assertSameCandidate(candidates[clones + i], deploy.externalBeaconProxyDeployCandidate(i));
            assertEq(uint256(candidates[clones + i].snapshot.mechanism), uint256(DeployMechanism.BeaconProxy));
        }
        assertNotEq(candidates[2].snapshot.storedDeployedAddress, candidates[3].snapshot.storedDeployedAddress);
        deploy.externalCheckCandidatesAnchoredToSource();
    }
}
