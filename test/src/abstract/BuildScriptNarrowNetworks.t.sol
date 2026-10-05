// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {BuildScriptHarness} from "../../concrete/BuildScriptHarness.sol";

/// @title BuildScriptNarrowNetworksTest
/// @notice The config is generated from the networks the declaration names and
/// from no others.
///
/// This is what the config group used to assert by comparison, re-expressed on
/// the generating side. There is one statement of the set now rather than two,
/// so there is nothing left to compare — but a generator that read this
/// package's catalogue instead of the declaration would put nine networks in
/// the `foundry.toml` of a repo that deploys to one, and that is still the
/// defect `arbitrum` named. What catches it now is the staged text.
///
/// The expectations are written out rather than built by calling
/// `LibRainDeployConfig`: an expectation assembled the way the generator
/// assembles its output passes for any spelling it happens to have, including
/// one that ignored the declaration entirely.
///
/// Base rather than any other alias, for the reason
/// `ExampleDeployNarrowNetworks` gives: it is neither the first nor the last
/// entry the catalogue lists.
contract BuildScriptNarrowNetworksTest is Test {
    /// The contract the fixture snapshots describe.
    string constant FIXTURE_CONTRACT = "Fixture";

    /// Where the narrowed-declaration fixture is built.
    string constant NARROW_FIXTURE_ROOT = "test/generated-buildscript-narrow";

    /// Where the uncatalogued-declaration fixture is built. Its own root, for
    /// the reason every other fixture root here has one: forge runs the tests
    /// in a contract in parallel.
    string constant UNCATALOGUED_FIXTURE_ROOT = "test/generated-buildscript-uncatalogued";

    /// A one-network declaration.
    /// @param network The name to declare.
    /// @return networks The declaration.
    function oneNetwork(string memory network) internal pure returns (string[] memory networks) {
        networks = new string[](1);
        networks[0] = network;
    }

    /// A seeded harness over a fresh fixture root, declaring exactly
    /// `networks`.
    /// @param root The fixture root.
    /// @param networks The networks to declare.
    /// @return The harness.
    function seededHarness(string memory root, string[] memory networks) internal returns (BuildScriptHarness) {
        if (vm.exists(root)) {
            //forge-lint: disable-next-line(unsafe-cheatcode)
            vm.removeDir(root, true);
        }
        BuildScriptHarness harness = new BuildScriptHarness(root, FIXTURE_CONTRACT);
        harness.declareNetworks(networks);
        harness.seedConfig();
        return harness;
    }

    /// PROPERTY: the generated config is the declared networks, exactly.
    ///
    /// Both files, because both are generated from the same selection and a
    /// `.env.example` holding endpoints for networks the repo does not deploy
    /// to is the same drift one direction further on.
    function testConfigIsHeldToTheDeclaredNetworks() external {
        string[] memory networks = oneNetwork(LibRainDeploy.BASE);
        assertLt(
            networks.length,
            LibRainDeploy.supportedNetworks().length,
            "this declaration names every supported network, so a generator that ignored it would read the same"
        );

        BuildScriptHarness harness = seededHarness(NARROW_FIXTURE_ROOT, networks);
        harness.run();

        // Read while the fixture is still there, asserted once it is gone.
        string memory stagedConfig = vm.readFile(harness.externalStagedConfigPath());
        string memory stagedEnvExample = vm.readFile(harness.externalStagedEnvExamplePath());

        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(NARROW_FIXTURE_ROOT, true);

        assertFalse(
            vm.contains(stagedConfig, LibRainDeploy.ARBITRUM_ONE),
            "[rpc_endpoints] alias is not a supported network: arbitrum"
        );
        assertEq(
            stagedConfig,
            string.concat(
                "# hand written\n",
                "# rain-deploy:generated:rpc_endpoints:begin\n",
                "[rpc_endpoints]\n",
                'base = "${BASE_RPC_URL}"\n',
                "# rain-deploy:generated:rpc_endpoints:end\n",
                "# rain-deploy:generated:etherscan:begin\n",
                "[etherscan]\n",
                'base = { key = "${CI_DEPLOY_BASE_ETHERSCAN_API_KEY}", chain = 8453 }\n',
                "# rain-deploy:generated:etherscan:end\n"
            )
        );
        assertEq(
            stagedEnvExample,
            string.concat(
                "# hand written\n",
                "# rain-deploy:generated:env:begin\n",
                "BASE_RPC_URL=https://mainnet.base.org\n",
                "# rain-deploy:generated:env:end\n"
            )
        );
    }

    /// PROPERTY: a declared network the catalogue states nothing about is
    /// REFUSED, naming it.
    ///
    /// The refusal that replaces the membership comparison. Skipping such a
    /// name instead would generate config for fewer networks than the repo
    /// deploys to and verifies on, from a build that reported success.
    function testConfigRefusesANetworkTheCatalogueDoesNotName() external {
        BuildScriptHarness harness = seededHarness(UNCATALOGUED_FIXTURE_ROOT, oneNetwork("nowhere"));

        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.NetworkNotInCatalogue.selector, "nowhere"));
        harness.run();

        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(UNCATALOGUED_FIXTURE_ROOT, true);
    }
}
