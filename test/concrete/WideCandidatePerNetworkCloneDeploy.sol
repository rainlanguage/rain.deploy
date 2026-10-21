// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {RainDeployBroadcast} from "../../src/abstract/RainDeployBroadcast.sol";
import {DeployCandidate, DeploySuite, RainDeploySuitesBase} from "../../src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeploy} from "../../src/lib/LibRainDeploy.sol";
import {LibRainDeployMechanism} from "../../src/lib/LibRainDeployMechanism.sol";
import {perNetworkCloneChainIds} from "../abstract/PerNetworkCloneDeploys.sol";
import {upgradedPerNetworkClone} from "../abstract/UpgradedPerNetworkCloneDeploys.sol";

/// @title WideCandidatePerNetworkCloneDeploy
/// @notice A broadcast whose hand-written candidate declares Arbitrum One and Polygon while the repo supports Arbitrum
/// One alone.
contract WideCandidatePerNetworkCloneDeploy is RainDeployBroadcast {
    /// @inheritdoc RainDeploySuitesBase
    function supportedNetworks() internal pure override returns (string[] memory) {
        string[] memory networks = new string[](1);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;
        return networks;
    }

    /// @inheritdoc RainDeploySuitesBase
    function releasedSuites() internal pure override returns (DeploySuite[] memory) {
        return new DeploySuite[](0);
    }

    /// @inheritdoc RainDeploySuitesBase
    function candidateSuites() internal view override returns (DeployCandidate[] memory) {
        DeployCandidate[] memory candidates = new DeployCandidate[](1);
        candidates[0] = LibRainDeployMechanism.cloneCandidate(upgradedPerNetworkClone(), perNetworkCloneChainIds());
        return candidates;
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
