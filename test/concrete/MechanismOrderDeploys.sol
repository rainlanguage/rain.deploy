// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DeployMechanismHandler, DeploySuite} from "../../src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeployZoltuMechanism} from "../../src/lib/LibRainDeployZoltuMechanism.sol";
import {ExternalDeploySuites} from "../abstract/ExternalDeploySuites.sol";
import {TwoMechanismDeploySuites} from "../abstract/TwoMechanismDeploySuites.sol";
import {LibMockCreate2Mechanism} from "../lib/LibMockCreate2Mechanism.sol";
import {LibMockSaltMechanism} from "../lib/LibMockSaltMechanism.sol";

function claimsAnyMechanismData(DeploySuite memory suite) pure returns (bool) {
    return suite.mechanismData.length != 0;
}

/// `LibMockSaltMechanism` claiming every suite with mechanism data.
function greedySaltHandler() pure returns (DeployMechanismHandler memory) {
    DeployMechanismHandler memory handler = LibMockSaltMechanism.handler();
    handler.claims = claimsAnyMechanismData;
    return handler;
}

contract GreedyFirstDeploy is TwoMechanismDeploySuites, ExternalDeploySuites {
    function mechanisms() internal pure override returns (DeployMechanismHandler[] memory) {
        DeployMechanismHandler[] memory handlers = new DeployMechanismHandler[](3);
        handlers[0] = greedySaltHandler();
        handlers[1] = LibMockCreate2Mechanism.handler();
        handlers[2] = LibRainDeployZoltuMechanism.handler();
        return handlers;
    }
}

contract GreedyLastDeploy is TwoMechanismDeploySuites, ExternalDeploySuites {
    function mechanisms() internal pure override returns (DeployMechanismHandler[] memory) {
        DeployMechanismHandler[] memory handlers = new DeployMechanismHandler[](3);
        handlers[0] = LibMockCreate2Mechanism.handler();
        handlers[1] = greedySaltHandler();
        handlers[2] = LibRainDeployZoltuMechanism.handler();
        return handlers;
    }
}

contract NoZoltuDeploy is TwoMechanismDeploySuites, ExternalDeploySuites {
    function mechanisms() internal pure override returns (DeployMechanismHandler[] memory) {
        DeployMechanismHandler[] memory handlers = new DeployMechanismHandler[](2);
        handlers[0] = LibMockSaltMechanism.handler();
        handlers[1] = LibMockCreate2Mechanism.handler();
        return handlers;
    }
}
