// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {DeployCandidate, DeploySuite, RainDeploySuitesBase} from "../../src/abstract/RainDeploySuitesBase.sol";
import {MockDeployableV2} from "../concrete/MockDeployableV2.sol";
import {
    BYTECODE_HASH as MOCK_BYTECODE_HASH_0_0_1,
    CREATION_CODE as MOCK_CREATION_CODE_0_0_1,
    DEPLOYED_ADDRESS as MOCK_DEPLOYED_ADDRESS_0_0_1,
    RUNTIME_CODE as MOCK_RUNTIME_CODE_0_0_1
} from "../generated/0_0_1/MockDeployable.sol";
import {
    BYTECODE_HASH as MOCK_BYTECODE_HASH_0_0_2,
    CREATION_CODE as MOCK_CREATION_CODE_0_0_2,
    DEPLOYED_ADDRESS as MOCK_DEPLOYED_ADDRESS_0_0_2,
    RUNTIME_CODE as MOCK_RUNTIME_CODE_0_0_2
} from "../generated/0_0_2/MockDeployableV2.sol";

/// @title MockDeploySuites
/// @notice A deploy repo's suite declaration, for exercising the verification
/// abstracts: two frozen releases plus a candidate, over two different
/// contracts at two different addresses — which is what a repo with a version
/// history actually looks like. `0_0_2` and the candidate are the same bytes
/// under different keys, so two suites derive one address.
///
/// Both snapshots are REAL generator output, emitted by
/// `script/BuildTestSnapshots.sol` through the same
/// `LibRainDeploySnapshot.writeSnapshot` that writes production deploy records.
/// There is no hand-maintained hex in this repo: a solc bump is
/// `forge script script/BuildTestSnapshots.sol` and commit.
abstract contract MockDeploySuites is RainDeploySuitesBase {
    /// @inheritdoc RainDeploySuitesBase
    function releasedSuites() internal pure override returns (DeploySuite[] memory suites) {
        suites = new DeploySuite[](2);
        suites[0] = DeploySuite({
            suite: "mock-deployable-0-0-1",
            creationCode: MOCK_CREATION_CODE_0_0_1,
            storedDeployedAddress: MOCK_DEPLOYED_ADDRESS_0_0_1,
            storedBytecodeHash: MOCK_BYTECODE_HASH_0_0_1,
            storedRuntimeCode: MOCK_RUNTIME_CODE_0_0_1,
            artifactPath: "test/concrete/MockDeployable.sol:MockDeployable",
            dependencies: new address[](0)
        });
        suites[1] = DeploySuite({
            suite: "mock-deployable-v2-0-0-2",
            creationCode: MOCK_CREATION_CODE_0_0_2,
            storedDeployedAddress: MOCK_DEPLOYED_ADDRESS_0_0_2,
            storedBytecodeHash: MOCK_BYTECODE_HASH_0_0_2,
            storedRuntimeCode: MOCK_RUNTIME_CODE_0_0_2,
            artifactPath: "test/concrete/MockDeployableV2.sol:MockDeployableV2",
            dependencies: new address[](0)
        });
    }

    /// @inheritdoc RainDeploySuitesBase
    function candidateSuite() internal pure override returns (DeployCandidate memory) {
        return DeployCandidate({
            snapshot: DeploySuite({
                suite: "mock-deployable-v2-candidate",
                creationCode: MOCK_CREATION_CODE_0_0_2,
                storedDeployedAddress: MOCK_DEPLOYED_ADDRESS_0_0_2,
                storedBytecodeHash: MOCK_BYTECODE_HASH_0_0_2,
                storedRuntimeCode: MOCK_RUNTIME_CODE_0_0_2,
                artifactPath: "test/concrete/MockDeployableV2.sol:MockDeployableV2",
                dependencies: new address[](0)
            }),
            sourceCreationCode: type(MockDeployableV2).creationCode
        });
    }
}
