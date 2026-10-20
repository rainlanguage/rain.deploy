// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DeploySuite} from "../../src/abstract/RainDeploySuitesBase.sol";
import {BeaconProxyDeploy} from "../../src/lib/LibRainDeployBeaconProxy.sol";
import {exampleBeaconProxy} from "../abstract/ExampleBeaconProxyDeploys.sol";
import {ExternalCloneDeploySuites} from "../abstract/ExternalCloneDeploySuites.sol";
import {ExternalDeploySuites} from "../abstract/ExternalDeploySuites.sol";

/// @title BeaconProxyOnlyDeploySuites
/// @notice No clones and one beacon proxy.
contract BeaconProxyOnlyDeploySuites is ExternalCloneDeploySuites, ExternalDeploySuites {
    /// No release.
    /// @return No suites.
    function releasedSuites() internal pure override returns (DeploySuite[] memory) {
        return new DeploySuite[](0);
    }

    /// The example beacon proxy alone.
    /// @return The beacon proxies.
    function beaconProxyDeploys() internal pure override returns (BeaconProxyDeploy[] memory) {
        BeaconProxyDeploy[] memory proxies = new BeaconProxyDeploy[](1);
        proxies[0] = exampleBeaconProxy(bytes32(uint256(7)));
        return proxies;
    }
}
