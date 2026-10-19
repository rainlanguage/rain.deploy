// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {RainDeployBroadcast} from "../../src/abstract/RainDeployBroadcast.sol";
import {DeploySuite, RainDeploySuitesBase} from "../../src/abstract/RainDeploySuitesBase.sol";
import {CloneNetwork} from "../../src/lib/LibRainDeployClone.sol";
import {PerNetworkCloneDeploys} from "../abstract/PerNetworkCloneDeploys.sol";
import {UpgradedPerNetworkCloneDeploys} from "../abstract/UpgradedPerNetworkCloneDeploys.sol";
import {ExternalCloneDeploySuites} from "../abstract/ExternalCloneDeploySuites.sol";
import {ExternalDeploySuites} from "../abstract/ExternalDeploySuites.sol";

/// @title UpgradedPerNetworkCloneDeploy `UpgradedPerNetworkCloneDeploys` plus
/// `RainDeployBroadcast`, with external wrappers so a plain `Test` contract can drive it.
contract UpgradedPerNetworkCloneDeploy is
    UpgradedPerNetworkCloneDeploys,
    ExternalCloneDeploySuites,
    ExternalDeploySuites,
    RainDeployBroadcast
{
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
    function extendedNetworks(string memory suite) internal view override returns (CloneNetwork[] memory) {
        if (keccak256(bytes(suite)) != keccak256(bytes(sExtendedSuite))) {
            return new CloneNetwork[](0);
        }
        return sExtendedNetworks;
    }

    /// @inheritdoc PerNetworkCloneDeploys
    function supportedNetworks()
        internal
        view
        override(PerNetworkCloneDeploys, RainDeploySuitesBase)
        returns (string[] memory)
    {
        return PerNetworkCloneDeploys.supportedNetworks();
    }

    /// @inheritdoc UpgradedPerNetworkCloneDeploys
    function initDataReaders(string memory suite)
        internal
        pure
        override(UpgradedPerNetworkCloneDeploys, RainDeploySuitesBase)
        returns (address[] memory)
    {
        return UpgradedPerNetworkCloneDeploys.initDataReaders(suite);
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
