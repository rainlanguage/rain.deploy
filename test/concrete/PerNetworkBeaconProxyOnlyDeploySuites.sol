// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DeploySuite} from "../../src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeploy} from "../../src/lib/LibRainDeploy.sol";
import {BeaconProxyDeploy} from "../../src/lib/LibRainDeployBeaconProxy.sol";
import {LibBeaconProxyTest} from "../lib/LibBeaconProxyTest.sol";
import {perNetworkCloneInitData} from "../abstract/PerNetworkCloneDeploys.sol";
import {ExternalCloneDeploySuites} from "../abstract/ExternalCloneDeploySuites.sol";
import {ExternalDeploySuites} from "../abstract/ExternalDeploySuites.sol";

/// @title PerNetworkBeaconProxyOnlyDeploySuites
/// @notice No clones and one beacon proxy whose init data is `perNetworkCloneInitData`, on Arbitrum One then
/// Polygon.
contract PerNetworkBeaconProxyOnlyDeploySuites is ExternalCloneDeploySuites, ExternalDeploySuites {
    /// No release.
    /// @return No suites.
    function releasedSuites() internal pure override returns (DeploySuite[] memory) {
        return new DeploySuite[](0);
    }

    /// Arbitrum One, then Polygon.
    /// @return The networks.
    function supportedNetworks() internal pure override returns (string[] memory) {
        string[] memory networks = new string[](2);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;
        networks[1] = LibRainDeploy.POLYGON;
        return networks;
    }

    /// The example beacon proxy with its init data per network.
    /// @return The beacon proxies.
    function beaconProxyDeploys() internal pure override returns (BeaconProxyDeploy[] memory) {
        BeaconProxyDeploy[] memory proxies = new BeaconProxyDeploy[](1);
        proxies[0] = LibBeaconProxyTest.example(bytes32(uint256(7)));
        proxies[0].data = "";
        proxies[0].initDataPerNetwork = true;
        proxies[0].initData = perNetworkCloneInitData;
        return proxies;
    }
}
