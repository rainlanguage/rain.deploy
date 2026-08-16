// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {DeployCandidate, DeploySuite, RainDeploySuitesBase} from "../../src/abstract/RainDeploySuitesBase.sol";
import {AddressRegistry} from "../../src/concrete/AddressRegistry.sol";
import {
    BYTECODE_HASH as ADDRESS_REGISTRY_BYTECODE_HASH,
    CREATION_CODE as ADDRESS_REGISTRY_CREATION_CODE,
    DEPLOYED_ADDRESS as ADDRESS_REGISTRY_DEPLOYED_ADDRESS,
    RUNTIME_CODE as ADDRESS_REGISTRY_RUNTIME_CODE
} from "../../src/generated/candidate/AddressRegistry.sol";
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
/// internal to a snapshot passes on it. Only the pairing with
/// `sourceCreationCode` says it describes the wrong contract, which is why the
/// source anchor is the only thing that can catch it.
///
/// `MockDeployable` and `MockDeployableV2` are the pair, deliberately: the
/// snapshot is `V2`'s while the source is `MockDeployable`'s, which is exactly
/// the shape of a snapshot regenerated from a build that has since moved, or
/// generated from the wrong contract in a repo that compiles several.
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
    function releasedSuites() internal pure override returns (DeploySuite[] memory suites) {
        suites = new DeploySuite[](0);
    }

    /// @inheritdoc RainDeploySuitesBase
    function candidateSuites() internal pure override returns (DeployCandidate[] memory candidates) {
        candidates = new DeployCandidate[](2);
        candidates[0] = DeployCandidate({
            snapshot: DeploySuite({
                suite: "anchored-candidate",
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
                suite: "mismatched-candidate",
                creationCode: type(MockDeployableV2).creationCode,
                storedDeployedAddress: LibRainDeploy.zoltuAddress(type(MockDeployableV2).creationCode),
                storedBytecodeHash: keccak256(type(MockDeployableV2).runtimeCode),
                storedRuntimeCode: type(MockDeployableV2).runtimeCode,
                artifactPath: "test/concrete/MockDeployableV2.sol:MockDeployableV2",
                dependencies: new address[](0)
            }),
            sourceCreationCode: type(MockDeployable).creationCode
        });
    }
}
