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
import {MockDependencyReader, READ_DEPENDENCY} from "../concrete/MockDependencyReader.sol";
import {MockDependencyReaderCaller} from "../concrete/MockDependencyReaderCaller.sol";

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
            deployedAddress: READ_DEPENDENCY, codeHash: keccak256(type(MockDeployable).runtimeCode)
        });
        return d;
    }

    function siblingSuite() internal pure returns (DeploySuite memory) {
        DeploySuite memory suite = LibBeaconTest.zoltuSuite(
            "sibling@0_0_1",
            type(MockDependencyReader).creationCode,
            type(MockDependencyReader).runtimeCode,
            "test/concrete/MockDependencyReader.sol:MockDependencyReader"
        );
        suite.dependencies = new DeployDependency[](1);
        suite.dependencies[0] =
            DeployDependency({deployedAddress: READ_DEPENDENCY, runtimeCode: type(MockDeployable).runtimeCode});
        return suite;
    }

    function dependentSuite() internal pure returns (DeploySuite memory) {
        address sibling = siblingSuite().storedDeployedAddress;
        DeploySuite memory suite = LibBeaconTest.zoltuSuite(
            "dependent",
            abi.encodePacked(type(MockDependencyReaderCaller).creationCode, abi.encode(sibling)),
            type(MockDependencyReaderCaller).runtimeCode,
            "test/concrete/MockDependencyReaderCaller.sol:MockDependencyReaderCaller"
        );
        suite.dependencies = new DeployDependency[](1);
        suite.dependencies[0] =
            DeployDependency({deployedAddress: sibling, runtimeCode: type(MockDependencyReader).runtimeCode});
        return suite;
    }

    function declaredDependentSuite() internal view returns (DeploySuite memory) {
        return declaration().candidates[0].snapshot;
    }
}
