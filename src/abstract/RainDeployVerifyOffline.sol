// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {DeployCandidate, DeployVersion, DerivedDeploy, RainDeployVerifyBase} from "./RainDeployVerifyBase.sol";

/// Thrown when the deploy address recorded for a version is not the address its
/// own creation code derives.
/// @param version The version label that failed.
/// @param storedAddress The address the version records.
/// @param derivedAddress The address its creation code derives.
error StoredAddressMismatch(string version, address storedAddress, address derivedAddress);

/// Thrown when the deployed code hash recorded for a version is not the hash
/// its own creation code produces.
/// @param version The version label that failed.
/// @param storedCodeHash The code hash the version records.
/// @param derivedCodeHash The code hash its creation code produces.
error StoredCodeHashMismatch(string version, bytes32 storedCodeHash, bytes32 derivedCodeHash);

/// Thrown when the runtime code recorded for a version does not hash to the
/// code hash recorded beside it.
/// @param version The version label that failed.
/// @param storedBytecodeHash The code hash the version records.
/// @param runtimeCodeHash The hash of the runtime code the version records.
error StoredRuntimeCodeHashMismatch(string version, bytes32 storedBytecodeHash, bytes32 runtimeCodeHash);

/// Thrown when the candidate's recorded creation code is not the creation code
/// this repo currently compiles. Hashes rather than the bytes themselves, which
/// run to tens of kilobytes.
/// @param version The candidate's version label.
/// @param storedCreationCodeHash Hash of the creation code the candidate
/// records.
/// @param sourceCreationCodeHash Hash of `type(X).creationCode` for the
/// contract the candidate claims to be.
error CandidateSourceMismatch(string version, bytes32 storedCreationCodeHash, bytes32 sourceCreationCodeHash);

/// @title RainDeployVerifyOffline
/// @notice Every deploy-pin assertion that needs no network, for every version
/// a repo records. Two groups, which catch different things and are documented
/// as such because it is easy to read the first as covering the second.
///
/// **Internal to the recorded set.** The address a version's creation code
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
/// Neither group can catch a version that was never deployed, or that is no
/// longer deployed. Only `RainDeployVerifyChain` can, and nothing here is a
/// substitute for it.
abstract contract RainDeployVerifyOffline is RainDeployVerifyBase {
    /// Checks one version against itself: derive from its creation code, then
    /// require everything it records to agree with the derivation.
    /// @param version The version to check.
    function checkInternallyConsistent(DeployVersion memory version) internal {
        DerivedDeploy memory derived = deriveDeployment(version);

        if (version.storedDeployedAddress != derived.deployedAddress) {
            revert StoredAddressMismatch(version.version, version.storedDeployedAddress, derived.deployedAddress);
        }

        if (version.storedBytecodeHash != derived.bytecodeHash) {
            revert StoredCodeHashMismatch(version.version, version.storedBytecodeHash, derived.bytecodeHash);
        }

        bytes32 runtimeCodeHash = keccak256(version.storedRuntimeCode);
        if (version.storedBytecodeHash != runtimeCodeHash) {
            revert StoredRuntimeCodeHashMismatch(version.version, version.storedBytecodeHash, runtimeCodeHash);
        }
    }

    /// Checks the candidate against the source this repo compiles.
    /// @param candidate The candidate to check.
    function checkAnchoredToSource(DeployCandidate memory candidate) internal pure {
        if (keccak256(candidate.snapshot.creationCode) != keccak256(candidate.sourceCreationCode)) {
            revert CandidateSourceMismatch(
                candidate.snapshot.version,
                keccak256(candidate.snapshot.creationCode),
                keccak256(candidate.sourceCreationCode)
            );
        }
    }

    /// Every recorded version MUST be internally consistent: what it records is
    /// what its own creation code derives.
    function testDeployPinsInternallyConsistent() external {
        DeployVersion[] memory versions = allVersions();
        for (uint256 i = 0; i < versions.length; i++) {
            checkInternallyConsistent(versions[i]);
        }
    }

    /// The candidate MUST be a snapshot of the contract this repo compiles, not
    /// of some other contract that happens to be internally consistent.
    function testDeployPinsCandidateAnchoredToSource() external pure {
        checkAnchoredToSource(candidateVersion());
    }
}
