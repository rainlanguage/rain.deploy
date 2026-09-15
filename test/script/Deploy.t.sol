// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";
import {DeployHarness} from "../concrete/DeployHarness.sol";
import {LibStringSet} from "../../src/lib/LibStringSet.sol";

/// @title DeployTest
/// @notice `script/Deploy.sol` has an empty body, and an empty body is a claim:
/// that a dispatch of this script reaches every network this repo is configured
/// for, because nothing here narrows the inherited target set.
///
/// The declaration half of that claim needs no test. `RegistryDeploySuites`
/// spells `releasedSuites` and `candidateSuites` as `override` without
/// `virtual`, so a script that tried to broadcast a different set of suites
/// than the verification contracts check would not compile.
///
/// `deployNetworks` is the half that is left. It IS virtual — a repo
/// bootstrapping onto one chain at a time overrides it — so this repo taking
/// the inherited answer is a decision rather than a guarantee, and a narrowed
/// one here is a dispatch that silently skips chains while every assertion in
/// this repo stays green.
contract DeployTest is Test {
    DeployHarness internal sDeploy;

    function setUp() external {
        sDeploy = new DeployHarness();
    }

    /// PROPERTY: a dispatch of this script targets EXACTLY the networks
    /// `foundry.toml` configures an RPC for.
    ///
    /// Matched against the config rather than against `supportedNetworks()`,
    /// which is the value the script's inherited body returns: an assertion
    /// written against that would be the implementation compared to itself and
    /// would pass for any override that happened to call it. The config is a
    /// separate statement of the same set, and
    /// `testSupportedNetworksAreFullyConfigured` is what holds the two together
    /// — so a narrowing here fails, and a network added to one place and not
    /// the other fails there.
    ///
    /// Both directions, because containment one way passes for a script that
    /// deploys to a subset and the other way for a config carrying an alias
    /// nothing deploys to. Membership rather than position: a config section is
    /// keyed rather than ordered.
    function testDeployBroadcastsToEveryConfiguredNetwork() external view {
        string[] memory targets = sDeploy.externalDeployNetworks();
        string[] memory rpcAliases = vm.parseTomlKeys(vm.readFile("foundry.toml"), ".rpc_endpoints");

        assertEq(
            targets.length, rpcAliases.length, "the deploy targets a different number of networks than are configured"
        );

        for (uint256 i = 0; i < targets.length; i++) {
            assertTrue(
                LibStringSet.holds(rpcAliases, targets[i]),
                string.concat("the deploy targets a network with no [rpc_endpoints] alias: ", targets[i])
            );
        }

        for (uint256 i = 0; i < rpcAliases.length; i++) {
            assertTrue(
                LibStringSet.holds(targets, rpcAliases[i]),
                string.concat("a configured network is not a deploy target: ", rpcAliases[i])
            );
        }
    }
}
