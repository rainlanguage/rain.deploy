// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {
    DeployDependency,
    DeployCandidate,
    DeploySuite,
    RainDeploySuitesBase
} from "../../src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeploy} from "../../src/lib/LibRainDeploy.sol";
import {ExternalDeploySuites} from "../abstract/ExternalDeploySuites.sol";
import {MockDeployableV2} from "./MockDeployableV2.sol";

/// @title UnanchorableWithStaleArtifactDeploySuites
/// @notice The same claim over a snapshot that is ALSO of the wrong contract —
/// the use a repo whose anchor has gone red would put the field to.
///
/// `MisanchoredDeploySuites` with a reason string added, and nothing else: the
/// record is `MockDeployableV2` while the contract it names is
/// `MockDeployable`, and one line now claims no compiler produces either.
///
/// It MUST be refused as the claim being false rather than reported as the
/// mismatch, because the mismatch is what the claim would be hiding. That is
/// also what separates a check that asks whether the artifact resolves from one
/// that compares first and reads the reason afterwards: the second reverts with
/// `CandidateSourceMismatch` here and is satisfied by the field everywhere a
/// record happens to agree.
contract UnanchorableWithStaleArtifactDeploySuites is ExternalDeploySuites {
    /// @inheritdoc RainDeploySuitesBase
    function releasedSuites() internal pure override returns (DeploySuite[] memory suites) {
        suites = new DeploySuite[](0);
    }

    /// @inheritdoc RainDeploySuitesBase
    function candidateSuites() internal pure override returns (DeployCandidate[] memory candidates) {
        candidates = new DeployCandidate[](1);
        candidates[0] = DeployCandidate({
            snapshot: DeploySuite({
                suite: "stale-source-candidate",
                creationCode: type(MockDeployableV2).creationCode,
                storedDeployedAddress: LibRainDeploy.zoltuAddress(type(MockDeployableV2).creationCode),
                storedBytecodeHash: keccak256(type(MockDeployableV2).runtimeCode),
                storedRuntimeCode: type(MockDeployableV2).runtimeCode,
                // Deliberately NOT `MockDeployableV2`, which every recorded field above is.
                artifactPath: "test/concrete/MockDeployable.sol:MockDeployable",
                dependencies: new DeployDependency[](0)
            }),
            unanchorableReason: "There is no source file to compile."
        });
    }
}
