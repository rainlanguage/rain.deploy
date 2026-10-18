// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {
    DeployCandidate,
    DeployDependency,
    DeployMechanism,
    DeploySuite,
    RainDeploySuitesBase
} from "../../src/abstract/RainDeploySuitesBase.sol";
import {ConfigRegistry} from "../../src/concrete/ConfigRegistry.sol";
import {
    BYTECODE_HASH as CONFIG_REGISTRY_BYTECODE_HASH,
    CREATION_CODE as CONFIG_REGISTRY_CREATION_CODE,
    DEPLOYED_ADDRESS as CONFIG_REGISTRY_DEPLOYED_ADDRESS,
    RUNTIME_CODE as CONFIG_REGISTRY_RUNTIME_CODE
} from "../../src/generated/candidate/ConfigRegistry.sol";
import {LibRainDeploy} from "../../src/lib/LibRainDeploy.sol";
import {MockDeployable} from "../concrete/MockDeployable.sol";
import {MockDeployableV2} from "../concrete/MockDeployableV2.sol";

/// @title SourceMismatchDeploySuites
/// @notice A declaration whose second candidate records a contract that is not
/// the one it claims to be — the stale generated file, as a repo actually holds
/// it.
///
/// The broken candidate is a CONSISTENT snapshot: the address it records is the
/// address its recorded creation code derives, the code hash is the one that
/// creation code produces, and the runtime code hashes to it. Every check
/// internal to a snapshot passes on it. Only the source anchor can catch it.
///
/// `MockDeployable` and `MockDeployableV2` are the pair, deliberately: the
/// snapshot is `V2`'s while the contract it names is `MockDeployable`.
///
/// TWO candidates, broken one LAST, behind a genuinely anchored one. A loop
/// that stops at the first entry is invisible against a single candidate and
/// silently stops anchoring the moment a repo declares two — and a repo with
/// several contracts is precisely where a snapshot of the wrong one comes from.
/// The first is the real `AddressRegistry` this repo compiles, so nothing fails
/// before the loop has to advance, and the failure has to name the SECOND key
/// rather than a fixed one or the first.
///
/// No releases. A release is meant to diverge from current source and is never
/// anchored, so declaring one here would add a suite that this fixture makes no
/// claim about. The keys are its own, shared with no other fixture, because
/// `DEPLOYMENT_SUITE` is a process-wide variable other tests write.
abstract contract SourceMismatchDeploySuites is RainDeploySuitesBase {
    /// @inheritdoc RainDeploySuitesBase
    function releasedSuites() internal pure override returns (DeploySuite[] memory) {
        DeploySuite[] memory suites = new DeploySuite[](0);
        return suites;
    }

    /// @inheritdoc RainDeploySuitesBase
    function candidateSuites() internal pure override returns (DeployCandidate[] memory) {
        DeployCandidate[] memory candidates = new DeployCandidate[](2);
        candidates[0] = DeployCandidate({
            snapshot: DeploySuite({
                suite: "anchored-candidate",
                creationCode: CONFIG_REGISTRY_CREATION_CODE,
                storedDeployedAddress: CONFIG_REGISTRY_DEPLOYED_ADDRESS,
                storedBytecodeHash: CONFIG_REGISTRY_BYTECODE_HASH,
                storedRuntimeCode: CONFIG_REGISTRY_RUNTIME_CODE,
                artifactPath: "src/concrete/ConfigRegistry.sol:ConfigRegistry",
                dependencies: new DeployDependency[](0),
                mechanism: DeployMechanism.Zoltu,
                mechanismData: ""
            }),
            unanchorableReason: ""
        });
        candidates[1] = DeployCandidate({
            snapshot: DeploySuite({
                suite: "mismatched-candidate",
                creationCode: type(MockDeployableV2).creationCode,
                storedDeployedAddress: LibRainDeploy.zoltuAddress(type(MockDeployableV2).creationCode),
                storedBytecodeHash: keccak256(type(MockDeployableV2).runtimeCode),
                storedRuntimeCode: type(MockDeployableV2).runtimeCode,
                // Deliberately NOT `MockDeployableV2`, which every recorded field above is.
                artifactPath: "test/concrete/MockDeployable.sol:MockDeployable",
                dependencies: new DeployDependency[](0),
                mechanism: DeployMechanism.Zoltu,
                mechanismData: ""
            }),
            unanchorableReason: ""
        });
        return candidates;
    }
}
