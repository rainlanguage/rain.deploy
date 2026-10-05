// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DeployCandidate, DeploySuite, RainDeploySuitesBase} from "../../src/abstract/RainDeploySuitesBase.sol";
import {ExternalDeploySuites} from "../abstract/ExternalDeploySuites.sol";
import {MockDeployable} from "./MockDeployable.sol";
import {MockDeployableV2} from "./MockDeployableV2.sol";
import {LibRainDeploy} from "../../src/lib/LibRainDeploy.sol";

/// @title UnqualifiedArtifactPathDeploySuites
/// A declaration whose CANDIDATE names its contract by bare name rather than
/// `<path>:<Name>`.
///
/// Nothing else about it is wrong: the bare name resolves, and it resolves to
/// the contract every recorded field is a snapshot of, so with the refusal
/// deleted this declaration passes the source anchor green. What is refused is
/// the PATH — a bare name is answered with whichever same-named artifact
/// resolves first, so a second contract of that name added anywhere later
/// anchors this candidate to it without anything saying so.
///
/// The offending candidate sits SECOND, behind one spelled properly, for the
/// reason `EmptyKeyDeploySuites` puts its bad key second: a check that only
/// looked at the first candidate answers this declaration as if it were fine,
/// and the position is what names the entry at fault.
contract UnqualifiedArtifactPathDeploySuites is ExternalDeploySuites {
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
                dependencies: new address[](0)
            }),
            unanchorableReason: ""
        });
        candidates[1] = DeployCandidate({
            snapshot: DeploySuite({
                suite: "bare-name-candidate",
                creationCode: type(MockDeployableV2).creationCode,
                storedDeployedAddress: LibRainDeploy.zoltuAddress(type(MockDeployableV2).creationCode),
                storedBytecodeHash: keccak256(type(MockDeployableV2).runtimeCode),
                storedRuntimeCode: type(MockDeployableV2).runtimeCode,
                artifactPath: "MockDeployableV2",
                dependencies: new address[](0)
            }),
            unanchorableReason: ""
        });
    }
}
