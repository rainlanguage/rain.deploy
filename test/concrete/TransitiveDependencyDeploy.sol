// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DeploySuite} from "../../src/abstract/RainDeploySuitesBase.sol";
import {ExternalDeployBroadcast} from "../abstract/ExternalDeployBroadcast.sol";
import {TransitiveDependencyDeploySuites} from "../abstract/TransitiveDependencyDeploySuites.sol";

contract TransitiveDependencyDeploy is TransitiveDependencyDeploySuites, ExternalDeployBroadcast {
    function externalDependentSuite() external view returns (DeploySuite memory) {
        return declaredDependentSuite();
    }

    function externalSiblingSuite() external pure returns (DeploySuite memory) {
        return siblingSuite();
    }
}
