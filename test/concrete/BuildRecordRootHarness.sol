// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {BuildScript} from "../../src/abstract/BuildScript.sol";
import {BuildHarness} from "./BuildHarness.sol";

contract BuildRecordRootHarness is BuildHarness {
    string internal sRoot;

    constructor(string memory root) {
        sRoot = root;
    }

    /// @inheritdoc BuildScript
    function recordRoot() internal view override returns (string memory) {
        return sRoot;
    }

    function externalRegenerateSnapshots() external {
        regenerateSnapshots();
    }
}
