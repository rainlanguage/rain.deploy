// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {DeployDeclaration, DeploySuite} from "../../src/abstract/RainDeploySuitesBase.sol";
import {ExternalDeployBroadcast} from "../abstract/ExternalDeployBroadcast.sol";
import {TransitiveDependencyDeploySuites} from "../abstract/TransitiveDependencyDeploySuites.sol";

contract TransitiveDependencyDeploy is TransitiveDependencyDeploySuites, ExternalDeployBroadcast {
    function externalDependentSuite() external view returns (DeploySuite memory) {
        return declaredDependentSuite();
    }

    function externalSiblingSuite() external pure returns (DeploySuite memory) {
        return siblingSuite();
    }

    function declaredSuites(DeployDeclaration memory d) internal pure returns (bytes memory) {
        return abi.encode(d.released, d.candidates);
    }

    /// @return The declaration's released suites and candidates, encoded before and after `deployAndBroadcast`.
    function externalDeclaredSuitesAroundDeployAndBroadcast(
        Vm forkVm,
        string[] memory networks,
        uint256 deployerPrivateKey,
        DeploySuite memory frozen,
        DeploySuite memory candidate
    ) external returns (bytes memory, bytes memory) {
        DeployDeclaration memory d = declaration();
        bytes memory declared = declaredSuites(d);
        deployAndBroadcast(d, forkVm, networks, deployerPrivateKey, frozen, candidate);
        return (declared, declaredSuites(d));
    }

    /// @return The declaration's released suites and candidates, encoded before and after `checkSeatsNoDeployKey`.
    function externalDeclaredSuitesAroundCheckSeatsNoDeployKey(
        DeploySuite memory suite,
        uint256[] memory chainIds,
        address deployer
    ) external returns (bytes memory, bytes memory) {
        DeployDeclaration memory d = declaration();
        bytes memory declared = declaredSuites(d);
        checkSeatsNoDeployKey(d, suite, chainIds, deployer);
        return (declared, declaredSuites(d));
    }
}
