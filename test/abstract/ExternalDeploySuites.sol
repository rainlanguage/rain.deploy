// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {DeployCandidate, DeploySuite, RainDeploySuitesBase} from "../../src/abstract/RainDeploySuitesBase.sol";

/// @title ExternalDeploySuites
/// @notice Every reader of the declaration, exposed externally so a plain
/// `Test` contract can drive them and `vm.expectRevert` lands at the right call
/// depth.
///
/// Here rather than on each fixture because every fixture needs all of them,
/// and a declaration that is refused has to be refused on ALL of them — a
/// wrapper a fixture forgot to carry is a reader nothing checks that fixture
/// through.
abstract contract ExternalDeploySuites is RainDeploySuitesBase {
    /// @return Every declared suite.
    function externalAllSuites() external pure returns (DeploySuite[] memory) {
        return allSuites();
    }

    /// @param requested The suite key to select.
    /// @return The selected suite.
    function externalSuiteByName(string memory requested) external pure returns (DeploySuite memory) {
        return suiteByName(requested);
    }

    /// @return The declared keys, comma separated.
    function externalSuiteNames() external pure returns (string memory) {
        return suiteNames();
    }

    /// @return The declared candidates, refusing an empty list.
    function externalCheckedCandidateSuites() external pure returns (DeployCandidate[] memory) {
        return checkedCandidateSuites();
    }

    /// Runs the source anchor over the fixture's own declaration.
    function externalCheckCandidatesAnchoredToSource() external pure {
        checkCandidatesAnchoredToSource();
    }
}
