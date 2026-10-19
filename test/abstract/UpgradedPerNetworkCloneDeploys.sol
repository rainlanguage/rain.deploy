// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {RainDeployCloneSuitesBase} from "../../src/abstract/RainDeployCloneSuitesBase.sol";
import {RainDeploySuitesBase} from "../../src/abstract/RainDeploySuitesBase.sol";
import {CloneDeploy, CloneTarget, LibRainDeployClone} from "../../src/lib/LibRainDeployClone.sol";
import {DeployDependency, LibRainDeploy} from "../../src/lib/LibRainDeploy.sol";
import {MockCloneFactory} from "../concrete/MockCloneFactory.sol";
import {MockCloneableV2} from "../concrete/MockCloneableV2.sol";
import {exampleCloneImplementation} from "./ExampleCloneDeploys.sol";
import {PerNetworkCloneDeploys, perNetworkCloneInitData} from "./PerNetworkCloneDeploys.sol";

/// The factory the upgraded candidate clones through.
/// @return The factory address.
function upgradedCloneFactory() pure returns (address) {
    return address(uint160(uint256(keccak256("rain.deploy.test.upgraded-clone-factory"))));
}

/// The implementation the upgraded candidate clones.
/// @return The implementation address.
function upgradedCloneImplementation() pure returns (address) {
    return LibRainDeploy.zoltuAddress(type(MockCloneableV2).creationCode);
}

/// The upgraded candidate's dependencies.
/// @return The dependencies.
function upgradedCloneDependencies() pure returns (DeployDependency[] memory) {
    DeployDependency[] memory dependencies = new DeployDependency[](2);
    dependencies[0] =
        DeployDependency({deployedAddress: upgradedCloneFactory(), runtimeCode: type(MockCloneFactory).runtimeCode});
    dependencies[1] = DeployDependency({
        deployedAddress: upgradedCloneImplementation(), runtimeCode: type(MockCloneableV2).runtimeCode
    });
    return dependencies;
}

/// The `per-network-clone` candidate after it moved to the upgraded factory and implementation,
/// with the same per-network init data and its own salt.
/// @return The candidate's clone declaration.
function upgradedPerNetworkClone() pure returns (CloneDeploy memory) {
    return CloneDeploy({
        suite: "per-network-clone",
        factory: upgradedCloneFactory(),
        implementation: upgradedCloneImplementation(),
        data: "",
        initDataPerNetwork: true,
        initData: perNetworkCloneInitData,
        salt: bytes32(uint256(4)),
        dependencies: upgradedCloneDependencies()
    });
}

/// Where the upgraded candidate's factory, implementation and salt put a clone initialized with a
/// network's init data.
/// @param chainId The network's chain id.
/// @return The clone address.
function upgradedPerNetworkCloneAddress(uint256 chainId) pure returns (address) {
    CloneDeploy memory candidate = upgradedPerNetworkClone();
    return LibRainDeployClone.cloneDeployedAddress(
        CloneTarget({
            factory: candidate.factory,
            implementation: candidate.implementation,
            data: perNetworkCloneInitData(chainId),
            salt: candidate.salt
        })
    );
}

/// @title UpgradedPerNetworkCloneDeploys
/// @notice `PerNetworkCloneDeploys` with its candidate moved to another factory and implementation
/// since its `0_0_1` release was cut.
abstract contract UpgradedPerNetworkCloneDeploys is PerNetworkCloneDeploys {
    /// @inheritdoc RainDeployCloneSuitesBase
    function cloneDeploys() internal pure override returns (CloneDeploy[] memory) {
        CloneDeploy[] memory clones = new CloneDeploy[](1);
        clones[0] = upgradedPerNetworkClone();
        return clones;
    }

    /// The release's implementation reads the upgraded candidate's init data, for that candidate alone.
    /// @inheritdoc RainDeploySuitesBase
    function initDataReaders(string memory suite) internal pure virtual override returns (address[] memory) {
        if (keccak256(bytes(suite)) != keccak256("per-network-clone")) {
            return new address[](0);
        }
        address[] memory readers = new address[](1);
        readers[0] = exampleCloneImplementation();
        return readers;
    }
}
