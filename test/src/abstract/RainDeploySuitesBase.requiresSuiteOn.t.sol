// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {DeploySuite} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {ExampleDeploySuites} from "../../abstract/ExampleDeploySuites.sol";

/// @title RainDeploySuitesBaseRequiresSuiteOnTest
/// @notice The default requires every suite on every network.
contract RainDeploySuitesBaseRequiresSuiteOnTest is ExampleDeploySuites, Test {
    /// Any suite key on any network is required.
    /// @param key The suite key.
    /// @param network The network.
    function testRequiresSuiteOnDefaultsToTrue(string memory key, string memory network) external view {
        DeploySuite memory suite;
        suite.suite = key;
        assertTrue(requiresSuiteOn(suite, network));
    }
}
