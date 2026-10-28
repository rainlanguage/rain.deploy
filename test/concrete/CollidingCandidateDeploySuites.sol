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
import {ConfigRegistry} from "../../src/concrete/ConfigRegistry.sol";
import {MockDeployableV2} from "./MockDeployableV2.sol";
import {LibRainDeploy} from "../../src/lib/LibRainDeploy.sol";
import {LibRainDeployDeclaration} from "../../src/lib/LibRainDeployDeclaration.sol";
import {
    BYTECODE_HASH as CONFIG_REGISTRY_BYTECODE_HASH,
    CREATION_CODE as CONFIG_REGISTRY_CREATION_CODE,
    DEPLOYED_ADDRESS as CONFIG_REGISTRY_DEPLOYED_ADDRESS,
    RUNTIME_CODE as CONFIG_REGISTRY_RUNTIME_CODE
} from "../../src/generated/candidate/ConfigRegistry.sol";

/// @title CollidingCandidateDeploySuites
/// A declaration with no releases at all and TWO candidates under one key.
///
/// Distinct from `DuplicateDeploySuites`, which collides a release with a
/// candidate. A key that selects what gets broadcast has to be unique across
/// the whole registry, and a candidate-against-candidate collision is the case
/// that only exists once the candidate side is a list — it is unreachable while
/// a repo can declare only one.
///
/// The two candidates are DIFFERENT contracts at different addresses, so the
/// key is the only thing they share: a check that compared anything else would
/// let this through.
contract CollidingCandidateDeploySuites is ExternalDeploySuites {
    function declaration() internal pure override returns (DeployDeclaration memory) {
        DeployDeclaration memory declared = LibRainDeployDeclaration.zoltu();
        declared.released = declaredReleased();
        declared.candidates = declaredCandidates();
        return declared;
    }


    function declaredReleased() internal pure returns (DeploySuite[] memory) {
        DeploySuite[] memory suites = new DeploySuite[](0);
        return suites;
    }

    function declaredCandidates() internal pure returns (DeployCandidate[] memory) {
        DeployCandidate[] memory candidates = new DeployCandidate[](2);
        candidates[0] = DeployCandidate({
            snapshot: DeploySuite({
                networks: new string[](0),
                suite: "collides",
                creationCode: CONFIG_REGISTRY_CREATION_CODE,
                storedDeployedAddress: CONFIG_REGISTRY_DEPLOYED_ADDRESS,
                storedBytecodeHash: CONFIG_REGISTRY_BYTECODE_HASH,
                storedRuntimeCode: CONFIG_REGISTRY_RUNTIME_CODE,
                artifactPath: "src/concrete/ConfigRegistry.sol:ConfigRegistry",
                dependencies: new DeployDependency[](0),
                mechanismData: ""
            }),
            unanchorableReason: ""
        });
        candidates[1] = DeployCandidate({
            snapshot: DeploySuite({
                networks: new string[](0),
                suite: "collides",
                creationCode: type(MockDeployableV2).creationCode,
                storedDeployedAddress: LibRainDeploy.zoltuAddress(type(MockDeployableV2).creationCode),
                storedBytecodeHash: keccak256(type(MockDeployableV2).runtimeCode),
                storedRuntimeCode: type(MockDeployableV2).runtimeCode,
                artifactPath: "test/concrete/MockDeployableV2.sol:MockDeployableV2",
                dependencies: new DeployDependency[](0),
                mechanismData: ""
            }),
            unanchorableReason: ""
        });
        return candidates;
    }
}
