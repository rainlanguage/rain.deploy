// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {RainDeployVerifyChain} from "../../../src/abstract/RainDeployVerifyChain.sol";
import {RegistryDeploySuites} from "../../../src/abstract/RegistryDeploySuites.sol";

/// @title RegistryDeployChainTest
/// @notice Whether every registry this repo has RELEASED is actually live, with
/// the code that release froze, on every supported network.
///
/// It has released none. The chain group reads `releasedSuites()`, which is
/// empty until the first release is cut, so there is nothing here to check: this
/// forks nothing and passes. It gets a subject the moment a release is frozen
/// and declared, and from then on it is red until that release is live on every
/// supported network — which is why the deploy is dispatched before the tag is
/// pushed.
///
/// That eventual failure is the check working. "Nothing is deployed at the
/// address `LibAddressRegistry` reads" is true today, it is the single most
/// important fact about these pins, and no snapshot assertion can discover it —
/// a perfectly consistent set of pins for a contract that exists nowhere passes
/// every one of them.
///
/// It is a separate contract from `RegistryDeploySnapshotTest` precisely so that
/// it says this and nothing more: a missing deployment or an unreachable
/// endpoint fails here alone, leaving every snapshot assertion to answer for
/// itself.
contract RegistryDeployChainTest is RegistryDeploySuites, RainDeployVerifyChain {
    /// Nothing to check MUST NOT touch an RPC endpoint. This repo has released
    /// nothing, so this is the branch every CI run takes: forking five networks
    /// to check nothing turns an outage into the failure of an assertion with
    /// no subject, which is the one failure this contract exists to stay
    /// legible against.
    ///
    /// The ABSENCE of a fork is what is asserted, because the pass is identical
    /// either way — the matrix that forks all five and finds nothing to check on
    /// each of them passes too, and is the only thing this contract would have
    /// done differently. `vm.activeFork()` reverts when nothing is selected, so
    /// the low-level call failing IS "no network was reached".
    ///
    /// It runs the whole inherited entry point rather than handing the matrix an
    /// empty array, so the derivation is inside what is asserted: a fork opened
    /// while deriving would touch the same five endpoints for the same nothing.
    ///
    /// The empty released set is asserted rather than assumed, because it is the
    /// premise and not the property. The first release gives this contract a
    /// subject and the matrix will fork for it — correctly — so this fails at
    /// that release naming what actually changed, instead of reporting that a
    /// matrix with nothing to check forked, which would by then be false.
    function testChainWithNothingToCheckForksNothing() external {
        assertEq(releasedSuites().length, 0, "this repo has released something, so the matrix has a subject");

        (bool activeBefore,) = address(vm).call(abi.encodeWithSignature("activeFork()"));
        assertFalse(activeBefore, "a fork was selected before the call");

        this.testSuitesLiveOnEverySupportedNetwork();

        (bool activeAfter,) = address(vm).call(abi.encodeWithSignature("activeFork()"));
        assertFalse(activeAfter, "the matrix forked a network with nothing to check");
    }
}
