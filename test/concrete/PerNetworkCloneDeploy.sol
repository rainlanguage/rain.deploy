// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {RainDeployBroadcast} from "../../src/abstract/RainDeployBroadcast.sol";
import {DeploySuite} from "../../src/abstract/RainDeploySuitesBase.sol";
import {PerNetworkCloneDeploys} from "../abstract/PerNetworkCloneDeploys.sol";
import {ExternalDeploySuites} from "../abstract/ExternalDeploySuites.sol";

/// @title PerNetworkCloneDeploy
/// A per-network clone deploy repo's whole script: the declaration plus
/// `RainDeployBroadcast`, with external wrappers so a plain `Test` contract
/// can drive it.
contract PerNetworkCloneDeploy is PerNetworkCloneDeploys, ExternalDeploySuites, RainDeployBroadcast {
    /// External wrapper for `broadcastSuite`.
    /// @param suite The suite to broadcast.
    /// @param networks The networks to broadcast to.
    /// @param deployerPrivateKey The key to broadcast as.
    /// @return deployedAddresses Where the suite is on each network.
    /// @return forkIds The fork each network was deployed on.
    function externalBroadcastSuite(DeploySuite memory suite, string[] memory networks, uint256 deployerPrivateKey)
        external
        returns (address[] memory deployedAddresses, uint256[] memory forkIds)
    {
        return broadcastSuite(suite, networks, deployerPrivateKey);
    }
}
