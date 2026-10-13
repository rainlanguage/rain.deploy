// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";

import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {SafeTx} from "../../../src/lib/LibSafeTx.sol";
import {LibSafeFork} from "../../../src/lib/LibSafeFork.sol";
import {LibSafeTxBuilderJson} from "../../../src/lib/LibSafeTxBuilderJson.sol";
import {ExampleSafeBundleScript} from "../../concrete/ExampleSafeBundleScript.sol";
import {MockCallRecorder} from "../../concrete/MockCallRecorder.sol";
import {LibForkSafe} from "../../lib/LibForkSafe.sol";

/// @title SafeBundleScriptTest
/// The inherited `run()` and `verify()` of `SafeBundleScript`, driven through
/// `ExampleSafeBundleScript` against a real Safe v1.4.1 created on a Base fork.
contract SafeBundleScriptTest is Test {
    /// Every artifact this suite writes lives under its own root.
    string constant ARTIFACT_ROOT = "fixture-lib/safe-bundle-script";

    Safe internal sSafe;
    MockCallRecorder internal sRecorder;
    ExampleSafeBundleScript internal sScript;
    string internal sPath;

    /// A fork Safe with two owners and a threshold of two, a recorder, and the
    /// example script writing to `name`'s own artifact path.
    /// @param name The artifact's file name.
    function setUpScript(string memory name) internal {
        vm.createSelectFork(LibRainDeploy.BASE);
        address[] memory owners = new address[](2);
        owners[0] = makeAddr("owner0");
        owners[1] = makeAddr("owner1");
        sSafe = LibForkSafe.deploy(owners, 2);
        sRecorder = new MockCallRecorder();
        vm.createDir(ARTIFACT_ROOT, true);
        sPath = string.concat(ARTIFACT_ROOT, "/", name, ".json");
        sScript = new ExampleSafeBundleScript(sSafe, sRecorder, sPath);
    }

    /// `run()` simulates every transaction as the Safe, leaves the Safe's nonce
    /// where it was, and writes an artifact that `verify()` accepts.
    function testRunSimulatesWritesAndVerifies() external {
        setUpScript("run");
        uint256 nonce = sSafe.nonce();

        sScript.run();

        assertEq(sRecorder.callCount(), 2);
        assertEq(sRecorder.calls(0).caller, address(sSafe));
        assertEq(sRecorder.calls(0).data, bytes("first"));
        assertEq(sRecorder.calls(1).caller, address(sSafe));
        assertEq(sRecorder.calls(1).data, bytes("second"));
        assertEq(sSafe.nonce(), nonce);
        sScript.verify(sPath);
    }

    /// The written artifact is the bundle itself: parsed back and executed by
    /// the Safe's owners, it makes exactly the calls `run()` simulated.
    function testArtifactExecutesTheSimulatedBundle() external {
        setUpScript("execute");
        sScript.run();
        uint256 simulated = sRecorder.callCount();

        (, address artifactSafe, SafeTx[] memory txs) = LibSafeTxBuilderJson.fromJson(vm, vm.readFile(sPath));
        assertEq(artifactSafe, address(sSafe));
        LibSafeFork.executeBundle(vm, sSafe, txs);

        assertEq(sRecorder.callCount(), simulated + 2);
        assertEq(sRecorder.calls(simulated).data, bytes("first"));
        assertEq(sRecorder.calls(simulated + 1).data, bytes("second"));
    }

    /// `run()` authors nothing when `preflight` refuses.
    function testRunRefusesUnauthorableState() external {
        setUpScript("preflight-run");
        sScript.setRefusePreflight(true);

        vm.expectRevert(ExampleSafeBundleScript.NotAuthorable.selector);
        sScript.run();
        assertEq(sRecorder.callCount(), 0);
    }

    /// `run()` refuses when the simulated bundle does not leave the state it
    /// exists to produce.
    function testRunRefusesMissingPostState() external {
        setUpScript("post-state");
        // A call already recorded means the bundle's two leave three.
        vm.prank(address(sSafe));
        (bool ok,) = address(sRecorder).call("earlier");
        assertTrue(ok);

        vm.expectRevert(abi.encodeWithSelector(ExampleSafeBundleScript.PostStateMissing.selector, uint256(3)));
        sScript.run();
    }

    /// `run()` refuses when a transaction reverts in simulation.
    function testRunRefusesRevertingTransaction() external {
        setUpScript("reverting");
        sScript.setSecondCallData("revert");

        vm.expectRevert(MockCallRecorder.Refused.selector);
        sScript.run();
    }

    /// `verify()` refuses an artifact whose transactions differ from the
    /// bundle re-derived from live state.
    function testVerifyRefusesChangedBundle() external {
        setUpScript("changed");
        sScript.run();
        sScript.setSecondCallData("other");

        vm.expectRevert(abi.encodeWithSelector(LibSafeTxBuilderJson.ArtifactMismatch.selector, "data"));
        sScript.verify(sPath);
    }

    /// `verify()` refuses an artifact authored for another Safe.
    function testVerifyRefusesOtherSafe() external {
        setUpScript("other-safe");
        sScript.run();
        address[] memory owners = new address[](1);
        owners[0] = makeAddr("otherOwner");
        sScript.setSafe(LibForkSafe.deploy(owners, 1));

        vm.expectRevert(abi.encodeWithSelector(LibSafeTxBuilderJson.ArtifactMismatch.selector, "safe"));
        sScript.verify(sPath);
    }

    /// `verify()` refuses when `preflight` refuses, before reading the
    /// artifact.
    function testVerifyRefusesUnauthorableState() external {
        setUpScript("preflight-verify");
        sScript.run();
        sScript.setRefusePreflight(true);

        vm.expectRevert(ExampleSafeBundleScript.NotAuthorable.selector);
        sScript.verify(sPath);
    }
}
