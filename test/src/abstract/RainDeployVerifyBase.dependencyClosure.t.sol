// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DerivedDeploy, RainDeployVerifyBase} from "../../../src/abstract/RainDeployVerifyBase.sol";
import {DeploySuite} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {
    TRANSITIVE_DEPENDENCY,
    TransitiveDependencyDeploySuites
} from "../../abstract/TransitiveDependencyDeploySuites.sol";
import {MockDependentDeployable} from "../../concrete/MockDependentDeployable.sol";

contract RainDeployVerifyBaseDependencyClosureTest is TransitiveDependencyDeploySuites, RainDeployVerifyBase {
    /// A constructor reading a dependency only its declared sibling declares derives, leaving no etch behind.
    function testDerivationEtchesADependencyOfADeclaredDependency() external {
        DeploySuite memory suite = declaredDependentSuite();
        address sibling = siblingSuite().storedDeployedAddress;

        DerivedDeploy memory derived = deriveDeployment(declaration(), suite);

        assertEq(derived.suite, "dependent");
        assertEq(derived.deployedAddresses.length, suite.networks.length);
        assertEq(derived.deployedAddresses[0], suite.storedDeployedAddress);
        assertEq(derived.bytecodeHash, keccak256(type(MockDependentDeployable).runtimeCode));
        assertEq(sibling.code.length, 0);
        assertEq(TRANSITIVE_DEPENDENCY.code.length, 0);
    }
}
