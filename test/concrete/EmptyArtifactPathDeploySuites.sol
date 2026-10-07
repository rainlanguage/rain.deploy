// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {
    DeployCandidate,
    DeployDependency,
    DeploySuite,
    RainDeploySuitesBase
} from "../../src/abstract/RainDeploySuitesBase.sol";
import {ExternalDeploySuites} from "../abstract/ExternalDeploySuites.sol";
import {LibRainDeploy} from "../../src/lib/LibRainDeploy.sol";
import {MockDeployable} from "./MockDeployable.sol";
import {MockDeployableV2} from "./MockDeployableV2.sol";

/// @title EmptyArtifactPathDeploySuites
/// A declaration whose CANDIDATE names no artifact at all: `artifactPath: ""`.
///
/// The case an unanchorable candidate reaches for first, and the reason
/// `LibRainDeployClone` spells a constant path instead. "No compiler produces
/// this contract" reads naturally as "there is no path", so a consumer declaring
/// an EIP-1167 proxy — or any other derived contract — writes the empty string
/// and expects `unanchorableReason` to carry the explanation on its own.
///
/// It does not work, and the refusal is not obvious from reading
/// `checkedCandidateSuites`: the qualifier scan is
/// `for (j = 0; j + 5 <= path.length; j++)`, so on an empty path the loop body
/// never runs, `qualified` is never set, and `UnqualifiedCandidateArtifactPath`
/// is raised by the fall-through rather than by any test the path failed. The
/// rule is the SHAPE `<path>:<Name>`, applied to unanchorable candidates too, and
/// the empty string has no shape.
///
/// This fixture is what makes that a measured fact rather than a reading of the
/// loop bounds, and it is why `CLONE_ARTIFACT_PATH` exists.
///
/// Offender SECOND, for the reason `UnqualifiedArtifactPathDeploySuites` puts its
/// own there: a refusal reporting a fixed position would still pass a test that
/// only asked whether it reverted.
contract EmptyArtifactPathDeploySuites is ExternalDeploySuites {
    /// @inheritdoc RainDeploySuitesBase
    function releasedSuites() internal pure override returns (DeploySuite[] memory suites) {
        suites = new DeploySuite[](0);
    }

    /// @inheritdoc RainDeploySuitesBase
    function candidateSuites() internal pure override returns (DeployCandidate[] memory candidates) {
        candidates = new DeployCandidate[](2);
        candidates[0] = DeployCandidate({
            snapshot: DeploySuite({
                suite: "qualified-candidate",
                creationCode: type(MockDeployable).creationCode,
                storedDeployedAddress: LibRainDeploy.zoltuAddress(type(MockDeployable).creationCode),
                storedBytecodeHash: keccak256(type(MockDeployable).runtimeCode),
                storedRuntimeCode: type(MockDeployable).runtimeCode,
                artifactPath: "test/concrete/MockDeployable.sol:MockDeployable",
                dependencies: new DeployDependency[](0)
            }),
            unanchorableReason: ""
        });
        candidates[1] = DeployCandidate({
            snapshot: DeploySuite({
                suite: "empty-path-candidate",
                creationCode: type(MockDeployableV2).creationCode,
                storedDeployedAddress: LibRainDeploy.zoltuAddress(type(MockDeployableV2).creationCode),
                storedBytecodeHash: keccak256(type(MockDeployableV2).runtimeCode),
                storedRuntimeCode: type(MockDeployableV2).runtimeCode,
                artifactPath: "",
                dependencies: new DeployDependency[](0)
            }),
            // Non-empty, because this is the shape a consumer reaching for the
            // empty path actually writes: the reason is SUPPOSED to be what
            // excuses the missing artifact. That it does not excuse the missing
            // PATH is the point of the fixture.
            unanchorableReason: "Derived bytes, with no source to anchor to."
        });
    }
}
