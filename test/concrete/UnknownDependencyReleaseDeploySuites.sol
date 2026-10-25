// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DeployDependency, DeploySuite, RainDeploySuitesBase} from "../../src/abstract/RainDeploySuitesBase.sol";
import {DefectiveReleaseDeploySuites} from "../abstract/DefectiveReleaseDeploySuites.sol";

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
