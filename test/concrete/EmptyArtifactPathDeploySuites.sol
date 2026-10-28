// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {
    DeployCandidate,
    DeployDependency,
    DeployDeclaration,
    DeploySuite,
    RainDeploySuitesBase
} from "../../src/abstract/RainDeploySuitesBase.sol";
import {ExternalDeploySuites} from "../abstract/ExternalDeploySuites.sol";
import {LibRainDeploy} from "../../src/lib/LibRainDeploy.sol";
import {LibRainDeployDeclaration} from "../../src/lib/LibRainDeployDeclaration.sol";
import {LibRainDeployZoltuMechanism} from "../../src/lib/LibRainDeployZoltuMechanism.sol";
import {MockDeployable} from "./MockDeployable.sol";
import {MockDeployableV2} from "./MockDeployableV2.sol";

/// @title EmptyArtifactPathDeploySuites A declaration whose CANDIDATE names no artifact at all:
/// `artifactPath: ""`. The case an unanchorable candidate reaches for first. "No compiler produces
/// this contract" reads naturally as "there is no path", so a consumer declaring a derived contract
/// writes the empty string and expects `unanchorableReason` to carry the explanation on its own. It
/// does not work, and the refusal is not obvious from reading `checkedCandidateSuites`: the
/// qualifier scan is `for (j = 0; j + 5 <= path.length; j++)`, so on an empty path the loop body
/// never runs, `qualified` is never set, and `UnqualifiedCandidateArtifactPath` is raised by the
/// fall-through rather than by any test the path failed. The rule is the SHAPE `<path>:<Name>`,
/// applied to unanchorable candidates too, and the empty string has no shape. This fixture is what
/// makes that a measured fact rather than a reading of the loop bounds. Offender SECOND, for the
/// reason `UnqualifiedArtifactPathDeploySuites` puts its own there: a refusal reporting a fixed
/// position would still pass a test that only asked whether it reverted.
contract EmptyArtifactPathDeploySuites is ExternalDeploySuites {
    function declaration() internal pure override returns (DeployDeclaration memory) {
        DeployDeclaration memory d;
        LibRainDeployDeclaration.extend(d);
        LibRainDeployZoltuMechanism.extend(d);
        LibRainDeployDeclaration.addReleased(d, declaredReleased());
        LibRainDeployDeclaration.addCandidates(d, declaredCandidates());
        return d;
    }

    function declaredReleased() internal pure returns (DeploySuite[] memory) {
        return new DeploySuite[](0);
    }

    function declaredCandidates() internal pure returns (DeployCandidate[] memory) {
        DeployCandidate[] memory candidates = new DeployCandidate[](2);
        candidates[0] = DeployCandidate({
            snapshot: DeploySuite({
                networks: new string[](0),
                suite: "qualified-candidate",
                creationCode: type(MockDeployable).creationCode,
                storedDeployedAddress: LibRainDeploy.zoltuAddress(type(MockDeployable).creationCode),
                storedBytecodeHash: keccak256(type(MockDeployable).runtimeCode),
                storedRuntimeCode: type(MockDeployable).runtimeCode,
                artifactPath: "test/concrete/MockDeployable.sol:MockDeployable",
                dependencies: new DeployDependency[](0),
                mechanismData: LibRainDeployZoltuMechanism.mechanismData(),
                describedByMeta: ""
            }),
            unanchorableReason: ""
        });
        candidates[1] = DeployCandidate({
            snapshot: DeploySuite({
                networks: new string[](0),
                suite: "empty-path-candidate",
                creationCode: type(MockDeployableV2).creationCode,
                storedDeployedAddress: LibRainDeploy.zoltuAddress(type(MockDeployableV2).creationCode),
                storedBytecodeHash: keccak256(type(MockDeployableV2).runtimeCode),
                storedRuntimeCode: type(MockDeployableV2).runtimeCode,
                artifactPath: "",
                dependencies: new DeployDependency[](0),
                mechanismData: LibRainDeployZoltuMechanism.mechanismData(),
                describedByMeta: ""
            }),
            unanchorableReason: "Derived bytes, with no source to anchor to."
        });
        return candidates;
    }
}
