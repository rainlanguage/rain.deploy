// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {Enum} from "safe-global-safe-smart-account-1.4.1-3/contracts/common/Enum.sol";

import {SafeBundleScript} from "../../src/abstract/SafeBundleScript.sol";
import {SafeTx} from "../../src/lib/LibSafeTx.sol";
import {MockCallRecorder} from "./MockCallRecorder.sol";

/// A bundle of two calls from a Safe into a call recorder, with each hook's
/// behaviour set by the test so the inherited `run()` and `verify()` can be
/// driven through every refusal.
contract ExampleSafeBundleScript is SafeBundleScript {
    /// `preflight` refuses.
    error NotAuthorable();
    /// `assertPostState` refuses.
    error PostStateMissing(uint256 callCount);

    Safe internal sSafe;
    MockCallRecorder internal sRecorder;
    string internal sArtifactPath;
    bool internal sRefusePreflight;
    bytes internal sSecondCallData;

    /// @param bundleSafe The Safe the bundle is for.
    /// @param recorder The call target.
    /// @param path Where `run()` writes the artifact.
    constructor(Safe bundleSafe, MockCallRecorder recorder, string memory path) {
        sSafe = bundleSafe;
        sRecorder = recorder;
        sArtifactPath = path;
        sSecondCallData = "second";
    }

    /// @param refuse Whether `preflight` refuses.
    function setRefusePreflight(bool refuse) external {
        sRefusePreflight = refuse;
    }

    /// @param data The second call's data, so a test can change the bundle
    /// after the artifact was written.
    function setSecondCallData(bytes memory data) external {
        sSecondCallData = data;
    }

    /// @param bundleSafe The Safe the script now targets.
    function setSafe(Safe bundleSafe) external {
        sSafe = bundleSafe;
    }

    /// @inheritdoc SafeBundleScript
    function safe() internal view override returns (Safe) {
        return sSafe;
    }

    /// @inheritdoc SafeBundleScript
    function preflight() internal view override {
        if (sRefusePreflight) revert NotAuthorable();
    }

    /// @inheritdoc SafeBundleScript
    function authorBundle() internal view override returns (SafeTx[] memory) {
        SafeTx[] memory txs = new SafeTx[](2);
        txs[0] = SafeTx({to: address(sRecorder), value: 0, data: "first", operation: Enum.Operation.Call});
        txs[1] = SafeTx({to: address(sRecorder), value: 0, data: sSecondCallData, operation: Enum.Operation.Call});
        return txs;
    }

    /// @inheritdoc SafeBundleScript
    function assertPostState() internal view override {
        uint256 callCount = sRecorder.callCount();
        if (callCount != 2) revert PostStateMissing(callCount);
    }

    /// @inheritdoc SafeBundleScript
    function artifactPath() internal view override returns (string memory) {
        return sArtifactPath;
    }

    /// @inheritdoc SafeBundleScript
    function bundleName() internal pure override returns (string memory) {
        return "Example bundle";
    }
}
