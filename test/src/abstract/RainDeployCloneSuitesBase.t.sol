// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {DeployCandidate} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {NoCloneDeploys} from "../../../src/abstract/RainDeployCloneSuitesBase.sol";
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

/// @title RainDeployCloneSuitesBaseTest
/// Tests for `RainDeployCloneSuitesBase`: that the candidates ARE the clone list
/// rather than a second list beside it, and that an empty clone list is refused
/// where the consumer wrote it.
contract RainDeployCloneSuitesBaseTest is Test {
    /// `candidateSuites()` MUST be `cloneCandidate` mapped over `cloneDeploys()`,
    /// in order and one for one.
    ///
    /// This is the whole claim of the contract. The hazard this package exists to
    /// close is a repo that broadcasts one thing while its tests verify another,
    /// and that can only happen where there are two lists to disagree — so the
    /// test is not "the candidates look right", it is "the candidates are a pure
    /// function of the clone list", asserted by deriving them again here from the
    /// clones the fixture declares.
    function testCandidatesAreTheCloneListDerived() external {
        ExampleCloneDeploy fixtureDeploy = new ExampleCloneDeploy();

        uint256 clones = fixtureDeploy.externalCheckedCloneDeploysLength();
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

        // The two entries really are at two different addresses, which is what
        // makes "the loop does not stop at the first" an assertion rather than a
        // hope.
        assertNotEq(candidates[0].snapshot.storedDeployedAddress, candidates[1].snapshot.storedDeployedAddress);
    }

    /// The derived candidates MUST satisfy `checkedCandidateSuites` — the
    /// qualifier rule included. A clone declaration that could not be read by the
    /// package's own reader would be useless, and `CLONE_ARTIFACT_PATH` is the
    /// reason it can be.
    function testCloneCandidatesPassTheSourceAnchor() external {
        ExampleCloneDeploy fixtureDeploy = new ExampleCloneDeploy();
        // Does not revert: the path is qualified, and it resolves to no artifact,
        // which is what the non-empty `unanchorableReason` declares. A path that
        // resolved would be refused by `CandidateSourceCompiles`.
        fixtureDeploy.externalCheckCandidatesAnchoredToSource();
    }

    /// An empty clone list MUST be refused with `NoCloneDeploys`, on EVERY reader
    /// that goes through it.
    ///
    /// Every loop over an empty list passes, so a guard on one reader and not
    /// another is a rule with as many spellings as readers. The refusal names the
    /// CLONE list because that is the list a consumer wrote — `NoDeployCandidates`
    /// would send them to `candidateSuites()`, which a clone repo does not write.
    function testNoCloneDeploysReverts() external {
        NoCloneDeploySuites empty = new NoCloneDeploySuites();

        vm.expectRevert(abi.encodeWithSelector(NoCloneDeploys.selector));
        empty.externalCheckedCloneDeploysLength();

        vm.expectRevert(abi.encodeWithSelector(NoCloneDeploys.selector));
        empty.externalCheckedCandidateSuites();

        vm.expectRevert(abi.encodeWithSelector(NoCloneDeploys.selector));
        empty.externalCheckCandidatesAnchoredToSource();

        vm.expectRevert(abi.encodeWithSelector(NoCloneDeploys.selector));
        empty.externalAllSuites();

        vm.expectRevert(abi.encodeWithSelector(NoCloneDeploys.selector));
        empty.externalSuiteNames();
    }

    /// A per-network clone's candidate has one entry per supported network,
    /// in `supportedNetworks()` order, each with that network's chain id, the
    /// init data `initData` gives for it and the address that data derives:
    /// for both orders of the clone's two networks, and for one of them alone.
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

    /// A supported network the clone's `initData` reverts on reverts every
    /// reader of the candidates, with `initData`'s own revert: the network is
    /// neither skipped nor given another network's data.
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
}
