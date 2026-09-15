// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {BuildScript} from "../../src/abstract/BuildScript.sol";
import {BuildHarness} from "./BuildHarness.sol";

/// @title BuildRecordRootHarness
/// @notice `Build` with its record root overridden — the one thing
/// `BuildScript` documents the root as being overridable for — and the
/// regeneration `cutRelease()` freezes from reachable from a test.
///
/// The regeneration alone. `run()` and `cutRelease()` also regenerate the libs,
/// and those are written into `LIB_DIR`, which no override moves, so either
/// entry point would rewrite committed libs that other test contracts read
/// while forge runs them in parallel.
contract BuildRecordRootHarness is BuildHarness {
    /// The record root this harness freezes into and regenerates under.
    string internal sRoot;

    /// @param root The fixture record root.
    constructor(string memory root) {
        sRoot = root;
    }

    /// @inheritdoc BuildScript
    function recordRoot() internal view override returns (string memory) {
        return sRoot;
    }

    /// Runs the hook `cutRelease()` regenerates through.
    function externalRegenerateSnapshots() external {
        regenerateSnapshots();
    }
}
