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
import {MockDeployableV2} from "../concrete/MockDeployableV2.sol";

/// @title ExampleDeploySuites
/// @notice A deploy repo's suite declaration, as the verification abstracts see
/// it: a released `AddressRegistry` and a candidate `AddressRegistry`, both
/// reading the real `src/generated/candidate/AddressRegistry.sol` snapshot this
/// repo generates.
///
/// That pair is the configuration every consumer has, and it is what makes the
/// released and candidate paths, and two suites deriving one address, real
/// rather than simulated.
///
/// The `MockDeployableV2` entries exist for one reason: every loop here runs
/// over a list, and proving a loop does not stop at the first entry requires a
/// second entry at a DIFFERENT address. `AddressRegistry` is the only concrete
/// in this repo, so the second address comes from `MockDeployableV2`, which is
/// already on main for `LibRainDeploy`'s own tests. Without it, "the matrix
/// silently checks only the first suite" is undetectable — the failure mode
/// that matters most to the repos this abstract exists for, where ten suites
/// sit at ten addresses.
///
/// It appears on BOTH sides for that reason, once as a release and once as a
/// candidate. The released side is the chain matrix's second address; the
/// candidate side is the source anchor's, which loops over the candidates
/// alone and would otherwise be a loop with one thing in it.
abstract contract ExampleDeploySuites is RainDeploySuitesBase {
    /// @inheritdoc RainDeploySuitesBase
    function releasedSuites() internal pure override returns (DeploySuite[] memory suites) {
        suites = new DeploySuite[](2);
        suites[0] = DeploySuite({
            suite: "address-registry-0-0-1",
            creationCode: ADDRESS_REGISTRY_CREATION_CODE,
            storedDeployedAddress: ADDRESS_REGISTRY_DEPLOYED_ADDRESS,
            storedBytecodeHash: ADDRESS_REGISTRY_BYTECODE_HASH,
            storedRuntimeCode: ADDRESS_REGISTRY_RUNTIME_CODE,
            artifactPath: "src/concrete/AddressRegistry.sol:AddressRegistry",
            dependencies: new address[](0)
        });
        suites[1] = DeploySuite({
            suite: "second-address",
            creationCode: type(MockDeployableV2).creationCode,
            storedDeployedAddress: LibRainDeploy.zoltuAddress(type(MockDeployableV2).creationCode),
            storedBytecodeHash: keccak256(type(MockDeployableV2).runtimeCode),
            storedRuntimeCode: type(MockDeployableV2).runtimeCode,
            artifactPath: "test/concrete/MockDeployableV2.sol:MockDeployableV2",
            dependencies: new address[](0)
        });
    }

    /// @inheritdoc RainDeploySuitesBase
    /// @dev TWO candidates, at two different addresses and anchored to two
    /// different sources, because a repo that deploys more than one contract is
    /// what the list exists for. One candidate cannot tell a loop that runs
    /// over every candidate apart from one that stops at the first, and the
    /// source anchor is the only check that catches a snapshot of the wrong
    /// contract — so a loop that stops early is a contract nothing anchors.
    function candidateSuites() internal pure override returns (DeployCandidate[] memory candidates) {
        candidates = new DeployCandidate[](2);
        candidates[0] = DeployCandidate({
            snapshot: DeploySuite({
                suite: "address-registry-candidate",
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
                suite: "second-address-candidate",
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
