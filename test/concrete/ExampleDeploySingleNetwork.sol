// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {RainDeployBroadcast} from "../../src/abstract/RainDeployBroadcast.sol";
import {LibRainDeploy} from "../../src/lib/LibRainDeploy.sol";
import {ExampleDeploySuites} from "../abstract/ExampleDeploySuites.sol";

/// @title ExampleDeploySingleNetwork
/// A repo that bootstraps one chain per dispatch, which is the case
/// `deployNetworks()` is overridable FOR — `st0x.deploy` selects between
/// Ethereum and HyperEVM per dispatch rather than fanning out to everything.
///
/// The same declaration as `ExampleDeploy` and a different target set, so the
/// only thing a broadcast through this fixture can differ in is where it went.
/// A run that reached a network this does not name is a suite deployed
/// somewhere the repo did not ask for, and the override being ignored is not
/// observable any other way: `deployNetworks()` returning the right list says
/// nothing about `run()` consulting it.
///
/// ARBITRUM rather than any other alias, deliberately. It is the network
/// `supportedNetworks()` lists FIRST and this returns ONLY, and
/// `deployToNetworks` forks each network in turn without restoring — so the
/// chain left selected after a completed run is arbitrum here and polygon for
/// the default, which is the difference an assertion can see. A single-element
/// override naming polygon would end on polygon either way and assert nothing.
contract ExampleDeploySingleNetwork is ExampleDeploySuites, RainDeployBroadcast {
    /// @inheritdoc RainDeployBroadcast
    function deployNetworks() internal pure override returns (string[] memory networks) {
        networks = new string[](1);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;
    }
}
