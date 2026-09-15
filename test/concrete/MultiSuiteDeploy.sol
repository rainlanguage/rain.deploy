// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {RainDeployBroadcast} from "../../src/abstract/RainDeployBroadcast.sol";
import {DeployCandidate, DeploySuite, RainDeploySuitesBase} from "../../src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeploy} from "../../src/lib/LibRainDeploy.sol";
import {MockDeployable} from "./MockDeployable.sol";
import {MockDeployableV2} from "./MockDeployableV2.sol";

/// @title MultiSuiteDeploy
/// @notice A declaration carrying two deployable suites, where every other
/// fixture carries one.
///
/// One suite is what a dispatch broadcasts, and a declaration with a single
/// entry cannot tell that apart from a broadcast of everything declared: both
/// put the same one contract on chain. Here the entry `DEPLOYMENT_SUITE` does
/// NOT name is a second contract, at its own permanent `CREATE2` address, that
/// a run reaching it would deploy to every network the dispatch targets.
///
/// Both candidates are anchored to their own source and record pins their own
/// creation code derives, so nothing about either is stale: the difference a
/// run can show is which of them it deployed, and nothing else.
///
/// One network, and the selected suite is keyed `second-address-candidate` for
/// the reason `StalePinDeploy` gives.
contract MultiSuiteDeploy is RainDeployBroadcast {
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
        candidates = new DeployCandidate[](2);
        candidates[0] = DeployCandidate({
            snapshot: DeploySuite({
                suite: "second-address-candidate",
                creationCode: type(MockDeployableV2).creationCode,
                storedDeployedAddress: LibRainDeploy.zoltuAddress(type(MockDeployableV2).creationCode),
                storedBytecodeHash: keccak256(type(MockDeployableV2).runtimeCode),
                storedRuntimeCode: type(MockDeployableV2).runtimeCode,
                artifactPath: "test/concrete/MockDeployableV2.sol:MockDeployableV2",
                dependencies: new address[](0)
            }),
            sourceCreationCode: type(MockDeployableV2).creationCode
        });
        candidates[1] = DeployCandidate({
            snapshot: DeploySuite({
                suite: "unselected-candidate",
                creationCode: type(MockDeployable).creationCode,
                storedDeployedAddress: LibRainDeploy.zoltuAddress(type(MockDeployable).creationCode),
                storedBytecodeHash: keccak256(type(MockDeployable).runtimeCode),
                storedRuntimeCode: type(MockDeployable).runtimeCode,
                artifactPath: "test/concrete/MockDeployable.sol:MockDeployable",
                dependencies: new address[](0)
            }),
            sourceCreationCode: type(MockDeployable).creationCode
        });
    }
}
