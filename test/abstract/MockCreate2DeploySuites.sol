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
import {MockDeployable} from "../concrete/MockDeployable.sol";

/// @title MockCreate2DeploySuites
/// @notice Test-only `LibMockCreate2Mechanism` suites: a per-network release and its candidate, whose payloads read
/// their recorded networks under a root set from outside.
abstract contract MockCreate2DeploySuites is RainDeploySuitesBase {
    /// The record root every mock suite's payload names; empty reads no records.
    string internal sMockRecordRoot;

    function setMockRecordRoot(string memory root) external {
        sMockRecordRoot = root;
    }

    function mockNetwork(uint256 chainId) internal pure returns (MockNetworkDeploy memory) {
        return LibMockCreate2Mechanism.network(
            MOCK_CREATE2_FACTORY, MOCK_CREATE2_SALT, type(MockDeployable).creationCode, chainId, abi.encode(chainId)
        );
    }

    /// A per-network suite on exactly `networks`.
    function mockSuite(string memory key, MockNetworkDeploy[] memory networks) internal view returns (DeploySuite memory) {
        DeploySuite memory suite = mockSingleSuite(key);
        suite.storedDeployedAddress = address(0);
        suite.networks = LibMockCreate2Mechanism.networkNames(networks);
        suite.mechanismData = LibMockCreate2Mechanism.encode(
            MockCreate2Mechanism({
                factory: MOCK_CREATE2_FACTORY,
                salt: MOCK_CREATE2_SALT,
                perNetwork: true,
                networks: networks,
                root: sMockRecordRoot
            })
        );
        return suite;
    }

    /// A single-address suite on the declaration's networks.
    function mockSingleSuite(string memory key) internal view returns (DeploySuite memory) {
        return DeploySuite({
            networks: new string[](0),
            suite: key,
            creationCode: type(MockDeployable).creationCode,
            storedDeployedAddress: LibMockCreate2Mechanism.create2Address(
                MOCK_CREATE2_FACTORY, MOCK_CREATE2_SALT, type(MockDeployable).creationCode
            ),
            storedBytecodeHash: keccak256(type(MockDeployable).runtimeCode),
            storedRuntimeCode: type(MockDeployable).runtimeCode,
            artifactPath: "test/concrete/MockDeployable.sol:MockDeployable",
            dependencies: new DeployDependency[](0),
            mechanismData: LibMockCreate2Mechanism.encode(
                MockCreate2Mechanism({
                    factory: MOCK_CREATE2_FACTORY,
                    salt: MOCK_CREATE2_SALT,
                    perNetwork: false,
                    networks: new MockNetworkDeploy[](0),
                    root: sMockRecordRoot
                })
            )
        });
    }

    /// The per-network release, recording Arbitrum One and Polygon.
    function mockRelease() internal view returns (DeploySuite memory) {
        MockNetworkDeploy[] memory networks = new MockNetworkDeploy[](2);
        networks[0] = mockNetwork(42161);
        networks[1] = mockNetwork(137);
        return mockSuite("mock-create-two@0_0_1", networks);
    }

    /// The release's candidate, on Arbitrum One, Polygon and Base.
    function mockCandidate() internal view returns (DeploySuite memory) {
        MockNetworkDeploy[] memory networks = new MockNetworkDeploy[](3);
        networks[0] = mockNetwork(42161);
        networks[1] = mockNetwork(137);
        networks[2] = mockNetwork(8453);
        return mockSuite("mock-create-two", networks);
    }

    /// Adds `mockRelease()` and `mockCandidate()` to `d`.
    /// @param d The declaration, mutated.
    function addMockCreate2(DeployDeclaration memory d) internal view {
        DeploySuite[] memory released = new DeploySuite[](1);
        released[0] = mockRelease();
        LibRainDeployDeclaration.addReleased(d, released);
        DeployCandidate[] memory candidates = new DeployCandidate[](1);
        candidates[0] = DeployCandidate({snapshot: mockCandidate(), unanchorableReason: ""});
        LibRainDeployDeclaration.addCandidates(d, candidates);
    }

    function externalMockRelease() external view returns (DeploySuite memory) {
        return mockRelease();
    }

    function externalMockCandidate() external view returns (DeploySuite memory) {
        return mockCandidate();
    }
}
