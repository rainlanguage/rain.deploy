// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DeployCandidate, DeploySuite, RainDeploySuitesBase} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {RainDeployVerifyChain} from "../../../src/abstract/RainDeployVerifyChain.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {MockDeployableV2} from "../../concrete/MockDeployableV2.sol";

/// @title RainDeployVerifyChainEmptyTest
/// @notice A repo that has released nothing: the matrix has no subject, and
/// MUST reach no network at all.
///
/// Forking seven endpoints to check nothing turns an outage into the failure of
/// an assertion with no subject, which is the one failure the chain group is
/// supposed to stay legible against. The pass is identical either way — a
/// matrix that forked all seven and found nothing to check on each of them
/// passes too — so the ABSENCE of a fork is the only thing that separates them
/// and it is what is asserted here.
///
/// The empty set is DECLARED here rather than read off a repo that happens not
/// to have released yet. A deploy repo's own declaration is empty exactly once,
/// before its first release, and a test resting on that is a test that stops
/// asserting anything the day the repo does the thing it exists to do. Declared,
/// the subject is empty for as long as this contract exists.
///
/// Its own contract for the reason `RainDeployVerifyChainCandidateTest` is its
/// own contract: the suites a contract inherits are the whole of what the
/// matrix runs over, and a contract has exactly one declaration, so a second
/// scope is a second contract. `RainDeployVerifyChainTest` cannot be it — it
/// declares two released suites so that the matrix has something to fail on.
contract RainDeployVerifyChainEmptyTest is RainDeployVerifyChain {
    /// @inheritdoc RainDeploySuitesBase
    /// @dev Nothing released. This is the whole fixture.
    function releasedSuites() internal pure override returns (DeploySuite[] memory) {
        return new DeploySuite[](0);
    }

    /// @inheritdoc RainDeploySuitesBase
    /// @dev A candidate, because a repo always compiles a current source and an
    /// empty candidate list is a declaration `RainDeploySuitesBase` refuses. The
    /// chain group never reads it — that scoping is
    /// `RainDeployVerifyChainCandidateTest`'s subject — so what it is does not
    /// matter here, only that this contract is a declaration a repo could
    /// actually have.
    function candidateSuites() internal pure override returns (DeployCandidate[] memory candidates) {
        candidates = new DeployCandidate[](1);
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
    }

    /// Nothing to check MUST NOT touch an RPC endpoint.
    ///
    /// `vm.activeFork()` reverts when nothing is selected, so the low-level call
    /// failing IS "no network was reached".
    ///
    /// It runs the whole inherited entry point rather than handing the matrix an
    /// empty array, so the derivation is inside what is asserted: a fork opened
    /// while deriving would touch the same seven endpoints for the same nothing.
    ///
    /// The empty released set is asserted rather than assumed, so an edit that
    /// gives this contract a subject fails naming the declaration it changed
    /// instead of reporting that a matrix with nothing to check forked — which
    /// would by then be describing a matrix that had something to check.
    function testChainWithNothingToCheckForksNothing() external {
        assertEq(releasedSuites().length, 0, "this fixture declares a release, so the matrix has a subject");

        (bool activeBefore,) = address(vm).call(abi.encodeWithSignature("activeFork()"));
        assertFalse(activeBefore, "a fork was selected before the call");

        this.testSuitesLiveOnEverySupportedNetwork();

        (bool activeAfter,) = address(vm).call(abi.encodeWithSignature("activeFork()"));
        assertFalse(activeAfter, "the matrix forked a network with nothing to check");
    }
}
