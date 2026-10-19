// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DeploySuite, RainDeploySuitesBase} from "../../src/abstract/RainDeploySuitesBase.sol";
import {ChainBeacon, DeployBeacon} from "../../src/lib/LibRainDeployBeacon.sol";
import {LibBeaconDeclarations} from "../lib/LibBeaconDeclarations.sol";
import {ExampleDeploy} from "./ExampleDeploy.sol";

/// @title BeaconOwnerDeploy
/// @notice `ExampleDeploy` with the beacons a test declares, and `broadcastSuite` exposed.
contract BeaconOwnerDeploy is ExampleDeploy {
    using LibBeaconDeclarations for ChainBeacon[];

    /// The declarations `beacons()` returns.
    ChainBeacon[] internal sBeacons;

    /// @inheritdoc RainDeploySuitesBase
    function beacons() internal view override returns (ChainBeacon[] memory) {
        return sBeacons;
    }

    /// @param chainId The beacon's network.
    /// @param beacon The beacon.
    function declareBeacon(uint256 chainId, DeployBeacon memory beacon) external {
        sBeacons.declare(chainId, beacon);
    }

    /// @param suite The suite to broadcast.
    /// @param networks The networks to broadcast to.
    /// @param deployerPrivateKey The key to broadcast as.
    function externalBroadcastSuite(DeploySuite memory suite, string[] memory networks, uint256 deployerPrivateKey)
        external
    {
        broadcastSuite(suite, networks, deployerPrivateKey);
    }

    /// @param suite The suite to check.
    /// @param deployer The deploy key's address.
    function externalCheckSeatsNoDeployKey(DeploySuite memory suite, address deployer) external {
        checkSeatsNoDeployKey(suite, deployer);
    }
}
