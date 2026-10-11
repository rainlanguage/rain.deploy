// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";

import {DeploySuite, RainDeploySuitesBase} from "./RainDeploySuitesBase.sol";
// `ZoltuDerivationMismatch` is declared beside the derivation that raises it
// and imported here so it stays importable from this path.
import {LibRainDeployMechanism, ZoltuDerivationMismatch} from "../lib/LibRainDeployMechanism.sol";

/// Thrown when the state snapshot taken around a derivation could not be
/// reverted. The derivation plants code at the derived address, clears its
/// nonce and etches the suite's declared dependencies; if that cannot be
/// undone, every later derivation reads state this one created, and the
/// chain-anchored checks compare a locally planted deployment against itself.
/// There is no safe way to continue.
/// @param suite The suite being derived when the revert failed.
/// @param snapshotId The snapshot that could not be reverted.
error DerivationSnapshotRevertFailed(string suite, uint256 snapshotId);

/// What a suite derives, by itself, through its own mechanism. Computed once
/// and then compared against whatever claims to hold it, whether that is a
/// recorded constant or a live chain.
struct DerivedDeploy {
    /// The suite the derivation came from.
    string suite;
    /// The address the suite's mechanism deploys it to, on every network.
    address deployedAddress;
    /// The code hash the mechanism leaves behind at that address.
    bytes32 bytecodeHash;
}

/// @title RainDeployVerifyBase
/// @notice The derivation every deploy-verification group shares: from a
/// suite to the (address, code hash) its mechanism produces, in one place
/// rather than restated per suite and per chain.
///
/// The suites themselves come from `RainDeploySuitesBase`, which is the SAME
/// declaration `RainDeployBroadcast` deploys from. Verification and deployment
/// therefore cannot describe different things.
///
/// This is not inherited directly. `RainDeployVerifySnapshot` and
/// `RainDeployVerifyChain` each inherit it and contribute the checks that need
/// no network and the checks that do, respectively. A repo inherits its
/// declaration into one of each, so running the snapshot checks never touches
/// an RPC endpoint — an outage is then a failure of one contract that plainly is
/// about the chain, and can never be confused with, or take down, the
/// snapshot assertions.
///
/// ## Chain-independent runtime code is a requirement, not a caveat
///
/// A single `storedBytecodeHash` per suite can only be true if the runtime
/// code is the same on every network. A constructor that reads `block.chainid`,
/// or anything else that varies per chain, produces a different code hash per
/// chain and cannot be described by these snapshots at all. Deploying through
/// Zoltu buys address predictability; a constructor that reads chain state
/// spends it. So a per-chain code hash difference is a DEFECT in the contract,
/// reported as a hard failure naming the chain and both hashes, and there is
/// deliberately no per-chain code hash to record.
abstract contract RainDeployVerifyBase is RainDeploySuitesBase, Test {
    /// Derives where a suite's mechanism puts it and the code hash it leaves
    /// there, from the suite alone.
    ///
    /// `LibRainDeployMechanism.deployLocally` runs the suite's OWN mechanism —
    /// the same dispatch the broadcast makes — and cross-checks where it landed
    /// against the pure formula for that mechanism, so a formula that drifted
    /// from the code that deploys is caught here rather than silently poisoning
    /// every downstream comparison. The code hash is read from what it left,
    /// because it cannot be known without running it.
    ///
    /// The whole derivation runs inside a state snapshot that is reverted, and
    /// the mechanism clears the derived address first, so that it reads ONLY
    /// what the suite produces. Both matter:
    ///
    /// - Two suites can legitimately share creation code (a release that
    ///   changed nothing that compiles), and `CREATE2` to an occupied address
    ///   fails. Clearing makes the second derivation work, and reverting means
    ///   the first never occupied it in the first place.
    /// - The local deploy must not survive into the chain-anchored checks. A
    ///   locally deployed contract that leaked into a fork would be compared
    ///   against itself, and every chain would pass whether or not anything is
    ///   deployed there.
    ///
    /// ## The suite's declared dependencies, etched
    ///
    /// A constructor that reads a dependency cannot run on an EVM where nothing
    /// is deployed, and neither can a clone factory, which is the EVM a
    /// derivation happens on. So the declared dependencies are etched, from the
    /// runtime code the declaration carries, inside the same snapshot. Nothing
    /// resolves an address to an owning suite: a dependency need not be a suite
    /// of this repo at all.
    ///
    /// That makes the derived code hash a function of what the declaration SAYS
    /// is at each dependency, which is a claim about every network and not an
    /// input this contract can settle. `LibRainDeploy.deployStepToNetworks` is
    /// what settles it, hashing the live code at each address against the same
    /// declared bytes before it broadcasts, so a wrong declaration is a red
    /// deploy run rather than a wrong hash frozen into a release.
    /// @param suite The suite to derive from.
    /// @return The address and code hash the suite's mechanism produces.
    function deriveDeployment(DeploySuite memory suite) internal returns (DerivedDeploy memory) {
        uint256 snapshotId = vm.snapshotState();

        address deployedAddress = LibRainDeployMechanism.deployLocally(vm, suite);
        DerivedDeploy memory derived = DerivedDeploy({
            suite: suite.suite, deployedAddress: deployedAddress, bytecodeHash: deployedAddress.codehash
        });

        // A failed revert is unrecoverable, not a warning to silence. The etch
        // and the nonce reset would survive into every later derivation, whose
        // results would then look entirely plausible while describing state
        // this call planted.
        if (!vm.revertToState(snapshotId)) {
            revert DerivationSnapshotRevertFailed(suite.suite, snapshotId);
        }

        return derived;
    }

    /// Derives every suite once, before anything forks. Callers that compare
    /// against chains need the derivation to have already happened on a local
    /// EVM, because on a fork the derived address is exactly the address the
    /// deployment under test occupies.
    /// @param suites The suites to derive.
    /// @return The derivation of each, positionally paired.
    function deriveDeployments(DeploySuite[] memory suites) internal returns (DerivedDeploy[] memory) {
        DerivedDeploy[] memory derived = new DerivedDeploy[](suites.length);
        for (uint256 i = 0; i < suites.length; i++) {
            derived[i] = deriveDeployment(suites[i]);
        }
        return derived;
    }
}
