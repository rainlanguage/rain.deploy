// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {RainDeployBroadcast} from "../../src/abstract/RainDeployBroadcast.sol";
import {DeployCandidate, DeploySuite, RainDeploySuitesBase} from "../../src/abstract/RainDeploySuitesBase.sol";
import {MockDeployableV2} from "./MockDeployableV2.sol";

/// @dev The address the candidate records, which its own creation code does not
/// derive.
address constant STALE_PIN_ADDRESS = address(0xdead);

/// @title StalePinDeploy
/// @notice A deploy script whose candidate records an address its creation code
/// does not derive: the snapshot whose pins went stale while its recorded bytes
/// stayed current.
///
/// The source anchor has nothing to say about it — the recorded creation code IS
/// the source — so this reaches `deployAndBroadcast` carrying a pin that
/// describes nothing, which is the state the pre-fork address comparison exists
/// for.
///
/// Keyed `second-address-candidate` so it answers to the `DEPLOYMENT_SUITE` the
/// broadcast test has already set: that variable is process-wide and forge runs
/// tests concurrently, so every write to it stays inside the one test that owns
/// it.
contract StalePinDeploy is RainDeployBroadcast {
    /// @inheritdoc RainDeploySuitesBase
    function releasedSuites() internal pure override returns (DeploySuite[] memory suites) {
        suites = new DeploySuite[](0);
    }

    /// @inheritdoc RainDeploySuitesBase
    function candidateSuites() internal pure override returns (DeployCandidate[] memory candidates) {
        candidates = new DeployCandidate[](1);
        candidates[0] = DeployCandidate({
            snapshot: DeploySuite({
                suite: "second-address-candidate",
                creationCode: type(MockDeployableV2).creationCode,
                storedDeployedAddress: STALE_PIN_ADDRESS,
                storedBytecodeHash: keccak256(type(MockDeployableV2).runtimeCode),
                storedRuntimeCode: type(MockDeployableV2).runtimeCode,
                artifactPath: "test/concrete/MockDeployableV2.sol:MockDeployableV2",
                dependencies: new address[](0)
            }),
            sourceCreationCode: type(MockDeployableV2).creationCode
        });
    }
}
