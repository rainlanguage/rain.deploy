// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibRainDeployZoltuMechanism} from "../../src/lib/LibRainDeployZoltuMechanism.sol";
import {
    DeployCandidate,
    DeployDependency,
    DeployMechanismHandler,
    DeploySuite,
    RainDeploySuitesBase
} from "../../src/abstract/RainDeploySuitesBase.sol";
import {ExternalDeploySuites} from "../abstract/ExternalDeploySuites.sol";
import {
    BYTECODE_HASH as CONFIG_REGISTRY_BYTECODE_HASH,
    CREATION_CODE as CONFIG_REGISTRY_CREATION_CODE,
    DEPLOYED_ADDRESS as CONFIG_REGISTRY_DEPLOYED_ADDRESS,
    RUNTIME_CODE as CONFIG_REGISTRY_RUNTIME_CODE
} from "../../src/generated/candidate/ConfigRegistry.sol";

/// @title NoCandidateDeploySuites
/// A declaration with releases and NO candidate — the shape that looks like a
/// repo with nothing left to say and is actually a repo that has opted out of
/// the only check catching a snapshot of the wrong contract.
///
/// It declares a release deliberately, so the refusal cannot be passing for the
/// trivial reason that there is nothing declared at all. Everything except the
/// candidate is present and correct.
contract NoCandidateDeploySuites is ExternalDeploySuites {
    function mechanisms() internal pure virtual override returns (DeployMechanismHandler[] memory) {
        DeployMechanismHandler[] memory handlers = new DeployMechanismHandler[](1);
        handlers[0] = LibRainDeployZoltuMechanism.handler();
        return handlers;
    }

    /// @inheritdoc RainDeploySuitesBase
    function releasedSuites() internal pure override returns (DeploySuite[] memory) {
        DeploySuite[] memory suites = new DeploySuite[](1);
        suites[0] = DeploySuite({
            networks: new string[](0),
            suite: "config-registry@0_0_1",
            creationCode: CONFIG_REGISTRY_CREATION_CODE,
            storedDeployedAddress: CONFIG_REGISTRY_DEPLOYED_ADDRESS,
            storedBytecodeHash: CONFIG_REGISTRY_BYTECODE_HASH,
            storedRuntimeCode: CONFIG_REGISTRY_RUNTIME_CODE,
            artifactPath: "src/concrete/ConfigRegistry.sol:ConfigRegistry",
            dependencies: new DeployDependency[](0),
            mechanismData: ""
        });
        return suites;
    }

    /// @inheritdoc RainDeploySuitesBase
    function candidateSuites() internal pure override returns (DeployCandidate[] memory) {
        DeployCandidate[] memory candidates = new DeployCandidate[](0);
        return candidates;
    }
}
