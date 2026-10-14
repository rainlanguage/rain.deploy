// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {RainDeployBroadcast} from "../../src/abstract/RainDeployBroadcast.sol";
import {DeploySuite} from "../../src/abstract/RainDeploySuitesBase.sol";
import {ExampleCloneDeploys} from "../abstract/ExampleCloneDeploys.sol";
import {ExternalCloneDeploySuites} from "../abstract/ExternalCloneDeploySuites.sol";
import {ExternalDeploySuites} from "../abstract/ExternalDeploySuites.sol";

/// @title ExampleCloneDeploy A clone deploy repo's whole script — a clone declaration plus
/// `RainDeployBroadcast` and nothing else, the same script a Zoltu repo writes. That it compiles to
/// a working script with no `run()`, no network list, no fork loop, no override and no assertions
/// of its own is itself the claim being made: the mechanism is carried on each `DeploySuite`, so
/// the broadcast dispatches a clone suite through the clone mechanism with nothing chosen per
/// script. The external wrappers let a plain `Test` contract drive the internals without inheriting
/// `Script`, exactly as `ExampleDeploy` does.
contract ExampleCloneDeploy is
    ExampleCloneDeploys,
    ExternalCloneDeploySuites,
    ExternalDeploySuites,
    RainDeployBroadcast
{
    /// @return The networks a broadcast would go to.
    function externalDeployNetworks() external view returns (string[] memory) {
        return deployNetworks();
    }

    /// External wrapper for `broadcastSuite`, so a plain `Test` contract can drive it and
    /// `vm.expectRevert` lands at the right call depth.
    /// @param suite The suite to broadcast.
    /// @param networks The networks to broadcast to.
    /// @param deployerPrivateKey The key to broadcast as.
    function externalBroadcastSuite(DeploySuite memory suite, string[] memory networks, uint256 deployerPrivateKey)
        external
    {
        broadcastSuite(suite, networks, deployerPrivateKey);
    }
}
