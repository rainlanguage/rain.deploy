// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {RainDeployCloneBroadcast} from "../../src/abstract/RainDeployCloneBroadcast.sol";
import {ExampleCloneDeploys} from "../abstract/ExampleCloneDeploys.sol";
import {ExternalCloneDeploySuites} from "../abstract/ExternalCloneDeploySuites.sol";
import {ExternalDeploySuites} from "../abstract/ExternalDeploySuites.sol";

/// @title ExampleCloneDeploy
/// A clone deploy repo's whole script — a clone declaration plus
/// `RainDeployCloneBroadcast` and nothing else, which is the shape the issue this
/// implements asks for. That it compiles to a working script with no `run()`, no
/// network list, no fork loop and no assertions of its own is itself the claim
/// being made: the clone mechanism is one overridden function and the rest is
/// shared with the Zoltu path.
///
/// The external wrappers let a plain `Test` contract drive the internals without
/// inheriting `Script`, exactly as `ExampleDeploy` does.
contract ExampleCloneDeploy is
    ExampleCloneDeploys,
    ExternalCloneDeploySuites,
    ExternalDeploySuites,
    RainDeployCloneBroadcast
{
    /// @return The networks a broadcast would go to.
    function externalDeployNetworks() external view returns (string[] memory) {
        return deployNetworks();
    }
}
