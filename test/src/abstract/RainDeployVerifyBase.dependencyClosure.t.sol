// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DerivedDeploy, RainDeployVerifyBase} from "../../../src/abstract/RainDeployVerifyBase.sol";
import {DeploySuite} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {TransitiveDependencyDeploySuites} from "../../abstract/TransitiveDependencyDeploySuites.sol";
import {READ_DEPENDENCY} from "../../concrete/MockDependencyReader.sol";
import {MockDependencyReaderCaller} from "../../concrete/MockDependencyReaderCaller.sol";

contract RainDeployVerifyBaseDependencyClosureTest is TransitiveDependencyDeploySuites, RainDeployVerifyBase {
    /// A constructor calling a declared sibling that reads a dependency only it declares derives, leaving no etch behind.
    function testDerivationEtchesADependencyOfADeclaredDependency() external {
        DeploySuite memory suite = declaredDependentSuite();
        address sibling = siblingSuite().storedDeployedAddress;

        DerivedDeploy memory derived = deriveDeployment(declaration(), suite);

        assertEq(derived.suite, "dependent");
        assertEq(derived.deployedAddresses.length, suite.networks.length);
        assertEq(derived.deployedAddresses[0], suite.storedDeployedAddress);
        assertEq(derived.bytecodeHash, keccak256(type(MockDependencyReaderCaller).runtimeCode));
        assertEq(sibling.code.length, 0);
        assertEq(READ_DEPENDENCY.code.length, 0);
    }
}
