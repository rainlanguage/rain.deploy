// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {DeployDeclaration, DeploySuite, RainDeploySuitesBase} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeployDeclaration} from "../../../src/lib/LibRainDeployDeclaration.sol";
import {LibRainDeployZoltuMechanism} from "../../../src/lib/LibRainDeployZoltuMechanism.sol";

/// @title RainDeploySuitesBaseRequiresSuiteOnTest
/// @notice A suite is required exactly on the networks it lists.
contract RainDeploySuitesBaseRequiresSuiteOnTest is RainDeploySuitesBase, Test {
    function declaration() internal pure override returns (DeployDeclaration memory) {
        DeployDeclaration memory d;
        LibRainDeployDeclaration.extend(d);
        LibRainDeployZoltuMechanism.extend(d);
        return d;
    }

    /// @param key The suite key.
    /// @param listed The network the suite lists.
    /// @param other Another network.
    function testRequiresSuiteOnExactlyItsListedNetworks(string memory key, string memory listed, string memory other)
        external
        pure
    {
        vm.assume(keccak256(bytes(listed)) != keccak256(bytes(other)));
        DeploySuite memory suite;
        suite.suite = key;
        suite.networks = new string[](1);
        suite.networks[0] = listed;
        assertTrue(requiresSuiteOn(suite, listed));
        assertFalse(requiresSuiteOn(suite, other));
    }

    /// No listed network means no required network.
    /// @param network The network.
    function testRequiresSuiteOnNoNetworkWhenNoneListed(string memory network) external pure {
        DeploySuite memory suite;
        assertFalse(requiresSuiteOn(suite, network));
    }
}
