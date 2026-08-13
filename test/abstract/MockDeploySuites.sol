// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {DeployCandidate, DeploySuite, RainDeploySuitesBase} from "../../src/abstract/RainDeploySuitesBase.sol";
import {MockDeployableV2} from "../concrete/MockDeployableV2.sol";
import {
    BYTECODE_HASH as MOCK_DEPLOYABLE_BYTECODE_HASH_0_0_1,
    CREATION_CODE as MOCK_DEPLOYABLE_CREATION_CODE_0_0_1,
    DEPLOYED_ADDRESS as MOCK_DEPLOYABLE_DEPLOYED_ADDRESS_0_0_1,
    RUNTIME_CODE as MOCK_DEPLOYABLE_RUNTIME_CODE_0_0_1
} from "../fixtures/0_0_1/MockDeployable.sol";
import {
    BYTECODE_HASH as MOCK_DEPLOYABLE_V2_BYTECODE_HASH_0_0_2,
    CREATION_CODE as MOCK_DEPLOYABLE_V2_CREATION_CODE_0_0_2,
    DEPLOYED_ADDRESS as MOCK_DEPLOYABLE_V2_DEPLOYED_ADDRESS_0_0_2,
    RUNTIME_CODE as MOCK_DEPLOYABLE_V2_RUNTIME_CODE_0_0_2
} from "../fixtures/0_0_2/MockDeployableV2.sol";

/// @title MockDeploySuites
/// @notice A deploy repo's suite declaration, as a fixture: two frozen
/// releases plus a candidate tracking `MockDeployableV2`.
///
/// It is declared once, here, and inherited into one `RainDeployVerifyOffline`
/// contract and one `RainDeployVerifyChain` contract. That is the shape every
/// consumer has, and it is what keeps the two groups in separate contracts
/// without the versions being written out twice.
///
/// Everything about it is deliberate:
///
/// - `0_0_1` and `0_0_2` take their creation code from frozen literal
///   constants, never from `type(X).creationCode`. A release records what was
///   deployed; that the contract still exists in this repo is incidental.
/// - `0_0_2` and the candidate are the same bytes, which is what a repo looks
///   like between a release and the next source change. Two suites therefore
///   derive one address, under two distinct keys — each is separately
///   deployable, which is how an old release reaches a chain added after it.
/// - The candidate takes its creation code from source, because it has no
///   frozen snapshot to take it from — the state `AddressRegistry` is in.
abstract contract MockDeploySuites is RainDeploySuitesBase {
    /// @inheritdoc RainDeploySuitesBase
    function releasedSuites() internal pure override returns (DeploySuite[] memory suites) {
        suites = new DeploySuite[](2);
        suites[0] = DeploySuite({
            suite: "mock-deployable-0-0-1",
            creationCode: MOCK_DEPLOYABLE_CREATION_CODE_0_0_1,
            storedDeployedAddress: MOCK_DEPLOYABLE_DEPLOYED_ADDRESS_0_0_1,
            storedBytecodeHash: MOCK_DEPLOYABLE_BYTECODE_HASH_0_0_1,
            storedRuntimeCode: MOCK_DEPLOYABLE_RUNTIME_CODE_0_0_1,
            artifactPath: "test/concrete/MockDeployable.sol:MockDeployable",
            dependencies: new address[](0)
        });
        suites[1] = DeploySuite({
            suite: "mock-deployable-v2-0-0-2",
            creationCode: MOCK_DEPLOYABLE_V2_CREATION_CODE_0_0_2,
            storedDeployedAddress: MOCK_DEPLOYABLE_V2_DEPLOYED_ADDRESS_0_0_2,
            storedBytecodeHash: MOCK_DEPLOYABLE_V2_BYTECODE_HASH_0_0_2,
            storedRuntimeCode: MOCK_DEPLOYABLE_V2_RUNTIME_CODE_0_0_2,
            artifactPath: "test/concrete/MockDeployableV2.sol:MockDeployableV2",
            dependencies: new address[](0)
        });
    }

    /// @inheritdoc RainDeploySuitesBase
    function candidateSuite() internal pure override returns (DeployCandidate memory) {
        return DeployCandidate({
            snapshot: DeploySuite({
                suite: "mock-deployable-v2-candidate",
                creationCode: type(MockDeployableV2).creationCode,
                storedDeployedAddress: MOCK_DEPLOYABLE_V2_DEPLOYED_ADDRESS_0_0_2,
                storedBytecodeHash: MOCK_DEPLOYABLE_V2_BYTECODE_HASH_0_0_2,
                storedRuntimeCode: type(MockDeployableV2).runtimeCode,
                artifactPath: "test/concrete/MockDeployableV2.sol:MockDeployableV2",
                dependencies: new address[](0)
            }),
            sourceCreationCode: type(MockDeployableV2).creationCode
        });
    }
}
