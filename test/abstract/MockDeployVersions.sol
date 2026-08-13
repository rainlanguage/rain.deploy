// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {DeployCandidate, DeployVersion, RainDeployVerifyBase} from "../../src/abstract/RainDeployVerifyBase.sol";
import {MockDeployableV2} from "../concrete/MockDeployableV2.sol";
import {
    BYTECODE_HASH as MOCK_DEPLOYABLE_BYTECODE_HASH_0_0_1,
    CREATION_CODE as MOCK_DEPLOYABLE_CREATION_CODE_0_0_1,
    DEPLOYED_ADDRESS as MOCK_DEPLOYABLE_DEPLOYED_ADDRESS_0_0_1,
    RUNTIME_CODE as MOCK_DEPLOYABLE_RUNTIME_CODE_0_0_1
} from "../fixtures/0_0_1/MockDeployable.pointers.sol";
import {
    BYTECODE_HASH as MOCK_DEPLOYABLE_V2_BYTECODE_HASH_0_0_2,
    CREATION_CODE as MOCK_DEPLOYABLE_V2_CREATION_CODE_0_0_2,
    DEPLOYED_ADDRESS as MOCK_DEPLOYABLE_V2_DEPLOYED_ADDRESS_0_0_2,
    RUNTIME_CODE as MOCK_DEPLOYABLE_V2_RUNTIME_CODE_0_0_2
} from "../fixtures/0_0_2/MockDeployableV2.pointers.sol";

/// @title MockDeployVersions
/// @notice A deploy repo's version declaration, as a fixture: two frozen
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
///   like between a release and the next source change. Two versions therefore
///   derive one address.
/// - The candidate takes its creation code from source, because it has no
///   frozen snapshot to take it from — the state `AddressRegistry` is in.
abstract contract MockDeployVersions is RainDeployVerifyBase {
    /// @inheritdoc RainDeployVerifyBase
    function releasedVersions() internal pure override returns (DeployVersion[] memory versions) {
        versions = new DeployVersion[](2);
        versions[0] = DeployVersion({
            version: "0_0_1",
            creationCode: MOCK_DEPLOYABLE_CREATION_CODE_0_0_1,
            storedDeployedAddress: MOCK_DEPLOYABLE_DEPLOYED_ADDRESS_0_0_1,
            storedBytecodeHash: MOCK_DEPLOYABLE_BYTECODE_HASH_0_0_1,
            storedRuntimeCode: MOCK_DEPLOYABLE_RUNTIME_CODE_0_0_1
        });
        versions[1] = DeployVersion({
            version: "0_0_2",
            creationCode: MOCK_DEPLOYABLE_V2_CREATION_CODE_0_0_2,
            storedDeployedAddress: MOCK_DEPLOYABLE_V2_DEPLOYED_ADDRESS_0_0_2,
            storedBytecodeHash: MOCK_DEPLOYABLE_V2_BYTECODE_HASH_0_0_2,
            storedRuntimeCode: MOCK_DEPLOYABLE_V2_RUNTIME_CODE_0_0_2
        });
    }

    /// @inheritdoc RainDeployVerifyBase
    function candidateVersion() internal pure override returns (DeployCandidate memory) {
        return DeployCandidate({
            snapshot: DeployVersion({
                version: "candidate",
                creationCode: type(MockDeployableV2).creationCode,
                storedDeployedAddress: MOCK_DEPLOYABLE_V2_DEPLOYED_ADDRESS_0_0_2,
                storedBytecodeHash: MOCK_DEPLOYABLE_V2_BYTECODE_HASH_0_0_2,
                storedRuntimeCode: type(MockDeployableV2).runtimeCode
            }),
            sourceCreationCode: type(MockDeployableV2).creationCode
        });
    }
}
