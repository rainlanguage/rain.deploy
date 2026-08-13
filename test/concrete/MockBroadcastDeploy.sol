// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DeploySuite} from "../../src/abstract/RainDeploySuitesBase.sol";
import {RainDeployBroadcast} from "../../src/abstract/RainDeployBroadcast.sol";
import {MockDeploySuites} from "../abstract/MockDeploySuites.sol";

/// @title MockBroadcastDeploy
/// A deploy repo's whole script, as a fixture — the fixture suite declaration
/// plus `RainDeployBroadcast` and nothing else, which is exactly what
/// `script/Deploy.sol` is. The external wrappers exist so a plain `Test`
/// contract can drive the internals without inheriting `Script`.
contract MockBroadcastDeploy is MockDeploySuites, RainDeployBroadcast {
    /// @param requested The suite key to select.
    /// @return The selected suite.
    function externalSuiteByName(string memory requested) external pure returns (DeploySuite memory) {
        return suiteByName(requested);
    }

    /// @return Every declared suite.
    function externalAllSuites() external pure returns (DeploySuite[] memory) {
        return allSuites();
    }

    /// @return The declared keys, comma separated.
    function externalSuiteNames() external pure returns (string memory) {
        return suiteNames();
    }

    /// @return The networks a broadcast would go to.
    function externalDeployNetworks() external view returns (string[] memory) {
        return deployNetworks();
    }
}
