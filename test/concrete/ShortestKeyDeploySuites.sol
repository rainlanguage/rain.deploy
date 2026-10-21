// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {
    DeployCandidate,
    DeployDependency,
    DeployMechanism,
    DeploySuite,
    RainDeploySuitesBase
} from "../../src/abstract/RainDeploySuitesBase.sol";
import {ExternalDeploySuites} from "../abstract/ExternalDeploySuites.sol";
import {MockDeployableV2} from "./MockDeployableV2.sol";
import {LibRainDeploy} from "../../src/lib/LibRainDeploy.sol";
import {
    BYTECODE_HASH as CONFIG_REGISTRY_BYTECODE_HASH,
    CREATION_CODE as CONFIG_REGISTRY_CREATION_CODE,
    DEPLOYED_ADDRESS as CONFIG_REGISTRY_DEPLOYED_ADDRESS,
    RUNTIME_CODE as CONFIG_REGISTRY_RUNTIME_CODE
} from "../../src/generated/candidate/ConfigRegistry.sol";

/// @title ShortestKeyDeploySuites
/// A declaration whose keys are the SHORTEST a key can be — one byte each.
///
/// The rule the registry enforces is that a key is not the empty string, and
/// nothing else in this repo is declared shorter than six bytes. So a check
/// spelled as any other short-key threshold refuses this perfectly ordinary
/// declaration while every other fixture still answers, and that is the whole
/// distance between "absent" and "short".
contract ShortestKeyDeploySuites is ExternalDeploySuites {
    /// @inheritdoc RainDeploySuitesBase
    function releasedSuites() internal pure override returns (DeploySuite[] memory) {
        DeploySuite[] memory suites = new DeploySuite[](1);
        suites[0] = DeploySuite({
            suite: "a",
            creationCode: CONFIG_REGISTRY_CREATION_CODE,
            storedDeployedAddress: CONFIG_REGISTRY_DEPLOYED_ADDRESS,
            storedBytecodeHash: CONFIG_REGISTRY_BYTECODE_HASH,
            storedRuntimeCode: CONFIG_REGISTRY_RUNTIME_CODE,
            artifactPath: "src/concrete/ConfigRegistry.sol:ConfigRegistry",
            dependencies: new DeployDependency[](0),
            mechanism: DeployMechanism.Zoltu,
            mechanismData: "",
            describedByMeta: ""
        });
        return suites;
    }

    /// @inheritdoc RainDeploySuitesBase
    function candidateSuites() internal pure override returns (DeployCandidate[] memory) {
        DeployCandidate[] memory candidates = new DeployCandidate[](1);
        candidates[0] = DeployCandidate({
            snapshot: DeploySuite({
                suite: "z",
                creationCode: type(MockDeployableV2).creationCode,
                storedDeployedAddress: LibRainDeploy.zoltuAddress(type(MockDeployableV2).creationCode),
                storedBytecodeHash: keccak256(type(MockDeployableV2).runtimeCode),
                storedRuntimeCode: type(MockDeployableV2).runtimeCode,
                artifactPath: "test/concrete/MockDeployableV2.sol:MockDeployableV2",
                dependencies: new DeployDependency[](0),
                mechanism: DeployMechanism.Zoltu,
                mechanismData: "",
                describedByMeta: ""
            }),
            unanchorableReason: ""
        });
        return candidates;
    }
}
