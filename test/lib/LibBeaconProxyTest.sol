// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";
import {LibRainDeployClone} from "../../src/lib/LibRainDeployClone.sol";
import {BeaconProxyDeploy} from "../../src/lib/LibRainDeployBeaconProxy.sol";
import {DeployDependency, LibRainDeploy} from "../../src/lib/LibRainDeploy.sol";
import {MockBeaconProxyFactory} from "../concrete/MockBeaconProxyFactory.sol";
import {perNetworkCloneInitData} from "../abstract/PerNetworkCloneDeploys.sol";

/// @title LibBeaconProxyTest
/// @notice The beacon proxy declarations the tests share.
library LibBeaconProxyTest {
    /// A beacon proxy over `factory` and `beacon`, both declared as its dependencies with the code they hold now.
    /// @param suite The suite key.
    /// @param factory The factory.
    /// @param beacon The beacon.
    /// @param data The one init data for every network, dropped when the init data is per network.
    /// @param initDataPerNetwork Whether the init data is per network, as `perNetworkCloneInitData`.
    /// @param salt The salt.
    /// @return The declaration.
    function declared(
        string memory suite,
        address factory,
        address beacon,
        bytes memory data,
        bool initDataPerNetwork,
        bytes32 salt
    ) internal view returns (BeaconProxyDeploy memory) {
        DeployDependency[] memory dependencies = new DeployDependency[](2);
        dependencies[0] = DeployDependency({deployedAddress: factory, runtimeCode: factory.code});
        dependencies[1] = DeployDependency({deployedAddress: beacon, runtimeCode: beacon.code});
        return BeaconProxyDeploy({
            suite: suite,
            factory: factory,
            beacon: beacon,
            data: initDataPerNetwork ? bytes("") : data,
            initDataPerNetwork: initDataPerNetwork,
            initData: initDataPerNetwork ? perNetworkCloneInitData : LibRainDeployClone.noInitDataPerNetwork,
            salt: salt,
            dependencies: dependencies
        });
    }

    /// @return The example beacon proxy's factory.
    function exampleFactory() internal pure returns (address) {
        return LibRainDeploy.zoltuAddress(type(MockBeaconProxyFactory).creationCode);
    }

    /// @return The example beacon proxy's beacon: an address of its own, nothing deployed at it.
    function exampleBeacon() internal pure returns (address) {
        return address(uint160(uint256(keccak256("rain.deploy.test.example-beacon"))));
    }

    /// The example beacon proxy, over its factory and beacon.
    /// @param salt The salt.
    /// @return The declaration.
    function example(bytes32 salt) internal pure returns (BeaconProxyDeploy memory) {
        DeployDependency[] memory dependencies = new DeployDependency[](2);
        dependencies[0] = DeployDependency({
            deployedAddress: exampleFactory(), runtimeCode: type(MockBeaconProxyFactory).runtimeCode
        });
        dependencies[1] =
            DeployDependency({deployedAddress: exampleBeacon(), runtimeCode: type(UpgradeableBeacon).runtimeCode});
        return BeaconProxyDeploy({
            suite: "example-beacon-proxy",
            factory: exampleFactory(),
            beacon: exampleBeacon(),
            data: hex"beef",
            initDataPerNetwork: false,
            initData: LibRainDeployClone.noInitDataPerNetwork,
            salt: salt,
            dependencies: dependencies
        });
    }
}
