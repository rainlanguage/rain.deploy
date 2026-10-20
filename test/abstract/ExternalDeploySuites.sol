// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {
    DeployCandidate,
    DeployDependency,
    DeploySuite,
    RainDeploySuitesBase
} from "../../src/abstract/RainDeploySuitesBase.sol";

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
    function externalAllSuites() external view returns (DeploySuite[] memory) {
        return allSuites();
    }

    /// @param requested The suite key to select.
    /// @return The selected suite.
    function externalSuiteByName(string memory requested) external view returns (DeploySuite memory) {
        return suiteByName(requested);
    }

    /// @param requested The suite key to select.
    /// @return The index of the suite `requested` selects in `allSuites()`, its length if none.
    function externalSuiteIndex(string memory requested) external view returns (uint256) {
        return suiteIndex(allSuites(), requested);
    }

    /// @param suites The suites to search.
    /// @param requested The suite key to select.
    /// @return The index of the suite `requested` selects in `suites`, its length if none.
    function externalSuiteIndexIn(DeploySuite[] memory suites, string memory requested)
        external
        pure
        returns (uint256)
    {
        return suiteIndex(suites, requested);
    }

    /// @return The declared keys, comma separated.
    function externalSuiteNames() external view returns (string memory) {
        return suiteNames();
    }

    /// @return The networks the declaration names.
    function externalSupportedNetworks() external view returns (string[] memory) {
        return supportedNetworks();
    }

    function externalCheckSuiteKey(uint256 index, string memory suite) external pure {
        checkSuiteKey(index, suite);
    }

    /// @return The declared candidates, refusing an empty list.
    function externalCheckedCandidateSuites() external view returns (DeployCandidate[] memory) {
        return checkedCandidateSuites();
    }

    /// @return The record root the extended networks records are read from.
    function externalExtendedNetworksRoot() external view returns (string memory) {
        return extendedNetworksRoot();
    }

    /// Runs the source anchor over the fixture's own declaration.
    function externalCheckCandidatesAnchoredToSource() external view {
        checkCandidatesAnchoredToSource();
    }
}
