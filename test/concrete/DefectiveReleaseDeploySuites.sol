// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DeployDependency, DeploySuite, RainDeploySuitesBase} from "../../src/abstract/RainDeploySuitesBase.sol";
import {ReachingDeploySuites} from "../abstract/ReachingDeploySuites.sol";

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

contract ZeroDependencyReleaseDeploySuites is DefectiveReleaseDeploySuites {
    /// @inheritdoc RainDeploySuitesBase
    function releasedSuites() internal pure override returns (DeploySuite[] memory) {
        DeploySuite[] memory suites = new DeploySuite[](1);
        suites[0] = leafSuite("mock-deployable@0_0_1");
        suites[0].dependencies = new DeployDependency[](1);
        return suites;
    }
}

contract UndeclaredSiblingReleaseDeploySuites is DefectiveReleaseDeploySuites {
    /// @inheritdoc RainDeploySuitesBase
    function releasedSuites() internal pure override returns (DeploySuite[] memory) {
        DeploySuite[] memory suites = new DeploySuite[](1);
        suites[0] = reachingSuite("mock-reaching-deployable@0_0_1");
        DeployDependency[] memory deps = new DeployDependency[](1);
        deps[0] = suites[0].dependencies[1];
        suites[0].dependencies = deps;
        return suites;
    }
}

contract UnknownDependencyReleaseDeploySuites is DefectiveReleaseDeploySuites {
    /// @inheritdoc RainDeploySuitesBase
    function releasedSuites() internal pure override returns (DeploySuite[] memory) {
        DeploySuite[] memory suites = new DeploySuite[](1);
        suites[0] = leafSuite("mock-deployable@0_0_1");
        suites[0].dependencies = new DeployDependency[](1);
        suites[0].dependencies[0] = DeployDependency({deployedAddress: address(0xdead), runtimeCode: ""});
        return suites;
    }
}
