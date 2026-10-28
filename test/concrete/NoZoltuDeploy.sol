// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DeployDeclaration} from "../../src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeployDeclaration} from "../../src/lib/LibRainDeployDeclaration.sol";
import {ExternalDeploySuites} from "../abstract/ExternalDeploySuites.sol";
import {TwoMechanismDeploySuites} from "../abstract/TwoMechanismDeploySuites.sol";
import {LibMockCreate2Mechanism} from "../lib/LibMockCreate2Mechanism.sol";
import {LibMockSaltMechanism} from "../lib/LibMockSaltMechanism.sol";

/// `TwoMechanismDeploy`'s declaration without Zoltu.
contract NoZoltuDeploy is TwoMechanismDeploySuites, ExternalDeploySuites {
    function declaration() internal pure override returns (DeployDeclaration memory) {
        DeployDeclaration memory d;
        LibRainDeployDeclaration.extend(d);
        LibMockSaltMechanism.extend(d);
        LibMockCreate2Mechanism.extend(d);
        addTwoMechanismCandidates(d);
        return d;
    }
}
