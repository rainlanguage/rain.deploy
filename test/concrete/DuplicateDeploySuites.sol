// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DeployCandidate, DeploySuite, RainDeploySuitesBase} from "../../src/abstract/RainDeploySuitesBase.sol";
import {AddressRegistry} from "../../src/concrete/AddressRegistry.sol";
import {
    BYTECODE_HASH as ADDRESS_REGISTRY_BYTECODE_HASH,
    CREATION_CODE as ADDRESS_REGISTRY_CREATION_CODE,
    DEPLOYED_ADDRESS as ADDRESS_REGISTRY_DEPLOYED_ADDRESS,
    RUNTIME_CODE as ADDRESS_REGISTRY_RUNTIME_CODE
} from "../../src/generated/candidate/AddressRegistry.sol";

/// @title DuplicateDeploySuites
/// A declaration whose released suite and candidate share a key — the one thing
/// a registry must refuse, because the key is what selects what gets broadcast.
contract DuplicateDeploySuites is RainDeploySuitesBase {
    /// The suite both entries declare, identically.
    /// @return The colliding suite.
    function collidingSuite() internal pure returns (DeploySuite memory) {
        return DeploySuite({
            suite: "collides",
            creationCode: ADDRESS_REGISTRY_CREATION_CODE,
            storedDeployedAddress: ADDRESS_REGISTRY_DEPLOYED_ADDRESS,
            storedBytecodeHash: ADDRESS_REGISTRY_BYTECODE_HASH,
            storedRuntimeCode: ADDRESS_REGISTRY_RUNTIME_CODE,
            artifactPath: "src/concrete/AddressRegistry.sol:AddressRegistry",
            dependencies: new address[](0)
        });
    }

    /// @inheritdoc RainDeploySuitesBase
    function releasedSuites() internal pure override returns (DeploySuite[] memory suites) {
        suites = new DeploySuite[](1);
        suites[0] = collidingSuite();
    }

    /// @inheritdoc RainDeploySuitesBase
    function candidateSuite() internal pure override returns (DeployCandidate memory) {
        return DeployCandidate({snapshot: collidingSuite(), sourceCreationCode: type(AddressRegistry).creationCode});
    }

    /// @return Every declared suite.
    function externalAllSuites() external pure returns (DeploySuite[] memory) {
        return allSuites();
    }

    /// @param requested The suite key to select.
    /// @return The selected suite.
    function externalSuiteByName(string memory requested) external pure returns (DeploySuite memory) {
        return suiteByName(requested);
    }
}
