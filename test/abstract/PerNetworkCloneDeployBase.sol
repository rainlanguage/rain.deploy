// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {RainDeployBroadcast} from "../../src/abstract/RainDeployBroadcast.sol";
import {DeploySuite} from "../../src/abstract/RainDeploySuitesBase.sol";
import {CloneNetwork} from "../../src/lib/LibRainDeployClone.sol";
import {ExternalCloneDeploySuites} from "./ExternalCloneDeploySuites.sol";
import {ExternalDeploySuites} from "./ExternalDeploySuites.sol";

/// @title PerNetworkCloneDeployBase `RainDeployBroadcast` with settable extended networks and external wrappers,
/// so a plain `Test` contract can drive a per-network clone declaration under it.
abstract contract PerNetworkCloneDeployBase is ExternalCloneDeploySuites, ExternalDeploySuites, RainDeployBroadcast {
    /// The suite `sExtendedNetworks` is declared for.
    string internal sExtendedSuite;

    /// The networks `extendedNetworks` declares for `sExtendedSuite`. Empty by default.
    CloneNetwork[] internal sExtendedNetworks;

    /// Sets what `extendedNetworks` declares.
    /// @param suite The release's suite key.
    /// @param networks The networks it declares for that release.
    function setExtendedNetworks(string memory suite, CloneNetwork[] memory networks) external {
        sExtendedSuite = suite;
        delete sExtendedNetworks;
        for (uint256 i = 0; i < networks.length; i++) {
            sExtendedNetworks.push(networks[i]);
        }
    }

    /// `sExtendedNetworks` for `sExtendedSuite`, else none.
    /// @param suite The release's suite key.
    /// @return The networks.
    function extendedNetworks(string memory suite) internal view virtual override returns (CloneNetwork[] memory) {
        if (keccak256(bytes(suite)) != keccak256(bytes(sExtendedSuite))) {
            return new CloneNetwork[](0);
        }
        return sExtendedNetworks;
    }

    /// External wrapper for `broadcastSuite`.
    /// @param suite The suite to broadcast.
    /// @param networks The networks to broadcast to.
    /// @param deployerPrivateKey The key to broadcast as.
    /// @return Where the suite is on each network.
    /// @return The fork each network was deployed on.
    function externalBroadcastSuite(DeploySuite memory suite, string[] memory networks, uint256 deployerPrivateKey)
        external
        returns (address[] memory, uint256[] memory)
    {
        return broadcastSuite(suite, networks, deployerPrivateKey);
    }
}
