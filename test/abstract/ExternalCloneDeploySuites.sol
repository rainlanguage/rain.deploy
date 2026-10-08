// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {RainDeployCloneSuitesBase} from "../../src/abstract/RainDeployCloneSuitesBase.sol";
import {CloneDeploy} from "../../src/lib/LibRainDeployClone.sol";

/// @title ExternalCloneDeploySuites
/// @notice The clone declaration's own readers, exposed externally so a plain
/// `Test` contract can drive them and `vm.expectRevert` lands at the right call
/// depth. The clone half of `ExternalDeploySuites`, which covers the readers
/// every declaration has; these two exist only on a clone declaration.
///
/// Here rather than on each fixture for the reason `ExternalDeploySuites` gives:
/// a declaration that is refused has to be refused on ALL of its readers, and a
/// wrapper a fixture forgot to carry is a reader nothing checks that fixture
/// through.
abstract contract ExternalCloneDeploySuites is RainDeployCloneSuitesBase {
    /// @return The declared clones, refusing an empty list.
    function externalCheckedCloneDeploys() external pure returns (CloneDeploy[] memory) {
        return checkedCloneDeploys();
    }

    /// @param requested The suite key to select.
    /// @return The selected clone.
    function externalCloneDeployByName(string memory requested) external pure returns (CloneDeploy memory) {
        return cloneDeployByName(requested);
    }
}
