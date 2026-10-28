// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";

import {
    DeploySuite,
    DerivationSnapshotRevertFailed,
    RainDeploySuitesBase,
    ZoltuDerivationMismatch
} from "./RainDeploySuitesBase.sol";

/// What a suite derives, by itself, through its own mechanism.
struct DerivedDeploy {
    /// The suite the derivation came from.
    string suite;
    /// The address the suite's mechanism deploys it to on each of its `networks`, in order.
    address[] deployedAddresses;
    /// The code hash the mechanism leaves behind at those addresses.
    bytes32 bytecodeHash;
}


/// @title RainDeployVerifyBase
/// @notice The derivation every deploy-verification group shares.
abstract contract RainDeployVerifyBase is RainDeploySuitesBase, Test {
    /// Derives where a suite's mechanism puts it and the code hash it leaves there, from the suite
    /// alone.
    /// @param suite The suite to derive from.
    /// @return The addresses and code hash the suite's mechanism produces.
    function deriveDeployment(DeploySuite memory suite) internal returns (DerivedDeploy memory) {
        uint256 snapshotId = vm.snapshotState();

        address[] memory deployedAddresses = deployLocally(vm, suite);
        DerivedDeploy memory derived = DerivedDeploy({
            suite: suite.suite,
            deployedAddresses: deployedAddresses,
            bytecodeHash: deployedAddresses[0].codehash
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
