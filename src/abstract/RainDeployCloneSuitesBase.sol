// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {CloneDeploy} from "../lib/LibRainDeployClone.sol";
import {LibRainDeploy, SupportedNetwork} from "../lib/LibRainDeploy.sol";
import {LibRainDeployMechanism} from "../lib/LibRainDeployMechanism.sol";
import {DeployCandidate, RainDeploySuitesBase} from "./RainDeploySuitesBase.sol";

/// Thrown when a declaration names no clone at all.
error NoCloneDeploys();

/// @title RainDeployCloneSuitesBase
/// @notice The declaration for a repo whose candidates are EIP-1167 factory clones.
abstract contract RainDeployCloneSuitesBase is RainDeploySuitesBase {
    /// Every clone candidate this repo deploys.
    /// @return The clones.
    function cloneDeploys() internal pure virtual returns (CloneDeploy[] memory);

    /// The declared clones, refusing an empty list.
    /// @return The clones.
    function checkedCloneDeploys() internal pure returns (CloneDeploy[] memory) {
        CloneDeploy[] memory clones = cloneDeploys();
        if (clones.length == 0) {
            revert NoCloneDeploys();
        }
        return clones;
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

    /// @inheritdoc RainDeploySuitesBase
    function candidateSuites() internal view override returns (DeployCandidate[] memory) {
        CloneDeploy[] memory clones = checkedCloneDeploys();
        uint256[] memory chainIds = supportedChainIds();
        DeployCandidate[] memory candidates = new DeployCandidate[](clones.length);
        for (uint256 i = 0; i < clones.length; i++) {
            candidates[i] = LibRainDeployMechanism.cloneCandidate(clones[i], chainIds);
        }
        return candidates;
    }
}
