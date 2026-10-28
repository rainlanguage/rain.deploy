// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {
    DeployCandidate,
    DeployDependency,
    DeployMechanismHandler,
    DeploySuite,
    RainDeploySuitesBase
} from "../../src/abstract/RainDeploySuitesBase.sol";
import {ChainDeploy} from "../../src/lib/LibRainDeployExtendedNetworks.sol";
import {LibRainDeployZoltuMechanism} from "../../src/lib/LibRainDeployZoltuMechanism.sol";
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
/// @notice One declaration over two non-Zoltu mechanisms and Zoltu: a `LibMockCreate2Mechanism` candidate on Arbitrum
/// One and Polygon, and a `LibMockSaltMechanism` candidate.
abstract contract TwoMechanismDeploySuites is RainDeploySuitesBase {
    function mechanisms() internal pure virtual override returns (DeployMechanismHandler[] memory) {
        DeployMechanismHandler[] memory handlers = new DeployMechanismHandler[](3);
        handlers[0] = LibMockSaltMechanism.handler();
        handlers[1] = LibMockCreate2Mechanism.handler();
        handlers[2] = LibRainDeployZoltuMechanism.handler();
        return handlers;
    }

    function create2Candidate() internal pure returns (DeploySuite memory) {
        ChainDeploy[] memory networks = new ChainDeploy[](2);
        for (uint256 i = 0; i < 2; i++) {
            bytes memory data = abi.encode(i == 0 ? 42161 : 137);
            networks[i] = ChainDeploy({
                chainId: i == 0 ? 42161 : 137,
                data: data,
                deployedAddress: LibMockCreate2Mechanism.create2Address(
                    MOCK_CREATE2_FACTORY,
                    LibMockCreate2Mechanism.networkSalt(MOCK_CREATE2_SALT, data),
                    type(MockDeployable).creationCode
                )
            });
        }
        return DeploySuite({
            suite: "mock-create-two",
            creationCode: type(MockDeployable).creationCode,
            storedDeployedAddress: address(0),
            storedBytecodeHash: keccak256(type(MockDeployable).runtimeCode),
            storedRuntimeCode: type(MockDeployable).runtimeCode,
            artifactPath: "test/concrete/MockDeployable.sol:MockDeployable",
            dependencies: new DeployDependency[](0),
            mechanismData: LibMockCreate2Mechanism.encode(
                MockCreate2Mechanism({
                    factory: MOCK_CREATE2_FACTORY, salt: MOCK_CREATE2_SALT, beacon: address(0), networks: networks
                })
            )
        });
    }

    function saltCandidate() internal pure returns (DeploySuite memory) {
        return DeploySuite({
            suite: "mock-salt",
            creationCode: type(MockDeployableV2).creationCode,
            storedDeployedAddress: LibMockCreate2Mechanism.create2Address(
                MOCK_CREATE2_FACTORY, TWO_MECHANISM_SALT, type(MockDeployableV2).creationCode
            ),
            storedBytecodeHash: keccak256(type(MockDeployableV2).runtimeCode),
            storedRuntimeCode: type(MockDeployableV2).runtimeCode,
            artifactPath: "test/concrete/MockDeployableV2.sol:MockDeployableV2",
            dependencies: new DeployDependency[](0),
            mechanismData: LibMockSaltMechanism.encode(TWO_MECHANISM_SALT)
        });
    }

    function releasedSuites() internal pure virtual override returns (DeploySuite[] memory) {
        return new DeploySuite[](0);
    }

    function candidateSuites() internal view virtual override returns (DeployCandidate[] memory) {
        DeployCandidate[] memory candidates = new DeployCandidate[](2);
        candidates[0] = DeployCandidate({snapshot: create2Candidate(), unanchorableReason: ""});
        candidates[1] = DeployCandidate({snapshot: saltCandidate(), unanchorableReason: ""});
        return candidates;
    }
}
