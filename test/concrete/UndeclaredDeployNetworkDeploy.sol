// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DeployDeclaration} from "../../src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeploy} from "../../src/lib/LibRainDeploy.sol";
import {LibRainDeployDeclaration} from "../../src/lib/LibRainDeployDeclaration.sol";
import {LibRainDeployZoltuMechanism} from "../../src/lib/LibRainDeployZoltuMechanism.sol";
import {ExampleDeployScript} from "../abstract/ExampleDeployScript.sol";

string constant UNALIASED_DEPLOY_NETWORK = "unaliased";

/// @title UndeclaredDeployNetworkDeploy
/// The exemplar declaration narrowed to Arbitrum One, deploying to Arbitrum One, Base and a name that is no alias.
contract UndeclaredDeployNetworkDeploy is ExampleDeployScript {
    function declaration() internal pure override returns (DeployDeclaration memory) {
        DeployDeclaration memory d;
        LibRainDeployDeclaration.extend(d);
        string[] memory networks = new string[](1);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;
        LibRainDeployDeclaration.setNetworks(d, networks);
        LibRainDeployZoltuMechanism.extend(d);
        addExample(d);
        string[] memory deployNetworks = new string[](3);
        deployNetworks[0] = LibRainDeploy.ARBITRUM_ONE;
        deployNetworks[1] = LibRainDeploy.BASE;
        deployNetworks[2] = UNALIASED_DEPLOY_NETWORK;
        LibRainDeployDeclaration.setDeployNetworks(d, deployNetworks);
        return d;
    }
}
