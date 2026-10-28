// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {RainDeployBroadcast} from "../../src/abstract/RainDeployBroadcast.sol";
import {ExampleDeploySuites} from "../abstract/ExampleDeploySuites.sol";
import {ExternalDeploySuites} from "../abstract/ExternalDeploySuites.sol";
import {DeploySuite} from "../../src/abstract/RainDeploySuitesBase.sol";
import {Vm} from "forge-std-1.17.0/src/Vm.sol";

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

    /// @param forkVm The Vm to fork and broadcast with.
    /// @param networks The networks to broadcast to.
    /// @param deployerPrivateKey The key to broadcast as.
    /// @param frozen The release with its extended networks.
    /// @param candidate The release's candidate.
    /// @return Where the suite is on each network.
    /// @return The fork each network was deployed on.
    function externalDeployAndBroadcast(
        Vm forkVm,
        string[] memory networks,
        uint256 deployerPrivateKey,
        DeploySuite memory frozen,
        DeploySuite memory candidate
    ) external returns (address[] memory, uint256[] memory) {
        return deployAndBroadcast(forkVm, networks, deployerPrivateKey, frozen, candidate);
    }
}
