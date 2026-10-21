// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DeployDependency, DeployMechanism, DeploySuite} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {ChainBeacon} from "../../../src/lib/LibRainDeployBeacon.sol";
import {
    CLONE_ARTIFACT_PATH,
    CloneNetwork,
    CloneNetworks,
    LibRainDeployClone
} from "../../../src/lib/LibRainDeployClone.sol";
import {LibRainDeploy, SupportedNetwork} from "../../../src/lib/LibRainDeploy.sol";
import {MockCloneFactory} from "../../concrete/MockCloneFactory.sol";
import {MockChainRefusingCloneable} from "../../concrete/MockChainRefusingCloneable.sol";
import {LibBeaconDeclarations} from "../../lib/LibBeaconDeclarations.sol";
import {BeaconVerifyFixture} from "../../abstract/BeaconVerifyFixture.sol";

/// @title RainDeployVerifyBaseBeaconPerNetworkCloneSeatedTest
/// @notice `RainDeployVerifyBase.checkSeatedState` deploys only the beacon network's own clone of a per-network
/// clone beacon suite.
contract RainDeployVerifyBaseBeaconPerNetworkCloneSeatedTest is BeaconVerifyFixture {
    using LibBeaconDeclarations for ChainBeacon[];

    /// @inheritdoc BeaconVerifyFixture
    function releasedSuites() internal pure override returns (DeploySuite[] memory) {
        DeploySuite[] memory fixture = super.releasedSuites();
        DeploySuite[] memory released = new DeploySuite[](fixture.length + 1);
        for (uint256 i = 0; i < fixture.length; i++) {
            released[i] = fixture[i];
        }
        address factory = LibRainDeploy.zoltuAddress(type(MockCloneFactory).creationCode);
        address implementation = LibRainDeploy.zoltuAddress(type(MockChainRefusingCloneable).creationCode);
        DeployDependency[] memory dependencies = new DeployDependency[](2);
        dependencies[0] = DeployDependency({deployedAddress: factory, runtimeCode: type(MockCloneFactory).runtimeCode});
        dependencies[1] = DeployDependency({
            deployedAddress: implementation, runtimeCode: type(MockChainRefusingCloneable).runtimeCode
        });
        CloneNetworks memory clones = CloneNetworks({
            factory: factory, implementation: implementation, salt: bytes32(uint256(7)), networks: new CloneNetwork[](2)
        });
        // Each network's clone refuses the other network's chain id.
        clones.networks[0] =
            CloneNetwork({chainId: 42161, data: abi.encode(uint256(8453)), deployedAddress: address(0)});
        clones.networks[1] =
            CloneNetwork({chainId: 8453, data: abi.encode(uint256(42161)), deployedAddress: address(0)});
        bytes memory runtimeCode = LibRainDeployClone.cloneRuntimeCode(implementation);
        released[fixture.length] = DeploySuite({
            suite: "chain-refusing-clone-beacon@0_0_1",
            creationCode: LibRainDeployClone.cloneCreationCode(implementation),
            storedDeployedAddress: address(0),
            storedBytecodeHash: keccak256(runtimeCode),
            storedRuntimeCode: runtimeCode,
            artifactPath: CLONE_ARTIFACT_PATH,
            dependencies: dependencies,
            mechanism: DeployMechanism.ClonePerNetwork,
            mechanismData: abi.encode(clones),
            describedByMeta: ""
        });
        return released;
    }

    /// External wrapper for `resolveBeacons`, counting what it resolves.
    /// @param networks The networks whose beacons to resolve.
    /// @return How many beacons resolved.
    function externalResolvedCount(SupportedNetwork[] memory networks) external returns (uint256) {
        return resolveBeacons(networks).length;
    }

    function testPerNetworkCloneBeaconSuiteResolvesOnArbitrum() external {
        sBeacons.declare(42161, bySuite("chain-refusing-clone-beacon@0_0_1", address(0)));
        assertEq(this.externalResolvedCount(arbitrum()), 1);
    }

    function testPerNetworkCloneBeaconSuiteResolvesOnBase() external {
        sBeacons.declare(8453, bySuite("chain-refusing-clone-beacon@0_0_1", address(0)));
        assertEq(this.externalResolvedCount(networksNamed(LibRainDeploy.BASE, "")), 1);
    }
}
