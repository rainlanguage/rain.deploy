// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DeployDeclaration, DeployDependency, DeploySuite} from "../../src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeployDeclaration} from "../../src/lib/LibRainDeployDeclaration.sol";
import {LibRainDeployZoltuMechanism} from "../../src/lib/LibRainDeployZoltuMechanism.sol";
import {DefectiveReleaseDeploySuites} from "../abstract/DefectiveReleaseDeploySuites.sol";

contract ZeroDependencyReleaseDeploySuites is DefectiveReleaseDeploySuites {
    function declaration() internal view override returns (DeployDeclaration memory) {
        DeployDeclaration memory d;
        LibRainDeployDeclaration.extend(d);
        LibRainDeployZoltuMechanism.extend(d);
        LibRainDeployDeclaration.addReleased(d, defectiveReleased());
        LibRainDeployDeclaration.addCandidates(d, reachingCandidates());
        return d;
    }

    function defectiveReleased() internal pure returns (DeploySuite[] memory) {
        DeploySuite[] memory suites = new DeploySuite[](1);
        suites[0] = leafSuite("mock-deployable@0_0_1");
        suites[0].dependencies = new DeployDependency[](1);
        return suites;
    }
}
