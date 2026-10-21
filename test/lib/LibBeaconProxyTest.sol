// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";
import {LibRainDeployClone} from "../../src/lib/LibRainDeployClone.sol";
import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {BeaconProxyDeploy, LibRainDeployBeaconProxy} from "../../src/lib/LibRainDeployBeaconProxy.sol";
import {DeployDependency, LibRainDeploy} from "../../src/lib/LibRainDeploy.sol";
import {MockBeaconProxyFactory} from "../concrete/MockBeaconProxyFactory.sol";
import {perNetworkCloneInitData} from "../abstract/PerNetworkCloneDeploys.sol";

/// @dev The runtime code of a proxy of `LibBeaconProxyTest.exampleBeacon()`, as a repo's Build script generates
/// it. `LibRainDeployBeaconProxyTest.testExampleBeaconProxyRuntimeCodeIsGenerated` holds it to the generator.
bytes constant EXAMPLE_BEACON_PROXY_RUNTIME_CODE =
    hex"608060405261000c61000e565b005b61001e610019610020565b6100b3565b565b5f7f000000000000000000000000c332dedab1a8b880780b1733a5f40b9793e0df7073ffffffffffffffffffffffffffffffffffffffff16635c60da1b6040518163ffffffff1660e01b8152600401602060405180830381865afa15801561008a573d5f803e3d5ffd5b505050506040513d601f19601f820116820180604052508101906100ae91906100d1565b905090565b365f80375f80365f845af43d5f803e8080156100cd573d5ff35b3d5ffd5b5f602082840312156100e1575f80fd5b815173ffffffffffffffffffffffffffffffffffffffff81168114610104575f80fd5b939250505056";

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
        bytes32 salt,
        bytes memory runtimeCode
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
            dependencies: dependencies,
            runtimeCode: runtimeCode
        });
    }

    /// The generated runtime code of a proxy of the real beacon at `beacon`.
    /// @param vm The Vm instance to generate with.
    /// @param beacon A real, deployed beacon.
    /// @return The proxy's runtime code.
    function runtimeOf(Vm vm, address beacon) internal returns (bytes memory) {
        address implementation = UpgradeableBeacon(beacon).implementation();
        return LibRainDeployBeaconProxy.beaconProxyRuntimeCode(vm, beacon, implementation, implementation.code);
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
            dependencies: dependencies,
            runtimeCode: EXAMPLE_BEACON_PROXY_RUNTIME_CODE
        });
    }
}
