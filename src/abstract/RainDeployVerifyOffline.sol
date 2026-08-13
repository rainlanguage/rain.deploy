// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {DerivedDeploy, RainDeployVerifyBase} from "./RainDeployVerifyBase.sol";
import {DeployCandidate, DeploySuite} from "./RainDeploySuitesBase.sol";

/// Thrown when the deploy address recorded for a version is not the address its
/// own creation code derives.
/// @param suite The suite that failed.
/// @param storedAddress The address the suite records.
/// @param derivedAddress The address its creation code derives.
error StoredAddressMismatch(string suite, address storedAddress, address derivedAddress);

/// Thrown when the deployed code hash recorded for a version is not the hash
/// its own creation code produces.
/// @param suite The suite that failed.
/// @param storedCodeHash The code hash the suite records.
/// @param derivedCodeHash The code hash its creation code produces.
error StoredCodeHashMismatch(string suite, bytes32 storedCodeHash, bytes32 derivedCodeHash);

/// Thrown when the runtime code recorded for a version does not hash to the
/// code hash recorded beside it.
/// @param suite The suite that failed.
/// @param storedBytecodeHash The code hash the suite records.
/// @param runtimeCodeHash The hash of the runtime code the suite records.
error StoredRuntimeCodeHashMismatch(string suite, bytes32 storedBytecodeHash, bytes32 runtimeCodeHash);

/// Thrown when the candidate's recorded creation code is not the creation code
/// this repo currently compiles. Hashes rather than the bytes themselves, which
/// run to tens of kilobytes.
/// @param suite The candidate's key.
/// @param storedCreationCodeHash Hash of the creation code the candidate
/// records.
/// @param sourceCreationCodeHash Hash of `type(X).creationCode` for the
/// contract the candidate claims to be.
error CandidateSourceMismatch(string suite, bytes32 storedCreationCodeHash, bytes32 sourceCreationCodeHash);

/// @title RainDeployVerifyOffline
/// @notice Every deploy-pin assertion that needs no network, for every suite
/// a repo declares. Two groups, which catch different things and are documented
/// as such because it is easy to read the first as covering the second.
///
/// **Internal to the recorded set.** The address a suite's creation code
/// derives is the address it records, the code hash that creation code produces
/// is the code hash it records, and the runtime code it records hashes to that
/// same code hash. These are real derivations and they catch a set generated
/// inconsistently — a hand-edited constant, a snapshot regenerated for one
/// field and not the others, an address copied from the wrong tag.
///
/// They CANNOT catch a snapshot of the wrong contract. A consistent snapshot of
/// the wrong thing satisfies all three, because all three only ask the recorded
/// bytes to agree with each other, and the wrong contract's bytes agree with
/// each other perfectly.
///
/// **Anchored to source.** The candidate's recorded creation code is the
/// creation code this repo compiles. This is the only check in the whole suite
/// that catches a snapshot of the wrong contract, and it applies to the
/// candidate alone: a released tag is meant to have diverged from current
/// source, so anchoring one to source asserts something that is false by
/// design.
///
/// Neither group can catch a suite that was never deployed, or that is no
/// longer deployed. Only `RainDeployVerifyChain` can, and nothing here is a
/// substitute for it.
abstract contract RainDeployVerifyOffline is RainDeployVerifyBase {
    /// Checks one suite against itself: derive from its creation code, then
    /// require everything it records to agree with the derivation.
    /// @param suite The suite to check.
    function checkInternallyConsistent(DeploySuite memory suite) internal {
        DerivedDeploy memory derived = deriveDeployment(suite);

        if (suite.storedDeployedAddress != derived.deployedAddress) {
            revert StoredAddressMismatch(suite.suite, suite.storedDeployedAddress, derived.deployedAddress);
        }

        if (suite.storedBytecodeHash != derived.bytecodeHash) {
            revert StoredCodeHashMismatch(suite.suite, suite.storedBytecodeHash, derived.bytecodeHash);
        }

        bytes32 runtimeCodeHash = keccak256(suite.storedRuntimeCode);
        if (suite.storedBytecodeHash != runtimeCodeHash) {
            revert StoredRuntimeCodeHashMismatch(suite.suite, suite.storedBytecodeHash, runtimeCodeHash);
        }
    }

    /// Checks the candidate against the source this repo compiles.
    /// @param candidate The candidate to check.
    function checkAnchoredToSource(DeployCandidate memory candidate) internal pure {
        if (keccak256(candidate.snapshot.creationCode) != keccak256(candidate.sourceCreationCode)) {
            revert CandidateSourceMismatch(
                candidate.snapshot.suite,
                keccak256(candidate.snapshot.creationCode),
                keccak256(candidate.sourceCreationCode)
            );
        }
    }

    /// Every declared suite MUST be internally consistent: what it records is
    /// what its own creation code derives.
    function testDeployPinsInternallyConsistent() external {
        DeploySuite[] memory suites = allSuites();
        for (uint256 i = 0; i < suites.length; i++) {
            checkInternallyConsistent(suites[i]);
        }
    }

    /// The candidate MUST be a snapshot of the contract this repo compiles, not
    /// of some other contract that happens to be internally consistent.
    function testDeployPinsCandidateAnchoredToSource() external pure {
        checkAnchoredToSource(candidateSuite());
    }
}
