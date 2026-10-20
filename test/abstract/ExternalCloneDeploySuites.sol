// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {RainDeployCloneSuitesBase} from "../../src/abstract/RainDeployCloneSuitesBase.sol";
import {DeployCandidate} from "../../src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeployMechanism} from "../../src/lib/LibRainDeployMechanism.sol";

/// @title ExternalCloneDeploySuites
/// @notice The clone declaration's own readers, exposed externally so a plain `Test` contract can
/// drive them and `vm.expectRevert` lands at the right call depth.
abstract contract ExternalCloneDeploySuites is RainDeployCloneSuitesBase {
    /// @return How many clones are declared.
    function externalCloneDeploysLength() external pure returns (uint256) {
        return cloneDeploys().length;
    }

    /// @param index The clone's position in the declared list.
    /// @return The candidate `cloneCandidate` derives from that clone for the supported networks'
    /// chain ids.
    function externalCloneDeployCandidate(uint256 index) external view returns (DeployCandidate memory) {
        return LibRainDeployMechanism.cloneCandidate(cloneDeploys()[index], supportedChainIds());
    }

    /// @return The chain id of every supported network, in order.
    function externalSupportedChainIds() external view returns (uint256[] memory) {
        return supportedChainIds();
    }

    /// @return The number of beacon proxies `beaconProxyDeploys()` declares.
    function externalBeaconProxyDeploysLength() external pure returns (uint256) {
        return beaconProxyDeploys().length;
    }

    /// @param index The beacon proxy's index in `beaconProxyDeploys()`.
    /// @return Its candidate, as `LibRainDeployMechanism.beaconProxyCandidate` builds it for the supported chain
    /// ids.
    function externalBeaconProxyDeployCandidate(uint256 index) external view returns (DeployCandidate memory) {
        return LibRainDeployMechanism.beaconProxyCandidate(beaconProxyDeploys()[index], supportedChainIds());
    }
}
