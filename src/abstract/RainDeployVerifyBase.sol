// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";

import {DeploySuite, RainDeploySuitesBase} from "./RainDeploySuitesBase.sol";
import {LibRainDeploy} from "../lib/LibRainDeploy.sol";

/// Thrown when the pure `LibRainDeploy.zoltuAddress` formula and an actual
/// deploy through the etched Zoltu factory bytecode disagree about where a
/// creation code lands. Both are `LibRainDeploy`'s, so this is a defect in the
/// library rather than in any snapshot, and it invalidates every derivation
/// made from it.
/// @param suite The suite whose creation code was being derived.
/// @param formulaAddress The address `zoltuAddress` computed.
/// @param factoryAddress The address the factory bytecode actually deployed to.
error ZoltuDerivationMismatch(string suite, address formulaAddress, address factoryAddress);

/// Thrown when the state snapshot taken around a derivation could not be
/// reverted. The derivation plants code at the derived address and clears its
/// nonce; if that cannot be undone, every later derivation reads state this one
/// created, and the chain-anchored checks compare a locally planted deployment
/// against itself. There is no safe way to continue.
/// @param suite The suite being derived when the revert failed.
/// @param snapshotId The snapshot that could not be reverted.
error DerivationSnapshotRevertFailed(string suite, uint256 snapshotId);

/// What a suite's creation code derives, by itself. Computed
/// once and then compared against whatever claims to hold it, whether that is a
/// recorded constant or a live chain.
struct DerivedDeploy {
    /// The suite the derivation came from.
    string suite;
    /// The address the creation code deploys to, on every network.
    address deployedAddress;
    /// The code hash the creation code leaves behind at that address.
    bytes32 bytecodeHash;
}

/// @title RainDeployVerifyBase
/// @notice The derivation every deploy-verification group shares: from a
/// suite's creation code to the (address, code hash) it produces, in one place
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
    /// Derives what a suite's creation code deploys to, from the creation
    /// code alone.
    ///
    /// The address comes from the pure `LibRainDeploy.zoltuAddress` formula and
    /// the code hash from actually running the creation code through the Zoltu
    /// factory bytecode locally, because the code hash cannot be known without
    /// executing the constructor. The two are cross-checked against each other,
    /// so a formula that drifted from the factory bytecode is caught here
    /// rather than silently poisoning every downstream comparison.
    ///
    /// The whole derivation runs inside a state snapshot that is reverted, and
    /// clears the derived address first, so that it reads ONLY what the
    /// creation code produces. Both matter:
    ///
    /// - Two suites can legitimately share creation code (a release that
    ///   changed nothing that compiles), and `CREATE2` to an occupied address
    ///   fails. Clearing makes the second derivation work, and reverting means
    ///   the first never occupied it in the first place.
    /// - The local deploy must not survive into the chain-anchored checks. A
    ///   locally deployed contract that leaked into a fork would be compared
    ///   against itself, and every chain would pass whether or not anything is
    ///   deployed there.
    /// @param suite The suite to derive from.
    /// @return The address and code hash the creation code produces.
    function deriveDeployment(DeploySuite memory suite) internal returns (DerivedDeploy memory) {
        address formulaAddress = LibRainDeploy.zoltuAddress(suite.creationCode);

        uint256 snapshotId = vm.snapshotState();

        // Whatever is at the derived address is not part of the derivation.
        // The nonce goes too: `CREATE2` collides on a non-zero nonce as well as
        // on non-empty code.
        vm.etch(formulaAddress, hex"");
        vm.resetNonce(formulaAddress);

        LibRainDeploy.etchZoltuFactory(vm);
        address factoryAddress = LibRainDeploy.deployZoltu(suite.creationCode);
        if (factoryAddress != formulaAddress) {
            revert ZoltuDerivationMismatch(suite.suite, formulaAddress, factoryAddress);
        }

        DerivedDeploy memory derived =
            DerivedDeploy({suite: suite.suite, deployedAddress: formulaAddress, bytecodeHash: factoryAddress.codehash});

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
