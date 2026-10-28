// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {RainDeployBroadcast} from "../../src/abstract/RainDeployBroadcast.sol";
import {DeployDeclaration} from "../../src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeployDeclaration} from "../../src/lib/LibRainDeployDeclaration.sol";
import {LibRainDeployZoltuMechanism} from "../../src/lib/LibRainDeployZoltuMechanism.sol";
import {ExternalDeploySuites} from "../abstract/ExternalDeploySuites.sol";
import {MisanchoredDeploySuites} from "../abstract/MisanchoredDeploySuites.sol";

contract MisanchoredDeploy is MisanchoredDeploySuites, ExternalDeploySuites, RainDeployBroadcast {
    function declaration() internal pure override returns (DeployDeclaration memory) {
        DeployDeclaration memory d;
        LibRainDeployDeclaration.extend(d);
        LibRainDeployZoltuMechanism.extend(d);
        LibRainDeployDeclaration.addCandidates(d, misanchoredCandidates());
        return d;
    }
}
