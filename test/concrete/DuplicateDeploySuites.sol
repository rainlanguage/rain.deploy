// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibRainDeployDeclaration} from "../../src/lib/LibRainDeployDeclaration.sol";
import {
    DeployCandidate,
    DeployDependency,
    DeployDeclaration,
    DeploySuite,
    RainDeploySuitesBase
} from "../../src/abstract/RainDeploySuitesBase.sol";
import {ExternalDeploySuites} from "../abstract/ExternalDeploySuites.sol";
import {ConfigRegistry} from "../../src/concrete/ConfigRegistry.sol";
import {
    BYTECODE_HASH as CONFIG_REGISTRY_BYTECODE_HASH,
    CREATION_CODE as CONFIG_REGISTRY_CREATION_CODE,
    DEPLOYED_ADDRESS as CONFIG_REGISTRY_DEPLOYED_ADDRESS,
    RUNTIME_CODE as CONFIG_REGISTRY_RUNTIME_CODE
} from "../../src/generated/candidate/ConfigRegistry.sol";

/// @title DuplicateDeploySuites
/// A declaration whose released suite and candidate share a key — the one thing
/// a registry must refuse, because the key is what selects what gets broadcast.
contract DuplicateDeploySuites is ExternalDeploySuites {
    function declaration() internal pure override returns (DeployDeclaration memory) {
        DeployDeclaration memory declared = LibRainDeployDeclaration.zoltu();
        declared.released = declaredReleased();
        declared.candidates = declaredCandidates();
        return declared;
    }


    /// The suite both entries declare, identically.
    /// @return The colliding suite.
    function collidingSuite() internal pure returns (DeploySuite memory) {
        return DeploySuite({
            networks: new string[](0),
            suite: "collides",
            creationCode: CONFIG_REGISTRY_CREATION_CODE,
            storedDeployedAddress: CONFIG_REGISTRY_DEPLOYED_ADDRESS,
            storedBytecodeHash: CONFIG_REGISTRY_BYTECODE_HASH,
            storedRuntimeCode: CONFIG_REGISTRY_RUNTIME_CODE,
            artifactPath: "src/concrete/ConfigRegistry.sol:ConfigRegistry",
            dependencies: new DeployDependency[](0),
            mechanismData: ""
        });
    }

    function declaredReleased() internal pure returns (DeploySuite[] memory) {
        DeploySuite[] memory suites = new DeploySuite[](1);
        suites[0] = collidingSuite();
        return suites;
    }

    function declaredCandidates() internal pure returns (DeployCandidate[] memory) {
        DeployCandidate[] memory candidates = new DeployCandidate[](1);
        candidates[0] = DeployCandidate({snapshot: collidingSuite(), unanchorableReason: ""});
        return candidates;
    }
}
