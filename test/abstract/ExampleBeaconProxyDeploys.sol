// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";
import {LibRainDeployClone} from "../../src/lib/LibRainDeployClone.sol";
import {BeaconProxyDeploy} from "../../src/lib/LibRainDeployBeaconProxy.sol";
import {DeployDependency, LibRainDeploy} from "../../src/lib/LibRainDeploy.sol";
import {MockBeaconProxyFactory} from "../concrete/MockBeaconProxyFactory.sol";

/// @return The example beacon proxy's factory.
function exampleBeaconProxyFactory() pure returns (address) {
    return LibRainDeploy.zoltuAddress(type(MockBeaconProxyFactory).creationCode);
}

/// @return The example beacon proxy's beacon: an address of its own, nothing deployed at it.
function exampleBeaconProxyBeacon() pure returns (address) {
    return address(uint160(uint256(keccak256("rain.deploy.test.example-beacon"))));
}

/// The example beacon proxy, over its factory and beacon.
/// @param salt The salt.
/// @return The declaration.
function exampleBeaconProxy(bytes32 salt) pure returns (BeaconProxyDeploy memory) {
    DeployDependency[] memory dependencies = new DeployDependency[](2);
    dependencies[0] = DeployDependency({
        deployedAddress: exampleBeaconProxyFactory(), runtimeCode: type(MockBeaconProxyFactory).runtimeCode
    });
    dependencies[1] = DeployDependency({
        deployedAddress: exampleBeaconProxyBeacon(), runtimeCode: type(UpgradeableBeacon).runtimeCode
    });
    return BeaconProxyDeploy({
        suite: "example-beacon-proxy",
        factory: exampleBeaconProxyFactory(),
        beacon: exampleBeaconProxyBeacon(),
        data: hex"beef",
        initDataPerNetwork: false,
        initData: LibRainDeployClone.noInitDataPerNetwork,
        salt: salt,
        dependencies: dependencies
    });
}
