// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DeployCandidate, DeploySuite, RainDeploySuitesBase} from "../../src/abstract/RainDeploySuitesBase.sol";
import {ExternalDeploySuites} from "../abstract/ExternalDeploySuites.sol";
import {
    BYTECODE_HASH as ADDRESS_REGISTRY_BYTECODE_HASH,
    CREATION_CODE as ADDRESS_REGISTRY_CREATION_CODE,
    DEPLOYED_ADDRESS as ADDRESS_REGISTRY_DEPLOYED_ADDRESS,
    RUNTIME_CODE as ADDRESS_REGISTRY_RUNTIME_CODE
} from "../../src/generated/candidate/AddressRegistry.sol";

/// @title NoCandidateDeploySuites
/// A declaration with releases and NO candidate — the shape that looks like a
/// repo with nothing left to say and is actually a repo that has opted out of
/// the only check catching a snapshot of the wrong contract.
///
/// It declares a release deliberately, so the refusal cannot be passing for the
/// trivial reason that there is nothing declared at all. Everything except the
/// candidate is present and correct.
contract NoCandidateDeploySuites is ExternalDeploySuites {
    /// @inheritdoc RainDeploySuitesBase
    function releasedSuites() internal pure override returns (DeploySuite[] memory suites) {
        suites = new DeploySuite[](1);
        suites[0] = DeploySuite({
            suite: "address-registry-0-0-1",
            creationCode: ADDRESS_REGISTRY_CREATION_CODE,
            storedDeployedAddress: ADDRESS_REGISTRY_DEPLOYED_ADDRESS,
            storedBytecodeHash: ADDRESS_REGISTRY_BYTECODE_HASH,
            storedRuntimeCode: ADDRESS_REGISTRY_RUNTIME_CODE,
            artifactPath: "src/concrete/AddressRegistry.sol:AddressRegistry",
            dependencies: new address[](0)
        });
    }

    /// @inheritdoc RainDeploySuitesBase
    function candidateSuites() internal pure override returns (DeployCandidate[] memory candidates) {
        candidates = new DeployCandidate[](0);
    }
}
