// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DeployCandidate, DeploySuite, RainDeploySuitesBase} from "../../src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeploy} from "../../src/lib/LibRainDeploy.sol";
import {ExternalDeploySuites} from "../abstract/ExternalDeploySuites.sol";
import {MockDeployableV2} from "./MockDeployableV2.sol";
import {VENDORED_CREATION_CODE} from "./UnanchorableDeploy.sol";

/// @title UnanchorableWithArtifactDeploySuites
/// @notice A declaration claiming no compiler produces a candidate whose
/// contract the compiler produces — the exemption spelled on an ORDINARY
/// candidate.
///
/// The offending candidate is otherwise perfect: it records exactly what its
/// `artifactPath` compiles to, so it would pass the anchor with the claim
/// deleted. Nothing about the SNAPSHOT is wrong, which is the point — what is
/// refused is the declaration, and a check that only refused a claim it caught
/// disagreeing with an artifact would pass this and leave the next edit to that
/// contract anchored by nothing.
///
/// It is the SECOND candidate, behind a legitimately unanchorable one, so the
/// refusal naming it is also what says the loop passes OVER an exemption rather
/// than stopping at it.
contract UnanchorableWithArtifactDeploySuites is ExternalDeploySuites {
    /// @inheritdoc RainDeploySuitesBase
    function releasedSuites() internal pure override returns (DeploySuite[] memory suites) {
        suites = new DeploySuite[](0);
    }

    /// @inheritdoc RainDeploySuitesBase
    function candidateSuites() internal pure override returns (DeployCandidate[] memory candidates) {
        candidates = new DeployCandidate[](2);
        candidates[0] = DeployCandidate({
            snapshot: DeploySuite({
                suite: "vendored-candidate",
                creationCode: VENDORED_CREATION_CODE,
                storedDeployedAddress: LibRainDeploy.zoltuAddress(VENDORED_CREATION_CODE),
                storedBytecodeHash: keccak256(hex""),
                storedRuntimeCode: hex"",
                artifactPath: "test/concrete/VendoredDeployable.sol:VendoredDeployable",
                dependencies: new address[](0)
            }),
            unanchorableReason: "Vendored third party deployment: the pinned creation code is the source."
        });
        candidates[1] = DeployCandidate({
            snapshot: DeploySuite({
                suite: "current-source-candidate",
                creationCode: type(MockDeployableV2).creationCode,
                storedDeployedAddress: LibRainDeploy.zoltuAddress(type(MockDeployableV2).creationCode),
                storedBytecodeHash: keccak256(type(MockDeployableV2).runtimeCode),
                storedRuntimeCode: type(MockDeployableV2).runtimeCode,
                // Resolves, and to the contract every recorded field above is.
                artifactPath: "test/concrete/MockDeployableV2.sol:MockDeployableV2",
                dependencies: new address[](0)
            }),
            unanchorableReason: "There is no source file to compile."
        });
    }
}
