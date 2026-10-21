// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DeployDependency, DeployMechanism, DeploySuite} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {DerivedDeploy} from "../../../src/abstract/RainDeployVerifyBase.sol";
import {ChainBeacon} from "../../../src/lib/LibRainDeployBeacon.sol";
import {
    CLONE_ARTIFACT_PATH,
    CloneNetwork,
    CloneNetworks,
    LibRainDeployClone
} from "../../../src/lib/LibRainDeployClone.sol";
import {LibRainDeploy, SupportedNetwork} from "../../../src/lib/LibRainDeploy.sol";
import {LibRainDeployMechanism} from "../../../src/lib/LibRainDeployMechanism.sol";
import {MockCloneFactory} from "../../concrete/MockCloneFactory.sol";
import {MockChainGatedCloneable, MockChainGatedCloneableWrongChain} from "../../concrete/MockChainGatedCloneable.sol";
import {MockCloneable} from "../../concrete/MockCloneable.sol";
import {LibBeaconDeclarations} from "../../lib/LibBeaconDeclarations.sol";
import {BeaconVerifyFixture} from "../../abstract/BeaconVerifyFixture.sol";

/// @title RainDeployVerifyBaseBeaconPerNetworkCloneChainGatedTest
/// @notice A per-network clone beacon suite whose clones initialize only under their own network's chain id derives
/// and resolves on each network.
contract RainDeployVerifyBaseBeaconPerNetworkCloneChainGatedTest is BeaconVerifyFixture {
    using LibBeaconDeclarations for ChainBeacon[];

    /// @return The chain-gated per-network clone suite.
    function chainGatedSuite() internal pure returns (DeploySuite memory) {
        return chainGatedSuite(8453);
    }

    /// @param baseNamed The chain id Base's clone's init data names.
    /// @return The chain-gated per-network clone suite.
    function chainGatedSuite(uint256 baseNamed) internal pure returns (DeploySuite memory) {
        address factory = LibRainDeploy.zoltuAddress(type(MockCloneFactory).creationCode);
        address implementation = LibRainDeploy.zoltuAddress(type(MockChainGatedCloneable).creationCode);
        DeployDependency[] memory dependencies = new DeployDependency[](2);
        dependencies[0] = DeployDependency({deployedAddress: factory, runtimeCode: type(MockCloneFactory).runtimeCode});
        dependencies[1] =
            DeployDependency({deployedAddress: implementation, runtimeCode: type(MockChainGatedCloneable).runtimeCode});
        CloneNetworks memory clones = CloneNetworks({
            factory: factory, implementation: implementation, salt: bytes32(uint256(7)), networks: new CloneNetwork[](2)
        });
        // Each network's clone initializes only under its own chain id.
        clones.networks[0] =
            CloneNetwork({chainId: 42161, data: abi.encode(uint256(42161)), deployedAddress: address(0)});
        clones.networks[1] = CloneNetwork({chainId: 8453, data: abi.encode(baseNamed), deployedAddress: address(0)});
        bytes memory runtimeCode = LibRainDeployClone.cloneRuntimeCode(implementation);
        return DeploySuite({
            suite: "chain-gated-clone-beacon@0_0_1",
            creationCode: LibRainDeployClone.cloneCreationCode(implementation),
            storedDeployedAddress: address(0),
            storedBytecodeHash: keccak256(runtimeCode),
            storedRuntimeCode: runtimeCode,
            artifactPath: CLONE_ARTIFACT_PATH,
            dependencies: dependencies,
            mechanism: DeployMechanism.ClonePerNetwork,
            mechanismData: abi.encode(clones)
        });
    }

    /// @inheritdoc BeaconVerifyFixture
    function releasedSuites() internal pure override returns (DeploySuite[] memory) {
        DeploySuite[] memory fixture = super.releasedSuites();
        DeploySuite[] memory released = new DeploySuite[](fixture.length + 1);
        for (uint256 i = 0; i < fixture.length; i++) {
            released[i] = fixture[i];
        }
        released[fixture.length] = chainGatedSuite();
        return released;
    }

    /// External wrapper for `resolveBeacons`, counting what it resolves.
    /// @param networks The networks whose beacons to resolve.
    /// @return How many beacons resolved.
    function externalResolvedCount(SupportedNetwork[] memory networks) external returns (uint256) {
        return resolveBeacons(networks).length;
    }

    function testChainGatedPerNetworkCloneBeaconSuiteResolvesOnArbitrum() external {
        sBeacons.declare(42161, bySuite("chain-gated-clone-beacon@0_0_1", address(0)));
        assertEq(this.externalResolvedCount(arbitrum()), 1);
    }

    function testChainGatedPerNetworkCloneBeaconSuiteResolvesOnBase() external {
        sBeacons.declare(8453, bySuite("chain-gated-clone-beacon@0_0_1", address(0)));
        assertEq(this.externalResolvedCount(networksNamed(LibRainDeploy.BASE, "")), 1);
    }

    /// Derivation returns every network's address in the suite's address order, the clone code hash, and leaves
    /// neither the chain id nor any clone behind.
    function testChainGatedPerNetworkCloneSuiteDerivesEveryNetwork() external {
        DeploySuite memory suite = chainGatedSuite();
        uint256 chainId = block.chainid;
        DerivedDeploy memory derived = deriveDeployment(suite);
        assertEq(derived.suite, suite.suite);
        address[] memory expected = LibRainDeployMechanism.deployedAddresses(suite);
        assertEq(derived.deployedAddresses, expected);
        assertEq(expected.length, 2);
        assertNotEq(expected[0], expected[1]);
        assertEq(derived.bytecodeHash, keccak256(suite.storedRuntimeCode));
        assertEq(block.chainid, chainId);
        assertEq(expected[0].code.length, 0);
        assertEq(expected[1].code.length, 0);
    }

    /// External wrapper for `deriveDeployment`.
    /// @param suite The suite to derive.
    /// @return The derivation.
    function externalDeriveDeployment(DeploySuite memory suite) external returns (DerivedDeploy memory) {
        return deriveDeployment(suite);
    }

    /// A later network's init that refuses under that network's own chain id refuses derivation.
    function testPerNetworkCloneSuiteRefusedByALaterNetworksInitIsRefused() external {
        vm.expectRevert(abi.encodeWithSelector(MockChainGatedCloneableWrongChain.selector, 42161, 8453));
        this.externalDeriveDeployment(chainGatedSuite(42161));
    }

    /// Networks sharing init data share an address, and each network's derivation deploys it afresh rather than
    /// colliding with another network's.
    function testPerNetworkCloneSuiteSharingAnAddressDerivesEveryNetwork() external {
        address factory = LibRainDeploy.zoltuAddress(type(MockCloneFactory).creationCode);
        address implementation = LibRainDeploy.zoltuAddress(type(MockCloneable).creationCode);
        DeployDependency[] memory dependencies = new DeployDependency[](2);
        dependencies[0] = DeployDependency({deployedAddress: factory, runtimeCode: type(MockCloneFactory).runtimeCode});
        dependencies[1] =
            DeployDependency({deployedAddress: implementation, runtimeCode: type(MockCloneable).runtimeCode});
        CloneNetworks memory clones = CloneNetworks({
            factory: factory, implementation: implementation, salt: bytes32(uint256(7)), networks: new CloneNetwork[](2)
        });
        clones.networks[0] = CloneNetwork({chainId: 42161, data: hex"01", deployedAddress: address(0)});
        clones.networks[1] = CloneNetwork({chainId: 8453, data: hex"01", deployedAddress: address(0)});
        bytes memory runtimeCode = LibRainDeployClone.cloneRuntimeCode(implementation);
        DeploySuite memory suite = DeploySuite({
            suite: "shared-clone@0_0_1",
            creationCode: LibRainDeployClone.cloneCreationCode(implementation),
            storedDeployedAddress: address(0),
            storedBytecodeHash: keccak256(runtimeCode),
            storedRuntimeCode: runtimeCode,
            artifactPath: CLONE_ARTIFACT_PATH,
            dependencies: dependencies,
            mechanism: DeployMechanism.ClonePerNetwork,
            mechanismData: abi.encode(clones)
        });
        DerivedDeploy memory derived = deriveDeployment(suite);
        assertEq(derived.deployedAddresses.length, 2);
        assertEq(derived.deployedAddresses[0], derived.deployedAddresses[1]);
        assertEq(derived.deployedAddresses, LibRainDeployMechanism.deployedAddresses(suite));
        assertEq(derived.bytecodeHash, keccak256(runtimeCode));
    }
}
