// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {RainDeployCloneSuitesBase} from "../../src/abstract/RainDeployCloneSuitesBase.sol";
import {CloneDeploy} from "../../src/lib/LibRainDeployClone.sol";
import {BeaconProxyDeploy} from "../../src/lib/LibRainDeployBeaconProxy.sol";
import {LibBeaconProxyTest} from "../lib/LibBeaconProxyTest.sol";
import {ExampleCloneDeploys} from "../abstract/ExampleCloneDeploys.sol";
import {ExternalCloneDeploySuites} from "../abstract/ExternalCloneDeploySuites.sol";
import {ExternalDeploySuites} from "../abstract/ExternalDeploySuites.sol";

/// @title MixedCloneBeaconProxyDeploySuites
/// @notice The example clones and two beacon proxies.
contract MixedCloneBeaconProxyDeploySuites is ExampleCloneDeploys, ExternalCloneDeploySuites, ExternalDeploySuites {
    /// @inheritdoc RainDeployCloneSuitesBase
    function cloneDeploys()
        internal
        pure
        override(ExampleCloneDeploys, RainDeployCloneSuitesBase)
        returns (CloneDeploy[] memory)
    {
        return ExampleCloneDeploys.cloneDeploys();
    }

    /// The example beacon proxy at two salts, under two suite names.
    /// @return The beacon proxies.
    function beaconProxyDeploys() internal pure override returns (BeaconProxyDeploy[] memory) {
        BeaconProxyDeploy[] memory proxies = new BeaconProxyDeploy[](2);
        proxies[0] = LibBeaconProxyTest.example(bytes32(uint256(7)));
        proxies[1] = LibBeaconProxyTest.example(bytes32(uint256(8)));
        proxies[1].suite = "example-beacon-proxy-second-salt";
        return proxies;
    }
}
