// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {RainDeployBroadcast} from "../../src/abstract/RainDeployBroadcast.sol";
import {DeployCandidate, DeploySuite, RainDeploySuitesBase} from "../../src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeploy} from "../../src/lib/LibRainDeploy.sol";
import {MockDeployableV2} from "./MockDeployableV2.sol";

/// @dev The code hash the candidate records, which the code it deploys does not
/// produce.
bytes32 constant STALE_CODE_HASH = bytes32(uint256(0xdead));

/// @title StaleCodeHashDeploy
/// @notice A deploy script whose candidate records a code hash that is neither
/// the hash of the runtime code it records nor the hash of what it puts on
/// chain: the second half of a stale snapshot, where `StalePinDeploy` is the
/// first.
///
/// Its address pin is correct, so it gets PAST the pre-fork address comparison
/// and deploys, and the post-deploy code hash check is what refuses it. That is
/// the only guard that reads the recorded hash at all, so a broadcast that
/// recomputed the hash from its own recorded runtime code instead of carrying
/// the recorded one would compare a value against itself and let this through.
///
/// One network, so the refusal is reached on the only fork rather than partway
/// down the default roster. Keyed `second-address-candidate` for the reason
/// `StalePinDeploy` gives.
contract StaleCodeHashDeploy is RainDeployBroadcast {
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
        candidates = new DeployCandidate[](1);
        candidates[0] = DeployCandidate({
            snapshot: DeploySuite({
                suite: "second-address-candidate",
                creationCode: type(MockDeployableV2).creationCode,
                storedDeployedAddress: LibRainDeploy.zoltuAddress(type(MockDeployableV2).creationCode),
                storedBytecodeHash: STALE_CODE_HASH,
                storedRuntimeCode: type(MockDeployableV2).runtimeCode,
                artifactPath: "test/concrete/MockDeployableV2.sol:MockDeployableV2",
                dependencies: new address[](0)
            }),
            sourceCreationCode: type(MockDeployableV2).creationCode
        });
    }
}
