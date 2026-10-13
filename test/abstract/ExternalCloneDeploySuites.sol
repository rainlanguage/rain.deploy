// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {RainDeployCloneSuitesBase} from "../../src/abstract/RainDeployCloneSuitesBase.sol";
import {DeployCandidate} from "../../src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeployMechanism} from "../../src/lib/LibRainDeployMechanism.sol";

/// @title ExternalCloneDeploySuites
/// @notice The clone declaration's own readers, exposed externally so a plain
/// `Test` contract can drive them and `vm.expectRevert` lands at the right call
/// depth. The clone half of `ExternalDeploySuites`, which covers the readers
/// every declaration has; this one exists only on a clone declaration.
///
/// Here rather than on each fixture for the reason `ExternalDeploySuites` gives:
/// a declaration that is refused has to be refused on ALL of its readers, and a
/// wrapper a fixture forgot to carry is a reader nothing checks that fixture
/// through.
///
/// A `CloneDeploy` carries an internal function, so it cannot cross an external
/// call: the declared clones are exposed by count and by the candidate each one
/// derives.
abstract contract ExternalCloneDeploySuites is RainDeployCloneSuitesBase {
    /// @return How many clones are declared, refusing an empty list.
    function externalCheckedCloneDeploysLength() external pure returns (uint256) {
        return checkedCloneDeploys().length;
    }

    /// @param index The clone's position in the declared list.
    /// @return The candidate `cloneCandidate` derives from that clone for the
    /// supported networks' chain ids.
    function externalCloneDeployCandidate(uint256 index) external view returns (DeployCandidate memory) {
        return LibRainDeployMechanism.cloneCandidate(checkedCloneDeploys()[index], supportedChainIds());
    }

    /// @return The chain id of every supported network, in order.
    function externalSupportedChainIds() external view returns (uint256[] memory) {
        return supportedChainIds();
    }
}
