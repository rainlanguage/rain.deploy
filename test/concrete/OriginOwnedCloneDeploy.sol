// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {RainDeployBroadcast} from "../../src/abstract/RainDeployBroadcast.sol";
import {RainDeployCloneSuitesBase} from "../../src/abstract/RainDeployCloneSuitesBase.sol";
import {DeploySuite, RainDeploySuitesBase} from "../../src/abstract/RainDeploySuitesBase.sol";
import {CloneDeploy} from "../../src/lib/LibRainDeployClone.sol";
import {DeployDependency, LibRainDeploy} from "../../src/lib/LibRainDeploy.sol";
import {MockCloneFactory} from "./MockCloneFactory.sol";
import {MockOriginOwnedCloneable} from "./MockOriginOwnedCloneable.sol";

/// The init data of the `origin-owned-clone` candidate: Base's clone seats its initialization's origin, every
/// other network's seats `0xB0B`.
/// @param chainId The network's chain id.
/// @return The init data on that network.
function originOwnedCloneInitData(uint256 chainId) pure returns (bytes memory) {
    return abi.encode(chainId == 8453 ? address(0) : address(0xB0B));
}

/// @title OriginOwnedCloneDeploy
/// @notice A per-network clone repo on Arbitrum One and Base whose candidate's Base clone seats the deploy key,
/// with `broadcastSuite` exposed.
contract OriginOwnedCloneDeploy is RainDeployCloneSuitesBase, RainDeployBroadcast {
    /// @inheritdoc RainDeploySuitesBase
    function supportedNetworks() internal pure override returns (string[] memory) {
        string[] memory networks = new string[](2);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;
        networks[1] = LibRainDeploy.BASE;
        return networks;
    }

    /// @inheritdoc RainDeploySuitesBase
    function releasedSuites() internal pure override returns (DeploySuite[] memory) {
        return new DeploySuite[](0);
    }

    /// @inheritdoc RainDeployCloneSuitesBase
    function cloneDeploys() internal pure override returns (CloneDeploy[] memory) {
        address factory = LibRainDeploy.zoltuAddress(type(MockCloneFactory).creationCode);
        address implementation = LibRainDeploy.zoltuAddress(type(MockOriginOwnedCloneable).creationCode);
        DeployDependency[] memory dependencies = new DeployDependency[](2);
        dependencies[0] = DeployDependency({deployedAddress: factory, runtimeCode: type(MockCloneFactory).runtimeCode});
        dependencies[1] = DeployDependency({
            deployedAddress: implementation, runtimeCode: type(MockOriginOwnedCloneable).runtimeCode
        });
        CloneDeploy[] memory clones = new CloneDeploy[](1);
        clones[0] = CloneDeploy({
            suite: "origin-owned-clone",
            factory: factory,
            implementation: implementation,
            data: "",
            initDataPerNetwork: true,
            initData: originOwnedCloneInitData,
            salt: bytes32(uint256(7)),
            dependencies: dependencies
        });
        return clones;
    }

    /// @param suite The suite to broadcast.
    /// @param networks The networks to broadcast to.
    /// @param deployerPrivateKey The key to broadcast as.
    function externalBroadcastSuite(DeploySuite memory suite, string[] memory networks, uint256 deployerPrivateKey)
        external
    {
        broadcastSuite(suite, networks, deployerPrivateKey);
    }
}
