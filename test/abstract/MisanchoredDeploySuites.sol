// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {
    DeployCandidate,
    DeployDependency,
    DeploySuite,
    RainDeploySuitesBase
} from "../../src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeploy} from "../../src/lib/LibRainDeploy.sol";
import {LibRainDeployZoltuMechanism} from "../../src/lib/LibRainDeployZoltuMechanism.sol";
import {MockDeployableV2} from "../concrete/MockDeployableV2.sol";

abstract contract MisanchoredDeploySuites is RainDeploySuitesBase {
    function misanchoredCandidates() internal pure returns (DeployCandidate[] memory) {
        DeployCandidate[] memory candidates = new DeployCandidate[](1);
        candidates[0] = DeployCandidate({
            snapshot: DeploySuite({
                networks: new string[](0),
                suite: "misanchored-candidate",
                creationCode: type(MockDeployableV2).creationCode,
                storedDeployedAddress: LibRainDeploy.zoltuAddress(type(MockDeployableV2).creationCode),
                storedBytecodeHash: keccak256(type(MockDeployableV2).runtimeCode),
                storedRuntimeCode: type(MockDeployableV2).runtimeCode,
                // Deliberately NOT `MockDeployableV2`, which every recorded field above is.
                artifactPath: "test/concrete/MockDeployable.sol:MockDeployable",
                dependencies: new DeployDependency[](0),
                mechanismData: LibRainDeployZoltuMechanism.mechanismData(),
                describedByMeta: ""
            }),
            unanchorableReason: ""
        });
        return candidates;
    }
}
