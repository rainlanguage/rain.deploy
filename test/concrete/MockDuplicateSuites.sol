// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DeployCandidate, DeploySuite, RainDeploySuitesBase} from "../../src/abstract/RainDeploySuitesBase.sol";
import {MockDeployable} from "./MockDeployable.sol";
import {MockDeployableV2} from "./MockDeployableV2.sol";

/// @title MockDuplicateSuites
/// A declaration whose released suite and candidate share a key, which is the
/// one thing a registry must refuse: the key is what selects what gets
/// broadcast, so a duplicate makes the selection ambiguous and leaves one of
/// the two unreachable. Deliberately different CONTRACTS under the one key, so
/// the ambiguity is a real one.
contract MockDuplicateSuites is RainDeploySuitesBase {
    /// @inheritdoc RainDeploySuitesBase
    function releasedSuites() internal pure override returns (DeploySuite[] memory suites) {
        suites = new DeploySuite[](1);
        suites[0] = DeploySuite({
            suite: "collides",
            creationCode: type(MockDeployable).creationCode,
            storedDeployedAddress: address(0),
            storedBytecodeHash: bytes32(0),
            storedRuntimeCode: hex"",
            artifactPath: "test/concrete/MockDeployable.sol:MockDeployable",
            dependencies: new address[](0)
        });
    }

    /// @inheritdoc RainDeploySuitesBase
    function candidateSuite() internal pure override returns (DeployCandidate memory) {
        return DeployCandidate({
            snapshot: DeploySuite({
                suite: "collides",
                creationCode: type(MockDeployableV2).creationCode,
                storedDeployedAddress: address(0),
                storedBytecodeHash: bytes32(0),
                storedRuntimeCode: hex"",
                artifactPath: "test/concrete/MockDeployableV2.sol:MockDeployableV2",
                dependencies: new address[](0)
            }),
            sourceCreationCode: type(MockDeployableV2).creationCode
        });
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
