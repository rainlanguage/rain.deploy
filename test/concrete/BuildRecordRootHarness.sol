// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {BuildScript} from "../../src/abstract/BuildScript.sol";
import {DeployDeclaration} from "../../src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeploySnapshot} from "../../src/lib/LibRainDeploySnapshot.sol";
import {BuildHarness} from "./BuildHarness.sol";

/// @title BuildRecordRootHarness
/// @notice `Build` with its record root overridden — the one thing
/// `BuildScript` documents the root as being overridable for — and the
/// regeneration and freeze `cutRelease()` runs reachable from a test.
///
/// Neither `run()` nor `cutRelease()` is reachable: both also regenerate the
/// libs, written into `LIB_DIR`, which no override moves, so either entry point
/// would rewrite committed libs that other test contracts read while forge
/// runs them in parallel. `externalFreeze` is the freeze without that step.
contract BuildRecordRootHarness is BuildHarness {
    string internal sRoot;

    constructor(string memory root) BuildHarness("") {
        sRoot = root;
    }

    /// @inheritdoc BuildScript
    function recordRoot() internal view override returns (string memory) {
        return sRoot;
    }

    function externalRegenerateSnapshots() external {
        regenerateSnapshots();
    }

    /// The freeze `cutRelease()` runs, without the lib regeneration that would
    /// write into `LIB_DIR`.
    function externalFreeze() external {
        DeployDeclaration memory d = declaration();
        LibRainDeploySnapshot.freeze(
            vm, recordRoot(), regenerateSnapshots, releaseRecordNames(d, checkedGeneratedContracts(d))
        );
    }
}
