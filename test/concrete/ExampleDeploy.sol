// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {RainDeployBroadcast} from "../../src/abstract/RainDeployBroadcast.sol";
import {ExampleDeploySuites} from "../abstract/ExampleDeploySuites.sol";
import {ExternalDeploySuites} from "../abstract/ExternalDeploySuites.sol";

/// @title ExampleDeploy
/// A deploy repo's whole script — a suite declaration plus `RainDeployBroadcast`
/// and nothing else, which is exactly what `script/Deploy.sol` is. The external
/// wrappers let a plain `Test` contract drive the internals without inheriting
/// `Script`.
contract ExampleDeploy is ExampleDeploySuites, ExternalDeploySuites, RainDeployBroadcast {
    /// @return The networks a broadcast would go to.
    function externalDeployNetworks() external view returns (string[] memory) {
        return deployNetworks();
    }
}
