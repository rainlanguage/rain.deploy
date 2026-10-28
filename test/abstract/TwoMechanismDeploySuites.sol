// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {
    DeployCandidate,
    DeployDeclaration,
    DeployDependency,
    DeploySuite,
    RainDeploySuitesBase
} from "../../src/abstract/RainDeploySuitesBase.sol";
import {MockNetworkDeploy} from "../lib/LibMockNetworkRecord.sol";
import {LibRainDeployDeclaration} from "../../src/lib/LibRainDeployDeclaration.sol";
import {
    LibMockCreate2Mechanism,
    MOCK_CREATE2_FACTORY,
    MOCK_CREATE2_SALT,
    MockCreate2Mechanism
} from "../lib/LibMockCreate2Mechanism.sol";
import {LibMockSaltMechanism} from "../lib/LibMockSaltMechanism.sol";
import {MockDeployable} from "../concrete/MockDeployable.sol";
import {MockDeployableV2} from "../concrete/MockDeployableV2.sol";

bytes32 constant TWO_MECHANISM_SALT = keccak256("rain.deploy.mock.salt");

/// @title TwoMechanismDeploySuites
/// @notice Candidates over two non-Zoltu mechanisms: a per-network `LibMockCreate2Mechanism` candidate on Arbitrum
/// One and Polygon, and a `LibMockSaltMechanism` candidate.
abstract contract TwoMechanismDeploySuites is RainDeploySuitesBase {
    function create2Candidate() internal pure returns (DeploySuite memory) {
        MockNetworkDeploy[] memory networks = new MockNetworkDeploy[](2);
        networks[0] = LibMockCreate2Mechanism.network(
            MOCK_CREATE2_FACTORY, MOCK_CREATE2_SALT, type(MockDeployable).creationCode, 42161, abi.encode(42161)
        );
        networks[1] = LibMockCreate2Mechanism.network(
            MOCK_CREATE2_FACTORY, MOCK_CREATE2_SALT, type(MockDeployable).creationCode, 137, abi.encode(137)
        );
        return DeploySuite({
            networks: LibMockCreate2Mechanism.networkNames(networks),
            suite: "mock-create-two",
            creationCode: type(MockDeployable).creationCode,
            storedDeployedAddress: address(0),
            storedBytecodeHash: keccak256(type(MockDeployable).runtimeCode),
            storedRuntimeCode: type(MockDeployable).runtimeCode,
            artifactPath: "test/concrete/MockDeployable.sol:MockDeployable",
            dependencies: new DeployDependency[](0),
            mechanismData: LibMockCreate2Mechanism.encode(
                MockCreate2Mechanism({
                    factory: MOCK_CREATE2_FACTORY,
                    salt: MOCK_CREATE2_SALT,
                    perNetwork: true,
                    networks: networks,
                    root: ""
                })
            ),
            describedByMeta: ""
        });
    }

    function saltCandidate() internal pure returns (DeploySuite memory) {
        return DeploySuite({
            networks: new string[](0),
            suite: "mock-salt",
            creationCode: type(MockDeployableV2).creationCode,
            storedDeployedAddress: LibMockCreate2Mechanism.create2Address(
                MOCK_CREATE2_FACTORY, TWO_MECHANISM_SALT, type(MockDeployableV2).creationCode
            ),
            storedBytecodeHash: keccak256(type(MockDeployableV2).runtimeCode),
            storedRuntimeCode: type(MockDeployableV2).runtimeCode,
            artifactPath: "test/concrete/MockDeployableV2.sol:MockDeployableV2",
            dependencies: new DeployDependency[](0),
            mechanismData: LibMockSaltMechanism.encode(TWO_MECHANISM_SALT),
            describedByMeta: ""
        });
    }

    /// Adds `create2Candidate()` and `saltCandidate()` to `d`.
    /// @param d The declaration, mutated.
    function addTwoMechanismCandidates(DeployDeclaration memory d) internal pure {
        DeployCandidate[] memory candidates = new DeployCandidate[](2);
        candidates[0] = DeployCandidate({snapshot: create2Candidate(), unanchorableReason: ""});
        candidates[1] = DeployCandidate({snapshot: saltCandidate(), unanchorableReason: ""});
        LibRainDeployDeclaration.addCandidates(d, candidates);
    }
}
