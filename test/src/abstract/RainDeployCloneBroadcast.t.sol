// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {DeploySuite} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {LibRainDeployClone} from "../../../src/lib/LibRainDeployClone.sol";
import {ExampleCloneDeploy} from "../../concrete/ExampleCloneDeploy.sol";

/// @title RainDeployCloneBroadcastTest
/// Tests for `RainDeployCloneBroadcast`: the one function a clone repo overrides,
/// and therefore the one thing this abstract can get wrong.
///
/// `broadcastSuite` computes nothing. It picks which `…AndBroadcast` to call and
/// hands it what the selected suite carries — the clone the suite's KEY names,
/// the suite's recorded address, its recorded code hash and its dependencies. So
/// every claim here is about the HAND-OVER, and a stale recorded address is what
/// makes a hand-over readable: `cloneToNetworks` refuses it naming BOTH the
/// recorded address and the address the selected clone derives, before any network
/// is forked. Two arguments, one error, no RPC.
contract RainDeployCloneBroadcastTest is Test {
    /// The first declared clone's key.
    string constant FIRST_SUITE = "example-clone";

    /// The second declared clone's key. The SECOND is what the test selects,
    /// because a hand-over that ignored the key and took the first clone would be
    /// indistinguishable from a correct one on the first.
    string constant SECOND_SUITE = "example-clone-second-salt";

    /// `broadcastSuite` MUST hand the clone broadcast the clone the suite's KEY
    /// names and the address the suite RECORDS.
    ///
    /// Both at once, because one error reports both: the refusal names the
    /// recorded address it was handed and the address the clone it selected
    /// derives. A hand-over passing the zero address changes the first; one
    /// selecting a different clone changes the second; a `broadcastSuite` that
    /// never called through at all produces neither.
    ///
    /// Fork-free, and that is a property of the guard rather than of the fixture:
    /// the derivation check this lands on is the one `cloneToNetworks` makes
    /// BEFORE it creates any fork, which is why a stale address is the input that
    /// reaches it without an RPC.
    function testBroadcastSuiteHandsOverTheSelectedCloneAndTheRecordedAddress() external {
        ExampleCloneDeploy deploy = new ExampleCloneDeploy();

        DeploySuite memory suite = deploy.externalSuiteByName(SECOND_SUITE);
        address derived = LibRainDeployClone.cloneDeployedAddress(deploy.externalCloneDeployByName(SECOND_SUITE));

        // Stated rather than assumed: the declaration AGREES before this test
        // stales it, so the refusal below is this test's doing and not a fixture
        // that was already broken.
        assertEq(suite.storedDeployedAddress, derived, "the declaration must agree before it is staled");

        // The key is load-bearing: the first declared clone derives a DIFFERENT
        // address, so a hand-over that ignored the key would change the error.
        assertTrue(
            derived != LibRainDeployClone.cloneDeployedAddress(deploy.externalCloneDeployByName(FIRST_SUITE)),
            "the two declared clones must derive apart"
        );

        // One address higher: the smallest disagreement there is, so what the
        // error reports is the value handed over and not the size of the mistake.
        suite.storedDeployedAddress = address(uint160(derived) + 1);

        string[] memory networks = new string[](1);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;

        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.UnexpectedDeployedAddress.selector, suite.storedDeployedAddress, derived
            )
        );
        deploy.externalBroadcastSuite(suite, networks, 1);
    }
}
