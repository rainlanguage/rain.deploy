// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";

import {UnknownDeploymentSuite} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {MockBroadcastDeploy} from "../../concrete/MockBroadcastDeploy.sol";

/// @title RainDeployBroadcastTest
/// @notice The broadcast entry point, driven exactly as the `Manual sol
/// artifacts` workflow drives it — through `DEPLOYMENT_SUITE` and
/// `DEPLOYMENT_KEY` env vars.
///
/// Nothing here broadcasts. Every case is one that fails before
/// `deployAndBroadcast` is reached, which is the half of `run()` that can be
/// tested without a key, an RPC and real money — and, not coincidentally, the
/// half that decides WHAT would be deployed.
contract RainDeployBroadcastTest is Test {
    MockBroadcastDeploy internal sDeploy;

    /// A deploy repo's whole script: the fixture declaration plus
    /// `RainDeployBroadcast`.
    function setUp() external {
        sDeploy = new MockBroadcastDeploy();
    }

    /// A mistyped suite MUST fail naming every valid suite, and MUST do so
    /// before `DEPLOYMENT_KEY` is read. `DEPLOYMENT_KEY` is deliberately unset
    /// here: if the key were read first, this would fail on the missing key and
    /// send the reader after the wrong thing entirely.
    function testRunUnknownSuiteRevertsBeforeReadingTheKey() external {
        vm.setEnv("DEPLOYMENT_SUITE", "address-registry");

        vm.expectRevert(
            abi.encodeWithSelector(
                UnknownDeploymentSuite.selector,
                "address-registry",
                "mock-deployable-0-0-1, mock-deployable-v2-0-0-2, mock-deployable-v2-candidate"
            )
        );
        sDeploy.run();
    }

    /// An unset `DEPLOYMENT_SUITE` MUST be an unknown suite rather than a
    /// default. A deploy that picks something when told nothing is how the
    /// wrong contract reaches a chain.
    function testRunUnsetSuiteReverts() external {
        vm.setEnv("DEPLOYMENT_SUITE", "");

        vm.expectRevert(
            abi.encodeWithSelector(
                UnknownDeploymentSuite.selector,
                "",
                "mock-deployable-0-0-1, mock-deployable-v2-0-0-2, mock-deployable-v2-candidate"
            )
        );
        sDeploy.run();
    }

    /// The default target set MUST be every supported network, so a
    /// deterministic deployment reaches one address on every chain from one
    /// dispatch and no repo restates the list.
    function testDeployNetworksDefaultsToSupportedNetworks() external view {
        string[] memory networks = sDeploy.externalDeployNetworks();
        string[] memory supported = LibRainDeploy.supportedNetworks();

        assertEq(networks.length, supported.length);
        for (uint256 i = 0; i < supported.length; i++) {
            assertEq(networks[i], supported[i]);
        }
    }

    /// The suite a key selects MUST be the one that would be broadcast — the
    /// creation code, the artifact path and the recorded pins all come from the
    /// same registry entry the verification contracts check.
    ///
    /// The recorded address and code hash are passed to `deployAndBroadcast`
    /// rather than derived at broadcast time on purpose:
    /// `LibRainDeploy.deployToNetworks` compares the recorded address against
    /// the creation code before it forks anything, and a derived value would
    /// make that comparison derived-against-derived.
    function testSelectedSuiteCarriesTheRecordedPins() external view {
        assertEq(
            sDeploy.externalSuiteByName("mock-deployable-0-0-1").storedDeployedAddress,
            LibRainDeploy.zoltuAddress(sDeploy.externalSuiteByName("mock-deployable-0-0-1").creationCode)
        );
        assertEq(
            sDeploy.externalSuiteByName("mock-deployable-0-0-1").artifactPath,
            "test/concrete/MockDeployable.sol:MockDeployable"
        );
    }
}
