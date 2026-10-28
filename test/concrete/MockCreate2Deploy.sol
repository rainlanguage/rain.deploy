// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DeployDeclaration} from "../../src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeployDeclaration} from "../../src/lib/LibRainDeployDeclaration.sol";
import {LibRainDeployZoltuMechanism} from "../../src/lib/LibRainDeployZoltuMechanism.sol";
import {ExternalDeployBroadcast} from "../abstract/ExternalDeployBroadcast.sol";
import {MockCreate2DeploySuites} from "../abstract/MockCreate2DeploySuites.sol";
import {LibMockCreate2Mechanism} from "../lib/LibMockCreate2Mechanism.sol";

contract MockCreate2Deploy is MockCreate2DeploySuites, ExternalDeployBroadcast {
    function declaration() internal view override returns (DeployDeclaration memory) {
        DeployDeclaration memory d;
        LibRainDeployDeclaration.extend(d);
        LibMockCreate2Mechanism.extend(d);
        LibRainDeployZoltuMechanism.extend(d);
        addMockCreate2(d);
        return d;
    }
}
