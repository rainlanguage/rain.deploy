// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {CloneDeploy} from "../lib/LibRainDeployClone.sol";
import {BeaconProxyDeploy} from "../lib/LibRainDeployBeaconProxy.sol";
import {LibRainDeploy, SupportedNetwork} from "../lib/LibRainDeploy.sol";
import {LibRainDeployMechanism} from "../lib/LibRainDeployMechanism.sol";
import {DeployCandidate, RainDeploySuitesBase} from "./RainDeploySuitesBase.sol";

/// Thrown when a declaration names no clone and no beacon proxy at all.
error NoFactoryDeploys();

/// @title RainDeployCloneSuitesBase
/// @notice The declaration for a repo whose candidates are factory deployments: EIP-1167 clones,
/// beacon proxies, or both.
abstract contract RainDeployCloneSuitesBase is RainDeploySuitesBase {
    /// Every clone candidate this repo deploys. None by default.
    /// @return The clones.
    function cloneDeploys() internal pure virtual returns (CloneDeploy[] memory) {
        return new CloneDeploy[](0);
    }

    /// Every beacon proxy candidate this repo deploys. None by default.
    /// @return The beacon proxies.
    function beaconProxyDeploys() internal pure virtual returns (BeaconProxyDeploy[] memory) {
        return new BeaconProxyDeploy[](0);
    }

    /// The chain id of every network in `supportedNetworks()`, in that order, from the network
    /// catalogue.
    /// @return The chain ids.
    function supportedChainIds() internal view returns (uint256[] memory) {
        SupportedNetwork[] memory configs = LibRainDeploy.declaredNetworkConfigs(supportedNetworks());
        uint256[] memory chainIds = new uint256[](configs.length);
        for (uint256 i = 0; i < configs.length; i++) {
            chainIds[i] = configs[i].chainId;
        }
        return chainIds;
    }

    /// Every candidate this repo deploys.
    /// @return The clones, then the beacon proxies, refusing `NoFactoryDeploys` when there are neither.
    function candidateSuites() internal view override returns (DeployCandidate[] memory) {
        CloneDeploy[] memory clones = cloneDeploys();
        BeaconProxyDeploy[] memory proxies = beaconProxyDeploys();
        if (clones.length == 0 && proxies.length == 0) {
            revert NoFactoryDeploys();
        }
        uint256[] memory chainIds = supportedChainIds();
        DeployCandidate[] memory candidates = new DeployCandidate[](clones.length + proxies.length);
        for (uint256 i = 0; i < clones.length; i++) {
            candidates[i] = LibRainDeployMechanism.cloneCandidate(clones[i], chainIds);
        }
        for (uint256 i = 0; i < proxies.length; i++) {
            candidates[clones.length + i] = LibRainDeployMechanism.beaconProxyCandidate(proxies[i], chainIds);
        }
        return candidates;
    }
}
