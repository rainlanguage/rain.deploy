// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {ZoltuDerivationMismatch} from "../../../src/abstract/RainDeployVerifyBase.sol";
import {DeployCandidate, DeploySuite, RainDeploySuitesBase} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {RainDeployVerifySnapshotBase} from "../../../src/abstract/RainDeployVerifySnapshotBase.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {MockDeployable} from "../../concrete/MockDeployable.sol";

/// @title RainDeployVerifySnapshotBaseCandidateTest
/// @notice A repo before its first release: the internal-consistency subject is
/// the CANDIDATE alone, and the candidate MUST still be checked.
///
/// Its own contract because the suites a contract inherits are the whole of
/// what the inherited tests run over, and a contract has exactly one
/// declaration. `RainDeployVerifySnapshotBaseTest` cannot be this scope:
/// every candidate it declares records the creation code a release beside it
/// also records — which is the ordinary state of a repo between a release and
/// the next source change, and is why that fixture is shaped that way — so
/// breaking a candidate's derivation there breaks the release ahead of it and
/// the failure names the release either way. Here no release carries the
/// candidate's creation code, because there is no release at all.
///
/// What that separates: a check that ran over the releases alone rather than
/// over every declared suite. The candidate is the snapshot a broadcast
/// deploys and the only one a repo regenerates, so it is the entry whose
/// consistency has to hold soonest, and a check quietly scoped to the releases
/// is green on exactly the file that is about to reach a chain — permanently
/// green in a repo that has released nothing.
contract RainDeployVerifySnapshotBaseCandidateTest is RainDeployVerifySnapshotBase {
    /// @inheritdoc RainDeploySuitesBase
    /// @dev Nothing released. This is the whole fixture.
    function releasedSuites() internal pure override returns (DeploySuite[] memory) {
        return new DeploySuite[](0);
    }

    /// @inheritdoc RainDeploySuitesBase
    /// @dev One candidate, consistent and anchored to its own source, so the
    /// inherited tests are the passing case here exactly as they are in a
    /// consumer.
    function candidateSuites() internal pure override returns (DeployCandidate[] memory candidates) {
        candidates = new DeployCandidate[](1);
        candidates[0] = DeployCandidate({
            snapshot: DeploySuite({
                suite: "mock-deployable-candidate",
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

    /// A candidate that no release stands in front of MUST still be checked for
    /// internal consistency.
    ///
    /// The whole inherited entry point rather than `checkInternallyConsistent`
    /// with a suite handed to it, because what is asserted is the SUBJECT the
    /// test takes rather than what the check does once it has one.
    ///
    /// Broken through the factory rather than by editing a field, because this
    /// contract's declaration is the passing case for its own inherited tests
    /// and so cannot be broken in place. The factory answers with an address
    /// that has code but is not the one the creation code derives, which is the
    /// same forcing `RainDeployVerifySnapshotBaseTest` uses.
    ///
    /// The empty released set is asserted rather than assumed: an edit that
    /// gives this contract a release fails naming the declaration it changed,
    /// instead of passing because the release happened to fail first.
    function testSnapshotInternallyConsistentReachesACandidateNoReleaseCarries() external {
        assertEq(releasedSuites().length, 0, "this fixture declares a release, so a candidate is not the subject");

        vm.mockCall(
            LibRainDeploy.ZOLTU_FACTORY,
            type(MockDeployable).creationCode,
            abi.encodePacked(bytes20(LibRainDeploy.ZOLTU_FACTORY))
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                ZoltuDerivationMismatch.selector,
                "mock-deployable-candidate",
                LibRainDeploy.zoltuAddress(type(MockDeployable).creationCode),
                LibRainDeploy.ZOLTU_FACTORY
            )
        );
        this.testSnapshotInternallyConsistent();
    }
}
