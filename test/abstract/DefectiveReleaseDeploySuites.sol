// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {ReachingDeploySuites} from "./ReachingDeploySuites.sol";

/// A `ReachingDeploySuites` whose one defect is in a released suite, exposing
/// the checks for a test to call.
abstract contract DefectiveReleaseDeploySuites is ReachingDeploySuites {
    function externalCheckDependenciesAreNonZeroAndUnique() external view {
        checkDependenciesAreNonZeroAndUnique();
    }

    function externalCheckDependenciesAreTheEmbeddedDeployments() external view {
        checkDependenciesAreTheEmbeddedDeployments();
    }

    function externalCheckDependencyRuntimeCodeIsKnown() external view {
        checkDependencyRuntimeCodeIsKnown();
    }
}
