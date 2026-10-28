// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";

import {ExampleSafeBundleScript} from "./ExampleSafeBundleScript.sol";
import {MockCallRecorder} from "./MockCallRecorder.sol";

/// `ExampleSafeBundleScript` with a bundle that cannot be shown reversible.
contract IrreversibleExampleSafeBundleScript is ExampleSafeBundleScript {
    /// `assertReversible` refuses.
    error NotReversible();

    /// Read, not a bare revert: the compiler specialises the inherited `run()`
    /// for this contract and reports every statement after an unconditional
    /// revert as unreachable, which `forge lint -D warnings` refuses.
    bool internal sIrreversible = true;

    /// @param bundleSafe The Safe the bundle is for.
    /// @param recorder The call target.
    /// @param path Where `run()` writes the artifact.
    constructor(Safe bundleSafe, MockCallRecorder recorder, string memory path)
        ExampleSafeBundleScript(bundleSafe, recorder, path)
    {}

    /// Refuses every bundle.
    function assertReversible() internal view override {
        if (sIrreversible) revert NotReversible();
    }
}
