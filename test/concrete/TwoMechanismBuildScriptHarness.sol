// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {BuildScript} from "../../src/abstract/BuildScript.sol";
import {ExternalDeploySuites} from "../abstract/ExternalDeploySuites.sol";
import {TwoMechanismDeploySuites} from "../abstract/TwoMechanismDeploySuites.sol";

contract TwoMechanismBuildScriptHarness is TwoMechanismDeploySuites, ExternalDeploySuites, BuildScript {
    function snapshotContractNames() internal pure override returns (string[] memory) {
        return new string[](0);
    }

    function regenerateSnapshots() internal override {}

    function regenerateLibs() internal override {}
}
