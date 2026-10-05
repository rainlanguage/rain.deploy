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

/// @dev The code the candidate declares belongs at the Zoltu factory, which is
/// not the code that is there. Non-empty and nothing like the factory's own, so
/// the refusal can only be the comparison against the DECLARED bytes.
bytes constant MISDECLARED_DEPENDENCY_RUNTIME_CODE = hex"fd";

/// @title ChangedDependencyDeploy
/// @notice A deploy script whose candidate declares the right dependency
/// ADDRESS and the wrong dependency CODE, so a broadcast that carries the
/// declared pair to `deployToNetworks` refuses and one that carries only the
/// addresses deploys.
///
/// `MissingDependencyDeploy` cannot say this. Its dependency is on no network,
/// so a `run()` that dropped the runtime code entirely still refuses it on
/// presence alone — which is exactly what `run()` used to do, projecting the
/// list down to an `address[]` before anything could read the other half.
///
/// The dependency is the Zoltu factory because it is the one address this repo
/// knows is live on every supported network: a refusal here cannot be a chain
/// that lacks the dependency. The factory's own presence-and-codehash check
/// runs first, against the library's constant, and passes — so what fails is
/// the declaration.
///
/// The suite is `MockDeployable`, which is on no supported network, so the
/// broadcast takes the deploying branch; the already-deployed branch skips the
/// dependency check by design and would say nothing about the list.
///
/// One network, so the refusal names a chain that is the whole target set
/// rather than the first of the default roster. Keyed
/// `second-address-candidate` for the reason `StalePinDeploy` gives.
contract ChangedDependencyDeploy is RainDeployBroadcast {
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
        dependencies[0] = DeployDependency({
            deployedAddress: LibRainDeploy.ZOLTU_FACTORY, runtimeCode: MISDECLARED_DEPENDENCY_RUNTIME_CODE
        });

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
