// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {DeployCandidate, DeploySuite, RainDeploySuitesBase} from "../../src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeploy} from "../../src/lib/LibRainDeploy.sol";
import {MockDeployableV2} from "../concrete/MockDeployableV2.sol";

/// @title MisanchoredDeploySuites
/// @notice A declaration that says it deploys one contract and records another,
/// with NOTHING in the declaration to say so.
///
/// The single candidate names `MockDeployable` as the contract it is a snapshot
/// of — that is what `artifactPath` is, the `<path>:<Name>` the explorer
/// verification command is run with — and every recorded field is
/// `MockDeployableV2`'s. The snapshot is perfectly consistent with itself: the
/// address is the one its recorded creation code derives, the code hash is the
/// one that creation code produces, and the runtime code hashes to it. So every
/// check internal to a snapshot passes, and the only claim left to check is the
/// one the anchor makes: that the record is what the named contract COMPILES TO.
///
/// This is the declaration the source anchor has to be able to refuse without
/// being handed the source by the thing it is checking, and it is the
/// regression fixture for rainlanguage/rain.factory.deploy#34. While
/// `DeployCandidate` carried a `sourceCreationCode` field, this declaration
/// pointed it at its own recorded bytes and passed: the anchor compared a value
/// with itself, so it was satisfied by construction for any candidate at all,
/// and the whole suite — and the broadcast — went green over it. There is no
/// longer a field with which to spell that, which is the only reason this
/// fixture cannot spell it.
///
/// ONE candidate, and no releases. The loop-reaches-every-candidate property is
/// `SourceMismatchDeploySuites`' subject and is pinned there, behind a
/// genuinely anchored first entry; this fixture is about where the anchor's
/// SOURCE operand comes from, which a lone candidate says with nothing else in
/// the way — there is no earlier entry for a short loop to have stopped at and
/// no other suite for a refusal to have been about. The key is its own, shared
/// with no other fixture, because `DEPLOYMENT_SUITE` is a process-wide variable
/// other tests write.
abstract contract MisanchoredDeploySuites is RainDeploySuitesBase {
    /// @inheritdoc RainDeploySuitesBase
    function releasedSuites() internal pure override returns (DeploySuite[] memory suites) {
        suites = new DeploySuite[](0);
    }

    /// @inheritdoc RainDeploySuitesBase
    function candidateSuites() internal pure override returns (DeployCandidate[] memory candidates) {
        candidates = new DeployCandidate[](1);
        candidates[0] = DeployCandidate({
            snapshot: DeploySuite({
                suite: "misanchored-candidate",
                creationCode: type(MockDeployableV2).creationCode,
                storedDeployedAddress: LibRainDeploy.zoltuAddress(type(MockDeployableV2).creationCode),
                storedBytecodeHash: keccak256(type(MockDeployableV2).runtimeCode),
                storedRuntimeCode: type(MockDeployableV2).runtimeCode,
                // NOT `MockDeployableV2`. The candidate claims to be a snapshot
                // of `MockDeployable`, and records the other contract.
                artifactPath: "test/concrete/MockDeployable.sol:MockDeployable",
                dependencies: new address[](0)
            })
        });
    }
}
