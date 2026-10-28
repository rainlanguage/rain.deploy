// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DeployDeclaration} from "../../src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeploy} from "../../src/lib/LibRainDeploy.sol";
import {LibRainDeployDeclaration} from "../../src/lib/LibRainDeployDeclaration.sol";
import {LibRainDeployZoltuMechanism} from "../../src/lib/LibRainDeployZoltuMechanism.sol";
import {ExampleDeployScript} from "../abstract/ExampleDeployScript.sol";

/// @title ExampleDeploySingleNetwork
/// A repo that bootstraps one chain per dispatch, which is the case
/// `d.deployNetworks` is narrowable FOR — `st0x.deploy` selects between
/// Ethereum and HyperEVM per dispatch rather than fanning out to everything.
///
/// The same declaration as `ExampleDeploy` and a different target set, so the
/// only thing a broadcast through this fixture can differ in is where it went.
/// A run that reached a network this does not name is a suite deployed
/// somewhere the repo did not ask for, and the narrowing being ignored is not
/// observable any other way: `d.deployNetworks` returning the right list says
/// nothing about `run()` consulting it.
///
/// ARBITRUM rather than any other alias, deliberately. It is the network
/// `supportedNetworks()` lists FIRST and this returns ONLY, and
/// `deployToNetworks` forks each network in turn without restoring — so the
/// chain left selected after a completed run is arbitrum here and polygon for
/// the default, which is the difference an assertion can see. A single-element
/// narrowing naming polygon would end on polygon either way and assert nothing.
contract ExampleDeploySingleNetwork is ExampleDeployScript {
    function declaration() internal pure override returns (DeployDeclaration memory) {
        DeployDeclaration memory d;
        LibRainDeployDeclaration.extend(d);
        LibRainDeployZoltuMechanism.extend(d);
        addExample(d);
        string[] memory deployNetworks = new string[](1);
        deployNetworks[0] = LibRainDeploy.ARBITRUM_ONE;
        LibRainDeployDeclaration.setDeployNetworks(d, deployNetworks);
        return d;
    }
}
