// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DeployDeclaration} from "../../src/abstract/RainDeploySuitesBase.sol";
import {ExampleDeployScript} from "../abstract/ExampleDeployScript.sol";

/// @title ExampleDeploy
/// `ExampleDeployScript` over the exemplar declaration as it stands.
contract ExampleDeploy is ExampleDeployScript {
    function declaration() internal pure override returns (DeployDeclaration memory) {
        return exampleDeclaration();
    }
}
