// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {RainDeployBroadcast} from "../../src/abstract/RainDeployBroadcast.sol";
import {
    DeployCandidate,
    DeployDependency,
    DeploySuite,
    RainDeploySuitesBase
} from "../../src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeploy} from "../../src/lib/LibRainDeploy.sol";
import {MockDeployable} from "./MockDeployable.sol";

/// @dev The address the candidate declares must already hold code, and which
/// holds none on any network.
address constant ABSENT_DEPENDENCY = address(0xdeadbee5);

/// @dev The code the candidate declares belongs at `ABSENT_DEPENDENCY`. Never
/// etched anywhere, but non-empty: a declaration carrying no code is a
/// declaration of something else.
bytes constant ABSENT_DEPENDENCY_RUNTIME_CODE = hex"fe";

/// @title MissingDependencyDeploy
/// @notice A deploy script whose candidate declares a dependency that is on no
/// network, so a broadcast that carries the declared list to
/// `deployToNetworks` refuses before it deploys anything and one that carries
/// an empty list deploys.
///
/// The suite is `MockDeployable`, which is on no supported network, so the
/// broadcast takes the deploying branch — the already-deployed branch skips the
/// dependency check by design and would say nothing about the list.
///
/// One network, so the refusal names a chain that is the whole target set
/// rather than the first of the default roster. Keyed
/// `second-address-candidate` for the reason `StalePinDeploy` gives.
contract MissingDependencyDeploy is RainDeployBroadcast {
    /// @inheritdoc RainDeployBroadcast
    function deployNetworks() internal pure override returns (string[] memory networks) {
        networks = new string[](1);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;
    }

    /// @inheritdoc RainDeploySuitesBase
    function releasedSuites() internal pure override returns (DeploySuite[] memory suites) {
        suites = new DeploySuite[](0);
    }

    /// @inheritdoc RainDeploySuitesBase
    function candidateSuites() internal pure override returns (DeployCandidate[] memory candidates) {
        DeployDependency[] memory dependencies = new DeployDependency[](1);
        dependencies[0] =
            DeployDependency({deployedAddress: ABSENT_DEPENDENCY, runtimeCode: ABSENT_DEPENDENCY_RUNTIME_CODE});

        candidates = new DeployCandidate[](1);
        candidates[0] = DeployCandidate({
            snapshot: DeploySuite({
                suite: "second-address-candidate",
                creationCode: type(MockDeployable).creationCode,
                storedDeployedAddress: LibRainDeploy.zoltuAddress(type(MockDeployable).creationCode),
                storedBytecodeHash: keccak256(type(MockDeployable).runtimeCode),
                storedRuntimeCode: type(MockDeployable).runtimeCode,
                artifactPath: "test/concrete/MockDeployable.sol:MockDeployable",
                dependencies: dependencies
            })
        });
    }
}
