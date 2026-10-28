// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {RainDeployBroadcast} from "../../src/abstract/RainDeployBroadcast.sol";
import {ExampleDeploySuites} from "./ExampleDeploySuites.sol";
import {ExternalDeploySuites} from "./ExternalDeploySuites.sol";
import {DeploySuite} from "../../src/abstract/RainDeploySuitesBase.sol";
import {MockOriginOwned} from "../concrete/MockOriginOwned.sol";
import {Vm} from "forge-std-1.17.0/src/Vm.sol";

/// @title ExampleDeployScript
/// A deploy repo's whole script — a suite declaration plus `RainDeployBroadcast`
/// and nothing else, which is exactly what `script/Deploy.sol` is. The external
/// wrappers let a plain `Test` contract drive the internals without inheriting
/// `Script`.
abstract contract ExampleDeployScript is ExampleDeploySuites, ExternalDeploySuites, RainDeployBroadcast {
    /// @return The networks a broadcast would go to.
    function externalDeployNetworks() external view returns (string[] memory) {
        return deployNetworks(declaration());
    }

    /// @param suite The suite to broadcast.
    /// @param networks The networks to broadcast to.
    /// @param deployerPrivateKey The key to broadcast as.
    /// @return Where the suite is on each network.
    /// @return The fork each network was deployed on.
    function externalBroadcastSuite(DeploySuite memory suite, string[] memory networks, uint256 deployerPrivateKey)
        external
        returns (address[] memory, uint256[] memory)
    {
        return broadcastSuite(declaration(), suite, networks, deployerPrivateKey);
    }

    /// @param suite The suite to check.
    /// @param chainIds The chain ids to deploy under.
    /// @param deployer The deploy key's address.
    function externalCheckSeatsNoDeployKey(DeploySuite memory suite, uint256[] memory chainIds, address deployer)
        external
    {
        checkSeatsNoDeployKey(declaration(), suite, chainIds, deployer);
    }

    /// @param suite The suite to check.
    /// @param chainIds The chain ids to deploy under.
    /// @param deployer The deploy key's address.
    /// @return The origin of a contract this deploy creates once the check returns.
    function externalCheckSeatsNoDeployKeyThenOrigin(
        DeploySuite memory suite,
        uint256[] memory chainIds,
        address deployer
    ) external returns (address) {
        checkSeatsNoDeployKey(declaration(), suite, chainIds, deployer);
        return new MockOriginOwned().owner();
    }

    /// @param forkVm The Vm to fork and broadcast with.
    /// @param networks The networks to broadcast to.
    /// @param deployerPrivateKey The key to broadcast as.
    /// @param frozen The release with its recorded networks.
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
        return deployAndBroadcast(declaration(), forkVm, networks, deployerPrivateKey, frozen, candidate);
    }
}
