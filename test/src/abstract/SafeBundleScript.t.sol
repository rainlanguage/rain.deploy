// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";

import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {SafeTx, LibSafeTx} from "../../../src/lib/LibSafeTx.sol";
import {Enum} from "safe-global-safe-smart-account-1.4.1-3/contracts/common/Enum.sol";
import {LibSafeFork} from "../../../src/lib/LibSafeFork.sol";
import {LibSafeTxBuilderJson} from "../../../src/lib/LibSafeTxBuilderJson.sol";
import {ExampleSafeBundleScript} from "../../concrete/ExampleSafeBundleScript.sol";
import {IrreversibleExampleSafeBundleScript} from "../../concrete/IrreversibleExampleSafeBundleScript.sol";
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

    /// A fork Safe with two owners and a threshold of two, a recorder, and
    /// `name`'s own artifact path with no artifact at it, so only what this
    /// test writes can be read back.
    /// @param name The artifact's file name.
    function setUpFork(string memory name) internal {
        vm.createSelectFork(LibRainDeploy.BASE);
        address[] memory owners = new address[](2);
        owners[0] = makeAddr("owner0");
        owners[1] = makeAddr("owner1");
        sSafe = LibForkSafe.deploy(owners, 2);
        sRecorder = new MockCallRecorder();
        vm.createDir(ARTIFACT_ROOT, true);
        sPath = string.concat(ARTIFACT_ROOT, "/", name, ".json");
        if (vm.exists(sPath)) vm.removeFile(sPath);
    }

    /// The two calls `ExampleSafeBundleScript` authors by default.
    /// @return The transactions.
    function authoredBundle() internal view returns (SafeTx[] memory) {
        SafeTx[] memory txs = new SafeTx[](2);
        txs[0] = SafeTx({to: address(sRecorder), value: 0, data: "first", operation: Enum.Operation.Call});
        txs[1] = SafeTx({to: address(sRecorder), value: 0, data: "second", operation: Enum.Operation.Call});
        return txs;
    }

    /// `setUpFork`, and the example script writing to `name`'s artifact path.
    /// @param name The artifact's file name.
    function setUpScript(string memory name) internal {
        setUpFork(name);
        sScript = new ExampleSafeBundleScript(sSafe, sRecorder, sPath);
    }

    /// `run()` executes the bundle through the Safe as one MultiSend
    /// transaction, consuming exactly one nonce, and writes an artifact that
    /// `verify()` accepts. Both return the MultiSend `safeTxHash` the signers
    /// sign: `run()` at the nonce before execution, `verify()` at the live one.
    function testRunExecutesWritesAndVerifies() external {
        setUpScript("run");
        uint256 nonce = sSafe.nonce();
        SafeTx[] memory txs = authoredBundle();
        bytes32 expectedHash = LibSafeTx.multiSendSafeTxHash(sSafe, txs, nonce);

        assertEq(sScript.run(), expectedHash);

        assertEq(sRecorder.callCount(), 2);
        assertEq(sRecorder.calls(0).caller, address(sSafe));
        assertEq(sRecorder.calls(0).data, bytes("first"));
        assertEq(sRecorder.calls(1).caller, address(sSafe));
        assertEq(sRecorder.calls(1).data, bytes("second"));
        assertEq(sSafe.nonce(), nonce + 1);
        assertEq(sScript.verify(sPath), LibSafeTx.multiSendSafeTxHash(sSafe, txs, nonce + 1));
    }

    /// A transaction's value reaches its target: the bundle is executed with
    /// the value the artifact carries, not replayed without it.
    function testRunCarriesValue() external {
        setUpScript("value");
        vm.deal(address(sSafe), 1 ether);
        sScript.setSecondCallValue(0.25 ether);

        sScript.run();

        assertEq(sRecorder.calls(1).value, 0.25 ether);
        assertEq(address(sRecorder).balance, 0.25 ether);
        sScript.verify(sPath);
    }

    /// `run()` refuses when the bundle cannot be shown reversible, after the
    /// bundle executed and its post-state held, and writes no artifact for it.
    function testRunRefusesIrreversibleBundle() external {
        setUpFork("reversible");
        sScript = new IrreversibleExampleSafeBundleScript(sSafe, sRecorder, sPath);

        vm.expectRevert(IrreversibleExampleSafeBundleScript.NotReversible.selector);
        sScript.run();
        assertFalse(vm.exists(sPath));
    }

    /// A script that keeps the default `assertReversible` runs to completion:
    /// the default proves nothing and refuses nothing.
    function testRunAcceptsDefaultReversibility() external {
        setUpScript("default-reversible");

        sScript.run();

        assertEq(sRecorder.callCount(), 2);
    }

    /// The artifact names the bundle: its `meta.name` is the script's
    /// `bundleName`.
    function testRunWritesBundleName() external {
        setUpScript("name");

        sScript.run();

        assertEq(vm.parseJsonString(vm.readFile(sPath), ".meta.name"), "Example bundle");
    }

    /// The written artifact is the bundle itself: parsed back and executed by
    /// the Safe's owners, it makes exactly the calls `run()` executed.
    function testArtifactExecutesTheAuthoredBundle() external {
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

    /// `run()` refuses when `preflight` refuses, before deriving the bundle,
    /// and executes nothing.
    function testRunRefusesUnauthorableState() external {
        setUpScript("preflight-run");
        sScript.setRefusePreflight(true);

        vm.expectRevert(ExampleSafeBundleScript.NotAuthorable.selector);
        sScript.run();
        assertEq(sRecorder.callCount(), 0);
    }

    /// `run()` refuses when the simulated bundle does not leave the state it
    /// exists to produce, and writes no artifact for it.
    function testRunRefusesMissingPostState() external {
        setUpScript("post-state");
        // A call already recorded means the bundle's two leave three.
        vm.prank(address(sSafe));
        (bool ok,) = address(sRecorder).call("earlier");
        assertTrue(ok);

        vm.expectRevert(abi.encodeWithSelector(ExampleSafeBundleScript.PostStateMissing.selector, uint256(3)));
        sScript.run();
        assertFalse(vm.exists(sPath));
    }

    /// `run()` refuses when a transaction reverts: the Safe executing the
    /// MultiSend refuses the whole bundle with `GS013`, exactly as it would on
    /// chain.
    function testRunRefusesRevertingTransaction() external {
        setUpScript("reverting");
        sScript.setSecondCallData("revert");

        vm.expectRevert(bytes("GS013"));
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

    /// `verify()` refuses when `preflight` refuses, before deriving the
    /// bundle or reading the artifact.
    function testVerifyRefusesUnauthorableState() external {
        setUpScript("preflight-verify");
        sScript.run();
        sScript.setRefusePreflight(true);

        vm.expectRevert(ExampleSafeBundleScript.NotAuthorable.selector);
        sScript.verify(sPath);
    }

    /// `verify()` checks the artifact at the path it is given, not the one
    /// `run()` writes to.
    function testVerifyReadsGivenPath() external {
        setUpScript("given-path");
        sScript.run();
        string memory copy = string.concat(ARTIFACT_ROOT, "/given-path-copy.json");
        vm.copyFile(sPath, copy);
        vm.writeFile(sPath, "not an artifact");

        sScript.verify(copy);
    }
}
