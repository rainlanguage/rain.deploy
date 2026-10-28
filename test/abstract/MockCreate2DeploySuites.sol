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
import {LibRainDeploySnapshot} from "../../src/lib/LibRainDeploySnapshot.sol";
import {LibRainDeployZoltuMechanism} from "../../src/lib/LibRainDeployZoltuMechanism.sol";
import {
    LibMockCreate2Mechanism,
    MOCK_CREATE2_FACTORY,
    MOCK_CREATE2_SALT,
    MockCreate2DerivationMismatch,
    MockCreate2Mechanism,
    MockCreate2NetworkUndeclared,
    MockCreate2NetworkUnfrozen
} from "../lib/LibMockCreate2Mechanism.sol";
import {MockDeployable} from "../concrete/MockDeployable.sol";

/// @title MockCreate2DeploySuites
/// @notice A test-only declaration of `LibMockCreate2Mechanism` suites, resolved before Zoltu. A concrete taking the
/// extended networks seam overrides `extendedNetworks` and `extendedNetworksRoot` with `mockExtendedNetworks` and
/// `mockExtendedNetworksRoot`.
abstract contract MockCreate2DeploySuites is RainDeploySuitesBase {
    ChainDeploy[] internal sMockExtendedNetworks;

    string internal sMockExtendedNetworksRoot;

    function setMockExtendedNetworksRoot(string memory root) external {
        sMockExtendedNetworksRoot = root;
    }

    function mockExtendedNetworksRoot() internal view returns (string memory) {
        if (bytes(sMockExtendedNetworksRoot).length == 0) {
            return LibRainDeploySnapshot.LIB_FS_ROOT;
        }
        return sMockExtendedNetworksRoot;
    }

    function setMockExtendedNetworks(ChainDeploy[] memory networks) external {
        delete sMockExtendedNetworks;
        for (uint256 i = 0; i < networks.length; i++) {
            sMockExtendedNetworks.push(networks[i]);
        }
    }


    function mockNetwork(uint256 chainId) internal pure returns (ChainDeploy memory) {
        bytes memory data = abi.encode(chainId);
        return ChainDeploy({
            chainId: chainId,
            data: data,
            deployedAddress: LibMockCreate2Mechanism.create2Address(
                MOCK_CREATE2_FACTORY, LibMockCreate2Mechanism.networkSalt(MOCK_CREATE2_SALT, data), type(MockDeployable).creationCode
            )
        });
    }

    function mockSuite(string memory key, address beacon, ChainDeploy[] memory networks)
        internal
        pure
        returns (DeploySuite memory)
    {
        return DeploySuite({
            suite: key,
            creationCode: type(MockDeployable).creationCode,
            storedDeployedAddress: networks.length == 0
                ? LibMockCreate2Mechanism.create2Address(MOCK_CREATE2_FACTORY, MOCK_CREATE2_SALT, type(MockDeployable).creationCode)
                : address(0),
            storedBytecodeHash: keccak256(type(MockDeployable).runtimeCode),
            storedRuntimeCode: type(MockDeployable).runtimeCode,
            artifactPath: "test/concrete/MockDeployable.sol:MockDeployable",
            dependencies: new DeployDependency[](0),
            mechanismData: abi.encode(
                MockCreate2Mechanism({
                    factory: MOCK_CREATE2_FACTORY, salt: MOCK_CREATE2_SALT, beacon: beacon, networks: networks
                })
            )
        });
    }

    /// The per-network release, recording Arbitrum One and Polygon.
    function mockRelease() internal pure returns (DeploySuite memory) {
        ChainDeploy[] memory networks = new ChainDeploy[](2);
        networks[0] = mockNetwork(42161);
        networks[1] = mockNetwork(137);
        return mockSuite("mock-create-two@0_0_1", address(0), networks);
    }

    /// The release's candidate, on Arbitrum One, Polygon and Base.
    function mockCandidate() internal pure returns (DeploySuite memory) {
        ChainDeploy[] memory networks = new ChainDeploy[](3);
        networks[0] = mockNetwork(42161);
        networks[1] = mockNetwork(137);
        networks[2] = mockNetwork(8453);
        return mockSuite("mock-create-two", address(0), networks);
    }

    function releasedSuites() internal pure virtual override returns (DeploySuite[] memory) {
        DeploySuite[] memory suites = new DeploySuite[](1);
        suites[0] = mockRelease();
        return suites;
    }

    function candidateSuites() internal view virtual override returns (DeployCandidate[] memory) {
        DeployCandidate[] memory candidates = new DeployCandidate[](1);
        candidates[0] = DeployCandidate({snapshot: mockCandidate(), unanchorableReason: ""});
        return candidates;
    }

    function mockExtendedNetworks() internal view returns (ChainDeploy[] memory) {
        return sMockExtendedNetworks;
    }

    function mechanisms() internal pure virtual override returns (DeployMechanismHandler[] memory) {
        DeployMechanismHandler[] memory handlers = new DeployMechanismHandler[](2);
        handlers[0] = LibMockCreate2Mechanism.handler();
        handlers[1] = LibRainDeployZoltuMechanism.handler();
        return handlers;
    }
}
