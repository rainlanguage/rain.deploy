// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DeployDeclaration} from "../../src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeploy} from "../../src/lib/LibRainDeploy.sol";
import {LibRainDeployDeclaration} from "../../src/lib/LibRainDeployDeclaration.sol";
import {LibRainDeployZoltuMechanism} from "../../src/lib/LibRainDeployZoltuMechanism.sol";
import {ExampleDeployScript} from "../abstract/ExampleDeployScript.sol";

/// @title ExampleDeployArbitrumNetworks
/// The exemplar declaration narrowed to Arbitrum One alone, so a dispatch can reach a network outside it.
contract ExampleDeployArbitrumNetworks is ExampleDeployScript {
    function declaration() internal pure override returns (DeployDeclaration memory) {
        DeployDeclaration memory d;
        LibRainDeployDeclaration.extend(d);
        d.networks = new string[](1);
        d.networks[0] = LibRainDeploy.ARBITRUM_ONE;
        LibRainDeployZoltuMechanism.extend(d);
        addExample(d);
        return d;
    }
}
