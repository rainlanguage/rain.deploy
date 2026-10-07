// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {DeployCandidate, DeploySuite, UnknownDeploymentSuite} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {NoCloneDeploys} from "../../../src/abstract/RainDeployCloneSuitesBase.sol";
import {CLONE_ARTIFACT_PATH, CloneDeploy, LibRainDeployClone} from "../../../src/lib/LibRainDeployClone.sol";
import {ExampleCloneDeploy} from "../../concrete/ExampleCloneDeploy.sol";
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

        CloneDeploy[] memory clones = fixtureDeploy.externalCheckedCloneDeploys();
        DeployCandidate[] memory candidates = fixtureDeploy.externalCheckedCandidateSuites();

        assertEq(candidates.length, clones.length, "one candidate per clone");
        assertEq(clones.length, 2, "the fixture declares two, so a loop that stops early is visible");

        for (uint256 i = 0; i < clones.length; i++) {
            DeployCandidate memory derived = LibRainDeployClone.cloneCandidate(clones[i]);
            assertEq(candidates[i].snapshot.suite, derived.snapshot.suite);
            assertEq(candidates[i].snapshot.creationCode, derived.snapshot.creationCode);
            assertEq(candidates[i].snapshot.storedDeployedAddress, derived.snapshot.storedDeployedAddress);
            assertEq(candidates[i].snapshot.storedBytecodeHash, derived.snapshot.storedBytecodeHash);
            assertEq(candidates[i].snapshot.storedRuntimeCode, derived.snapshot.storedRuntimeCode);
            assertEq(candidates[i].snapshot.artifactPath, CLONE_ARTIFACT_PATH);
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

    /// `releasedSuites()` MUST default to empty, so `allSuites()` is the clone
    /// list alone and a clone repo declares nothing it has not cut.
    function testReleasedSuitesDefaultsToEmpty() external {
        ExampleCloneDeploy fixtureDeploy = new ExampleCloneDeploy();
        DeploySuite[] memory all = fixtureDeploy.externalAllSuites();
        assertEq(all.length, 2, "the clones and nothing else");
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
        empty.externalCheckedCloneDeploys();

        vm.expectRevert(abi.encodeWithSelector(NoCloneDeploys.selector));
        empty.externalCheckedCandidateSuites();

        vm.expectRevert(abi.encodeWithSelector(NoCloneDeploys.selector));
        empty.externalCheckCandidatesAnchoredToSource();

        vm.expectRevert(abi.encodeWithSelector(NoCloneDeploys.selector));
        empty.externalAllSuites();

        vm.expectRevert(abi.encodeWithSelector(NoCloneDeploys.selector));
        empty.externalSuiteNames();

        vm.expectRevert(abi.encodeWithSelector(NoCloneDeploys.selector));
        empty.externalCloneDeployByName("anything");
    }

    /// `cloneDeployByName` MUST select the clone the suite key names, and the
    /// candidate that key selects MUST be the one derived from it — which is what
    /// makes the broadcast and the verification the same clone.
    function testCloneDeployByNameSelectsTheDeclaredClone() external {
        ExampleCloneDeploy fixtureDeploy = new ExampleCloneDeploy();

        CloneDeploy memory first = fixtureDeploy.externalCloneDeployByName("example-clone");
        assertEq(first.suite, "example-clone");

        CloneDeploy memory second = fixtureDeploy.externalCloneDeployByName("example-clone-second-salt");
        assertEq(second.suite, "example-clone-second-salt");

        // Not merely a different key: a different clone, at a different address.
        assertNotEq(
            LibRainDeployClone.cloneDeployedAddress(first), LibRainDeployClone.cloneDeployedAddress(second)
        );

        // The selected clone and the selected SUITE agree, which is the one list
        // claim at the point it matters: the broadcast reads the clone, the
        // verification reads the suite.
        DeploySuite memory suite = fixtureDeploy.externalSuiteByName("example-clone");
        assertEq(suite.storedDeployedAddress, LibRainDeployClone.cloneDeployedAddress(first));
        assertEq(suite.storedBytecodeHash, LibRainDeployClone.cloneDeployedCodehash(first.implementation));
    }

    /// An unknown key MUST be refused with `UnknownDeploymentSuite` carrying the
    /// full declared key list, so a caller is told which keys it CAN use.
    function testCloneDeployByNameUnknownKeyReverts() external {
        ExampleCloneDeploy fixtureDeploy = new ExampleCloneDeploy();
        string memory names = fixtureDeploy.externalSuiteNames();

        vm.expectRevert(abi.encodeWithSelector(UnknownDeploymentSuite.selector, "not-a-clone", names));
        fixtureDeploy.externalCloneDeployByName("not-a-clone");
    }
}
