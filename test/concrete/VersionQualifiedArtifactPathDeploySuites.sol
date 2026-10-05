// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DeployCandidate, DeploySuite, RainDeploySuitesBase} from "../../src/abstract/RainDeploySuitesBase.sol";
import {ExternalDeploySuites} from "../abstract/ExternalDeploySuites.sol";
import {MockDeployable} from "./MockDeployable.sol";
import {MockDeployableV2} from "./MockDeployableV2.sol";
import {LibRainDeploy} from "../../src/lib/LibRainDeploy.sol";

/// @title VersionQualifiedArtifactPathDeploySuites
/// A declaration whose CANDIDATE qualifies its contract name with a compiler
/// VERSION instead of a file: `Name:0.8.25`, which forge reads as a name plus a
/// version.
///
/// It carries a colon and qualifies nothing, so a guard looking for any colon
/// admits it. Measured on the pinned forge: `Dup2:0.8.25` resolves to the same
/// bytes as `File.sol:Dup2` with two `Dup2` compiled, which is the ambiguity the
/// refusal exists to stop.
///
/// Offender SECOND, for the reason `UnqualifiedArtifactPathDeploySuites` puts
/// its own there.
contract VersionQualifiedArtifactPathDeploySuites is ExternalDeploySuites {
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
                suite: "version-qualified-candidate",
                creationCode: type(MockDeployableV2).creationCode,
                storedDeployedAddress: LibRainDeploy.zoltuAddress(type(MockDeployableV2).creationCode),
                storedBytecodeHash: keccak256(type(MockDeployableV2).runtimeCode),
                storedRuntimeCode: type(MockDeployableV2).runtimeCode,
                artifactPath: "MockDeployableV2:0.8.25",
                dependencies: new address[](0)
            }),
            unanchorableReason: ""
        });
    }
}
