// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {
    DeployCandidate,
    DeployDeclaration,
    DeployDependency,
    DeploySuite,
    ExternalDeployment,
    RainDeploySuitesBase
} from "../../src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeployDeclaration} from "../../src/lib/LibRainDeployDeclaration.sol";
import {LibRainDeployZoltuMechanism} from "../../src/lib/LibRainDeployZoltuMechanism.sol";
import {LibBeaconTest} from "../lib/LibBeaconTest.sol";
import {MockDeployable} from "../concrete/MockDeployable.sol";
import {MockDependentDeployable} from "../concrete/MockDependentDeployable.sol";

address constant TRANSITIVE_DEPENDENCY = address(0xdef2);

abstract contract TransitiveDependencyDeploySuites is RainDeploySuitesBase {
    function declaration() internal view override returns (DeployDeclaration memory) {
        DeployDeclaration memory d;
        LibRainDeployDeclaration.extend(d);
        LibRainDeployZoltuMechanism.extend(d);
        DeploySuite[] memory released = new DeploySuite[](1);
        released[0] = siblingSuite();
        LibRainDeployDeclaration.addReleased(d, released);
        DeployCandidate[] memory candidates = new DeployCandidate[](1);
        candidates[0] = DeployCandidate({snapshot: dependentSuite(), unanchorableReason: ""});
        LibRainDeployDeclaration.addCandidates(d, candidates);
        d.externalDeployments = new ExternalDeployment[](1);
        d.externalDeployments[0] = ExternalDeployment({
            deployedAddress: TRANSITIVE_DEPENDENCY, codeHash: keccak256(type(MockDeployable).runtimeCode)
        });
        return d;
    }

    function siblingSuite() internal pure returns (DeploySuite memory) {
        DeploySuite memory suite = LibBeaconTest.zoltuSuite(
            "sibling@0_0_1",
            type(MockDeployable).creationCode,
            type(MockDeployable).runtimeCode,
            "test/concrete/MockDeployable.sol:MockDeployable"
        );
        suite.dependencies = new DeployDependency[](1);
        suite.dependencies[0] =
            DeployDependency({deployedAddress: TRANSITIVE_DEPENDENCY, runtimeCode: type(MockDeployable).runtimeCode});
        return suite;
    }

    function dependentSuite() internal pure returns (DeploySuite memory) {
        address sibling = siblingSuite().storedDeployedAddress;
        address[] memory reads = new address[](2);
        reads[0] = sibling;
        reads[1] = TRANSITIVE_DEPENDENCY;
        DeploySuite memory suite = LibBeaconTest.zoltuSuite(
            "dependent",
            abi.encodePacked(type(MockDependentDeployable).creationCode, abi.encode(reads)),
            type(MockDependentDeployable).runtimeCode,
            "test/concrete/MockDependentDeployable.sol:MockDependentDeployable"
        );
        suite.dependencies = new DeployDependency[](1);
        suite.dependencies[0] =
            DeployDependency({deployedAddress: sibling, runtimeCode: type(MockDeployable).runtimeCode});
        return suite;
    }

    function declaredDependentSuite() internal view returns (DeploySuite memory) {
        return declaration().candidates[0].snapshot;
    }
}
