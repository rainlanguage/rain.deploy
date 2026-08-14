// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {DerivedDeploy, RainDeployVerifyBase} from "./RainDeployVerifyBase.sol";
import {LibRainDeploy} from "../lib/LibRainDeploy.sol";

/// Thrown when a version's derived address has no code on a network. Either it
/// never deployed there, or it is not there any more.
/// @param network The network name, as configured in `[rpc_endpoints]`.
/// @param suite The suite that is missing.
/// @param deployedAddress The address that should hold it.
error NotDeployedOnNetwork(string network, string suite, address deployedAddress);

/// Thrown when a version's derived address holds code that is not the code its
/// creation code produces.
///
/// This is also what a chain-dependent runtime code looks like: a constructor
/// that reads `block.chainid` or similar deploys different code per network,
/// so one network disagrees while others pass. That is a defect in the
/// contract, not a shortcoming of a single recorded hash — hence a hard failure
/// naming the chain and both hashes, rather than a per-chain hash to record.
/// @param network The network name, as configured in `[rpc_endpoints]`.
/// @param suite The suite that failed.
/// @param deployedAddress The address checked.
/// @param expectedCodeHash The code hash the version's creation code produces.
/// @param actualCodeHash The code hash actually found on this network.
error CodeHashMismatchOnNetwork(
    string network, string suite, address deployedAddress, bytes32 expectedCodeHash, bytes32 actualCodeHash
);

/// @title RainDeployVerifyChain
/// @notice The only deploy-pin assertions anchored to something outside the
/// repo: across every network in `LibRainDeploy.supportedNetworks()`, every
/// RELEASED suite's derived address carries code with its derived code hash.
///
/// This is the only group that can catch a suite that never deployed to a
/// network, or that is not there any more. Neither is a fact the repo can hold:
/// both can go false with nobody touching it — a release that reached four
/// chains of five, a chain added to `supportedNetworks()` after a release that
/// therefore never got it, a deploy that silently failed.
///
/// ## Released only, for the same reason source anchors the candidate only
///
/// A release IS a deployment that happened. That is what its recorded bytes
/// describe and why they are frozen, so "it is on every network" is a claim
/// about it that is either true or a defect. The candidate is what the NEXT
/// release will be: between releases it is ordinarily ahead of anything on
/// chain, and a repo whose source has moved since its last deploy is the
/// normal state of a repo, not a fault in it. Demanding the candidate be live
/// asserts something false by design.
///
/// The two exemptions are the same shape from opposite ends —
/// `RainDeployVerifySnapshot` anchors the candidate to source and never a
/// release, because a release is meant to have diverged from source; this
/// anchors releases to the chain and never the candidate, because the
/// candidate is meant to be ahead of the chain. Neither is a field a caller
/// can set: there is nothing to opt a suite into or out of.
///
/// That puts the whole weight on `releasedSuites()` naming every release. A
/// frozen tag missing from it would be a release nothing here is ever handed,
/// and a check that is never handed a subject cannot fail on it — so
/// `RainDeployVerifySnapshot` checks that declaration against the append-only
/// `src/generated/<tag>/` record. Without that, scoping to releases would be a
/// way to make this contract quiet rather than correct.
///
/// The matrix is suites by networks and is generated from both, so a new
/// network leaves no suite unchecked and a new release is checked on every
/// network from the moment it is declared. There are deliberately no per-chain
/// or per-suite functions to add.
///
/// It compares against the DERIVED code hash rather than the recorded one, so
/// the creation code stays the only parameter. `RainDeployVerifySnapshot` is
/// what ties the derivation back to the recorded constants; the two together
/// say the recorded set describes what is actually live.
///
/// Kept in its own contract, away from every assertion about the snapshot, so
/// an unreachable RPC endpoint fails only this. It cannot take down the
/// snapshot checks with it, and its failures are legible: a fork that cannot be created
/// is an outage, while `NotDeployedOnNetwork` from a fork that was created is a
/// missing deployment. A contract boundary is what `forge test
/// --match-contract` and a CI job select at, and it is structural rather than
/// conventional — nothing reachable from the snapshot contract forks anything.
abstract contract RainDeployVerifyChain is RainDeployVerifyBase {
    /// Checks one derived suite against whichever network is currently
    /// selected.
    /// @param network The network name, for the error only.
    /// @param derived The derivation to check for.
    function checkDeployedOnNetwork(string memory network, DerivedDeploy memory derived) internal view {
        if (derived.deployedAddress.code.length == 0) {
            revert NotDeployedOnNetwork(network, derived.suite, derived.deployedAddress);
        }
        bytes32 actualCodeHash = derived.deployedAddress.codehash;
        if (actualCodeHash != derived.bytecodeHash) {
            revert CodeHashMismatchOnNetwork(
                network, derived.suite, derived.deployedAddress, derived.bytecodeHash, actualCodeHash
            );
        }
    }

    /// Checks every derived suite against every supported network, forking
    /// each network once and checking every suite on it.
    ///
    /// The derivations are taken as an argument, already computed, because they
    /// have to be computed before anything forks: on a fork the derived address
    /// is the very address the deployment under test occupies, so deriving
    /// there would either collide with it or read it back as its own
    /// expectation.
    /// @param derived The derivation of every suite to check.
    function checkDeployedOnSupportedNetworks(DerivedDeploy[] memory derived) internal {
        // Nothing to check is not a reason to touch five RPC endpoints. Forking
        // to check nothing turns an outage into the failure of an assertion
        // that has no subject, which is the one failure this contract is
        // supposed to be legible against.
        if (derived.length == 0) {
            return;
        }

        string[] memory networks = LibRainDeploy.supportedNetworks();
        for (uint256 i = 0; i < networks.length; i++) {
            // createSelectFork returns a fork id that is not needed here; bind
            // and reference it so the unused-return lint stays satisfied.
            uint256 forkId = vm.createSelectFork(networks[i]);
            (forkId);
            for (uint256 j = 0; j < derived.length; j++) {
                checkDeployedOnNetwork(networks[i], derived[j]);
            }
        }
    }

    /// Every RELEASED suite MUST be live, with the code its creation code
    /// produces, on every supported network.
    function testSuitesLiveOnEverySupportedNetwork() external {
        checkDeployedOnSupportedNetworks(deriveDeployments(releasedSuites()));
    }
}
