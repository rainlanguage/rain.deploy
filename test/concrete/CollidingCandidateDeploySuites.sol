// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DeployCandidate, DeploySuite, RainDeploySuitesBase} from "../../src/abstract/RainDeploySuitesBase.sol";
import {ExternalDeploySuites} from "../abstract/ExternalDeploySuites.sol";
import {AddressRegistry} from "../../src/concrete/AddressRegistry.sol";
import {MockDeployableV2} from "./MockDeployableV2.sol";
import {LibRainDeploy} from "../../src/lib/LibRainDeploy.sol";
import {
    BYTECODE_HASH as ADDRESS_REGISTRY_BYTECODE_HASH,
    CREATION_CODE as ADDRESS_REGISTRY_CREATION_CODE,
    DEPLOYED_ADDRESS as ADDRESS_REGISTRY_DEPLOYED_ADDRESS,
    RUNTIME_CODE as ADDRESS_REGISTRY_RUNTIME_CODE
} from "../../src/generated/candidate/AddressRegistry.sol";

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
    /// @inheritdoc RainDeploySuitesBase
    function releasedSuites() internal pure override returns (DeploySuite[] memory suites) {
        suites = new DeploySuite[](0);
    }

    /// @inheritdoc RainDeploySuitesBase
    function candidateSuites() internal pure override returns (DeployCandidate[] memory candidates) {
        candidates = new DeployCandidate[](2);
        candidates[0] = DeployCandidate({
            snapshot: DeploySuite({
                suite: "collides",
                creationCode: ADDRESS_REGISTRY_CREATION_CODE,
                storedDeployedAddress: ADDRESS_REGISTRY_DEPLOYED_ADDRESS,
                storedBytecodeHash: ADDRESS_REGISTRY_BYTECODE_HASH,
                storedRuntimeCode: ADDRESS_REGISTRY_RUNTIME_CODE,
                artifactPath: "src/concrete/AddressRegistry.sol:AddressRegistry",
                dependencies: new address[](0)
            }),
            sourceCreationCode: type(AddressRegistry).creationCode
        });
        candidates[1] = DeployCandidate({
            snapshot: DeploySuite({
                suite: "collides",
                creationCode: type(MockDeployableV2).creationCode,
                storedDeployedAddress: LibRainDeploy.zoltuAddress(type(MockDeployableV2).creationCode),
                storedBytecodeHash: keccak256(type(MockDeployableV2).runtimeCode),
                storedRuntimeCode: type(MockDeployableV2).runtimeCode,
                artifactPath: "test/concrete/MockDeployableV2.sol:MockDeployableV2",
                dependencies: new address[](0)
            }),
            sourceCreationCode: type(MockDeployableV2).creationCode
        });
    }
}
